import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../i18n/strings.dart';
import '../services/locale_provider.dart';
import '../theme/app_theme.dart';
import 'banner_ad_widget.dart';

const _capitlePlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.capitle';

/// How long Continue stays locked for — a plain countdown, same shape
/// (and same reasoning) as ad_break_screen.dart's own `_minWatchSeconds`
/// rather than gating on the video's own reported playback position.
/// That earlier approach (unlock once `_controller.value.position`
/// reaches `duration`) had no escape path at all if video_player's
/// position stream stalled mid-playback — a watchdog Timer was added to
/// force Continue open after a ceiling, but a report of the hang still
/// happening after that fix pointed at a deeper problem: video_player's
/// native plugin channel itself can stop delivering position updates
/// (buffering, resource contention, a screen-off/on cycle tearing down
/// the decode surface) in a way a Dart-side Timer *should* survive, but
/// evidently wasn't reliably doing so in practice. Decoupling entirely
/// — the video now plays purely for show, Continue unlocks on this
/// timer alone — removes video_player from the unlock path altogether,
/// closing off that whole category of stall rather than racing it.
const _fallbackWatchSeconds = 20;

/// Stands in for the real rewarded "clear shots and continue" ad (see
/// GameScreen._watchAdToContinue) when it isn't available — not
/// configured yet, or no fill. Rather than leaving the continue-offer
/// as a dead end, this plays a short Capitle video in its place.
/// Continue unlocks after [_fallbackWatchSeconds], the same fixed
/// minimum-watch-timer shape the MREC ad break uses (see its doc for
/// why this no longer gates on the video's own playback position).
/// Returns true once that happens, false if the player backs out early
/// — the caller treats a false the same as declining the offer outright.
///
/// Used to embed a YouTube Short via WebView instead — dropped after a
/// field report showed "This video is unavailable — Error code: 152-4"
/// for every user, which turned out to be YouTube itself refusing to
/// embed that video (152 means the uploader/platform has embedding
/// disabled for it — common for Shorts specifically), not a WebView
/// config issue the way an earlier fix attempt assumed. A locally
/// bundled video file sidesteps that category of problem entirely —
/// same approach already proven working for the MREC/banner Capitle
/// ads (see video_mrec_ad.dart, banner_ad_widget.dart's _CapitleBanner).
///
/// Plays assets/videos/continue_fallback_capitle.mp4 (720x1280, a "99%
/// Fail" geography-challenge clip) at a moderate boxed size, not
/// stretched full-bleed to fill the screen — confirmed on-device that
/// scaling this same file up to fill the whole portrait frame is what
/// breaks rendering (leaves the texture a flat grey indefinitely, even
/// though decode/duration/position all genuinely advance); the identical
/// file plays back fine at a small MREC-card size. Sized to the video's
/// own 9:16 aspect rather than force-cropped into a square/landscape box
/// the way the MREC fallback's 300x250 card is. The whole video is the
/// tap target for Capitle's Play Store listing — no separate CTA button
/// — matching how a real video ad's click-through normally works.
/// [restoreBannerOnExit] defaults to true — right for this screen's other
/// two callers (shop_screen.dart/get_credits_dialog.dart's "watch ad for
/// credits," reachable directly from the menu, with nothing else that
/// will ever restore the banner once this hides it). GameScreen's own
/// call passes false, since it hides the banner for its own entire
/// lifetime and only its own dispose should bring it back — restoring it
/// here too would flip the banner visible while popping back to a still-
/// mounted GameScreen that wants it hidden. The bug this fixes: this
/// screen used to never restore the banner at all (a stale comment here
/// claimed GameScreen was "the only real caller," which stopped being
/// true once the Shop's ad-credits flow started using it too) — hitting
/// it from Shop left the banner hidden for the rest of the session, on
/// every screen, with nothing left to ever bring it back.
Future<bool> showContinueFallbackVideo(BuildContext context, AppLocale locale, {bool restoreBannerOnExit = true}) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ContinueFallbackVideoScreen(locale: locale, restoreBannerOnExit: restoreBannerOnExit),
    ),
  );
  return result ?? false;
}

class _ContinueFallbackVideoScreen extends ConsumerStatefulWidget {
  final AppLocale locale;
  final bool restoreBannerOnExit;
  const _ContinueFallbackVideoScreen({required this.locale, required this.restoreBannerOnExit});

  @override
  ConsumerState<_ContinueFallbackVideoScreen> createState() => _ContinueFallbackVideoScreenState();
}

class _ContinueFallbackVideoScreenState extends ConsumerState<_ContinueFallbackVideoScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _canContinue = false;
  int _secondsRemaining = _fallbackWatchSeconds;
  Timer? _countdownTimer;

  /// Restores the bottom banner; captured in initState because Riverpod 3
  /// throws if ref is used inside dispose().
  late final void Function() _restoreBanner;

  @override
  void initState() {
    super.initState();
    // Ads/video playback is exactly the kind of screen a player sits
    // and watches without touching anything — without this, a normal
    // screen-timeout can turn the lights out mid-video.
    WakelockPlus.enable();
    // Started immediately, independent of the video controller below —
    // see _fallbackWatchSeconds' doc for why Continue no longer waits on
    // video_player at all.
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
    // Hidden unconditionally on entry regardless of caller — see
    // [restoreBannerOnExit]'s doc for the exit side of this.
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.hidden;
    final bannerNotifier = ref.read(bannerPositionProvider.notifier);
    _restoreBanner = () => Future.microtask(() => bannerNotifier.state = BannerPosition.bottom);
    _controller = VideoPlayerController.asset('assets/videos/continue_fallback_capitle.mp4');
    _controller
      ..setVolume(0)
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        // Purely cosmetic now (see _fallbackWatchSeconds) — a broken
        // video just leaves the box blank, Continue still unlocks on
        // the timer regardless.
      });
  }

  @override
  void dispose() {
    if (widget.restoreBannerOnExit) {
      _restoreBanner();
    }
    _countdownTimer?.cancel();
    WakelockPlus.disable();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openPlayStore() async {
    final uri = Uri.parse(_capitlePlayStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                  child: GestureDetector(
                    onTap: _openPlayStore,
                    child: Container(
                      width: 320,
                      height: 320 * 16 / 9,
                      decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
                      clipBehavior: Clip.antiAlias,
                      child: _ready
                          ? FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: _controller.value.size.width,
                                height: _controller.value.size.height,
                                child: VideoPlayer(_controller),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: GestureDetector(
                  onTap: _canContinue ? () => Navigator.of(context).pop(true) : null,
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
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _canContinue ? Colors.black : AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
