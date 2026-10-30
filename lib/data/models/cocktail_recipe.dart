import 'ingredient.dart' show evolutionChainForLevel, kLevelCount;

/// A cocktail order — the set of ingredient ids that must physically touch
/// each other on the table (forming one connected cluster of items at
/// their respective evolution tiers, whatever those tiers currently look
/// like) to fulfil it. Order within [ingredientIds] doesn't matter.
class CocktailRecipe {
  final String id;
  final String name;
  final List<String> ingredientIds;
  final String assetPath;

  /// Credits to buy this order from the Cocktail Menu — 200 for the
  /// first (Mojito), rising 50 at a time down the list to 500 for the
  /// last (Blue Hawaiian). Shown as plain code-rendered text in the
  /// Cocktail Menu overlay rather than baked into the sign art, so this
  /// stays the single source of truth for what's actually charged.
  final int price;

  const CocktailRecipe({
    required this.id,
    required this.name,
    required this.ingredientIds,
    required this.assetPath,
    required this.price,
  });
}

/// The cocktail orders on offer, drawn from [kEvolutionChain]'s ingredient
/// ids, in Cocktail Menu display order. The very first order of a fresh
/// game is always [kStarterCocktailId] (free); every order after that has
/// to be bought from the Cocktail Menu with credits — there's no more
/// automatic cycling, since the evolution chain itself already gates
/// difficulty (you can't complete an order needing rum before you've
/// merged your way up to rum).
const kStarterCocktailId = 'screwdriver';

