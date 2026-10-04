import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/ingredient.dart';
import '../info_level_data.dart';

/// Every ingredient in the evolution chain, one page per level (see
/// [kInfoLevels]) — swipe left/right to move between levels, each shown
/// against that level's own backdrop photo so it reads as "the Beach
/// bar's ingredients" rather than a plain undifferentiated list.
class IngredientsScreen extends ConsumerStatefulWidget {
  const IngredientsScreen({super.key});

  @override
  ConsumerState<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends ConsumerState<IngredientsScreen> {
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
                _IngredientsLevelPage(level: level, plankWidth: plankWidth, plankHeight: plankHeight, locale: locale),
            ],
          ),
          Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
        ],
      ),
    );
  }
}

class _IngredientsLevelPage extends StatelessWidget {
  final InfoLevelData level;
  final double plankWidth;
  final double plankHeight;
  final AppLocale locale;
  const _IngredientsLevelPage({required this.level, required this.plankWidth, required this.plankHeight, required this.locale});

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
                title: '${tr(locale, 'ingredients')} — ${level.name}',
                icon: Icons.local_bar_rounded,
                iconAsset: 'assets/images/ingredient_cherry.png',
                width: plankWidth,
                height: plankHeight,
                assetPath: 'assets/images/menu_board_3.png',
                fontScale: 0.72,
              ),
              for (final ingredient in level.chain) _IngredientRow(ingredient: ingredient, width: plankWidth, height: plankHeight),
            ],
          ),
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final Ingredient ingredient;
  final double width;
  final double height;
  const _IngredientRow({required this.ingredient, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return WoodPlank(
      width: width,
      height: height,
      assetPath: 'assets/images/menu_board_3.png',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.06),
        child: Row(
          children: [
            GlassVisual(ingredient: ingredient, size: height * 0.72, applyDisplayScale: false),
            SizedBox(width: width * 0.04),
            Expanded(
              child: ColorfulPlankText(text: ingredient.label, fontSize: height * 0.22, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
            ),
          ],
        ),
      ),
    );
  }
}
