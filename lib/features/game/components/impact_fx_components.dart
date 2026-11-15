import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Decorative impact effects for the power-ups and cocktails — plain
/// components in the physics world (sized in metres, like
/// MergeExplosionComponent), purely visual: they never hold the game up
/// (nothing waits on them via MixolocoGame.isAnimating).

/// A Bomb hit: a hot orange flash and sparks where an item was, then a
/// grey cloud of smoke that billows out and fades. Scaled to the
/// removed item's [radius].
class BlastComponent extends PositionComponent {
  BlastComponent({required Vector2 position, required this.radius, double delay = 0})
    : _elapsed = -delay,
      super(position: position);

  final double radius;
  double _elapsed;

  static const _flashDuration = 0.22;
  static const _duration = 1.3;
  static final _random = Random();

  late final List<_Spark> _sparks = List.generate(12, (_) {
    final angle = _random.nextDouble() * 2 * pi;
    return _Spark(Vector2(cos(angle), sin(angle)), 2.2 + _random.nextDouble() * 2.6, 0.18 + _random.nextDouble() * 0.2);
  });
  late final List<_Puff> _puffs = List.generate(7, (_) {
    final angle = _random.nextDouble() * 2 * pi;
    return _Puff(
      Vector2(cos(angle), sin(angle)) * (0.25 + _random.nextDouble() * 0.55),
      0.45 + _random.nextDouble() * 0.35,
      0.55 + _random.nextDouble() * 0.25,
    );
  });

  final _paint = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (_elapsed < 0) return;
    final r = radius;
    final t = (_elapsed / _duration).clamp(0.0, 1.0);

    // Smoke first, so the fire draws over it while both are showing.
    for (final p in _puffs) {
      final grow = Curves.easeOut.transform(t);
      final centre = p.offset * r * (0.6 + grow * 1.4);
      // Drifts a little toward the top of the screen as it billows.
      final drift = Offset(centre.x, centre.y - grow * r * 0.6);
      final alpha = (t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85).clamp(0.0, 1.0) * p.shade;
      _paint
        ..shader = null
        ..color = Color.fromRGBO(95, 90, 88, alpha * 0.85)
        ..maskFilter = null;
      canvas.drawCircle(drift, r * p.size * (0.7 + grow * 1.1), _paint);
    }

    if (_elapsed < _flashDuration) {
      final f = (_elapsed / _flashDuration).clamp(0.0, 1.0);
      _paint
        ..color = Colors.white
        ..shader = ui.Gradient.radial(Offset.zero, r * (0.8 + f * 1.2), [
          const Color(0xFFFFF6C8).withValues(alpha: 1 - f),
          const Color(0xFFFFA726).withValues(alpha: (1 - f) * 0.95),
          const Color(0xFFE64A19).withValues(alpha: 0),
        ], [0.0, 0.45, 1.0]);
      canvas.drawCircle(Offset.zero, r * (0.8 + f * 1.2), _paint);
      _paint.shader = null;
    }

    final sparkT = (_elapsed / 0.6).clamp(0.0, 1.0);
    if (sparkT < 1) {
      final eased = Curves.easeOut.transform(sparkT);
      for (final s in _sparks) {
        final pos = s.direction * r * s.speed * eased;
        _paint.color = Color.lerp(const Color(0xFFFFE082), const Color(0xFFFF7043), sparkT)!.withValues(alpha: 1 - sparkT);
        canvas.drawCircle(pos.toOffset(), r * s.size * (1 - sparkT * 0.6), _paint);
      }
    }
  }
}

class _Spark {
  final Vector2 direction;
  final double speed;
  final double size;
  _Spark(this.direction, this.speed, this.size);
}

class _Puff {
  final Vector2 offset;
  final double size;
  final double shade;
  _Puff(this.offset, this.size, this.shade);
}

/// A big arcade-style word ("SLAM!", "MIXOLOCO!") stamped over the table:
/// chunky white letters with a thick dark-red outline, tilted, popping in
/// with an overshoot, with a ring and sparkles bursting behind it, then
/// fading out. [height] is the letters' cap height in metres; a word wider
/// than [maxWidth] metres is shrunk to fit.
class StampTextComponent extends PositionComponent {
  StampTextComponent({required this.text, required Vector2 position, this.height = 0.6, this.tilt = -0.14, this.maxWidth = double.infinity, double delay = 0})
    : _elapsed = -delay,
      super(position: position);

  final String text;
  final double height;
  final double tilt;
  final double maxWidth;
  double _elapsed;

  static const _duration = 1.4;
  static const _popDuration = 0.28;
  static const _layoutSize = 100.0;
  static final _random = Random();

  // Laid out once at a large size and scaled down at draw time, so the
  // glyphs are rasterised at their on-screen size, not at a fraction of
  // a metre.
  late final TextPainter _stroke = _painter(
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _layoutSize * 0.16
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF8E1B12),
  );
  late final TextPainter _fill = _painter(Paint()..color = Colors.white);
  late final List<double> _sparkleAngles = List.generate(8, (_) => _random.nextDouble() * 2 * pi);

  TextPainter _painter(Paint foreground) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontFamily: 'Lilita One', fontSize: _layoutSize, foreground: foreground, height: 1),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _duration) removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    if (_elapsed < 0) return;
    final t = (_elapsed / _duration).clamp(0.0, 1.0);
    final pop = (_elapsed / _popDuration).clamp(0.0, 1.0);
    final scale = Curves.elasticOut.transform(pop).clamp(0.0, 1.3);
    final alpha = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
    final unit = min(height / _layoutSize, maxWidth / _fill.width);
    final h = unit * _layoutSize; // effective letter height after any shrink-to-fit
    final width = _fill.width * unit;

    // Ring and sparkles behind the word.
    final ringT = Curves.easeOut.transform((_elapsed / 0.6).clamp(0.0, 1.0));
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.06
      ..color = const Color(0xFFFFF3C4).withValues(alpha: (1 - ringT) * 0.9);
    canvas.drawCircle(Offset.zero, width * (0.25 + ringT * 0.45), ringPaint);
    final sparklePaint = Paint()..color = const Color(0xFFFFD54F).withValues(alpha: (1 - ringT) * alpha);
    for (final a in _sparkleAngles) {
      final d = width * (0.3 + ringT * 0.5);
      _drawSparkle(canvas, Offset(cos(a) * d, sin(a) * d), h * 0.12 * (1 - ringT * 0.5), sparklePaint);
    }

    canvas.save();
    canvas.rotate(tilt);
    canvas.scale(scale * unit);
    canvas.translate(-_fill.width / 2, -_fill.height / 2);
    // A soft drop shadow, the outline, then the white face.
    canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: alpha));
    canvas.save();
    canvas.translate(_layoutSize * 0.04, _layoutSize * 0.07);
    _stroke.paint(canvas, Offset.zero);
    canvas.restore();
    _stroke.paint(canvas, Offset.zero);
    _fill.paint(canvas, Offset.zero);
    canvas.restore();
    canvas.restore();
  }

  /// A four-pointed twinkle.
  void _drawSparkle(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }
}
