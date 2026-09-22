import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/aluna_availability_service.dart';

// ── Aluna house banner ───────────────────────────────────────────────
// Dark green background with a glowing mint ring icon that slowly
// "breathes" (scales up and down), matching Aluna's own brand look.
// Text cycles by fading in/out. Once the intro word cycle finishes, it
// settles into a permanent live state that itself alternates between a
// tagline and a "get it on Google Play" call to action — the whole
// banner is tappable and opens Aluna's real Play Store listing.
//
// Ported near-verbatim from Capitle's aluna_house_ad.dart (its
// AlunaBanner is the 320x50 nav-banner version, distinct from
// AlunaMrecAd's 300x250 card also used in this project) — same
// visual/timing design, only adapted to `.withValues(alpha:)` and this
// project's own aluna_availability_service.

const _alunaBg = Color(0xFF0B1F16);
const _alunaBgDeep = Color(0xFF0F241A);
const _alunaMint = Color(0xFF6EE7B7);
const _alunaWhite = Color(0xFFF4FFF9);
const _alunaMuted = Color(0xFFAFC2B8);

const List<String> _alunaMessages = [
  'relax',
  'take deep breaths',
];

const _alunaPlayStoreUrl = 'https://play.google.com/store/apps/details?id=com.brinklabs.aluna';

class AlunaBanner extends StatefulWidget {
  const AlunaBanner({super.key});

  @override
  State<AlunaBanner> createState() => _AlunaBannerState();
}

enum _AlunaLiveView { tagline, playStore }

class _AlunaBannerState extends State<AlunaBanner> with TickerProviderStateMixin {
  late final AnimationController _breatheController;
  int _messageIndex = 0;
  bool _wordVisible = false;
  bool _isLive = false;
  _AlunaLiveView _liveView = _AlunaLiveView.tagline;
  Timer? _sequenceTimer;
  Timer? _liveViewTimer;

  static const _wordFadeIn = Duration(milliseconds: 1400);
  static const _holdWord = Duration(milliseconds: 3000);
  static const _iconSettleDelay = Duration(milliseconds: 900);
  static const _breatheStartDelay = Duration(seconds: 3);
  static const _breatheCycle = Duration(seconds: 4);
  static const _taglineDuration = Duration(seconds: 4, milliseconds: 500);

  @override
  void initState() {
    super.initState();
    _breatheController = AnimationController(vsync: this, duration: _breatheCycle);
    Future.delayed(_breatheStartDelay, () {
      if (mounted) _breatheController.repeat(reverse: true);
    });
    _sequenceTimer = Timer(_iconSettleDelay, () {
      if (!mounted) return;
      setState(() => _wordVisible = true);
      _runWordCycle();
    });
  }

  void _runWordCycle() {
    _sequenceTimer = Timer(_wordFadeIn + _holdWord, () {
      if (!mounted) return;
      setState(() => _wordVisible = false);
      _sequenceTimer = Timer(_wordFadeIn, () {
        if (!mounted) return;
        final isLastMessage = _messageIndex == _alunaMessages.length - 1;
        if (isLastMessage) {
          setState(() {
            _isLive = true;
            _wordVisible = true;
          });
          _scheduleNextLiveView();
          return;
        }
        setState(() {
          _messageIndex++;
          _wordVisible = true;
        });
        _runWordCycle();
      });
    });
  }

  void _scheduleNextLiveView() {
    _liveViewTimer = Timer(_taglineDuration, () {
      if (!mounted) return;
      setState(() => _liveView = _AlunaLiveView.playStore);
    });
  }

  Future<void> _openPlayStore() async {
    if (!alunaAvailabilityService.isLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🌿 Aluna — coming soon!'), duration: Duration(seconds: 2)),
      );
      return;
    }
    final uri = Uri.parse(_alunaPlayStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    _liveViewTimer?.cancel();
    _breatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openPlayStore,
      child: Container(
        width: double.infinity,
        height: 50,
        color: _alunaBg,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _breatheController,
              builder: (context, child) {
                final scale = 1.0 + (_breatheController.value * 0.45);
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _alunaBgDeep,
                  border: Border.all(color: _alunaMint, width: 1.5),
                  boxShadow: [
                    BoxShadow(color: _alunaMint.withValues(alpha: 0.55), blurRadius: 9, spreadRadius: 1),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedOpacity(
                opacity: _wordVisible ? 1.0 : 0.0,
                duration: _wordFadeIn,
                child: _isLive ? _buildLiveContent() : _buildWord(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWord() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _alunaMessages[_messageIndex],
        style: GoogleFonts.quicksand(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: _alunaWhite,
          height: 1.0,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }

  Widget _buildLiveContent() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: _liveView == _AlunaLiveView.tagline
          ? _buildTagline(key: const ValueKey('tagline'))
          : _buildPlayStoreRow(key: const ValueKey('playstore')),
    );
  }

  Widget _buildWordmark({double fontSize = 16}) {
    return RichText(
      text: TextSpan(
        style: GoogleFonts.quicksand(fontSize: fontSize, fontWeight: FontWeight.w700, height: 1.0, decoration: TextDecoration.none),
        children: const [
          TextSpan(text: 'a', style: TextStyle(color: _alunaMint, decoration: TextDecoration.none)),
          TextSpan(text: 'lun', style: TextStyle(color: _alunaWhite, decoration: TextDecoration.none)),
          TextSpan(text: 'a', style: TextStyle(color: _alunaMint, decoration: TextDecoration.none)),
        ],
      ),
    );
  }

  Widget _buildTagline({Key? key}) {
    return Align(
      key: key,
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.quicksand(fontSize: 16, fontWeight: FontWeight.w700, height: 1.0, decoration: TextDecoration.none),
          children: [
            const TextSpan(text: 'a', style: TextStyle(color: _alunaMint, decoration: TextDecoration.none)),
            const TextSpan(text: 'lun', style: TextStyle(color: _alunaWhite, decoration: TextDecoration.none)),
            const TextSpan(text: 'a', style: TextStyle(color: _alunaMint, decoration: TextDecoration.none)),
            const TextSpan(text: '  ·  ', style: TextStyle(color: _alunaMuted, decoration: TextDecoration.none)),
            TextSpan(
              text: 'no ads, no subscription, on Play Store now',
              style: GoogleFonts.quicksand(fontSize: 12, fontWeight: FontWeight.w500, color: _alunaMuted, height: 1.0, decoration: TextDecoration.none),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayStoreRow({Key? key}) {
    return Row(
      key: key,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildWordmark(),
        const _GooglePlayBadge(),
      ],
    );
  }
}

/// Small "available on Google Play" badge — the Play triangle (rendered
/// with the store's own 4-colour gradient via ShaderMask rather than a
/// bundled image) plus "Google Play" in a Google-ish sans-serif.
class _GooglePlayBadge extends StatelessWidget {
  const _GooglePlayBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF00D2FF),
              Color(0xFF00F076),
              Color(0xFFFFCF00),
              Color(0xFFFF3A44),
            ],
            stops: [0.0, 0.4, 0.65, 1.0],
          ).createShader(bounds),
          child: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(
          'Google Play',
          style: GoogleFonts.roboto(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _alunaWhite,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
