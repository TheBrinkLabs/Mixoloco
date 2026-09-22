import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../i18n/strings.dart';
import '../services/ad_service.dart';
import '../services/locale_provider.dart';
import '../theme/app_theme.dart';
import 'aluna_mrec_ad.dart';
import 'video_mrec_ad.dart';

/// A short, full-screen ad break — an MREC embedded in a page we control,
/// with our own always-visible countdown/continue button, shown every
/// [kAdBreakScoreThreshold] points (see game_state_provider.dart).
/// Modelled directly on Capitle's own "watch an ad for a clue" screen:
/// same embedded-MREC-plus-owned-minimum-watch-timer shape, just without
/// that screen's "this unlocks something" framing — here it's a plain
/// break between rounds of play, so it auto-continues once the timer
/// runs out rather than needing an explicit reward to hand back.
Future<void> showAdBreakScreen(BuildContext context, AppLocale locale) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _AdBreakScreen(locale: locale)),
  );
}

class _AdBreakScreen extends StatefulWidget {
  final AppLocale locale;
  const _AdBreakScreen({required this.locale});

  @override
  State<_AdBreakScreen> createState() => _AdBreakScreenState();
}

class _AdBreakScreenState extends State<_AdBreakScreen> implements LevelPlayBannerAdViewListener {
  static const _minWatchSeconds = 9;
  static const _providerTimeout = Duration(seconds: 6);

  final _mrecKey = GlobalKey<LevelPlayBannerAdViewState>();

  // Picked once per ad break (not re-rolled on rebuild) so the two
  // fallbacks split impressions roughly evenly across a session rather
  // than one always winning.
  final bool _useVideoFallback = Random().nextBool();

  bool _adFailed = false;
  bool _canContinue = false;
  int _secondsRemaining = _minWatchSeconds;
  Timer? _countdownTimer;
  Timer? _loadTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _startProviderTimeout();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }

  void _startProviderTimeout() {
    _loadTimeoutTimer?.cancel();
    _loadTimeoutTimer = Timer(_providerTimeout, _onProviderFailed);
  }

  void _onProviderFailed() {
    if (!mounted || _countdownTimer != null) return;
    setState(() => _adFailed = true);
    _startCountdown();
  }

  void _startCountdown() {
    _loadTimeoutTimer?.cancel();
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _canContinue = true;
        });
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Widget _buildProviderAd() {
    return LevelPlayBannerAdView(
      key: _mrecKey,
      adUnitId: adService.levelPlayMrecAdUnitId,
      adSize: LevelPlayAdSize.MEDIUM_RECTANGLE,
      listener: this,
      onPlatformViewCreated: () => _mrecKey.currentState?.loadAd(),
    );
  }

  // ── LevelPlayBannerAdViewListener ────────────────────────────────────

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => _startCountdown();

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint('Ad break (LevelPlay MREC) failed to load: $error');
    _onProviderFailed();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {
    debugPrint('Ad break (LevelPlay MREC) failed to display: $error');
    _onProviderFailed();
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                tr(widget.locale, 'advertisement'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.textMuted),
              ),
            ),
            Expanded(
              child: Center(
                child: _adFailed ? (_useVideoFallback ? const VideoMrecAd() : const AlunaMrecAd()) : _buildProviderAd(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: GestureDetector(
                onTap: _canContinue ? () => Navigator.of(context).pop() : null,
                child: AnimatedOpacity(
                  opacity: _canContinue ? 1.0 : 0.5,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    width: double.infinity,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: _canContinue ? AppColors.gradientSunset : null,
                      color: _canContinue ? null : AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _canContinue
                          ? [BoxShadow(color: AppColors.sunsetOrange.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 5))]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        _canContinue ? tr(widget.locale, 'continue_label') : '${tr(widget.locale, 'continue_in')} ${_secondsRemaining}s',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _canContinue ? Colors.black : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
