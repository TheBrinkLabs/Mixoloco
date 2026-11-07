import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/widgets/continue_fallback_video_screen.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../game/providers/game_state_provider.dart';
import '../../menu/info_level_data.dart';

/// Shop: the credit-for-ad row, the two credit packs, plus the four
/// ad-removal purchases (1 Day/Monthly/Yearly/Forever — see
/// purchase_service.dart) — restyled onto the sub-menu redesign's
/// grouped-inset-row system (see settings_screen.dart, the first screen
/// this pattern shipped on) rather than the older BlueTile boards.
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
  CreditPack? _purchasingPack;
  bool _purchasingUnlock = false;

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

  // Mirrors GetCreditsDialog._buyCreditPack — the credit award itself
  // arrives separately via GameStateNotifier's global
  // creditPackPurchaseProvider listener, not awaited here.
  Future<void> _buyCreditPack(AppLocale locale, CreditPack pack) async {
    if (_purchasingPack != null) return;
    final details = _products[kCreditPackProductIds[pack]];
    if (details == null) {
      setState(() => _statusMessage = tr(locale, 'purchase_not_available'));
      return;
    }
    setState(() {
      _purchasingPack = pack;
      _statusMessage = null;
    });
    try {
      await purchaseService.buy(details);
    } catch (_) {
      if (mounted) setState(() => _statusMessage = tr(locale, 'purchase_failed'));
    } finally {
      if (mounted) setState(() => _purchasingPack = null);
    }
  }

  Future<void> _buyUnlockLevel(AppLocale locale) async {
    if (_purchasingUnlock) return;
    final details = _products[kUnlockLevelProductId];
    if (details == null) {
      setState(() => _statusMessage = tr(locale, 'purchase_not_available'));
      return;
    }
    setState(() {
      _purchasingUnlock = true;
      _statusMessage = null;
    });
    try {
      await purchaseService.buy(details);
    } catch (_) {
      if (mounted) setState(() => _statusMessage = tr(locale, 'purchase_failed'));
    } finally {
      if (mounted) setState(() => _purchasingUnlock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);
    final adFree = ref.watch(adFreeProvider).value ?? false;

    return SubmenuScaffold(
      title: tr(locale, 'shop'),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                '${tr(locale, 'credits')}: ${board.credits}',
                style: submenuNunito(size: 13, weight: FontWeight.w900, color: SubmenuColors.gold),
              ),
            ),
            GroupHeader(text: tr(locale, 'shop_group_credits')),
            InsetList(
              rows: [
                SubmenuRow(
                  icon: Icons.smart_display_rounded,
                  label: tr(locale, 'credits_amount').replaceFirst('{n}', '$kShopAdCreditReward'),
                  labelFontSize: 14,
                  trailing: SubmenuGoldButton(
                    label: tr(locale, 'shop_watch_ad_button'),
                    loading: _watching,
                    onTap: _watching ? null : () => _watchAdForCredits(locale),
                  ),
                ),
                _CreditPackRow(
                  pack: CreditPack.small,
                  details: _products[kCreditPackProductIds[CreditPack.small]],
                  purchasing: _purchasingPack == CreditPack.small,
                  disabled: _purchasingPack != null,
                  onBuy: () => _buyCreditPack(locale, CreditPack.small),
                  locale: locale,
                  fallbackPrice: '49p',
                ),
                _CreditPackRow(
                  pack: CreditPack.large,
                  details: _products[kCreditPackProductIds[CreditPack.large]],
                  purchasing: _purchasingPack == CreditPack.large,
                  disabled: _purchasingPack != null,
                  onBuy: () => _buyCreditPack(locale, CreditPack.large),
                  locale: locale,
                  fallbackPrice: '£2.49',
                ),
              ],
            ),
            if (board.highestLevelReached < kMaxLevel) ...[
              GroupHeader(text: tr(locale, 'shop_group_unlock')),
              InsetList(
                rows: [
                  SubmenuRow(
                    icon: Icons.lock_open_rounded,
                    label: tr(locale, 'shop_unlock_level_title').replaceFirst(
                      '{level}',
                      kInfoLevels[board.highestLevelReached].name,
                    ),
                    labelFontSize: 14,
                    minHeight: 58,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _products[kUnlockLevelProductId]?.price ?? '£1.99',
                          style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        SubmenuGoldButton(
                          label: tr(locale, 'shop_buy_button'),
                          loading: _purchasingUnlock,
                          onTap: () => _buyUnlockLevel(locale),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            GroupHeader(text: tr(locale, 'shop_remove_ads_title')),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
              child: Text(
                tr(locale, 'shop_remove_ads_subtitle'),
                style: submenuNunito(size: 12, weight: FontWeight.w700, color: SubmenuColors.textSecondary, height: 1.35),
              ),
            ),
            InsetList(
              rows: [
                _AdFreeRow(
                  tier: AdFreeTier.oneDay,
                  icon: Icons.today_rounded,
                  details: _products[kAdFreeProductIds[AdFreeTier.oneDay]],
                  purchasing: _purchasingTier == AdFreeTier.oneDay,
                  disabled: _purchasingTier != null,
                  onBuy: () => _buyAdFree(locale, AdFreeTier.oneDay),
                  locale: locale,
                  fallbackPrice: '£0.19',
                ),
                _AdFreeRow(
                  tier: AdFreeTier.monthly,
                  icon: Icons.calendar_month_rounded,
                  details: _products[kAdFreeProductIds[AdFreeTier.monthly]],
                  purchasing: _purchasingTier == AdFreeTier.monthly,
                  disabled: _purchasingTier != null,
                  onBuy: () => _buyAdFree(locale, AdFreeTier.monthly),
                  locale: locale,
                  fallbackPrice: '£1.49',
                ),
                _AdFreeRow(
                  tier: AdFreeTier.yearly,
                  icon: Icons.event_rounded,
                  details: _products[kAdFreeProductIds[AdFreeTier.yearly]],
                  purchasing: _purchasingTier == AdFreeTier.yearly,
                  disabled: _purchasingTier != null,
                  onBuy: () => _buyAdFree(locale, AdFreeTier.yearly),
                  locale: locale,
                  fallbackPrice: '£2.99',
                ),
                _AdFreeRow(
                  tier: AdFreeTier.forever,
                  icon: Icons.all_inclusive_rounded,
                  details: _products[kAdFreeProductIds[AdFreeTier.forever]],
                  purchasing: _purchasingTier == AdFreeTier.forever,
                  disabled: _purchasingTier != null,
                  onBuy: () => _buyAdFree(locale, AdFreeTier.forever),
                  locale: locale,
                  fallbackPrice: '£3.99',
                ),
              ],
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(_statusMessage!, style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary)),
              ),
            ],
            if (adFree) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  tr(locale, 'shop_ads_free_forever'),
                  style: submenuNunito(size: 13, weight: FontWeight.w900, color: SubmenuColors.greenBright),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One ad-removal tier's row — price pulled from Play Console via
/// [details] once it's loaded (falling back to [fallbackPrice], this
/// project's baseline GBP price, while that query is still in flight or
/// if the product isn't configured yet).
class _AdFreeRow extends StatelessWidget {
  final AdFreeTier tier;
  final IconData icon;
  final ProductDetails? details;
  final bool purchasing;
  final bool disabled;
  final VoidCallback onBuy;
  final AppLocale locale;
  final String fallbackPrice;

  const _AdFreeRow({
    required this.tier,
    required this.icon,
    required this.details,
    required this.purchasing,
    required this.disabled,
    required this.onBuy,
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
    return SubmenuRow(
      icon: icon,
      label: tr(locale, _tierLabelKey),
      minHeight: 58,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(price, style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary)),
          const SizedBox(width: 8),
          SubmenuGoldButton(label: tr(locale, 'shop_buy_button'), loading: purchasing, onTap: (disabled && !purchasing) ? null : onBuy),
        ],
      ),
    );
  }
}

/// One credit pack's row — same shape as [_AdFreeRow], just for the two
/// consumable credit packs instead of the ad-removal tiers (see
/// purchase_service.dart's CreditPack/kCreditPackProductIds). Also
/// offered from the home screen's credits "+" popup (GetCreditsDialog) —
/// this is the same purchase reachable from the Shop screen directly.
class _CreditPackRow extends StatelessWidget {
  final CreditPack pack;
  final ProductDetails? details;
  final bool purchasing;
  final bool disabled;
  final VoidCallback onBuy;
  final AppLocale locale;
  final String fallbackPrice;

  const _CreditPackRow({
    required this.pack,
    required this.details,
    required this.purchasing,
    required this.disabled,
    required this.onBuy,
    required this.locale,
    required this.fallbackPrice,
  });

  String get _amountLabel => tr(locale, 'credits_amount').replaceFirst(
    '{n}',
    kCreditPackAmounts[pack] == 1000 ? '1,000' : '10,000',
  );

  @override
  Widget build(BuildContext context) {
    final price = details?.price ?? fallbackPrice;
    return SubmenuRow(
      icon: Icons.add_circle_rounded,
      label: _amountLabel,
      labelFontSize: 14,
      minHeight: 58,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(price, style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary)),
          const SizedBox(width: 8),
          SubmenuGoldButton(label: tr(locale, 'shop_buy_button'), loading: purchasing, onTap: (disabled && !purchasing) ? null : onBuy),
        ],
      ),
    );
  }
}
