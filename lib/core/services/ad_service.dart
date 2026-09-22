import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

/// Rewarded ad "slot" — both share the one underlying ad unit/instance;
/// this only exists so call sites keep expressing which feature is
/// asking (same pattern Capitle's AdService uses for its own single
/// rewarded slot).
enum RewardedAdSlot { continueGame, shopCredits }

/// Unity LevelPlay mediates ads — currently just Unity Ads itself (the
/// one network LevelPlay ships with, needing no separate account setup);
/// see android/app/build.gradle.kts for where Vungle/Meta/Mintegral would
/// be added the same way Capitle's sibling app does, once/if those
/// accounts exist for Mixoloco too. Four ad units: the persistent bottom
/// banner, the score-milestone MREC (see ad_break_screen.dart), the
/// end-of-level interstitial, and the shop/continue-after-game-over
/// rewarded video.
class AdService implements LevelPlayInitListener {
  // TODO: replace with Mixoloco's own LevelPlay app key + ad unit ids,
  // from a NEW app entry in the LevelPlay dashboard registered against
  // com.brinklabs.mixoloco — these must NOT be Capitle's (its app key is
  // tied to com.brinklabs.capitle and won't serve ads for a different
  // bundle id). Everything below works as soon as real values land here.
  static const _levelPlayAppKey = 'TODO_MIXOLOCO_LEVELPLAY_APP_KEY';
  static const _levelPlayBannerAdUnitId = 'TODO_MIXOLOCO_BANNER_AD_UNIT_ID';
  static const _levelPlayMrecAdUnitId = 'TODO_MIXOLOCO_MREC_AD_UNIT_ID';
  static const _levelPlayInterstitialAdUnitId = 'TODO_MIXOLOCO_INTERSTITIAL_AD_UNIT_ID';
  static const _levelPlayRewardedAdUnitId = 'TODO_MIXOLOCO_REWARDED_AD_UNIT_ID';

  bool _isLevelPlayInitialized = false;

  late final LevelPlayInterstitialAd _levelPlayInterstitialAd;
  bool _levelPlayInterstitialReady = false;
  bool _levelPlayInterstitialLoading = false;
  VoidCallback? _pendingLevelPlayInterstitialDismiss;

  late final LevelPlayRewardedAd _levelPlayRewardedAd;
  bool _rewardedReady = false;
  bool _rewardedLoading = false;
  bool _rewardEarned = false; // set in onAdRewarded, read in onAdClosed
  VoidCallback? _pendingRewardOnReward;
  VoidCallback? _pendingRewardOnDismissedWithoutReward;

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
    if (_isLevelPlayInitialized) return;
    await _initLevelPlay();
  }

  Future<void> _applyConsent(bool granted) async {
    try {
      await LevelPlayPrivacySettings.setGDPRConsents({'UnityAds': granted});
      await LevelPlayPrivacySettings.setCCPA(!granted); // CCPA flag = "opted out of sale"
    } catch (e, st) {
      debugPrint('Failed to apply ad consent: $e\n$st');
    }
  }

  Future<void> _initLevelPlay() async {
    try {
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
  }

  void _onInterstitialLoadFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay interstitial failed to load: $error');
    _levelPlayInterstitialReady = false;
    _levelPlayInterstitialLoading = false;
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
    _rewardedLoading = true;
    _levelPlayRewardedAd.loadAd();
  }

  void showRewardedAd(RewardedAdSlot slot, {required VoidCallback onReward, VoidCallback? onDismissedWithoutReward, VoidCallback? onNotReady}) {
    if (!_rewardedReady) {
      onNotReady?.call();
      loadRewardedAd(slot);
      return;
    }
    _rewardedReady = false; // consumed — reload below for next time
    _rewardEarned = false;
    _pendingRewardOnReward = onReward;
    _pendingRewardOnDismissedWithoutReward = onDismissedWithoutReward;
    _levelPlayRewardedAd.showAd(placementName: 'Default');
  }

  void _onRewardedLoaded() {
    debugPrint('LevelPlay rewarded ad loaded');
    _rewardedReady = true;
    _rewardedLoading = false;
  }

  void _onRewardedLoadFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay rewarded ad failed to load: $error');
    _rewardedReady = false;
    _rewardedLoading = false;
  }

  void _onRewardedDisplayFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay rewarded ad failed to display: $error');
    _rewardedReady = false;
    _pendingRewardOnDismissedWithoutReward?.call();
    _pendingRewardOnReward = null;
    _pendingRewardOnDismissedWithoutReward = null;
    loadRewardedAd(RewardedAdSlot.continueGame);
  }

  void _onRewardedEarned() {
    _rewardEarned = true;
  }

  void _onRewardedClosed() {
    if (_rewardEarned) {
      _pendingRewardOnReward?.call();
    } else {
      _pendingRewardOnDismissedWithoutReward?.call();
    }
    _pendingRewardOnReward = null;
    _pendingRewardOnDismissedWithoutReward = null;
    loadRewardedAd(RewardedAdSlot.continueGame);
  }

  void dispose() {
    // Both SDKs manage their own ad lifecycle internally; nothing to
    // explicitly dispose here.
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
