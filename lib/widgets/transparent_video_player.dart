import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class TransparentVideoPlayer extends StatefulWidget {
  final String videoAssetPath;
  final double width;
  final double height;
  final bool loop;
  final bool autoPlay;
  final double opacity;
  final BoxFit fit;

  const TransparentVideoPlayer({
    Key? key,
    required this.videoAssetPath,
    required this.width,
    required this.height,
    this.loop = true,
    this.autoPlay = true,
    this.opacity = 1.0,
    this.fit = BoxFit.contain,
  }) : super(key: key);

  @override
  State<TransparentVideoPlayer> createState() => _TransparentVideoPlayerState();
}

class _TransparentVideoPlayerState extends State<TransparentVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      _controller = VideoPlayerController.asset(widget.videoAssetPath);
      await _controller.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        if (widget.autoPlay) {
          _controller.play();
        }

        if (widget.loop) {
          _controller.setLooping(true);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load video: $e';
        });
      }
      print('VideoPlayer Error: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TransparentVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoAssetPath != widget.videoAssetPath) {
      _controller.dispose();
      _isInitialized = false;
      _initializeVideo();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.1),
          border: Border.all(color: Colors.red),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Opacity(
      opacity: widget.opacity,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Container(
          color: Colors.transparent,
          child: FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          ),
        ),
      ),
    );
  }
}
