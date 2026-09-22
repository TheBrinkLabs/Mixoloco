import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // StateProvider moved here in Riverpod 3.x
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../services/ad_service.dart';
import 'aluna_banner.dart';

/// Where the single persistent banner ad should currently sit. Defaults
/// to `bottom` — every screen except the game screen wants the banner
/// visible, so only GameScreen ever needs to touch this (hidden on
/// init, bottom again on dispose); the ad-consent screen shows nothing
/// regardless of this value since BannerAdWidget itself no-ops until
/// AdService is actually initialized.
enum BannerPosition { bottom, hidden }

final bannerPositionProvider = StateProvider<BannerPosition>((ref) => BannerPosition.bottom);

/// The ONE instance of [BannerAdWidget] for the whole app, injected above
/// the Navigator via MaterialApp.builder (see main.dart) so it's never
/// unmounted by screen navigation. Screens never create their own
/// banner; they just set [bannerPositionProvider] to say whether it
/// should currently be visible (see GameScreen for the only screen that
/// hides it).
class PersistentBannerAd extends ConsumerWidget {
  const PersistentBannerAd({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(bannerPositionProvider) == BannerPosition.hidden;
    return IgnorePointer(
      ignoring: hidden,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Visibility(
          visible: !hidden,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: const BannerAdWidget(),
        ),
      ),
    );
  }
}

enum _BannerState { loading, loaded, failed }

/// Banner ad backed by Unity LevelPlay, pinned to the bottom safe area.
/// If the ad fails to load — or never responds at all within a
/// reasonable window (covers "no return", not just an explicit failure
/// callback) — falls back to a self-provided house banner instead of
/// leaving a dead strip, same shape as Capitle's own banner_ad_widget.dart.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> implements LevelPlayBannerAdViewListener {
  // Once the ad has failed, wait this long before trying again. Ad
  // auctions refresh, so a request that fails now can easily succeed a
  // bit later — but ad networks generally advise against refreshing much
  // faster than this.
  static const _retryInterval = Duration(seconds: 20);
  static const _providerTimeout = Duration(seconds: 8);

  _BannerState _state = _BannerState.loading;
  Timer? _timeoutTimer;
  Timer? _retryTimer;
  // Bumped on every retry so the ad view gets a new GlobalKey — that's
  // what actually forces its underlying native platform view to be torn
  // down and recreated, which is what triggers a fresh load attempt.
  int _loadAttempt = 0;

  GlobalKey<LevelPlayBannerAdViewState>? _bannerKey;
  int? _bannerKeyAttempt;

  GlobalKey<LevelPlayBannerAdViewState> get _currentBannerKey {
    if (_bannerKeyAttempt != _loadAttempt) {
      _bannerKey = GlobalKey<LevelPlayBannerAdViewState>();
      _bannerKeyAttempt = _loadAttempt;
    }
    return _bannerKey!;
  }

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(_providerTimeout, () {
      if (mounted && _state == _BannerState.loading) _onFailed();
    });
  }

  void _onLoaded() {
    _timeoutTimer?.cancel();
    _retryTimer?.cancel();
    if (mounted) setState(() => _state = _BannerState.loaded);
  }

  void _onFailed() {
    if (!mounted) return;
    setState(() => _state = _BannerState.failed);
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryInterval, () {
      if (!mounted) return;
      setState(() {
        _loadAttempt++;
        _state = _BannerState.loading;
      });
      _startTimeout();
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  // ── LevelPlayBannerAdViewListener ────────────────────────────────────

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) => _onLoaded();

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint('LevelPlay banner failed to load: $error');
    _onFailed();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {
    debugPrint('LevelPlay banner failed to display: $error');
    _onFailed();
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}

  Widget _buildProviderAd() {
    final key = _currentBannerKey;
    return LevelPlayBannerAdView(
      key: key,
      adUnitId: adService.levelPlayBannerAdUnitId,
      adSize: LevelPlayAdSize.BANNER,
      listener: this,
      onPlatformViewCreated: () => key.currentState?.loadAd(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        height: 50, // standard banner height
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Real ad — kept mounted even after falling back (just
            // offstage, and periodically retried via the key bump above),
            // so a later successful load can swap back in automatically
            // without losing the house banner's own state. Built even
            // before LevelPlay itself has finished initializing (no early
            // gate on adService.isLevelPlayInitialized) — same as
            // ad_break_screen's own provider ad, this relies purely on
            // _startTimeout's own timer to fall back to the house banner
            // if the provider never responds, rather than waiting on a
            // flag that never flips true while real ad credentials are
            // still the TODO placeholders in ad_service.dart.
            Offstage(offstage: _state == _BannerState.failed, child: _buildProviderAd()),
            // Also kept permanently mounted rather than built/torn down
            // conditionally — providers can flicker between loaded and
            // failed, and conditionally removing this from the tree would
            // destroy its State every time, restarting the whole
            // Aluna/Higgins/Capitle cycle from scratch instead of just
            // resuming where it left off.
            Offstage(offstage: _state != _BannerState.failed, child: const _HouseBanner()),
          ],
        ),
      ),
    );
  }
}

