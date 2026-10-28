import 'dart:math' show cos, pi, sin, sqrt;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart'
    show
        BlurStyle,
        Canvas,
        Color,
        MaskFilter,
        Offset,
        Paint,
        PaintingStyle,
        Rect,
        Size;
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
class IngredientBodyComponent extends BodyComponent<MixolocoGame>
    with ContactCallbacks {
  IngredientBodyComponent({
    required this.tier,
    required this.ingredient,
    required Vector2 spawnPosition,
    this.spawnAngle = 0,
    required this.radius,
    Vector2? initialVelocity,
    double? throwTargetFarX,
    this.debugShowFixtures = false,
    this.debugPinned = false,
  }) : _spawnPosition = spawnPosition,
       _initialVelocity = initialVelocity ?? Vector2.zero(),
       _throwTargetFarX = throwTargetFarX,
       // Only a player-thrown drop needs bullet mode to start with — see
       // _bulletTimeRemaining's own doc.
       _bulletTimeRemaining = throwTargetFarX != null ? _bulletDuration : 0,
       // BodyComponent's own renderBody draws the *real* fixture geometry
       // directly — exactly what the collision calibration testbed needs
       // (see MixolocoGame.debugSpawnIngredient/debugShowerProbes), no
       // custom shape-drawing math required. Stroke-only paint so it
       // outlines the sprite instead of covering it (the default Paint()
       // BodyComponent falls back to is a solid fill). strokeWidth is set
       // as a fraction of radius rather than a flat pixel count — this
       // body's canvas is still in Forge2D's meters-space here (the
       // meters-to-pixels scale is applied further up the render tree, by
       // the camera), the same space radius itself is in, so a flat width
       // like "2" became ~2 *meters* wide once that scale landed — far
       // bigger than the whole circle, which read as a solid fill instead
       // of a thin outline. 0.04 (~4px on a typical device) was still too
       // thick for pixel-level calibration work: Canvas centers a stroke
       // on the path, so half that width oversails the true boundary on
       // the outside — at 0.04 that's a ~2px outward overhang on top of
       // whatever the collision data itself gets wrong, easy to mistake
       // for a data error. Halved to keep the stroke visible while
       // cutting that overhang closer to sub-pixel.
       super(
         renderBody: debugShowFixtures,
         paint: debugShowFixtures
             ? (Paint()
                 ..color = const Color(0xFFFF1744)
                 ..style = PaintingStyle.stroke
                 ..strokeWidth = radius * 0.02)
             : null,
       );

  /// Draws this body's real Box2D fixture outline on top of its sprite —
  /// only ever set true by the debug collision-calibration testbed (see
  /// MixolocoGame's debug* methods and GameScreen's kDebugMode-gated
  /// panel), never by normal gameplay spawns.
  final bool debugShowFixtures;

  /// Testbed-only: a static body that stays exactly where it was spawned,
  /// upright and clear of the table edges, so its outline can be judged
  /// against the sprite without it toppling or sliding to the far wall.
  final bool debugPinned;

  /// Initial rotation — a restored table puts tipped items back as they were.
  final double spawnAngle;

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
  // Zero (not _bulletDuration) for anything that isn't a player-thrown
  // drop — see the constructor's own initializer. A merge/cocktail
  // result spawns essentially at rest right where its parents were, so
  // it was never at risk of tunneling through a wall in the first place;
  // the doc above already called this out as pure waste, this just
  // actually acts on it instead of paying the pricier time-of-impact
  // solver pass for the full 1.5s on every single merge result regardless.
  double _bulletTimeRemaining;

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
        final frac = switch (c) {
          CollisionCircle(:final radius) => radius,
          CollisionEllipse(:final radiusX, :final radiusY) => radiusX > radiusY ? radiusX : radiusY,
          CollisionPolygon(:final points, :final cornerRadius) =>
            points.map((p) => sqrt(p.$1 * p.$1 + p.$2 * p.$2)).reduce((a, b) => a > b ? a : b) + cornerRadius,
        };
        if (frac > maxFrac) maxFrac = frac;
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
      rotation: Rot.fromAngle(spawnAngle),
      type: debugPinned ? BodyType.static : BodyType.dynamic,
      userData: this,
      linearVelocity: _initialVelocity,
      angularDamping: 2.5,
      linearDamping: 0.1,
      // A drop can build up real speed crossing the whole table under
      // constant gravity before it hits anything — without continuous
      // collision detection a fast small circle can tunnel straight
      // through the thin floor/wall segments in a single physics step.
      // Only a thrown drop (_throwTargetFarX set) actually falls like
      // that; a merge/cocktail result spawns at rest and never needs
      // this — see _bulletTimeRemaining's own doc.
      isBullet: _throwTargetFarX != null,
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

  double _shapeMultiplier = 1.0;
  List<CollisionPiece>? _localPieces;

  /// This body's collision shapes in world space — mirrors
  /// [_createShapes] exactly, so overlap/gap checks see the same geometry
  /// Box2D does. Circles stay true circles (a centre plus a radius), not
  /// polygon approximations: an inscribed polygon's flat sides sit inside
  /// the real circle, which reads two touching round items as cm apart.
  List<CollisionPiece> worldCollisionPieces() {
    final local = _localPieces ??= _buildLocalPieces(_shapeMultiplier);
    final t = body.transform;
    final c = t.rotation.cos, s = t.rotation.sin, p = t.position;
    return [
      for (final piece in local)
        CollisionPiece(
          [for (final v in piece.core) Vector2(p.x + c * v.x - s * v.y, p.y + s * v.x + c * v.y)],
          piece.radius,
        ),
    ];
  }

  List<CollisionPiece> _buildLocalPieces(double m) {
    final r = radius * m;
    CollisionPiece circle(double cx, double cy, double cr) => CollisionPiece([Vector2(cx, cy)], cr);
    final pieces = <CollisionPiece>[];
    final capsule = ingredient.collisionCapsule;
    final profile = ingredient.collisionProfile;
    if (capsule != null) {
      final hl = r * capsule.halfLength, oy = r * capsule.offsetY;
      pieces.add(CollisionPiece([Vector2(0, oy - hl), Vector2(0, oy + hl)], r * capsule.radius));
    } else if (profile == null || profile.isEmpty) {
      pieces.add(circle(0, 0, r));
    } else {
      for (final c in profile) {
        switch (c) {
          case CollisionCircle():
            pieces.add(circle(r * c.offsetX, r * c.offsetY, r * c.radius));
          case CollisionEllipse():
            pieces.add(CollisionPiece([
              for (var i = 0; i < 8; i++)
                Vector2(
                  r * c.offsetX + r * c.radiusX * cos(2 * pi * i / 8),
                  r * c.offsetY + r * c.radiusY * sin(2 * pi * i / 8),
                ),
            ], 0));
          case CollisionPolygon():
            final hull = _hull([for (final p in c.points) Vector2(r * p.$1, r * p.$2)]);
            if (hull.length >= 3) pieces.add(CollisionPiece(hull, 0));
        }
      }
    }
    for (final c in ingredient.extraCircles ?? const <CollisionCircle>[]) {
      pieces.add(circle(r * c.offsetX, r * c.offsetY, r * c.radius));
    }
    return pieces;
  }

  /// Monotone-chain convex hull, counter-clockwise.
  static List<Vector2> _hull(List<Vector2> pts) {
    final p = [...pts]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    if (p.length < 3) return p;
    double cross(Vector2 o, Vector2 a, Vector2 b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    final lower = <Vector2>[], upper = <Vector2>[];
    for (final v in p) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, v) <= 0) {
        lower.removeLast();
      }
      lower.add(v);
    }
    for (final v in p.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, v) <= 0) {
        upper.removeLast();
      }
      upper.add(v);
    }
    return [...lower..removeLast(), ...upper..removeLast()];
  }

  /// Deepest penetration between any piece of [a] and any piece of [b]
  /// (0 when nothing overlaps).
  static double penetrationDepth(List<CollisionPiece> a, List<CollisionPiece> b) {
    var deepest = 0.0;
    for (final pa in a) {
      for (final pb in b) {
        final d = -_signedGap(pa, pb);
        if (d > deepest) deepest = d;
      }
    }
    return deepest;
  }

  /// Smallest distance between any piece of [a] and any piece of [b];
  /// 0 when they overlap.
  static double gapBetween(List<CollisionPiece> a, List<CollisionPiece> b) {
    var best = double.infinity;
    for (final pa in a) {
      for (final pb in b) {
        final g = _signedGap(pa, pb);
        if (g <= 0) return 0;
        if (g < best) best = g;
      }
    }
    return best;
  }

  /// Distance between two pieces' surfaces — negative (the penetration
  /// depth) when they overlap.
  static double _signedGap(CollisionPiece a, CollisionPiece b) {
    final coreOverlap = _satDepth(a.core, b.core);
    if (coreOverlap > 0) return -(coreOverlap + a.radius + b.radius);
    return _coreDistance(a.core, b.core) - a.radius - b.radius;
  }

  static double _coreDistance(List<Vector2> a, List<Vector2> b) {
    double pointSeg(Vector2 p, Vector2 s0, Vector2 s1) {
      final dx = s1.x - s0.x, dy = s1.y - s0.y;
      final l2 = dx * dx + dy * dy;
      var t = l2 == 0 ? 0.0 : ((p.x - s0.x) * dx + (p.y - s0.y) * dy) / l2;
      t = t < 0 ? 0 : (t > 1 ? 1 : t);
      final ex = s0.x + t * dx - p.x, ey = s0.y + t * dy - p.y;
      return sqrt(ex * ex + ey * ey);
    }

    var best = double.infinity;
    for (final (from, to) in [(a, b), (b, a)]) {
      for (final p in from) {
        for (var i = 0; i < to.length; i++) {
          final d = pointSeg(p, to[i], to[(i + 1) % to.length]);
          if (d < best) best = d;
        }
      }
    }
    return best;
  }

  /// Separating-axis overlap of two convex cores, using only the edges of
  /// real polygons (3+ points) as axes — so a point core (a circle's
  /// centre) is tested for lying inside a polygon. 0 if separated, or if
  /// neither core is a polygon (then the distance test decides).
  static double _satDepth(List<Vector2> a, List<Vector2> b) {
    var minOverlap = double.infinity;
    for (final poly in [a, b]) {
      if (poly.length < 3) continue;
      for (var i = 0; i < poly.length; i++) {
        final e = poly[(i + 1) % poly.length] - poly[i];
        final len = e.length;
        if (len < 1e-9) continue;
        final nx = -e.y / len, ny = e.x / len;
        var minA = double.infinity, maxA = -double.infinity;
        var minB = double.infinity, maxB = -double.infinity;
        for (final v in a) {
          final d = v.x * nx + v.y * ny;
          if (d < minA) minA = d;
          if (d > maxA) maxA = d;
        }
        for (final v in b) {
          final d = v.x * nx + v.y * ny;
          if (d < minB) minB = d;
          if (d > maxB) maxB = d;
        }
        // Push-out distance along this axis (not the overlap length,
        // which is zero for a point core and so misses a circle centre
        // sitting inside a polygon).
        final pushA = maxA - minB, pushB = maxB - minA;
        final o = pushA < pushB ? pushA : pushB;
        if (o <= 0) return 0;
        if (o < minOverlap) minOverlap = o;
      }
    }
    return minOverlap == double.infinity ? 0 : minOverlap;
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
    _shapeMultiplier = multiplier;
    _localPieces = null;
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
      _currentShapes.add(
        b.createShape(Circle(radius: radius * multiplier), _shapeDef),
      );
    } else {
      for (final c in profile) {
        switch (c) {
          case CollisionCircle():
            _currentShapes.add(
              b.createShape(
                Circle(
                  radius: radius * c.radius * multiplier,
                  center: Vector2(
                    radius * c.offsetX * multiplier,
                    radius * c.offsetY * multiplier,
                  ),
                ),
                _shapeDef,
              ),
            );
          case CollisionEllipse():
            _currentShapes.add(
              b.createShape(_ellipsePolygon(c, multiplier), _shapeDef),
            );
          case CollisionPolygon():
            // Box2D welds hull vertices closer than 4x linearSlop (2cm),
            // so a thin band can collapse to <3 points at a small tier
            // radius or under the shake's squish multiplier — and the
            // resulting ArgumentError, thrown from inside onLoad, stalls
            // Flame's component loading so every later spawn silently
            // never appears. A sub-shape that small is negligible to the
            // overall silhouette; skip it rather than take the game down.
            try {
              _currentShapes.add(
                b.createShape(
                  Polygon(
                    [
                      for (final p in c.points)
                        Vector2(
                          radius * p.$1 * multiplier,
                          radius * p.$2 * multiplier,
                        ),
                    ],
                    radius: radius * c.cornerRadius * multiplier,
                  ),
                  _shapeDef,
                ),
              );
            } on ArgumentError catch (e) {
              debugPrint(
                'Skipped degenerate collision polygon on '
                '${ingredient.id} (radius $radius x$multiplier): $e',
              );
            }
        }
      }
      if (_currentShapes.isEmpty) {
        _currentShapes.add(
          b.createShape(Circle(radius: radius * multiplier), _shapeDef),
        );
      }
    }
    final extra = ingredient.extraCircles;
    if (extra != null) {
      for (final c in extra) {
        _currentShapes.add(
          b.createShape(
            Circle(
              radius: radius * c.radius * multiplier,
              center: Vector2(
                radius * c.offsetX * multiplier,
                radius * c.offsetY * multiplier,
              ),
            ),
            _shapeDef,
          ),
        );
      }
    }
  }

  /// Approximates [e] as a Box2D [Polygon] sampled around its perimeter —
  /// Box2D has no native ellipse shape, just circle/capsule/segment/
  /// polygon (see [CollisionEllipse]'s own doc), and [Polygon.maxVertices]
  /// caps a convex polygon at 8 points. 8 evenly-spaced points already
  /// reads as a smooth oval at this game's render scale (the same reason
  /// an 8-gon is the usual "good enough" circle approximation generally),
  /// so there's no need to spend more of that budget than that.
  Polygon _ellipsePolygon(CollisionEllipse e, double multiplier) {
    const sides = 8;
    final cx = radius * e.offsetX * multiplier;
    final cy = radius * e.offsetY * multiplier;
    final rx = radius * e.radiusX * multiplier;
    final ry = radius * e.radiusY * multiplier;
    return Polygon([
      for (var i = 0; i < sides; i++)
        Vector2(
          cx + rx * cos(2 * pi * i / sides),
          cy + ry * sin(2 * pi * i / sides),
        ),
    ]);
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
    final velocity = body.linearVelocity;
    // Once vy has dropped this low, the body isn't really "falling"
    // anymore — it's jostling/settling against whatever it landed on.
    // Forcing vx = slope * vy every frame through that phase re-derives
    // a tiny-but-nonzero vx from the tiny residual vy every single
    // frame, which fights Box2D's own collision/friction response and
    // its sleep threshold — the body keeps getting nudged sideways in
    // small steps instead of settling immediately, reading as an odd
    // slow-motion "creep" into its final resting spot that wasn't there
    // before this steering existed. Bailing out here once it's clearly
    // past the falling phase leaves the landing itself to ordinary
    // physics, same as every other body on the table.
    if (velocity.y.abs() < kRestSpeedThreshold) return;
    final dyTotal = farY - _spawnPosition.y;
    if (dyTotal == 0) return;
    final slope = (_throwTargetFarX! - _spawnPosition.x) / dyTotal;
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
    // No depth-cue scaling by table position: the sprite must stay the
    // same size as its collision shape everywhere on the table.
    final baseSize = physicsVisualSize(radius);
    // Purely cosmetic squash/stretch during a Shaker Maker shake — see
    // MixolocoGame.shakeSquishScaleFor. (1, 1) outside a shake, so this
    // is a no-op the rest of the time.
    final squish = game.shakeSquishScaleFor(this);
    final size = Size(baseSize.width * squish.x, baseSize.height * squish.y);

    // Ground shadow — counter-rotate renderTree's own body.angle rotation
    // first so it reads as sitting flat on the table regardless of which
    // way the piece has tumbled, rather than spinning with it.
    canvas.save();
    canvas.rotate(-body.angle);
    _paintDropShadow(canvas, size);
    canvas.restore();

    // Sprite rotates only with the body itself (renderTree's body.angle):
    // any extra sprite-only tilt would swing the art away from its
    // collision shape and read as items overlapping.
    canvas.save();
    canvas.translate(-size.width / 2, -size.height / 2);
    if (_isOutOfZone) _paintDangerGlow(canvas, size);
    paintIngredient(canvas, ingredient, size);
    canvas.restore();

    // This override replaces BodyComponent's own render() entirely, so its
    // renderBody/renderShape fixture-outline drawing (what the collision
    // calibration testbed relies on — see debugShowFixtures above) would
    // otherwise never run. Calling it last draws the outline on top of the
    // sprite, in the same body-local frame renderTree already set up; it's
    // a no-op whenever renderBody is false (every non-debug spawn).
    super.render(canvas);
  }

  /// A soft dark oval beneath and slightly behind the piece — purely
  /// cosmetic, per the gameplay redesign handoff's ingredient shadow spec.
  void _paintDropShadow(Canvas canvas, Size size) {
    final offset = Offset(size.shortestSide * 0.05, size.shortestSide * 0.12);
    final shadowPaint = Paint()
      ..color = const Color(0xFF281400).withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        size.shortestSide * 0.08,
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: offset,
        width: size.width * 0.8,
        height: size.height * 0.35,
      ),
      shadowPaint,
    );
  }

  /// True once this body has crossed the game-over line (see
  /// MixolocoGame._checkOverflow/kGameOverLineFraction) — checked purely
  /// by position, not the settled+touching gate the actual game-over
  /// trigger uses, since the glow's job is an early visual warning
  /// ("you're heading for the line"), not a precise readout of whether
  /// this exact body currently counts toward ending the game.
  bool get _isOutOfZone =>
      !consumed &&
      (body.position.y - radius) >
          game.worldHeight * (1 - kGameOverLineFraction);

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
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        size.shortestSide * 0.06,
      );
    canvas.drawCircle(center, glowRadius, glowPaint);

    final crispPaint = Paint()
      ..color = Color.fromRGBO(255, 80, 80, pulse * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.014;
    canvas.drawCircle(center, glowRadius, crispPaint);
  }
}

/// One convex collision piece: a convex [core] (a single point for a
/// circle, two for a capsule, 3+ for a polygon) grown by [radius].
class CollisionPiece {
  const CollisionPiece(this.core, this.radius);
  final List<Vector2> core;
  final double radius;
}
