import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/game_logo.dart';
import '../../../core/widgets/wood_plank.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  // Null while loading — the version plank just shows a blank value
  // briefly rather than a hardcoded number that could drift from
  // pubspec.yaml's own (see PackageInfo.fromPlatform, which reads the
  // actual installed build's version, not a string maintained by hand).
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = info.version);
    });
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
        child: Stack(
          children: [
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
                          text: '${tr(locale, 'version')} ${_version ?? ''}',
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
                      height: plankHeight * 2.2,
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
            // Painted last — see info_screen.dart's matching comment.
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
          ],
        ),
      ),
    );
  }
}
