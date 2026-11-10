import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart' show migrateLegacyLevel5Tier;

const _kCreditsKey = 'credits';
const _kHighestTierKey = 'highest_tier_unlocked';
const _kHighestLevelReachedKey = 'highest_level_reached';
// The single old flag is kept as the migration source for menu music —
// existing installs' one saved preference carries over as their menu
// setting rather than silently resetting once it split into three.
const _kMusicEnabledKey = 'music_enabled';
const _kMenuMusicEnabledKey = 'menu_music_enabled';
const _kGameMusicEnabledKey = 'game_music_enabled';
const _kSfxEnabledKey = 'sfx_enabled';
const _kAllSoundMutedKey = 'all_sound_muted';
const _kCocktailModeEnabledKey = 'cocktail_mode_enabled';
const _kLocaleKey = 'app_locale';
const _kAdFreeForeverKey = 'ad_free_forever';
const _kAdFreeOneDayExpiryKey = 'ad_free_one_day_expiry_ms';
const _kAdFreeSubscriptionCachedKey = 'ad_free_subscription_cached';
const _kLastProgressSyncAtKey = 'last_progress_sync_at_ms';
const _kMixedCocktailIdsKey = 'mixed_cocktail_ids';

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

/// Storage key for [level]'s lifetime highest-tier record. Level 1 keeps
/// its original unsuffixed key so existing installs' records carry over.
String _highestTierKey(int level) =>
    level <= 1 ? _kHighestTierKey : 'highest_tier_unlocked_level$level';

/// The highest evolution tier ever reached on [level] (by dropping or
/// merging into it), across every game ever played. Level 1 defaults to 0;
/// every later level to -1 ("never reached"), so its very first tier still
/// counts as a new lifetime milestone worth its credit reward.
Future<int> loadHighestTierForLevel(int level) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(_highestTierKey(level)) ?? (level <= 1 ? 0 : -1);
}

Future<void> saveHighestTierForLevel(int level, int tier) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_highestTierKey(level), tier);
}

/// Every level's record at once, index 0 = Level 1.
Future<List<int>> loadHighestTiers(int levelCount) async {
  await _migrateLegacyLevel5Record();
  return [for (var l = 1; l <= levelCount; l++) await loadHighestTierForLevel(l)];
}

const _kLevel5OrderMigratedKey = 'level5_order_v2';

/// Level 5's chain was reordered after build 20, and its record is a
/// position in the chain — remap it once so it names the same ingredient.
Future<void> _migrateLegacyLevel5Record() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kLevel5OrderMigratedKey) ?? false) return;
  final old = prefs.getInt(_highestTierKey(5));
  if (old != null) await prefs.setInt(_highestTierKey(5), migrateLegacyLevel5Tier(old));
  await prefs.setBool(_kLevel5OrderMigratedKey, true);
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

/// When this device's local progress was last confirmed in sync with its
/// Google-account backup — set after every successful push (see
/// GameStateNotifier._pushProgressToServer) and read by progress_sync.dart
/// to tell "another device has pushed more recently than we last synced"
/// apart from "we're the freshest copy," which is what lets credits (the
/// one progress field that isn't safely mergeable via a plain max(), since
/// spending legitimately lowers it) pick the right side instead of always
/// trending upward. Null until the very first successful push.
Future<DateTime?> loadLastProgressSyncAt() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_kLastProgressSyncAtKey);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> saveLastProgressSyncAt(DateTime time) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kLastProgressSyncAtKey, time.millisecondsSinceEpoch);
}

/// Every cocktail recipe id this player has ever completed, across every
/// game/level ever played — unlike [BoardState.completedCocktailIds]
/// (which resets on every new game/level, tracking only the current
/// run's own order-chasing progress), this one only ever grows. Backs
/// the Guide/Cocktails/Cocktail-detail screens' "ever mixed" tracking —
/// not touched by Settings' "Reset Progress" (same lifetime-record
/// treatment as high scores, not the tier/level record it does reset).
Future<Set<String>> loadMixedCocktailIds() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getStringList(_kMixedCocktailIdsKey) ?? const []).toSet();
}

Future<void> saveMixedCocktailIds(Set<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(_kMixedCocktailIdsKey, ids.toList());
}

/// Settings' "Reset Progress" — puts the evolution/level record back to
/// where a brand new install starts, without touching credits (an
/// explicit, separate decision the player didn't ask to also lose) or
/// anything about the run currently in progress, which the caller
/// handles (see GameStateNotifier.resetProgression).
Future<void> resetTierProgression() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kHighestTierKey, 0);
  for (var level = 2; level <= 20; level++) {
    await prefs.remove(_highestTierKey(level));
  }
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

/// The gameplay screen's top-left mute button — a hard override on top
/// of [loadMenuMusicEnabled]/[loadGameMusicEnabled]/[loadSfxEnabled]
/// rather than a replacement for them, so turning it back off (sound
/// back on) restores whatever those were already set to instead of
/// forcing everything on. Off by default.
Future<bool> loadAllSoundMuted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kAllSoundMutedKey) ?? false;
}

Future<void> saveAllSoundMuted(bool muted) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kAllSoundMutedKey, muted);
}

/// Whether cocktails drive progression — on by default (the game's
/// normal mode), toggled from Settings. Off switches the level-up
/// condition from "every cocktail plus the jug" to just "merge the two
/// highest items" (reach the jug/capstone tier on its own) and hides
/// the progress-tabs row — see GameStateNotifier._checkLevelUp and
/// GameScreen's own use of this.
Future<bool> loadCocktailModeEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kCocktailModeEnabledKey) ?? true;
}

Future<void> saveCocktailModeEnabled(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kCocktailModeEnabledKey, enabled);
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

/// Whether the Forever ad-removal purchase has ever been made — permanent
/// once true, never reset (see PurchaseService, which is the only writer).
Future<bool> loadAdFreeForever() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kAdFreeForeverKey) ?? false;
}

Future<void> saveAdFreeForever(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kAdFreeForeverKey, value);
}

/// When the 1-Day ad-removal purchase's grant runs out — null if it's
/// never been bought (or ran out and wasn't renewed). A future timestamp
/// here means ads are currently suppressed regardless of anything else.
Future<DateTime?> loadAdFreeOneDayExpiry() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_kAdFreeOneDayExpiryKey);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> saveAdFreeOneDayExpiry(DateTime expiry) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_kAdFreeOneDayExpiryKey, expiry.millisecondsSinceEpoch);
}

/// Best-effort local cache of "was the Monthly/Yearly subscription active
/// last time PurchaseService checked with Play Billing" — used only so
/// the UI doesn't flash ads on for the moment between app launch and that
/// live re-check finishing; the live check (not this cache) is always the
/// actual source of truth once it completes.
Future<bool> loadAdFreeSubscriptionCached() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kAdFreeSubscriptionCachedKey) ?? false;
}

Future<void> saveAdFreeSubscriptionCached(bool active) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kAdFreeSubscriptionCachedKey, active);
}

const _kHowToPlaySeenKey = 'how_to_play_seen';

/// Whether the How to Play walkthrough has already been offered on first
/// launch (see MenuScreen._maybeShowGuide).
Future<bool> loadHowToPlaySeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kHowToPlaySeenKey) ?? false;
}

Future<void> saveHowToPlaySeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHowToPlaySeenKey, true);
}
