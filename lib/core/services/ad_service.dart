import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'analytics_service.dart';

/// Rewarded ad "slot" — both share the one underlying ad unit/instance;
/// this only exists so call sites keep expressing which feature is
/// asking (same pattern Capitle's AdService uses for its own single
/// rewarded slot).
enum RewardedAdSlot { continueGame, shopCredits }

/// Unity LevelPlay mediates ads — Unity Ads, Vungle, and Meta Audience
/// Network are all live, each linked as a network instance under every
/// ad unit in the LevelPlay dashboard (see Setup -> Networks there).
/// Mintegral isn't set up for Mixoloco (no account, unlike Capitle) —
/// add it back the same way if that changes (see
/// android/app/build.gradle.kts's own git history for the dependency
/// lines it needs). Four ad units: the persistent bottom banner, the
/// score-milestone MREC (see ad_break_screen.dart), the end-of-level
/// interstitial, and the shop/continue-after-game-over rewarded video.
class AdService implements LevelPlayInitListener {
  // Mixoloco's own LevelPlay app key + ad unit ids, from its own app
  // entry in the LevelPlay dashboard (registered against
  // com.brinklabs.mixoloco — deliberately not Capitle's, since its app
  // key is tied to com.brinklabs.capitle and won't serve ads for a
  // different bundle id).
  static const _levelPlayAppKey = '2884bb915';
  static const _levelPlayBannerAdUnitId = 'gnia6fbjeqnkk528';
  static const _levelPlayMrecAdUnitId = '6smnc6a5j3b9i5t2';
  static const _levelPlayInterstitialAdUnitId = 'f20mh6miux9i9tm7';
  static const _levelPlayRewardedAdUnitId = 'hsn1tjs54f5fkbk3';

  bool _isLevelPlayInitialized = false;

  /// Flips true once LevelPlay reports init success — banner/MREC views
  /// must not call loadAd() before that (it fails with error 625).
  final levelPlayReady = ValueNotifier<bool>(false);

  late final LevelPlayInterstitialAd _levelPlayInterstitialAd;
  bool _levelPlayInterstitialReady = false;
  bool _levelPlayInterstitialLoading = false;
  VoidCallback? _pendingLevelPlayInterstitialDismiss;
  final _interstitialRetry = _LoadRetry();

  late final LevelPlayRewardedAd _levelPlayRewardedAd;
  bool _rewardedReady = false;
  bool _rewardedLoading = false;
  final _rewardedRetry = _LoadRetry();
  bool _rewardEarned = false; // set in onAdRewarded, read in onAdClosed
  VoidCallback? _pendingRewardOnReward;
  VoidCallback? _pendingRewardOnDismissedWithoutReward;
  VoidCallback? _pendingRewardOnNotReady;

  AdService() {
    _levelPlayInterstitialAd = LevelPlayInterstitialAd(adUnitId: _levelPlayInterstitialAdUnitId);
    _levelPlayInterstitialAd.setListener(_InterstitialListener(this));
    _levelPlayRewardedAd = LevelPlayRewardedAd(adUnitId: _levelPlayRewardedAdUnitId);
    _levelPlayRewardedAd.setListener(_RewardedListener(this));
  }

  // GDPR/CCPA consent — see ad_consent.dart, which owns *when* this is
  // called (first-launch gate, or re-opened from Settings). Must be
  // applied before LevelPlay.init() the first time; on a later call
  // (consent changed mid-session) LevelPlay is already initialized so
  // this just re-applies the flags, which only affects *future* ad
  // requests.
  Future<void> initialize({required bool consentGranted}) async {
    await _applyConsent(consentGranted);
    await analyticsService.applyAdConsent(consentGranted);
    if (_isLevelPlayInitialized) return;
    analyticsService.attachToLevelPlay();
    await _initLevelPlay();
  }

  Future<void> _applyConsent(bool granted) async {
    try {
      // Exact network key strings LevelPlay expects — confirmed against
      // Unity's own docs (and already proven in Capitle), not guessed:
      // case-sensitive, "UnityAds" not "Unity".
      await LevelPlayPrivacySettings.setGDPRConsents({'UnityAds': granted, 'Vungle': granted, 'Facebook': granted});
      await LevelPlayPrivacySettings.setCCPA(!granted); // CCPA flag = "opted out of sale"
    } catch (e, st) {
      debugPrint('Failed to apply ad consent: $e\n$st');
    }
  }

  Future<void> _initLevelPlay() async {
    try {
      // Debug builds only: lets the LevelPlay Integration Test Suite be
      // opened (collision testbed sheet) to see which networks are
      // actually configured per ad unit. Must be set before init.
      if (kDebugMode) {
        await LevelPlay.setMetaData({'is_test_suite': ['enable']});
      }
      final initRequest = LevelPlayInitRequest.builder(_levelPlayAppKey).build();
      // Bounded — callers (the ad-consent screen, main.dart's launch
      // gate) await this before letting the player into the app at all,
      // and a malformed app key (e.g. the TODO placeholder above, before
      // real LevelPlay credentials are dropped in) or no network can
      // otherwise leave LevelPlay.init()'s own Future pending forever,
      // since it only completes once the native side's listener actually
      // fires. A timeout here just means ads stay unavailable for this
      // session rather than the whole app hanging on the splash/consent
      // screen.
      await LevelPlay.init(initRequest: initRequest, initListener: this).timeout(const Duration(seconds: 8));
    } catch (e, st) {
      debugPrint('LevelPlay failed to initialize: $e\n$st');
    }
  }