const kCocktailRecipes = [
  CocktailRecipe(
    // Replaced Vodka Tonic when Tonic Water left the evolution chain —
    // same slot, same price; rum+cherry+lime, the true Daiquiri citrus,
    // rather than vodka+cherry+lemon.
    id: 'cherry_daiquiri',
    name: 'Cherry Daiquiri',
    ingredientIds: ['rum', 'cherry', 'lime'],
    assetPath: 'assets/images/game/c_cherry_daiquiri.png',
    price: 200,
  ),
  CocktailRecipe(
    id: 'mojito',
    name: 'Mojito',
    ingredientIds: ['rum', 'lime', 'soda', 'mint'],
    assetPath: 'assets/images/mohito.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'screwdriver',
    name: 'Screwdriver',
    ingredientIds: ['vodka', 'orange'],
    assetPath: 'assets/images/game/c_screwdriver.png',
    price: 300,
  ),
  CocktailRecipe(
    // Lemon added alongside lime — a real rum punch is usually a mix of
    // citrus juices, and this also gives Lemon its first recipe use
    // since Cherry Daiquiri took its old vodka+cherry+lemon slot.
    id: 'rum_punch',
    name: 'Rum Punch',
    ingredientIds: ['rum', 'lime', 'orange', 'lemon'],
    assetPath: 'assets/images/rum_punch.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'rum_and_coke',
    name: 'Rum & Coke',
    ingredientIds: ['rum', 'cola'],
    assetPath: 'assets/images/rum_and_coke.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'cosmopolitan',
    name: 'Cosmopolitan',
    ingredientIds: ['vodka', 'cranberry', 'lime', 'orange'],
    assetPath: 'assets/images/cosmopolitan.png',
    price: 450,
  ),
  CocktailRecipe(
    // Cherry added on top of the original three — genuinely traditional
    // here too, a maraschino cherry is the standard Blue Hawaiian garnish.
    id: 'blue_hawaiian',
    name: 'Blue Hawaiian',
    ingredientIds: ['rum', 'blue_curacao', 'pineapple', 'cherry'],
    assetPath: 'assets/images/game/c_blue_hawaiian.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktail =>
    kCocktailRecipes.firstWhere((r) => r.id == kStarterCocktailId);

/// The rooftop bar's own cocktail list (Level 2) — ordered easiest to
/// hardest by the highest evolution tier each recipe needs (see
/// GameStateNotifier for how that ordering was derived), same 200-500
/// price range and 50-credit steps as [kCocktailRecipes]. Old Fashioned
/// didn't survive this round: Whisky + Cherry alone didn't read as an
/// Old Fashioned, and Manhattan (Whisky + Vermouth + Cherry) covers the
/// same whisky-and-a-cherry-garnish territory using ingredients already
/// on this chain, so it took that slot instead.
const kStarterCocktailIdLevel2 = 'espresso_martini';

const kCocktailRecipesLevel2 = [
  CocktailRecipe(
    id: 'espresso_martini',
    name: 'Espresso Martini',
    ingredientIds: ['vodka', 'coffee_liqueur'],
    assetPath: 'assets/images/espresso_martini.png',
    price: 200,
  ),
  CocktailRecipe(
    id: 'melon_sour',
    name: 'Melon Sour',
    ingredientIds: ['vodka', 'lime', 'melon_liqueur', 'cherry'],
    assetPath: 'assets/images/melon_sour.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'bramble',
    name: 'Bramble',
    ingredientIds: ['gin', 'lime', 'blackberry'],
    assetPath: 'assets/images/bramble.png',
    price: 300,
  ),
  CocktailRecipe(
    id: 'martini',
    name: 'Martini',
    ingredientIds: ['gin', 'vermouth'],
    assetPath: 'assets/images/martini.png',
    price: 350,
  ),
  CocktailRecipe(
    // Replaced Gin & Tonic — moved to the safari bar's own list (Level
    // 3) instead, since it's a genuinely good fit there too and
    // recipes shouldn't duplicate across levels. That left Tonic Water
    // with no recipe using it at all (nothing else on this chain calls
    // for it), so rather than restructure the chain itself (tier
    // positions are load-bearing: saved per-player tier records, radius
    // scaling, the throwable rotation), this gives Tonic a new,
    // genuinely distinct home — Vermouth & Tonic ("vermut con tónica")
    // is a real, increasingly fashionable drink in its own right, not
    // just a reskinned G&T. Same price/list position as the recipe it
    // replaced, so the difficulty ladder doesn't shift.
    id: 'vermouth_tonic',
    name: 'Vermouth & Tonic',
    ingredientIds: ['vermouth', 'tonic', 'lime'],
    assetPath: 'assets/images/vermouth_&_tonic.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'manhattan',
    name: 'Manhattan',
    ingredientIds: ['whisky', 'vermouth', 'cherry'],
    assetPath: 'assets/images/manhattan.png',
    price: 450,
  ),
  CocktailRecipe(
    id: 'bellini',
    name: 'Bellini',
    ingredientIds: ['peach', 'prosecco'],
    assetPath: 'assets/images/bellini.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktailLevel2 =>
    kCocktailRecipesLevel2.firstWhere((r) => r.id == kStarterCocktailIdLevel2);

/// The safari bar's own cocktail list (Level 3) — same shape as
/// [kCocktailRecipesLevel2], ordered easiest to hardest by highest
/// evolution tier needed. Dawa is a genuine classic (Swahili for
/// "medicine"): vodka, honey, and lime, traditionally muddled together
/// with a "dawa stick". Golden Pineapple is this list's own addition
/// (not from the original brainstorm) — Pineapple Juice otherwise had
/// no recipe using it at all, the same "ingredient nothing calls for"
/// gap Tonic Water hit above, worth closing the same way rather than
/// leaving it on the chain unused.
const kStarterCocktailIdLevel3 = 'dawa';

const kCocktailRecipesLevel3 = [
  CocktailRecipe(
    id: 'dawa',
    name: 'Dawa',
    ingredientIds: ['vodka', 'honey', 'lime'],
    assetPath: 'assets/images/game/c_dawa.png',
    price: 200,
  ),
  CocktailRecipe(
    id: 'marula_sunset',
    name: 'Marula Sunset',
    ingredientIds: ['marula_liqueur', 'orange_slice'],
    assetPath: 'assets/images/marula_sunset.png',
    price: 250,
  ),
  CocktailRecipe(
    // Reuses the same picture as before — moved here from Level 2 (see
    // that list's own vermouth_tonic comment), the drink itself didn't
    // change, just which bar's menu it's on.
    id: 'gin_and_tonic',
    name: 'Gin & Tonic',
    ingredientIds: ['gin', 'tonic', 'lime'],
    assetPath: 'assets/images/gin_and_tonic.png',
    price: 300,
  ),
  CocktailRecipe(
    id: 'mimosa',
    name: 'Mimosa',
    ingredientIds: ['prosecco', 'orange_slice'],
    assetPath: 'assets/images/mimosa.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'citrus_mule',
    name: 'Citrus Mule',
    ingredientIds: ['vodka', 'ginger_beer', 'lime'],
    assetPath: 'assets/images/game/c_citrus_mule.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'savanna_gold_mule',
    name: 'Savanna Gold Mule',
    ingredientIds: ['marula_liqueur', 'ginger_beer', 'mango'],
    assetPath: 'assets/images/savanna_gold_mule.png',
    price: 450,
  ),
  CocktailRecipe(
    // Vodka, not ginger beer — per feedback the original had no alcohol
    // in it at all. Close to a real "Pineapple Upside-Down" martini.
    id: 'golden_pineapple',
    name: 'Golden Pineapple',
    ingredientIds: ['pineapple_fruit', 'honey', 'vodka'],
    assetPath: 'assets/images/golden_pineapple.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktailLevel3 =>
    kCocktailRecipesLevel3.firstWhere((r) => r.id == kStarterCocktailIdLevel3);

/// The piazza bar's own cocktail list (Level 4) — same shape as
/// [kCocktailRecipesLevel3], ordered easiest to hardest by highest
/// evolution tier needed. Kir Royale and Hugo Spritz reuse the same
/// fruit/liqueur-plus-Prosecco shape Bellini/Mimosa/Marula Sunset already
/// established on the earlier two chains; Hugo Spritz specifically needs
/// Mint (and Prosecco/Elderflower Liqueur) to actually read as a Hugo
/// Spritz rather than just another fruit spritz — real recipes use a
/// lime wedge, but Lime isn't on this chain (already reused on Levels
/// 1-3), so Lemon stands in for it; the real recipe's splash of soda is
/// dropped to keep it to a reasonable ingredient count. French 75
/// uses Cognac rather than gin — the original Harry's New York Bar
/// version did too, and gin itself isn't on this chain (already reused
/// on Level 2 and Level 3, so Level 4 leans into its own new spirits
/// instead). Strawberry Mule continues the "spirit + ginger ale/beer +
/// fruit" mule shape Level 3's Citrus Mule/Savanna Gold Mule already
/// established, taking the slot an Aperol Spritz would have — Aperol
/// itself is a brand name, not a generic spirit, so neither it nor a
/// recipe built around it belongs here.
const kStarterCocktailIdLevel4 = 'vodka_lemon';

const kCocktailRecipesLevel4 = [
  CocktailRecipe(
    id: 'vodka_lemon',
    name: 'Vodka Lemon',
    ingredientIds: ['vodka', 'lemon'],
    assetPath: 'assets/images/vodka_lemon.png',
    price: 200,
  ),
  CocktailRecipe(
    id: 'kir_royale',
    name: 'Kir Royale',
    ingredientIds: ['blackcurrant', 'prosecco'],
    assetPath: 'assets/images/kir_royale.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'french_75',
    name: 'French 75',
    ingredientIds: ['cognac', 'lemon', 'prosecco'],
    assetPath: 'assets/images/game/c_french_75.png',
    price: 300,
  ),
  CocktailRecipe(
    id: 'hugo_spritz',
    name: 'Hugo Spritz',
    // Lemon stands in for the real recipe's lime wedge — this chain
    // doesn't carry Lime (already on Levels 1-3), so Lemon's the
    // closest citrus actually available here.
    ingredientIds: ['mint', 'lemon', 'elderflower_liqueur', 'prosecco'],
    assetPath: 'assets/images/game/c_hugo_spritz.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'lemon_fizz',
    name: 'Lemon Fizz',
    ingredientIds: ['lemon_liqueur', 'tonic'],
    assetPath: 'assets/images/lemon_fizz.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'emerald_fizz',
    name: 'Emerald Fizz',
    ingredientIds: ['irish_cream', 'ginger_ale'],
    assetPath: 'assets/images/emerald_fizz.png',
    price: 450,
  ),
  CocktailRecipe(
    id: 'strawberry_mule',
    name: 'Strawberry Mule',
    ingredientIds: ['vodka', 'ginger_ale', 'strawberry'],
    assetPath: 'assets/images/strawberry_mule.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktailLevel4 =>
    kCocktailRecipesLevel4.firstWhere((r) => r.id == kStarterCocktailIdLevel4);

/// Jungle bar's own 7 recipes (Costa Rica/Caribbean-themed) — ordered by
/// rising ingredient tier complexity, same convention every earlier
/// level's price ladder follows. Guaro Sour is the starter: its 3
/// ingredients (sugar/guaro/lime) are this chain's lowest tiers, same
/// "cheap and immediately reachable" reasoning every other level's
/// starter follows.
const kStarterCocktailIdLevel5 = 'guaro_sour';

const kCocktailRecipesLevel5 = [
  CocktailRecipe(
    id: 'guaro_sour',
    name: 'Guaro Sour',
    ingredientIds: ['guaro', 'lime', 'sugar_cube'],
    assetPath: 'assets/images/guaro_sour.png',
    price: 200,
  ),
  CocktailRecipe(
    id: 'daiquiri',
    name: 'Daiquiri',
    ingredientIds: ['rum', 'lime', 'sugar_cube'],
    assetPath: 'assets/images/daiquiri.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'chiliguaro',
    name: 'Chiliguaro',
    ingredientIds: ['guaro', 'tomato_juice', 'hot_sauce', 'lime'],
    assetPath: 'assets/images/chiliguaro.png',
    price: 300,
  ),
  CocktailRecipe(
    id: 'cuba_libre',
    name: 'Cuba Libre',
    ingredientIds: ['rum', 'cola', 'lime'],
    assetPath: 'assets/images/cuba_libre.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'guaro_paloma',
    name: 'Guaro Paloma',
    ingredientIds: ['guaro', 'grapefruit', 'lime', 'soda'],
    assetPath: 'assets/images/guaro_paloma.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'banana_daiquiri',
    name: 'Banana Daiquiri',
    ingredientIds: ['rum', 'banana', 'lime', 'sugar_cube'],
    assetPath: 'assets/images/banana_daiquiri.png',
    price: 450,
  ),
  CocktailRecipe(
    id: 'pina_colada',
    name: 'Piña Colada',
    ingredientIds: ['rum', 'coconut', 'pineapple_fruit'],
    assetPath: 'assets/images/pina_colada.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktailLevel5 =>
    kCocktailRecipesLevel5.firstWhere((r) => r.id == kStarterCocktailIdLevel5);

/// The five "After Dark" signature cocktails, one per night level.
/// [price] here is a placeholder — [_nightMenu] assigns the real one.
const kNightSignatureCocktails = [
  CocktailRecipe(
    id: 'mai_tai',
    name: 'Mai Tai',
    ingredientIds: ['rum', 'lime', 'orange', 'mint', 'cherry'],
    assetPath: 'assets/images/mai_tai.png',
    price: 0,
  ),
  CocktailRecipe(
    id: 'bramble_royale',
    name: 'Bramble Royale',
    ingredientIds: ['gin', 'blackberry', 'lemon', 'prosecco'],
    assetPath: 'assets/images/bramble_royale.png',
    price: 0,
  ),
  CocktailRecipe(
    id: 'marula_espresso',
    name: 'Marula Espresso',
    ingredientIds: ['marula_liqueur', 'coffee_liqueur', 'vodka'],
    assetPath: 'assets/images/marula_espresso.png',
    price: 0,
  ),
  CocktailRecipe(
    id: 'caffe_corretto',
    name: 'Caffè Corretto',
    ingredientIds: ['grappa', 'coffee_liqueur', 'sugar_cube'],
    assetPath: 'assets/images/caffe_corretto.png',
    price: 0,
  ),
  CocktailRecipe(
    id: 'jungle_fire_margarita',
    name: 'Jungle Fire Margarita',
    ingredientIds: ['tequila', 'lime', 'hot_sauce', 'sugar_cube'],
    assetPath: 'assets/images/jungle_fire_margarita.png',
    price: 0,
  ),
];

CocktailRecipe _recipeById(String id) => [
  ...kCocktailRecipes,
  ...kCocktailRecipesLevel2,
  ...kCocktailRecipesLevel3,
  ...kCocktailRecipesLevel4,
  ...kCocktailRecipesLevel5,
  ...kNightSignatureCocktails,
].firstWhere((r) => r.id == id);

/// A night level's menu: the given recipes ordered by the highest tier
/// they need in [level]'s chain (ties by total tiers, then fewer
/// ingredients first) and priced 200..500 in that order — so a dearer
/// cocktail always needs a higher-evolved ingredient.
List<CocktailRecipe> _nightMenu(int level, List<String> ids) {
  final chain = evolutionChainForLevel(level);
  int tierOf(String id) => chain.indexWhere((i) => i.id == id);
  (int, int, int) key(CocktailRecipe r) {
    final tiers = r.ingredientIds.map(tierOf).toList();
    assert(!tiers.contains(-1), '${r.id} needs an ingredient missing from level $level');
    return (tiers.reduce((x, y) => x > y ? x : y), tiers.reduce((x, y) => x + y), tiers.length);
  }
  final recipes = ids.map(_recipeById).toList()
    ..sort((x, y) {
      final kx = key(x), ky = key(y);
      if (kx.$1 != ky.$1) return kx.$1.compareTo(ky.$1);
      if (kx.$2 != ky.$2) return kx.$2.compareTo(ky.$2);
      return kx.$3.compareTo(ky.$3);
    });
  return [
    for (var k = 0; k < recipes.length; k++)
      CocktailRecipe(
        id: recipes[k].id,
        name: recipes[k].name,
        ingredientIds: recipes[k].ingredientIds,
        assetPath: recipes[k].assetPath,
        price: 200 + 50 * k,
      ),
  ];
}

final kCocktailRecipesLevel6 = _nightMenu(6, [
  'daiquiri', 'cherry_daiquiri', 'mojito', 'cuba_libre', 'blue_hawaiian', 'banana_daiquiri', 'mai_tai',
]);
final kCocktailRecipesLevel7 = _nightMenu(7, [
  'espresso_martini', 'bramble', 'martini', 'gin_and_tonic', 'vermouth_tonic', 'manhattan', 'bramble_royale',
]);
final kCocktailRecipesLevel8 = _nightMenu(8, [
  'dawa', 'marula_sunset', 'gin_and_tonic', 'citrus_mule', 'savanna_gold_mule', 'golden_pineapple', 'marula_espresso',
]);
final kCocktailRecipesLevel9 = _nightMenu(9, [
  'vodka_lemon', 'espresso_martini', 'kir_royale', 'lemon_fizz', 'french_75', 'hugo_spritz', 'caffe_corretto',
]);
final kCocktailRecipesLevel10 = _nightMenu(10, [
  'guaro_sour', 'daiquiri', 'chiliguaro', 'cuba_libre', 'guaro_paloma', 'banana_daiquiri', 'jungle_fire_margarita',
]);

/// Every level's cocktail list, index 0 = Level 1.
final List<List<CocktailRecipe>> kCocktailRecipesByLevel = [
  kCocktailRecipes,
  kCocktailRecipesLevel2,
  kCocktailRecipesLevel3,
  kCocktailRecipesLevel4,
  kCocktailRecipesLevel5,
  kCocktailRecipesLevel6,
  kCocktailRecipesLevel7,
  kCocktailRecipesLevel8,
  kCocktailRecipesLevel9,
  kCocktailRecipesLevel10,
];

/// The cocktail list for [level] (1-based, clamped to [kLevelCount]).
List<CocktailRecipe> cocktailRecipesForLevel(int level) =>
    kCocktailRecipesByLevel[level.clamp(1, kLevelCount) - 1];

/// The free starter order for a fresh run at [level]. Levels 1-5 keep
/// their hand-picked starters; each night level starts on its cheapest.
CocktailRecipe starterCocktailForLevel(int level) => switch (level) {
  <= 1 => kStarterCocktail,
  2 => kStarterCocktailLevel2,
  3 => kStarterCocktailLevel3,
  4 => kStarterCocktailLevel4,
  5 => kStarterCocktailLevel5,
  _ => cocktailRecipesForLevel(level).first,
};
