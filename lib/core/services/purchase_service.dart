import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' show BillingResponse;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import '../../data/models/ingredient.dart' show kLevelCount;
import '../../data/services/progression_service.dart';

/// The four ad-removal tiers sold from the Shop.
enum AdFreeTier { oneDay, monthly, yearly, forever }

/// Play Console product ids this app expects to exist — these exact
/// strings must be created there (Play Console won't let a product id
/// ever be deleted/reused, so treat them as a permanent contract, not a
/// first draft):
///  - ads_free_1_day: a CONSUMABLE in-app product (rebuyable — each
///    purchase adds another day, see PurchaseService._applyPurchase).
///  - ads_free_forever: a non-consumable ("managed") in-app product.
///  - ads_free_monthly / ads_free_yearly: auto-renewing subscriptions.
const kAdFreeProductIds = {
  AdFreeTier.oneDay: 'ads_free_1_day',
  AdFreeTier.monthly: 'ads_free_monthly',
  AdFreeTier.yearly: 'ads_free_yearly',
  AdFreeTier.forever: 'ads_free_forever',
};

/// The two credit packs sold from [GetCreditsDialog] — same "permanent
/// contract" rule as [kAdFreeProductIds]: both ids must be created by
/// hand in Play Console as CONSUMABLE in-app products (rebuyable, same
/// shape as ads_free_1_day) before either row there will do anything but
/// show "not available yet".
enum CreditPack { small, large }

const kCreditPackProductIds = {
  CreditPack.small: 'credits_1000',
  CreditPack.large: 'credits_10000',
};

/// How many credits each pack grants — looked up by
/// [PurchaseService._applyPurchaseLocked] once Play Billing actually
/// reports the purchase as complete, not assumed up front.
const kCreditPackAmounts = {CreditPack.small: 1000, CreditPack.large: 10000};

/// ShopScreen's "Unlock Next Level" row — same "permanent contract" rule
/// as the ids above: a CONSUMABLE in-app product (rebuyable — a player
/// who's already bought their way past one level can buy it again for
/// the next), created by hand in Play Console before the row does
/// anything but show "not available yet". Raises
/// BoardState.highestLevelReached by one (see
/// GameStateNotifier.unlockNextLevelFromPurchase) — it doesn't touch
/// evolution tiers or credits, and doesn't teleport an in-progress run
/// there either; it just lets the player start a New Game at that level
/// whenever they choose, same as reaching it by play would.
const kUnlockLevelProductId = 'unlock_next_level';

