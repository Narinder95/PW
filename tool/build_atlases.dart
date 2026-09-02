// Offline sprite-atlas builder for the Journey canvas.
//
// Reads the raw per-frame PNG renders under assets/journey/pet/** plus the
// parallax layers, and emits a handful of small sprite sheets and a manifest
// into assets/journey/atlas/. Only those outputs are shipped in the app.
//
// Run with:  dart run tool/build_atlases.dart
//
// Safe to re-run; it only writes into assets/journey/atlas/.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const outDir = 'assets/journey/atlas';

/// Transparent gutter between packed frames so the GPU's bilinear sampling
/// never bleeds a neighbouring frame in at the edges.
const padding = 2;

/// Sheets are sized so that BOTH dimensions round up to at most this power of
/// two.
///
/// This matters more than the raw pixel count. GPU drivers allocate textures at
/// power-of-two dimensions, so a 2394x2387 sheet holding 22.9 MB of pixels
/// actually occupies a 4096x4096 texture — 67 MB. Measured on device, that one
/// sheet cost 70 MB of GPU memory. Keeping every sheet inside 2048x2048 caps it
/// at 16.8 MB instead, a 4x saving for the same artwork.
const maxSheetDimension = 2048;

/// No point packing frames larger than the pet is ever drawn. On a 1080p phone
/// the sprite lands at roughly 425 physical pixels wide.
const maxFrameWidth = 448;

class AnimSpec {
  final String name;

  /// Source directories, concatenated in order. Files inside each are sorted
  /// lexicographically, which is frame order since all names are zero padded.
  final List<String> dirs;

  /// How many frames to keep. The source sequences are far denser than the
  /// playback rate needs, so they get evenly subsampled down to this.
  final int keep;

  /// Playback rate the app should use for this animation.
  final int fps;

  /// Alpha at or above this counts as content when measuring the crop box.
  final int alphaThreshold;

  const AnimSpec(
    this.name,
    this.dirs,
    this.keep,
    this.fps, {
    this.alphaThreshold = 16,
  });
}

const specs = <AnimSpec>[
  // walk and idle are true cycles and stay resident, so they are kept lean.
  // The walk renders carry the pet's soft ground shadow at low alpha, so their
  // crop box needs a higher cutoff than the clean activity renders or the box
  // grows to the full frame.
  AnimSpec('walk', ['assets/journey/pet/walk/right'], 21, 24,
      alphaThreshold: 40),
  AnimSpec(
    'idle',
    [
      'assets/journey/pet/idle/yawning/yawning_1',
      'assets/journey/pet/idle/yawning/yawning_2',
      'assets/journey/pet/idle/yawning/yawning_3',
      'assets/journey/pet/idle/yawning/yawning_4',
    ],
    28,
    8,
    alphaThreshold: 40,
  ),
  // The activity clips are narrative sequences rather than loops (exercise runs
  // dumbbells -> bench press -> run -> celebrate), so they need enough frames
  // that each beat still reads as motion. 30 is what fits a 2048x2048 sheet at
  // close to full sprite resolution; going higher would force either a smaller
  // frame or a 4x more expensive texture.
  //
  // These play through exactly once, so fps sets how long the pet spends on the
  // activity: 30 frames at 8fps is a 3.75s clip. Lower this to slow them down.
  AnimSpec('exercise', ['assets/journey/pet/exercise'], 30, 8),
  AnimSpec('meditation', ['assets/journey/pet/meditation'], 30, 8),
  AnimSpec('reading', ['assets/journey/pet/reading'], 30, 8),
  AnimSpec('drinking_water', ['assets/journey/pet/drinking_water'], 30, 8),
];

/// Parallax layers keep their exact aspect ratio: the painter derives tile
/// width from it, so cropping them would shift the scroll geometry. They are
/// only downscaled.
///
/// Sized against the band each one fills rather than uniformly. `near` occupies
/// just 10% of the canvas height, so it needs a fraction of the resolution the
/// full-height layers do, and these widths land just under a power of two so
/// none of the texture allocation is wasted.
const parallaxSpecs = <String, int>{
  'sky': 1024,
  'mid': 1280,
  'near': 512,
  'ground': 1280,
};

List<File> listFrames(List<String> dirs) {
  final out = <File>[];
  for (final d in dirs) {
    final dir = Directory(d);
    if (!dir.existsSync()) {
      stderr.writeln('  ! missing dir $d');
      continue;
    }
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    out.addAll(files);
  }
  return out;
}

