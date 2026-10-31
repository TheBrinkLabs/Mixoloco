import 'package:flutter/material.dart';

/// Which vessel shape an ingredient is served in — purely visual, but
/// picked per-ingredient so the bar reads as varied glassware rather
/// than identical tinted boxes (matches the mixed tumblers/martini
/// glasses/jugs look of real cocktail-bar reference art).
enum GlassShape { tumbler, martini, jug, mug }

/// What kind of tiny debris bits a same-tier merge scatters alongside the
/// plain colored shards — glass for anything served/poured in a glass,
/// peel for a citrus/berry fruit, leaf for the peppermint (see
/// MergeExplosionComponent).
enum DebrisType { glass, peel, leaf }

/// One rung of the merge ladder (peppermint → vodka → ... → cocktail
/// jug). Two
/// touching items at the same [tier] merge into the item at `tier + 1` —
/// see [kEvolutionChain] for the full ordered sequence and
/// [radiusForTier] for how much bigger each step is.
///
/// [color] + [shape] render a code-drawn placeholder glass (see
/// GlassVisual) until real art exists — [assetPath] is reserved for that
/// swap: once set, GlassVisual should prefer it over the drawn version,
/// so no caller needs to change when real art lands.
///
/// [displayScale] compensates for each source photo's own transparent
/// padding — every ingredient's own opaque content extends a different
/// distance from its image's center, so without this, items with more
/// natural padding (a tall glass, an angled bottle) visibly fall short
/// of actually touching a neighbor whose art fills more of its own box,
/// even when their physics circles are genuinely in contact. Computed
/// per-ingredient (not guessed) so every ingredient's visible edge lands
/// at the same relative distance from its center — see
/// scratchpad/art_tool/measure_display_scales.dart's derivation:
/// `longerRawImageSide / (2 * maxContentRadiusInRawPixels)`. Independent
/// of the tier-based size growth; only nudges how much of its own circle
/// an ingredient's art fills.
///
/// [sizeMultiplier] shrinks/grows an ingredient smaller/bigger than its
/// tier would otherwise make it — unlike [displayScale]/[displayScaleX]
/// (which only change how much of its own physics circle the art
/// fills), this scales the physics circle itself, so both the merge
/// contact size *and* the rendered art shrink together with no gap
/// introduced (the render size is always derived from the same radius
/// passed into the physics body — see IngredientBodyComponent). Default
/// 1.0 — every Level 1 ingredient is already 5% smaller than its
/// original size via kBaseRadiusMeters' own global factor (see
/// mixoloco_game.dart), so 1.0 here already means "the standard 5%
/// smaller." Only rum currently deviates on top of that, at 0.9684,
/// landing it at an effective 8% smaller overall per feedback it still
/// read a touch large next to its neighbors even at the standard rate.
///
/// [displayScaleX] is a second, *horizontal-only* correction on top of
/// that — needed because [displayScale] alone only calibrates the single
/// farthest opaque pixel in ANY direction, which for a tall narrow glass
/// (soda, tonic, the spirit bottles) is always near its top/bottom, not
/// its sides. BoxFit.contain then scales the whole image by that same
/// factor in both directions, so the vertical reach lands exactly right
/// while the horizontal reach — the axis two items resting side by side
/// on the table actually touch along — falls well short, reading as a
/// gap even though their physics circles are genuinely in contact.
/// Stretching width alone (not a second uniform scale, which would just
/// push the vertical overshoot even further past the physics circle)
/// closes that gap directly. Measured per-ingredient the same precise
/// way (scratchpad/art_tool/measure_geomean.dart:
/// `contentHalfHeight / contentHalfWidth`, i.e. how much narrower the
/// content is than it is tall), capped at 1.7 for most ingredients —
/// raised from an original 1.45 per feedback that items should actually
/// touch (a very slight overlap is fine, a gap isn't), but 1.7 is itself
/// a deliberate ceiling, not every ingredient's true ratio: an early
/// attempt at removing the cap entirely stretched everything by its own
/// raw measured value, including cases dominated by a source photo's own
/// asymmetric padding or off-center garnish rather than the glass's true
/// proportions, and those specific cases changed shape dramatically. 1.7
/// itself is empirically chosen, not derived — it's where vodka/rum/blue
/// curaçao (already right at ~1.65x) read as a perfectly natural
/// "slightly wider glass" rather than a visibly stretched one.
///
/// jug/pineapple were exactly that failure mode: both photos had badly
/// asymmetric transparent padding (the jug's decorative umbrella
/// garnish pulled its own visual weight upward and sideways; the
/// pineapple glass had a large empty gap above its rim), which the old
/// farthest-point/aspect-ratio measurement couldn't tell apart from the
/// glass's own true shape — re-centering both source images tight to
/// their actual content (see tools/center_ingredient_art.dart) resolved
/// almost all of the visible mismatch on its own, and their true ratios
/// measured out to 1.73/1.67 respectively once centered correctly —
/// close enough to the standard cap that no real exception was needed.
/// soda's centering was already correct — its true ratio (2.73) was
/// tried uncapped once, but per feedback it read as short and fat rather
/// than the tall narrow glass it should be, so it's back to the standard
/// 1.7 cap. The lesson holds generally: a narrow tall glass keeping a
/// small residual gap at 1.7 reads better than a fully "correct" but
/// visibly squat/stretched one — this is why tonic (similarly narrow)
/// stays at the standard cap too.
///
/// champagne/prosecco are the extreme end of this problem — their true
/// ratio (~3.45) is so far past the 1.7 cap that even the capped render
/// only reaches about half the width needed to touch a same-tier
/// neighbor, reading as a genuinely large gap rather than a small
/// residual one, and both are shaped nothing like a simple cylinder (a
/// bottle's narrow neck vs. wide body; a flute's wide bowl, thin stem,
/// wide foot) — no single width-stretch factor fits a shape whose width
/// varies that dramatically top to bottom without distorting it exactly
/// like soda's rejected uncap. Per feedback, these two instead get a
/// [Ingredient.collisionProfile]: a compound Box2D shape built from
/// several stacked circles that actually hugs the bottle/flute silhouette
/// instead of one oversized bounding circle, so neighbors can nestle into
/// the real narrow stem/neck the same way they would against the real
/// art — closing the gap by fixing the collision shape instead of
/// stretching the art, so both stay at their natural, undistorted
/// proportions (displayScaleX back to 1.0).
/// One circle in a compound Box2D collision shape — see
/// [Ingredient.collisionProfile] and [Ingredient.extraCircles]. [offsetX],
/// [offsetY], and [radius] are all fractions of the body's nominal tier
/// radius (not raw meters), so the same profile scales correctly whatever
/// radius that tier resolves to. [offsetY] follows the game's own Y-down
/// convention (matching TableBoundaryComponent/game-over line): negative
/// is toward the far/serving edge (top of screen), positive toward the
/// near/staging edge (bottom) — e.g. a bottle's neck is a small radius at
/// a negative offsetY, its wide base a larger radius at a positive one.
/// [offsetX] defaults to 0 (centered) — every compound-profile shape so
/// far has been left/right symmetric; only an off-center appendage like
/// tonic's straw (see [Ingredient.extraCircles]) needs it non-zero. Since
/// this offset is in the body's own local space, it rotates along with
/// the body (and the art, which Flame rotates to match) rather than
/// staying screen-locked — exactly what an appendage fixed to the glass
/// needs.
/// One shape in a compound [Ingredient.collisionProfile] — either a
/// [CollisionCircle] or a [CollisionEllipse]. Sealed so a profile list can
/// freely mix both (a round rim circle stacked over an oval base, say)
/// instead of forcing every entry in a profile to be the same kind.
sealed class CollisionProfileShape {
  const CollisionProfileShape();
}

class CollisionCircle extends CollisionProfileShape {
  const CollisionCircle({
    this.offsetX = 0.0,
    required this.offsetY,
    required this.radius,
  });
  final double offsetX;
  final double offsetY;
  final double radius;
}

/// An oval collision shape — Box2D has no native ellipse primitive (just
/// circle/capsule/segment/polygon), so this is built as a Box2D [Polygon]
/// sampled around the ellipse's perimeter (see
/// IngredientBodyComponent._ellipsePolygon), which is why it's capped at
/// Polygon.maxVertices (8) points — plenty to read as a smooth oval at
/// this game's render scale, not enough to need a general N-gon API.
/// Exists for a silhouette a stack of circles can't track well: a wide,
/// flat rim or a squashed-flat base, the width varying *within* one
/// "slice" of the glass rather than just tier to tier the way
/// [CollisionCircle] stacking already handles. [radiusX]/[radiusY],
/// [offsetX]/[offsetY] follow [CollisionCircle]'s own fractions-of-tier-
/// radius and Y-down convention.
class CollisionEllipse extends CollisionProfileShape {
  const CollisionEllipse({
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    required this.radiusX,
    required this.radiusY,
  });
  final double offsetX;
  final double offsetY;
  final double radiusX;
  final double radiusY;
}

/// A freeform convex polygon collision shape — wraps Box2D's own native
/// polygon primitive directly (see IngredientBodyComponent._createShapes),
/// for a silhouette that isn't close to any circle/ellipse stack: a
/// flared glass's straight tapered sides read as a trapezoid, not a
/// smooth curve, and a stack of circles/ellipses can only ever
/// approximate a straight edge with a bulge. [points] are (offsetX,
/// offsetY) pairs — same fractions-of-tier-radius, Y-down convention as
/// [CollisionCircle] — listed in order around the shape (Box2D takes
/// their convex hull, so they don't need to be hand-sorted, just not
/// self-intersecting). Capped at [maxPoints] (Box2D's own Polygon.
/// maxVertices). [cornerRadius] (also a fraction of tier radius) rounds
/// every corner by that amount — a real glass's rim/base edge is never
/// perfectly sharp, so a small rounding reads truer than a crisp corner
/// and avoids a neighbour snagging on a mathematically-sharp point.
class CollisionPolygon extends CollisionProfileShape {
  const CollisionPolygon({required this.points, this.cornerRadius = 0.0});
  final List<(double offsetX, double offsetY)> points;
  final double cornerRadius;
  static const maxPoints = 8;
}

/// A vertical capsule (a line segment with a radius, i.e. a true
/// rounded-rectangle/cylinder shape) as a collision shape — the correct
/// fit for a simple uniform-width glass (soda, tonic) rather than
/// champagne/prosecco's varying-width compound circles, since a cylinder
/// doesn't need multiple different-sized circles to approximate it, just
/// one shape whose ends are already rounded. [halfLength], [radius], and
/// [offsetY] are all fractions of the body's nominal tier radius, same
/// convention as [CollisionCircle]. [offsetY] defaults to 0 (the capsule
/// centered on the body, correct whenever the glass itself is centered
/// in its own source image) — tonic needs it non-zero because its straw
/// pulls the image's own bounding box upward off the glass body's true
/// center (see its entry and [Ingredient.extraCircles]). See
/// [Ingredient.collisionCapsule].
class CollisionCapsule {
  const CollisionCapsule({
    required this.halfLength,
    required this.radius,
    this.offsetY = 0.0,
  });
  final double halfLength;
  final double radius;
  final double offsetY;
}

class Ingredient {
  final String id;
  final String label;
  final Color color;
  final GlassShape shape;
  final DebrisType debris;
  final String? assetPath;
  final double displayScale;
  final double displayScaleX;
  final double sizeMultiplier;
  final int tier;

  /// A compound collision shape (several stacked circles and/or ellipses
  /// — see [CollisionProfileShape]) approximating this ingredient's true
  /// silhouette instead of one bounding circle — see the class doc's
  /// champagne/prosecco paragraph for why. Null (the default) keeps the
  /// plain single circle of the tier's nominal radius.
  final List<CollisionProfileShape>? collisionProfile;

  /// A capsule collision shape for a simple, uniform-width cylinder glass
  /// — see [CollisionCapsule] and soda/tonic's entries. Mutually exclusive
  /// with [collisionProfile] in practice (nothing currently sets both).
  final CollisionCapsule? collisionCapsule;

  /// Extra circles added on top of whichever primary shape above is
  /// active (capsule, profile, or the plain default circle) — for a
  /// protruding appendage that isn't part of the glass's own main body,
  /// like tonic's straw sticking up out of one side of the rim. Unlike
  /// [collisionProfile], these can (and typically do, for an off-center
  /// appendage) set a non-zero [CollisionCircle.offsetX].
  final List<CollisionCircle>? extraCircles;

  /// Whether this ingredient contains alcohol — purely descriptive game
  /// data at the moment (nothing currently reads it; the rewarded-ad
  /// "clear all shots" continue and the Slam Mini-Shots purchase both
  /// clear by [isMiniShot] instead, since this broader flag's rooftop
  /// set turned out to include Whisky, which isn't a shot glass and
  /// reads oddly as something a "clear shots" offer sweeps away).
  final bool isAlcoholic;

  /// Whether this ingredient counts toward the Slam Mini-Shots purchase's
  /// clear-the-table effect (see MixolocoGame.clearMiniShots) — a much
  /// narrower list than [isAlcoholic] (just Vodka, Melon Liqueur, Gin,
  /// Coffee Liqueur, the actual shot-glass drinks, not every alcoholic
  /// ingredient), so it gets its own flag rather than overloading that
  /// one.
  final bool isMiniShot;

