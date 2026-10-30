import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bar_backdrop.dart'
    show FilteredAssetImage, backgroundAssetPathForLevel, backgroundFilterForLevel;
import '../../../core/widgets/notification_tablet.dart' show StoneButton;
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/ingredient.dart' show barForLevel, isAfterDarkLevel, kBarNames;

enum _Step { celebrate, ad, ready }

/// Pushes the end-of-level sequence as a fullscreen route: a "Level
/// Complete!" beat (with a confetti burst) that waits for the player to
/// tap Next, then the end-of-level interstitial, then a "ready" beat —
/// [level]'s own background photo loaded in on its own (no table/tabs/
/// HUD yet) behind a "Level [level]" message and a Play button — before
/// finally popping, letting GameScreen's already-reset table/HUD
/// (swapped in before this overlay ever showed — see GameScreen, which
/// pushes state.level up front and calls this to cover that swap) show
/// through only once the player actually taps Play. A plain pushed route
/// rather than a Stack overlay so Navigator handles "on top of
/// everything, blocks input beneath" for free instead of this screen
/// having to thread another blockInput flag through its own layout.
Future<void> showLevelUpOverlay(BuildContext context, AppLocale locale, {required int level}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => LevelUpOverlay(locale: locale, level: level),
    ),
  );
}

class LevelUpOverlay extends StatefulWidget {
  final AppLocale locale;
  final int level;
  const LevelUpOverlay({super.key, required this.locale, required this.level});

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay> with SingleTickerProviderStateMixin {
  _Step _step = _Step.celebrate;

  /// Drives the confetti burst — starts the moment the celebration
  /// appears and simply stays finished once played; there's no auto
  /// advance to wait for (see [_ConfettiBurst]'s own doc), the player
  /// taps Next when they're ready.
  late final AnimationController _confettiController;
  late final List<_ConfettiPiece> _confettiPieces;

  @override
  void initState() {
    super.initState();
    // Bigger celebration per feedback — more confetti, running longer,
    // than the original 28-piece/2.2s burst.
    _confettiController = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..forward();
    _confettiPieces = List.generate(48, (_) => _ConfettiPiece.random());
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _onNextPressed() {
    if (!mounted || _step != _Step.celebrate) return;
    // Ad-free purchase active — skip straight to the ready beat, same as
    // GameScreen._runAdBreak skips the MREC ad break entirely.
    if (purchaseService.isAdFree) {
      _showReady();
      return;
    }
    setState(() => _step = _Step.ad);
    adService.showLevelPlayInterstitial(
      onDismissed: _showReady,
      // Never leave the player stuck waiting on an ad that isn't
      // coming — give it a moment in case a load was already in flight,
      // then just move on into the ready beat anyway.
      onNotReady: () => Future.delayed(const Duration(seconds: 2), _showReady),
    );
  }

  void _showReady() {
    if (!mounted) return;
    setState(() => _step = _Step.ready);
  }

  void _finish() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The sequence runs itself through to completion — no dismissing
      // it early with a back-gesture mid-celebration.
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The ready beat shows the new level's real background photo
          // (no table/HUD yet — those are already loaded underneath,
          // just still covered) instead of the plain dark scrim the
          // celebrate/ad beats use.
          if (_step == _Step.ready)
            FilteredAssetImage(
              assetPath: backgroundAssetPathForLevel(widget.level),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              // See BarBackdrop's matching comment.
              cacheWidth: MediaQuery.sizeOf(context).width > 0
                  ? (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round()
                  : null,
              colorFilter: backgroundFilterForLevel(widget.level),
            ),
          Container(color: Colors.black.withValues(alpha: _step == _Step.ready ? 0.35 : 0.75)),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_step == _Step.celebrate)
                  AnimatedBuilder(
                    animation: _confettiController,
                    builder: (context, _) => CustomPaint(
                      size: Size.infinite,
                      painter: _ConfettiPainter(pieces: _confettiPieces, t: _confettiController.value),
                    ),
                  ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: switch (_step) {
                    _Step.ad => const SizedBox(key: ValueKey('ad'), width: 40, height: 40, child: CircularProgressIndicator(color: AppColors.sunsetGold)),
                    _Step.ready => _buildReadyMessage(),
                    _Step.celebrate => _buildCelebrateMessage(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCelebrateMessage() {
    return Column(
      key: const ValueKey('celebrate'),
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1.0),
          duration: const Duration(milliseconds: 550),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 12, 32, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: SubmenuColors.gold, width: 3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
              ),
              boxShadow: [
                BoxShadow(color: SubmenuColors.goldEdge, offset: const Offset(0, 6)),
                BoxShadow(color: Colors.black.withValues(alpha: 0.4), offset: const Offset(0, 14), blurRadius: 24),
              ],
            ),
            child: OutlinedLabel(
              text: tr(widget.locale, 'level_complete_title').toUpperCase(),
              fontSize: 40,
              fill: Colors.white,
              stroke: SubmenuColors.goldEdge,
              strokeWidth: 6,
            ),
          ),
        ),
        const SizedBox(height: 32),
        StoneButton(onTap: _onNextPressed, width: 220, height: 54, child: Text(tr(widget.locale, 'next'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black))),
      ],
    );
  }

  Widget _buildReadyMessage() {
    final barName = kBarNames[barForLevel(widget.level) - 1];
    return Column(
      key: const ValueKey('ready'),
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1.0),
          duration: const Duration(milliseconds: 450),
          curve: Curves.elasticOut,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tr(widget.locale, 'level')} ${widget.level}'.toUpperCase(),
                style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, letterSpacing: 1.4, color: SubmenuColors.gold),
              ),
              const SizedBox(height: 4),
              OutlinedLabel(text: barName.toUpperCase(), fontSize: 44, fill: Colors.white, stroke: SubmenuColors.ring, strokeWidth: 6),
              if (isAfterDarkLevel(widget.level))
                const OutlinedLabel(
                  text: 'NIGHT',
                  fontSize: 26,
                  fill: SubmenuColors.gold,
                  stroke: SubmenuColors.ring,
                  strokeWidth: 5,
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        StoneButton(onTap: _finish, width: 220, height: 54, child: Text(tr(widget.locale, 'play_game'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black))),
      ],
    );
  }
}

