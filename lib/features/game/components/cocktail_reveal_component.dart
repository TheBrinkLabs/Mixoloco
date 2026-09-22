import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/extensions.dart';
import 'package:flutter/material.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../data/models/ingredient.dart';
import 'ingredient_sprite.dart';

/// One captured ingredient piece's starting point for the cocktail
/// reveal — captured at the moment its body is removed from the table,
/// since the body itself won't exist for the rest of the animation.
typedef CocktailPiece = ({Vector2 start, Ingredient ingredient, double radius});

/// Plays once a cocktail order's ingredients finish touching/clustering
/// on the table (see MixolocoGame._completeCocktail): every matched
/// piece flies to the table's center, growing as it goes, then bursts
/// into a placeholder cocktail glass that briefly appears before fading
/// — entirely inside the physics world's canvas, since Flame can't paint
/// outside it.
class CocktailRevealComponent extends PositionComponent {
  CocktailRevealComponent({required this.pieces, required Vector2 center, required this.cocktailAssetPath, required this.onComplete})
    : _center = center;

  final List<CocktailPiece> pieces;
  final Vector2 _center;
  final String cocktailAssetPath;
  final void Function() onComplete;

  static const _flyDuration = 0.5;
  static const _explodeDuration = 0.25;
  static const _revealDuration = 1.8; // twice as long, per user request
  static const _totalDuration = _flyDuration + _explodeDuration + _revealDuration;

  double _elapsed = 0;
  final _rand = Random();
  late final List<_Burst> _burstShards = List.generate(16, (_) {
    final angle = _rand.nextDouble() * 2 * pi;
    return _Burst(direction: Vector2(cos(angle), sin(angle)), speed: 0.9 + _rand.nextDouble() * 1.1);
  });

  @override
  void update(double dt) {
    super.update(dt);
    _elapsed += dt;
    if (_elapsed >= _totalDuration) {
      onComplete();
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    if (_elapsed < _flyDuration) {
      _renderFlight(canvas);
    } else if (_elapsed < _flyDuration + _explodeDuration) {
      _renderBurst(canvas);
    } else {
      _renderReveal(canvas);
    }
  }

  void _renderFlight(Canvas canvas) {
    final t = Curves.easeIn.transform((_elapsed / _flyDuration).clamp(0.0, 1.0));
    for (final piece in pieces) {
      final pos = piece.start + (_center - piece.start) * t;
      final radius = piece.radius * (1 + t * 0.8);
      final size = radius * 2;
      canvas.save();
      canvas.translate(pos.x - radius, pos.y - radius);
      paintIngredient(canvas, piece.ingredient, Size(size, size));
      canvas.restore();
    }
  }

  void _renderBurst(Canvas canvas) {
    final t = ((_elapsed - _flyDuration) / _explodeDuration).clamp(0.0, 1.0);
    final paint = Paint()..color = Colors.white.withValues(alpha: 1 - t);
    for (final shard in _burstShards) {
      final pos = _center + shard.direction * shard.speed * t;
      canvas.drawCircle(pos.toOffset(), 0.05 * (1 - t * 0.5), paint);
    }
  }

  void _renderReveal(Canvas canvas) {
    final t = ((_elapsed - _flyDuration - _explodeDuration) / _revealDuration).clamp(0.0, 1.0);
    final scale = t < 0.2 ? (t / 0.2) : 1.0;
    final opacity = t > 0.7 ? (1 - (t - 0.7) / 0.3) : 1.0;
    const size = 2.2; // 2x, per user request
    canvas.save();
    canvas.translate(_center.x, _center.y);
    canvas.scale(scale);
    canvas.translate(-size / 2, -size / 2);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, size, size), Paint()..color = Colors.white.withValues(alpha: opacity));
    final drewRealArt = paintImageAsset(canvas, cocktailAssetPath, const Size(size, size));
    if (!drewRealArt) {
      GlassPainter(shape: GlassShape.jug, liquidColor: _blendedColor()).paint(canvas, const Size(size, size));
    }
    canvas.restore();
    canvas.restore();
  }

  Color _blendedColor() {
    var r = 0.0, g = 0.0, b = 0.0;
    for (final piece in pieces) {
      r += piece.ingredient.color.r;
      g += piece.ingredient.color.g;
      b += piece.ingredient.color.b;
    }
    final n = pieces.length;
    return Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  }
}

class _Burst {
  final Vector2 direction;
  final double speed;
  _Burst({required this.direction, required this.speed});
}
