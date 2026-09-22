import 'dart:io';
import 'package:image/image.dart';

void main() {
  final dir = Directory('assets/images');
  final files = dir.listSync().whereType<File>().where((file) {
    final name = file.uri.pathSegments.last;
    return name.startsWith('ingredient_') && name.endsWith('.png');
  }).toList();

  if (files.isEmpty) {
    print('No ingredient PNGs found in assets/images');
    return;
  }

  for (final file in files) {
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