  // ── LevelPlayInitListener ────────────────────────────────────────────

  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    debugPrint('LevelPlay initialized');
    _isLevelPlayInitialized = true;
    levelPlayReady.value = true;
    loadLevelPlayInterstitial();
    loadRewardedAd(RewardedAdSlot.continueGame);
  }

  @override
  void onInitFailed(LevelPlayInitError error) {
    debugPrint('LevelPlay failed to initialize: $error');
  }

  // ── Banner + MREC (LevelPlay) ────────────────────────────────────────

  String get levelPlayBannerAdUnitId => _levelPlayBannerAdUnitId;
  String get levelPlayMrecAdUnitId => _levelPlayMrecAdUnitId;
  bool get isLevelPlayInitialized => _isLevelPlayInitialized;

  // ── Interstitial, end-of-level (LevelPlay) ───────────────────────────

  bool get isLevelPlayInterstitialReady => _levelPlayInterstitialReady;

  void loadLevelPlayInterstitial() {
    if (_levelPlayInterstitialReady || _levelPlayInterstitialLoading) return;
    _interstitialRetry.cancelPending(); // loading now, so a queued retry is redundant
    _levelPlayInterstitialLoading = true;
    _levelPlayInterstitialAd.loadAd();
  }

  /// Shows the end-of-level interstitial. Unlike a rewarded ad, an
  /// interstitial has no "reward earned" signal of its own: [onDismissed]
  /// fires once the user closes it, full stop — callers treat "watched"
  /// and "dismissed" as the same outcome, since nothing here is gated on
  /// having actually watched it (see level_up_screen.dart).
  Future<void> showLevelPlayInterstitial({required VoidCallback onDismissed, VoidCallback? onNotReady}) async {
    final ready = await _levelPlayInterstitialAd.isAdReady();
    if (!ready) {
      onNotReady?.call();
      loadLevelPlayInterstitial();
      return;
    }
    _pendingLevelPlayInterstitialDismiss = onDismissed;
    // 'Default' — LevelPlay's placement name is a reporting tag, not a
    // functional identifier; there's only one placement for this slot.
    _levelPlayInterstitialAd.showAd(placementName: 'Default');
  }

  void _onInterstitialLoaded() {
    debugPrint('LevelPlay interstitial loaded');
    _levelPlayInterstitialReady = true;
    _levelPlayInterstitialLoading = false;
    _interstitialRetry.reset();
  }

  void _onInterstitialLoadFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay interstitial failed to load: $error');
    _levelPlayInterstitialReady = false;
    _levelPlayInterstitialLoading = false;
    // Without this, nothing asks again until the game next wants to show
    // one — by then it's too late and that ad opportunity is lost.
    _interstitialRetry.schedule(loadLevelPlayInterstitial);
  }

  void _onInterstitialDisplayFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay interstitial failed to display: $error');
    _levelPlayInterstitialReady = false;
    _pendingLevelPlayInterstitialDismiss?.call();
    _pendingLevelPlayInterstitialDismiss = null;
    loadLevelPlayInterstitial();
  }

  void _onInterstitialClosed() {
    _levelPlayInterstitialReady = false; // consumed — reload below for next time
    _pendingLevelPlayInterstitialDismiss?.call();
    _pendingLevelPlayInterstitialDismiss = null;
    loadLevelPlayInterstitial();
  }

  // ── Rewarded, shop credits + continue-after-game-over (LevelPlay) ────
  //
  // `slot` is accepted on every method below purely so call sites keep
  // expressing which feature is asking, even though both currently share
  // the one rewarded ad unit/instance.

  bool isRewardedAdReady(RewardedAdSlot slot) => _rewardedReady;

  void loadRewardedAd(RewardedAdSlot slot) {
    if (_rewardedReady || _rewardedLoading) return;
    _rewardedRetry.cancelPending(); // loading now, so a queued retry is redundant
    _rewardedLoading = true;
    _levelPlayRewardedAd.loadAd();
  }

  /// True while a show request checks the ad is still ready — a second
  /// request meanwhile (a double tap) is ignored, so it can't replace the
  /// first caller's callbacks.
  bool _rewardedShowing = false;

  Future<void> showRewardedAd(
    RewardedAdSlot slot, {
    required VoidCallback onReward,
    VoidCallback? onDismissedWithoutReward,
    VoidCallback? onNotReady,
  }) async {
    if (_rewardedShowing) return;
    _rewardedShowing = true;
    // A loaded ad can expire while it waits (a long game) — ask the SDK
    // rather than trusting our own flag, so an expired ad goes down the
    // not-ready path (fallback video) instead of failing on show.
    var ready = _rewardedReady;
    _rewardedReady = false; // claimed now, before the await below
    if (ready) {
      try {
        ready = await _levelPlayRewardedAd.isAdReady();
      } catch (_) {
        ready = false;
      }
    }
    if (!ready) {
      _rewardedShowing = false;
      onNotReady?.call();
      loadRewardedAd(slot);
      return;
    }
    _rewardEarned = false;
    _pendingRewardOnReward = onReward;
    _pendingRewardOnDismissedWithoutReward = onDismissedWithoutReward;
    _pendingRewardOnNotReady = onNotReady;
    _levelPlayRewardedAd.showAd(placementName: 'Default');
    _rewardedShowing = false; // the ad now covers the screen
  }

  void _onRewardedLoaded() {
    debugPrint('LevelPlay rewarded ad loaded');
    _rewardedReady = true;
    _rewardedLoading = false;
    _rewardedRetry.reset();
  }

  void _onRewardedLoadFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay rewarded ad failed to load: $error');
    _rewardedReady = false;
    _rewardedLoading = false;
    // Keep trying in the background so the continue / free-coins offer
    // has an ad ready when the player asks for one.
    _rewardedRetry.schedule(() => loadRewardedAd(RewardedAdSlot.continueGame));
  }

  void _onRewardedDisplayFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay rewarded ad failed to display: $error');
    _rewardedReady = false;
    _rewardedShowing = false;
    // The player never saw an ad, so this isn't "closed without reward" —
    // treat it like no ad being available (e.g. the continue offer's
    // fallback video) rather than ending their game.
    final fallback = _pendingRewardOnNotReady ?? _pendingRewardOnDismissedWithoutReward;
    _pendingRewardOnReward = null;
    _pendingRewardOnDismissedWithoutReward = null;
    _pendingRewardOnNotReady = null;
    fallback?.call();
    loadRewardedAd(RewardedAdSlot.continueGame);
  }

  void _onRewardedEarned() {
    _rewardEarned = true;
  }

  void _onRewardedClosed() {
    _rewardedShowing = false;
    if (_rewardEarned) {
      _pendingRewardOnReward?.call();
    } else {
      _pendingRewardOnDismissedWithoutReward?.call();
    }
    _pendingRewardOnReward = null;
    _pendingRewardOnDismissedWithoutReward = null;
    _pendingRewardOnNotReady = null;
    loadRewardedAd(RewardedAdSlot.continueGame);
  }

  void dispose() {
    // Both SDKs manage their own ad lifecycle internally; only our own
    // pending retry timers need stopping.
    _interstitialRetry.cancelPending();
    _rewardedRetry.cancelPending();
  }
}

