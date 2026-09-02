// Renders a downscaled contact sheet of a built atlas over magenta, so the
// packing and the alpha channel can be eyeballed after a rebuild.
//
//   dart run tool/preview.dart exercise walk
//
// Writes build/preview_<name>.png.

import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> names) {
  if (names.isEmpty) {
    stderr.writeln('usage: dart run tool/preview.dart <atlas-name>...');
    exit(64);
  }
  Directory('build').createSync(recursive: true);
  for (final name in names) {
    final file = File('assets/journey/atlas/$name.png');
    if (!file.existsSync()) {
      stderr.writeln('no such atlas: ${file.path}');
      continue;
    }
    final atlas = img.decodePng(file.readAsBytesSync())!;
    final bg = img.Image(width: atlas.width, height: atlas.height, numChannels: 4);
    img.fill(bg, color: img.ColorRgba8(255, 0, 255, 255));
    img.compositeImage(bg, atlas);
    final out = 'build/preview_$name.png';
    File(out).writeAsBytesSync(img.encodePng(
      img.copyResize(bg, width: 900, interpolation: img.Interpolation.average),
      level: 6,
    ));
    stdout.writeln(out);
  }
}
