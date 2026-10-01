import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../info_level_data.dart';

/// Every cocktail order in the game, one page per level (see
/// [kInfoLevels]) — same swipe-between-levels pattern as
/// ingredients_screen.dart. Each row shows the finished drink plus the
/// small icons of exactly what it needs, per feedback that just the
/// name/picture wasn't enough on its own.
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
                _CocktailsLevelPage(level: level, plankWidth: plankWidth, plankHeight: plankHeight, locale: locale),
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
  final double plankWidth;
  final double plankHeight;
  final AppLocale locale;
  const _CocktailsLevelPage({required this.level, required this.plankWidth, required this.plankHeight, required this.locale});

  @override
  Widget build(BuildContext context) {
    // Cocktail rows need more vertical room than a plain ingredient row
    // — the finished-drink picture, name, and a row of needed-ingredient
    // icons all share the one plank.
    final rowHeight = plankHeight * 1.3;
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
                width: plankWidth,
                height: plankHeight,
                assetPath: 'assets/images/menu_board_3.png',
                fontScale: 0.72,
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < level.recipes.length; i++) ...[
                _CocktailRow(recipe: level.recipes[i], width: plankWidth, height: rowHeight),
                if (i < level.recipes.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CocktailRow extends StatelessWidget {
  final CocktailRecipe recipe;
  final double width;
  final double height;
  const _CocktailRow({required this.recipe, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06, vertical: height * 0.08),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(recipe.assetPath, width: height * 0.4, height: height * 0.4, fit: BoxFit.contain),
                ),
                SizedBox(width: width * 0.04),
                Expanded(
                  child: ColorfulPlankText(text: recipe.name, fontSize: height * 0.17, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                ),
              ],
            ),
            SizedBox(height: height * 0.07),
            Row(
              children: [
                for (final id in recipe.ingredientIds)
                  Padding(
                    padding: EdgeInsets.only(right: width * 0.025),
                    child: GlassVisual(ingredient: findIngredientById(id), size: height * 0.28),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
