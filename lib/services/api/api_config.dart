import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the backend base URL, with a persisted runtime override.
///
/// Defaults follow the contract: an Android emulator reaches the host machine
/// at `10.0.2.2`, everything else at `localhost`. The override exists so QA
/// can point a build at a staging host without a rebuild; it is persisted in
/// shared_preferences and survives a restart.
class ApiConfig {
  /// shared_preferences key for the override. Namespaced so it cannot collide
  /// with the auth token or any UI preference.
  static const String prefsKey = 'pw.api.baseUrl';

  static const String _androidDefault = 'http://10.0.2.2:8080';
  static const String _hostDefault = 'http://localhost:8080';

  /// The real, hosted API (Render + Neon Postgres). Release builds go
  /// straight here — a shipped app has no `localhost`/`10.0.2.2` to probe,
  /// and trying them first would just waste a couple of seconds on every
  /// cold start for no benefit.
  static const String _productionDefault = 'https://habitpet-api.onrender.com';

  String? _override;

  /// Host discovered by [autoDetect], used when there is no explicit
  /// [_override]. Held in memory only: re-probing every launch means moving
  /// between an emulator, a cabled handset and a laptop just works, whereas a
  /// persisted value would go stale and need clearing by hand.
  String? _detected;

  /// [override] seeds the value without touching shared_preferences, which is
  /// what tests want (no plugin, no async).
  ApiConfig({String? override}) : _override = _normalise(override);

  /// Platform default, ignoring any override.
  ///
  /// A release build always defaults to the real hosted API — there is no
  /// dev server to guess at once this is installed on someone's device.
  /// `kIsWeb` is checked next: `defaultTargetPlatform` reports the *browser's*
  /// host OS on web, so an Android phone browsing the web build would
  /// otherwise be handed the emulator address.
  static String get platformDefault {
    if (kReleaseMode) return _productionDefault;
    if (kIsWeb) return _hostDefault;
    return defaultTargetPlatform == TargetPlatform.android
        ? _androidDefault
        : _hostDefault;
  }

  /// Candidate hosts to probe, best guess first.
  ///
  /// Empty in a release build: there is nothing local worth probing for, and
  /// trying anyway would just waste a couple of seconds on every cold start
  /// before falling back to [platformDefault]. On Android `localhost` comes
  /// first because that is what an `adb reverse tcp:8080 tcp:8080` tunnel
  /// exposes on a **physical** handset, and a physical device is the common
  /// case. On an emulator nothing is listening there, so the probe fails
  /// fast and falls through to `10.0.2.2`, the emulator's alias for the host
  /// machine.
  static List<String> get candidates {
    if (kReleaseMode) return const <String>[];
    if (kIsWeb) return const <String>[_hostDefault];
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const <String>[_hostDefault, _androidDefault];
    }
    return const <String>[_hostDefault];
  }

  /// The base URL in force: an explicit override, else an auto-detected host,
  /// else [platformDefault]. Never has a trailing slash.
  String get baseUrl => _override ?? _detected ?? platformDefault;

  /// Whether a non-default host is currently in force.
  bool get hasOverride => _override != null;

  /// Whether [autoDetect] picked the host currently in use.
  bool get isAutoDetected => _override == null && _detected != null;

  /// Probes [candidates] and adopts the first that answers `/api/health`.
  ///
  /// A no-op when the user has set an explicit override — their choice wins
  /// over anything we sniff out. Never throws: if nothing answers, the
  /// platform default stays in place and the UI shows its normal
  /// "can't reach the server" panel with the change-server affordance.
  ///
  /// This exists because the single most common way to lose an afternoon on
  /// this project is running against a physical Android device, where the
  /// emulator-only `10.0.2.2` silently fails.
  Future<void> autoDetect({
    http.Client? httpClient,
    Duration perHostTimeout = const Duration(milliseconds: 1200),
  }) async {
    if (_override != null) return;

    final client = httpClient ?? http.Client();
    try {
      for (final host in candidates) {
        try {
          final res = await client
              .get(Uri.parse('$host/api/health'))
              .timeout(perHostTimeout);
          if (res.statusCode == 200) {
            _detected = host;
            return;
          }
        } on Exception {
          // Refused, unreachable, or timed out (TimeoutException is itself an
          // Exception) — try the next candidate.
        }
      }
      _detected = null;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  /// Loads a persisted override. Safe to call before `runApp` completes; a
  /// missing plugin (unit test, unsupported platform) leaves the default in
  /// place rather than throwing.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _override = _normalise(prefs.getString(prefsKey));
    } on Exception {
      _override = null;
    }
  }

  /// Sets and persists the override. Pass null to clear it and fall back to
  /// [platformDefault].
  Future<void> setBaseUrl(String? value) async {
    _override = _normalise(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_override == null) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, _override!);
      }
    } on Exception {
      // Persisting is best-effort: the in-memory override still applies for
      // this run, which is what a QA session actually needs.
    }
  }

  /// Sets the override for this run only, without persisting.
  void setBaseUrlInMemory(String? value) => _override = _normalise(value);

  /// Builds an absolute [Uri] for [path], appending [query].
  ///
  /// Null query values are dropped (an absent `?before=` is not the same as an
  /// empty one), and non-string values are stringified, so callers can pass
  /// ints and bools directly.
  Uri resolve(String path, [Map<String, dynamic>? query]) {
    final normalisedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalisedPath');

    if (query == null || query.isEmpty) return uri;

    final params = <String, String>{...uri.queryParameters};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is String ? value : '$value';
    });
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  /// Trims whitespace and any trailing slash; empty becomes null so a blank
  /// text field clears the override instead of producing `http:///api/...`.
  static String? _normalise(String? value) {
    if (value == null) return null;
    var trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() => 'ApiConfig($baseUrl${hasOverride ? ' [override]' : ''})';
}
