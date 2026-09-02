import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sprite_atlas.dart';

/// Loads and caches the Journey sprite sheets and parallax layers.
///
/// Two rules keep this cheap:
///
///  * Nothing is decoded until something needs it. The parallax layers and the
///    two always-on pet cycles (walk, idle) load at startup; an activity clip
///    loads the first time that activity is triggered.
///  * Activity sheets are the large ones, so only [_activityBudget] of them
///    stay resident. The least recently used is disposed past that, which keeps
///    steady-state image memory around 50 MB instead of unbounded.
class SpriteLibrary {
  SpriteLibrary._();

  static final SpriteLibrary instance = SpriteLibrary._();

  static const _root = 'assets/journey/atlas';

  /// Cycles that are on screen almost all the time and are never evicted.
  static const _pinned = {'walk', 'idle'};

  /// How many activity sheets stay decoded. Activities are mutually exclusive
  /// and the sheets are the big ones, so one is enough: re-logging the same
  /// activity is still instant, and switching costs a decode the pet covers by
  /// walking. Raise this to trade memory for that decode.
  static const _activityBudget = 1;

  Map<String, dynamic>? _manifest;
  Future<void>? _manifestLoad;

  final Map<String, SpriteAtlas> _atlases = {};
  final Map<String, Future<SpriteAtlas?>> _inFlight = {};

  /// Activity atlas names, oldest use first.
  final List<String> _lru = [];

  final Map<String, ui.Image> parallax = {};

  /// Decodes straight from the asset bundle. [ui.ImmutableBuffer.fromAsset]
  /// hands the bytes to the engine without copying them through Dart, and the
  /// decode itself runs off the UI thread.
  static Future<ui.Image> _decode(String key) async {
    final buffer = await ui.ImmutableBuffer.fromAsset(key);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Future<void> _ensureManifest() {
    return _manifestLoad ??= () async {
      final raw = await rootBundle.loadString('$_root/manifest.json');
      _manifest = json.decode(raw) as Map<String, dynamic>;
    }();
  }

  /// Loads the parallax layers. These are small and are what the very first
  /// frame needs, so they are fetched before any pet sheet.
  Future<void> loadParallax() async {
    await _ensureManifest();
    final layers = (_manifest?['parallax'] as Map<String, dynamic>?) ?? const {};
    await Future.wait(layers.entries.map((e) async {
      // Already decoded from a previous visit to the tab. Re-decoding would
      // also orphan the existing ui.Image handle.
      if (parallax.containsKey(e.key)) return;
      final file = (e.value as Map<String, dynamic>)['file'] as String;
      try {
        parallax[e.key] = await _decode('$_root/$file');
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'journey',
          context: ErrorDescription('loading parallax layer ${e.key}'),
        ));
      }
    }));
  }

  /// Already-decoded atlas, or null. Safe to call from a painter.
  SpriteAtlas? peek(String name) {
    final atlas = _atlases[name];
    if (atlas != null && !_pinned.contains(name)) _touch(name);
    return atlas;
  }

  /// Decodes [name] if needed. Concurrent calls share one decode.
  Future<SpriteAtlas?> load(String name) {
    final cached = _atlases[name];
    if (cached != null) {
      if (!_pinned.contains(name)) _touch(name);
      return Future.value(cached);
    }
    return _inFlight[name] ??= _load(name).whenComplete(() {
      _inFlight.remove(name);
    });
  }

  Future<SpriteAtlas?> _load(String name) async {
    await _ensureManifest();
    final animations = _manifest?['animations'] as Map<String, dynamic>?;
    final spec = animations?[name] as Map<String, dynamic>?;
    if (spec == null) return null;
    try {
      final sheet = await _decode('$_root/${spec['sheet']}');
      final atlas = SpriteAtlas.fromManifest(spec, sheet);
      _atlases[name] = atlas;
      if (!_pinned.contains(name)) {
        _touch(name);
        _evictIfOverBudget();
      }
      return atlas;
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'journey',
        context: ErrorDescription('loading sprite atlas $name'),
      ));
      return null;
    }
  }

  void _touch(String name) {
    _lru
      ..remove(name)
      ..add(name);
  }

  void _evictIfOverBudget() {
    while (_lru.length > _activityBudget) {
      final victim = _lru.removeAt(0);
      _atlases.remove(victim)?.dispose();
    }
  }

  /// Drops the activity sheets but keeps the parallax layers and the two pet
  /// cycles decoded.
  ///
  /// This is what the canvas calls when it is torn down, which happens on every
  /// tab switch. Releasing the big transient sheets reclaims most of the memory
  /// while leaving the tab instant to return to; a full [clear] would mean
  /// re-decoding the whole world every time the user looks at Journal.
  void releaseActivities() {
    for (final name in _lru) {
      _atlases.remove(name)?.dispose();
    }
    _lru.clear();
  }

  /// Frees everything, including the pinned cycles and parallax layers.
  void clear() {
    for (final atlas in _atlases.values) {
      atlas.dispose();
    }
    _atlases.clear();
    _lru.clear();
    for (final image in parallax.values) {
      image.dispose();
    }
    parallax.clear();
  }
}
