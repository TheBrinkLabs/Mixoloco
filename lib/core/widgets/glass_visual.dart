import 'package:flutter/material.dart';
import '../../data/models/ingredient.dart';

/// Renders one ingredient as a stylized glass/jug/mug — code-drawn (no
/// image asset) so it costs nothing to spin up dozens of these on the
/// bar at once. Prefers [Ingredient.assetPath] once real art exists for
/// a given ingredient, so callers never need to change when that swap
/// happens piece by piece.
class GlassVisual extends StatelessWidget {
  final Ingredient ingredient;
  final double size;

  const GlassVisual({super.key, required this.ingredient, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final assetPath = ingredient.assetPath;
    if (assetPath != null) {
      final image = Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // A real asset failing to load at runtime (a flaky fetch, not a
        // missing file) shouldn't leave a blank gap — fall back to the
        // drawn glass the same way an ingredient with no art at all does.
        errorBuilder: (context, error, stackTrace) => _drawn,
      );
      // Some photos are naturally tall/narrow and read as smaller than
      // rounder ones once fit into the same square box — displayScale
      // compensates, scaling in place so it doesn't shift neighbors.
      // displayScaleX stretches width only, on top of that, so this
      // preview matches the (non-uniformly stretched) art on the table —
      // see Ingredient.displayScaleX's doc comment for why.
      final scaleX = ingredient.displayScale * ingredient.displayScaleX;
      final scaleY = ingredient.displayScale;
      if (scaleX == 1.0 && scaleY == 1.0) return image;
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
        child: image,
      );
    }
    return _drawn;
  }

  Widget get _drawn => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: GlassPainter(shape: ingredient.shape, liquidColor: ingredient.color),
    ),
  );
}

/// Draws one stylized glass/jug/mug. Public so the Flame-side game
/// components (thrown/settled glasses on the board) can paint with the
/// exact same code instead of re-implementing the vessel art.
class GlassPainter extends CustomPainter {
  final GlassShape shape;
  final Color liquidColor;

  GlassPainter({required this.shape, required this.liquidColor});

  // Thin, semi-transparent stroke reading as "glass material" around
  // whatever liquid shape sits inside it — shared by every vessel shape.
  Paint get _glassStroke => Paint()
    ..color = Colors.white.withValues(alpha: 0.55)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6;

  Paint _glassFill() => Paint()..color = Colors.white.withValues(alpha: 0.06);

  @override
  void paint(Canvas canvas, Size size) {
    switch (shape) {
      case GlassShape.tumbler:
        _paintTumbler(canvas, size);
      case GlassShape.martini:
        _paintMartini(canvas, size);
      case GlassShape.jug:
        _paintJug(canvas, size);
      case GlassShape.mug:
        _paintMug(canvas, size);
    }
  }

  // A liquid fill with a lighter band near the top — reads as light
  // catching the surface, without needing a real reflection/shader.
  Shader _liquidShader(Rect bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(liquidColor, Colors.white, 0.35)!,
          liquidColor,
          Color.lerp(liquidColor, Colors.black, 0.15)!,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(bounds);

  void _shine(Canvas canvas, Path clip) {
    canvas.save();
    canvas.clipPath(clip);
    final shinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rect = clip.getBounds();
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.28, rect.top + rect.height * 0.1),
      Offset(rect.left + rect.width * 0.2, rect.bottom - rect.height * 0.15),
      shinePaint,
    );
    canvas.restore();
  }

  void _paintTumbler(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final glass = Path()
      ..moveTo(w * 0.22, h * 0.08)
      ..lineTo(w * 0.78, h * 0.08)
      ..lineTo(w * 0.68, h * 0.95)
      ..lineTo(w * 0.32, h * 0.95)
      ..close();

    canvas.drawPath(glass, _glassFill());
    final liquidPaint = Paint()..shader = _liquidShader(glass.getBounds());
    canvas.drawPath(glass, liquidPaint);
    _shine(canvas, glass);
    canvas.drawPath(glass, _glassStroke);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.08), width: w * 0.56, height: h * 0.05),
        Paint()..color = Colors.white.withValues(alpha: 0.25));
  }

  void _paintMartini(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bowl = Path()
      ..moveTo(w * 0.08, h * 0.1)
      ..lineTo(w * 0.92, h * 0.1)
      ..lineTo(w * 0.5, h * 0.55)
      ..close();
    final stem = Rect.fromCenter(center: Offset(w * 0.5, h * 0.72), width: w * 0.05, height: h * 0.28);
    final base = Rect.fromCenter(center: Offset(w * 0.5, h * 0.95), width: w * 0.4, height: h * 0.045);

    canvas.drawPath(bowl, _glassFill());
    final liquidPaint = Paint()..shader = _liquidShader(bowl.getBounds());
    canvas.drawPath(bowl, liquidPaint);
    _shine(canvas, bowl);
    canvas.drawPath(bowl, _glassStroke);
    canvas.drawRect(stem, _glassStroke);
    canvas.drawRRect(RRect.fromRectAndRadius(base, const Radius.circular(3)), _glassStroke);
  }

  void _paintJug(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.18, h * 0.18, w * 0.64, h * 0.78),
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(6),
      bottomLeft: const Radius.circular(14),
      bottomRight: const Radius.circular(14),
    );
    final spout = Path()
      ..moveTo(w * 0.66, h * 0.18)
      ..lineTo(w * 0.86, h * 0.06)
      ..lineTo(w * 0.9, h * 0.14)
      ..lineTo(w * 0.78, h * 0.22)
      ..close();
    final handle = Rect.fromLTWH(w * 0.02, h * 0.32, w * 0.2, h * 0.38);

    final bodyPath = Path()..addRRect(body);
    canvas.drawPath(bodyPath, _glassFill());
    final liquidPaint = Paint()..shader = _liquidShader(body.outerRect);
    canvas.drawRRect(body, liquidPaint);
    _shine(canvas, bodyPath);
    canvas.drawRRect(body, _glassStroke);
    canvas.drawPath(spout, _glassFill());
    canvas.drawPath(spout, _glassStroke);
    canvas.drawArc(handle, -1.7, 3.0, false, _glassStroke);
  }

  void _paintMug(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.2, h * 0.12, w * 0.58, h * 0.82),
      const Radius.circular(8),
    );
    final handle = Rect.fromLTWH(w * 0.62, h * 0.28, w * 0.28, h * 0.44);

    final bodyPath = Path()..addRRect(body);
    canvas.drawPath(bodyPath, _glassFill());
    final liquidPaint = Paint()..shader = _liquidShader(body.outerRect);
    canvas.drawRRect(body, liquidPaint);
    _shine(canvas, bodyPath);
    canvas.drawRRect(body, _glassStroke);
    canvas.drawArc(handle, -1.4, 2.6, false, _glassStroke);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * 0.49, h * 0.12), width: w * 0.5, height: h * 0.05),
        Paint()..color = Colors.white.withValues(alpha: 0.25));
  }

  @override
  bool shouldRepaint(covariant GlassPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.liquidColor != liquidColor;
}
