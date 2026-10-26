import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart'
    show Alignment, Canvas, Color, Colors, Offset, Paint, PaintingStyle, Path, RadialGradient, Rect;
import '../../../data/models/ingredient.dart';

/// A single consistent "lit from above-left" highlight position, used by
/// every shard/debris gradient below so the whole burst reads as one
/// coherently-lit scene rather than each piece picking its own light
/// source.
const _highlightAlignment = Alignment(-0.45, -0.45);

/// The bounds every cached gradient shader below is built against — a
/// canonical unit circle centered on the origin, not each piece's actual
/// (constantly moving/growing) on-screen position. A RadialGradient's
/// [Alignment]-based center/radius are fractions of whatever bounds its
/// shader is built from, so a shader built once against this fixed unit
/// circle renders identically to one rebuilt every frame against the
/// piece's real bounds, as long as the same translate/rotate/scale that
/// would have produced those real bounds is applied to the canvas before
/// drawing (see render() below) — this is what lets every shard/debris
/// piece share one cached Shader for its whole lifetime instead of each
/// of the ~23 pieces calling the comparatively expensive
/// Gradient.createShader() every single frame.
final Rect _unitBounds = Rect.fromCircle(center: Offset.zero, radius: 1);

Color _lighten(Color c, double amount) => Color.lerp(c, Colors.white, amount)!;
Color _darken(Color c, double amount) => Color.lerp(c, Colors.black, amount)!;

/// A radial gradient from a bright highlight down to a darkened rim —
/// the same "glossy sphere" shading trick used for every round/curved
/// piece below, so flat solid fills don't read as flat paper cutouts.
/// Built once (against [_unitBounds]) and reused — see its doc.
Paint _shadedFillPaint(Color base) {
  final gradient = RadialGradient(
    center: _highlightAlignment,
    radius: 1.1,
    colors: [_lighten(base, 0.6), base, _darken(base, 0.4)],
    stops: const [0.0, 0.55, 1.0],
  );
  // With a shader set, Paint.color's RGB is ignored but its alpha still
  // modulates the shader output — this is how the fade-out is applied on
  // top of the gradient. The caller mutates just the alpha each frame,
  // never rebuilding the shader itself.
  return Paint()..shader = gradient.createShader(_unitBounds);
}

/// A radiating burst of shards at [position] — plays once two same-tier
/// items merge, between them vanishing and the next-tier item appearing
/// in their place (see MixolocoGame._tryMerge). Lives directly in the
/// physics world (plain Component, not a body) since it's purely
/// decorative and needs no simulation of its own.
///
/// A bright shockwave flash at the very start, plus shards that burst
/// outward fast and then ease off (rather than moving at a constant
/// speed), sells "exploded into the new thing" more than a plain
/// linear scatter did.
class MergeExplosionComponent extends PositionComponent {
  MergeExplosionComponent({required Vector2 position, required this.ingredient, required this.onSpawnReady, this.onFinished})
    : super(position: position, anchor: Anchor.center);

  final Ingredient ingredient;

  /// Fires once, partway through the animation — the merged-up item used
  /// to only appear once this whole effect finished playing out, which
  /// read as a bit of a wait; spawning it as soon as the initial flash
  /// fades (while the shards are still mid-flight around it) gets it on
  /// screen quicker without cutting the burst itself short.
  final void Function() onSpawnReady;
  bool _spawnFired = false;

  /// Fires once the burst has actually finished (right before this
  /// component removes itself) — distinct from [onSpawnReady], which
  /// fires early. Used by MixolocoGame to know when it's safe to treat
  /// the table as visually settled again (see its isAnimating getter).
  final void Function()? onFinished;

  Color get color => ingredient.color;

  static const _duration = 0.52;
  static const _flashDuration = 0.16;
  static const _spawnReadyAt = 0.2;
  double _elapsed = 0;

  // Bigger, fewer, rounder shards than the original spark burst — solid,
  // opaque, and colored with the ingredient that exploded (not a
  // translucent/white bubble look).
  late final List<_Shard> _shards = List.generate(16, (i) {
    final angle = _random.nextDouble() * 2 * pi;
    final speed = 1.1 + _random.nextDouble() * 2.0;
    final radius = 0.05 + _random.nextDouble() * 0.09;
    return _Shard(direction: Vector2(cos(angle), sin(angle)), speed: speed, radius: radius);
  });

  // A handful of bigger, shaped bits matching what the ingredient
  // actually is — a broken-glass fragment for anything poured/served in
  // a glass, a curled peel for a citrus/berry fruit, a leaf for the
  // peppermint (see [ingredient]'s DebrisType) — scattered alongside the
  // plain round shards for real shape variety instead of just bubbles.
  late final List<_Debris> _debris = List.generate(7, (i) {
    final angle = _random.nextDouble() * 2 * pi;
    final speed = 0.9 + _random.nextDouble() * 1.7;
    final size = 0.07 + _random.nextDouble() * 0.05;
    final spin = (_random.nextDouble() - 0.5) * 7;
    return _Debris(direction: Vector2(cos(angle), sin(angle)), speed: speed, size: size, spin: spin);
  });

  static final _random = Random();

  // Every gradient-filled piece in this burst shares just two cached
  // Shaders (ingredient-colored "glossy" and the fixed glass-blue one) —
  // see _shadedFillPaint's doc for why reusing one Paint, translated/
  // scaled per piece at draw time, renders identically to building a
  // fresh one per piece per frame.
  late final Paint _glossyPaint = _shadedFillPaint(color);
  late final Paint _glassFillPaint = _shadedFillPaint(_glassBase);
  final Paint _glassEdgePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.12;
  final Paint _leafVeinPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.06;

