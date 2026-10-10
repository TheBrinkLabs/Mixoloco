import 'package:flutter/material.dart';
import '../i18n/strings.dart';
import '../services/locale_provider.dart';

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

/// bronze_league.png's own aspect once cropped tight to its plate (was
/// 1408x768 with a lot of transparent padding baked in, cropped down
/// to 1238x452) — used to size it without letterboxing. gold_league.png/
/// silver_league.png were supplied and cropped the same way, landing
/// within a pixel or two of the same aspect, so this one constant covers
/// all three.
const kLeaguePlateAspect = 1238 / 452;

/// The engraved-metal plate art for every tier.
String? leagueAssetForTier(String tier) {
  switch (tier) {
    case 'gold':
      return 'assets/images/gold_league.png';
    case 'silver':
      return 'assets/images/silver_league.png';
    case 'bronze':
      return 'assets/images/bronze_league.png';
    default:
      return null;
  }
}

/// A league tier badge — the real engraved plate art
/// (assets/images/bronze_league.png etc) when one exists for [tier],
/// otherwise a colour-coded pill as a placeholder. Used both as the
/// league screen's own full-width header (pass [width]) and as a
/// small badge elsewhere (pass [fontSize] instead).
class LeagueTierBadge extends StatelessWidget {
  final String tier;
  final AppLocale locale;
  final double fontSize;

  /// When set, renders as a full-width banner at this width (height
  /// follows [kLeaguePlateAspect]) instead of the small auto-sized
  /// badge — the league screen's own header row.
  final double? width;
  const LeagueTierBadge({super.key, required this.tier, required this.locale, this.fontSize = 11, this.width});

  @override
  Widget build(BuildContext context) {
    final asset = leagueAssetForTier(tier);
    final color = colorForTier(tier);
    if (width != null) {
      final w = width!;
      final h = w / kLeaguePlateAspect;
      if (asset != null) {
        return Image.asset(asset, width: w, height: h, fit: BoxFit.contain);
      }
      return Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(h * 0.22),
          border: Border.all(color: color, width: 1.4),
        ),
        child: Text(
          '${labelForTier(tier, locale)} ${tr(locale, 'leaderboard')}',
          style: TextStyle(fontSize: h * 0.3, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: color),
        ),
      );
    }
    if (asset != null) {
      final height = fontSize * 3.6;
      return Image.asset(asset, height: height, width: height * kLeaguePlateAspect, fit: BoxFit.contain);
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
