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
  CocktailRecipe(id: 'mojito', name: 'Mojito', ingredientIds: ['rum', 'lime', 'soda', 'mint'], assetPath: 'assets/images/mohito.png', price: 200),
  CocktailRecipe(id: 'screwdriver', name: 'Screwdriver', ingredientIds: ['vodka', 'orange'], assetPath: 'assets/images/screwdriver.png', price: 250),
  CocktailRecipe(
    // Lemon added alongside lime — a real rum punch is usually a mix of
    // citrus juices, and this also gives Lemon its first recipe use
    // since Cherry Daiquiri took its old vodka+cherry+lemon slot.
    id: 'rum_punch',
    name: 'Rum Punch',
    ingredientIds: ['rum', 'lime', 'orange', 'lemon'],
    assetPath: 'assets/images/rum_punch.png',
    price: 300,
  ),
  CocktailRecipe(
    // Replaced Vodka Tonic when Tonic Water left the evolution chain —
    // same slot, same price; rum+cherry+lime, the true Daiquiri citrus,
    // rather than vodka+cherry+lemon.
    id: 'cherry_daiquiri',
    name: 'Cherry Daiquiri',
    ingredientIds: ['rum', 'cherry', 'lime'],
    assetPath: 'assets/images/cherry_daiquiri.png',
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
    assetPath: 'assets/images/blue_hawaiian.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktail => kCocktailRecipes.firstWhere((r) => r.id == kStarterCocktailId);

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
    id: 'bramble',
    name: 'Bramble',
    ingredientIds: ['gin', 'lime', 'blackberry'],
    assetPath: 'assets/images/bramble.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'melon_sour',
    name: 'Melon Sour',
    ingredientIds: ['vodka', 'lime', 'melon_liqueur', 'cherry'],
    assetPath: 'assets/images/melon_sour.png',
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

CocktailRecipe get kStarterCocktailLevel2 => kCocktailRecipesLevel2.firstWhere((r) => r.id == kStarterCocktailIdLevel2);

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
  CocktailRecipe(id: 'dawa', name: 'Dawa', ingredientIds: ['vodka', 'honey', 'lime'], assetPath: 'assets/images/dawa.png', price: 200),
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
    id: 'citrus_mule',
    name: 'Citrus Mule',
    ingredientIds: ['vodka', 'ginger_beer', 'lime'],
    assetPath: 'assets/images/citrus_mule.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'savanna_gold_mule',
    name: 'Savanna Gold Mule',
    ingredientIds: ['marula_liqueur', 'ginger_beer', 'mango'],
    assetPath: 'assets/images/savanna_gold_mule.png',
    price: 400,
  ),
  CocktailRecipe(
    // Vodka, not ginger beer — per feedback the original had no alcohol
    // in it at all. Close to a real "Pineapple Upside-Down" martini.
    id: 'golden_pineapple',
    name: 'Golden Pineapple',
    ingredientIds: ['pineapple_fruit', 'honey', 'vodka'],
    assetPath: 'assets/images/golden_pineapple.png',
    price: 450,
  ),
  CocktailRecipe(id: 'mimosa', name: 'Mimosa', ingredientIds: ['prosecco', 'orange_slice'], assetPath: 'assets/images/mimosa.png', price: 500),
];

CocktailRecipe get kStarterCocktailLevel3 => kCocktailRecipesLevel3.firstWhere((r) => r.id == kStarterCocktailIdLevel3);

/// The piazza bar's own cocktail list (Level 4) — same shape as
/// [kCocktailRecipesLevel3], ordered easiest to hardest by highest
/// evolution tier needed. Kir Royale and Hugo Spritz reuse the same
/// fruit/liqueur-plus-Prosecco shape Bellini/Mimosa/Marula Sunset already
/// established on the earlier two chains; Hugo Spritz specifically needs
/// Mint (and Prosecco/Elderflower Liqueur) to actually read as a Hugo
/// Spritz rather than just another fruit spritz — real recipes also
/// include a splash of soda and a lime wedge, both dropped here to keep
/// it to the chain's own established 2-3-ingredient shape. French 75
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
    id: 'lemon_fizz',
    name: 'Lemon Fizz',
    ingredientIds: ['lemon_liqueur', 'tonic'],
    assetPath: 'assets/images/lemon_fizz.png',
    price: 250,
  ),
  CocktailRecipe(
    id: 'strawberry_mule',
    name: 'Strawberry Mule',
    ingredientIds: ['vodka', 'ginger_ale', 'strawberry'],
    assetPath: 'assets/images/strawberry_mule.png',
    price: 300,
  ),
  CocktailRecipe(
    id: 'emerald_fizz',
    name: 'Emerald Fizz',
    ingredientIds: ['irish_cream', 'ginger_ale'],
    assetPath: 'assets/images/emerald_fizz.png',
    price: 350,
  ),
  CocktailRecipe(
    id: 'kir_royale',
    name: 'Kir Royale',
    ingredientIds: ['blackcurrant', 'prosecco'],
    assetPath: 'assets/images/kir_royale.png',
    price: 400,
  ),
  CocktailRecipe(
    id: 'hugo_spritz',
    name: 'Hugo Spritz',
    ingredientIds: ['mint', 'elderflower_liqueur', 'prosecco'],
    assetPath: 'assets/images/hugo_spritz.png',
    price: 450,
  ),
  CocktailRecipe(
    id: 'french_75',
    name: 'French 75',
    ingredientIds: ['cognac', 'lemon', 'prosecco'],
    assetPath: 'assets/images/french_75.png',
    price: 500,
  ),
];

CocktailRecipe get kStarterCocktailLevel4 => kCocktailRecipesLevel4.firstWhere((r) => r.id == kStarterCocktailIdLevel4);

/// The cocktail list for [level] — see evolutionChainForLevel (in
/// ingredient.dart) for the matching evolution-chain split and why a
/// future Level 5 needs a parallel branch added here too.
List<CocktailRecipe> cocktailRecipesForLevel(int level) =>
    level >= 4 ? kCocktailRecipesLevel4 : (level >= 3 ? kCocktailRecipesLevel3 : (level >= 2 ? kCocktailRecipesLevel2 : kCocktailRecipes));

/// The free starter order for a fresh run at [level] — see
/// [cocktailRecipesForLevel].
CocktailRecipe starterCocktailForLevel(int level) =>
    level >= 4 ? kStarterCocktailLevel4 : (level >= 3 ? kStarterCocktailLevel3 : (level >= 2 ? kStarterCocktailLevel2 : kStarterCocktail));