/// Evenly spreads [keep] picks across [total] frames, always including the
/// first, so a subsampled cycle still covers the whole motion.
List<int> pickIndices(int total, int keep) {
  if (total <= keep) return List<int>.generate(total, (i) => i);
  return List<int>.generate(keep, (i) => (i * total / keep).floor());
}

img.Image loadRgba8(File f) {
  final decoded = img.decodePng(f.readAsBytesSync());
  if (decoded == null) throw StateError('cannot decode ${f.path}');
  // Sources are a mix of 8-bit RGB, 8-bit RGBA and 16-bit RGBA. Normalise.
  if (decoded.format == img.Format.uint8 && decoded.numChannels == 4) {
    return decoded;
  }
  return decoded.convert(format: img.Format.uint8, numChannels: 4);
}

class Box {
  int l, t, r, b;
  Box(this.l, this.t, this.r, this.b);

  bool get isEmpty => r < l || b < t;
  int get width => r - l + 1;
  int get height => b - t + 1;

  void union(Box o) {
    if (o.isEmpty) return;
    if (isEmpty) {
      l = o.l;
      t = o.t;
      r = o.r;
      b = o.b;
      return;
    }
    l = math.min(l, o.l);
    t = math.min(t, o.t);
    r = math.max(r, o.r);
    b = math.max(b, o.b);
  }
}