  static const _glassBase = Color(0xFFBEE3F0);

  // Canonical (size=1) local-space paths — each debris piece's actual
  // [_Debris.size] is applied as a canvas scale at draw time instead of
  // being baked into the path, so every piece of a given shape reuses
  // the exact same Path object too.
  static final Path _glassShardPath = Path()
    ..moveTo(0, -1)
    ..lineTo(0.65, 0.25)
    ..lineTo(-0.35, 0.55)
    ..close();
  static final Path _peelPath = Path()
    ..addArc(_unitBounds, -1.0, 2.6)
    ..arcTo(Rect.fromCircle(center: Offset.zero, radius: 0.5), 1.6, -2.6, false)
    ..close();
  static final Path _leafPath = Path()
    ..moveTo(0, -1)
    ..quadraticBezierTo(0.7, 0, 0, 1)
    ..quadraticBezierTo(-0.7, 0, 0, -1)
    ..close();

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (!_spawnFired && _elapsed >= _spawnReadyAt) {
      _spawnFired = true;
      onSpawnReady();
    }
    if (_elapsed >= _duration) {
      onFinished?.call();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final t = (_elapsed / _duration).clamp(0.0, 1.0);

    if (_elapsed < _flashDuration) {
      final flashT = (_elapsed / _flashDuration).clamp(0.0, 1.0);
      final ringPaint = Paint()
        ..color = Colors.white.withValues(alpha: (1 - flashT) * 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.03 * (1 - flashT * 0.5);
      canvas.drawCircle(Offset.zero, 0.03 + flashT * 0.24, ringPaint);
      final corePaint = Paint()..color = Colors.white.withValues(alpha: 1 - flashT);
      canvas.drawCircle(Offset.zero, 0.08 * (1 - flashT), corePaint);
    }

    // Ease-out: a sharp initial burst that settles, rather than constant
    // speed all the way through. Shards also swell slightly as they fly
    // outward before shrinking away at the very end, instead of just
    // shrinking the whole time.
    final easedT = 1 - pow(1 - t, 2).toDouble();
    final growth = t < 0.35 ? (1 + t / 0.35 * 0.25) : (1.25 - (t - 0.35) / 0.65 * 0.85);
    for (final shard in _shards) {
      final dist = shard.speed * easedT * _duration;
      final pos = shard.direction * dist;
      final r = shard.radius * growth.clamp(0.0, 1.25);
      // Opaque the whole time it's flying — only fades right at the very
      // end, rather than being translucent throughout.
      final alpha = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(pos.x, pos.y);
      canvas.scale(r);
      _glossyPaint.color = Colors.black.withValues(alpha: alpha);
      canvas.drawCircle(Offset.zero, 1, _glossyPaint);
      canvas.restore();
    }

    final debrisAlpha = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2).clamp(0.0, 1.0);
    for (final d in _debris) {
      final dist = d.speed * easedT * _duration;
      final pos = d.direction * dist;
      canvas.save();
      canvas.translate(pos.x, pos.y);
      canvas.rotate(d.spin * t * _duration);
      canvas.scale(d.size);
      _renderDebrisShape(canvas, debrisAlpha);
      canvas.restore();
    }
  }

  void _renderDebrisShape(Canvas canvas, double alpha) {
    switch (ingredient.debris) {
      case DebrisType.glass:
        _renderGlassShard(canvas, alpha);
      case DebrisType.peel:
        _renderPeel(canvas, alpha);
      case DebrisType.leaf:
        _renderLeaf(canvas, alpha);
    }
  }

  /// A jagged little triangle rendered pale/translucent (like actual
  /// glass, not the ingredient's own color), shaded like a faceted chip
  /// catching the light rather than a flat translucent flag. Canvas is
  /// already translated/rotated/scaled to this piece's position/spin/
  /// size by render() above, so everything here draws in canonical
  /// (size=1) local space.
  void _renderGlassShard(Canvas canvas, double alpha) {
    _glassFillPaint.color = Colors.black.withValues(alpha: alpha * 0.6);
    canvas.drawPath(_glassShardPath, _glassFillPaint);
    _glassEdgePaint.color = Colors.white.withValues(alpha: alpha * 0.85);
    canvas.drawPath(_glassShardPath, _glassEdgePaint);
  }

  /// A thin curled crescent in the fruit's own color, like a peeled
  /// strip — shaded so the curl itself reads as rolled/3D rather than a
  /// flat cutout.
  void _renderPeel(Canvas canvas, double alpha) {
    _glossyPaint.color = Colors.black.withValues(alpha: alpha);
    canvas.drawPath(_peelPath, _glossyPaint);
  }

  /// A small pointed leaf with a center vein.
  void _renderLeaf(Canvas canvas, double alpha) {
    _glossyPaint.color = Colors.black.withValues(alpha: alpha);
    canvas.drawPath(_leafPath, _glossyPaint);
    _leafVeinPaint.color = Colors.black.withValues(alpha: alpha * 0.3);
    canvas.drawLine(const Offset(0, -0.8), const Offset(0, 0.8), _leafVeinPaint);
  }
}

class _Shard {
  final Vector2 direction;
  final double speed;
  final double radius;
  _Shard({required this.direction, required this.speed, required this.radius});
}

class _Debris {
  final Vector2 direction;
  final double speed;
  final double size;
  final double spin;
  _Debris({required this.direction, required this.speed, required this.size, required this.spin});
}
