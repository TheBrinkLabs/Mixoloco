import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../cocktail_instructions.dart';

/// One cocktail's own page — its picture and name up top, the
/// ingredients it needs listed below, and (where we have one — see
/// [kCocktailInstructions]) a brief how-to-make underneath. Reached by
/// tapping its row on [CocktailsScreen].
class CocktailDetailScreen extends ConsumerWidget {
  final CocktailRecipe recipe;
  const CocktailDetailScreen({super.key, required this.recipe});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;
    final instructions = kCocktailInstructions[recipe.id];

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
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(recipe.assetPath, width: plankWidth * 0.5, height: plankWidth * 0.5, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 12),
                    ColorfulPlankText(text: recipe.name, fontSize: plankHeight * 0.3, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                    const SizedBox(height: 18),
                    WoodTitlePlank(
                      title: tr(locale, 'ingredients'),
                      icon: Icons.local_bar_rounded,
                      width: plankWidth,
                      height: plankHeight * 0.85,
                      assetPath: 'assets/images/menu_board_3.png',
                      fontScale: 0.85,
                    ),
                    for (final id in recipe.ingredientIds) _IngredientRow(ingredient: findIngredientById(id), width: plankWidth, height: plankHeight * 0.85),
                    if (instructions != null) ...[
                      const SizedBox(height: 18),
                      WoodTitlePlank(
                        title: tr(locale, 'how_to_make'),
                        icon: Icons.menu_book_rounded,
                        width: plankWidth,
                        height: plankHeight * 0.85,
                        assetPath: 'assets/images/menu_board_3.png',
                        fontScale: 0.85,
                      ),
                      WoodPlank(
                        width: plankWidth,
                        height: plankHeight * 1.7,
                        assetPath: 'assets/images/menu_board_3.png',
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: plankWidth * 0.08),
                          child: Center(
                            child: Text(
                              instructions,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textLight, height: 1.4),
                            ),
                          ),
                        ),
                      ),
                    ],
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
            GlassVisual(ingredient: ingredient, size: height * 0.72),
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
