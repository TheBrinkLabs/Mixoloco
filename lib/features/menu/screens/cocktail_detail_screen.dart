import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/share_service.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/hud_kit.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../cocktail_instructions.dart';
import '../info_level_data.dart';

/// One lifetime-mixed cocktail paired with the level it belongs to —
/// the hero's prev/next arrows step through a flattened list of these
/// across every level, not just the current one.
class _Entry {
  final InfoLevelData level;
  final CocktailRecipe recipe;
  const _Entry(this.level, this.recipe);
}

_Entry _entryForId(String id) {
  for (final level in kInfoLevels) {
    for (final recipe in level.recipes) {
      if (recipe.id == id) return _Entry(level, recipe);
    }
  }
  throw StateError('Unknown recipe id: $id');
}

/// Each cocktail once, under the first level that serves it — After Dark
/// menus reuse some of their day bar's cocktails.
List<_Entry> _mixedEntries(Set<String> mixedIds) {
  final seen = <String>{};
  return [
    for (final level in kInfoLevels)
      for (final recipe in level.recipes)
        if (mixedIds.contains(recipe.id) && seen.add(recipe.id)) _Entry(level, recipe),
  ];
}

/// A cocktail's own page — reached by tapping an unlocked cocktail on
/// [IngredientsScreen]'s "Used In" sheet or [CocktailsScreen]'s grid.
/// The hero up top lets the player step through every cocktail they've
/// ever mixed, in any level, via the prev/next arrows or a swipe — it
/// wraps at the ends rather than stopping at this level's own list, per
/// design_handoff_submenus/README.md's "Screen 5: Cocktail detail".
class CocktailDetailScreen extends ConsumerStatefulWidget {
  final CocktailRecipe recipe;
  const CocktailDetailScreen({super.key, required this.recipe});

  @override
  ConsumerState<CocktailDetailScreen> createState() => _CocktailDetailScreenState();
}

class _CocktailDetailScreenState extends ConsumerState<CocktailDetailScreen> {
  late String _currentId = widget.recipe.id;
  Set<String>? _mixedIds;

