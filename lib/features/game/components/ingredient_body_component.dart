import 'dart:math' show sin;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show BlurStyle, Canvas, Color, MaskFilter, Offset, Paint, PaintingStyle, Size;
import '../../../data/models/ingredient.dart';
import '../mixoloco_game.dart';
import 'ingredient_sprite.dart';

/// One item on the table: a dynamic circular Box2D body sized for its
/// evolution [tier], rendered with the same art used everywhere else in
/// the game (see [paintIngredient]). All merge/cocktail-cluster logic
/// lives on [MixolocoGame] instead of here, since it needs to see every
/// body on the table at once — this component only reports its own
/// contacts up to it.
class IngredientBodyComponent extends BodyComponent<MixolocoGame> with ContactCallbacks {
  IngredientBodyComponent({
    required this.tier,
    required this.ingredient,
    required Vector2 spawnPosition,
    required this.radius,
    Vector2? initialVelocity,
    double laneAccelX = 0,
    double laneAccelDuration = 0,
  }) : _spawnPosition = spawnPosition,
       _initialVelocity = initialVelocity ?? Vector2.zero(),
       _laneAccelX = laneAccelX,
       _laneAccelRemaining = laneAccelDuration,
       super(renderBody: false);

  final int tier;
  final Ingredient ingredient;
  final double radius;
  final Vector2 _spawnPosition;
  final Vector2 _initialVelocity;

  /// A constant sideways push held for [_laneAccelRemaining] seconds after
  /// spawn — only ever set on a player-thrown drop (see
  /// MixolocoGame._handleDrop/_laneAccelXFor), never on a merge/cocktail
  /// result — so a throw aimed away from center lands on the same
  /// straight, tapered line StagingComponent draws as its aim guide,
  /// instead of drifting only once it happens to hit the angled boundary
  /// wall.
  final double _laneAccelX;
  double _laneAccelRemaining;

  /// How long a body stays in Box2D's continuous-collision ("bullet")
  /// mode after spawning — comfortably longer than any realistic fall
  /// across the table (a freefall from the staging edge to the far one
  /// takes well under a second at this world's gravity), so every drop
  /// still gets full tunneling protection while it's actually moving
  /// fast. Bullet mode makes Box2D run its (much pricier) time-of-impact
  /// solver pass for that body on every single physics step for as long
  /// as it's set — leaving it on forever, for every body that's ever
  /// existed, meant a table that had accumulated a lot of settled items
  /// over a long session was paying that extra cost for every one of
  /// them, every frame, even ones that had been sitting perfectly still
  /// for the last ten minutes. That's pure waste once a body's actually
  /// come to rest (or was never moving fast to begin with, like a merge
  /// result spawning right where its two parents were).
  static const _bulletDuration = 1.5;
  double _bulletTimeRemaining = _bulletDuration;

  /// Free-running clock driving the danger-glow pulse below — not tied
  /// to whether this particular body is currently past the line, so the
  /// pulse doesn't restart/jump in phase with its neighbours' every time
  /// one crosses the line independently.
  double _pulseT = 0;

  /// Claimed by a merge or a cocktail completion the instant it's
  /// decided — guards every other simultaneous contact callback (Box2D
  /// reports a contact to both bodies involved, and several contacts can
  /// resolve in the same physics step) from also trying to consume this
  /// same body.
  bool consumed = false;

  /// Kept from [createBody] so [setPhysicsRadiusMultiplier] can recreate
  /// the collision shape with the same material/density/contact settings
  /// later — Box2D shapes are immutable once created, there's no
  /// "resize" call, only destroy-and-recreate.
  late final ShapeDef _shapeDef;
  Shape? _currentShape;

  @override
  Body createBody() {
    final bodyDef = BodyDef(
      position: _spawnPosition,
      type: BodyType.dynamic,
      userData: this,
      linearVelocity: _initialVelocity,
      angularDamping: 2.5,
      linearDamping: 0.1,
      // A drop can build up real speed crossing the whole table under
      // constant gravity before it hits anything — without continuous
      // collision detection a fast small circle can tunnel straight
      // through the thin floor/wall segments in a single physics step.
      isBullet: true,
    );
    _shapeDef = ShapeDef(
      material: SurfaceMaterial(restitution: 0.05, friction: 0.6),
      density: 1,
      enableContactEvents: true,
    );
    final b = world.createBody(bodyDef);
    _currentShape = b.createShape(Circle(radius: radius), _shapeDef);
    return b;
  }

