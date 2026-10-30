import 'package:flutter/foundation.dart' show kDebugMode;
import '../../core/services/audio_settings_provider.dart';
import '../../core/widgets/bar_backdrop.dart' show backgroundAssetPathForLevel;
import '../../data/models/cocktail_recipe.dart';
import '../../data/models/ingredient.dart';
import '../../data/repositories/league_repository.dart' show highestTierFor;
import '../../data/services/progression_service.dart' show loadMixedCocktailIds;

/// One playable level's worth of content for the Info menu's Ingredients/
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

  /// The tracks this level actually plays (see [musicTracksForLevel]).
  final List<String> songs;

  /// A daytime level's bar's fourth track, which only unlocks once its
  /// "After Dark" level ([bonusSongLevel]) is reached — null on an After
  /// Dark level itself, where it's already part of [songs].
  final String? bonusSong;
  final int? bonusSongLevel;

  const InfoLevelData({
    required this.level,
    required this.name,
    required this.backgroundAssetPath,
    required this.chain,
    required this.recipes,
    required this.songs,
    this.bonusSong,
    this.bonusSongLevel,
  });
}

/// Debug builds show every Guide page fully unlocked, so all the content
/// can be checked without playing through it. Never true in release.
const kGuideShowsAll = kDebugMode;

bool guideLevelReached(int level, int highestLevelReached) =>
    kGuideShowsAll || level <= highestLevelReached;

/// The highest tier the Guide treats as collected on [level].
int guideTierFor(List<int> highestTiers, int level) =>
    kGuideShowsAll ? 1 << 20 : highestTierFor(highestTiers, level);

/// The cocktails the Guide treats as mixed.
Future<Set<String>> guideMixedCocktailIds() async => kGuideShowsAll
    ? {for (final level in kInfoLevels) for (final recipe in level.recipes) recipe.id}
    : loadMixedCocktailIds();

final kInfoLevels = [
  for (var level = 1; level <= kLevelCount; level++)
    InfoLevelData(
      level: level,
      name: levelName(level),
      backgroundAssetPath: backgroundAssetPathForLevel(level),
      chain: evolutionChainForLevel(level),
      recipes: cocktailRecipesForLevel(level),
      songs: musicTracksForLevel(level),
      bonusSong: isAfterDarkLevel(level) ? null : bonusTrackForLevel(level),
      bonusSongLevel: isAfterDarkLevel(level) ? null : level + kBarNames.length,
    ),
];
