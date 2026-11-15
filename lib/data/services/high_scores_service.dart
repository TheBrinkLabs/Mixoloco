import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kHighScoresKey = 'high_scores';
const _kHighScoreDetailsKey = 'high_score_details';

/// The level a high score finished on and the best evolution tier
/// reached there — kept locally beside the plain score list (which is
/// what syncs to the Google backup). Backed up too since build 31; a
/// score restored from an older backup simply has no details.
class HighScoreDetail {
  final int level;
  final int tier;
  const HighScoreDetail({required this.level, required this.tier});
}

/// [details] as plain JSON-able maps: {"12345": {"level": 2, "tier": 7}}.
/// Also the shape the Google backup stores (see LeagueRepository).
Map<String, Object> highScoreDetailsToJson(Map<int, HighScoreDetail> details) => {
  for (final e in details.entries) '${e.key}': {'level': e.value.level, 'tier': e.value.tier},
};

/// The reverse of [highScoreDetailsToJson]; skips anything malformed.
Map<int, HighScoreDetail> highScoreDetailsFromJson(Map<String, dynamic>? json) {
  final out = <int, HighScoreDetail>{};
  for (final e in (json ?? const {}).entries) {
    final score = int.tryParse(e.key);
    final v = e.value;
    if (score == null || v is! Map || v['level'] is! int || v['tier'] is! int) continue;
    out[score] = HighScoreDetail(level: v['level'] as int, tier: v['tier'] as int);
  }
  return out;
}

/// Overwrites the stored details outright (progress_sync.dart's merge).
Future<void> saveHighScoreDetails(Map<int, HighScoreDetail> details) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kHighScoreDetailsKey, jsonEncode(highScoreDetailsToJson(details)));
}

/// Details for whichever of the saved high scores have them, by score.
Future<Map<int, HighScoreDetail>> loadHighScoreDetails() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kHighScoreDetailsKey);
  if (raw == null) return {};
  try {
    return highScoreDetailsFromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return {};
  }
}

/// How many locally-saved scores the "High Scores" menu shows.
const kMaxHighScores = 5;

/// The top [kMaxHighScores] scores ever finished, highest first.
Future<List<int>> loadHighScores() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kHighScoresKey);
  if (raw == null) return [];
  return (jsonDecode(raw) as List).cast<int>();
}

/// Files a finished game's [score] into the local top-[kMaxHighScores]
/// list (highest first, ties broken by whichever was already there) and
/// returns the updated list. [level]/[tier] are stored as that score's
/// [HighScoreDetail].
Future<List<int>> recordScore(int score, {required int level, required int tier}) async {
  final scores = await loadHighScores();
  scores.add(score);
  scores.sort((a, b) => b.compareTo(a));
  final top = scores.take(kMaxHighScores).toList();
  await saveHighScores(top);
  if (top.contains(score)) {
    final details = await loadHighScoreDetails();
    details[score] = HighScoreDetail(level: level, tier: tier);
    details.removeWhere((s, _) => !top.contains(s));
    await saveHighScoreDetails(details);
  }
  return top;
}

/// Overwrites the local top-[kMaxHighScores] list outright — used by
/// progress_sync.dart to apply a merged (local ∪ server) list after
/// signing in with Google, where the caller's already done the
/// union/sort/truncate itself rather than filing one score at a time.
Future<void> saveHighScores(List<int> scores) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kHighScoresKey, jsonEncode(scores));
}
