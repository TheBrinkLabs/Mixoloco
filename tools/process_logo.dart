import 'dart:io';
import 'package:image/image.dart' as img;

/// One-off: converts the sourced mixoloco.jpg (white background, JPG —
/// no alpha) into a trimmed, transparent-background PNG matching how
/// every other placed-art asset in the game is prepared (see
/// remove_white_background.dart / center_ingredient_art.dart).
void main() {
  final bytes = File('assets/images/mixoloco.jpg').readAsBytesSync();
  final source = img.decodeJpg(bytes)!;
  final image = source.convert(numChannels: 4);

  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      if (p.r >= 245 && p.g >= 245 && p.b >= 245) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
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

  const margin = 14;
  final cropX = (minX - margin).clamp(0, w - 1);
  final cropY = (minY - margin).clamp(0, h - 1);
  final cropW = (maxX - cropX + margin).clamp(1, w - cropX);
  final cropH = (maxY - cropY + margin).clamp(1, h - cropY);
  final cropped = img.copyCrop(image, x: cropX, y: cropY, width: cropW, height: cropH);

  File('assets/images/mixoloco_logo.png').writeAsBytesSync(img.encodePng(cropped));
  print('wrote assets/images/mixoloco_logo.png: ${cropped.width}x${cropped.height}');
}
