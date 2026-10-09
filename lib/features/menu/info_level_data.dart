import '../../core/services/audio_settings_provider.dart';
import '../../data/models/cocktail_recipe.dart';
import '../../data/models/ingredient.dart';

/// One playable bar's worth of content for the Info menu's Ingredients/
/// Cocktails/Songs screens (see ingredients_screen.dart/
/// cocktails_screen.dart/songs_screen.dart) — each level gets its own
/// swipeable page, backed by that level's own photo so it reads as "the
/// Beach bar" vs "the Rooftop bar" rather than a plain list with a
/// label.
class InfoLevelData {
  final int level;
  final String name;
  final String backgroundAssetPath;
  final List<Ingredient> chain;
  final List<CocktailRecipe> recipes;
  final List<String> songs;
  const InfoLevelData({
    required this.level,
    required this.name,
    required this.backgroundAssetPath,
    required this.chain,
    required this.recipes,
    required this.songs,
  });
}

const kInfoLevels = [
  InfoLevelData(
    level: 1,
    name: 'Beach',
    backgroundAssetPath: 'assets/images/beach_background.png',
    chain: kEvolutionChain,
    recipes: kCocktailRecipes,
    songs: kMusicTracks,
  ),
  InfoLevelData(
    level: 2,
    name: 'Rooftop',
    backgroundAssetPath: 'assets/images/rooftop_background.png',
    chain: kEvolutionChainLevel2,
    recipes: kCocktailRecipesLevel2,
    songs: kMusicTracksLevel2,
  ),
  InfoLevelData(
    level: 3,
    name: 'Safari',
    backgroundAssetPath: 'assets/images/safari_background.png',
    chain: kEvolutionChainLevel3,
    recipes: kCocktailRecipesLevel3,
    songs: kMusicTracksLevel3,
  ),
  InfoLevelData(
    level: 4,
    name: 'Piazza',
    backgroundAssetPath: 'assets/images/piazza_background.png',
    chain: kEvolutionChainLevel4,
    recipes: kCocktailRecipesLevel4,
    songs: kMusicTracksLevel4,
  ),
];