  const Ingredient({
    required this.id,
    required this.label,
    required this.color,
    required this.tier,
    this.shape = GlassShape.tumbler,
    this.debris = DebrisType.glass,
    this.assetPath,
    this.displayScale = 1.0,
    this.displayScaleX = 1.0,
    this.sizeMultiplier = 1.0,
    this.isAlcoholic = false,
    this.isMiniShot = false,
    this.collisionProfile,
    this.collisionCapsule,
    this.extraCircles,
  });

  /// This same ingredient at a different position in a chain — used by
  /// the "After Dark" levels, which reuse existing ingredients.
  Ingredient withTier(int tier) => Ingredient(
    id: id,
    label: label,
    color: color,
    tier: tier,
    shape: shape,
    debris: debris,
    assetPath: assetPath,
    displayScale: displayScale,
    displayScaleX: displayScaleX,
    sizeMultiplier: sizeMultiplier,
    isAlcoholic: isAlcoholic,
    isMiniShot: isMiniShot,
    collisionProfile: collisionProfile,
    collisionCapsule: collisionCapsule,
    extraCircles: extraCircles,
  );
}

/// How much bigger each successive tier is than the last — "15% larger
/// each step" — compounding from [baseRadius] at tier 0.
const kTierGrowthFactor = 1.15;

double radiusForTier(int tier, double baseRadius) =>
    baseRadius * _pow(kTierGrowthFactor, tier);

double _pow(double base, int exponent) {
  var result = 1.0;
  for (var i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}

/// The merge ladder, small to large — index is the tier. Order was picked
/// by hand (not by original-ingredient-list order) so early, easy merges
/// can still feed into a cocktail before too long — putting vodka/rum
/// near the throwable tiers means every recipe's hardest-to-reach
/// ingredient stays close to reach rather than clear at the top of the
/// ladder. Cherry leads the whole chain (tier 0, "to make things a bit
/// more colourful") and a jug of cocktails caps it (tier 12, after
/// pineapple juice) — both with real art, same as every other ingredient
/// here. Tonic Water was dropped entirely (see Vodka Tonic's
/// replacement, Cherry Daiquiri, in cocktail_recipe.dart) rather than
/// just reslotted, since nothing else needed its spot.
const kEvolutionChain = [
  Ingredient(
    id: 'cherry',
    label: 'Cherry',
    color: Color(0xFFB0203A),
    tier: 0,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_cherry.png',
    displayScale: 1.078,
    // Round fruit: one circle fitted to the on-screen sprite (approved).
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.34),
    ],
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.265, -1.336), (0.240, -1.336),
          (-1.310, -1.185), (1.302, -1.185),
          (-1.038, -0.134), (1.030, -0.134),
          (-0.893, 0.548), (0.883, 0.548),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.893, 0.548), (0.883, 0.548),
          (-0.908, 0.726), (0.905, 0.726),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.908, 0.726), (0.905, 0.726),
          (-1.104, 0.976), (1.096, 0.976),
          (-1.074, 1.149), (1.061, 1.149),
          (-0.383, 1.314), (0.351, 1.314),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'mint',
    label: 'Peppermint',
    color: Color(0xFF1B7B4B),
    tier: 2,
    shape: GlassShape.martini,
    debris: DebrisType.leaf,
    assetPath: 'assets/images/ingredient_mint.png',
    displayScale: 1.045,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    // Rounded by 0.05 so the leaf tips are inside the shape too — they
    // overhung it by up to ~2cm, so two mints could look touching
    // without being close enough to merge.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.246, -1.188), (0.239, -1.188),
          (-0.471, -0.884), (0.288, -0.884),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.471, -0.884), (0.288, -0.884),
          (-0.422, -0.729), (0.783, -0.729),
          (-0.315, -0.574), (0.732, -0.574),
          (-0.062, -0.435), (0.627, -0.435),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.062, -0.435), (0.627, -0.435),
          (-0.732, -0.296), (0.459, -0.296),
          (-0.720, -0.056), (0.064, -0.056),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.720, -0.056), (0.064, -0.056),
          (-0.753, 0.195), (0.011, 0.195),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.753, 0.195), (0.011, 0.195),
          (-0.150, 0.318), (0.438, 0.318),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.150, 0.318), (0.438, 0.318),
          (-0.150, 0.435), (0.550, 0.435),
          (-0.198, 0.740), (0.667, 0.740),
          (-0.253, 1.012), (0.662, 1.012),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.253, 1.012), (0.662, 1.012),
          (-0.217, 1.183), (-0.203, 1.183),
        ],
        cornerRadius: 0.05,
      ),
    ],
  ),
  Ingredient(
    // Replaced with a new shot-glass illustration (the old
    // ingredient_blue_cucacao.png — typo kept in that filename — no
    // longer exists on disk); displayScale/displayScaleX remeasured
    // against the new art, same precise method as every other ingredient.
    id: 'blue_curacao',
    label: 'Blue Curaçao',
    color: Color(0xFF1E90E0),
    tier: 3,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_blue_curacao.png',
    displayScale: 1.048,
    displayScaleX: 1.636,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.326, -1.194), (0.315, -1.194),
          (-1.092, -1.092), (1.086, -1.092),
          (-1.193, -0.989), (1.186, -0.989),
          (-0.925, -0.088), (0.918, -0.088),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.925, -0.088), (0.918, -0.088),
          (-0.791, 0.469), (0.787, 0.469),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.791, 0.469), (0.787, 0.469),
          (-0.805, 0.645), (0.800, 0.645),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.805, 0.645), (0.800, 0.645),
          (-0.978, 0.874), (0.972, 0.874),
          (-0.988, 0.985), (0.985, 0.985),
          (-0.228, 1.190), (0.223, 1.190),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lemon',
    label: 'Lemon Juice',
    color: Color(0xFFFFF176),
    tier: 4,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lemon.png',
    displayScale: 1.121,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // ingredient_lemon.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.263),
    ],
  ),
  Ingredient(
    id: 'rum',
    label: 'Rum',
    color: Color(0xFFC48A3E),
    tier: 5,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_rum.png',
    displayScale: 1.046,
    // Every Level 1 ingredient is already 5% smaller than its original
    // size via kBaseRadiusMeters' own global 0.95 factor (see
    // mixoloco_game.dart) — rum additionally deviates on top of that,
    // per feedback it should end up 8% smaller overall rather than the
    // standard 5%: 0.95 (global) * 0.9684 (this) ≈ 0.92.
    sizeMultiplier: 0.9684,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.157, -1.189), (0.140, -1.189),
          (-0.675, -1.085), (0.673, -1.085),
          (-0.718, -1.000), (0.716, -1.000),
          (-0.480, 0.490), (0.478, 0.490),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.480, 0.490), (0.478, 0.490),
          (-0.491, 0.660), (0.491, 0.660),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.491, 0.660), (0.491, 0.660),
          (-0.600, 0.891), (0.598, 0.891),
          (-0.605, 0.974), (0.604, 0.974),
          (-0.551, 1.055), (0.549, 1.055),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.551, 1.055), (0.549, 1.055),
          (0.035, 1.179), (0.105, 1.179),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 6,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_lime.png',
    displayScale: 1.119,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // i_lime.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.416),
    ],
  ),
  Ingredient(
    id: 'soda',
    label: 'Soda Water',
    color: Color(0xFFE8F6F6),
    tier: 7,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_soda.png',
    displayScale: 1.103,
    // 10% bigger per feedback.
    sizeMultiplier: 1.10,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.109, -1.258), (0.103, -1.258),
          (-0.425, -1.205), (0.424, -1.205),
          (-0.457, -1.101), (0.457, -1.101),
          (-0.457, -1.022), (0.454, -1.022),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.457, -1.022), (0.454, -1.022),
          (-0.405, 1.087), (0.395, 1.087),
          (-0.383, 1.144), (0.372, 1.144),
          (-0.321, 1.197), (0.310, 1.197),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.321, 1.197), (0.310, 1.197),
          (-0.067, 1.257), (0.065, 1.257),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'orange',
    label: 'Orange Juice',
    color: Color(0xFFFFA500),
    tier: 8,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_orange.png',
    displayScale: 1.024,
    displayScaleX: 1.340,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.164, -1.167), (0.218, -1.167),
          (-0.708, -1.104), (0.750, -1.104),
          (-0.986, -1.027), (1.009, -1.027),
          (-1.100, -0.969), (1.112, -0.969),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.100, -0.969), (1.112, -0.969),
          (-1.166, -0.897), (1.160, -0.897),
          (-1.166, -0.798), (1.160, -0.798),
          (-1.057, 0.326), (1.027, 0.326),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.057, 0.326), (1.027, 0.326),
          (-0.979, 0.866), (0.949, 0.866),
          (-0.937, 0.929), (0.901, 0.929),
          (-0.871, 0.982), (0.828, 0.982),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.871, 0.982), (0.828, 0.982),
          (-0.684, 1.068), (0.636, 1.068),
          (-0.200, 1.162), (0.158, 1.162),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'cola',
    label: 'Cola',
    color: Color(0xFF3B1F0E),
    tier: 9,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_cola.png',
    displayScale: 1.021,
    displayScaleX: 1.358,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.156, -1.160), (0.310, -1.160),
          (-0.672, -1.103), (0.768, -1.103),
          (-0.883, -1.054), (0.955, -1.054),
          (-1.054, -0.983), (1.106, -0.983),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.054, -0.983), (1.106, -0.983),
          (-1.124, -0.934), (1.155, -0.934),
          (-1.160, -0.872), (1.160, -0.872),
          (-1.138, -0.672), (1.160, -0.672),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.138, -0.672), (1.160, -0.672),
          (-0.952, 0.863), (0.931, 0.863),
          (-0.901, 0.934), (0.871, 0.934),
          (-0.829, 0.987), (0.805, 0.987),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.829, 0.987), (0.805, 0.987),
          (-0.726, 1.041), (0.691, 1.041),
          (-0.491, 1.112), (0.455, 1.112),
          (-0.188, 1.156), (0.158, 1.156),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'cranberry',
    label: 'Cranberry Juice',
    color: Color(0xFFC2185B),
    tier: 10,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_cranberry.png',
    displayScale: 1.030,
    displayScaleX: 1.361,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.119, -1.174), (0.251, -1.174),
          (-0.647, -1.122), (0.714, -1.122),
          (-0.857, -1.076), (0.915, -1.076),
          (-1.022, -1.017), (1.053, -1.017),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.022, -1.017), (1.053, -1.017),
          (-1.102, -0.971), (1.120, -0.971),
          (-1.174, -0.879), (1.170, -0.879),
          (-0.969, 0.876), (0.919, 0.876),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.969, 0.876), (0.919, 0.876),
          (-0.893, 0.967), (0.836, 0.967),
          (-0.719, 1.066), (0.661, 1.066),
          (-0.478, 1.135), (0.415, 1.135),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.478, 1.135), (0.415, 1.135),
          (-0.180, 1.174), (0.113, 1.174),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'pineapple',
    label: 'Pineapple Juice',
    color: Color(0xFFF7C948),
    tier: 11,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_pineapple.png',
    displayScale: 1.075,
    displayScaleX: 1.671,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.195, -1.227), (0.227, -1.227),
          (-0.789, -1.171), (0.808, -1.171),
          (-0.950, -1.138), (0.964, -1.138),
          (-1.072, -1.102), (1.080, -1.102),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.072, -1.102), (1.080, -1.102),
          (-1.169, -1.057), (1.173, -1.057),
          (-1.225, -0.964), (1.225, -0.964),
          (-0.998, 0.959), (0.990, 0.959),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.998, 0.959), (0.990, 0.959),
          (-0.918, 1.044), (0.909, 1.044),
          (-0.830, 1.093), (0.819, 1.093),
          (-0.704, 1.140), (0.693, 1.140),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.704, 1.140), (0.693, 1.140),
          (-0.547, 1.178), (0.540, 1.178),
          (-0.110, 1.224), (0.139, 1.224),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'jug',
    label: 'Jug of Cocktails',
    color: Color(0xFFE0A845),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/c_cocktail_jug.png',
    displayScale: 1.060,
    displayScaleX: 1.729,
    // 15% bigger per feedback — matches the same bump already applied to
    // champagne (Level 2's own capstone item) below.
    sizeMultiplier: 1.15,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.773, -1.357), (-0.734, -1.357),
          (-0.795, -1.325), (0.903, -1.325),
          (-0.776, -1.280), (0.880, -1.280),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.776, -1.280), (0.880, -1.280),
          (-1.130, -1.081), (1.146, -1.081),
          (-1.357, -0.927), (1.327, -0.927),
          (-1.161, -0.900), (1.169, -0.900),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.161, -0.900), (1.169, -0.900),
          (-1.028, -0.832), (0.755, -0.832),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.028, -0.832), (0.755, -0.832),
          (-1.053, -0.805), (0.872, -0.805),
          (-1.075, -0.778), (0.911, -0.778),
          (-1.091, -0.737), (0.919, -0.737),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.091, -0.737), (0.919, -0.737),
          (-1.077, -0.651), (0.825, -0.651),
          (-0.981, -0.561), (0.606, -0.561),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.981, -0.561), (0.606, -0.561),
          (-0.856, -0.516), (1.067, -0.516),
          (-0.669, -0.470), (1.153, -0.470),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.669, -0.470), (1.153, -0.470),
          (-0.640, -0.430), (1.194, -0.430),
          (-0.614, -0.326), (1.255, -0.326),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.614, -0.326), (1.255, -0.326),
          (-0.614, -0.217), (1.271, -0.217),
          (-0.645, -0.127), (1.255, -0.127),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.645, -0.127), (1.255, -0.127),
          (-0.755, 0.063), (1.153, 0.063),
          (-0.817, 0.190), (1.036, 0.190),
          (-0.833, 0.249), (0.974, 0.249),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.833, 0.249), (0.974, 0.249),
          (-0.841, 0.280), (0.934, 0.280),
          (-0.833, 0.412), (0.756, 0.412),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.833, 0.412), (0.756, 0.412),
          (-0.825, 0.448), (0.747, 0.448),
          (-0.780, 0.525), (0.708, 0.525),
          (-0.701, 0.611), (0.629, 0.611),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.701, 0.611), (0.629, 0.611),
          (-0.653, 0.651), (0.575, 0.651),
          (-0.567, 0.701), (0.497, 0.701),
          (-0.504, 0.733), (0.426, 0.733),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.504, 0.733), (0.426, 0.733),
          (-0.418, 0.764), (0.348, 0.764),
          (-0.282, 0.805), (0.209, 0.805),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.282, 0.805), (0.209, 0.805),
          (-0.231, 0.837), (0.156, 0.837),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.231, 0.837), (0.156, 0.837),
          (-0.270, 0.914), (0.199, 0.914),
          (-0.270, 0.954), (0.192, 0.954),
          (-0.215, 1.009), (0.140, 1.009),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.215, 1.009), (0.140, 1.009),
          (-0.246, 1.058), (0.171, 1.058),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.246, 1.058), (0.171, 1.058),
          (-0.332, 1.085), (0.262, 1.085),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.332, 1.085), (0.262, 1.085),
          (-0.536, 1.117), (0.465, 1.117),
          (-0.645, 1.153), (0.567, 1.153),
          (-0.670, 1.180), (0.598, 1.180),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.670, 1.180), (0.598, 1.180),
          (-0.676, 1.226), (0.598, 1.226),
          (-0.629, 1.257), (0.551, 1.257),
          (-0.543, 1.284), (0.465, 1.284),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.543, 1.284), (0.465, 1.284),
          (-0.246, 1.325), (0.176, 1.325),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// Only these tiers are ever thrown/queued for the player — every higher
