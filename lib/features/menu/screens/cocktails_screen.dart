import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/locked_overlay.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../game/providers/game_state_provider.dart';
import '../info_level_data.dart';
import 'cocktail_detail_screen.dart';

/// Every cocktail order in the game, one page per level (see
/// [kInfoLevels]) — same swipe-between-levels pattern as
/// ingredients_screen.dart. Each row is just the picture and name — tap
/// it for the full recipe (ingredients + how-to-make) on its own page,
/// since a full ingredient breakdown didn't leave enough room on the
/// row itself.
class CocktailsScreen extends ConsumerStatefulWidget {
  const CocktailsScreen({super.key});

  @override
  ConsumerState<CocktailsScreen> createState() => _CocktailsScreenState();
}

class _CocktailsScreenState extends ConsumerState<CocktailsScreen> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final highestLevelReached = ref.watch(gameStateProvider).highestLevelReached;
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            children: [
              for (final level in kInfoLevels)
                _CocktailsLevelPage(
                  level: level,
                  locked: level.level > highestLevelReached,
                  plankWidth: plankWidth,
                  plankHeight: plankHeight,
                  locale: locale,
                ),
            ],
          ),
          Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
        ],
      ),
    );
  }
}

class _CocktailsLevelPage extends StatelessWidget {
  final InfoLevelData level;
  final bool locked;
  final double plankWidth;
  final double plankHeight;
  final AppLocale locale;
  const _CocktailsLevelPage({required this.level, required this.locked, required this.plankWidth, required this.plankHeight, required this.locale});

  @override
  Widget build(BuildContext context) {
    return BarBackdrop(
      showTable: false,
      showHeaderBoard: false,
      backgroundAssetPath: level.backgroundAssetPath,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WoodTitlePlank(
                title: '${tr(locale, 'cocktails')} — ${level.name}',
                icon: Icons.wine_bar_rounded,
                iconAsset: 'assets/images/mohito.png',
                width: plankWidth,
                height: plankHeight,
                assetPath: 'assets/images/menu_board_3.png',
                fontScale: 0.72,
              ),
              // One blur over the whole locked column rather than one
              // per row — see ingredients_screen.dart's matching comment.
              LockedContent(
                locked: locked,
                child: Column(
                  children: [
                    for (final recipe in level.recipes)
                      _CocktailRow(
                        recipe: recipe,
                        locked: locked,
                        width: plankWidth,
                        height: plankHeight,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => CocktailDetailScreen(recipe: recipe, backgroundAssetPath: level.backgroundAssetPath)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CocktailRow extends StatelessWidget {
  final CocktailRecipe recipe;
  final bool locked;
  final double width;
  final double height;
  final VoidCallback onTap;
  const _CocktailRow({required this.recipe, required this.locked, required this.width, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: locked ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: WoodPlank(
        width: width,
        height: height,
        assetPath: 'assets/images/menu_board_3.png',
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: width * 0.06),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  recipe.assetPath,
                  width: height * 0.72,
                  height: height * 0.72,
                  fit: BoxFit.contain,
                  // A few Level 3 recipes reference art that hasn't been
                  // supplied yet — a plain glyph beats Flutter's broken-
                  // image icon until it lands.
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.local_bar_rounded, size: height * 0.5, color: kPlankIconColor),
                ),
              ),
              SizedBox(width: width * 0.04),
              Expanded(
                child: ColorfulPlankText(text: recipe.name, fontSize: height * 0.22, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
              ),
              Icon(Icons.chevron_right_rounded, size: height * 0.3, color: kPlankIconColor),
            ],
          ),
        ),
      ),
    );
  }
}
