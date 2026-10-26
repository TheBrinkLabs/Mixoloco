import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../services/locale_provider.dart';
import 'submenu_kit.dart';

const _bronze = Color(0xFFCD7F32);
const _bronzeDark = Color(0xFF8A5323);
const _silver = Color(0xFFC0C0C8);
const _silverDark = Color(0xFF86868E);
const _gold = Color(0xFFFFD54A);
const _goldDark = Color(0xFFB8860B);

Color _darkForTier(String tier) {
  switch (tier) {
    case 'silver':
      return _silverDark;
    case 'gold':
      return _goldDark;
    default:
      return _bronzeDark;
  }
}

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

String labelForTier(String tier, AppLocale locale) {
  switch (tier) {
    case 'silver':
      return tr(locale, 'tier_silver');
    case 'gold':
      return tr(locale, 'tier_gold');
    default:
      return tr(locale, 'tier_bronze');
  }
}

/// A league tier badge — a gold-rimmed blue tab with a tier-coloured
/// coin for the league screen's own full-width header (pass [width]),
/// or a small colour-coded pill elsewhere (pass [fontSize] instead, no
/// [width] — e.g. a future compact badge; nothing currently calls this
/// branch, but it's kept as the no-width fallback shape).
class LeagueTierBadge extends StatelessWidget {
  final String tier;
  final AppLocale locale;
  final double fontSize;
  final double? width;
  const LeagueTierBadge({super.key, required this.tier, required this.locale, this.fontSize = 11, this.width});

  @override
  Widget build(BuildContext context) {
    final color = colorForTier(tier);
    if (width != null) {
      final w = width!;
      final dark = _darkForTier(tier);
      return Container(
        width: w,
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SubmenuColors.gold, width: 2),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom],
          ),
          boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: dark, width: 2),
                gradient: RadialGradient(colors: [color, dark]),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${labelForTier(tier, locale)} ${tr(locale, 'league_word')}'.toUpperCase(),
              style: const TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: Colors.white),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        labelForTier(tier, locale),
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: color),
      ),
    );
  }
}
