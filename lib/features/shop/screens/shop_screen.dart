import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../game/providers/game_state_provider.dart';

/// The one Shop feature that exists so far — watch a rewarded ad for a
/// one-off credit top-up. Everything else on the main menu's Shop tile
/// is still "coming soon"; this screen only exists to host this row
/// until there's an actual item catalog to sell.
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _watching = false;
  String? _statusMessage;

  void _watchAdForCredits(AppLocale locale) {
    if (_watching) return;
    setState(() {
      _watching = true;
      _statusMessage = null;
    });
    adService.showRewardedAd(
      RewardedAdSlot.shopCredits,
      onReward: () {
        ref.read(gameStateProvider.notifier).addAdCredits(kShopAdCreditReward);
        if (mounted) setState(() { _watching = false; _statusMessage = tr(locale, 'shop_credits_earned'); });
      },
      onDismissedWithoutReward: () {
        if (mounted) setState(() => _watching = false);
      },
      onNotReady: () {
        if (mounted) setState(() { _watching = false; _statusMessage = tr(locale, 'ad_not_ready'); });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WoodTitlePlank(
                      title: tr(locale, 'shop'),
                      icon: Icons.storefront_rounded,
                      width: plankWidth,
                      height: plankHeight,
                      assetPath: 'assets/images/menu_board_3.png',
                    ),
                    const SizedBox(height: 10),
                    WoodPlank(
                      width: plankWidth,
                      height: plankHeight,
                      assetPath: 'assets/images/menu_board_3.png',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: plankWidth * 0.06),
                        child: Row(
                          children: [
                            Icon(Icons.smart_display_rounded, size: plankHeight * 0.3, color: kPlankIconColor, shadows: kPlankIconShadows),
                            SizedBox(width: plankWidth * 0.03),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: ColorfulPlankText(
                                  text: '${tr(locale, 'shop_watch_ad_title')} $kShopAdCreditReward',
                                  fontSize: plankHeight * 0.2,
                                  variant: kPlankTextVariant,
                                  font: kPlankTextFont,
                                  shadowStyle: kPlankShadowStyle,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _watching ? null : () => _watchAdForCredits(locale),
                              child: Opacity(
                                opacity: _watching ? 0.6 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(12)),
                                  child: _watching
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                      : Text(
                                          tr(locale, 'shop_watch_ad_button'),
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(_statusMessage!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                    const SizedBox(height: 18),
                    Text('${tr(locale, 'credits')}: ${board.credits}', style: const TextStyle(color: AppColors.textLight, fontSize: 15, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