/// tier only ever appears by merging up from here. One more joins the
/// rotation (see [kExtraThrowableUnlockTier]) once the player's lifetime
/// record reaches Cranberry — a small "the pool gets richer as you get
/// better" reward on top of the flat one-time credit bonus every new
/// tier already pays (see GameStateNotifier.registerTierSeen).
const kThrowableTierCount = 4;

/// Cranberry's own tier, looked up by id rather than hardcoded so this
/// keeps tracking it if the evolution chain's order ever changes again —
/// reaching this tier (lifetime, per-level highest-tier record) is what
/// unlocks the 5th throwable item, see [throwableIngredientsFor].
final kExtraThrowableUnlockTier = kEvolutionChain
    .firstWhere((i) => i.id == 'cranberry')
    .tier;

/// The rooftop bar's own evolution chain — Level 2, unlocked once every
/// Level 1 cocktail plus the Jug have been completed (see
/// GameStateNotifier._checkLevelUp). A second, independent 13-tier chain
/// rather than an extension of [kEvolutionChain]: tier numbers here are
/// local to this chain (0-12, same range as Level 1) since
/// [radiusForTier] uses tier as a direct exponent — a continuing 13-25
/// numbering would make the rooftop table's very first thrown item
/// already dwarf the beach table's fully-merged Jug. Lifetime "highest
/// evolution ever reached" instead treats *any* Level 2 tier as ranking
/// above *every* Level 1 tier (see BoardState.highestTierUnlockedLevel2/
/// highestLevelReached) — that's tracked as a separate comparison, not
/// by the tier numbers themselves.
///
/// Cherry, Vodka, and Lime are the same ingredients (same art, same
/// measurements) as their Level 1 counterparts, reused here rather than
/// re-defined — Old Fashioned/Manhattan's garnish, Espresso Martini and
/// Melon Sour's base spirit, and Gin & Tonic/Bramble/Melon Sour's citrus
/// respectively, rather than adding new art for something already drawn.
/// Ordered smallest real-world object to largest, per design: Cherry
/// (single fruit) through Champagne (a full bottle, this chain's
/// capstone — mirrors the Jug's role, and likewise never appears inside
/// a recipe of its own).
const kEvolutionChainLevel2 = [
  Ingredient(
    id: 'cherry',
    label: 'Cherry',
    color: Color(0xFFB0203A),
    tier: 0,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_cherry.png',
    displayScale: 1.078,
    // Round fruit: one circle fitted to the on-screen sprite (approved).
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.34),
    ],
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.265, -1.336), (0.240, -1.336),
          (-1.310, -1.185), (1.302, -1.185),
          (-1.038, -0.134), (1.030, -0.134),
          (-0.893, 0.548), (0.883, 0.548),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.893, 0.548), (0.883, 0.548),
          (-0.908, 0.726), (0.905, 0.726),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.908, 0.726), (0.905, 0.726),
          (-1.104, 0.976), (1.096, 0.976),
          (-1.074, 1.149), (1.061, 1.149),
          (-0.383, 1.314), (0.351, 1.314),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'melon_liqueur',
    label: 'Melon Liqueur',
    color: Color(0xFF3DDC5A),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_melon_liqueur.png',
    displayScale: 0.893,
    displayScaleX: 1.575,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.465, -1.139), (0.517, -1.139),
          (0.676, -1.010), (1.125, -1.010),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.676, -1.010), (1.125, -1.010),
          (0.207, -0.872), (1.066, -0.872),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.207, -0.872), (1.066, -0.872),
          (-0.803, -0.743), (1.054, -0.743),
          (-1.138, -0.581), (0.961, -0.581),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.138, -0.581), (0.961, -0.581),
          (-0.935, 0.319), (0.754, 0.319),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.935, 0.319), (0.754, 0.319),
          (-0.830, 0.989), (0.646, 0.989),
          (-0.250, 1.139), (0.075, 1.139),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'blackberry',
    label: 'Blackberry',
    color: Color(0xFF4A2B5C),
    tier: 3,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_blackberry.png',
    displayScale: 0.993,
    displayScaleX: 1.316,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.159, -1.271), (0.231, -1.271),
          (-0.491, -1.164), (0.409, -1.164),
          (-0.915, -1.062), (0.605, -1.062),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.915, -1.062), (0.605, -1.062),
          (-0.923, -0.916), (0.985, -0.916),
          (-0.780, -0.751), (0.874, -0.751),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.780, -0.751), (0.874, -0.751),
          (-1.026, -0.622), (1.026, -0.622),
          (-1.067, -0.467), (1.126, -0.467),
          (-1.197, -0.333), (1.099, -0.333),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.197, -0.333), (1.099, -0.333),
          (-1.260, -0.231), (1.225, -0.231),
          (-1.249, -0.080), (1.266, -0.080),
          (-1.184, 0.022), (1.225, 0.022),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.184, 0.022), (1.225, 0.022),
          (-1.243, 0.129), (1.167, 0.129),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.243, 0.129), (1.167, 0.129),
          (-1.237, 0.249), (1.208, 0.249),
          (-1.094, 0.400), (1.152, 0.400),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.094, 0.400), (1.152, 0.400),
          (-1.085, 0.551), (1.015, 0.551),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.085, 0.551), (1.015, 0.551),
          (-0.929, 0.693), (0.981, 0.693),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.929, 0.693), (0.981, 0.693),
          (-0.898, 0.809), (0.845, 0.809),
          (-0.676, 0.924), (0.670, 0.924),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.676, 0.924), (0.670, 0.924),
          (-0.566, 1.058), (0.535, 1.058),
          (-0.093, 1.209), (0.032, 1.209),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'coffee_liqueur',
    label: 'Coffee Liqueur',
    color: Color(0xFF4A2E1E),
    tier: 4,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_coffee_liqueur.png',
    displayScale: 0.840,
    displayScaleX: 1.517,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (1.021, -1.071), (1.062, -1.071),
          (0.456, -0.934), (1.010, -0.934),
          (0.089, -0.837), (0.859, -0.837),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.089, -0.837), (0.859, -0.837),
          (-0.929, -0.728), (1.003, -0.728),
          (-1.070, -0.622), (0.886, -0.622),
          (-0.868, 0.348), (0.684, 0.348),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.868, 0.348), (0.684, 0.348),
          (-0.849, 0.441), (0.671, 0.441),
          (-0.788, 0.914), (0.604, 0.914),
          (-0.289, 1.067), (0.115, 1.067),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'gin',
    label: 'Gin',
    color: Color(0xFFF0F4F0),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_gin.png',
    // Art replaced (a cut-glass goblet, on a stem/foot rather than the
    // old tumbler) — bg-removed and recentered the same way as jug/
    // pineapple (see tools/center_ingredient_art.dart; original backed
    // up to assets/images/.asset_backup_batch3/), displayScale
    // remeasured against the new art, and given a compound
    // collisionProfile like vermouth/prosecco/champagne rather than the
    // old displayScaleX stretch — same bowl/stem/foot shape category.
    displayScale: 0.992,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.382, -1.132), (0.264, -1.132),
          (-0.674, -1.055), (0.674, -1.055),
          (-0.521, 0.273), (0.521, 0.273),
          (-0.307, 0.432), (0.297, 0.432),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.307, 0.432), (0.297, 0.432),
          (-0.204, 0.554), (0.190, 0.554),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.204, 0.554), (0.190, 0.554),
          (-0.199, 0.687), (0.199, 0.687),
          (-0.218, 0.769), (0.246, 0.769),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.218, 0.769), (0.246, 0.769),
          (-0.465, 0.871), (0.463, 0.871),
          (-0.562, 0.994), (0.567, 0.994),
          (-0.167, 1.122), (0.211, 1.122),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 6,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_lime.png',
    displayScale: 1.119,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // i_lime.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.416),
    ],
  ),
  Ingredient(
    id: 'vermouth',
    label: 'Vermouth',
    color: Color(0xFFD9B97A),
    tier: 7,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vermouth.png',
    // Wide martini-style bowl on a thin stem and foot — same shape
    // category as prosecco/champagne (see the class doc's paragraph on
    // those), so it gets a compound collisionProfile instead of the
    // displayScaleX stretch: its overall content ratio (1.72) happened
    // to land right at the standard 1.7 cap, which hid how badly a
    // uniform stretch would have distorted the thin stem specifically.
    displayScale: 0.970,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.293, -1.242), (0.323, -1.242),
          (0.143, -1.129), (0.315, -1.129),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.143, -1.129), (0.315, -1.129),
          (0.113, -1.069), (0.659, -1.069),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.113, -1.069), (0.659, -1.069),
          (-0.506, -1.006), (0.602, -1.006),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.506, -1.006), (0.602, -1.006),
          (-0.693, -0.947), (0.688, -0.947),
          (-0.718, -0.888), (0.718, -0.888),
          (-0.443, 0.175), (0.438, 0.175),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.443, 0.175), (0.438, 0.175),
          (-0.369, 0.283), (0.369, 0.283),
          (-0.208, 0.391), (0.204, 0.391),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.208, 0.391), (0.204, 0.391),
          (-0.108, 0.617), (0.104, 0.617),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.108, 0.617), (0.104, 0.617),
          (-0.115, 0.770), (0.113, 0.770),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.115, 0.770), (0.113, 0.770),
          (-0.167, 0.888), (0.162, 0.888),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.167, 0.888), (0.162, 0.888),
          (-0.423, 0.951), (0.418, 0.951),
          (-0.546, 1.025), (0.541, 1.025),
          (-0.556, 1.084), (0.551, 1.084),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.556, 1.084), (0.551, 1.084),
          (-0.511, 1.143), (0.506, 1.143),
          (-0.180, 1.232), (0.185, 1.232),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'peach',
    label: 'Peach',
    color: Color(0xFFFF8C42),
    tier: 8,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_peach.png',
    displayScale: 0.848,
    displayScaleX: 1.069,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.539, -1.082), (-0.378, -1.082),
          (-0.833, -0.989), (-0.137, -0.989),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.833, -0.989), (-0.137, -0.989),
          (-0.928, -0.930), (0.319, -0.930),
          (-1.032, -0.841), (0.365, -0.841),
          (-0.709, -0.771), (0.304, -0.771),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.709, -0.771), (0.304, -0.771),
          (-0.611, -0.709), (0.456, -0.709),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.611, -0.709), (0.456, -0.709),
          (-0.700, -0.624), (0.688, -0.624),
          (-0.787, -0.558), (0.783, -0.558),
          (-0.958, -0.353), (0.961, -0.353),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.958, -0.353), (0.961, -0.353),
          (-0.990, -0.298), (0.990, -0.298),
          (-1.061, -0.101), (1.061, -0.101),
          (-1.077, -0.016), (1.073, -0.016),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.077, -0.016), (1.073, -0.016),
          (-1.082, 0.058), (1.082, 0.058),
          (-1.061, 0.298), (1.061, 0.298),
          (-0.986, 0.508), (0.986, 0.508),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.986, 0.508), (0.986, 0.508),
          (-0.924, 0.616), (0.922, 0.616),
          (-0.874, 0.682), (0.874, 0.682),
          (-0.734, 0.822), (0.738, 0.822),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.734, 0.822), (0.738, 0.822),
          (-0.584, 0.923), (0.593, 0.923),
          (-0.468, 0.973), (0.501, 0.973),
          (-0.068, 1.078), (0.134, 1.078),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tonic',
    label: 'Tonic Water',
    color: Color(0xFFDCEFF5),
    tier: 9,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tonic.png',
    displayScale: 1.065,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.369, -1.215), (0.402, -1.215),
          (0.230, -0.804), (0.344, -0.804),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.230, -0.804), (0.344, -0.804),
          (-0.360, -0.760), (0.371, -0.760),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.360, -0.760), (0.371, -0.760),
          (-0.530, -0.694), (0.534, -0.694),
          (-0.602, -0.604), (0.600, -0.604),
          (-0.498, 0.954), (0.496, 0.954),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.498, 0.954), (0.496, 0.954),
          (-0.465, 1.047), (0.461, 1.047),
          (-0.384, 1.122), (0.379, 1.122),
          (-0.062, 1.213), (0.075, 1.213),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'whisky',
    label: 'Whisky',
    color: Color(0xFFB5651D),
    tier: 10,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_whisky.png',
    // displayScale/displayScaleX were stale — calibrated against a
    // previous, more padded version of this art. The current source PNG
    // is already tightly cropped to its own content (symmetric padding,
    // 38px sides/52px top-bottom on a 707x978 canvas) with a mild,
    // simple taper (no waist/stem), so it needed a full remeasure rather
    // than a tweak: 1.434 rendered it roughly 40% oversized relative to
    // its actual physics circle — the "enormous glass, undersized-
    // looking collision barrier" symptom was really just this stale
    // scale inflating the art alone, not the collision shape being
    // wrong. Its true content ratio (874/631 = 1.385) is comfortably
    // under the standard 1.7 cap, so it's used directly, uncapped, same
    // as vodka/rum/blue curaçao.
    displayScale: 1.003,
    displayScaleX: 1.385,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.233, -1.145), (0.232, -1.145),
          (-0.816, -1.087), (0.813, -1.087),
          (-1.047, -1.027), (1.049, -1.027),
          (-1.140, -0.961), (1.136, -0.961),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.140, -0.961), (1.136, -0.961),
          (-1.144, -0.916), (1.140, -0.916),
          (-0.995, 0.286), (0.995, 0.286),
          (-0.944, 0.404), (0.944, 0.404),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.944, 0.404), (0.944, 0.404),
          (-0.958, 0.536), (0.958, 0.536),
          (-0.911, 0.859), (0.911, 0.859),
          (-0.856, 0.924), (0.860, 0.924),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.856, 0.924), (0.860, 0.924),
          (-0.805, 0.964), (0.805, 0.964),
          (-0.610, 1.053), (0.653, 1.053),
          (-0.127, 1.139), (0.190, 1.139),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 11,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_prosecco.png',
    displayScale: 0.993,
    // 15% bigger, same as champagne — see its own sizeMultiplier comment.
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.181, -1.267), (0.191, -1.267),
          (-0.331, -0.412), (0.331, -0.412),
          (-0.259, -0.128), (0.259, -0.128),
          (-0.083, 0.142), (0.084, 0.142),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.083, 0.142), (0.084, 0.142),
          (-0.054, 0.214), (0.056, 0.214),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.214), (0.056, 0.214),
          (-0.038, 0.934), (0.038, 0.934),
          (-0.054, 0.997), (0.027, 0.997),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.997), (0.027, 0.997),
          (-0.098, 1.078), (0.101, 1.078),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.098, 1.078), (0.101, 1.078),
          (-0.272, 1.109), (0.277, 1.109),
          (-0.322, 1.163), (0.344, 1.163),
          (-0.358, 1.195), (0.358, 1.195),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.358, 1.195), (0.358, 1.195),
          (-0.295, 1.231), (0.295, 1.231),
          (-0.109, 1.262), (0.116, 1.262),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'champagne',
    label: 'Champagne',
    color: Color(0xFFD4C28A),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_champagne.png',
    displayScale: 0.996,
    // 15% bigger overall per feedback it still read a touch small —
    // sizeMultiplier (not displayScale) since this should grow the
    // actual physics footprint and render together, not just how much
    // of the same circle the art fills.
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.062, -1.270), (0.057, -1.270),
          (-0.126, -1.216), (0.117, -1.216),
          (-0.117, -0.784), (0.113, -0.784),
          (-0.135, -0.595), (0.132, -0.595),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.135, -0.595), (0.132, -0.595),
          (-0.153, -0.500), (0.149, -0.500),
          (-0.313, 0.027), (0.311, 0.027),
          (-0.333, 0.104), (0.329, 0.104),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.333, 0.104), (0.329, 0.104),
          (-0.360, 0.347), (0.360, 0.347),
          (-0.360, 1.162), (0.356, 1.162),
          (-0.320, 1.225), (0.315, 1.225),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.320, 1.225), (0.315, 1.225),
          (-0.161, 1.266), (0.165, 1.266),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// The safari bar's own evolution chain (Level 3) — same independent-
