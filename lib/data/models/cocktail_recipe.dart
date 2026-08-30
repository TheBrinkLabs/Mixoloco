/// A cocktail "order" — the set of ingredient ids the player must throw
/// down to the serving end, all together, to fulfil it. Order within
/// [ingredientIds] doesn't matter, only that every required ingredient
/// lands as part of the same throw group.
class CocktailRecipe {
  final String id;
  final String name;
  final List<String> ingredientIds;

  const CocktailRecipe({
    required this.id,
    required this.name,
    required this.ingredientIds,
  });
}

/// Starter recipes for tier 1 (the dodgy bar) — simple 2-3 ingredient
/// drinks. Later tiers introduce longer, more exotic recipes as the bar
/// itself gets fancier.
const kTier1Recipes = [
  CocktailRecipe(id: 'rum_and_coke', name: 'Rum & Coke', ingredientIds: ['rum', 'cola']),
  CocktailRecipe(id: 'screwdriver', name: 'Screwdriver', ingredientIds: ['orange', 'soda']),
  CocktailRecipe(id: 'rum_punch', name: 'Rum Punch', ingredientIds: ['rum', 'lime', 'orange']),
];