  /// Temporarily resizes this body's actual collision circle to
  /// `radius * multiplier` — used only by the Shaker Maker's squish
  /// effect (see MixolocoGame.shakeTable/_updateShake), which shrinks
  /// every live body for the duration of a shake and restores it (pass
  /// 1.0) once things settle. A one-time swap, not something called
  /// continuously — see the doc on MixolocoGame's _shakeSquishBase for
  /// why the shake's visual wobble/flex stays purely cosmetic instead of
  /// also flexing this collision boundary every frame. `updateBodyMass:
  /// false` deliberately leaves the body's mass/inertia exactly as they
  /// were — the shake's impulse pulses are tuned against the original
  /// mass, and letting a temporarily-smaller shape shrink it too would
  /// change how hard every pulse throws this item for reasons that have
  /// nothing to do with the resize itself.
  void setPhysicsRadiusMultiplier(double multiplier) {
    if (!isMounted) return;
    _currentShape?.destroy(updateBodyMass: false);
    _currentShape = body.createShape(Circle(radius: radius * multiplier), _shapeDef);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isMounted) return;

    if (_laneAccelRemaining > 0) {
      final step = dt < _laneAccelRemaining ? dt : _laneAccelRemaining;
      body.linearVelocity.x += _laneAccelX * step;
      _laneAccelRemaining -= dt;
    }

    if (_bulletTimeRemaining > 0) {
      _bulletTimeRemaining -= dt;
      if (_bulletTimeRemaining <= 0) {
        body.isBullet = false;
      }
    }

    _pulseT += dt;
  }

  @override
  void beginContact(Object other, Contact contact) {
    if (other is IngredientBodyComponent) {
      game.handleContactBegin(this, other);
    }
  }

  @override
  void endContact(Object other, Contact contact) {
    if (other is IngredientBodyComponent) {
      game.handleContactEnd(this, other);
    }
  }

  @override
  void render(Canvas canvas) {
    final scale = perspectiveScaleForY(body.position.y, game.worldHeight);
    final baseSize = physicsVisualSize(radius) * scale;
    // Purely cosmetic squash/stretch during a Shaker Maker shake — see
    // MixolocoGame.shakeSquishScaleFor. (1, 1) outside a shake, so this
    // is a no-op the rest of the time.
    final squish = game.shakeSquishScaleFor(this);
    final size = Size(baseSize.width * squish.x, baseSize.height * squish.y);
    canvas.save();
    canvas.translate(-size.width / 2, -size.height / 2);
    if (_isOutOfZone) _paintDangerGlow(canvas, size);
    paintIngredient(canvas, ingredient, size);
    canvas.restore();
  }

  /// True once this body has crossed the game-over line (see
  /// MixolocoGame._checkOverflow/kGameOverLineFraction) — checked purely
  /// by position, not the settled+touching gate the actual game-over
  /// trigger uses, since the glow's job is an early visual warning
  /// ("you're heading for the line"), not a precise readout of whether
  /// this exact body currently counts toward ending the game.
  bool get _isOutOfZone => !consumed && (body.position.y - radius) > game.worldHeight * (1 - kGameOverLineFraction);

  /// A soft, thin red ring around the item's own circular footprint —
  /// deliberately not shaped to the art's silhouette (which varies a lot
  /// glass to glass), a plain blurred circle reads clearly as "danger"
  /// without fighting the artwork underneath it. Pulses gently rather
  /// than staying static so it catches the eye without being frantic.
  void _paintDangerGlow(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final glowRadius = size.shortestSide / 2;
    final pulse = 0.55 + 0.35 * (0.5 + 0.5 * sin(_pulseT * 3.2));
    final glowPaint = Paint()
      ..color = Color.fromRGBO(255, 45, 45, pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.05
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.06);
    canvas.drawCircle(center, glowRadius, glowPaint);

    final crispPaint = Paint()
      ..color = Color.fromRGBO(255, 80, 80, pulse * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.014;
    canvas.drawCircle(center, glowRadius, crispPaint);
  }
}
