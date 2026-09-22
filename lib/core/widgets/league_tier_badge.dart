import 'package:flutter/material.dart';

const _bronze = Color(0xFFCD7F32);
const _silver = Color(0xFFC0C0C8);
const _gold = Color(0xFFFFD54A);

Color colorForTier(String tier) {
  switch (tier) {
    case 'silver':
      return _silver;
    case 'gold':
      return _gold;
    default:
      return _bronze;
  }
}

String labelForTier(String tier) {
  switch (tier) {
    case 'silver':
      return 'SILVER';
    case 'gold':
      return 'GOLD';
    default:
      return 'BRONZE';
  }
}

/// A small pill showing a league tier — bronze/silver/gold, colour-coded.
/// Used on the league screen's header and next to each leaderboard row's
/// outcome (promoted/relegated/stayed).
class LeagueTierBadge extends StatelessWidget {
  final String tier;
  final double fontSize;
  const LeagueTierBadge({super.key, required this.tier, this.fontSize = 11});

  @override
  Widget build(BuildContext context) {
    final color = colorForTier(tier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        labelForTier(tier),
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: color),
      ),
    );
  }
}
