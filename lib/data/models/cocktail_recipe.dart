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
    assetPath: 'assets/images/vermouth_tonic.png',
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
    ingredientIds: ['marula_liqueur', 'orange'],
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
    id: 'golden_pineapple',
    name: 'Golden Pineapple',
    ingredientIds: ['pineapple', 'honey', 'ginger_beer'],
    assetPath: 'assets/images/golden_pineapple.png',
    price: 450,
  ),
  CocktailRecipe(id: 'mimosa', name: 'Mimosa', ingredientIds: ['prosecco', 'orange'], assetPath: 'assets/images/mimosa.png', price: 500),
];

CocktailRecipe get kStarterCocktailLevel3 => kCocktailRecipesLevel3.firstWhere((r) => r.id == kStarterCocktailIdLevel3);
