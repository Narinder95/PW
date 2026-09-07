import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;
import '../../models/journey/journey_world.dart';
import '../../services/animation/journey_scene.dart';

class JourneyWorldPainter extends CustomPainter {
  /// Every animation frame comes from [scene] notifying, not from a widget
  /// rebuild — hence passing it as `repaint`. Nothing in this painter may be
  /// captured at construction time; it all reads through [scene].
  JourneyWorldPainter(this.scene) : super(repaint: scene);

  final JourneyScene scene;

  JourneyWorld get world => scene.world;
  Map<String, ui.Image> get parallaxLayers => scene.library.parallax;

  /// Seconds of travel, for the procedural fallback backgrounds below. They
  /// are switched off in [paint] but kept intact so they can be turned back on.
  double get animationTime => scene.scrollDistance;

  /// One reusable Paint for every image draw. Allocating a Paint per
  /// `drawImageRect` was showing up on every frame, and the default filter
  /// quality leaves scaled sprites and layers visibly aliased.
  static final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.low
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    // Completely skip procedural background - use parallax layers only
    // if (parallaxLayers.isEmpty) {
    //   _drawParallaxBackground(canvas, size);
    // }
    _drawParallaxLayers(canvas, size);
    // _drawPlatforms(canvas, size);  // Removed - using ground layer instead
    // _drawEnvironmentObjects(canvas, size);  // Keep disabled for now
    _drawStepBankBar(canvas, size);
    _drawPet(canvas, size);
    _drawParticles(canvas, size);
    _drawStatsOverlay(canvas, size);
  }

  /// The step-bank bar: how many of today's steps the pet has "walked off"
  /// (dark green) versus how many are still sitting in the bank waiting to be
  /// burned (light green), out of the day's step goal. Sits low on the ground
  /// layer so it never competes with the pet or the HUD.
  void _drawStepBankBar(Canvas canvas, Size size) {
    final goal = world.stepsGoal;
    if (goal <= 0) return;

    final total = world.stepsToday.clamp(0, goal).toDouble();
    final remaining = scene.stepBank.remaining.clamp(0.0, goal.toDouble());
    final consumed = (total - remaining).clamp(0.0, goal.toDouble());

    const barHeight = 10.0;
    final barWidth = size.width * 0.55;
    final barLeft = (size.width - barWidth) / 2;
    final barTop = size.height * 0.87;

    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(barLeft, barTop, barWidth, barHeight),
      const Radius.circular(5),
    );
    canvas.drawRRect(track, _stepBankTrackPaint);

    void drawSegment(double fromFraction, double toFraction, Paint paint) {
      if (toFraction <= fromFraction) return;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            barLeft + barWidth * fromFraction,
            barTop,
            barWidth * (toFraction - fromFraction),
            barHeight,
          ),
          const Radius.circular(5),
        ),
        paint,
      );
    }

    final consumedFraction = consumed / goal;
    final totalFraction = total / goal;
    drawSegment(0, consumedFraction, _stepBankConsumedPaint);
    drawSegment(consumedFraction, totalFraction, _stepBankRemainingPaint);

    canvas.drawRRect(track, _stepBankBorderPaint);
  }

  static final Paint _stepBankTrackPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.3);

  // Steps the pet has already walked off.
  static final Paint _stepBankConsumedPaint = Paint()
    ..color = const Color(0xFF2E7D32);

  // Steps still in the bank, waiting to be walked off.
  static final Paint _stepBankRemainingPaint = Paint()
    ..color = const Color(0xFF81C784);

  static final Paint _stepBankBorderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.white.withValues(alpha: 0.3);

  // ignore: unused_element
  void _drawParallaxBackground(Canvas canvas, Size size) {
    final hour = DateTime.now().hour;
    final isNight = hour < 6 || hour >= 18;

    // Skip sky gradient if using parallax layers with assets
    // Sky gradient (Far background - slowest parallax) - only draw if no parallax layers
    if (parallaxLayers.isEmpty) {
      final skyGradient = LinearGradient(
        colors: isNight
            ? [const Color(0xFF1a1a2e), const Color(0xFF16213e)]
            : [const Color(0xFF87CEEB), const Color(0xFFE0F6FF)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
        Paint()..shader = skyGradient.createShader(
          Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
        ),
      );
    }

    // Skip procedural backgrounds if using parallax layers
    if (parallaxLayers.isEmpty) {
      // Far background clouds/mountains (parallax layer 1 - slowest)
      _drawFarBackground(canvas, size);

      // Mid background trees/hills (parallax layer 2)
      _drawMidBackground(canvas, size);

      // Near background elements (parallax layer 3 - fastest)
      _drawNearBackground(canvas, size);

      // Ground gradient
      final groundGradient = LinearGradient(
        colors: isNight
            ? [const Color(0xFF2a2a3e), const Color(0xFF1a1a2e)]
            : [const Color(0xFF90EE90), const Color(0xFF7CB342)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.4),
        Paint()..shader = groundGradient.createShader(
          Rect.fromLTWH(0, size.height * 0.6, size.width, size.height * 0.4),
        ),
      );
    }
  }

  void _drawFarBackground(Canvas canvas, Size size) {
    // Mountains/clouds - slowest parallax, moves at 0.3x speed
    const parallaxSpeed = 20.0; // Slow speed for far background
    final parallaxOffset = (animationTime * parallaxSpeed) % (size.width + 300);
    final petOffset = world.pet.position.x * 0.05;

    final paint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final cloudPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Draw repeating mountain/cloud pattern
    for (int cycle = -1; cycle < 3; cycle++) {
      final baseOffset = (parallaxOffset + petOffset) + (cycle * (size.width + 300));

      // Mountains
      canvas.drawPath(
        Path()
          ..moveTo(-100 + baseOffset, size.height * 0.35)
          ..lineTo(50 + baseOffset, size.height * 0.15)
          ..lineTo(200 + baseOffset, size.height * 0.35)
          ..close(),
        paint,
      );

      canvas.drawPath(
        Path()
          ..moveTo(size.width - 150 + baseOffset, size.height * 0.3)
          ..lineTo(size.width - 50 + baseOffset, size.height * 0.1)
          ..lineTo(size.width + 100 + baseOffset, size.height * 0.3)
          ..close(),
        paint,
      );

      // Clouds
      for (int i = 0; i < 3; i++) {
        final cloudX = (i * 200) + baseOffset;
        _drawCloud(canvas, cloudX, size.height * 0.12, cloudPaint);
      }
    }
  }

  void _drawMidBackground(Canvas canvas, Size size) {
    // Trees/hills - medium parallax, moves at 0.6x speed
    const parallaxSpeed = 50.0; // Medium speed for mid background
    final parallaxOffset = (animationTime * parallaxSpeed) % (size.width + 150);
    final petOffset = world.pet.position.x * 0.15;

    final treePaint = Paint()
      ..color = const Color(0xFF228B22)
      ..style = PaintingStyle.fill;

    // Draw repeating trees with seamless looping
    for (int cycle = -1; cycle < 3; cycle++) {
      final baseOffset = (parallaxOffset + petOffset) + (cycle * (size.width + 150));
      for (int i = 0; i < 4; i++) {
        final treeX = (i * 150) + baseOffset;
        _drawTree(canvas, treeX, size.height * 0.45, 40, treePaint);
      }
    }
  }

  void _drawNearBackground(Canvas canvas, Size size) {
    // Foreground elements - fastest parallax, moves at 1x speed
    const parallaxSpeed = 80.0; // Fast speed for near background
    final parallaxOffset = (animationTime * parallaxSpeed) % (size.width + 120);
    final petOffset = world.pet.position.x * 0.25;

    final bushPaint = Paint()
      ..color = const Color(0xFF7CB342)
      ..style = PaintingStyle.fill;

    // Draw repeating bushes with seamless looping
    for (int cycle = -1; cycle < 3; cycle++) {
      final baseOffset = (parallaxOffset + petOffset) + (cycle * (size.width + 120));
      for (int i = 0; i < 5; i++) {
        final bushX = (i * 120) + baseOffset;
        _drawBush(canvas, bushX, size.height * 0.58, bushPaint);
      }
    }
  }

  void _drawParallaxLayers(Canvas canvas, Size size) {
    // Distance travelled only accumulates while the pet walks, so the
    // background pauses and resumes cleanly instead of jumping.
    final travelled = scene.scrollDistance;
    final h = size.height;

    for (final layer in _parallaxOrder) {
      final image = parallaxLayers[layer.name];
      if (image == null) continue;
      _drawScrollingLayer(
        canvas,
        image,
        size,
        h * layer.top,
        h * layer.bottom,
        travelled * layer.speed,
      );
    }
  }

  /// The five layers differ only in band and speed, so they share one routine.
  /// Pixels-per-second of scroll; larger reads as nearer the camera.
  static const _parallaxOrder = <_ParallaxLayer>[
    _ParallaxLayer('background', 0.0, 0.8, 30.0),
    _ParallaxLayer('sky', 0.0, 0.5, 30.0),
    _ParallaxLayer('mid', 0.0, 0.8, 60.0),
    _ParallaxLayer('near', 0.8, 0.9, 100.0),
    _ParallaxLayer('ground', 0.25, 1.0, 80.0),
  ];

  void _drawScrollingLayer(
    Canvas canvas,
    ui.Image layer,
    Size canvasSize,
    double startY,
    double endY,
    double offsetX,
  ) {
    final layerHeight = endY - startY;
    // Tile width follows the image aspect so the artwork is never stretched.
    final tileWidth = layerHeight * layer.width / layer.height;
    if (tileWidth <= 0) return;

    final src = Rect.fromLTWH(
      0,
      0,
      layer.width.toDouble(),
      layer.height.toDouble(),
    );

    // Only the tiles that actually intersect the canvas are drawn. The old
    // code walked a fixed range and issued draws far off screen.
    final scrolled = offsetX % tileWidth;
    var drawX = -scrolled;
    while (drawX < canvasSize.width) {
      canvas.drawImageRect(
        layer,
        src,
        Rect.fromLTWH(drawX, startY, tileWidth, layerHeight),
        _imagePaint,
      );
      drawX += tileWidth;
    }
  }

  // ignore: unused_element
  void _drawTileableLayer(
    Canvas canvas,
    ui.Image layer,
    double startY,
    double endY,
    double offsetX,
  ) {
    final layerHeight = endY - startY;
    final layerWidth = layer.width.toDouble();

    // Normalize offset to layer width for seamless tiling
    final normalizedOffset = offsetX % layerWidth;

    // Draw multiple tiles to ensure full coverage with infinite loop
    // Start further left and end further right to guarantee seamless coverage
    int startTile = (-normalizedOffset / layerWidth).floor() - 1;
    int endTile = ((8000 - normalizedOffset) / layerWidth).ceil() + 1;

    for (int i = startTile; i <= endTile; i++) {
      final drawX = (i * layerWidth) - normalizedOffset;

      canvas.drawImageRect(
        layer,
        Rect.fromLTWH(0, 0, layer.width.toDouble(), layer.height.toDouble()),
        Rect.fromLTWH(drawX, startY, layerWidth, layerHeight),
        Paint(),
      );
    }
  }

  void _drawCloud(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 60, 25),
        const Radius.circular(12),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 30, y - 12, 50, 30),
        const Radius.circular(12),
      ),
      paint,
    );
  }

  void _drawTree(Canvas canvas, double x, double y, double size, Paint paint) {
    // Trunk
    canvas.drawRect(
      Rect.fromLTWH(x + size * 0.35, y + size * 0.6, size * 0.3, size * 0.4),
      paint,
    );
    // Crown
    canvas.drawCircle(
      Offset(x + size / 2, y + size * 0.4),
      size * 0.35,
      paint,
    );
  }

  void _drawBush(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, 50, 30),
        const Radius.circular(15),
      ),
      paint,
    );
  }

  // ignore: unused_element
  void _drawPlatforms(Canvas canvas, Size size) {
    final platformY = size.height * 0.65;
    final platformPaint = Paint()
      ..color = const Color(0xFF8B6F47)
      ..style = PaintingStyle.fill;

    final platformShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    // Main platform
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, platformY, size.width, size.height * 0.08),
        const Radius.circular(0),
      ),
      platformPaint,
    );

    // Platform shadow
    canvas.drawRect(
      Rect.fromLTWH(0, platformY + size.height * 0.08, size.width, 2),
      platformShadowPaint,
    );

    // Platform texture (grass top)
    final grassPaint = Paint()
      ..color = const Color(0xFF7CB342)
      ..style = PaintingStyle.fill;

    canvas.drawRect(
      Rect.fromLTWH(0, platformY - 3, size.width, 3),
      grassPaint,
    );
  }

  // ignore: unused_element
  void _drawEnvironmentObjects(Canvas canvas, Size size) {
    final sortedObjects = [...world.objects]
      ..sort((a, b) => a.depth.compareTo(b.depth));

    for (var obj in sortedObjects) {
      _drawObject(canvas, obj, size);
    }
  }

  void _drawObject(Canvas canvas, EnvironmentObject obj, Size size) {
    final paint = Paint()
      ..color = _getObjectColor(obj.assetName)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final rect = Rect.fromLTWH(obj.position.x, obj.position.y, obj.size.x, obj.size.y);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      paint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      borderPaint,
    );

    if (obj.isInteractive) {
      canvas.drawCircle(
        Offset(obj.position.x + obj.size.x - 6, obj.position.y + 6),
        4,
        Paint()..color = Colors.amber.withValues(alpha: 0.8),
      );
    }
  }

  void _drawPet(Canvas canvas, Size size) {
    final petSize = size.width * 0.42;
    final petWidth = petSize * 1.2; // +20% wider
    final petHeight = petSize;

    // The pet holds the centre of the frame; the world scrolls past it.
    final petVisualX = size.width * 0.5;
    final petY = size.height * 0.55 + petHeight * 0.1;

    final atlas = switch (scene.mode) {
      SceneMode.activity => scene.activityAtlas,
      SceneMode.yawning => scene.idleAtlas,
      SceneMode.walking => scene.walkAtlas,
    };

    if (atlas == null) {
      // Nothing decoded yet, or a clip failed to load.
      _drawPetEmoji(canvas, petVisualX, petY, petSize);
      return;
    }

    final scale = scene.mode == SceneMode.activity ? scene.activityScale : 1.0;
    final w = petWidth * scale;
    final h = petHeight * scale;

    atlas.drawFrame(
      canvas,
      scene.currentFrame,
      Rect.fromLTWH(petVisualX - w * 0.5, petY - h * 0.5, w, h),
      _imagePaint,
    );

    // Draw state indicator above pet
    // _drawPetStateIndicator(canvas, Offset(petVisualX, petY), petSize);  // Disabled

    // Draw movement direction
    // if (world.pet.velocity.x != 0) {
    //   _drawMovementArrow(canvas, petVisualX, petY, petSize, world.pet.velocity.x);  // Disabled
    // }
  }

  void _drawPetEmoji(Canvas canvas, double petX, double petY, double petSize) {
    // Fallback emoji rendering
    final textPainter = TextPainter(
      text: TextSpan(
        text: '🐾',
        style: TextStyle(fontSize: petSize * 0.7),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        petX - textPainter.width / 2,
        petY - textPainter.height / 2,
      ),
    );
  }

  // ignore: unused_element
  void _drawPetStateIndicator(Canvas canvas, Offset petCenter, double petSize) {
    String stateIcon = '';
    Color stateColor = Colors.transparent;

    switch (world.pet.state) {
      case PetState.idle:
        stateIcon = '✨';
        stateColor = Colors.green;
        break;
      case PetState.walking:
        stateIcon = '👟';
        stateColor = Colors.blue;
        break;
      case PetState.playing:
        stateIcon = '🎮';
        stateColor = Colors.purple;
        break;
      case PetState.sleeping:
        stateIcon = '💤';
        stateColor = Colors.indigo;
        break;
      case PetState.celebrating:
        stateIcon = '🎉';
        stateColor = Colors.amber;
        break;
      case PetState.meditating:
        stateIcon = '🧘';
        stateColor = Colors.cyan;
        break;
      case PetState.exercising:
        stateIcon = '💪';
        stateColor = Colors.red;
        break;
      case PetState.drinking_water:
        stateIcon = '💧';
        stateColor = Colors.blue;
        break;
      case PetState.reading:
        stateIcon = '📚';
        stateColor = Colors.orange;
        break;
    }

    // Draw state badge
    canvas.drawCircle(
      Offset(petCenter.dx + petSize * 0.6, petCenter.dy - petSize * 0.7),
      9,
      Paint()
        ..color = stateColor
        ..style = PaintingStyle.fill,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: stateIcon,
        style: const TextStyle(fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        petCenter.dx + petSize * 0.5 - 3,
        petCenter.dy - petSize * 0.75 - 5,
      ),
    );
  }

  // ignore: unused_element
  void _drawMovementArrow(Canvas canvas, double petX, double petY, double petSize, double velocityX) {
    final direction = velocityX > 0 ? '→' : '←';
    final arrowPaint = TextPainter(
      text: TextSpan(
        text: direction,
        style: TextStyle(
          fontSize: petSize * 0.6,
          color: Colors.white,
          shadows: const [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Colors.black45,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    arrowPaint.layout();
    arrowPaint.paint(
      canvas,
      Offset(
        petX + (velocityX > 0 ? petSize * 0.7 : -petSize * 1.2),
        petY - petSize * 0.8,
      ),
    );
  }

  void _drawParticles(Canvas canvas, Size size) {
    for (var emitter in world.particles) {
      final progress = emitter.getProgress();
      final opacity = (1 - progress).clamp(0.0, 1.0);

      for (int i = 0; i < emitter.particleCount; i++) {
        final angle = (i / emitter.particleCount) * 2 * pi;
        final distance = progress * 100;
        final x = emitter.position.x + (distance * cos(angle));
        final y = emitter.position.y + (distance * sin(angle));

        canvas.drawCircle(
          Offset(x, y),
          4 * opacity,
          Paint()
            ..color = Colors.primaries[i % Colors.primaries.length]
                .withValues(alpha: opacity * 0.9),
        );
      }
    }
  }

  /// Laid-out stat lines, rebuilt only when a value actually changes. Laying
  /// out four TextPainters on every frame was pure waste at 60fps.
  final List<TextPainter> _statPainters = [];
  String _statSignature = '';

  static const _statStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    shadows: [
      Shadow(offset: Offset(1, 1), blurRadius: 3, color: Colors.black54),
    ],
  );

  void _drawStatsOverlay(Canvas canvas, Size size) {
    // Game HUD-style stats display at top-right in a card
    final stats = [
      ('👟', '${world.stepsToday}'),
      ('💧', '${world.waterIntake}'),
      ('💪', '${world.exerciseMinutes}m'),
      ('😴', '${world.sleepHours}h'),
    ];

    final signature = stats.map((s) => s.$2).join('|');
    if (signature != _statSignature) {
      _statSignature = signature;
      for (final p in _statPainters) {
        p.dispose();
      }
      _statPainters
        ..clear()
        ..addAll(stats.map((s) => TextPainter(
              text: TextSpan(text: '${s.$1} ${s.$2}', style: _statStyle),
              textDirection: TextDirection.ltr,
            )..layout()));
    }

    const padding = 12.0;
    const lineHeight = 18.0;
    const cardWidth = 65.0;
    final cardHeight = (stats.length * lineHeight) + (padding * 2);

    final cardX = size.width - cardWidth - 12;
    const cardY = 8.0;
    final card = RRect.fromRectAndRadius(
      Rect.fromLTWH(cardX, cardY, cardWidth, cardHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(card, _cardPaint);
    canvas.drawRRect(card, _cardBorderPaint);

    var yOffset = cardY + padding;
    for (final painter in _statPainters) {
      painter.paint(canvas, Offset(cardX + padding, yOffset));
      yOffset += lineHeight;
    }
  }

  static final Paint _cardPaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.6)
    ..style = PaintingStyle.fill;

  static final Paint _cardBorderPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  Color _getObjectColor(String assetName) {
    const colors = {
      'sky_background': Color(0xFF87CEEB),
      'ground_base': Color(0xFF8B6F47),
      'tree_large': Color(0xFF228B22),
      'banner_structure': Color(0xFF8B4513),
      'rock': Color(0xFF6B5B4A),
      'collectible': Color(0xFFFFD700),
      'obstacle': Color(0xFFD32F2F),
    };
    return colors[assetName] ?? Colors.grey[400] ?? Colors.grey;
  }

  @override
  bool shouldRepaint(JourneyWorldPainter oldDelegate) {
    // Animation repaints are driven by the `repaint` listenable in the
    // constructor, so a rebuild with the same scene needs nothing further.
    return oldDelegate.scene != scene;
  }
}

/// One parallax band: which slice of the canvas it fills and how fast it
/// scrolls.
class _ParallaxLayer {
  const _ParallaxLayer(this.name, this.top, this.bottom, this.speed);

  final String name;

  /// Fractions of canvas height.
  final double top;
  final double bottom;

  /// Pixels per second of travel.
  final double speed;
}
