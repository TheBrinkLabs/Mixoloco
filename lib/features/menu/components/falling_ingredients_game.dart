import 'dart:async';
import 'dart:math';
import 'package:flame/components.dart' show Anchor;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Canvas, Color, Colors;
import '../../../data/models/ingredient.dart';
import '../../game/components/ingredient_sprite.dart';
import '../../game/mixoloco_game.dart' show kBaseRadiusMeters, kWorldWidthMeters;

/// A second, much smaller Forge2D world — the main menu's idle-screen
/// decoration. Ingredients actually fall and physically pile up against
/// each other under real gravity/collision, the same world scale and
/// per-tier radius/restitution/friction as the real table
/// (MixolocoGame), rather than a hand-scripted "each item eases along
/// its own pre-computed path" animation, which could never have an item
/// genuinely react to whatever was already sitting where it landed.
/// Deliberately minimal next to MixolocoGame: no merge rule, no
/// cocktail/staging/score logic, no contact callbacks at all — Box2D's
/// own solver already handles two circles colliding/stacking without
/// any of that, so this only needs bodies, a floor, and gravity.
class FallingIngredientsGame extends Forge2DGame {
  FallingIngredientsGame() : super(gravity: Vector2(0, 9.8));

  // Flame games default to an opaque black background — needs to stay
  // transparent, same as MixolocoGame, so the beach photo behind this
  // GameWidget (see its Positioned.fill in MenuScreen.build) shows
  // through everywhere there isn't actually a falling item.
  @override
  Color backgroundColor() => Colors.transparent;

  // Only the smaller/simpler early tiers — the later ones (cranberry
  // onward) read more like an assembled drink than a loose ingredient,
  // which doesn't fit "things falling out of the sky" as well.
  static final _pool = kEvolutionChain.take(9).where((i) => i.assetPath != null).toList();

  // One roughly every 2-3 seconds, not a quick trickle.
  static const _spawnInterval = Duration(milliseconds: 2500);

  // A generous backstop against runaway body count on a very long idle
  // session.
  static const _hardCap = 300;

  final _random = Random();
  Timer? _spawnTimer;
  int _spawned = 0;
  bool _paused = false;
  late double _worldHeight;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await preloadIngredientArt(_pool);

    // Forge2DGame's own metersToPixels setter — not
    // camera.viewfinder.zoom directly. Forge2DViewfinder treats zoom as
    // a multiplier *on top of* metersToPixels (default 100), so setting
    // zoom to a pixel-scale value like this one directly compounds with
    // that default into an enormous, effectively-off-screen render
    // scale instead of replacing it.
    metersToPixels = size.x / kWorldWidthMeters;
    _worldHeight = size.y / metersToPixels;

    // Box2D's raw Y-down convention, unlike MixolocoGame's own inverted
    // "gravity pulls toward the far/small-y edge" perspective trick —
    // this is just a plain background, items should fall straight down
    // the screen the ordinary way.
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();

    await world.add(_FloorAndWalls(worldWidth: kWorldWidthMeters, worldHeight: _worldHeight));

    _spawnTimer = Timer.periodic(_spawnInterval, (_) => _spawnItem());
  }

  void _spawnItem() {
    if (_spawned >= _hardCap) {
      _spawnTimer?.cancel();
      return;
    }
    // The topmost point of whatever's already settled — if the pile has
    // climbed high enough that a new item would spawn already
    // overlapping it, Box2D would shove them apart with an unnatural
    // pop instead of a normal landing. Stopping here reads as "the
    // screen's full" instead.
    var highestY = _worldHeight;
    for (final child in world.children) {
      if (child is _FallingIngredientBody) {
        final y = child.body.position.y;
        if (y < highestY) highestY = y;
      }
    }
    if (highestY < _worldHeight * 0.08) {
      _spawnTimer?.cancel();
      return;
    }
    final ingredient = _pool[_random.nextInt(_pool.length)];
    final radius = radiusForTier(ingredient.tier, kBaseRadiusMeters);
    final x = radius + _random.nextDouble() * (kWorldWidthMeters - radius * 2);
    world.add(_FallingIngredientBody(ingredient: ingredient, radius: radius, spawnPosition: Vector2(x, -radius * 2)));
    _spawned++;
  }

  /// Stops the physics engine ticking and the spawn timer — called
  /// whenever the menu screen itself isn't actually the visible one
  /// (another route pushed on top, or the whole app backgrounded), so
  /// items don't keep falling/spawning somewhere the player can't see.
  void pauseFalling() {
    if (_paused) return;
    _paused = true;
    pauseEngine();
    _spawnTimer?.cancel();
    _spawnTimer = null;
  }

  /// Undoes [pauseFalling] — picks back up with a fresh spawn interval
  /// rather than trying to resume mid-interval.
  void resumeFalling() {
    if (!_paused) return;
    _paused = false;
    resumeEngine();
    _spawnTimer = Timer.periodic(_spawnInterval, (_) => _spawnItem());
  }

  @override
  void onRemove() {
    _spawnTimer?.cancel();
    super.onRemove();
  }
}

/// Invisible floor + side walls sized to the screen itself, so the
/// pile — and anything that rolls — stays within view instead of
/// falling off the edges.
class _FloorAndWalls extends BodyComponent<FallingIngredientsGame> {
  final double worldWidth;
  final double worldHeight;
  _FloorAndWalls({required this.worldWidth, required this.worldHeight}) : super(renderBody: false);

  @override
  Body createBody() {
    final body = world.createBody(BodyDef(position: Vector2.zero()));
    final shapeDef = ShapeDef(material: SurfaceMaterial(friction: 0.5));
    body.createShape(Segment(point1: Vector2(0, worldHeight), point2: Vector2(worldWidth, worldHeight)), shapeDef);
    body.createShape(Segment(point1: Vector2(0, 0), point2: Vector2(0, worldHeight)), shapeDef);
    body.createShape(Segment(point1: Vector2(worldWidth, 0), point2: Vector2(worldWidth, worldHeight)), shapeDef);
    return body;
  }
}

/// One falling/settled ingredient — a plain dynamic circle sized and
/// rendered exactly like MixolocoGame's own IngredientBodyComponent
/// (same radiusForTier scale, same paintIngredient art), just without
/// any of its contact/merge machinery, since nothing here ever merges.
class _FallingIngredientBody extends BodyComponent<FallingIngredientsGame> {
  final Ingredient ingredient;
  final double radius;
  final Vector2 spawnPosition;
  _FallingIngredientBody({required this.ingredient, required this.radius, required this.spawnPosition}) : super(renderBody: false);

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: spawnPosition, type: BodyType.dynamic, angularDamping: 0.6, linearDamping: 0.05);
    final shapeDef = ShapeDef(material: SurfaceMaterial(restitution: 0.05, friction: 0.6), density: 1);
    final b = world.createBody(bodyDef);
    b.createShape(Circle(radius: radius), shapeDef);
    return b;
  }

  @override
  void render(Canvas canvas) {
    final size = physicsVisualSize(radius);
    canvas.save();
    canvas.translate(-size.width / 2, -size.height / 2);
    paintIngredient(canvas, ingredient, size);
    canvas.restore();
  }
}
