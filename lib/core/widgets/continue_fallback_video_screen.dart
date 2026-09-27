import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../i18n/strings.dart';
import '../services/locale_provider.dart';
import '../theme/app_theme.dart';
import 'banner_ad_widget.dart';

const _capitlePlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.capitle';

/// How close to the very end counts as "finished" — video_player's
/// position updates don't always land exactly on duration (the last
/// reported position can sit a frame or two short), so waiting for an
/// exact match can leave Continue stuck just short of unlocking.
const _completionTolerance = Duration(milliseconds: 300);

/// Stands in for the real rewarded "clear shots and continue" ad (see
/// GameScreen._watchAdToContinue) when it isn't available — not
/// configured yet, or no fill. Rather than leaving the continue-offer
/// as a dead end, this plays a short Capitle video in its place. Unlike
/// the MREC ad break's fixed minimum-watch timer, Continue only unlocks
/// once the video has actually finished playing — this is standing in
/// for a real rewarded ad, which the same way requires watching the
/// whole thing, not a skippable placeholder. Returns true once that
/// happens, false if the player backs out early — the caller treats a
/// false the same as declining the offer outright.
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
Future<bool> showContinueFallbackVideo(BuildContext context, AppLocale locale) async {
  final result = await Navigator.of(context).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => _ContinueFallbackVideoScreen(locale: locale)),
  );
  return result ?? false;
}

class _ContinueFallbackVideoScreen extends ConsumerStatefulWidget {
  final AppLocale locale;
  const _ContinueFallbackVideoScreen({required this.locale});

  @override
  ConsumerState<_ContinueFallbackVideoScreen> createState() => _ContinueFallbackVideoScreenState();
}

class _ContinueFallbackVideoScreenState extends ConsumerState<_ContinueFallbackVideoScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _canContinue = false;
  int _secondsRemaining = 0;

  @override
  void initState() {
    super.initState();
    // GameScreen (the only real caller — see _watchAdToContinue) already
    // hides the persistent banner for as long as it's mounted, so this
    // is normally redundant — but it's not safe to rely on that: this
    // widget is also reachable in isolation (e.g. a debug/test entry
    // point that skips GameScreen), where nothing else would have
    // hidden it, and the banner ends up sitting over the Continue
    // button. Deliberately does NOT restore it to `bottom` on dispose
    // — this screen pops back to GameScreen, which still wants it
    // hidden for the rest of the run; only GameScreen's own dispose
    // should ever bring it back.
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.hidden;
    _controller = VideoPlayerController.asset('assets/videos/continue_fallback_capitle.mp4');
    _controller
      ..setVolume(0)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _ready = true;
          _secondsRemaining = _controller.value.duration.inSeconds;
        });
        _controller.play();
      }).catchError((_) {
        // A broken/unplayable video shouldn't trap the player on a dead
        // screen with no way forward — same "never leave a hard stop"
        // reasoning as every other ad-fallback in this chain.
        if (!mounted) return;
        setState(() => _canContinue = true);
      });
    _controller.addListener(_onVideoTick);
  }

  void _onVideoTick() {
    if (!mounted || !_ready || _canContinue) return;
    final position = _controller.value.position;
    final duration = _controller.value.duration;
    if (duration == Duration.zero) return;

    final remainingMs = (duration - position).inMilliseconds;
    final remainingSeconds = (remainingMs / 1000).ceil().clamp(0, duration.inSeconds);
    if (remainingSeconds != _secondsRemaining) {
      setState(() => _secondsRemaining = remainingSeconds);
    }
    if (remainingMs <= _completionTolerance.inMilliseconds) {
      setState(() => _canContinue = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoTick);
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
