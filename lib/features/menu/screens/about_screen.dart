import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/game_logo.dart';
import '../../../core/widgets/wood_plank.dart';

/// Shown on the About page — keep in sync with pubspec.yaml's own
/// `version:` line by hand (no package_info_plus dependency just for
/// one static line of text).
const kAppVersionLabel = '1.0.0';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GameLogo(height: 90),
                    const SizedBox(height: 22),
                    WoodPlank(
                      width: plankWidth,
                      height: plankHeight * 0.75,
                      assetPath: 'assets/images/menu_board_3.png',
                      child: Center(
                        child: ColorfulPlankText(
                          text: '${tr(locale, 'version')} $kAppVersionLabel',
                          fontSize: plankHeight * 0.2,
                          variant: kPlankTextVariant,
                          font: kPlankTextFont,
                          shadowStyle: kPlankShadowStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    WoodPlank(
                      width: plankWidth,
                      height: plankHeight * 2.0,
                      assetPath: 'assets/images/menu_board_3.png',
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: plankWidth * 0.09),
                        child: Center(
                          child: Text(
                            tr(locale, 'about_credits_body'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLight, height: 1.45),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
