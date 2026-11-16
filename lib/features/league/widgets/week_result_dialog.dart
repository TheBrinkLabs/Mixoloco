import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/submenu_kit.dart';

/// Shown once, the first time a player opens Rankings after finishing in
/// last week's global top 10 (see LeagueController.refresh, which has
/// already banked the credits by then — "Collect" just closes it). Built
/// from the sub-menu kit so it reads as part of the same family: the navy
/// gold-rimmed panel, a gold ribbon over its top edge, Lilita headings.
///
/// [result] is the players/{uid}/weekHistory/{weekId} doc rollover.js
/// writes: rank, score, creditsAwarded, isWinner.
class WeekResultDialog extends StatelessWidget {
  final Map<String, dynamic> result;
  final AppLocale locale;
  const WeekResultDialog({super.key, required this.result, required this.locale});

  static Future<void> show(BuildContext context, Map<String, dynamic> result, AppLocale locale) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (_) => WeekResultDialog(result: result, locale: locale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rank = (result['rank'] as int?) ?? 0;
    final score = (result['score'] as int?) ?? 0;
    final credits = (result['creditsAwarded'] as int?) ?? 0;
    final isWinner = rank == 1 || ((result['isWinner'] as bool?) ?? false);

    final headline = isWinner ? tr(locale, 'league_result_won') : tr(locale, 'league_result_placed').replaceFirst('{n}', '$rank');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 26),
              child: SubmenuPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 6),
                    _Medal(rank: rank),
                    const SizedBox(height: 14),
                    OutlinedLabel(
                      text: headline,
                      fontSize: 24,
                      fill: Colors.white,
                      stroke: SubmenuColors.ring,
                      strokeWidth: 4,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr(locale, 'league_result_score').replaceFirst('{n}', formatScore(score)),
                      textAlign: TextAlign.center,
                      style: submenuNunito(size: 14, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
                    ),
                    if (credits > 0) ...[
                      const SizedBox(height: 16),
                      _CreditsPill(text: tr(locale, 'league_credits_earned').replaceFirst('{n}', formatScore(credits))),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 160,
                      child: SubmenuGoldButton(
                        label: tr(locale, 'league_result_collect').toUpperCase(),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            Positioned(top: 0, child: _SmallRibbon(text: tr(locale, 'league_result_ribbon'))),
          ],
        ),
      ),
    );
  }
}

/// 1234567 -> "1,234,567".
String formatScore(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// [RibbonTitle]'s look at dialog size — the full-size one is built for a
/// screen header and is too big over a small panel.
class _SmallRibbon extends StatelessWidget {
  final String text;
  const _SmallRibbon({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SubmenuColors.goldEdge, width: 3),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
        ),
        boxShadow: [
          const BoxShadow(color: SubmenuColors.goldEdge, offset: Offset(0, 4)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), offset: const Offset(0, 8), blurRadius: 14),
        ],
      ),
      child: OutlinedLabel(
        text: text.toUpperCase(),
        fontSize: 22,
        fill: Colors.white,
        stroke: SubmenuColors.goldEdge,
        strokeWidth: 4,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// A round medal with the finishing place on it: gold, silver and bronze
/// for the podium, the sub-menu's blue plate with a gold rim for 4th–10th.
/// 1st gets a crown on top.
class _Medal extends StatelessWidget {
  final int rank;
  const _Medal({required this.rank});

  @override
  Widget build(BuildContext context) {
    final (List<Color> face, Color edge) = switch (rank) {
      1 => (const [SubmenuColors.goldTop, SubmenuColors.goldBottom], SubmenuColors.goldEdge),
      2 => (const [Color(0xFFF2F6FA), Color(0xFFAEBBC8)], const Color(0xFF55636F)),
      3 => (const [Color(0xFFF0A868), Color(0xFFB8642A)], const Color(0xFF5E2C0C)),
      _ => (const [SubmenuColors.plateTop, SubmenuColors.plateBottom], SubmenuColors.gold),
    };
    const size = 96.0;
    return SizedBox(
      width: size,
      height: size + 18,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: edge, width: 4),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: face),
              boxShadow: [
                BoxShadow(color: edge, offset: const Offset(0, 4)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), offset: const Offset(0, 10), blurRadius: 16),
              ],
            ),
            alignment: Alignment.center,
            child: OutlinedLabel(
              text: '#$rank',
              fontSize: 40,
              fill: Colors.white,
              stroke: rank <= 3 ? edge : SubmenuColors.ring,
              strokeWidth: 6,
            ),
          ),
          if (rank == 1) const Positioned(top: -6, child: Text('👑', style: TextStyle(fontSize: 34))),
        ],
      ),
    );
  }
}

/// The credits reward: the coin stack and the amount, in an inset pill.
class _CreditsPill extends StatelessWidget {
  final String text;
  const _CreditsPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
      decoration: BoxDecoration(
        color: SubmenuColors.inset,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: SubmenuColors.gold, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Image.asset('assets/images/coins.webp', width: 34, height: 34, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          OutlinedLabel(text: text, fontSize: 22, fill: SubmenuColors.gold, stroke: SubmenuColors.ring, strokeWidth: 4),
        ],
      ),
    );
  }
}
