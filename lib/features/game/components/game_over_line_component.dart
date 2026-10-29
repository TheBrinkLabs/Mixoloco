import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart' show Canvas, Color, Paint, PaintingStyle, Path, StrokeCap;

/// A line across the table marking where a settled pile ends the game —
/// see MixolocoGame._checkOverflow / kGameOverLineFraction. Used to be an
/// entirely invisible rule the player could only discover by losing;
/// this makes the danger zone visible up front. Drawn as a faint wavy
/// scorch mark burnt into the wood, not a bright/dashed warning line, so
/// it reads as part of the table rather than a UI overlay.
class GameOverLineComponent extends PositionComponent {
  GameOverLineComponent({required double worldWidth, required double lineY}) : super(position: Vector2(0, lineY), size: Vector2(worldWidth, 0)) {
    _path = _buildScorchPath();
  }

  late final Path _path;

  /// A fixed seed — the wobble should look natural but stay put, not
  /// re-randomize (and visually jump) every time geometry recalculates
  /// and this component gets rebuilt.
  Path _buildScorchPath() {
    final random = Random(7);
    final path = Path();
    const step = 0.09;
    var x = 0.0;
    var y = (random.nextDouble() - 0.5) * 0.02;
    path.moveTo(x, y);
    while (x < size.x) {
      x += step;
      y += (random.nextDouble() - 0.5) * 0.024;
      y = y.clamp(-0.032, 0.032);
      path.lineTo(x.clamp(0.0, size.x), y);
    }
    return path;
  }

  static final _glowOuter = Paint()
    ..color = const Color(0x262A1B12)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.09
    ..strokeCap = StrokeCap.round;
  static final _glowInner = Paint()
    ..color = const Color(0x332A1B12)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    // A soft diffuse scorch glow underneath the mark itself — two
    // widening faint strokes rather than a blur (a blur is a separate
    // render pass every frame on Impeller).
    canvas.drawPath(_path, _glowOuter);
    canvas.drawPath(_path, _glowInner);

    // ...and a darker, thinner charred line on top of it.
    final linePaint = Paint()
      ..color = const Color(0xD91A1108)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.016
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(_path, linePaint);
  }
}