// ── House banner ─────────────────────────────────────────────────────
// Cross-promotion shown whenever the real ad can't fill. Rotates through
// three brands on a fixed timer rather than picking one and sticking
// with it, so none of them gets starved of impressions just because it
// happened to lose a coin flip on mount — same shape as Capitle's own
// two-brand rotation, extended to three (Capitle itself is now also a
// cross-promoted app worth a turn here).

class _HouseBanner extends StatefulWidget {
  const _HouseBanner();

  @override
  State<_HouseBanner> createState() => _HouseBannerState();
}

class _HouseBannerState extends State<_HouseBanner> {
  // Aluna's own intro + live-view sequence needs ~19.5s to play out in
  // full (see AlunaBanner) — keep this comfortably above that so its
  // Play Store view actually gets a turn before rotating on.
  static const _brandDuration = Duration(seconds: 21);
  static const _brandCount = 3;

  int _brandIndex = 0;
  Timer? _alternateTimer;

  @override
  void initState() {
    super.initState();
    _scheduleNext();
  }

  void _scheduleNext() {
    _alternateTimer = Timer(_brandDuration, () {
      if (!mounted) return;
      setState(() => _brandIndex = (_brandIndex + 1) % _brandCount);
      _scheduleNext();
    });
  }

  @override
  void dispose() {
    _alternateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child;
    switch (_brandIndex) {
      case 0:
        child = const _HigginsBanner(key: ValueKey('higgins'));
        break;
      case 1:
        child = const AlunaBanner(key: ValueKey('aluna'));
        break;
      default:
        child = const _CapitleBanner(key: ValueKey('capitle'));
    }
    // Each brand widget carries its own key so AnimatedSwitcher treats a
    // re-entry as a fresh instance — every brand restarts its own
    // animation/video from scratch every time it cycles back around,
    // rather than trying to resume mid-animation.
    return AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: child);
  }
}

// ── Higgins ──────────────────────────────────────────────────────────
// Dark navy background, bold serif type, cream text with a gold accent
// on the final punctuation mark, typewriter reveal that's LEFT-ANCHORED
// — ported near-verbatim from Capitle's own Higgins house banner.

const _navyBg = Color(0xFF0D1830);
const _cream = Color(0xFFF4F1EA);
const _gold = Color(0xFFD4AF5A);

const List<String> _houseMessages = [
  "Hi, I'm Higgins.",
  "I'm your new personal trainer.",
];

// TODO: once Higgins ships, swap this tap behaviour to open its real
// Play Store listing via url_launcher instead of showing this message.

class _HigginsBanner extends StatefulWidget {
  const _HigginsBanner({super.key});

  @override
  State<_HigginsBanner> createState() => _HigginsBannerState();
}

class _HigginsBannerState extends State<_HigginsBanner> with TickerProviderStateMixin {
  int _messageIndex = 0;
  int _charCount = 0;
  bool _showingComingSoon = false;
  Timer? _typeTimer;
  Timer? _cycleTimer;
  late final AnimationController _cursorController;