/// One confetti piece's randomized flight — a small rect that launches
/// from center, arcs under a light simulated gravity, spins, and fades
/// out over the burst's duration. Purely cosmetic parameters (all in
/// normalized 0..1-ish ranges scaled against the actual canvas size at
/// paint time), regenerated fresh each time the overlay's shown.
class _ConfettiPiece {
  _ConfettiPiece({
    required this.angle,
    required this.speed,
    required this.color,
    required this.size,
    required this.spinSpeed,
    required this.startDelay,
  });

  final double angle;
  final double speed;
  final Color color;
  final double size;
  final double spinSpeed;
  final double startDelay;

  static final _colors = [AppColors.sunsetGold, AppColors.sunsetOrange, Colors.pinkAccent, Colors.lightBlueAccent, Colors.greenAccent];

  factory _ConfettiPiece.random() {
    final r = Random();
    return _ConfettiPiece(
      angle: r.nextDouble() * pi * 2,
      speed: 0.55 + r.nextDouble() * 0.55,
      color: _colors[r.nextInt(_colors.length)],
      size: 5 + r.nextDouble() * 5,
      spinSpeed: (r.nextDouble() - 0.5) * 14,
      startDelay: r.nextDouble() * 0.15,
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.pieces, required this.t});
  final List<_ConfettiPiece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.4);
    final scale = size.shortestSide;
    for (final p in pieces) {
      final localT = ((t - p.startDelay) / (1 - p.startDelay)).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final dx = cos(p.angle) * p.speed * scale * 0.6 * localT;
      final dy = sin(p.angle) * p.speed * scale * 0.35 * localT + 0.5 * scale * localT * localT;
      final opacity = (1 - localT).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: opacity);
      canvas.save();
      canvas.translate(center.dx + dx, center.dy + dy);
      canvas.rotate(p.spinSpeed * localT);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => oldDelegate.t != t;
}
