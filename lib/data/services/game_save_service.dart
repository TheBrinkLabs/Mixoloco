import 'package:shared_preferences/shared_preferences.dart';

const _kSavedGameKey = 'saved_game_state';

/// Stores/retrieves the in-progress run as an opaque JSON string — kept
/// primitive-typed (no BoardState/Ingredient references) the same way
/// progression_service.dart stays primitive-typed, so the actual
/// encode/decode into a real BoardState lives in game_state_provider.dart
/// (which already has the model imports this would otherwise duplicate).
Future<void> saveGameJson(String json) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_kSavedGameKey, json);
}

Future<String?> loadGameJson() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSavedGameKey);
}
