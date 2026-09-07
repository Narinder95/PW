import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class LottieAnimationPlayer extends StatefulWidget {
  final String animationAssetPath;
  final double width;
  final double height;
  final bool loop;
  final bool autoPlay;
  final double opacity;
  final BoxFit fit;

  const LottieAnimationPlayer({
    Key? key,
    required this.animationAssetPath,
    required this.width,
    required this.height,
    this.loop = true,
    this.autoPlay = true,
    this.opacity = 1.0,
    this.fit = BoxFit.contain,
  }) : super(key: key);

  @override
  State<LottieAnimationPlayer> createState() => _LottieAnimationPlayerState();
}

class _LottieAnimationPlayerState extends State<LottieAnimationPlayer>
    with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    if (widget.autoPlay) {
      _animationController.forward();
    }

    if (widget.loop) {
      _animationController.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationController.forward(from: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: widget.opacity,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Container(
          color: Colors.transparent,
          child: Lottie.asset(
            widget.animationAssetPath,
            controller: _animationController,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            onLoaded: (composition) {
              _animationController.duration = composition.duration;
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    'Failed to load animation\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