/// chain shape as [kEvolutionChainLevel2] (tiers 0-12, local to this
/// chain). Originally 12 tiers (no Cherry) rather than the standard 13 —
/// per feedback, Cherry was added back as tier 0 (same id/art every
/// other chain uses), both to match every other chain's length and
/// because Cherry Bomb (which sweeps whatever the current level's own
/// tier-0 id is — see MixolocoGame.cherryBomb) was a silent no-op here
/// without a real 'cherry' id to match.
///
/// Lime/Vodka/Gin/Tonic/Orange/Prosecco/Pineapple reuse their existing
/// art directly (same pattern as Level 2 reusing Cherry/Vodka/Lime from
/// Level 1) rather than commissioning new versions of ingredients that
/// already exist. Marula Liqueur/Honey/Mango/Ginger Beer/Pineapple/
/// Orange/Safari Beer are this chain's own dedicated art — every one
/// now has its displayScale/displayScaleX precisely measured the same
/// way as every other ingredient (see the class doc's derivation),
/// rather than sitting at the placeholder 1.0/1.0 default: that default
/// was the real cause of the pineapple reading with a large gap around
/// it, since 1.0 never stretches the art to actually reach its physics
/// circle's edge the way a measured value does.
///
/// Prosecco sits two tiers earlier here (9, not 11) than it first
/// launched at — per feedback it read too similar to Level 2's own
/// prosecco (also second-from-top there), so it's pulled forward,
/// off the capstone-adjacent spot.
const kEvolutionChainLevel3 = [
  Ingredient(
    // Added as tier 0 per feedback — this chain was 12 tiers instead of
    // the standard 13, and lacking a real 'cherry' id meant Cherry Bomb
    // (which sweeps whatever the current level's own tier-0 id is — see
    // MixolocoGame.cherryBomb) was silently a no-op here, same as every
    // level before it fixes itself once it has a genuine tier-0 cherry.
    id: 'cherry',
    label: 'Cherry',
    color: Color(0xFFB0203A),
    tier: 0,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_cherry.png',
    displayScale: 1.078,
    // Round fruit: one circle fitted to the on-screen sprite (approved).
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.34),
    ],
  ),
  Ingredient(
    // Reordered (per feedback) so tier position tracks each item's own
    // real-world size, same reasoning as Level 4's reorder — a mini
    // shot through a splash of juice through a cut-glass goblet up to
    // a full jar. ids/labels/art are all unchanged, only each entry's
    // position (and so its tier number) moved.
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.265, -1.336), (0.240, -1.336),
          (-1.310, -1.185), (1.302, -1.185),
          (-1.038, -0.134), (1.030, -0.134),
          (-0.893, 0.548), (0.883, 0.548),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.893, 0.548), (0.883, 0.548),
          (-0.908, 0.726), (0.905, 0.726),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.908, 0.726), (0.905, 0.726),
          (-1.104, 0.976), (1.096, 0.976),
          (-1.074, 1.149), (1.061, 1.149),
          (-0.383, 1.314), (0.351, 1.314),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 2,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_lime.png',
    displayScale: 1.119,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // i_lime.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.416),
    ],
  ),
  Ingredient(
    id: 'gin',
    label: 'Gin',
    color: Color(0xFFF0F4F0),
    tier: 3,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_gin.png',
    displayScale: 0.992,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.382, -1.132), (0.264, -1.132),
          (-0.674, -1.055), (0.674, -1.055),
          (-0.521, 0.273), (0.521, 0.273),
          (-0.307, 0.432), (0.297, 0.432),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.307, 0.432), (0.297, 0.432),
          (-0.204, 0.554), (0.190, 0.554),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.204, 0.554), (0.190, 0.554),
          (-0.199, 0.687), (0.199, 0.687),
          (-0.218, 0.769), (0.246, 0.769),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.218, 0.769), (0.246, 0.769),
          (-0.465, 0.871), (0.463, 0.871),
          (-0.562, 0.994), (0.567, 0.994),
          (-0.167, 1.122), (0.211, 1.122),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'honey',
    label: 'Honey',
    color: Color(0xFFE8A317),
    tier: 4,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_honey.png',
    displayScale: 0.969,
    displayScaleX: 1.300,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.692, -1.104), (0.670, -1.104),
          (-0.975, -0.893), (0.960, -0.893),
          (-0.899, -0.787), (0.889, -0.787),
          (-0.895, -0.686), (0.888, -0.686),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.895, -0.686), (0.888, -0.686),
          (-1.102, -0.576), (1.094, -0.576),
          (-1.092, 0.869), (1.087, 0.869),
          (-0.303, 1.100), (0.342, 1.100),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    // A raw orange-slice picture, not the poured-glass art Level 1/2's
    // own 'orange' uses — this chain's own dedicated art rather than a
    // reuse, per feedback. A distinct id (not 'orange') since
    // findIngredientById searches all three chains and would otherwise
    // always resolve to Level 1's entry first, showing the wrong art on
    // this bar's own cocktail/order screens.
    id: 'orange_slice',
    label: 'Orange',
    color: Color(0xFFFFA500),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_orange_slice.png',
    displayScale: 1.114,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // ingredient_orange_slice.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.265),
    ],
  ),
  Ingredient(
    id: 'marula_liqueur',
    label: 'Marula Liqueur',
    color: Color(0xFFD2A857),
    tier: 6,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_marula.png',
    displayScale: 1.062,
    displayScaleX: 1.452,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.196, -1.213), (0.177, -1.213),
          (-0.827, -1.128), (0.820, -1.128),
          (-1.033, -1.061), (1.033, -1.061),
          (-1.157, -0.991), (1.150, -0.991),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.157, -0.991), (1.150, -0.991),
          (-1.212, -0.877), (1.212, -0.877),
          (-1.095, 0.026), (1.102, 0.026),
          (-1.054, 0.135), (1.061, 0.135),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.054, 0.135), (1.061, 0.135),
          (-1.047, 0.456), (1.047, 0.456),
          (-1.000, 0.546), (1.006, 0.546),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.000, 0.546), (1.006, 0.546),
          (-1.006, 0.626), (1.020, 0.626),
          (-0.951, 0.939), (0.954, 0.939),
          (-0.814, 1.061), (0.820, 1.061),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.814, 1.061), (0.820, 1.061),
          (-0.636, 1.128), (0.649, 1.128),
          (-0.143, 1.208), (0.138, 1.208),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tonic',
    label: 'Tonic Water',
    color: Color(0xFFDCEFF5),
    tier: 7,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tonic.png',
    displayScale: 1.065,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.369, -1.215), (0.402, -1.215),
          (0.230, -0.804), (0.344, -0.804),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.230, -0.804), (0.344, -0.804),
          (-0.360, -0.760), (0.371, -0.760),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.360, -0.760), (0.371, -0.760),
          (-0.530, -0.694), (0.534, -0.694),
          (-0.602, -0.604), (0.600, -0.604),
          (-0.498, 0.954), (0.496, 0.954),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.498, 0.954), (0.496, 0.954),
          (-0.465, 1.047), (0.461, 1.047),
          (-0.384, 1.122), (0.379, 1.122),
          (-0.062, 1.213), (0.075, 1.213),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'mango',
    label: 'Mango',
    color: Color(0xFFFF8C42),
    tier: 8,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_mango.png',
    displayScale: 0.986,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.146, -1.093), (0.362, -1.093),
          (-0.058, -1.034), (0.555, -1.034),
          (-0.213, -0.954), (0.679, -0.954),
          (-0.308, -0.878), (0.753, -0.878),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.308, -0.878), (0.753, -0.878),
          (-0.057, -0.803), (0.801, -0.803),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.057, -0.803), (0.801, -0.803),
          (-0.296, -0.727), (0.837, -0.727),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.296, -0.727), (0.837, -0.727),
          (-0.407, -0.676), (0.919, -0.676),
          (-0.598, -0.553), (1.055, -0.553),
          (-0.710, -0.457), (0.938, -0.457),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.710, -0.457), (0.938, -0.457),
          (-0.869, -0.270), (1.055, -0.270),
          (-0.965, -0.115), (1.107, -0.115),
          (-1.085, 0.179), (1.115, 0.179),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.085, 0.179), (1.115, 0.179),
          (-1.103, 0.239), (1.101, 0.239),
          (-1.119, 0.521), (0.988, 0.521),
          (-1.111, 0.572), (0.952, 0.572),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.111, 0.572), (0.952, 0.572),
          (-1.059, 0.708), (0.849, 0.708),
          (-1.000, 0.791), (0.757, 0.791),
          (-0.857, 0.902), (0.598, 0.902),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.857, 0.902), (0.598, 0.902),
          (-0.721, 0.974), (0.459, 0.974),
          (-0.244, 1.085), (0.031, 1.085),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 9,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_prosecco.png',
    displayScale: 0.993,
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.181, -1.267), (0.191, -1.267),
          (-0.331, -0.412), (0.331, -0.412),
          (-0.259, -0.128), (0.259, -0.128),
          (-0.083, 0.142), (0.084, 0.142),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.083, 0.142), (0.084, 0.142),
          (-0.054, 0.214), (0.056, 0.214),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.214), (0.056, 0.214),
          (-0.038, 0.934), (0.038, 0.934),
          (-0.054, 0.997), (0.027, 0.997),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.997), (0.027, 0.997),
          (-0.098, 1.078), (0.101, 1.078),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.098, 1.078), (0.101, 1.078),
          (-0.272, 1.109), (0.277, 1.109),
          (-0.322, 1.163), (0.344, 1.163),
          (-0.358, 1.195), (0.358, 1.195),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.358, 1.195), (0.358, 1.195),
          (-0.295, 1.231), (0.295, 1.231),
          (-0.109, 1.262), (0.116, 1.262),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'ginger_beer',
    label: 'Ginger Beer',
    color: Color(0xFFC77A2B),
    tier: 10,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_ginger_beer.png',
    displayScale: 1.035,
    displayScaleX: 1.700,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.450, -1.181), (0.475, -1.181),
          (-1.008, -1.127), (1.002, -1.127),
          (-1.008, -1.069), (1.002, -1.069),
          (-0.886, 1.004), (0.892, 1.004),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.886, 1.004), (0.892, 1.004),
          (-0.843, 1.090), (0.849, 1.090),
          (-0.328, 1.173), (0.303, 1.173),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    // A whole-fruit picture, not the poured-glass art Level 1's own
    // 'pineapple' uses — same reasoning (and same distinct-id fix) as
    // this chain's own 'orange_slice' above.
    id: 'pineapple_fruit',
    label: 'Pineapple',
    color: Color(0xFFF7C948),
    tier: 11,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_pineapple_fruit.png',
    displayScale: 1.087,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.314, -1.239), (-0.307, -1.239),
          (-0.302, -1.206), (0.065, -1.206),
          (-0.262, -1.080), (0.310, -1.080),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.262, -1.080), (0.310, -1.080),
          (-0.373, -0.916), (0.396, -0.916),
          (-0.414, -0.761), (0.436, -0.761),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.414, -0.761), (0.436, -0.761),
          (-0.480, -0.705), (0.382, -0.705),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.480, -0.705), (0.382, -0.705),
          (-0.410, -0.642), (0.519, -0.642),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.410, -0.642), (0.519, -0.642),
          (-0.466, -0.579), (0.423, -0.579),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.466, -0.579), (0.423, -0.579),
          (-0.357, -0.497), (0.404, -0.497),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.357, -0.497), (0.404, -0.497),
          (-0.421, -0.456), (0.499, -0.456),
          (-0.492, -0.423), (0.486, -0.423),
          (-0.562, -0.386), (0.377, -0.386),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.562, -0.386), (0.377, -0.386),
          (-0.347, -0.338), (0.436, -0.338),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.347, -0.338), (0.436, -0.338),
          (-0.495, -0.286), (0.529, -0.286),
          (-0.392, -0.182), (0.410, -0.182),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.392, -0.182), (0.410, -0.182),
          (-0.425, -0.130), (0.432, -0.130),
          (-0.462, 0.037), (0.455, 0.037),
          (-0.510, 0.108), (0.482, 0.108),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.510, 0.108), (0.482, 0.108),
          (-0.521, 0.152), (0.532, 0.152),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.521, 0.152), (0.532, 0.152),
          (-0.566, 0.186), (0.526, 0.186),
          (-0.562, 0.297), (0.532, 0.297),
          (-0.558, 0.341), (0.544, 0.341),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.558, 0.341), (0.544, 0.341),
          (-0.571, 0.375), (0.570, 0.375),
          (-0.581, 0.538), (0.551, 0.538),
          (-0.568, 0.583), (0.566, 0.583),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.568, 0.583), (0.566, 0.583),
          (-0.603, 0.623), (0.578, 0.623),
          (-0.562, 0.768), (0.533, 0.768),
          (-0.562, 0.879), (0.532, 0.879),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.562, 0.879), (0.532, 0.879),
          (-0.472, 1.013), (0.471, 1.013),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.472, 1.013), (0.471, 1.013),
          (-0.466, 1.083), (0.417, 1.083),
          (-0.380, 1.146), (0.363, 1.146),
          (-0.071, 1.236), (0.055, 1.236),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'safari_beer',
    label: 'Safari Beer',
    color: Color(0xFFC98A2C),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_safari_beer.png',
    displayScale: 0.875,
    isAlcoholic: true,
    // 15% bigger per feedback — matches the same bump already applied to
    // champagne (Level 2's own capstone item).
    sizeMultiplier: 1.15,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.771, -0.888), (0.784, -0.888),
          (-0.821, -0.855), (0.831, -0.855),
          (-0.813, -0.722), (0.822, -0.722),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.813, -0.722), (0.822, -0.722),
          (-0.913, -0.691), (0.907, -0.691),
          (-0.946, -0.639), (0.939, -0.639),
          (-0.949, -0.299), (0.943, -0.299),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.949, -0.299), (0.943, -0.299),
          (-0.998, -0.050), (0.996, -0.050),
          (-0.993, 0.796), (0.996, 0.796),
          (-0.816, 0.885), (0.833, 0.885),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// The piazza bar's own evolution chain (Level 4) — same independent-
