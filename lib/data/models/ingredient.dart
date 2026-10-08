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
class CollisionCircle {
  const CollisionCircle({this.offsetX = 0.0, required this.offsetY, required this.radius});
  final double offsetX;
  final double offsetY;
  final double radius;
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
  const CollisionCapsule({required this.halfLength, required this.radius, this.offsetY = 0.0});
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

  /// A compound collision shape (several stacked circles) approximating
  /// this ingredient's true silhouette instead of one bounding circle —
  /// see the class doc's champagne/prosecco paragraph for why. Null (the
  /// default, and every ingredient except those two) keeps the plain
  /// single circle of the tier's nominal radius.
  final List<CollisionCircle>? collisionProfile;

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
}

/// How much bigger each successive tier is than the last — "15% larger
/// each step" — compounding from [baseRadius] at tier 0.
const kTierGrowthFactor = 1.15;

double radiusForTier(int tier, double baseRadius) => baseRadius * _pow(kTierGrowthFactor, tier);

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
    assetPath: 'assets/images/ingredient_cherry.png',
    displayScale: 1.078,
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
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
    displayScaleX: 1.434,
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
    displayScaleX: 1.654,
    // Every Level 1 ingredient is already 5% smaller than its original
    // size via kBaseRadiusMeters' own global 0.95 factor (see
    // mixoloco_game.dart) — rum additionally deviates on top of that,
    // per feedback it should end up 8% smaller overall rather than the
    // standard 5%: 0.95 (global) * 0.9684 (this) ≈ 0.92.
    sizeMultiplier: 0.9684,
    isAlcoholic: true,
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 6,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lime.png',
    displayScale: 1.119,
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
    // Simple uniform-width cylinder — a capsule collision shape (see
    // CollisionCapsule) matches its true footprint exactly, closing the
    // touching gap without needing displayScaleX to stretch (and distort)
    // the art the way the rejected uncap attempt did.
    //
    // First pass measured this against the source PNG's *content* height
    // (559x1526, minus its own 34/92px symmetric padding) instead of the
    // *raw* canvas height that BoxFit.contain actually scales against —
    // both radius and halfLength came out wrong (radius too big,
    // halfLength too short, since dividing by the smaller content height
    // inflates the per-pixel scale factor), reading as too big a gap
    // above/below. Recomputed against the raw 627x1710 canvas instead.
    collisionCapsule: CollisionCapsule(halfLength: 0.950, radius: 0.462),
    // 10% bigger per feedback.
    sizeMultiplier: 1.10,
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
  ),
  Ingredient(
    id: 'jug',
    label: 'Jug of Cocktails',
    color: Color(0xFFE0A845),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/cocktail_jug.png',
    displayScale: 1.060,
    displayScaleX: 1.729,
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
final kExtraThrowableUnlockTier = kEvolutionChain.firstWhere((i) => i.id == 'cranberry').tier;

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
    assetPath: 'assets/images/ingredient_cherry.png',
    displayScale: 1.078,
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
  ),
  Ingredient(
    id: 'melon_liqueur',
    label: 'Melon Liqueur',
    color: Color(0xFF3DDC5A),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_melon_liqueur.png',
    displayScale: 0.893,
    displayScaleX: 1.575,
    isAlcoholic: true,
    isMiniShot: true,
  ),
  Ingredient(
    id: 'blackberry',
    label: 'Blackberry',
    color: Color(0xFF4A2B5C),
    tier: 3,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_blackberry.png',
    displayScale: 0.993,
    displayScaleX: 1.316,
  ),
  Ingredient(
    id: 'coffee_liqueur',
    label: 'Coffee Liqueur',
    color: Color(0xFF4A2E1E),
    tier: 4,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_coffee_liqueur.png',
    displayScale: 0.840,
    displayScaleX: 1.517,
    isAlcoholic: true,
    isMiniShot: true,
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
    // The first pass placed the rim/foot circles at their literal
    // measured height, each sized to the true rim/foot width — but a
    // circle that wide, centered that close to the render's own top/
    // bottom edge, pokes out past where the art actually ends (a circle
    // extends [radius] in *every* direction, including past the rim
    // where there's nothing above it). That read as an oversized
    // invisible barrier above and below the glass — closer to plausible
    // reach on the sides (where the art continues) than top/bottom
    // (where it doesn't). Pulled both circles' centers in just enough
    // that top/bottom reach lands exactly on the render's own edge
    // instead of past it, trimming the foot's radius slightly too so it
    // doesn't collide with the stem circle above it.
    collisionProfile: [
      CollisionCircle(offsetY: -0.59, radius: 0.68),
      CollisionCircle(offsetY: -0.50, radius: 0.62),
      CollisionCircle(offsetY: 0.07, radius: 0.56),
      CollisionCircle(offsetY: 0.50, radius: 0.32),
      CollisionCircle(offsetY: 0.63, radius: 0.21),
      CollisionCircle(offsetY: 0.85, radius: 0.42),
    ],
  ),
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 6,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lime.png',
    displayScale: 1.119,
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
    // Pulled the rim/foot circles in from their literal measured height
    // — see the matching comment on gin's collisionProfile for why a
    // wide circle centered right at the render's own top/bottom edge
    // overshoots past it (an oversized barrier above/below the glass,
    // even though the sides read fine).
    collisionProfile: [
      CollisionCircle(offsetY: -0.55, radius: 0.69),
      CollisionCircle(offsetY: -0.50, radius: 0.64),
      CollisionCircle(offsetY: 0.00, radius: 0.52),
      CollisionCircle(offsetY: 0.45, radius: 0.24),
      CollisionCircle(offsetY: 0.70, radius: 0.12),
      CollisionCircle(offsetY: 0.85, radius: 0.39),
    ],
    isAlcoholic: true,
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
    // Simple uniform-width cylinder for the glass body — see soda's
    // collisionCapsule comment for the raw-vs-content scale bug this
    // also had. On top of that fix, this one also needs its own
    // [CollisionCapsule.offsetY]: the straw sticking up out of the rim
    // makes the source PNG's overall bounding box (which centering is
    // based on) taller above the glass than below it, so the glass
    // body's own true center sits lower than the image's center — this
    // capsule targets the glass rim specifically (~16% down the content,
    // where the width profile actually reaches the glass's full
    // diameter) as its top, rather than the image's own top (which is
    // the straw tip, not the glass).
    collisionCapsule: CollisionCapsule(halfLength: 0.418, radius: 0.603, offsetY: 0.194),
    // The straw pokes up out of one side of the rim, well above the
    // glass's own capsule body — without this, neighbors could get close
    // enough to visually overlap that exposed tip (a gap on that side,
    // mirror image of vermouth/gin's earlier top/bottom overshoot bug).
    // Measured the same width-band way as the compound profiles, but
    // this one needs a real offsetX too since the straw sits well off
    // to one side rather than centered. Same raw-vs-content scale fix as
    // the capsule above.
    extraCircles: [CollisionCircle(offsetX: 0.357, offsetY: -1.022, radius: 0.077)],
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
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 11,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_prosecco.png',
    displayScale: 0.993,
    // 15% bigger, same as champagne — see its own sizeMultiplier comment.
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    // Flute silhouette, top to bottom: wide bowl, narrow stem, wide foot
    // — see the class doc's champagne/prosecco paragraph. Derived from
    // scratchpad/asset_tool/profile_shape.dart's width-band measurement
    // of the (already tightly cropped, zero-padding) source art.
    collisionProfile: [
      CollisionCircle(offsetY: -0.95, radius: 0.27),
      CollisionCircle(offsetY: -0.55, radius: 0.34),
      CollisionCircle(offsetY: -0.15, radius: 0.28),
      CollisionCircle(offsetY: 0.45, radius: 0.07),
      // Foot circle pushed down and widened a touch (was offsetY 0.95,
      // radius 0.37) — per feedback there was a visible gap between the
      // glass's drawn foot and where neighbours actually stopped.
      CollisionCircle(offsetY: 1.0, radius: 0.42),
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
    // Bottle silhouette, top to bottom: narrow neck/cork, tapering
    // shoulder, wide constant-width body — see the class doc's
    // champagne/prosecco paragraph. Derived the same way as prosecco's
    // profile above.
    collisionProfile: [
      CollisionCircle(offsetY: -0.85, radius: 0.13),
      CollisionCircle(offsetY: -0.45, radius: 0.20),
      CollisionCircle(offsetY: 0.00, radius: 0.32),
      CollisionCircle(offsetY: 0.75, radius: 0.37),
    ],
  ),
];