/// Bounding box of pixels whose alpha clears [threshold]. Scans on a 2px grid
/// and pads the result by 2, since we only need it accurate to a pixel or two.
Box contentBox(img.Image im, int threshold) {
  var l = im.width, t = im.height, r = -1, b = -1;
  for (var y = 0; y < im.height; y += 2) {
    for (var x = 0; x < im.width; x += 2) {
      if (im.getPixel(x, y).a >= threshold) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  if (r < 0) return Box(0, 0, im.width - 1, im.height - 1);
  return Box(
    math.max(0, l - 2),
    math.max(0, t - 2),
    math.min(im.width - 1, r + 2),
    math.min(im.height - 1, b + 2),
  );
}

int _nextPowerOfTwo(int v) {
  var p = 1;
  while (p < v) {
    p <<= 1;
  }
  return p;
}

class Layout {
  const Layout(this.cols, this.rows, this.frameWidth, this.frameHeight);
  final int cols;
  final int rows;
  final int frameWidth;
  final int frameHeight;
}

/// Finds the grid that fits [frameCount] frames of the given [aspect] at the
/// largest possible frame width, subject to both sheet dimensions rounding up
/// to no more than [maxSheetDimension].
///
/// Searching cols and frame width together matters: the obvious grid often
/// leaves a sheet like 1800x1650, which the driver rounds to 2048x2048 anyway.
/// Trading those wasted rows for larger frames is free.
Layout? chooseLayout(int frameCount, double aspect) {
  Layout? best;
  for (var cols = 1; cols <= frameCount; cols++) {
    final rows = (frameCount / cols).ceil();
    for (var fw = maxFrameWidth; fw >= 96; fw--) {
      final fh = (fw / aspect).round();
      if (fh < 1) continue;
      final w = _nextPowerOfTwo(cols * (fw + padding));
      final h = _nextPowerOfTwo(rows * (fh + padding));
      if (w > maxSheetDimension || h > maxSheetDimension) continue;
      if (best == null || fw > best.frameWidth) {
        best = Layout(cols, rows, fw, fh);
      }
      break; // Larger widths for this grid already failed.
    }
  }
  return best;
}

Map<String, dynamic> buildAnimation(AnimSpec spec) {
  final files = listFrames(spec.dirs);
  if (files.isEmpty) {
    stderr.writeln('  ! ${spec.name}: no source frames, skipping');
    return const {};
  }
  final picks = pickIndices(files.length, spec.keep);
  stdout.writeln('  ${spec.name}: ${files.length} source -> ${picks.length} frames');

  final frames = <img.Image>[];
  final box = Box(1 << 30, 1 << 30, -1, -1);
  for (final i in picks) {
    final im = loadRgba8(files[i]);
    frames.add(im);
    box.union(contentBox(im, spec.alphaThreshold));
  }

  final srcW = frames.first.width;
  final srcH = frames.first.height;
  // Every frame shares one crop window; a per-frame box would make the sprite
  // jitter as the trim changed from frame to frame.
  final cropW = box.width;
  final cropH = box.height;

  final aspect = cropW / cropH;
  final layout = chooseLayout(picks.length, aspect);
  if (layout == null) {
    stderr.writeln('  ! ${spec.name}: cannot fit ${picks.length} frames in a '
        '${maxSheetDimension}px sheet, lower its frame count');
    return const {};
  }
  final fw = layout.frameWidth;
  final fh = layout.frameHeight;
  final cols = layout.cols;
  final rows = layout.rows;
  final sheetW = cols * (fw + padding);
  final sheetH = rows * (fh + padding);

  final sheet = img.Image(width: sheetW, height: sheetH, numChannels: 4);
  img.fill(sheet, color: img.ColorRgba8(0, 0, 0, 0));

  for (var i = 0; i < frames.length; i++) {
    final cropped = img.copyCrop(frames[i],
        x: box.l, y: box.t, width: cropW, height: cropH);
    final scaled = img.copyResize(cropped,
        width: fw, height: fh, interpolation: img.Interpolation.average);
    img.compositeImage(
      sheet,
      scaled,
      dstX: (i % cols) * (fw + padding),
      dstY: (i ~/ cols) * (fh + padding),
      blend: img.BlendMode.direct,
    );
  }

  final path = '$outDir/${spec.name}.png';
  File(path).writeAsBytesSync(img.encodePng(sheet, level: 6));
  final kb = (File(path).lengthSync() / 1024).round();
  stdout.writeln('    -> $path  ${sheetW}x$sheetH  ${kb}KB '
      '(frame ${fw}x$fh, ${cols}c x ${rows}r)');

  return {
    'name': spec.name,
    'sheet': '${spec.name}.png',
    'frameCount': frames.length,
    'cols': cols,
    'rows': rows,
    'frameWidth': fw,
    'frameHeight': fh,
    'padding': padding,
    'fps': spec.fps,
    // The crop window in the coordinate space of the original render. The
    // painter uses it to place the trimmed sprite exactly where the untrimmed
    // frame would have landed, so trimming costs nothing visually.
    'sourceWidth': srcW,
    'sourceHeight': srcH,
    'cropX': box.l,
    'cropY': box.t,
    'cropWidth': cropW,
    'cropHeight': cropH,
  };
}

Map<String, dynamic> buildParallax() {
  final layers = <String, dynamic>{};
  Directory('$outDir/parallax').createSync(recursive: true);
  parallaxSpecs.forEach((name, targetW) {
    final src = File('assets/journey/backgrounds/parallax/$name.png');
    if (!src.existsSync()) {
      stderr.writeln('  ! missing parallax layer $name');
      return;
    }
    final im = loadRgba8(src);
    final w = math.min(targetW, im.width);
    final h = math.max(1, (im.height * w / im.width).round());
    final scaled = w == im.width
        ? im
        : img.copyResize(im,
            width: w, height: h, interpolation: img.Interpolation.average);
    final path = '$outDir/parallax/$name.png';
    File(path).writeAsBytesSync(img.encodePng(scaled, level: 6));
    final kb = (File(path).lengthSync() / 1024).round();
    stdout.writeln(
        '  parallax $name: ${im.width}x${im.height} -> ${w}x$h  ${kb}KB');
    layers[name] = {'width': w, 'height': h, 'file': 'parallax/$name.png'};
  });
  return layers;
}

void main() {
  final sw = Stopwatch()..start();
  Directory(outDir).createSync(recursive: true);

  stdout.writeln('Building parallax layers...');
  final parallax = buildParallax();

  stdout.writeln('Building sprite atlases...');
  final anims = <String, dynamic>{};
  for (final spec in specs) {
    final m = buildAnimation(spec);
    if (m.isNotEmpty) anims[spec.name] = m;
  }

  File('$outDir/manifest.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'animations': anims,
      'parallax': parallax,
    }),
  );

  var total = 0;
  for (final f
      in Directory(outDir).listSync(recursive: true).whereType<File>()) {
    total += f.lengthSync();
  }
  stdout.writeln('\nDone in ${sw.elapsed.inSeconds}s. '
      'Atlas payload: ${(total / 1024 / 1024).toStringAsFixed(1)} MB');
}