/// chain shape as [kEvolutionChainLevel3] (tiers 0-12, local to this
/// chain), European-themed. Lemon/Vodka/Mint/Tonic/Prosecco reuse their
/// existing art and measurements directly (same pattern every later
/// chain has followed for ingredients that already exist); Ginger Ale
/// also reuses Level 3's Ginger Beer art file outright (same picture,
/// per feedback) under its own id/label, same as the Jug/Prosecco-style
/// shared-art reuse. Every genuinely new ingredient's displayScale/
/// displayScaleX is measured precisely up front, the same way Level 3's
/// retrofit was — no placeholder 1.0/1.0 defaults this time.
const kEvolutionChainLevel4 = [
  Ingredient(
    // Reordered again (per feedback) — a handful of blackcurrant
    // berries reads smaller than the peppermint sprig, so it leads
    // instead now; mint/vodka/irish_cream keep their prior relative
    // order, just shifted one tier later. Tier position still tracks
    // each item's own real-world size overall: berries through a leaf
    // garnish through a mini shot through a full mug and finally a
    // bottle. ids/labels/art are all unchanged, only each entry's
    // position (and so its tier number) moved.
    id: 'blackcurrant',
    label: 'Blackcurrant',
    color: Color(0xFF3B1E4A),
    tier: 0,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_blackcurrant.png',
    // Rounder than it used to be (was 1.119 x 1.299): the wider stretch
    // put the berry's sides ~1cm outside its circle, so two side by side
    // looked touching while still too far apart to merge.
    displayScale: 1.17,
    displayScaleX: 1.16,
    // Round berry cluster — same story as cherry (see its comment): a
    // multi-shape polygon is the wrong tool for something that's
    // supposed to read as round (caught worse-not-better on-device, the
    // same complaint across every round fruit in this file). Also the
    // collision testbed's own default probe ingredient (see
    // MixolocoGame.debugShowerProbes), so this one gets showered around
    // every other ingredient during the tuning pass — worth it being
    // right in its own regard too. A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // ingredient_blackcurrant.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.142, radius: 1.217),
    ],
  ),
  Ingredient(
    // Aperol itself is a brand name, not a generic spirit category the
    // way "gin" or "vermouth" are — swapped for Peppermint instead
    // (same id/art/measurements as Level 1's own entry), which Hugo
    // Spritz actually needs to read as a real Hugo Spritz in the first
    // place.
    id: 'mint',
    label: 'Peppermint',
    color: Color(0xFF1B7B4B),
    tier: 1,
    shape: GlassShape.martini,
    debris: DebrisType.leaf,
    assetPath: 'assets/images/ingredient_mint.png',
    displayScale: 1.045,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    // Rounded by 0.05 so the leaf tips are inside the shape too — they
    // overhung it by up to ~2cm, so two mints could look touching
    // without being close enough to merge.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.246, -1.188), (0.239, -1.188),
          (-0.471, -0.884), (0.288, -0.884),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.471, -0.884), (0.288, -0.884),
          (-0.422, -0.729), (0.783, -0.729),
          (-0.315, -0.574), (0.732, -0.574),
          (-0.062, -0.435), (0.627, -0.435),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.062, -0.435), (0.627, -0.435),
          (-0.732, -0.296), (0.459, -0.296),
          (-0.720, -0.056), (0.064, -0.056),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.720, -0.056), (0.064, -0.056),
          (-0.753, 0.195), (0.011, 0.195),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.753, 0.195), (0.011, 0.195),
          (-0.150, 0.318), (0.438, 0.318),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.150, 0.318), (0.438, 0.318),
          (-0.150, 0.435), (0.550, 0.435),
          (-0.198, 0.740), (0.667, 0.740),
          (-0.253, 1.012), (0.662, 1.012),
        ],
        cornerRadius: 0.05,
      ),
      CollisionPolygon(
        points: [
          (-0.253, 1.012), (0.662, 1.012),
          (-0.217, 1.183), (-0.203, 1.183),
        ],
        cornerRadius: 0.05,
      ),
    ],
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.265, -1.336), (0.240, -1.336),
          (-1.310, -1.185), (1.302, -1.185),
          (-1.038, -0.134), (1.030, -0.134),
          (-0.893, 0.548), (0.883, 0.548),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.893, 0.548), (0.883, 0.548),
          (-0.908, 0.726), (0.905, 0.726),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.908, 0.726), (0.905, 0.726),
          (-1.104, 0.976), (1.096, 0.976),
          (-1.074, 1.149), (1.061, 1.149),
          (-0.383, 1.314), (0.351, 1.314),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'irish_cream',
    label: 'Irish Cream',
    color: Color(0xFF6B4226),
    tier: 3,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_irish_cream.png',
    displayScale: 0.924,
    displayScaleX: 1.232,
    isAlcoholic: true,
    isMiniShot: true,
    // 10% bigger per feedback.
    sizeMultiplier: 1.10,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.391, -1.050), (0.373, -1.050),
          (-1.044, -0.954), (1.039, -0.954),
          (-0.925, 0.841), (0.917, 0.841),
          (-0.275, 1.046), (0.254, 1.046),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'strawberry',
    label: 'Strawberry',
    color: Color(0xFFE23B5E),
    tier: 4,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_strawberry.png',
    displayScale: 1.078,
    displayScaleX: 1.398,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.495, -1.232), (-0.426, -1.232),
          (-0.671, -1.142), (0.236, -1.142),
          (-0.745, -1.039), (0.894, -1.039),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.745, -1.039), (0.894, -1.039),
          (-1.022, -0.949), (1.135, -0.949),
          (-1.020, -0.839), (1.183, -0.839),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.020, -0.839), (1.183, -0.839),
          (-1.227, -0.740), (1.147, -0.740),
          (-1.129, -0.625), (1.026, -0.625),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.129, -0.625), (1.026, -0.625),
          (-1.009, -0.482), (1.015, -0.482),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.009, -0.482), (1.015, -0.482),
          (-1.169, -0.285), (1.169, -0.285),
          (-1.221, -0.100), (1.221, -0.100),
          (-1.215, 0.018), (1.221, 0.018),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.215, 0.018), (1.221, 0.018),
          (-1.141, 0.256), (1.147, 0.256),
          (-1.020, 0.453), (1.022, 0.453),
          (-0.579, 0.945), (0.580, 0.945),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.579, 0.945), (0.580, 0.945),
          (-0.063, 1.228), (0.069, 1.228),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lemon_liqueur',
    label: 'Lemon Liqueur',
    color: Color(0xFFF5E663),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_lemon_liqueur.png',
    displayScale: 1.096,
    displayScaleX: 1.700,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.437, -1.246), (0.461, -1.246),
          (0.339, -1.146), (0.509, -1.146),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.339, -1.146), (0.509, -1.146),
          (0.312, -1.061), (1.161, -1.061),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.312, -1.061), (1.161, -1.061),
          (-1.161, -0.977), (1.188, -0.977),
          (-1.161, -0.819), (1.161, -0.819),
          (-1.103, -0.720), (1.161, -0.720),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.103, -0.720), (1.161, -0.720),
          (-0.914, -0.413), (0.634, -0.413),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.914, -0.413), (0.634, -0.413),
          (-0.392, 0.320), (0.124, 0.320),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.392, 0.320), (0.124, 0.320),
          (-0.309, 0.497), (0.020, 0.497),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.309, 0.497), (0.020, 0.497),
          (-0.268, 0.666), (-0.003, 0.666),
          (-0.268, 0.804), (0.000, 0.804),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.268, 0.804), (0.000, 0.804),
          (-0.303, 0.889), (0.033, 0.889),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.303, 0.889), (0.033, 0.889),
          (-0.711, 0.988), (0.411, 0.988),
          (-0.940, 1.069), (0.666, 1.069),
          (-0.907, 1.146), (0.659, 1.146),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.907, 1.146), (0.659, 1.146),
          (-0.272, 1.242), (0.135, 1.242),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lemon',
    label: 'Lemon Juice',
    color: Color(0xFFFFF176),
    tier: 6,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lemon.png',
    displayScale: 1.121,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // ingredient_lemon.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.263),
    ],
  ),
  Ingredient(
    id: 'elderflower_liqueur',
    label: 'Elderflower Liqueur',
    color: Color(0xFFEDE4B0),
    tier: 7,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_elderflower_liqueur.png',
    displayScale: 1.077,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.194, -1.229), (0.185, -1.229),
          (-0.496, -1.170), (0.487, -1.170),
          (-0.460, -0.935), (0.455, -0.935),
          (-0.487, -0.509), (0.478, -0.509),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.487, -0.509), (0.478, -0.509),
          (-0.414, -0.224), (0.405, -0.224),
          (-0.333, -0.102), (0.324, -0.102),
          (-0.176, 0.043), (0.170, 0.043),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.176, 0.043), (0.170, 0.043),
          (-0.115, 0.156), (0.108, 0.156),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.115, 0.156), (0.108, 0.156),
          (-0.075, 0.414), (0.070, 0.414),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.075, 0.414), (0.070, 0.414),
          (-0.075, 0.758), (0.070, 0.758),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.075, 0.758), (0.070, 0.758),
          (-0.148, 0.944), (0.140, 0.944),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.148, 0.944), (0.140, 0.944),
          (-0.460, 1.007), (0.455, 1.007),
          (-0.541, 1.071), (0.536, 1.071),
          (-0.518, 1.134), (0.514, 1.134),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.518, 1.134), (0.514, 1.134),
          (-0.208, 1.220), (0.183, 1.220),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'cognac',
    label: 'Cognac',
    color: Color(0xFFA6621E),
    tier: 8,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_cognac.png',
    displayScale: 1.050,
    displayScaleX: 1.592,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.367, -1.198), (0.336, -1.198),
          (-0.885, -1.145), (0.875, -1.145),
          (-1.124, -0.726), (1.114, -0.726),
          (-1.149, -0.669), (1.135, -0.669),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.149, -0.669), (1.135, -0.669),
          (-1.184, -0.532), (1.177, -0.532),
          (-1.191, -0.404), (1.184, -0.404),
          (-1.128, -0.227), (1.121, -0.227),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.128, -0.227), (1.121, -0.227),
          (-1.093, -0.174), (1.079, -0.174),
          (-1.032, -0.117), (1.022, -0.117),
          (-0.917, -0.033), (0.910, -0.033),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.917, -0.033), (0.910, -0.033),
          (-0.706, 0.068), (0.699, 0.068),
          (-0.476, 0.135), (0.474, 0.135),
          (-0.165, 0.254), (0.158, 0.254),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.165, 0.254), (0.158, 0.254),
          (-0.102, 0.554), (0.098, 0.554),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.102, 0.554), (0.098, 0.554),
          (-0.109, 0.766), (0.102, 0.766),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.109, 0.766), (0.102, 0.766),
          (-0.152, 0.867), (0.145, 0.867),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.152, 0.867), (0.145, 0.867),
          (-0.235, 0.925), (0.228, 0.925),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.235, 0.925), (0.228, 0.925),
          (-0.713, 0.982), (0.699, 0.982),
          (-0.840, 1.044), (0.833, 1.044),
          (-0.706, 1.137), (0.699, 1.137),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.706, 1.137), (0.699, 1.137),
          (-0.210, 1.194), (0.172, 1.194),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 9,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/game/i_prosecco.png',
    displayScale: 0.993,
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.181, -1.267), (0.191, -1.267),
          (-0.331, -0.412), (0.331, -0.412),
          (-0.259, -0.128), (0.259, -0.128),
          (-0.083, 0.142), (0.084, 0.142),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.083, 0.142), (0.084, 0.142),
          (-0.054, 0.214), (0.056, 0.214),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.214), (0.056, 0.214),
          (-0.038, 0.934), (0.038, 0.934),
          (-0.054, 0.997), (0.027, 0.997),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.054, 0.997), (0.027, 0.997),
          (-0.098, 1.078), (0.101, 1.078),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.098, 1.078), (0.101, 1.078),
          (-0.272, 1.109), (0.277, 1.109),
          (-0.322, 1.163), (0.344, 1.163),
          (-0.358, 1.195), (0.358, 1.195),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.358, 1.195), (0.358, 1.195),
          (-0.295, 1.231), (0.295, 1.231),
          (-0.109, 1.262), (0.116, 1.262),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tonic',
    label: 'Tonic Water',
    color: Color(0xFFDCEFF5),
    tier: 10,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tonic.png',
    displayScale: 1.065,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (0.369, -1.215), (0.402, -1.215),
          (0.230, -0.804), (0.344, -0.804),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.230, -0.804), (0.344, -0.804),
          (-0.360, -0.760), (0.371, -0.760),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.360, -0.760), (0.371, -0.760),
          (-0.530, -0.694), (0.534, -0.694),
          (-0.602, -0.604), (0.600, -0.604),
          (-0.498, 0.954), (0.496, 0.954),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.498, 0.954), (0.496, 0.954),
          (-0.465, 1.047), (0.461, 1.047),
          (-0.384, 1.122), (0.379, 1.122),
          (-0.062, 1.213), (0.075, 1.213),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    // Same picture as Level 3's Ginger Beer, per feedback — just its own
    // id/label here, same reuse-the-art-under-a-new-name treatment as
    // this chain's Ginger Ale needing its own distinct entry rather than
    // pulling 'ginger_beer' in directly (a different drink in-world,
    // even though it's the same glass illustration).
    id: 'ginger_ale',
    label: 'Ginger Ale',
    color: Color(0xFFC77A2B),
    tier: 11,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_ginger_beer.png',
    displayScale: 1.035,
    displayScaleX: 1.700,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.450, -1.181), (0.475, -1.181),
          (-1.008, -1.127), (1.002, -1.127),
          (-1.008, -1.069), (1.002, -1.069),
          (-0.886, 1.004), (0.892, 1.004),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.886, 1.004), (0.892, 1.004),
          (-0.843, 1.090), (0.849, 1.090),
          (-0.328, 1.173), (0.303, 1.173),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    // Capstone — a bottle of grappa, same "never appears inside a
    // recipe" dead-end role as Jug/Champagne/Safari Beer (see
    // MixolocoGame._tryMerge's final-level win condition).
    id: 'grappa',
    label: 'Grappa',
    color: Color(0xFFD8CBA0),
    tier: 12,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_grappa.png',
    displayScale: 1.058,
    displayScaleX: 1.700,
    isAlcoholic: true,
    // 15% bigger per feedback — matches the same bump already applied to
    // champagne (Level 2's own capstone item).
    sizeMultiplier: 1.15,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.174, -1.206), (0.172, -1.206),
          (-0.290, -1.166), (0.290, -1.166),
          (-0.304, -0.905), (0.304, -0.905),
          (-0.276, -0.805), (0.276, -0.805),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.276, -0.805), (0.276, -0.805),
          (-0.312, -0.560), (0.312, -0.560),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.312, -0.560), (0.312, -0.560),
          (-0.380, -0.512), (0.374, -0.512),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.380, -0.512), (0.374, -0.512),
          (-0.651, -0.423), (0.651, -0.423),
          (-0.802, -0.343), (0.802, -0.343),
          (-0.897, -0.251), (0.897, -0.251),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.897, -0.251), (0.897, -0.251),
          (-0.952, -0.126), (0.952, -0.126),
          (-0.856, 1.061), (0.856, 1.061),
          (-0.822, 1.101), (0.822, 1.101),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.822, 1.101), (0.822, 1.101),
          (-0.713, 1.146), (0.713, 1.146),
          (-0.288, 1.194), (0.299, 1.194),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// The jungle bar's own evolution chain (Level 5) — same independent-
