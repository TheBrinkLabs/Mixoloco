import 'dart:io';
import 'dart:math';
import 'package:image/image.dart';

void main() {
  final outDir = Directory('assets/images');
  outDir.createSync(recursive: true);

  final specs = [
    _DrinkSpec('ingredient_orange.png', ColorRgb8(255, 150, 0), garnish: 'slice'),
    _DrinkSpec('ingredient_lime.png', ColorRgb8(174, 240, 92), garnish: 'slice'),
    _DrinkSpec('ingredient_cola.png', ColorRgb8(92, 35, 15), garnish: 'ice'),
    _DrinkSpec('ingredient_soda.png', ColorRgb8(227, 244, 248), garnish: 'slice'),
    _DrinkSpec('ingredient_rum.png', ColorRgb8(196, 117, 54), garnish: 'slice'),
    _DrinkSpec('ingredient_vodka.png', ColorRgb8(236, 243, 247), garnish: 'slice'),
    _DrinkSpec('ingredient_lemon.png', ColorRgb8(247, 212, 83), garnish: 'slice'),
    _DrinkSpec('ingredient_cranberry.png', ColorRgb8(212, 62, 103), garnish: 'cherry'),
    _DrinkSpec('ingredient_tonic.png', ColorRgb8(225, 243, 247), garnish: 'slice'),
    _DrinkSpec('ingredient_mint.png', ColorRgb8(35, 170, 92), garnish: 'leaf'),
  ];

  for (final spec in specs) {
    final image = _buildDrink(spec);
    File('${outDir.path}/${spec.filename}').writeAsBytesSync(encodePng(image));
    print('created ${spec.filename}');
  }
}

Image _buildDrink(_DrinkSpec spec) {
  final image = Image(width: 640, height: 640, numChannels: 4);
  fill(image, color: ColorRgba8(0, 0, 0, 0));

  final glassColor = ColorRgba8(206, 226, 245, 175);
  final glassEdge = ColorRgba8(82, 102, 128, 220);
  final liquidColor = ColorRgba8(
    spec.liquid.r.toInt(),
    spec.liquid.g.toInt(),
    spec.liquid.b.toInt(),
    220,
  );

  drawRect(
    image,
    x1: 110,
    y1: 120,
    x2: 530,
    y2: 540,
    color: glassColor,
    radius: 42,
  );
  drawRect(
    image,
    x1: 110,
    y1: 120,
    x2: 530,
    y2: 540,
    color: glassEdge,
    thickness: 12,
    radius: 42,
  );

  drawRect(
    image,
    x1: 150,
    y1: 160,
    x2: 490,
    y2: 500,
    color: liquidColor,
    radius: 34,
  );

  for (var y = 170; y <= 500; y += 12) {
    final alpha = (190 - ((y - 170) / 330 * 110)).round().clamp(30, 180);
    drawLine(
      image,
      x1: 180,
      y1: y,
      x2: 460,
      y2: y,
      color: ColorRgba8(255, 255, 255, alpha),
      thickness: 3,
    );
  }

  final ice = <({int x, int y, int w, int h})>[
    (x: 165, y: 205, w: 92, h: 92),
    (x: 265, y: 240, w: 100, h: 100),
    (x: 390, y: 185, w: 82, h: 82),
    (x: 210, y: 330, w: 102, h: 102),
    (x: 350, y: 332, w: 92, h: 92),
  ];
  for (final block in ice) {
    drawRect(
      image,
      x1: block.x,
      y1: block.y,
      x2: block.x + block.w,
      y2: block.y + block.h,
      color: ColorRgba8(220, 230, 248, 220),
      radius: 14,
    );
    drawRect(
      image,
      x1: block.x + 10,
      y1: block.y + 10,
      x2: block.x + block.w - 10,
      y2: block.y + block.h - 10,
      color: ColorRgba8(150, 170, 190, 170),
      thickness: 4,
      radius: 10,
    );
    drawLine(
      image,
      x1: block.x + 20,
      y1: block.y + 25,
      x2: block.x + block.w - 20,
      y2: block.y + block.h - 25,
      color: ColorRgba8(170, 190, 210, 170),
    );
    drawLine(
      image,
      x1: block.x + 20,
      y1: block.y + block.h - 25,
      x2: block.x + block.w - 20,
      y2: block.y + 25,
      color: ColorRgba8(170, 190, 210, 170),
    );
  }

  switch (spec.garnish) {
    case 'slice':
      drawCircle(image, x: 420, y: 80, radius: 56, color: ColorRgba8(255, 200, 0, 255));
      drawCircle(image, x: 420, y: 80, radius: 28, color: ColorRgba8(255, 255, 255, 96));
      drawLine(image, x1: 420, y1: 24, x2: 420, y2: 132, color: ColorRgba8(228, 120, 30, 255));
      drawLine(image, x1: 370, y1: 80, x2: 470, y2: 80, color: ColorRgba8(228, 120, 30, 255));
      break;
    case 'cherry':
      drawCircle(image, x: 420, y: 78, radius: 34, color: ColorRgba8(170, 10, 30, 255));
      drawLine(image, x1: 420, y1: 38, x2: 420, y2: 120, color: ColorRgba8(90, 0, 0, 200));
      break;
    case 'leaf':
      drawCircle(image, x: 420, y: 80, radius: 28, color: ColorRgba8(35, 170, 92, 255));
      for (var i = 0; i < 5; i++) {
        final angle = i * (pi / 2.5);
        final x = 420 + (cos(angle) * 34).round();
        final y = 80 + (sin(angle) * 34).round();
        drawLine(image, x1: 420, y1: 80, x2: x, y2: y, color: ColorRgba8(18, 110, 60, 255));
      }
      break;
    case 'ice':
      drawRect(
        image,
        x1: 360,
        y1: 60,
        x2: 480,
        y2: 180,
        color: ColorRgba8(210, 220, 255, 255),
        radius: 18,
      );
      drawRect(
        image,
        x1: 360,
        y1: 60,
        x2: 480,
        y2: 180,
        color: ColorRgba8(120, 150, 170, 255),
        thickness: 5,
        radius: 18,
      );
      break;
    default:
      break;
  }

  drawLine(image, x1: 150, y1: 120, x2: 490, y2: 120, color: ColorRgba8(255, 255, 255, 120));
  drawLine(image, x1: 250, y1: 20, x2: 250, y2: 150, color: ColorRgba8(255, 145, 0, 255));
  drawLine(image, x1: 235, y1: 20, x2: 265, y2: 20, color: ColorRgba8(255, 160, 70, 255));

  return image;
}

class _DrinkSpec {
  final String filename;
  final ColorRgb8 liquid;
  final String garnish;

  const _DrinkSpec(this.filename, this.liquid, {required this.garnish});
}