  @override
  void initState() {
    super.initState();
    guideMixedCocktailIds().then((ids) {
      if (mounted) setState(() => _mixedIds = ids);
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final mixedIds = _mixedIds;
    var entries = mixedIds != null ? _mixedEntries(mixedIds) : [_entryForId(_currentId)];
    var index = entries.indexWhere((e) => e.recipe.id == _currentId);
    if (index == -1) {
      // The id we opened with isn't (yet) in the lifetime-mixed set —
      // shouldn't normally happen since every entry point only links to
      // an already-mixed cocktail, but falls back to showing just it,
      // arrows disabled, rather than crashing on a bad index.
      entries = [_entryForId(_currentId)];
      index = 0;
    }
    final entry = entries[index];
    final n = entries.length;
    final steps = kCocktailInstructions[entry.recipe.id] ?? const <String>[];

    void goTo(int newIndex) {
      setState(() => _currentId = entries[newIndex % n].recipe.id);
    }

    return SubmenuScaffold(
      title: entry.recipe.name,
      panelTop: 276,
      ribbonTop: 252,
      panelBottom: 86,
      aboveRibbon: [
        Positioned(
          left: 0,
          right: 0,
          top: 82,
          child: _Hero(
            recipe: entry.recipe,
            canNavigate: n > 1,
            onPrev: () => goTo((index - 1 + n) % n),
            onNext: () => goTo((index + 1) % n),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Balances the share icon so the count stays centred.
              const SizedBox(width: 40),
              Expanded(
                child: Text(
                  '${index + 1} of $n · ${entry.level.name}',
                  textAlign: TextAlign.center,
                  style: submenuNunito(size: 12, weight: FontWeight.w900, color: SubmenuColors.textSecondary),
                ),
              ),
              Semantics(
                button: true,
                label: tr(locale, 'share'),
                child: GestureDetector(
                  onTap: () => shareText(tr(locale, 'share_cocktail_text').replaceFirst('{cocktail}', entry.recipe.name)),
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(
                    width: 40,
                    height: 32,
                    child: Icon(Icons.share_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            tr(locale, 'ingredients').toUpperCase(),
            style: const TextStyle(fontFamily: 'Lilita One', fontSize: 12, color: SubmenuColors.gold),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in entry.recipe.ingredientIds) _IngredientChip(ingredient: findIngredientById(id)),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(child: _RecipeCard(locale: locale, steps: steps)),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final CocktailRecipe recipe;
  final bool canNavigate;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _Hero({required this.recipe, required this.canNavigate, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: !canNavigate
          ? null
          : (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -200) {
                onNext();
              } else if (v > 200) {
                onPrev();
              }
            },
      child: SizedBox(
        height: 170,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GoldArrowButton(icon: Icons.chevron_left_rounded, enabled: canNavigate, onTap: onPrev, size: 44),
            const SizedBox(width: 24),
            SizedBox(
              width: 170,
              height: 170,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0xD9FFF4D6), Color(0x73FFDC96), Color(0x00FFDC96)],
                        stops: [0.0, 0.45, 0.70],
                      ),
                    ),
                  ),
                  ShadowedAsset(
                    key: ValueKey(recipe.id),
                    path: recipe.assetPath,
                    width: 150,
                    shadows: const [
                      SpriteShadow(offset: Offset(0, 10), color: Color(0x59000000), blur: 14),
                      SpriteShadow(offset: Offset(-3, 0), color: Colors.white),
                      SpriteShadow(offset: Offset(3, 0), color: Colors.white),
                      SpriteShadow(offset: Offset(0, -3), color: Colors.white),
                      SpriteShadow(offset: Offset(0, 3), color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 24),
            GoldArrowButton(icon: Icons.chevron_right_rounded, enabled: canNavigate, onTap: onNext, size: 44),
          ],
        ),
      ),
    );
  }
}

class _IngredientChip extends StatelessWidget {
  final Ingredient ingredient;
  const _IngredientChip({required this.ingredient});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SubmenuColors.gold, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom],
              ),
              boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 3))],
            ),
            child: GlassVisual(ingredient: ingredient, size: 42, applyDisplayScale: false),
          ),
          const SizedBox(height: 4),
          Text(
            ingredient.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: submenuNunito(size: 11, weight: FontWeight.w900, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// The code-drawn parchment recipe card — replaces the old
/// Cocktail_intructions.png-based card with the redesign's own layout
/// (numbered Caveat steps, dashed dividers), scrolling internally if the
/// step list is too long for the space left under the ingredient chips.
class _RecipeCard extends StatelessWidget {
  final AppLocale locale;
  final List<String> steps;
  const _RecipeCard({required this.locale, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubmenuColors.paperBorder, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.paperTop, SubmenuColors.paperBottom],
        ),
        boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(locale, 'recipe_label').toUpperCase(),
            style: const TextStyle(fontFamily: 'Lilita One', fontSize: 12, color: SubmenuColors.paperLabel),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < steps.length; i++) _StepRow(number: i + 1, text: steps[i], isLast: i == steps.length - 1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int number;
  final String text;
  final bool isLast;
  const _StepRow({required this.number, required this.text, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final stepStyle = GoogleFonts.caveat(fontSize: 22, fontWeight: FontWeight.w600, color: SubmenuColors.paperInk, height: 1.25);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text('$number.', style: GoogleFonts.caveat(fontSize: 22, fontWeight: FontWeight.w600, color: SubmenuColors.paperNumber)),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: stepStyle)),
            ],
          ),
          if (!isLast) ...[
            const SizedBox(height: 8),
            CustomPaint(painter: _DashedLinePainter(), size: const Size(double.infinity, 1)),
          ],
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF785A28).withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashGap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