/// chain shape as [kEvolutionChainLevel4] (tiers 0-12, local to this
/// chain), Costa Rica/Caribbean-themed. Lime/Rum/Soda/Cola/Pineapple
/// reuse their existing art and measurements directly (same pattern
/// every later chain has followed for ingredients that already exist —
/// Pineapple specifically reuses Level 3's 'pineapple_fruit' id/art,
/// since there's no dedicated "pineapple juice" asset and this chain's
/// own Piña Colada recipe just needs the fruit itself, same abstraction
/// every other level's recipes already use). Every genuinely new
/// ingredient's displayScale/displayScaleX was measured precisely
/// against its final, centered, transparent PNG (see
/// tools/center_ingredient_art.dart's own doc comment for the general
/// method — no scratchpad script survives between sessions, so this was
/// a fresh one-off measurement script, same formula this class doc
/// documents). Tier order is smallest-to-largest by real-world size,
/// same feedback-driven convention Safari/Piazza's own chains follow —
/// a first pass, not yet visually tuned on-device.
const kEvolutionChainLevel5 = [
  Ingredient(
    id: 'sugar_cube',
    label: 'Sugar',
    color: Color(0xFFF5F0E0),
    tier: 0,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_sugar_cube.png',
    displayScale: 0.920,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.069, -1.000), (0.122, -1.000),
          (-0.752, -0.844), (0.697, -0.844),
          (-1.039, -0.692), (1.032, -0.692),
          (-1.043, -0.415), (1.036, -0.415),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.043, -0.415), (1.036, -0.415),
          (-1.022, -0.255), (1.039, -0.255),
          (-1.032, 0.089), (1.029, 0.089),
          (-1.025, 0.266), (1.032, 0.266),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.025, 0.266), (1.032, 0.266),
          (-1.008, 0.426), (1.002, 0.426),
          (-0.993, 0.621), (0.976, 0.621),
          (-0.617, 0.784), (0.642, 0.784),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.617, 0.784), (0.642, 0.784),
          (-0.044, 1.000), (-0.012, 1.000),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 1,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/game/i_lime.png',
    displayScale: 1.119,
    // Round citrus slice — same story as cherry (see its comment): a
    // plain circle undersized it, but a multi-shape polygon is the
    // wrong fix for something that's supposed to read as round (caught
    // worse-not-better on-device). A single CollisionCircle sized to
    // the average of the measured width/height extremes off
    // i_lime.png's own alpha silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.416),
    ],
  ),
  Ingredient(
    id: 'guaro',
    label: 'Guaro',
    color: Color(0xFFEAF6FA),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_guaro.png',
    displayScale: 0.951,
    displayScaleX: 1.313,
    isAlcoholic: true,
    isMiniShot: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.305, -1.082), (0.301, -1.082),
          (-1.081, -0.934), (1.075, -0.934),
          (-0.783, 0.908), (0.795, 0.908),
          (-0.172, 1.074), (0.267, 1.074),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'rum',
    label: 'Rum',
    color: Color(0xFFC48A3E),
    tier: 3,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_rum.png',
    displayScale: 1.046,
    sizeMultiplier: 0.9684,
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.157, -1.189), (0.140, -1.189),
          (-0.675, -1.085), (0.673, -1.085),
          (-0.718, -1.000), (0.716, -1.000),
          (-0.480, 0.490), (0.478, 0.490),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.480, 0.490), (0.478, 0.490),
          (-0.491, 0.660), (0.491, 0.660),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.491, 0.660), (0.491, 0.660),
          (-0.600, 0.891), (0.598, 0.891),
          (-0.605, 0.974), (0.604, 0.974),
          (-0.551, 1.055), (0.549, 1.055),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.551, 1.055), (0.549, 1.055),
          (0.035, 1.179), (0.105, 1.179),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'hot_sauce',
    label: 'Hot Sauce',
    color: Color(0xFFD1392B),
    tier: 4,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_hot_sauce.png',
    displayScale: 1.107,
    displayScaleX: 1.700,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.148, -1.240), (0.125, -1.240),
          (-0.323, -0.977), (0.316, -0.977),
          (-0.272, -0.827), (0.291, -0.827),
          (-0.316, -0.680), (0.291, -0.680),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.316, -0.680), (0.291, -0.680),
          (-0.329, -0.485), (0.316, -0.485),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.329, -0.485), (0.316, -0.485),
          (-0.540, -0.233), (0.527, -0.233),
          (-0.572, -0.060), (0.565, -0.060),
          (-0.572, 1.041), (0.562, 1.041),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.572, 1.041), (0.562, 1.041),
          (0.157, 1.237), (0.316, 1.237),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tomato_juice',
    label: 'Tomato Juice',
    color: Color(0xFFE0442E),
    tier: 5,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tomato_juice.png',
    displayScale: 1.076,
    displayScaleX: 1.570,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.248, -1.199), (0.250, -1.199),
          (-0.981, -1.087), (0.963, -1.087),
          (-1.170, -0.983), (1.163, -0.983),
          (-1.194, -0.870), (1.181, -0.870),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.194, -0.870), (1.181, -0.870),
          (-1.061, -0.758), (1.163, -0.758),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.061, -0.758), (1.163, -0.758),
          (-1.115, -0.623), (1.139, -0.623),
          (-1.090, -0.511), (1.108, -0.511),
          (-1.060, -0.395), (1.061, -0.395),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.060, -0.395), (1.061, -0.395),
          (-0.987, 0.197), (0.993, 0.197),
          (-0.957, 0.453), (0.938, 0.453),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.957, 0.453), (0.938, 0.453),
          (-0.926, 0.615), (0.945, 0.615),
          (-0.823, 0.770), (0.805, 0.770),
          (-0.203, 0.940), (0.175, 0.940),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'cola',
    label: 'Cola',
    color: Color(0xFF3B1F0E),
    tier: 6,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_cola.png',
    displayScale: 1.021,
    displayScaleX: 1.358,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.156, -1.160), (0.310, -1.160),
          (-0.672, -1.103), (0.768, -1.103),
          (-0.883, -1.054), (0.955, -1.054),
          (-1.054, -0.983), (1.106, -0.983),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.054, -0.983), (1.106, -0.983),
          (-1.124, -0.934), (1.155, -0.934),
          (-1.160, -0.872), (1.160, -0.872),
          (-1.138, -0.672), (1.160, -0.672),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.138, -0.672), (1.160, -0.672),
          (-0.952, 0.863), (0.931, 0.863),
          (-0.901, 0.934), (0.871, 0.934),
          (-0.829, 0.987), (0.805, 0.987),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.829, 0.987), (0.805, 0.987),
          (-0.726, 1.041), (0.691, 1.041),
          (-0.491, 1.112), (0.455, 1.112),
          (-0.188, 1.156), (0.158, 1.156),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'soda',
    label: 'Soda Water',
    color: Color(0xFFE8F6F6),
    tier: 7,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_soda.png',
    displayScale: 1.103,
    sizeMultiplier: 1.10,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.109, -1.258), (0.103, -1.258),
          (-0.425, -1.205), (0.424, -1.205),
          (-0.457, -1.101), (0.457, -1.101),
          (-0.457, -1.022), (0.454, -1.022),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.457, -1.022), (0.454, -1.022),
          (-0.405, 1.087), (0.395, 1.087),
          (-0.383, 1.144), (0.372, 1.144),
          (-0.321, 1.197), (0.310, 1.197),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.321, 1.197), (0.310, 1.197),
          (-0.067, 1.257), (0.065, 1.257),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'grapefruit',
    label: 'Grapefruit',
    color: Color(0xFFF08060),
    tier: 8,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_grapefruit.png',
    displayScale: 1.085,
    // Round citrus — same story as cherry (see its comment): a
    // multi-shape polygon is the wrong tool for something that's
    // supposed to read as round (caught worse-not-better on-device). A
    // single CollisionCircle sized to the average of the measured
    // width/height extremes off ingredient_grapefruit.png's own alpha
    // silhouette instead.
    collisionProfile: [
      CollisionCircle(offsetY: 0.0, radius: 1.229),
    ],
  ),
  Ingredient(
    id: 'banana',
    label: 'Banana',
    color: Color(0xFFF2D43C),
    tier: 9,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_banana.png',
    displayScale: 0.922,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-1.053, 0.141), (-1.053, 0.246),
          (-0.972, 0.061), (-0.972, 0.329),
          (-0.782, 0.011), (-0.782, 0.486),
          (-0.455, 0.007), (-0.455, 0.589),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.455, 0.007), (-0.455, 0.589),
          (-0.189, 0.018), (-0.189, 0.621),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.189, 0.018), (-0.189, 0.621),
          (0.162, -0.069), (0.162, 0.556),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.162, -0.069), (0.162, 0.556),
          (0.282, -0.135), (0.282, 0.524),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.282, -0.135), (0.282, 0.524),
          (0.582, -0.372), (0.582, 0.346),
          (0.763, -0.482), (0.763, 0.204),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (0.763, -0.482), (0.763, 0.204),
          (0.834, -0.601), (0.834, 0.120),
          (0.926, -0.747), (0.926, -0.028),
          (1.050, -0.726), (1.050, -0.686),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'coconut',
    label: 'Coconut',
    color: Color(0xFF9C6B3E),
    tier: 10,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_coconut.png',
    displayScale: 1.075,
    // Round fruit: one circle fitted to the on-screen sprite (approved).
    collisionProfile: [
      CollisionCircle(offsetY: 0.07, radius: 1.231),
    ],
  ),
  Ingredient(
    id: 'pineapple_fruit',
    label: 'Pineapple',
    color: Color(0xFFF7C948),
    tier: 11,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_pineapple_fruit.png',
    displayScale: 1.087,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.314, -1.239), (-0.307, -1.239),
          (-0.302, -1.206), (0.065, -1.206),
          (-0.262, -1.080), (0.310, -1.080),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.262, -1.080), (0.310, -1.080),
          (-0.373, -0.916), (0.396, -0.916),
          (-0.414, -0.761), (0.436, -0.761),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.414, -0.761), (0.436, -0.761),
          (-0.480, -0.705), (0.382, -0.705),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.480, -0.705), (0.382, -0.705),
          (-0.410, -0.642), (0.519, -0.642),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.410, -0.642), (0.519, -0.642),
          (-0.466, -0.579), (0.423, -0.579),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.466, -0.579), (0.423, -0.579),
          (-0.357, -0.497), (0.404, -0.497),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.357, -0.497), (0.404, -0.497),
          (-0.421, -0.456), (0.499, -0.456),
          (-0.492, -0.423), (0.486, -0.423),
          (-0.562, -0.386), (0.377, -0.386),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.562, -0.386), (0.377, -0.386),
          (-0.347, -0.338), (0.436, -0.338),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.347, -0.338), (0.436, -0.338),
          (-0.495, -0.286), (0.529, -0.286),
          (-0.392, -0.182), (0.410, -0.182),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.392, -0.182), (0.410, -0.182),
          (-0.425, -0.130), (0.432, -0.130),
          (-0.462, 0.037), (0.455, 0.037),
          (-0.510, 0.108), (0.482, 0.108),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.510, 0.108), (0.482, 0.108),
          (-0.521, 0.152), (0.532, 0.152),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.521, 0.152), (0.532, 0.152),
          (-0.566, 0.186), (0.526, 0.186),
          (-0.562, 0.297), (0.532, 0.297),
          (-0.558, 0.341), (0.544, 0.341),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.558, 0.341), (0.544, 0.341),
          (-0.571, 0.375), (0.570, 0.375),
          (-0.581, 0.538), (0.551, 0.538),
          (-0.568, 0.583), (0.566, 0.583),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.568, 0.583), (0.566, 0.583),
          (-0.603, 0.623), (0.578, 0.623),
          (-0.562, 0.768), (0.533, 0.768),
          (-0.562, 0.879), (0.532, 0.879),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.562, 0.879), (0.532, 0.879),
          (-0.472, 1.013), (0.471, 1.013),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.472, 1.013), (0.471, 1.013),
          (-0.466, 1.083), (0.417, 1.083),
          (-0.380, 1.146), (0.363, 1.146),
          (-0.071, 1.236), (0.055, 1.236),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tequila',
    label: 'Tequila',
    color: Color(0xFFE8D9A0),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tequila.png',
    displayScale: 1.091,
    displayScaleX: 1.700,
    isAlcoholic: true,
    // 15% bigger per feedback — matches the same bump already applied to
    // champagne (Level 2's own capstone item).
    sizeMultiplier: 1.15,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.149, -1.244), (0.164, -1.244),
          (-0.329, -1.214), (0.336, -1.214),
          (-0.381, -1.180), (0.377, -1.180),
          (-0.375, -0.944), (0.375, -0.944),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.375, -0.944), (0.375, -0.944),
          (-0.291, -0.895), (0.291, -0.895),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.291, -0.895), (0.291, -0.895),
          (-0.291, -0.648), (0.291, -0.648),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.291, -0.648), (0.291, -0.648),
          (-0.318, -0.568), (0.319, -0.568),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.318, -0.568), (0.319, -0.568),
          (-0.384, -0.526), (0.388, -0.526),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.384, -0.526), (0.388, -0.526),
          (-0.687, -0.439), (0.743, -0.439),
          (-0.796, -0.405), (0.846, -0.405),
          (-0.898, -0.355), (0.917, -0.355),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.898, -0.355), (0.917, -0.355),
          (-0.943, -0.294), (0.946, -0.294),
          (-0.937, 1.070), (0.937, 1.070),
          (-0.904, 1.111), (0.937, 1.111),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.904, 1.111), (0.937, 1.111),
          (-0.795, 1.153), (0.904, 1.153),
          (-0.711, 1.180), (0.833, 1.180),
          (-0.465, 1.244), (-0.278, 1.244),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// The five "After Dark" final items — each night chain's capstone (see
