import 'package:shared_preferences/shared_preferences.dart';

const _kCreditsKey = 'credits';
const _kHighestTierKey = 'highest_tier_unlocked';
const _kHighestTierLevel2Key = 'highest_tier_unlocked_level2';
const _kHighestLevelReachedKey = 'highest_level_reached';
// The single old flag is kept as the migration source for menu music —
// existing installs' one saved preference carries over as their menu
// setting rather than silently resetting once it split into three.
const _kMusicEnabledKey = 'music_enabled';
const _kMenuMusicEnabledKey = 'menu_music_enabled';
const _kGameMusicEnabledKey = 'game_music_enabled';
const _kSfxEnabledKey = 'sfx_enabled';
const _kLocaleKey = 'app_locale';

/// The player's current credit balance — persists across games and app
/// restarts (unlike score, which resets every run).
Future<int> loadCredits() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kCreditsKey) ?? 0;
}

Future<void> saveCredits(int credits) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kCreditsKey, credits);
}

/// The highest evolution tier ever reached (by dropping or merging into
/// it), across every game ever played — starts at 0 (Peppermint).
Future<int> loadHighestTier() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kHighestTierKey) ?? 0;
}

Future<void> saveHighestTier(int tier) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kHighestTierKey, tier);
}

/// The highest rooftop-bar (Level 2) evolution tier ever reached —
/// mirrors [loadHighestTier]/[saveHighestTier], but for
/// kEvolutionChainLevel2. -1 (not 0) is "never reached" here specifically
/// so the very first Level 2 tier ever seen (Cherry, tier 0) still counts
/// as a genuinely new lifetime milestone worth its credit reward.
Future<int> loadHighestTierLevel2() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kHighestTierLevel2Key) ?? -1;
}

Future<void> saveHighestTierLevel2(int tier) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kHighestTierLevel2Key, tier);
}

/// The highest bar level ever reached (1 = beach, 2 = rooftop) — once
/// this reaches 2, every new game starts there directly instead of back
/// on the beach, and the "Unlocked" display on the home screen shows a
/// Level 2 ingredient regardless of how far into that chain a fresh run
/// has gotten (even its lowest tier outranks every Level 1 tier).
Future<int> loadHighestLevelReached() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_kHighestLevelReachedKey) ?? 1;
}

Future<void> saveHighestLevelReached(int level) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kHighestLevelReachedKey, level);
}

/// Settings' "Reset Progress" — puts the evolution/level record back to
/// where a brand new install starts, without touching credits (an
/// explicit, separate decision the player didn't ask to also lose) or
/// anything about the run currently in progress, which the caller
/// handles (see GameStateNotifier.resetProgression).
Future<void> resetTierProgression() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kHighestTierKey, 0);
  await prefs.remove(_kHighestTierLevel2Key);
  await prefs.setInt(_kHighestLevelReachedKey, 1);
}

/// Whether background music should play on the menu screen — on by
/// default, toggled from Settings. Falls back to the old single
/// music-enabled flag (pre-dating separate menu/game toggles) if it was
/// ever set, so an existing install's one preference still applies.
Future<bool> loadMenuMusicEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kMenuMusicEnabledKey) ?? prefs.getBool(_kMusicEnabledKey) ?? true;
}

Future<void> saveMenuMusicEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kMenuMusicEnabledKey, enabled);
}

/// Whether background music should play during gameplay — on by
/// default, toggled from Settings, independent of [loadMenuMusicEnabled].
Future<bool> loadGameMusicEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kGameMusicEnabledKey) ?? true;
}

Future<void> saveGameMusicEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kGameMusicEnabledKey, enabled);
}

/// Whether sound effects (merge pop, cocktail pour) should play — on by
/// default, toggled from Settings, independent of the music toggles.
Future<bool> loadSfxEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kSfxEnabledKey) ?? true;
}

Future<void> saveSfxEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kSfxEnabledKey, enabled);
}

/// The selected app language — a plain language code ('en'/'es') rather
/// than the AppLocale enum itself, so this file doesn't need to depend
/// on the i18n layer. Defaults to English.
Future<String> loadLocaleCode() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLocaleKey) ?? 'en';
}

Future<void> saveLocaleCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLocaleKey, code);
}
