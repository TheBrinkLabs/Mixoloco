import 'dart:math';

/// Fallback nickname for players who skip the league profile setup —
/// never blocks play, just gives them something displayable on the
/// leaderboard. Ported from Capitle's own nickname_generator.dart.
String generateFallbackNickname() {
  final n = 1000 + Random().nextInt(9000);
  return 'Player$n';
}
