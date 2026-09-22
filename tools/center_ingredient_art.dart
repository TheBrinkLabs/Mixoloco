import 'dart:io';
import 'package:image/image.dart' as img;

/// Several ingredient PNGs have their actual drink/glass artwork sitting
/// off-center within their own canvas (asymmetric transparent padding) —
/// harmless for a full-bleed image, but visible once BoxFit.contain
/// centers the *whole image rectangle* in a small icon box: the padding
/// asymmetry reads as the drink itself being off-center. This crops each
/// ingredient PNG tight to its actual (alpha > threshold) content, then
/// re-pads it symmetrically, so centering the image always centers the
/// drink.
void main() {
  final dir = Directory('assets/images');
  const cocktailFiles = {
    'mohito.png',
    'screwdriver.png',
    'rum_and_coke.png',
    'rum_punch.png',
    'vodka_tonic.png',
    'cosmopolitan.png',
  };
  final files = dir.listSync().whereType<File>().where((file) {
    final name = file.uri.pathSegments.last;
    return (name.startsWith('ingredient_') && name.endsWith('.png')) || cocktailFiles.contains(name);
  }).toList();

  const marginFraction = 0.06; // breathing room on each side, relative to content size

  for (final file in files) {
    final bytes = file.readAsBytesSync();
    final image = img.decodePng(bytes);
    if (image == null) {
      print('Skipped ${file.path}: could not decode PNG');
      continue;
    }

    final w = image.width, h = image.height;
    var minX = w, maxX = -1, minY = h, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (image.getPixel(x, y).a > 15) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) {
      print('Skipped ${file.path}: no opaque content found');
      continue;
    }

    final leftPad = minX, rightPad = w - 1 - maxX, topPad = minY, bottomPad = h - 1 - maxY;
    // Already symmetric within a couple px (both axes) — leave it alone.
    if ((leftPad - rightPad).abs() <= 2 && (topPad - bottomPad).abs() <= 2) {
      print('OK already centered: ${file.path}');
      continue;
    }

    final contentW = maxX - minX + 1, contentH = maxY - minY + 1;
    final cropped = img.copyCrop(image, x: minX, y: minY, width: contentW, height: contentH);

    final marginX = (contentW * marginFraction).round();
    final marginY = (contentH * marginFraction).round();
    final canvas = img.Image(width: contentW + marginX * 2, height: contentH + marginY * 2, numChannels: 4);
    img.compositeImage(canvas, cropped, dstX: marginX, dstY: marginY);

    file.writeAsBytesSync(img.encodePng(canvas));
    print(
      'Recentered ${file.path}: was leftPad=$leftPad rightPad=$rightPad '
      'topPad=$topPad bottomPad=$bottomPad -> ${canvas.width}x${canvas.height}',
    );
  }
}