/// Retries a failed full-screen ad load with exponential backoff — 5s,
/// 10s, 20s, 40s, then every 60s — as LevelPlay recommends, so a no-fill
/// moment doesn't leave the slot empty until the next show attempt.
/// Capped rather than abandoned: a player offline for a while should
/// still get an ad once they're back, and one request a minute is cheap.
class _LoadRetry {
  static const _base = Duration(seconds: 5);
  static const _max = Duration(seconds: 60);

  int _attempt = 0;
  Timer? _timer;

  void schedule(VoidCallback load) {
    _timer?.cancel();
    final delay = Duration(milliseconds: math.min(_base.inMilliseconds << math.min(_attempt, 4), _max.inMilliseconds));
    _attempt++;
    _timer = Timer(delay, () {
      _timer = null;
      load();
    });
  }

  void cancelPending() {
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    cancelPending();
    _attempt = 0;
  }
}

// LevelPlayInterstitialAd and LevelPlayRewardedAd share identically-named
// listener methods (onAdLoaded, onAdClosed, etc.) — if AdService
// implemented both listener interfaces directly, one method body
// couldn't tell which ad type had actually fired it. Each ad object gets
// its own small adapter instead, delegating to AdService's private
// per-ad-type handlers.

class _InterstitialListener implements LevelPlayInterstitialAdListener {
  final AdService _service;
  _InterstitialListener(this._service);

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => _service._onInterstitialLoaded();
  @override
  void onAdLoadFailed(LevelPlayAdError error) => _service._onInterstitialLoadFailed(error);
  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}
  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) => _service._onInterstitialDisplayFailed(error);
  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}
  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => _service._onInterstitialClosed();
  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
}

class _RewardedListener implements LevelPlayRewardedAdListener {
  final AdService _service;
  _RewardedListener(this._service);

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => _service._onRewardedLoaded();
  @override
  void onAdLoadFailed(LevelPlayAdError error) => _service._onRewardedLoadFailed(error);
  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}
  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) => _service._onRewardedDisplayFailed(error);
  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}
  @override
  void onAdClosed(LevelPlayAdInfo adInfo) => _service._onRewardedClosed();
  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}
  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) => _service._onRewardedEarned();
}

final adService = AdService();
