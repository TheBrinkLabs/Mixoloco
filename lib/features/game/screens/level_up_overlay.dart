import 'package:flutter/material.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/wood_plank.dart';

enum _Step { celebrate, ontoNext, ad }

/// Pushes the end-of-level sequence as a fullscreen route: a "Level
/// Complete!" beat, then "Onto the next level!", then the end-of-level
/// interstitial, then pops itself — letting the already-swapped level-2
/// background/table underneath finally show through (see GameScreen,
/// which pushes state.level to 2 the instant the unlock conditions are
/// met; this overlay is what actually covers that swap until the
/// celebration's played out, rather than the background just silently
/// changing mid-frame). A plain pushed route rather than a Stack overlay
/// so Navigator handles "on top of everything, blocks input beneath" for
/// free instead of this screen having to thread another blockInput flag
/// through its own layout.
Future<void> showLevelUpOverlay(BuildContext context, AppLocale locale) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => LevelUpOverlay(locale: locale),
    ),
  );
}

class LevelUpOverlay extends StatefulWidget {
  final AppLocale locale;
  const LevelUpOverlay({super.key, required this.locale});

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay> {
  _Step _step = _Step.celebrate;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), _advanceToOntoNext);
  }

  void _advanceToOntoNext() {
    if (!mounted) return;
    setState(() => _step = _Step.ontoNext);
    Future.delayed(const Duration(milliseconds: 1500), _showInterstitial);
  }

  void _showInterstitial() {
    if (!mounted) return;
    setState(() => _step = _Step.ad);
    adService.showLevelPlayInterstitial(
      onDismissed: _finish,
      // Never leave the player stuck waiting on an ad that isn't
      // coming — give it a moment in case a load was already in flight,
      // then just move on into level 2 anyway.
      onNotReady: () => Future.delayed(const Duration(seconds: 2), _finish),
    );
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
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _step == _Step.ad
                ? const SizedBox(key: ValueKey('ad'), width: 40, height: 40, child: CircularProgressIndicator(color: AppColors.sunsetGold))
                : _buildMessage(),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage() {
    final text = _step == _Step.celebrate ? tr(widget.locale, 'level_complete_title') : tr(widget.locale, 'onto_next_level');
    return TweenAnimationBuilder<double>(
      key: ValueKey(_step),
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: ColorfulPlankText(
        text: text,
        fontSize: 34,
        variant: PlankTextVariant.sunsetGradient,
        font: kPlankTextFont,
        shadowStyle: kPlankShadowStyle,
      ),
    );
  }
}
