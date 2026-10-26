import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/continue_fallback_video_screen.dart';
import '../../../core/widgets/notification_tablet.dart';
import '../../../core/widgets/submenu_kit.dart' show IconBadge;
import '../../game/providers/game_state_provider.dart';

/// Quick "get credits" popup opened from the HUD credits pill's "+" —
/// the same two ways to earn credits ShopScreen already offers (watch an
/// ad, or buy) condensed into one dialog so the player doesn't have to
/// leave the menu for either. Mirrors ShopScreen's own
/// `_watchAdForCredits`/`_buyAdFree` logic rather than sharing it
/// directly (that logic is State-scoped there); ShopScreen itself is
/// untouched.
class GetCreditsDialog extends ConsumerStatefulWidget {
  const GetCreditsDialog({super.key});

  @override
  ConsumerState<GetCreditsDialog> createState() => _GetCreditsDialogState();
}

class _GetCreditsDialogState extends ConsumerState<GetCreditsDialog> {
  bool _watching = false;
  CreditPack? _purchasingPack;
  String? _statusMessage;

  /// Keyed by product id — empty until [_loadProducts] resolves, and
  /// stays empty (not an error) if Play Console doesn't have the credit
  /// packs configured yet, same soft-failure shape as ShopScreen's own
  /// `_loadProducts`.
  Map<String, ProductDetails> _products = {};

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
        if (mounted) {
          setState(() {
            _watching = false;
            _statusMessage = tr(locale, 'shop_credits_earned');
          });
        }
      },
      onDismissedWithoutReward: () {
        if (mounted) setState(() => _watching = false);
      },
      onNotReady: () async {
        if (!mounted) return;
        setState(() => _watching = false);
        final watched = await showContinueFallbackVideo(context, locale);
        if (!mounted) return;
        if (watched) {
          ref
              .read(gameStateProvider.notifier)
              .addAdCredits(kShopAdCreditReward);
          setState(() => _statusMessage = tr(locale, 'shop_credits_earned'));
        }
      },
    );
  }

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
      // The actual credit award arrives separately, via
      // GameStateNotifier's global creditPackPurchaseProvider listener,
      // once Play Billing reports the purchase complete — not awaited
      // here, same as ShopScreen._buyAdFree doesn't wait for entitlement
      // to land before clearing its own loading state.
    } catch (_) {
      if (mounted) {
        setState(() => _statusMessage = tr(locale, 'purchase_failed'));
      }
    } finally {
      if (mounted) setState(() => _purchasingPack = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(locale, 'get_credits_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textOnStone,
              ),
            ),
            const SizedBox(height: 18),
            _GetCreditsRow(
              icon: Icons.smart_display_rounded,
              label:
                  '${tr(locale, 'shop_watch_ad_title')} $kShopAdCreditReward',
              buttonLabel: tr(locale, 'shop_watch_ad_button'),
              busy: _watching,
              onTap: () => _watchAdForCredits(locale),
            ),
            const SizedBox(height: 10),
            _GetCreditsRow(
              icon: Icons.add_circle_rounded,
              label: tr(locale, 'credits_amount').replaceFirst('{n}', '1,000'),
              price:
                  _products[kCreditPackProductIds[CreditPack.small]]?.price ??
                  '49p',
              buttonLabel: tr(locale, 'shop_buy_button'),
              busy: _purchasingPack == CreditPack.small,
              disabled: _purchasingPack != null,
              onTap: () => _buyCreditPack(locale, CreditPack.small),
            ),
            const SizedBox(height: 10),
            _GetCreditsRow(
              icon: Icons.add_circle_rounded,
              label: tr(locale, 'credits_amount').replaceFirst('{n}', '10,000'),
              price:
                  _products[kCreditPackProductIds[CreditPack.large]]?.price ??
                  '£2.49',
              buttonLabel: tr(locale, 'shop_buy_button'),
              busy: _purchasingPack == CreditPack.large,
              disabled: _purchasingPack != null,
              onTap: () => _buyCreditPack(locale, CreditPack.large),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _statusMessage!,
                style: const TextStyle(
                  color: AppColors.textOnStoneMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row — an icon, a label (with an optional price beneath it), and a
/// small pill button on the right. Same visual shape as ShopScreen's own
/// watch-ad/buy rows, just laid out for NotificationTablet's narrower
/// dialog width instead of a full-width WoodPlank.
class _GetCreditsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? price;
  final String buttonLabel;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  const _GetCreditsRow({
    required this.icon,
    required this.label,
    this.price,
    required this.buttonLabel,
    required this.busy,
    this.disabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tapDisabled = busy || disabled;
    return Row(
      children: [
        IconBadge(icon: icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textOnStone,
                ),
              ),
              if (price != null)
                Text(
                  price!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textOnStoneMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: tapDisabled ? null : onTap,
          child: Opacity(
            opacity: disabled && !busy ? 0.4 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF7A3A00), width: 2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFFD95E), Color(0xFFF39A12)],
                ),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}
