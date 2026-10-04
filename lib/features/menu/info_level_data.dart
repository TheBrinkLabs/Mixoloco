import '../../data/models/cocktail_recipe.dart';
import '../../data/models/ingredient.dart';

/// One playable bar's worth of content for the Info menu's Ingredients/
/// Cocktails screens (see ingredients_screen.dart/cocktails_screen.dart) —
/// each level gets its own swipeable page, backed by that level's own
/// photo so it reads as "the Beach bar" vs "the Rooftop bar" rather than
/// a plain list with a label.
class InfoLevelData {
  final String name;
  final String backgroundAssetPath;
  final List<Ingredient> chain;
  final List<CocktailRecipe> recipes;
  const InfoLevelData({required this.name, required this.backgroundAssetPath, required this.chain, required this.recipes});
}

const kInfoLevels = [
  InfoLevelData(name: 'Beach', backgroundAssetPath: 'assets/images/beach_background.png', chain: kEvolutionChain, recipes: kCocktailRecipes),
  InfoLevelData(name: 'Rooftop', backgroundAssetPath: 'assets/images/rooftop_background.png', chain: kEvolutionChainLevel2, recipes: kCocktailRecipesLevel2),
  InfoLevelData(name: 'Safari', backgroundAssetPath: 'assets/images/safari_background.png', chain: kEvolutionChainLevel3, recipes: kCocktailRecipesLevel3),
];
