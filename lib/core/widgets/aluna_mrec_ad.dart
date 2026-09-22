import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/aluna_availability_service.dart';

// Colors mirror Aluna's own brand — ported verbatim from Capitle's
// aluna_mrec_ad.dart (same cross-promoted app, same card), kept as its
// own copy here rather than shared across two separate apps' codebases.
const _mrecBg = Color(0xFF0B1F16);
const _mrecBgDeep = Color(0xFF0F241A);
const _mrecMint = Color(0xFF6EE7B7);
const _mrecWhite = Color(0xFFF4FFF9);
const _mrecPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.aluna';

// One font, two weights, two opacities — everything on this card reads
// as the same calm voice rather than a grab-bag of ad-copy styles.
TextStyle _mrecFont({required double size, required FontWeight weight, required Color color}) {
  return GoogleFonts.quicksand(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: 1.3,
    letterSpacing: 0.2,
    decoration: TextDecoration.none,
  );
}

/// Fallback shown in Mixoloco's score-milestone MREC ad break (see
/// ad_break_screen.dart) when the real network ad fails to fill — ported
/// directly from Capitle's own AlunaMrecAd (its "watch an ad for a clue"
/// screen uses the exact same card), per direct request to reuse it
/// here rather than build a new one from scratch. A slow, noticeably
/// breathing icon with a calm sequence of soft fading lines beneath it,
/// ending on a Google Play call to action — deliberately paced slowly,
/// meant to feel like a moment of calm rather than a typical ad's snappy
/// attention-grab. The whole card is tappable and opens Aluna's real
/// Play Store listing, same as Capitle's own copy does.
class AlunaMrecAd extends StatefulWidget {
  const AlunaMrecAd({super.key});

  @override
  State<AlunaMrecAd> createState() => _AlunaMrecAdState();
}

class _AlunaMrecAdState extends State<AlunaMrecAd> with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  int _slideIndex = 0;
  bool _started = false;
  Timer? _cycleTimer;

  // Long, slow, and eased — a linear repeat reads mechanical; easing
  // in/out of each breath is what actually makes it look like breathing.
  static const _breatheCycle = Duration(seconds: 7);
  static const _breatheAmount = 0.34;
  static const _breatheStartDelay = Duration(milliseconds: 500);
  // Each line still gets a slow, relaxed fade — but paced so at least a
  // couple of lines are actually seen within the ad break's own minimum
  // watch time before "Continue" unlocks, rather than the viewer sitting
  // on just the first line the whole time.
  static const _introDelay = Duration(milliseconds: 500);
  static const _slideInterval = Duration(seconds: 3, milliseconds: 800);
  static const _fadeDuration = Duration(milliseconds: 1200);
  static const _slideCount = 6;

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(vsync: this, duration: _breatheCycle);
    // The icon breathes continuously for as long as this card is on
    // screen — a brief settle before it starts, rather than animating
    // immediately on mount.
    Future.delayed(_breatheStartDelay, () {
      if (mounted) _breatheController.repeat(reverse: true);
    });
    // Start from nothing so the very first line genuinely fades in too,
    // rather than popping in instantly the way AnimatedSwitcher's first
    // child otherwise would.
    Future.delayed(_introDelay, () {
      if (!mounted) return;
      setState(() => _started = true);
      _cycleTimer = Timer.periodic(_slideInterval, (_) {
        if (!mounted) return;
        setState(() => _slideIndex = (_slideIndex + 1) % _slideCount);
      });
    });
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _cycleTimer?.cancel();
    super.dispose();
  }

  Future<void> _openPlayStore() async {
    if (!alunaAvailabilityService.isLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🌿 Aluna — coming soon!'), duration: Duration(seconds: 2)),
      );
      return;
    }
    final uri = Uri.parse(_mrecPlayStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openPlayStore,
      child: Container(
        width: 300,
        height: 250,
        decoration: BoxDecoration(color: _mrecBg, borderRadius: BorderRadius.circular(12)),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _breatheController,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_breatheController.value);
                final scale = 1.0 + (t * _breatheAmount);
                return Transform.scale(scale: scale, child: child);
              },
              child: SizedBox(
                width: 132,
                height: 132,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 132,
                      height: 132,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [_mrecMint.withValues(alpha: 0.38), Colors.transparent]),
                      ),
                    ),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _mrecBgDeep,
                        border: Border.all(color: _mrecMint, width: 2.5),
                        boxShadow: [BoxShadow(color: _mrecMint.withValues(alpha: 0.5), blurRadius: 20, spreadRadius: 2)],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 64,
              child: Center(
                child: AnimatedSwitcher(duration: _fadeDuration, child: _buildSlide(_slideIndex)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(int index) {
    if (!_started) return const SizedBox.shrink(key: ValueKey('blank'));
    switch (index) {
      case 0:
        return _text('Feeling overwhelmed?', slideKey: 'q1', size: 17);
      case 1:
        return _text('take a moment', slideKey: 'q2', size: 17);
      case 2:
        return _wordmark(slideKey: 'wordmark');
      case 3:
        return _text('your wellbeing companion', slideKey: 'q4', size: 15);
      case 4:
        return _text('No ads · no subscription', slideKey: 'q5', size: 15);
      default:
        return _playStoreCta(slideKey: 'cta');
    }
  }

  // One shared, soft style for every line on the card (bar the wordmark)
  // — nothing gets to look bolder or brighter than anything else.
  Widget _text(String text, {required String slideKey, required double size}) {
    return Center(
      key: ValueKey(slideKey),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _mrecFont(size: size, weight: FontWeight.w500, color: _mrecWhite.withValues(alpha: 0.82)),
      ),
    );
  }

  Widget _wordmark({required String slideKey}) {
    final base = _mrecFont(size: 32, weight: FontWeight.w500, color: _mrecWhite);
    // A gentle real blur (not just a lighter weight) is what actually
    // reads as "fuzzy, very soft" rather than merely dim.
    return Center(
      key: ValueKey(slideKey),
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 1.1, sigmaY: 1.1),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: base.copyWith(height: 1.0),
            children: [
              TextSpan(text: 'a', style: base.copyWith(color: _mrecMint.withValues(alpha: 0.85))),
              TextSpan(text: 'lun', style: base.copyWith(color: _mrecWhite.withValues(alpha: 0.82))),
              TextSpan(text: 'a', style: base.copyWith(color: _mrecMint.withValues(alpha: 0.85))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playStoreCta({required String slideKey}) {
    return Center(
      key: ValueKey(slideKey),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Available now on',
            textAlign: TextAlign.center,
            style: _mrecFont(size: 13, weight: FontWeight.w500, color: _mrecWhite.withValues(alpha: 0.82)),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF00D2FF), Color(0xFF00F076), Color(0xFFFFCF00), Color(0xFFFF3A44)],
                  stops: [0.0, 0.4, 0.65, 1.0],
                ).createShader(bounds),
                child: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text('Google Play', style: _mrecFont(size: 14, weight: FontWeight.w500, color: _mrecWhite.withValues(alpha: 0.82))),
            ],
          ),
        ],
      ),
    );
  }
}
