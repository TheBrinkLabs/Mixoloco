import 'dart:io';
import 'package:image/image.dart' as img;

/// One-off: the sourced mixoloco_icon.png has its actual squircle
/// content filling only ~38% of a non-square 1408x768 canvas — far
/// short of standard app-icon fill guidelines (content should fill most
/// of the tile). This crops tight to the real content, then pads it
/// into a square canvas with a small, even margin, ready for
/// flutter_launcher_icons to mask/resize per-platform.
void main() {
  final image = img.decodePng(File('assets/images/mixoloco_icon.png').readAsBytesSync())!;
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
  final contentW = maxX - minX + 1;
  final contentH = maxY - minY + 1;
  final cropped = img.copyCrop(image, x: minX, y: minY, width: contentW, height: contentH);

  const marginFraction = 0.06;
  final side = (contentW > contentH ? contentW : contentH);
  final canvasSide = (side * (1 + marginFraction * 2)).round();
  final canvas = img.Image(width: canvasSide, height: canvasSide, numChannels: 4);
  final dstX = (canvasSide - contentW) ~/ 2;
  final dstY = (canvasSide - contentH) ~/ 2;
  img.compositeImage(canvas, cropped, dstX: dstX, dstY: dstY);

  File('assets/images/mixoloco_icon_square.png').writeAsBytesSync(img.encodePng(canvas));
  print('wrote assets/images/mixoloco_icon_square.png: ${canvas.width}x${canvas.height}');
}
