import 'dart:io';
import 'package:image/image.dart';

/// One-off: play.png/about.png (the new Songs/About tile icons) came
/// with an opaque white background instead of a transparent one, unlike
/// every other tile icon (shop.png, settings.png, info.png, ...) — same
/// near-white-to-transparent technique as remove_white_background.dart,
/// just scoped to these two specific files instead of every
/// ingredient_*.png.
void main() {
  for (final name in ['play.png', 'about.png']) {
    final file = File('assets/images/$name');
    final image = decodePng(file.readAsBytesSync());
    if (image == null) {
      print('Skipped ${file.path}: could not decode PNG');
      continue;
    }
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        final isNearWhite = pixel.r >= 245 && pixel.g >= 245 && pixel.b >= 245;
        if (isNearWhite) {
          pixel.a = 0;
          pixel.r = 0;
          pixel.g = 0;
          pixel.b = 0;
        }
      }
    }
    file.writeAsBytesSync(encodePng(image));
    print('Processed ${file.path}');
  }
}
