/// Brief how-to-make text for each cocktail recipe (see
/// cocktail_recipe.dart), shown on the Info menu's cocktail detail
/// screen — keyed by [CocktailRecipe.id]. Deliberately only ever
/// references ingredients already in that recipe's own ingredientIds
/// list, never anything extra invented for flavor (a dash of bitters, a
/// sugar rim, ...) that isn't actually one of the things the player
/// throws/merges for it.
const kCocktailInstructions = <String, String>{
  'mojito': 'Muddle the mint and lime, add the rum, top with soda, and stir.',
  'screwdriver': 'Pour the vodka over ice, then top with orange juice and stir.',
  'rum_punch': 'Shake the rum with the lime, orange, and lemon juice, then pour over ice.',
  'cherry_daiquiri': 'Shake the rum, cherry, and lime juice with ice, then strain into a glass.',
  'rum_and_coke': 'Pour the rum over ice and top with cola.',
  'cosmopolitan': 'Shake the vodka with the cranberry, lime, and orange juice, then strain into a glass.',
  'blue_hawaiian': 'Blend the rum, blue curaçao, and pineapple juice with ice, then garnish with the cherry.',
  'espresso_martini': 'Shake the vodka and coffee liqueur hard with ice, then strain into a glass.',
  'bramble': 'Shake the gin and lime juice with ice, then top with the blackberry.',
  'melon_sour': 'Shake the vodka, lime juice, and melon liqueur with ice, then garnish with the cherry.',
  'martini': 'Stir the gin and vermouth with ice, then strain into a glass.',
  'gin_and_tonic': 'Pour the gin over ice, top with tonic water, and add a squeeze of lime.',
  'manhattan': 'Stir the whisky and vermouth with ice, then garnish with the cherry.',
  'bellini': 'Pour the peach juice into a glass and top with prosecco.',
};
