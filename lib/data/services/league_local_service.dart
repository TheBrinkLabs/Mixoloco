import 'package:shared_preferences/shared_preferences.dart';

const _kNicknameKey = 'league_nickname';
const _kLastClaimedWeekIdKey = 'league_last_claimed_week_id';

/// The player's league nickname, cached locally so the app can tell
/// "has this player set one up yet" (and prefill the setup screen on a
/// re-visit) without a Firestore round trip. The actual source of truth
/// once set is players/{uid}.nickname — this is purely a local mirror.
Future<String?> loadNickname() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kNicknameKey);
}

Future<void> saveNickname(String nickname) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kNicknameKey, nickname);
}

/// The most recent weekId whose weekHistory credit reward (see
/// rollover.js's creditsAwarded field) has already been added to the
/// player's local credit balance — guards against re-awarding the same
/// week's credits every time the league screen is reopened. Only tracks
/// the single most recent claimed week (not a full set), which is
/// enough for the normal case of opening the app at least once between
/// rollovers; a player who skips several weeks entirely only ever gets
/// credited for the most recent one they check, same trade-off Capitle
/// accepts for its own once-per-week reveal.
Future<String?> loadLastClaimedWeekId() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kLastClaimedWeekIdKey);
}

Future<void> saveLastClaimedWeekId(String weekId) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kLastClaimedWeekIdKey, weekId);
}
