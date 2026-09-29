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

  /// Continuously nudges this body's horizontal velocity toward wherever
  /// the aim line predicts it should be for its *current* height, so it
  /// visibly tracks that line all the way down rather than only
  /// approximately matching it (see [_throwTargetFarX]'s own doc for why
  /// a single upfront prediction wasn't reliable enough). Gated on
  /// [Body.isAwake] (not a fall-speed threshold) so it keeps correcting
  /// right up until this body genuinely settles — linearDamping/friction
  /// naturally slow its fall well before that, and bailing out once fall
  /// speed dropped below a fixed threshold (an earlier version of this)
  /// stopped correcting during exactly the last, most-needed stretch,
  /// leaving a visible gap between the line and where it actually
  /// landed. A collision with something else on the table can still
  /// leave this short of the line, same as it would for a real thrown
  /// object — this corrects a *clear* fall, not a blocked one.
  void _steerTowardThrowLine() {
    if (!body.isAwake) return;
    final farY = kTableFarInset;
    final remaining = body.position.y - farY;
    if (remaining <= 0.02) return;
    final total = _spawnPosition.y - farY;
    if (total <= 0) return;

    final t = ((_spawnPosition.y - body.position.y) / total).clamp(0.0, 1.0);
    final targetX = _spawnPosition.x + (_throwTargetFarX! - _spawnPosition.x) * t;
    // Floors the fall-speed estimate rather than bailing out as it decays
    // toward zero — keeps timeToFar (and so the correction) bounded and
    // meaningful instead of blowing up or vanishing right when the body
    // is closest to the target and the correction matters most.
    final fallSpeed = (-body.linearVelocity.y).clamp(0.3, double.infinity);
    final timeToFar = remaining / fallSpeed;
    final desiredVx = (targetX - body.position.x) / timeToFar;
    // A firm cap, not a gradual blend — the whole point is this body
    // reliably lands on the line, and recomputing fresh every frame from
    // its actual position already keeps the correction smooth in
    // practice (each frame's target only shifts a little from the last).
    const maxSteerSpeed = 6.0;
    body.linearVelocity.x = desiredVx.clamp(-maxSteerSpeed, maxSteerSpeed);
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
