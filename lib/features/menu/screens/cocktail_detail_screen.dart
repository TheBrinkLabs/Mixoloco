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
import '../cocktail_instructions.dart';

/// cocktail_intructions.png's own aspect — a tall parchment recipe-card
/// photo with a decorative glass sketch in its own top-left corner (see
/// _InstructionsCard), kept as one constant so the compact preview and
/// the full-screen view both size off the same real ratio instead of
/// stretching the art.
const _kInstructionsCardAspect = 848 / 1264;

/// One cocktail's own page — its picture and name up top, the
/// ingredients it needs listed below, and (where we have one — see
/// [kCocktailInstructions]) a brief step-by-step how-to-make on its own
/// recipe-card graphic underneath, tap to view full-screen. Reached by
/// tapping its row on [CocktailsScreen], which also passes through
/// that row's own level backdrop so a Rooftop cocktail's page shows the
/// Rooftop photo, not always the beach one.
class CocktailDetailScreen extends ConsumerWidget {
  final CocktailRecipe recipe;
  final String backgroundAssetPath;
  const CocktailDetailScreen({super.key, required this.recipe, this.backgroundAssetPath = 'assets/images/beach_background.png'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 28.0;
    final plankWidth = screenSize.width - sideMargin * 2;
    final plankHeight = plankWidth / kMenuBoard3Aspect;
    final steps = kCocktailInstructions[recipe.id];

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        backgroundAssetPath: backgroundAssetPath,
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        recipe.assetPath,
                        width: plankWidth * 0.5,
                        height: plankWidth * 0.5,
                        fit: BoxFit.contain,
                        // See cocktails_screen.dart's matching comment —
                        // some Level 3 recipes' art hasn't landed yet.
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.local_bar_rounded, size: plankWidth * 0.3, color: kPlankIconColor),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ColorfulPlankText(text: recipe.name, fontSize: plankHeight * 0.3, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                    const SizedBox(height: 18),
                    WoodTitlePlank(
                      title: tr(locale, 'ingredients'),
                      icon: Icons.local_bar_rounded,
                      iconAsset: 'assets/images/ingredient_cherry.png',
                      width: plankWidth,
                      height: plankHeight * 0.85,
                      assetPath: 'assets/images/menu_board_3.png',
                      fontScale: 0.85,
                    ),
                    for (final id in recipe.ingredientIds) _IngredientRow(ingredient: findIngredientById(id), width: plankWidth, height: plankHeight * 0.85),
                    if (steps != null) ...[
                      const SizedBox(height: 18),
                      _InstructionsCard(
                        steps: steps,
                        width: plankWidth,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _InstructionsFullScreen(recipeName: recipe.name, steps: steps))),
                      ),
                    ],
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

/// The numbered step list laid out on cocktail_intructions.png's own
/// parchment card — dark text (the card is light, unlike every wood
/// plank elsewhere) inset to clear its decorative corner sketch and
/// hand-drawn border. Tappable: opens [_InstructionsFullScreen] for a
/// bigger, easier read.
class _InstructionsCard extends StatelessWidget {
  final List<String> steps;
  final double width;
  final VoidCallback onTap;
  const _InstructionsCard({required this.steps, required this.width, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final height = width / _kInstructionsCardAspect;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/Cocktail_intructions.png', fit: BoxFit.fill),
            Padding(
              padding: EdgeInsets.only(top: height * 0.3, left: width * 0.14, right: width * 0.1, bottom: height * 0.08),
              child: _StepList(steps: steps, fontSize: width * 0.044),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepList extends StatelessWidget {
  final List<String> steps;
  final double fontSize;
  const _StepList({required this.steps, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: fontSize * 0.55),
            child: Text(
              '${i + 1}. ${steps[i]}',
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: Colors.black87, height: 1.3),
            ),
          ),
      ],
    );
  }
}

/// The same recipe card, full-screen and bigger — reached by tapping
/// [_InstructionsCard] on the detail page.
class _InstructionsFullScreen extends StatelessWidget {
  final String recipeName;
  final List<String> steps;
  const _InstructionsFullScreen({required this.recipeName, required this.steps});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    const sideMargin = 20.0;
    final width = screenSize.width - sideMargin * 2;
    final height = width / _kInstructionsCardAspect;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ColorfulPlankText(text: recipeName, fontSize: width * 0.09, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: width,
                      height: height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset('assets/images/Cocktail_intructions.png', fit: BoxFit.fill),
                          Padding(
                            padding: EdgeInsets.only(top: height * 0.3, left: width * 0.14, right: width * 0.1, bottom: height * 0.08),
                            child: _StepList(steps: steps, fontSize: width * 0.058),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(left: 12, top: 10, child: PlankBackButton(onTap: () => Navigator.of(context).pop())),
          ],
        ),
      ),
    );
  }
}
