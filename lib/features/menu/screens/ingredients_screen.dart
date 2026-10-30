import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/bar_backdrop.dart' show backgroundAssetPathForLevel;
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../../game/providers/game_state_provider.dart';
import '../info_level_data.dart';
import 'cocktail_detail_screen.dart';

/// Every ingredient in the evolution chain, one page per level (see
/// [kInfoLevels]) — swipe or use the arrows to move between levels.
class IngredientsScreen extends ConsumerStatefulWidget {
  const IngredientsScreen({super.key});

  @override
  ConsumerState<IngredientsScreen> createState() => _IngredientsScreenState();
}

class _IngredientsScreenState extends ConsumerState<IngredientsScreen> {
  late int _levelIndex;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);
    if (!_initialized) {
      _levelIndex = (board.highestLevelReached - 1).clamp(0, kInfoLevels.length - 1);
      _initialized = true;
    }

    int bucketFor(int level) => guideTierFor(board.highestTiers, level);

    return SubmenuScaffold(
      title: tr(locale, 'ingredients'),
      ribbonTop: 84,
      panelTop: 108,
      panelBottom: 64,
      backgroundAssetPath: backgroundAssetPathForLevel(kInfoLevels[_levelIndex].level),
      night: isAfterDarkLevel(kInfoLevels[_levelIndex].level),
      child: LevelPager(
        itemCount: kInfoLevels.length,
        initialPage: (board.highestLevelReached - 1).clamp(0, kInfoLevels.length - 1),
        levelName: (i) => kInfoLevels[i].name,
        levelReached: (i) => guideLevelReached(kInfoLevels[i].level, board.highestLevelReached),
        lockedNoun: tr(locale, 'ingredients').toLowerCase(),
        onPageChanged: (i) => setState(() => _levelIndex = i),
        pageBuilder: (context, i) {
          final level = kInfoLevels[i];
          final bucket = bucketFor(level.level);
          final collected = (bucket + 1).clamp(0, level.chain.length);
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CountRow(label: tr(locale, 'collected_label'), value: '$collected / ${level.chain.length}'),
                const SizedBox(height: 2),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: level.chain.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    mainAxisExtent: 86,
                  ),
                  itemBuilder: (context, index) {
                    final ingredient = level.chain[index];
                    final unlocked = index <= bucket;
                    return _IngredientCard(
                      ingredient: ingredient,
                      levelName: level.name,
                      unlocked: unlocked,
                      onTap: unlocked
                          ? () => _openSheet(context, locale, ingredient, level.name)
                          : null,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openSheet(BuildContext context, AppLocale locale, Ingredient ingredient, String levelName) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _IngredientSheet(ingredient: ingredient, levelName: levelName, locale: locale),
    );
  }
}

class _IngredientCard extends StatefulWidget {
  final Ingredient ingredient;
  final String levelName;
  final bool unlocked;
  final VoidCallback? onTap;
  const _IngredientCard({required this.ingredient, required this.levelName, required this.unlocked, this.onTap});

  @override
  State<_IngredientCard> createState() => _IngredientCardState();
}

class _IngredientCardState extends State<_IngredientCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sprite = GlassVisual(ingredient: widget.ingredient, size: 40, applyDisplayScale: false);
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.unlocked ? SubmenuColors.gold : SubmenuColors.lockedCardBorder, width: 2),
        gradient: widget.unlocked
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom])
            : null,
        color: widget.unlocked ? null : SubmenuColors.lockedCard,
        boxShadow: widget.unlocked ? [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 3))] : null,
      ),
      padding: const EdgeInsets.fromLTRB(3, 5, 3, 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(child: Center(child: widget.unlocked ? sprite : lockedSilhouette(sprite, lockSize: 22))),
          Text(
            widget.unlocked ? widget.ingredient.label : '???',
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(
              fontFamily: 'Lilita One',
              fontSize: 12,
              color: widget.unlocked ? Colors.white : SubmenuColors.textDisabled,
            ),
          ),
        ],
      ),
    );
    if (widget.onTap == null) return card;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _pressed ? 0.95 : 1.0, duration: const Duration(milliseconds: 100), child: card),
    );
  }
}

class _IngredientSheet extends StatelessWidget {
  final Ingredient ingredient;
  final String levelName;
  final AppLocale locale;
  const _IngredientSheet({required this.ingredient, required this.levelName, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 74),
      child: FutureBuilder<Set<String>>(
        future: guideMixedCocktailIds(),
        builder: (context, snapshot) {
          final mixedIds = snapshot.data ?? const <String>{};
          // Deduped by id — After Dark menus reuse some day cocktails.
          final seen = <String>{};
          final usedIn = [
            ...kInfoLevels.expand((l) => l.recipes),
          ].where((r) => r.ingredientIds.contains(ingredient.id) && mixedIds.contains(r.id) && seen.add(r.id)).take(3).toList();

          return Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: SubmenuColors.gold, width: 3),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2364A0), SubmenuColors.panelBottom],
              ),
              boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 8))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: SubmenuColors.gold, width: 2),
                        gradient: const RadialGradient(colors: [Color(0xFF3D8FD0), Color(0xFF1A4670)]),
                      ),
                      child: GlassVisual(ingredient: ingredient, size: 56, applyDisplayScale: false),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          OutlinedLabel(text: ingredient.label, fontSize: 26, fill: Colors.white, stroke: SubmenuColors.ring, strokeWidth: 4, textAlign: TextAlign.left),
                          const SizedBox(height: 4),
                          Text(
                            tr(locale, 'level_ingredient').replaceFirst('{level}', levelName),
                            style: submenuNunito(size: 13, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SubmenuColors.red,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [BoxShadow(color: SubmenuColors.redEdge, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
                if (usedIn.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    tr(locale, 'used_in').toUpperCase(),
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 13, color: SubmenuColors.gold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final recipe in usedIn) ...[
                        if (recipe != usedIn.first) const SizedBox(width: 10),
                        Expanded(child: _UsedInCard(recipe: recipe, onTap: () => _openDetail(context, recipe))),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _openDetail(BuildContext context, CocktailRecipe recipe) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CocktailDetailScreen(recipe: recipe)));
  }
}

class _UsedInCard extends StatelessWidget {
  final CocktailRecipe recipe;
  final VoidCallback onTap;
  const _UsedInCard({required this.recipe, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: SubmenuColors.lockedCard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              recipe.assetPath,
              width: 52,
              height: 52,
              fit: BoxFit.contain,
              // See GlassVisual's matching comment.
              cacheWidth: (52 * 2.2 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
            const SizedBox(height: 6),
            Text(
              recipe.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: submenuNunito(size: 11, weight: FontWeight.w900, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
