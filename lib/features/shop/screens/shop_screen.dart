import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/continue_fallback_video_screen.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../game/providers/game_state_provider.dart';

/// Shop: the credit-for-ad row, plus the four ad-removal purchases (1
/// Day/Monthly/Yearly/Forever — see purchase_service.dart). Everything
/// else on the main menu's Shop tile is still "coming soon".
class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _watching = false;
  String? _statusMessage;

  /// Keyed by product id (see kAdFreeProductIds) — empty until
  /// [_loadProducts] resolves, and stays empty (not an error state) if
  /// Play Console doesn't have these products configured yet, so each
  /// row just falls back to showing its baseline price instead of a
  /// broken-looking blank.
  Map<String, ProductDetails> _products = {};
  AdFreeTier? _purchasingTier;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final details = await purchaseService.queryProducts();
      if (!mounted) return;
      setState(() => _products = {for (final d in details) d.id: d});
    } catch (_) {
      // Soft failure — rows fall back to their baseline price text.
    }
  }

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
      // No real ad available — same fallback the game-over "watch ad to
      // continue" offer uses (see GameScreen._watchAdToContinue) rather
      // than leaving this as a dead end: a short video that has to be
      // watched to completion, same reward on finishing it.
      onNotReady: () async {
        if (!mounted) return;
        setState(() => _watching = false);
        final watched = await showContinueFallbackVideo(context, locale);
        if (!mounted) return;
        if (watched) {
          ref.read(gameStateProvider.notifier).addAdCredits(kShopAdCreditReward);
          setState(() => _statusMessage = tr(locale, 'shop_credits_earned'));
        }
      },
    );
  }

  Future<void> _buyAdFree(AppLocale locale, AdFreeTier tier) async {
    if (_purchasingTier != null) return;
    final details = _products[kAdFreeProductIds[tier]];
    if (details == null) {
      setState(() => _statusMessage = tr(locale, 'purchase_not_available'));
      return;
    }
    setState(() {
      _purchasingTier = tier;
      _statusMessage = null;
    });
    try {
      await purchaseService.buy(details);
    } catch (_) {
      if (mounted) setState(() => _statusMessage = tr(locale, 'purchase_failed'));
    } finally {
      if (mounted) setState(() => _purchasingTier = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);
    final adFree = ref.watch(adFreeProvider).value ?? false;
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
                    const SizedBox(height: 24),
                    WoodTitlePlank(
                      title: tr(locale, 'shop_remove_ads_title'),
                      icon: Icons.block_rounded,
                      width: plankWidth,
                      height: plankHeight,
                      assetPath: 'assets/images/menu_board_3.png',
                    ),
                    const SizedBox(height: 10),
                    _AdFreeRow(
                      tier: AdFreeTier.oneDay,
                      details: _products[kAdFreeProductIds[AdFreeTier.oneDay]],
                      purchasing: _purchasingTier == AdFreeTier.oneDay,
                      disabled: _purchasingTier != null,
                      onBuy: () => _buyAdFree(locale, AdFreeTier.oneDay),
                      width: plankWidth,
                      height: plankHeight,
                      locale: locale,
                      fallbackPrice: '£0.25',
                    ),
                    const SizedBox(height: 10),
                    _AdFreeRow(
                      tier: AdFreeTier.monthly,
                      details: _products[kAdFreeProductIds[AdFreeTier.monthly]],
                      purchasing: _purchasingTier == AdFreeTier.monthly,
                      disabled: _purchasingTier != null,
                      onBuy: () => _buyAdFree(locale, AdFreeTier.monthly),
                      width: plankWidth,
                      height: plankHeight,
                      locale: locale,
                      fallbackPrice: '£1.99',
                    ),
                    const SizedBox(height: 10),
                    _AdFreeRow(
                      tier: AdFreeTier.yearly,
                      details: _products[kAdFreeProductIds[AdFreeTier.yearly]],
                      purchasing: _purchasingTier == AdFreeTier.yearly,
                      disabled: _purchasingTier != null,
                      onBuy: () => _buyAdFree(locale, AdFreeTier.yearly),
                      width: plankWidth,
                      height: plankHeight,
                      locale: locale,
                      fallbackPrice: '£7.99',
                    ),
                    const SizedBox(height: 10),
                    _AdFreeRow(
                      tier: AdFreeTier.forever,
                      details: _products[kAdFreeProductIds[AdFreeTier.forever]],
                      purchasing: _purchasingTier == AdFreeTier.forever,
                      disabled: _purchasingTier != null,
                      onBuy: () => _buyAdFree(locale, AdFreeTier.forever),
                      width: plankWidth,
                      height: plankHeight,
                      locale: locale,
                      fallbackPrice: '£19.99',
                    ),
                    if (adFree) ...[
                      const SizedBox(height: 14),
                      Text(
                        tr(locale, 'shop_ads_free_forever'),
                        style: const TextStyle(color: AppColors.mint, fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
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

/// One ad-removal tier's row — same plank/layout shape as the
/// watch-an-ad row above it, just with a Buy button and a price pulled
/// from Play Console via [details] once it's loaded (falling back to
/// [fallbackPrice], this project's baseline GBP price, while that query
/// is still in flight or if the product isn't configured yet).
class _AdFreeRow extends StatelessWidget {
  final AdFreeTier tier;
  final ProductDetails? details;
  final bool purchasing;
  final bool disabled;
  final VoidCallback onBuy;
  final double width;
  final double height;
  final AppLocale locale;
  final String fallbackPrice;

  const _AdFreeRow({
    required this.tier,
    required this.details,
    required this.purchasing,
    required this.disabled,
    required this.onBuy,
    required this.width,
    required this.height,
    required this.locale,
    required this.fallbackPrice,
  });

  String get _tierLabelKey => switch (tier) {
    AdFreeTier.oneDay => 'ads_free_1_day',
    AdFreeTier.monthly => 'ads_free_monthly',
    AdFreeTier.yearly => 'ads_free_yearly',
    AdFreeTier.forever => 'ads_free_forever',
  };

  @override
  Widget build(BuildContext context) {
    final price = details?.price ?? fallbackPrice;
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ColorfulPlankText(
                      text: tr(locale, _tierLabelKey),
                      fontSize: height * 0.18,
                      variant: kPlankTextVariant,
                      font: kPlankTextFont,
                      shadowStyle: kPlankShadowStyle,
                    ),
                    SizedBox(width: width * 0.02),
                    // Plain system font, not the decorative plank font —
                    // "Luckiest Guy" doesn't have a real £/currency glyph
                    // for every symbol Play Console can hand back, and
                    // silently substitutes the wrong character (a real
                    // £ rendered as what looked like a €) rather than
                    // erroring, so prices specifically stay off it.
                    Text(
                      price,
                      style: TextStyle(fontSize: height * 0.16, fontWeight: FontWeight.w800, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: disabled ? null : onBuy,
              child: Opacity(
                opacity: disabled && !purchasing ? 0.4 : 1.0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(12)),
                  child: purchasing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : Text(tr(locale, 'shop_buy_button'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
