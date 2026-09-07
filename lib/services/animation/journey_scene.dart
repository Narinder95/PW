import 'package:flutter/foundation.dart';

import '../../models/journey/journey_world.dart';
import 'sprite_atlas.dart';
import 'sprite_library.dart';

/// What the pet is doing right now.
enum SceneMode { walking, yawning, activity }

/// Steps taken but not yet "walked off", plus how much of today's step count
/// has already been credited to it.
///
/// Lives on [AppServices][1], **not** on [JourneyScene] — the Journal/Journey
/// tab switch tears down and rebuilds the whole canvas (and with it a fresh
/// `JourneyScene`) every time the tab is hidden and shown again, by design,
/// so the walk ticker doesn't run off screen. If the bank lived on the scene
/// it would reset to a fresh deposit of the *entire* day's steps on every
/// return to the tab, letting the pet re-walk steps it already burned. This
/// object is constructed once per app session and handed to whichever
/// `JourneyScene` is current, so the bank itself survives the tear-down.
///
/// [1]: ../../widgets/app_scope.dart
class PetStepBank {
  /// Steps deposited but not yet walked off. The pet only walks while this is
  /// positive; it drains at [stepBurnRate] while walking, and once it hits
  /// zero the pet yawns once and holds there until fresh steps arrive.
  double remaining = 0;

  /// Steps/second a walk burns from the bank — 150 steps/minute.
  static const double stepBurnRate = 150 / 60;

  /// Cumulative steps already credited to [remaining], so a later sync only
  /// deposits the *increase* rather than double-crediting the same steps.
  int lastSynced = 0;

  /// Whether the yawn clip has already played through to its last frame for
  /// the *current* empty-bank episode.
  ///
  /// Needed for the same reason [remaining] lives here rather than on
  /// `JourneyScene`: a tab round-trip rebuilds the scene from scratch, which
  /// would otherwise replay the whole yawn from frame 0 every time, even
  /// though the pet had already finished it and was just holding the last
  /// frame. `walk()` clears this the moment fresh energy lets the pet move
  /// again, so the next time it runs dry the yawn plays in full once more.
  bool yawnPlayed = false;
}

/// Mutable render state for the journey canvas.
///
/// The ticker mutates this and calls [notifyListeners]. The painter is wired to
/// it through `CustomPainter`'s `repaint`, so an animation frame costs one
/// repaint and no widget rebuild at all — nothing above the canvas is marked
/// dirty and no element tree is walked.
class JourneyScene extends ChangeNotifier {
  JourneyScene(this.world, this.stepBank);

  final JourneyWorld world;
  final PetStepBank stepBank;
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

  /// Playback speed multiplier for activity animations (slower than walk).
  static const double _activityAnimationSpeedMultiplier = 0.75;

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
    // Already played through once for this empty-bank episode (possibly in a
    // scene instance before a tab switch tore it down) — jump straight to
    // the held last frame instead of animating up to it again.
    if (mode == SceneMode.yawning && stepBank.yawnPlayed) {
      return atlas.frameCount - 1;
    }
    // Activity animations play slower
    return (_clipElapsed * atlas.fps * _activityAnimationSpeedMultiplier).floor().clamp(0, atlas.frameCount - 1);
  }

  /// Advances one animation frame. [dt] is clamped by the caller.
  void advance(double dt) {
    switch (mode) {
      case SceneMode.walking:
        stepBank.remaining =
            (stepBank.remaining - PetStepBank.stepBurnRate * dt).clamp(0.0, double.infinity);
        scrollDistance += dt;
        if (scrollDistance > _scrollWrap) scrollDistance -= _scrollWrap;
        // The bank just ran dry mid-stride — park on a yawn until more steps
        // come in rather than walking on nothing.
        if (stepBank.remaining <= 0) _parkOnEmptyBank();
        break;
      case SceneMode.yawning:
        // Plays once and holds on its last frame (see currentFrame) — no
        // auto-return to walking. Only syncSteps() wakes the pet back up.
        _clipElapsed += dt;
        final duration = (_clipAtlas?.duration ?? 0) / _activityAnimationSpeedMultiplier;
        if (_clipElapsed >= duration) stepBank.yawnPlayed = true;
        break;
      case SceneMode.activity:
        _clipElapsed += dt;
        // Account for speed multiplier when checking if animation is done.
        if (_clipElapsed >= ((_clipAtlas?.duration ?? 0) / _activityAnimationSpeedMultiplier)) {
          walk();
        }
        break;
    }
    world.update(dt);
    notifyListeners();
  }

  /// Enters walking mode if there is anything left in the step bank to burn;
  /// otherwise parks the pet on a held yawn instead of walking on empty.
  void walk() {
    _activityName = null;
    _clipElapsed = 0;
    if (stepBank.remaining > 0) {
      mode = SceneMode.walking;
      // Fresh energy — the next time the bank runs dry is a new episode, so
      // the yawn should play in full again rather than jump to its end.
      stepBank.yawnPlayed = false;
      world.petMove(1);
    } else {
      _parkOnEmptyBank();
    }
  }

  void _parkOnEmptyBank() {
    mode = SceneMode.yawning;
    _clipElapsed = 0;
    world.petSleep();
  }

  /// Call whenever the device's step count for today changes. Only the
  /// increase since the last sync is deposited into the bank — a total that
  /// drops (a fresh day rolling over) just resets the baseline rather than
  /// crediting a negative deposit.
  void syncSteps(int totalStepsToday) {
    final delta = totalStepsToday - stepBank.lastSynced;
    stepBank.lastSynced = totalStepsToday;
    if (delta <= 0) return;
    stepBank.remaining += delta;
    // Fresh steps arrived while the pet was parked on an empty bank — put it
    // back to work.
    if (mode == SceneMode.yawning) walk();
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
