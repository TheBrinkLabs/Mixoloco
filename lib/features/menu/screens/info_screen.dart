import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/wood_plank.dart';
import 'about_screen.dart';
import 'cocktails_screen.dart';
import 'ingredients_screen.dart';
import 'songs_screen.dart';

/// The Info hub — its own pushed screen (same family as Settings/Best
/// Scores) listing the four reference sub-pages rather than cramming
/// them directly onto the main menu.
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

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
                    WoodTitlePlank(title: tr(locale, 'info'), icon: Icons.menu_book_rounded, width: plankWidth, height: plankHeight, assetPath: 'assets/images/menu_board_3.png'),
                    _InfoRow(
                      icon: Icons.local_bar_rounded,
                      label: tr(locale, 'ingredients'),
                      width: plankWidth,
                      height: plankHeight,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngredientsScreen())),
                    ),
                    _InfoRow(
                      icon: Icons.wine_bar_rounded,
                      label: tr(locale, 'cocktails'),
                      width: plankWidth,
                      height: plankHeight,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CocktailsScreen())),
                    ),
                    _InfoRow(
                      icon: Icons.music_note_rounded,
                      label: tr(locale, 'songs'),
                      width: plankWidth,
                      height: plankHeight,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SongsScreen())),
                    ),
                    _InfoRow(
                      icon: Icons.info_rounded,
                      label: tr(locale, 'about'),
                      width: plankWidth,
                      height: plankHeight,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _InfoRow({required this.icon, required this.label, required this.width, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.06),
          child: Row(
            children: [
              Icon(icon, size: height * 0.3, color: kPlankIconColor, shadows: kPlankIconShadows),
              SizedBox(width: width * 0.03),
              Expanded(
                child: ColorfulPlankText(text: label, fontSize: height * 0.22, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
              ),
              Icon(Icons.chevron_right_rounded, size: height * 0.3, color: kPlankIconColor),
            ],
          ),
        ),
      ),
    );
  }
}
