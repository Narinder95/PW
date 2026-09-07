import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/journey/journey_world.dart';
import '../../models/walking_challenge.dart';
import '../../services/animation/journey_scene.dart';
import '../../services/animation/sprite_library.dart';
import 'journey_world_painter.dart';
import 'walking_challenge_card.dart';

class JourneyCanvas extends StatefulWidget {
  final int stepsToday;
  final int waterIntake;
  final int exerciseMinutes;
  final int sleepHours;
  final Function(int steps)? onActivityLogged;
  final WalkingChallenge? challenge;
  final bool challengeLoading;
  final bool challengePermissionDenied;
  final VoidCallback? onConnectHealth;

  /// The pet's step bank. Owned by [AppServices][1] (one session-lifetime
  /// instance), not by this widget — this canvas is torn down and rebuilt
  /// every time the Journey tab is hidden and shown again, and the bank must
  /// survive that or the pet would re-walk steps it already burned. Null
  /// falls back to a fresh bank of this widget's own, for standalone use
  /// (tests, previews) outside the app's [AppScope].
  ///
  /// [1]: ../app_scope.dart
  final PetStepBank? petStepBank;

  const JourneyCanvas({
    Key? key,
    this.stepsToday = 0,
    this.waterIntake = 0,
    this.exerciseMinutes = 0,
    this.sleepHours = 0,
    this.onActivityLogged,
    this.challenge,
    this.challengeLoading = false,
    this.challengePermissionDenied = false,
    this.onConnectHealth,
    this.petStepBank,
  }) : super(key: key);

  @override
  State<JourneyCanvas> createState() => JourneyCanvasState();
}

/// Public so [JourneyScreen] can drive the animations through a
/// GlobalKey<JourneyCanvasState> and have those calls type-checked.
class JourneyCanvasState extends State<JourneyCanvas>
    with SingleTickerProviderStateMixin {
  final SpriteLibrary _library = SpriteLibrary.instance;

  late final JourneyWorld _world;
  late final JourneyScene _scene;
  late final Ticker _ticker;

  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();

    _world = JourneyWorld()..initialize(1, 1);
    _scene = JourneyScene(_world, widget.petStepBank ?? PetStepBank());
    // Deposit today's steps into the bank before deciding walk vs. yawn, so
    // the pet doesn't flash a yawn on startup just because the sync order
    // would otherwise ask it to walk on an empty bank.
    _scene.syncSteps(widget.stepsToday);
    _world.updateActivityStats(
      steps: widget.stepsToday,
      stepsGoal: widget.challenge?.target,
      water: widget.waterIntake,
      exercise: widget.exerciseMinutes,
      sleep: widget.sleepHours,
    );
    _scene.walk();

    _ticker = createTicker(_onTick);
    _bootstrap();
  }

  /// Startup order is deliberate. The parallax layers are small and are all the
  /// first frame needs, so they load first and the world appears immediately.
  /// The pet cycles follow, and the activity clips are not touched until the
  /// user logs something.
  Future<void> _bootstrap() async {
    await _library.loadParallax();
    if (!mounted) return;
    _scene.ready = true;
    setState(() {});
    _ticker.start();

    await Future.wait([_library.load('walk'), _library.load('idle')]);
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    // A backgrounded app or a dropped frame can hand us a huge delta; clamping
    // keeps the pet from teleporting when the app comes back.
    if (dt <= 0) return;
    _scene.advance(dt > 0.05 ? 0.05 : dt);
  }

  @override
  void didUpdateWidget(JourneyCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepsToday != widget.stepsToday) {
      _scene.syncSteps(widget.stepsToday);
    }
    if (oldWidget.stepsToday != widget.stepsToday ||
        oldWidget.challenge?.target != widget.challenge?.target ||
        oldWidget.waterIntake != widget.waterIntake ||
        oldWidget.exerciseMinutes != widget.exerciseMinutes ||
        oldWidget.sleepHours != widget.sleepHours) {
      _world.updateActivityStats(
        steps: widget.stepsToday,
        stepsGoal: widget.challenge?.target,
        water: widget.waterIntake,
        exercise: widget.exerciseMinutes,
        sleep: widget.sleepHours,
      );
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    // Keep the parallax layers and pet cycles decoded so coming back to this
    // tab is instant; only the large activity sheets are given back.
    _library.releaseActivities();
    super.dispose();
  }

  // --- Public API used by JourneyScreen -------------------------------------

  /// Each of these plays its clip through once and then the pet resumes
  /// walking, regardless of how much the user logged.
  void startMeditation() => _play('meditation', PetState.meditating);

  void startExercise() => _play('exercise', PetState.exercising);

  void startReading() => _play('reading', PetState.reading);

  void startDrinkingWater() => _play('drinking_water', PetState.drinking_water);

  /// Decodes the clip if this is its first use, then plays it. The pet keeps
  /// walking during the decode rather than freezing on a blank frame.
  Future<void> _play(String name, PetState state) async {
    final atlas = await _library.load(name);
    if (!mounted || atlas == null) return;
    _scene.startActivity(name, state);
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_scene.ready) {
      return const ColoredBox(
        color: Color(0xFFF5F5F5),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Stack(
      children: [
        GestureDetector(
          onTapDown: _handleCanvasTap,
          // The canvas repaints every frame. A boundary keeps that off the
          // rest of the screen, so the activity cards below are never
          // re-rastered.
          child: RepaintBoundary(
            child: CustomPaint(
              painter: JourneyWorldPainter(_scene),
              willChange: true,
              size: Size.infinite,
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: WalkingTierBadge(
            challenge: widget.challenge,
            isLoading: widget.challengeLoading,
            permissionDenied: widget.challengePermissionDenied,
            onConnectHealth: widget.onConnectHealth,
          ),
        ),
      ],
    );
  }

  void _handleCanvasTap(TapDownDetails details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(details.globalPosition);
    // The pet is always drawn centred on the ground line.
    final petCentre = Offset(box.size.width * 0.5, box.size.height * 0.7);
    if ((local - petCentre).distance <= box.size.width * 0.25) {
      _world.celebrate();
    }
  }
}
