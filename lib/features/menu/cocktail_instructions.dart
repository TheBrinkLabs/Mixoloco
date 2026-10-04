/// Brief, step-by-step how-to-make text for each cocktail recipe (see
/// cocktail_recipe.dart), shown on the Info menu's cocktail detail
/// screen — keyed by [CocktailRecipe.id]. Each step only ever
/// references ingredients already in that recipe's own ingredientIds
/// list, with exactly one deliberate exception: a dash of simple syrup,
/// on the handful of recipes where a real one actually calls for it
/// (Mojito, Rum Punch, Cherry Daiquiri, Bramble) — it isn't one of the
/// game's own throwable/mergeable ingredients, so it never appears on
/// the ingredients list above these steps, only in the step text
/// itself.
const kCocktailInstructions = <String, List<String>>{
  'mojito': [
    'Muddle the mint and lime in the glass.',
    'Add a dash of simple syrup.',
    'Pour in the rum.',
    'Fill with ice and top with soda.',
    'Stir gently and serve.',
  ],
  'screwdriver': [
    'Fill a glass with ice.',
    'Pour in the vodka.',
    'Top with orange juice.',
    'Stir and serve.',
  ],
  'rum_punch': [
    'Fill a shaker with ice.',
    'Add the rum, lime, orange, and lemon juice.',
    'Add a dash of simple syrup.',
    'Shake well.',
    'Strain over fresh ice.',
  ],
  'cherry_daiquiri': [
    'Fill a shaker with ice.',
    'Add the rum, cherry, and lime juice.',
    'Add a dash of simple syrup.',
    'Shake well.',
    'Strain into a chilled glass.',
  ],
  'rum_and_coke': [
    'Fill a glass with ice.',
    'Pour in the rum.',
    'Top with cola.',
    'Stir gently and serve.',
  ],
  'cosmopolitan': [
    'Fill a shaker with ice.',
    'Add the vodka, cranberry, lime, and orange juice.',
    'Shake well.',
    'Strain into a chilled glass.',
  ],
  'blue_hawaiian': [
    'Add the rum, blue curaçao, and pineapple juice to a blender with ice.',
    'Blend until smooth.',
    'Pour into a glass.',
    'Garnish with the cherry.',
  ],
  'espresso_martini': [
    'Fill a shaker with ice.',
    'Add the vodka and coffee liqueur.',
    'Shake hard until frothy.',
    'Strain into a chilled glass.',
  ],
  'bramble': [
    'Fill a glass with crushed ice.',
    'Pour in the gin and lime juice.',
    'Add a dash of simple syrup.',
    'Stir, then top with the blackberry.',
  ],
  'melon_sour': [
    'Fill a shaker with ice.',
    'Add the vodka, lime juice, and melon liqueur.',
    'Shake well.',
    'Strain into a glass and garnish with the cherry.',
  ],
  'martini': [
    'Fill a mixing glass with ice.',
    'Add the gin and vermouth.',
    "Stir well — don't shake.",
    'Strain into a chilled glass.',
  ],
  'gin_and_tonic': [
    'Fill a glass with ice.',
    'Pour in the gin.',
    'Top with tonic water.',
    'Add a squeeze of lime.',
  ],
  'manhattan': [
    'Fill a mixing glass with ice.',
    'Add the whisky and vermouth.',
    'Stir well.',
    'Strain into a glass and garnish with the cherry.',
  ],
  'bellini': [
    'Pour the peach juice into a chilled glass.',
    'Top slowly with prosecco.',
    'Stir gently and serve.',
  ],
  'vermouth_tonic': [
    'Fill a glass with ice.',
    'Pour in the vermouth.',
    'Top with tonic water.',
    'Garnish with a twist of lime.',
  ],
  'dawa': [
    'Muddle the honey and lime in the glass.',
    'Pour in the vodka.',
    'Fill with ice and stir well.',
  ],
  'marula_sunset': [
    'Fill a glass with ice.',
    'Pour in the marula liqueur.',
    'Top with orange juice and let it settle.',
  ],
  'citrus_mule': [
    'Fill a glass with ice.',
    'Pour in the vodka.',
    'Top with ginger beer.',
    'Add a squeeze of lime.',
  ],
  'savanna_gold_mule': [
    'Fill a glass with ice.',
    'Pour in the marula liqueur.',
    'Top with ginger beer.',
    'Add the mango.',
  ],
  'golden_pineapple': [
    'Fill a shaker with ice.',
    'Add the vodka, pineapple juice, and a dash of honey.',
    'Shake well.',
    'Strain into a chilled glass.',
  ],
  'mimosa': [
    'Pour the orange juice into a chilled glass.',
    'Top slowly with prosecco.',
    'Stir gently and serve.',
  ],
};
