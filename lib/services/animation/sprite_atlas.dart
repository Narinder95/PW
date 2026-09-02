import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// One packed sprite sheet plus the geometry needed to draw a single frame
/// from it.
///
/// The sheets are produced offline by `tool/build_atlases.dart`. Each one holds
/// every frame of an animation in a grid, already trimmed to the artwork's
/// bounding box and scaled down to the size the pet is actually drawn at.
class SpriteAtlas {
  SpriteAtlas({
    required this.name,
    required this.sheet,
    required this.frameCount,
    required this.cols,
    required this.frameWidth,
    required this.frameHeight,
    required this.padding,
    required this.fps,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
  });

  final String name;
  final ui.Image sheet;
  final int frameCount;
  final int cols;
  final int frameWidth;
  final int frameHeight;
  final int padding;
  final int fps;

  /// Geometry of the original render, and the window within it that the packed
  /// frames were trimmed to. Together these let [drawFrame] place a trimmed
  /// sprite exactly where the untrimmed frame would have landed, so trimming
  /// saves memory without shifting anything on screen.
  final int sourceWidth;
  final int sourceHeight;
  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;

  /// Seconds for one pass through the animation at its authored rate.
  double get duration => frameCount / fps;

  /// Approximate decoded size in bytes, used for the residency budget.
  int get byteSize => sheet.width * sheet.height * 4;

  static SpriteAtlas fromManifest(
    Map<String, dynamic> m,
    ui.Image sheet,
  ) {
    int i(String k) => (m[k] as num).toInt();
    return SpriteAtlas(
      name: m['name'] as String,
      sheet: sheet,
      frameCount: i('frameCount'),
      cols: i('cols'),
      frameWidth: i('frameWidth'),
      frameHeight: i('frameHeight'),
      padding: i('padding'),
      fps: i('fps'),
      sourceWidth: i('sourceWidth'),
      sourceHeight: i('sourceHeight'),
      cropX: i('cropX'),
      cropY: i('cropY'),
      cropWidth: i('cropWidth'),
      cropHeight: i('cropHeight'),
    );
  }

  /// The frame's rectangle within the sheet.
  Rect sourceRect(int index) {
    final i = index.clamp(0, frameCount - 1);
    final col = i % cols;
    final row = i ~/ cols;
    return Rect.fromLTWH(
      (col * (frameWidth + padding)).toDouble(),
      (row * (frameHeight + padding)).toDouble(),
      frameWidth.toDouble(),
      frameHeight.toDouble(),
    );
  }

  /// Draws frame [index] as though the full untrimmed render were being drawn
  /// into [frameDest].
  void drawFrame(Canvas canvas, int index, Rect frameDest, Paint paint) {
    final sx = frameDest.width / sourceWidth;
    final sy = frameDest.height / sourceHeight;
    canvas.drawImageRect(
      sheet,
      sourceRect(index),
      Rect.fromLTWH(
        frameDest.left + cropX * sx,
        frameDest.top + cropY * sy,
        cropWidth * sx,
        cropHeight * sy,
      ),
      paint,
    );
  }

  void dispose() => sheet.dispose();
}
