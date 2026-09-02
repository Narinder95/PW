import 'package:flutter/foundation.dart';

import '../../models/journey/journey_world.dart';
import 'sprite_atlas.dart';
import 'sprite_library.dart';

/// What the pet is doing right now.
enum SceneMode { walking, yawning, activity }

/// Mutable render state for the journey canvas.
///
/// The ticker mutates this and calls [notifyListeners]. The painter is wired to
/// it through `CustomPainter`'s `repaint`, so an animation frame costs one
/// repaint and no widget rebuild at all — nothing above the canvas is marked
/// dirty and no element tree is walked.
class JourneyScene extends ChangeNotifier {
  JourneyScene(this.world);

  final JourneyWorld world;
  final SpriteLibrary library = SpriteLibrary.instance;

  SceneMode mode = SceneMode.walking;

  /// True once the parallax layers have decoded and there is something worth
  /// painting.
  bool ready = false;

  /// Seconds of forward travel, integrated only while the pet is walking. The
  /// parallax offset and the walk cycle are both derived from it, so pausing
  /// and resuming never makes the background jump.
  double scrollDistance = 0;

  /// Wrapped well before doubles lose sub-pixel precision on the multiplied
  /// layer offsets.
  static const _scrollWrap = 1000000.0;

  /// Elapsed seconds within the current yawn or activity clip.
  double _clipElapsed = 0;

  String? _activityName;
  String? get activityName => _activityName;

  SpriteAtlas? get walkAtlas => library.peek('walk');
  SpriteAtlas? get idleAtlas => library.peek('idle');
  SpriteAtlas? get activityAtlas =>
      _activityName == null ? null : library.peek(_activityName!);

  /// Extra scale some clips are drawn at, matching how they were framed.
  static const _clipScale = <String, double>{
    'meditation': 1.2,
    'reading': 1.1,
  };

  double get activityScale => _clipScale[_activityName] ?? 1.0;

  /// The clip playing right now, if any.
  SpriteAtlas? get _clipAtlas => switch (mode) {
        SceneMode.walking => walkAtlas,
        SceneMode.yawning => idleAtlas,
        SceneMode.activity => activityAtlas,
      };

  /// Frame to draw.
  ///
  /// Walking is a true cycle and wraps. Yawns and activities play through
  /// exactly once, so they clamp instead — if a tick overshoots the end, the
  /// clip holds its last frame for that frame rather than snapping back to the
  /// start.
  int get currentFrame {
    final atlas = _clipAtlas;
    if (atlas == null) return 0;
    if (mode == SceneMode.walking) {
      return (scrollDistance * atlas.fps).floor() % atlas.frameCount;
    }
    return (_clipElapsed * atlas.fps).floor().clamp(0, atlas.frameCount - 1);
  }

  /// Advances one animation frame. [dt] is clamped by the caller.
  void advance(double dt) {
    if (mode == SceneMode.walking) {
      scrollDistance += dt;
      if (scrollDistance > _scrollWrap) scrollDistance -= _scrollWrap;
    } else {
      _clipElapsed += dt;
      // One pass through the clip, then the pet carries on walking, however
      // much activity was logged.
      if (_clipElapsed >= (_clipAtlas?.duration ?? 0)) walk();
    }
    world.update(dt);
    notifyListeners();
  }

  void walk() {
    mode = SceneMode.walking;
    _activityName = null;
    _clipElapsed = 0;
    world.petMove(1);
  }

  void yawn() {
    if (idleAtlas == null) return;
    mode = SceneMode.yawning;
    _clipElapsed = 0;
    world.petSleep();
  }

  /// Plays [name] once, then returns to walking. The atlas must already be
  /// decoded; the canvas awaits [SpriteLibrary.load] first.
  void startActivity(String name, PetState state) {
    if (library.peek(name) == null) return;
    mode = SceneMode.activity;
    _activityName = name;
    _clipElapsed = 0;
    world.pet.state = state;
    world.pet.velocity.x = 0;
  }
}
