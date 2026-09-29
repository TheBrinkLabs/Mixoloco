import 'dart:math' show sin;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show BlurStyle, Canvas, Color, MaskFilter, Offset, Paint, PaintingStyle, Size;
import '../../../data/models/ingredient.dart';
import '../mixoloco_game.dart';
import 'ingredient_sprite.dart';
import 'table_boundary_component.dart' show kTableFarInset;

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
    double? throwTargetFarX,
  }) : _spawnPosition = spawnPosition,
       _initialVelocity = initialVelocity ?? Vector2.zero(),
       _throwTargetFarX = throwTargetFarX,
       super(renderBody: false);

  final int tier;
  final Ingredient ingredient;
  final double radius;
  final Vector2 _spawnPosition;
  final Vector2 _initialVelocity;

  /// The X the aim line predicts this body should reach by the time it
  /// gets to the far edge (kTableFarInset) — only set on a player-thrown
  /// drop (see MixolocoGame._handleDrop), never a merge/cocktail result.
  /// [_steerTowardThrowLine] uses this to continuously correct this
  /// body's horizontal velocity every frame, rather than a single
  /// precomputed push applied at spawn: that one-shot approach assumed
  /// the body fell from rest under plain constant acceleration, but the
  /// spawn's own initial downward nudge (see MixolocoGame._handleDrop)
  /// and this body's own linearDamping both violate that assumption, so
  /// the predicted push landed short/long of the line it was drawn
  /// against. Recomputing fresh from the body's actual current position
  /// and fall speed every frame self-corrects against whatever damping/
  /// nudges/bumps have actually done to it so far, instead of trusting a
  /// single upfront prediction.
  final double? _throwTargetFarX;

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
  /// the collision shape(s) with the same material/density/contact
  /// settings later — Box2D shapes are immutable once created, there's no
  /// "resize" call, only destroy-and-recreate.
  late final ShapeDef _shapeDef;
  final List<Shape> _currentShapes = [];

  /// The largest single collision circle's radius (in the same units as
  /// [radius]) — for a plain single-circle body this is just [radius]
  /// itself, but for a compound body (see Ingredient.collisionProfile) a
  /// thin bottle/flute's true footprint can be much smaller than its
  /// nominal tier radius, and a capsule body (Ingredient.collisionCapsule)
  /// has its own, usually narrower, true radius too. Used by
  /// MixolocoGame._sweepForMerges' safety net so that check matches the
  /// real touching distance instead of the (much larger) nominal radius.
  double get contactRadius {
    final capsule = ingredient.collisionCapsule;
    final profile = ingredient.collisionProfile;
    var maxFrac = 0.0;
    if (capsule != null) {
      maxFrac = capsule.radius;
    } else if (profile == null || profile.isEmpty) {
      maxFrac = 1.0;
    } else {
      for (final c in profile) {
        if (c.radius > maxFrac) maxFrac = c.radius;
      }
    }
    final extra = ingredient.extraCircles;
    if (extra != null) {
      for (final c in extra) {
        if (c.radius > maxFrac) maxFrac = c.radius;
      }
    }
    return radius * maxFrac;
  }

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
    _createShapes(b, 1.0);
    return b;
  }

  /// Creates this body's collision shape(s) at `radius * multiplier`,
  /// appending to [_currentShapes] — a capsule when
  /// [Ingredient.collisionCapsule] is set (a simple cylinder glass), a
  /// compound (multi-circle) body when [Ingredient.collisionProfile] is
  /// set (a bottle/flute), else the plain single circle — plus, on top
  /// of whichever of those is active, one circle per
  /// [Ingredient.extraCircles] entry for a protruding appendage (tonic's
  /// straw) that isn't part of the glass's own main-body shape.
  void _createShapes(Body b, double multiplier) {
    final capsule = ingredient.collisionCapsule;
    final profile = ingredient.collisionProfile;
    if (capsule != null) {
      final halfLength = radius * capsule.halfLength * multiplier;
      final offsetY = radius * capsule.offsetY * multiplier;
      _currentShapes.add(
        b.createShape(
          Capsule(
            center1: Vector2(0, offsetY - halfLength),
            center2: Vector2(0, offsetY + halfLength),
            radius: radius * capsule.radius * multiplier,
          ),
          _shapeDef,
        ),
      );
    } else if (profile == null || profile.isEmpty) {
      _currentShapes.add(b.createShape(Circle(radius: radius * multiplier), _shapeDef));
    } else {
      for (final c in profile) {
        _currentShapes.add(
          b.createShape(
            Circle(radius: radius * c.radius * multiplier, center: Vector2(radius * c.offsetX * multiplier, radius * c.offsetY * multiplier)),
            _shapeDef,
          ),
        );
      }
    }
    final extra = ingredient.extraCircles;
    if (extra != null) {
      for (final c in extra) {
        _currentShapes.add(
          b.createShape(
            Circle(radius: radius * c.radius * multiplier, center: Vector2(radius * c.offsetX * multiplier, radius * c.offsetY * multiplier)),
            _shapeDef,
          ),
        );
      }
    }
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
    for (final s in _currentShapes) {
      s.destroy(updateBodyMass: false);
    }
    _currentShapes.clear();
    _createShapes(body, multiplier);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isMounted) return;

    if (_throwTargetFarX != null && _bulletTimeRemaining > 0) {
      _steerTowardThrowLine();
    }

    if (_bulletTimeRemaining > 0) {
      _bulletTimeRemaining -= dt;
      if (_bulletTimeRemaining <= 0) {
        body.isBullet = false;
      }
    }

    _pulseT += dt;
  }

  /// Locks this body's horizontal velocity to the *exact* slope of the
  /// aim line, every frame, so its path is genuinely straight in x-vs-y
  /// (matching the line's own shape, not just eventually arriving near
  /// its endpoint). Earlier versions of this computed a target x for the
  /// body's current height and steered toward *that* — but at spawn the
  /// body is already exactly at its own current-height target (x hasn't
  /// moved yet), so that approach always started with zero correction
  /// and only visibly bent the path late in the fall once a gap had
  /// built up: a curved path, not the straight one the line draws.
  ///
  /// The fix is a direct geometric constraint instead of a target to
  /// chase: dx/dy must equal the line's slope at every instant. Since
  /// vx/vy = dx/dy, setting vx = slope * vy — using whatever this body's
  /// *actual* vy is each frame, however gravity/damping/a graze off
  /// another item have left it — keeps that ratio exact throughout the
  /// whole flight, automatically, with no fall-time estimate to get
  /// wrong. Integrating dx = slope * dy over the full fall lands exactly
  /// on [_throwTargetFarX] by construction. Gated on [Body.isAwake] and
  /// still being above the far line, so it stops once this body's
  /// actually settled — a collision that stops it short of the far edge
  /// still leaves it short of the line, same as a real thrown object.
  ///
  /// [Body.linearVelocity] is a getter backed by forge2d's FFI bridge —
  /// it marshals a *fresh* Vector2 from native state on every read, so
  /// mutating `.x` on the returned object (as an earlier version of this
  /// did) silently touches a throwaway copy and never reaches the real
  /// body. The velocity has to go back through the setter as a whole
  /// Vector2 to actually take effect.
  void _steerTowardThrowLine() {
    if (!body.isAwake) return;
    final farY = kTableFarInset;
    if (body.position.y <= farY) return;
    final dyTotal = farY - _spawnPosition.y;
    if (dyTotal == 0) return;
    final slope = (_throwTargetFarX! - _spawnPosition.x) / dyTotal;
    final velocity = body.linearVelocity;
    body.linearVelocity = Vector2(slope * velocity.y, velocity.y);
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
