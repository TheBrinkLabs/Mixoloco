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
/// 1.0; only rum and cranberry currently deviate (0.95, "5% smaller"
/// per feedback that they read a touch large next to their neighbors).
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
/// content is than it is tall), capped at 1.7 — raised from an original
/// 1.45 per feedback that items should actually touch (a very slight
/// overlap is fine, a gap isn't), but 1.7 is itself a deliberate ceiling,
/// not every ingredient's true ratio: removing the cap entirely made the
/// most extreme cases (soda 2.73x, champagne/prosecco 3.4x+) stretch
/// dramatically enough to change the glass's actual shape, which was a
/// worse outcome than the small residual gap those specific items still
/// have at 1.7x. 1.7 itself is empirically chosen, not derived — it's
/// where vodka/rum/blue curaçao (already right at ~1.65x) read as a
/// perfectly natural "slightly wider glass" rather than a visibly
/// stretched one.
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

  /// Whether this ingredient counts toward the Alcohol-Free purchase's
  /// clear-the-table effect (see MixolocoGame.clearAlcoholic). A flag
  /// rather than a hardcoded id list at the call site — the rooftop
  /// chain alone adds five more alcoholic ingredients (Gin, Whisky,
  /// Vermouth, Coffee Liqueur, Melon Liqueur) on top of the beach
  /// chain's three (Vodka, Rum, Blue Curaçao), and a per-ingredient flag
  /// scales to that without the clearing logic needing to know the full
  /// list by name.
  final bool isAlcoholic;

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
    sizeMultiplier: 0.95,
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
    displayScaleX: 1.7,
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
    sizeMultiplier: 0.95,
  ),
  Ingredient(
    id: 'pineapple',
    label: 'Pineapple Juice',
    color: Color(0xFFF7C948),
    tier: 11,
    shape: GlassShape.tumbler,
    debris: DebrisType.peel,
    assetPath: 'assets/images/ingredient_pineapple.png',
    displayScale: 1.050,
    displayScaleX: 1.7,
  ),
  Ingredient(
    id: 'jug',
    label: 'Jug of Cocktails',
    color: Color(0xFFE0A845),
    tier: 12,
    shape: GlassShape.jug,
    debris: DebrisType.glass,
    assetPath: 'assets/images/cocktail_jug.png',
    displayScale: 1.066,
    displayScaleX: 1.7,
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
  ),
  Ingredient(
    id: 'gin',
    label: 'Gin',
    color: Color(0xFFF0F4F0),
    tier: 5,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_gin.png',
    displayScale: 1.044,
    displayScaleX: 1.652,
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
    id: 'vermouth',
    label: 'Vermouth',
    color: Color(0xFFD9B97A),
    tier: 7,
    shape: GlassShape.martini,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_vermouth.png',
    displayScale: 0.970,
    displayScaleX: 1.7,
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
    displayScaleX: 1.7,
  ),
  Ingredient(
    id: 'whisky',
    label: 'Whisky',
    color: Color(0xFFB5651D),
    tier: 10,
    shape: GlassShape.tumbler,
    debris: DebrisType.glass,
    assetPath: 'assets/images/ingredient_whisky.png',
    displayScale: 1.434,
    displayScaleX: 1.559,
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
    displayScaleX: 1.7,
    isAlcoholic: true,
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
    displayScaleX: 1.7,
    isAlcoholic: true,
  ),
];

/// The actual throwable pool for a player whose lifetime record within
/// this level is [highestTierUnlocked] — [kThrowableTierCount] items
/// normally, growing by one (the very next tier up) once they've reached
/// [kExtraThrowableUnlockTier]. [level] picks which chain: 1 for the
/// beach bar, 2 for the rooftop bar.
List<Ingredient> throwableIngredientsFor(int level, int highestTierUnlocked) {
  final chain = level >= 2 ? kEvolutionChainLevel2 : kEvolutionChain;
  final count = highestTierUnlocked >= kExtraThrowableUnlockTier ? kThrowableTierCount + 1 : kThrowableTierCount;
  return chain.take(count).toList();
}

/// Resolves a CocktailRecipe.ingredientIds entry back to its Ingredient —
/// searches both chains, since a handful of ids (cherry, vodka, lime)
/// are shared between them. Throws if [id] isn't in either — recipes are
/// only ever built from real ingredient ids, so that would mean a
/// genuine data bug worth surfacing loudly rather than swallowing.
Ingredient findIngredientById(String id) =>
    [...kEvolutionChain, ...kEvolutionChainLevel2].firstWhere((i) => i.id == id);