/// [_nightChain]). Their `tier` here is a placeholder; [_nightChain]
/// assigns the real one. Collision profiles are traced from each PNG's
/// own alpha silhouette, same as every other ingredient.
const kNightCapstones = [
  Ingredient(
    id: 'tiki_punchbowl',
    label: 'Tiki Punch Bowl',
    color: Color(0xFFE07A3F),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tiki_punchbowl.png',
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.012, -1.017), (0.426, -1.017),
          (-0.824, -0.937), (0.411, -0.937),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.824, -0.937), (0.411, -0.937),
          (-1.070, -0.613), (0.661, -0.613),
          (-0.841, -0.580), (0.583, -0.580),
          (-0.847, -0.500), (0.480, -0.500),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.847, -0.500), (0.480, -0.500),
          (-0.893, -0.457), (1.150, -0.457),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.893, -0.457), (1.150, -0.457),
          (-1.027, -0.393), (1.157, -0.393),
          (-1.070, -0.363), (1.140, -0.363),
          (-1.117, -0.317), (0.747, -0.317),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.117, -0.317), (0.747, -0.317),
          (-1.150, -0.257), (0.703, -0.257),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.150, -0.257), (0.703, -0.257),
          (-1.160, -0.120), (0.717, -0.120),
          (-1.143, 0.123), (0.703, 0.123),
          (-1.100, 0.320), (0.660, 0.320),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.100, 0.320), (0.660, 0.320),
          (-1.020, 0.477), (0.583, 0.477),
          (-0.943, 0.587), (0.497, 0.587),
          (-0.827, 0.680), (0.395, 0.680),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.827, 0.680), (0.395, 0.680),
          (-0.797, 0.793), (0.370, 0.793),
          (-0.717, 0.883), (0.290, 0.883),
          (-0.617, 0.940), (0.193, 0.940),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.617, 0.940), (0.193, 0.940),
          (-0.318, 1.007), (-0.117, 1.007),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'champagne_tower',
    label: 'Champagne Tower',
    color: Color(0xFFF3E3A8),
    tier: 12,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_champagne_tower.png',
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.095, -1.134), (0.095, -1.134),
          (-0.205, -1.053), (0.205, -1.053),
          (-0.168, -0.955), (0.167, -0.955),
          (-0.037, -0.853), (0.033, -0.853),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.037, -0.853), (0.033, -0.853),
          (-0.035, -0.600), (0.031, -0.600),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.035, -0.600), (0.031, -0.600),
          (-0.188, -0.558), (0.188, -0.558),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.188, -0.558), (0.188, -0.558),
          (-0.413, -0.527), (0.430, -0.527),
          (-0.504, -0.390), (0.497, -0.390),
          (-0.372, -0.281), (0.365, -0.281),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.372, -0.281), (0.365, -0.281),
          (-0.378, -0.046), (0.368, -0.046),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.378, -0.046), (0.368, -0.046),
          (-0.418, -0.014), (0.412, -0.014),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.418, -0.014), (0.412, -0.014),
          (-0.827, 0.119), (0.823, 0.119),
          (-0.687, 0.239), (0.681, 0.239),
          (-0.687, 0.464), (0.681, 0.464),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.687, 0.464), (0.681, 0.464),
          (-0.993, 0.495), (0.992, 0.495),
          (-1.157, 0.530), (1.150, 0.530),
          (-1.134, 0.632), (1.129, 0.632),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.134, 0.632), (1.129, 0.632),
          (-1.017, 0.716), (1.007, 0.716),
          (-0.992, 0.751), (0.985, 0.751),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.992, 0.751), (0.985, 0.751),
          (-0.990, 0.966), (0.985, 0.966),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.990, 0.966), (0.985, 0.966),
          (-1.013, 1.004), (1.011, 1.004),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.013, 1.004), (1.011, 1.004),
          (-1.108, 1.036), (1.104, 1.036),
          (-1.024, 1.068), (0.999, 1.068),
          (-0.820, 1.099), (0.820, 1.099),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.820, 1.099), (0.820, 1.099),
          (-0.504, 1.148), (0.514, 1.148),
          (-0.097, 1.212), (0.108, 1.212),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'cool_box',
    label: 'Cool Box',
    color: Color(0xFF6E7F5E),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_cool_box.png',
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.641, -0.813), (0.740, -0.813),
          (-0.817, -0.777), (0.839, -0.777),
          (-0.917, -0.743), (0.937, -0.743),
          (-1.127, -0.323), (1.130, -0.323),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.127, -0.323), (1.130, -0.323),
          (-1.163, -0.190), (1.160, -0.190),
          (-1.147, -0.120), (1.147, -0.120),
          (-1.080, 0.303), (1.070, 0.303),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.080, 0.303), (1.070, 0.303),
          (-1.073, 0.393), (1.067, 0.393),
          (-1.043, 0.430), (1.037, 0.430),
          (-0.870, 0.783), (0.863, 0.783),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.870, 0.783), (0.863, 0.783),
          (-0.837, 0.827), (0.830, 0.827),
          (-0.751, 0.857), (0.766, 0.857),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'spritz_pitcher',
    label: 'Spritz Pitcher',
    color: Color(0xFFF2C14E),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_spritz_pitcher.png',
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.704, -1.163), (-0.617, -1.163),
          (-0.874, -1.102), (-0.428, -1.102),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.874, -1.102), (-0.428, -1.102),
          (-0.918, -1.071), (-0.184, -1.071),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.918, -1.071), (-0.184, -1.071),
          (-0.973, -1.023), (0.456, -1.023),
          (-1.001, -0.985), (0.483, -0.985),
          (-0.990, -0.941), (0.470, -0.941),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.990, -0.941), (0.470, -0.941),
          (-0.895, -0.906), (0.463, -0.906),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.895, -0.906), (0.463, -0.906),
          (-0.841, -0.852), (0.450, -0.852),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.841, -0.852), (0.450, -0.852),
          (-0.819, -0.780), (0.850, -0.780),
          (-0.805, -0.691), (0.949, -0.691),
          (-0.799, -0.519), (1.025, -0.519),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.799, -0.519), (1.025, -0.519),
          (-0.834, -0.362), (1.042, -0.362),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.834, -0.362), (1.042, -0.362),
          (-0.953, -0.111), (1.025, -0.111),
          (-1.023, 0.094), (0.963, 0.094),
          (-1.045, 0.307), (0.850, 0.307),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.045, 0.307), (0.850, 0.307),
          (-1.035, 0.478), (0.703, 0.478),
          (-1.019, 0.543), (0.632, 0.543),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.019, 0.543), (0.632, 0.543),
          (-0.939, 0.745), (0.548, 0.745),
          (-0.748, 0.961), (0.361, 0.961),
          (-0.709, 1.044), (0.322, 1.044),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.709, 1.044), (0.322, 1.044),
          (-0.655, 1.085), (0.260, 1.085),
          (-0.565, 1.116), (0.158, 1.116),
          (-0.328, 1.153), (-0.072, 1.153),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
  Ingredient(
    id: 'tequila_barrel',
    label: 'Tequila Barrel',
    color: Color(0xFF8B5A2B),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tequila_barrel.png',
    isAlcoholic: true,
    // Traced from the sprite PNG's alpha silhouette through
    // paintIngredient's transform (scratchpad gen_png), on-device approved.
    collisionProfile: [
      CollisionPolygon(
        points: [
          (-0.122, -1.163), (0.029, -1.163),
          (-0.122, -1.077), (0.032, -1.077),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.122, -1.077), (0.032, -1.077),
          (-0.289, -1.030), (0.289, -1.030),
          (-0.472, -0.983), (0.466, -0.983),
          (-0.722, -0.873), (0.725, -0.873),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.722, -0.873), (0.725, -0.873),
          (-0.862, -0.773), (0.854, -0.773),
          (-0.915, -0.717), (0.908, -0.717),
          (-0.992, -0.630), (0.975, -0.630),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.992, -0.630), (0.975, -0.630),
          (-1.038, -0.540), (1.028, -0.540),
          (-1.118, -0.327), (1.108, -0.327),
          (-1.138, -0.210), (1.128, -0.210),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.138, -0.210), (1.128, -0.210),
          (-1.145, -0.087), (1.142, -0.087),
          (-1.128, 0.053), (1.135, 0.053),
          (-1.109, 0.130), (1.125, 0.130),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-1.109, 0.130), (1.125, 0.130),
          (-1.058, 0.267), (1.090, 0.267),
          (-0.962, 0.417), (1.029, 0.417),
          (-0.932, 0.447), (1.015, 0.447),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.932, 0.447), (1.015, 0.447),
          (-0.759, 0.597), (0.912, 0.597),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.759, 0.597), (0.912, 0.597),
          (-0.865, 0.637), (0.878, 0.637),
          (-0.905, 0.750), (0.755, 0.750),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.905, 0.750), (0.755, 0.750),
          (-0.935, 0.947), (0.805, 0.947),
          (-0.452, 1.057), (0.808, 1.057),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.452, 1.057), (0.808, 1.057),
          (-0.458, 1.087), (-0.052, 1.087),
        ],
        cornerRadius: 0.0,
      ),
      CollisionPolygon(
        points: [
          (-0.458, 1.087), (-0.052, 1.087),
          (-0.468, 1.147), (-0.158, 1.147),
          (-0.433, 1.190), (-0.361, 1.190),
        ],
        cornerRadius: 0.0,
      ),
    ],
  ),
];