/// The safari bar's own evolution chain (Level 3) — same independent-
/// chain shape as [kEvolutionChainLevel2] (tiers 0-11, local to this
/// chain). Shorter than the first two chains (12 tiers, not 13) since
/// that's how many real ingredients this one's recipes actually need —
/// nothing architecturally requires every chain to be the same length.
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
/// Prosecco sits two tiers earlier here (8, not 10) than it first
/// launched at — per feedback it read too similar to Level 2's own
/// prosecco (also second-from-top there), so it's pulled forward,
/// off the capstone-adjacent spot.
const kEvolutionChainLevel3 = [
  Ingredient(
    id: 'lime',
    label: 'Lime Juice',
    color: Color(0xFF9ACD32),
    tier: 0,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lime.png',
    displayScale: 1.119,
  ),
  Ingredient(
    id: 'honey',
    label: 'Honey',
    color: Color(0xFFE8A317),
    tier: 1,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_honey.png',
    displayScale: 0.969,
    displayScaleX: 1.300,
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
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
    collisionProfile: [
      CollisionCircle(offsetY: -0.59, radius: 0.68),
      CollisionCircle(offsetY: -0.50, radius: 0.62),
      CollisionCircle(offsetY: 0.07, radius: 0.56),
      CollisionCircle(offsetY: 0.50, radius: 0.32),
      CollisionCircle(offsetY: 0.63, radius: 0.21),
      CollisionCircle(offsetY: 0.85, radius: 0.42),
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
    tier: 4,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_orange_slice.png',
    displayScale: 1.114,
  ),
  Ingredient(
    id: 'marula_liqueur',
    label: 'Marula Liqueur',
    color: Color(0xFFD2A857),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_marula.png',
    displayScale: 1.062,
    displayScaleX: 1.452,
    isAlcoholic: true,
  ),
  Ingredient(
    id: 'tonic',
    label: 'Tonic Water',
    color: Color(0xFFDCEFF5),
    tier: 6,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tonic.png',
    displayScale: 1.065,
    collisionCapsule: CollisionCapsule(halfLength: 0.418, radius: 0.603, offsetY: 0.194),
    extraCircles: [CollisionCircle(offsetX: 0.357, offsetY: -1.022, radius: 0.077)],
  ),
  Ingredient(
    id: 'mango',
    label: 'Mango',
    color: Color(0xFFFF8C42),
    tier: 7,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_mango.png',
    displayScale: 0.986,
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 8,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_prosecco.png',
    displayScale: 0.993,
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    collisionProfile: [
      CollisionCircle(offsetY: -0.95, radius: 0.27),
      CollisionCircle(offsetY: -0.55, radius: 0.34),
      CollisionCircle(offsetY: -0.15, radius: 0.28),
      CollisionCircle(offsetY: 0.45, radius: 0.07),
      CollisionCircle(offsetY: 0.95, radius: 0.37),
    ],
  ),
  Ingredient(
    id: 'ginger_beer',
    label: 'Ginger Beer',
    color: Color(0xFFC77A2B),
    tier: 9,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_ginger_beer.png',
    displayScale: 1.035,
    displayScaleX: 1.700,
  ),
  Ingredient(
    // A whole-fruit picture, not the poured-glass art Level 1's own
    // 'pineapple' uses — same reasoning (and same distinct-id fix) as
    // this chain's own 'orange_slice' above.
    id: 'pineapple_fruit',
    label: 'Pineapple',
    color: Color(0xFFF7C948),
    tier: 10,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_pineapple_fruit.png',
    displayScale: 1.087,
    displayScaleX: 1.700,
  ),
  Ingredient(
    id: 'safari_beer',
    label: 'Safari Beer',
    color: Color(0xFFC98A2C),
    tier: 11,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_safari_beer.png',
    displayScale: 0.875,
    isAlcoholic: true,
  ),
];

/// The piazza bar's own evolution chain (Level 4) — same independent-
/// chain shape as [kEvolutionChainLevel3] (tiers 0-12, local to this
/// chain), European-themed. Lemon/Vodka/Tonic/Prosecco reuse their
/// existing art and measurements directly (same pattern every later
/// chain has followed for ingredients that already exist); Ginger Ale
/// also reuses Level 3's Ginger Beer art file outright (same picture,
/// per feedback) under its own id/label, same as the Jug/Prosecco-style
/// shared-art reuse. Every genuinely new ingredient's displayScale/
/// displayScaleX is measured precisely up front, the same way Level 3's
/// retrofit was — no placeholder 1.0/1.0 defaults this time.
const kEvolutionChainLevel4 = [
  Ingredient(
    id: 'lemon',
    label: 'Lemon Juice',
    color: Color(0xFFFFF176),
    tier: 0,
    shape: GlassShape.jug,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_lemon.png',
    displayScale: 1.121,
  ),
  Ingredient(
    id: 'lemon_liqueur',
    label: 'Lemon Liqueur',
    color: Color(0xFFF5E663),
    tier: 1,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_lemon_liqueur.png',
    displayScale: 1.096,
    displayScaleX: 1.700,
    isAlcoholic: true,
  ),
  Ingredient(
    id: 'vodka',
    label: 'Vodka',
    color: Color(0xFFEAF6FA),
    tier: 2,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vodka.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
    isAlcoholic: true,
    isMiniShot: true,
  ),
  Ingredient(
    id: 'aperol',
    label: 'Aperol',
    color: Color(0xFFFF7F32),
    tier: 3,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_aperol.png',
    displayScale: 1.078,
    displayScaleX: 1.700,
    isAlcoholic: true,
  ),
  Ingredient(
    id: 'tonic',
    label: 'Tonic Water',
    color: Color(0xFFDCEFF5),
    tier: 4,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_tonic.png',
    displayScale: 1.065,
    collisionCapsule: CollisionCapsule(halfLength: 0.418, radius: 0.603, offsetY: 0.194),
    extraCircles: [CollisionCircle(offsetX: 0.357, offsetY: -1.022, radius: 0.077)],
  ),
  Ingredient(
    id: 'strawberry',
    label: 'Strawberry',
    color: Color(0xFFE23B5E),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_strawberry.png',
    displayScale: 1.078,
    displayScaleX: 1.398,
  ),
  Ingredient(
    id: 'elderflower_liqueur',
    label: 'Elderflower Liqueur',
    color: Color(0xFFEDE4B0),
    tier: 6,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_elderflower_liqueur.png',
    displayScale: 1.077,
    displayScaleX: 1.700,
    isAlcoholic: true,
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
    tier: 7,
    shape: GlassShape.mug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_ginger_beer.png',
    displayScale: 1.035,
    displayScaleX: 1.700,
  ),
  Ingredient(
    id: 'blackcurrant',
    label: 'Blackcurrant',
    color: Color(0xFF3B1E4A),
    tier: 8,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_blackcurrant.png',
    displayScale: 1.119,
    displayScaleX: 1.299,
  ),
  Ingredient(
    id: 'irish_cream',
    label: 'Irish Cream',
    color: Color(0xFF6B4226),
    tier: 9,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_irish_cream.png',
    displayScale: 0.924,
    displayScaleX: 1.232,
    isAlcoholic: true,
    isMiniShot: true,
  ),
  Ingredient(
    id: 'prosecco',
    label: 'Prosecco',
    color: Color(0xFFE8D9A0),
    tier: 10,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_prosecco.png',
    displayScale: 0.993,
    sizeMultiplier: 1.15,
    isAlcoholic: true,
    collisionProfile: [
      CollisionCircle(offsetY: -0.95, radius: 0.27),
      CollisionCircle(offsetY: -0.55, radius: 0.34),
      CollisionCircle(offsetY: -0.15, radius: 0.28),
      CollisionCircle(offsetY: 0.45, radius: 0.07),
      CollisionCircle(offsetY: 0.95, radius: 0.37),
    ],
  ),
  Ingredient(
    id: 'cognac',
    label: 'Cognac',
    color: Color(0xFFA6621E),
    tier: 11,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_cognac.png',
    displayScale: 1.050,
    displayScaleX: 1.592,
    isAlcoholic: true,
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
  ),
];

/// The evolution chain for [level] — 1 is the beach bar, 2 the rooftop,
/// 3 the safari, 4+ the piazza (currently the last one with real
/// content; a future Level 5 needs its own branch added here, same as
/// everywhere else this split appears — see cocktailRecipesForLevel,
/// GameScreen's recipe-list lookups, and GameStateNotifier's
/// highest-tier bucket selection, which all mirror this same
/// level->content mapping).
List<Ingredient> evolutionChainForLevel(int level) =>
    level >= 4 ? kEvolutionChainLevel4 : (level >= 3 ? kEvolutionChainLevel3 : (level >= 2 ? kEvolutionChainLevel2 : kEvolutionChain));

/// The actual throwable pool for a player whose lifetime record within
/// this level is [highestTierUnlocked] — [kThrowableTierCount] items
/// normally, growing by one (the very next tier up) once they've reached
/// [kExtraThrowableUnlockTier]. [level] picks which chain — see
/// [evolutionChainForLevel].
List<Ingredient> throwableIngredientsFor(int level, int highestTierUnlocked) {
  final chain = evolutionChainForLevel(level);
  final count = highestTierUnlocked >= kExtraThrowableUnlockTier ? kThrowableTierCount + 1 : kThrowableTierCount;
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
Ingredient findIngredientById(String id) =>
    [...kEvolutionChain, ...kEvolutionChainLevel2, ...kEvolutionChainLevel3, ...kEvolutionChainLevel4].firstWhere((i) => i.id == id);
