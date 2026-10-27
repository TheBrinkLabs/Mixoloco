import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'firebase_bootstrap.dart';

/// Firebase Analytics for Mixoloco: game milestones, power-up spends and
/// LevelPlay ad revenue (one `ad_impression` per ad shown, which is what
/// Firebase/GA4 ad-revenue reporting is built on).
///
/// Every call is fire-and-forget and silently skipped when Firebase isn't
/// available — analytics must never affect gameplay. Debug builds don't
/// collect at all, so testing doesn't pollute real-player numbers.
class AnalyticsService implements LevelPlayImpressionDataListener {
  FirebaseAnalytics? get _fa =>
      firebaseAvailable && !kDebugMode ? FirebaseAnalytics.instance : null;

  /// Mirrors the player's ad-consent answer into Google consent mode:
  /// gameplay analytics is always on, but ad storage / ad user data /
  /// personalization signals follow the same choice LevelPlay gets.
  Future<void> applyAdConsent(bool granted) async {
    if (!firebaseAvailable) return;
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(!kDebugMode);
      await FirebaseAnalytics.instance.setConsent(
        analyticsStorageConsentGranted: true,
        adStorageConsentGranted: granted,
        adUserDataConsentGranted: granted,
        adPersonalizationSignalsConsentGranted: granted,
      );
    } catch (e) {
      debugPrint('Analytics consent update failed: $e');
    }
  }

  /// Registers for LevelPlay impression-level revenue. Safe to call
  /// before or after LevelPlay.init().
  void attachToLevelPlay() => LevelPlay.addImpressionDataListener(this);

  @override
  void onImpressionSuccess(LevelPlayImpressionData data) {
    final revenue = data.revenue;
    if (revenue == null) return;
    _log(() => _fa?.logAdImpression(
          adPlatform: 'LevelPlay',
          adSource: data.adNetwork,
          adFormat: data.adFormat,
          adUnitName: data.mediationAdUnitName ?? data.placement,
          value: revenue,
          currency: 'USD',
        ));
  }

  void setUserId(String? uid) => _log(() => _fa?.setUserId(id: uid));

  void levelUp(int level) => _log(() => _fa?.logLevelUp(level: level));

  void gameOver({required int level, required int score}) =>
      _log(() => _fa?.logEvent(name: 'game_over', parameters: {'level': level, 'score': score}));

  void gameComplete({required int score}) =>
      _log(() => _fa?.logEvent(name: 'game_complete', parameters: {'score': score}));

  void cocktailMade({required String cocktailId, required int level}) =>
      _log(() => _fa?.logEvent(name: 'cocktail_made', parameters: {'cocktail': cocktailId, 'level': level}));

  void finalItemReached({required int level}) =>
      _log(() => _fa?.logEvent(name: 'final_item_reached', parameters: {'level': level}));

  void spendCoins({required String item, required int amount}) =>
      _log(() => _fa?.logSpendVirtualCurrency(itemName: item, virtualCurrencyName: 'coins', value: amount));

  void _log(Future<void>? Function() call) {
    try {
      call()?.catchError((Object e) => debugPrint('Analytics event failed: $e'));
    } catch (e) {
      debugPrint('Analytics event failed: $e');
    }
  }
}

final analyticsService = AnalyticsService();