/// Owns every "is this player ad-free right now" question in the app —
/// every ad-serving call site (the persistent banner, the score-threshold
/// MREC ad break, the level-up interstitial) checks [isAdFree] before
/// showing anything. Rewarded ads (Shop's watch-for-credits, the
/// game-over continue offer) are deliberately NOT gated by this — those
/// are ads the player chooses to watch for a benefit, not ones forced on
/// them, so buying ad removal shouldn't take that option away too.
///
/// No backend purchase validation here — no Real-time Developer
/// Notifications, no server-side receipt check, nothing beyond what Play
/// Billing itself reports on-device. Entitlement state is re-derived from
/// that via [refresh], called on [init] and again whenever GameScreen
/// notices the app resuming (mirroring how it re-asserts music there).
/// That's the standard approach for an app with no backend of its own,
/// but it means a cancelled subscription's ad-free access lapses at the
/// next refresh, not the instant it's cancelled — a real limitation, not
/// an oversight; hardening this later would mean standing up a small
/// server (this project already has Firebase, used for the weekly
/// league) to verify purchases and react to Play's RTDN webhooks.
class PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _adFreeController = StreamController<bool>.broadcast();
  final _creditPackController = StreamController<int>.broadcast();
  final _unlockLevelController = StreamController<int>.broadcast();

  /// Numbers every grant announced on the two streams above. Riverpod
  /// skips an AsyncValue equal to the one before it, so a second
  /// identical announcement (two 1,000-credit packs, two level unlocks)
  /// was silently dropped — the second purchase reached nobody. A fresh
  /// number each time keeps every one distinct.
  int _grantSequence = 0;

  bool _adFree = false;
  bool get isAdFree => _adFree;

  /// Fires whenever [isAdFree] changes — GameScreen/BannerAdWidget can
  /// listen instead of polling.
  Stream<bool> get adFreeChanges => _adFreeController.stream;

  /// Fires the credit amount (see [kCreditPackAmounts]) once per
  /// completed credit-pack purchase — unlike [adFreeChanges] this isn't a
  /// "current value" stream, it's a one-shot event per purchase, since
  /// crediting the player is an action (GameStateNotifier.build() listens
  /// globally and calls addPurchasedCredits), not a state to render.
  Stream<int> get creditPackPurchases => _creditPackController.stream;

  /// Fires once per completed "Unlock Next Level" purchase — same
  /// one-shot-event shape as [creditPackPurchases], not a current-value
  /// stream.
  Stream<int> get unlockLevelPurchases => _unlockLevelController.stream;

  /// Set within a single [refresh] call as subscription purchases are
  /// seen come through the stream — reset to false at the start of each
  /// refresh so a subscription that's genuinely lapsed (no longer
  /// reported by Play Billing at all) correctly stops being treated as
  /// active, rather than the last-seen `true` persisting forever.
  bool _subscriptionSeenThisRefresh = false;

  Future<void> init() async {
    _adFree = await _loadCachedAdFree();
    _adFreeController.add(_adFree);
    if (!await _iap.isAvailable()) return;
    _sub = _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
    await refresh();
  }

  void dispose() {
    _sub?.cancel();
    _adFreeController.close();
    _creditPackController.close();
    _unlockLevelController.close();
  }

  /// Re-asks Play Billing what this account currently owns/is subscribed
  /// to. Safe to call repeatedly (e.g. every app resume) — a soft no-op
  /// if billing isn't available (emulator without Play Store, etc.).
  Future<void> refresh() async {
    if (!await _iap.isAvailable()) return;
    _subscriptionSeenThisRefresh = false;
    try {
      await _iap.restorePurchases();
    } catch (_) {
      // Soft failure — keep whatever entitlement state was already
      // cached rather than let a transient billing-service hiccup strip
      // ad-free access the player genuinely still has.
    }
    // restorePurchases() only awaits the platform *request* — the actual
    // PurchaseDetails for each restored entitlement arrive afterward,
    // asynchronously, through purchaseStream (_onPurchaseUpdate), a
    // known quirk of this plugin. Without this pause, an active
    // subscriber's _subscriptionSeenThisRefresh could still read false
    // here (events just haven't landed yet), writing a wrong "not
    // subscribed" cache that PersistentBannerAd reads and briefly shows
    // ads on — self-corrects the moment the stream event does arrive
    // and _recomputeAdFree runs again, but there's no reason to risk
    // that flash when a short, bounded wait avoids it.
    await Future.delayed(const Duration(milliseconds: 600));
    await saveAdFreeSubscriptionCached(_subscriptionSeenThisRefresh);
    await _recomputeAdFree();
  }

  /// Every product id the app knows how to sell, in one query — shared by
  /// ShopScreen (ad-free tiers) and GetCreditsDialog (credit packs) so
  /// either can look up any of them from the same call.
  Future<List<ProductDetails>> queryProducts() async {
    final ids = {...kAdFreeProductIds.values, ...kCreditPackProductIds.values, kUnlockLevelProductId};
    final response = await _iap.queryProductDetails(ids);
    return response.productDetails;
  }

  /// Starts the platform purchase flow for [details] — 1 Day and both
  /// credit packs are consumables (rebuyable every time), Monthly/Yearly
  /// need their subscription offer token, Forever is a plain
  /// non-consumable.
  Future<void> buy(ProductDetails details) async {
    if (_isConsumable(details.id)) {
      // Consumed by _onPurchaseUpdate, not the plugin's autoConsume — see
      // there for why.
      await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
        autoConsume: false,
      );
      return;
    }
    final isSubscription =
        details.id == kAdFreeProductIds[AdFreeTier.monthly] ||
        details.id == kAdFreeProductIds[AdFreeTier.yearly];
    if (isSubscription &&
        details is GooglePlayProductDetails &&
        details.offerToken != null) {
      await _iap.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: details,
          offerToken: details.offerToken,
        ),
      );
      return;
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  /// The rebuyable products: 1 Day, both credit packs and Unlock Next Level.
  bool _isConsumable(String productId) =>
      productId == kAdFreeProductIds[AdFreeTier.oneDay] ||
      kCreditPackProductIds.values.contains(productId) ||
      productId == kUnlockLevelProductId;

  void _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final owned = purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (_isConsumable(purchase.productID)) {
        // A consumable stays "owned" — and can't be bought again ("you
        // already own this item") — until it's consumed. The plugin's own
        // autoConsume only did that for a purchase that came back in the
        // same session it was started, and on failure marked it an error,
        // so the player paid, got nothing, and couldn't buy again. Every
        // owned consumable — a fresh buy, or one Play re-reports on the
        // next refresh because it was never consumed — is consumed here,
        // and granted only once Play confirms. A second delivery of the
        // same purchase then fails to consume, so it's never granted twice.
        // Consuming also acknowledges it, so completePurchase isn't needed.
        if (owned && await _consume(purchase)) await _applyPurchase(purchase);
        continue;
      }
      if (owned) await _applyPurchase(purchase);
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
    await _recomputeAdFree();
  }

  Future<bool> _consume(PurchaseDetails purchase) async {
    try {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final result = await android.consumePurchase(purchase);
      return result.responseCode == BillingResponse.ok;
    } catch (_) {
      return false;
    }
  }

  /// Serializes [_applyPurchase]'s own read-modify-write of the 1-Day
  /// expiry across overlapping calls — `purchaseStream` can deliver more
  /// than one event in quick succession (a double-tap buy, or Play
  /// replaying a purchase on reconnect), and since `_onPurchaseUpdate`
  /// isn't awaited between stream events, two such calls could otherwise
  /// both read the same stale `existing` expiry before either writes
  /// back, and the second write would silently clobber the first instead
  /// of stacking — one of two paid days lost. Chaining every call onto
  /// this one Future forces them to run one at a time, in arrival order,
  /// the same effect a mutex would give without needing one.
  Future<void> _applyQueue = Future.value();

  Future<void> _applyPurchase(PurchaseDetails purchase) {
    final result = _applyQueue.then((_) => _applyPurchaseLocked(purchase));
    _applyQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _applyPurchaseLocked(PurchaseDetails purchase) async {
    if (purchase.productID == kAdFreeProductIds[AdFreeTier.oneDay]) {
      // Consumable, so every event here is a fresh buy (only reached
      // once _onPurchaseUpdate has consumed it) — stacks onto
      // any time already remaining rather than always resetting to
      // exactly 24h from now, so buying a second day before the first
      // runs out doesn't waste the remainder of the first.
      final existing = await loadAdFreeOneDayExpiry();
      final base = existing != null && existing.isAfter(DateTime.now())
          ? existing
          : DateTime.now();
      await saveAdFreeOneDayExpiry(base.add(const Duration(days: 1)));
    } else if (purchase.productID == kAdFreeProductIds[AdFreeTier.forever]) {
      await saveAdFreeForever(true);
    } else if (purchase.productID == kAdFreeProductIds[AdFreeTier.monthly] ||
        purchase.productID == kAdFreeProductIds[AdFreeTier.yearly]) {
      _subscriptionSeenThisRefresh = true;
      await saveAdFreeSubscriptionCached(true);
    } else if (purchase.productID == kUnlockLevelProductId) {
      // Consumable, same "every event is a fresh buy" reasoning as
      // ads_free_1_day above. Saved here, before announcing it — a
      // purchase recovered at startup can arrive before GameStateNotifier
      // is listening, or while it's still loading its save, and the
      // player must still get what they paid for. The notifier just
      // re-reads the saved value (see unlockNextLevelFromPurchase).
      final reached = await loadHighestLevelReached();
      if (reached < kLevelCount) await saveHighestLevelReached(reached + 1);
      _unlockLevelController.add(++_grantSequence);
    } else {
      // Consumable — saved first and then announced, same as Unlock Next
      // Level above (see addPurchasedCredits).
      for (final tier in CreditPack.values) {
        if (purchase.productID == kCreditPackProductIds[tier]) {
          final amount = kCreditPackAmounts[tier]!;
          await saveCredits(await loadCredits() + amount);
          _creditPackController.add(++_grantSequence);
          break;
        }
      }
    }
  }

  Future<bool> _loadCachedAdFree() async {
    if (await loadAdFreeForever()) return true;
    final oneDayExpiry = await loadAdFreeOneDayExpiry();
    if (oneDayExpiry != null && oneDayExpiry.isAfter(DateTime.now())) {
      return true;
    }
    return loadAdFreeSubscriptionCached();
  }

  Future<void> _recomputeAdFree() async {
    final adFree = await _loadCachedAdFree();
    if (adFree != _adFree) {
      _adFree = adFree;
      _adFreeController.add(_adFree);
    }
  }
}

final purchaseService = PurchaseService();

/// [purchaseService.isAdFree]'s current value, immediately (not waiting
/// for the first stream event) then live thereafter — for any widget
/// that wants to react to it (PersistentBannerAd) without holding its
/// own subscription.
final adFreeProvider = StreamProvider<bool>((ref) async* {
  yield purchaseService.isAdFree;
  yield* purchaseService.adFreeChanges;
});

/// Each completed credit-pack purchase's amount, as a one-shot event —
/// GameStateNotifier.build() listens to this globally and credits the
/// player, so this stays a thin pass-through with no "current value"
/// semantics (unlike [adFreeProvider]).
final creditPackPurchaseProvider = StreamProvider<int>(
  (ref) => purchaseService.creditPackPurchases,
);

/// Each completed "Unlock Next Level" purchase, as a one-shot event —
/// same shape/reasoning as [creditPackPurchaseProvider].
final unlockLevelPurchaseProvider = StreamProvider<int>(
  (ref) => purchaseService.unlockLevelPurchases,
);
