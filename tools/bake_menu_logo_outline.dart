import 'dart:io';
import 'package:image/image.dart' as img;

/// One-off: bakes the new main-menu's "sticker" treatment (a 3px white
/// outline, then a 6px-down navy under-shadow) directly into a copy of
/// mixoloco_logo.png, per the menu redesign handoff's own recommended
/// approach ("bake the outline into the PNG" rather than build it from
/// stacked layers at runtime). Source art is unchanged; this only adds a
/// new derived asset.
void main() {
  final bytes = File('assets/images/mixoloco_logo.png').readAsBytesSync();
  final source = img.decodePng(bytes)!;
  final src = source.convert(numChannels: 4);

  const outlineWidth = 3;
  const shadowOffsetX = 0;
  const shadowOffsetY = 6;
  const navy = [0x17, 0x3A, 0x5E];
  const padding = outlineWidth + shadowOffsetY + 2;

  final w = src.width, h = src.height;
  final canvasW = w + padding * 2;
  final canvasH = h + padding * 2;

  final mask = List.generate(
    h,
    (y) => List.generate(w, (x) => src.getPixel(x, y).a > 40),
  );

  bool nearOpaque(int x, int y, int radius) {
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        if (dx * dx + dy * dy > radius * radius) continue;
        final nx = x + dx, ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < w && ny < h && mask[ny][nx]) return true;
      }
    }
    return false;
  }

  // 3px white ring: every transparent source pixel within outlineWidth of
  // an opaque one.
  final outlineLayer = img.Image(width: canvasW, height: canvasH, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (!mask[y][x] && nearOpaque(x, y, outlineWidth)) {
        outlineLayer.setPixelRgba(x + padding, y + padding, 255, 255, 255, 255);
      }
    }
  }

  // Navy under-shadow: the full silhouette (logo + ring), offset down,
  // painted first so only the part peeking out past the ring/logo shows.
  final shadowLayer = img.Image(width: canvasW, height: canvasH, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (mask[y][x] || nearOpaque(x, y, outlineWidth)) {
        shadowLayer.setPixelRgba(
          x + padding + shadowOffsetX,
          y + padding + shadowOffsetY,
          navy[0],
          navy[1],
          navy[2],
          255,
        );
      }
    }
  }

  final result = img.Image(width: canvasW, height: canvasH, numChannels: 4);
  img.compositeImage(result, shadowLayer);
  img.compositeImage(result, outlineLayer);
  img.compositeImage(result, src, dstX: padding, dstY: padding);

  File('assets/images/menu_logo_sticker.png').writeAsBytesSync(img.encodePng(result));
  print('wrote assets/images/menu_logo_sticker.png: ${result.width}x${result.height}');
}
