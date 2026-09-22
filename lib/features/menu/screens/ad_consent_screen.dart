import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';

/// Shown exactly once, before the very first MenuScreen — the real
/// GDPR/CCPA consent choice, not a silent default. [onAnswered] is
/// awaited (buttons disable meanwhile) so the caller can persist the
/// choice and initialize LevelPlay with it before navigating onward; see
/// ad_consent.dart and main.dart's launch gate.
class AdConsentScreen extends ConsumerStatefulWidget {
  final Future<void> Function(BuildContext context, bool consentGranted) onAnswered;
  const AdConsentScreen({super.key, required this.onAnswered});

  @override
  ConsumerState<AdConsentScreen> createState() => _AdConsentScreenState();
}

class _AdConsentScreenState extends ConsumerState<AdConsentScreen> {
  bool _submitting = false;

  Future<void> _answer(bool granted) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.onAnswered(context, granted);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WoodTitlePlank(
                    title: tr(locale, 'ads_consent_title'),
                    icon: Icons.local_bar_rounded,
                    width: plankWidth,
                    height: plankHeight,
                    assetPath: 'assets/images/menu_board_3.png',
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: plankWidth,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                    ),
                    child: Text(
                      tr(locale, 'ads_consent_body'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: _submitting ? null : () => _answer(true),
                    child: Opacity(
                      opacity: _submitting ? 0.6 : 1.0,
                      child: Container(
                        width: plankWidth,
                        height: 54,
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientSunset,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: AppColors.sunsetOrange.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 5))],
                        ),
                        child: Center(
                          child: Text(tr(locale, 'allow'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _submitting ? null : () => _answer(false),
                    child: Opacity(
                      opacity: _submitting ? 0.6 : 1.0,
                      child: SizedBox(
                        width: plankWidth,
                        height: 44,
                        child: Center(
                          child: Text(tr(locale, 'no_thanks'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