  static const _msPerChar = 45;
  static const _pauseAfterTyped = Duration(seconds: 3);
  static const _waitBeforeComingSoon = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
    _startTyping();
  }

  void _startTyping() {
    _charCount = 0;
    final message = _houseMessages[_messageIndex];
    _typeTimer?.cancel();
    _typeTimer = Timer.periodic(const Duration(milliseconds: _msPerChar), (timer) {
      if (!mounted) return;
      setState(() => _charCount++);
      if (_charCount >= message.length) {
        timer.cancel();
        final isLastMessage = _messageIndex == _houseMessages.length - 1;
        if (isLastMessage) {
          _cycleTimer = Timer(_waitBeforeComingSoon, () {
            if (!mounted) return;
            setState(() => _showingComingSoon = true);
          });
          return;
        }
        _cycleTimer = Timer(_pauseAfterTyped, () {
          if (!mounted) return;
          setState(() => _messageIndex = (_messageIndex + 1) % _houseMessages.length);
          _startTyping();
        });
      }
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _cycleTimer?.cancel();
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🐾 Personal Trainer Higgins — coming soon!'), duration: Duration(seconds: 2)),
        );
      },
      child: Container(
        width: double.infinity,
        height: 50,
        color: _navyBg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _showingComingSoon ? _buildComingSoon() : _buildTyping(),
        ),
      ),
    );
  }

  Widget _buildTyping() {
    final message = _houseMessages[_messageIndex];
    final visible = message.substring(0, _charCount.clamp(0, message.length));
    final hasFullText = visible.isNotEmpty;
    final bodyText = hasFullText && visible.length > 1 ? visible.substring(0, visible.length - 1) : '';
    final lastChar = hasFullText ? visible.substring(visible.length - 1) : '';
    final isFullyTyped = _charCount >= message.length;

    return RichText(
      textAlign: TextAlign.left,
      text: TextSpan(
        style: const TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700, fontSize: 16, height: 1.0, decoration: TextDecoration.none),
        children: [
          TextSpan(text: bodyText, style: const TextStyle(color: _cream, decoration: TextDecoration.none)),
          TextSpan(text: lastChar, style: const TextStyle(color: _gold, decoration: TextDecoration.none)),
          if (!isFullyTyped)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: FadeTransition(
                opacity: _cursorController,
                child: const Text('|', style: TextStyle(color: _gold, fontFamily: 'serif', fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComingSoon() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _HigginsLogoBars(),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: const TextStyle(fontFamily: 'serif', fontWeight: FontWeight.w700, fontSize: 16, height: 1.0, decoration: TextDecoration.none),
            children: [
              const TextSpan(text: 'Higgins', style: TextStyle(color: _cream, decoration: TextDecoration.none)),
              const TextSpan(text: '... ', style: TextStyle(color: _gold, decoration: TextDecoration.none)),
              TextSpan(text: 'coming soon', style: TextStyle(color: _cream.withValues(alpha: 0.75), decoration: TextDecoration.none)),
            ],
          ),
        ),
      ],
    );
  }
}

class _HigginsLogoBars extends StatelessWidget {
  const _HigginsLogoBars();

  @override
  Widget build(BuildContext context) {
    Widget bar(double height) => Container(
      width: 5,
      height: height,
      margin: const EdgeInsets.only(right: 3),
      decoration: const BoxDecoration(color: _gold, borderRadius: BorderRadius.vertical(top: Radius.circular(2))),
    );

    return SizedBox(
      width: 24,
      height: 22,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [bar(10), bar(16), bar(22)]),
    );
  }
}

// ── Capitle ──────────────────────────────────────────────────────────
// A real 320x50 animated video creative (assets/videos/banner_fallback_
// capitle.mp4) rather than a hand-built animation — muted, looping, and
// tappable straight through to Capitle's Play Store listing.

const _capitlePlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.capitle';

class _CapitleBanner extends StatefulWidget {
  const _CapitleBanner({super.key});

  @override
  State<_CapitleBanner> createState() => _CapitleBannerState();
}

class _CapitleBannerState extends State<_CapitleBanner> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('assets/videos/banner_fallback_capitle.mp4');
    _controller
      ..setVolume(0)
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
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
    return GestureDetector(
      onTap: _openPlayStore,
      child: Container(
        width: double.infinity,
        height: 50,
        color: Colors.black,
        alignment: Alignment.center,
        child: _ready
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
