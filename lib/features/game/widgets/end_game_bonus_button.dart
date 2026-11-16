import 'package:flutter/material.dart';

import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart' show AppLocale;
import '../../../core/widgets/submenu_kit.dart';

/// Credits for the end-of-game "watch an ad" bonus — more than the Shop's
/// usual [kShopAdCreditReward], as a last-chance reward when a game ends.
const kEndGameAdCreditReward = 500;

/// The once-per-game "watch an ad for +500 credits" offer on the Game Over
/// and Game Complete panels. Stateless — GameScreen owns whether it's been
/// claimed (so it survives the overlay rebuilding) and runs the ad.
class EndGameBonusButton extends StatelessWidget {
  final bool claimed;
  final bool watching;
  final VoidCallback onWatch;
  final AppLocale locale;
  const EndGameBonusButton({
    super.key,
    required this.claimed,
    required this.watching,
    required this.onWatch,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    if (claimed) {
      return SizedBox(
        height: 50,
        child: Center(
          child: OutlinedLabel(
            text: tr(locale, 'end_bonus_claimed').replaceFirst('{n}', '$kEndGameAdCreditReward'),
            fontSize: 18,
            fill: SubmenuColors.gold,
            stroke: SubmenuColors.goldEdge,
            strokeWidth: 4,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: watching ? null : onWatch,
      child: Container(
        height: 50,
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SubmenuColors.goldEdge, width: 2),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
          ),
          boxShadow: const [BoxShadow(color: SubmenuColors.goldEdge, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            ClipOval(child: Image.asset('assets/images/coins.webp', width: 36, height: 36, fit: BoxFit.cover)),
            const SizedBox(width: 10),
            Expanded(
              child: watching
                  ? const Center(
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: SubmenuColors.goldEdge)),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr(locale, 'end_bonus_button').replaceFirst('{n}', '$kEndGameAdCreditReward'),
                        maxLines: 1,
                        style: const TextStyle(fontFamily: 'Lilita One', fontSize: 17, color: SubmenuColors.goldEdge),
                      ),
                    ),
            ),
            const Icon(Icons.play_circle_fill_rounded, color: SubmenuColors.goldEdge, size: 26),
          ],
        ),
      ),
    );
  }
}