/// Levels 6-10 are an "After Dark" second visit to each bar: existing
/// ingredients (each keeping its own art, collision profile and display
/// tuning) re-sorted smallest to largest by real-life size, capped by a
/// new final item. Any earlier bar's final item (champagne, grappa,
/// tequila) can appear here as an ordinary ingredient.
List<Ingredient> _nightChain(List<String> ids, String capstoneId) => [
  for (var t = 0; t < ids.length; t++) _baseIngredient(ids[t]).withTier(t),
  kNightCapstones.firstWhere((i) => i.id == capstoneId).withTier(ids.length),
];

Ingredient _baseIngredient(String id) => [
  ...kEvolutionChain,
  ...kEvolutionChainLevel2,
  ...kEvolutionChainLevel3,
  ...kEvolutionChainLevel4,
  ...kEvolutionChainLevel5,
].firstWhere((i) => i.id == id);

/// Beach Bar · After Dark — tiki night.
final kEvolutionChainLevel6 = _nightChain([
  'sugar_cube', 'cherry', 'mint', 'lime', 'blue_curacao', 'rum',
  'cola', 'orange', 'pineapple', 'soda', 'banana', 'coconut',
], 'tiki_punchbowl');

/// Rooftop · After Dark — late-night lounge.
final kEvolutionChainLevel7 = _nightChain([
  'cherry', 'vodka', 'blackberry', 'lime', 'coffee_liqueur', 'lemon',
  'gin', 'vermouth', 'whisky', 'tonic', 'prosecco', 'champagne',
], 'champagne_tower');

/// Safari · After Dark — around the campfire.
final kEvolutionChainLevel8 = _nightChain([
  'lime', 'vodka', 'orange_slice', 'coffee_liqueur', 'gin', 'marula_liqueur',
  'honey', 'mango', 'tonic', 'ginger_beer', 'prosecco', 'pineapple_fruit',
], 'cool_box');

/// Piazza · After Dark — digestivo hour.
final kEvolutionChainLevel9 = _nightChain([
  'sugar_cube', 'vodka', 'blackcurrant', 'mint', 'lemon', 'coffee_liqueur',
  'lemon_liqueur', 'elderflower_liqueur', 'cognac', 'tonic', 'prosecco', 'grappa',
], 'spritz_pitcher');

/// Jungle · After Dark — the grand finale.
final kEvolutionChainLevel10 = _nightChain([
  'sugar_cube', 'lime', 'guaro', 'rum', 'hot_sauce', 'tomato_juice',
  'cola', 'soda', 'grapefruit', 'banana', 'coconut', 'tequila',
], 'tequila_barrel');

const kLevelCount = 10;

/// The five bars, in order. Levels 1-5 visit each in daylight; levels
/// 6-10 revisit the same bars "After Dark".
const kBarNames = ['Beach', 'Rooftop', 'Safari', 'Piazza', 'Jungle'];

/// Which bar (1-5) [level] takes place in.
int barForLevel(int level) => (level.clamp(1, kLevelCount) - 1) % kBarNames.length + 1;

/// Whether [level] is one of the "After Dark" revisits (6-10).
bool isAfterDarkLevel(int level) => level > kBarNames.length;

/// Display name for [level], e.g. "Beach" or "Beach Night".
String levelName(int level) {
  final bar = kBarNames[barForLevel(level) - 1];
  return isAfterDarkLevel(level) ? '$bar Night' : bar;
}

/// Every level's chain, index 0 = Level 1.
final List<List<Ingredient>> kEvolutionChains = [
  kEvolutionChain,
  kEvolutionChainLevel2,
  kEvolutionChainLevel3,
  kEvolutionChainLevel4,
  kEvolutionChainLevel5,
  kEvolutionChainLevel6,
  kEvolutionChainLevel7,
  kEvolutionChainLevel8,
  kEvolutionChainLevel9,
  kEvolutionChainLevel10,
];

/// The evolution chain for [level] (1-based, clamped to [kLevelCount]).
List<Ingredient> evolutionChainForLevel(int level) =>
    kEvolutionChains[level.clamp(1, kLevelCount) - 1];

/// The actual throwable pool for a player whose lifetime record within
/// this level is [highestTierUnlocked] — [kThrowableTierCount] items
/// normally, growing by one (the very next tier up) once they've reached
/// [kExtraThrowableUnlockTier]. [level] picks which chain — see
/// [evolutionChainForLevel].
List<Ingredient> throwableIngredientsFor(int level, int highestTierUnlocked) {
  final chain = evolutionChainForLevel(level);
  final count = highestTierUnlocked >= kExtraThrowableUnlockTier
      ? kThrowableTierCount + 1
      : kThrowableTierCount;
  return chain.take(count).toList();
}

/// Resolves a CocktailRecipe.ingredientIds entry back to its Ingredient —
/// searches all four chains, since a handful of ids (cherry, vodka,
/// lime, gin, tonic, prosecco) are shared between them, always with the
/// same art, so resolving to whichever chain's copy comes first is safe.
/// Level 3's orange/pineapple and Level 4's ginger ale deliberately use
/// their own ids ('orange_slice'/'pineapple_fruit'/'ginger_ale') rather
/// than reusing 'orange'/'pineapple'/'ginger_beer', since they're a
/// genuinely different in-world drink (ginger ale) or different art
/// (orange/pineapple) from the earlier chain's own entry, and a shared
/// id would silently resolve to the wrong one. Throws if [id] isn't in
/// any — recipes are only ever built from real ingredient ids, so that
/// would mean a genuine data bug worth surfacing loudly rather than
/// swallowing.
Ingredient findIngredientById(String id) => [
  ...kEvolutionChain,
  ...kEvolutionChainLevel2,
  ...kEvolutionChainLevel3,
  ...kEvolutionChainLevel4,
  ...kEvolutionChainLevel5,
  ...kNightCapstones,
].firstWhere((i) => i.id == id);

/// Level 5's chain order up to build 20. Saves and lifetime records from
/// those builds store Level 5 tiers as positions in this list; the chain
/// was then reordered smallest-to-largest. See [migrateLegacyLevel5Tier].
const _kLegacyLevel5Order = [
  'sugar_cube', 'hot_sauce', 'guaro', 'tomato_juice', 'lime', 'soda', 'cola',
  'grapefruit', 'banana', 'pineapple_fruit', 'coconut', 'rum', 'tequila',
];

/// The ingredient id an old (build 20 or earlier) Level 5 [tier] meant.
String? legacyLevel5Id(int tier) =>
    tier >= 0 && tier < _kLegacyLevel5Order.length ? _kLegacyLevel5Order[tier] : null;

/// Maps an old Level 5 [tier] to the current chain's tier for the same
/// ingredient (unchanged for -1, "never reached").
int migrateLegacyLevel5Tier(int tier) {
  final id = legacyLevel5Id(tier);
  if (id == null) return tier;
  final i = kEvolutionChainLevel5.indexWhere((x) => x.id == id);
  return i < 0 ? tier : i;
}
