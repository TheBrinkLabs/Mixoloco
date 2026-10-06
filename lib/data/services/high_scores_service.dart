import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

const _kHighScoresKey = 'high_scores';

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
/// returns the updated list.
Future<List<int>> recordScore(int score) async {
  final scores = await loadHighScores();
  scores.add(score);
  scores.sort((a, b) => b.compareTo(a));
  final top = scores.take(kMaxHighScores).toList();
  await saveHighScores(top);
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
