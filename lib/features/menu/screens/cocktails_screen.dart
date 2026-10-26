import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/bar_backdrop.dart' show backgroundAssetPathForLevel;
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../../../data/services/progression_service.dart';
import '../../game/providers/game_state_provider.dart';
import '../info_level_data.dart';
import 'cocktail_detail_screen.dart';

/// Every cocktail order in the game, one page per level (see
/// [kInfoLevels]) — same swipe-between-levels pattern as
/// ingredients_screen.dart. Each card is the picture, name and a row of
/// mini ingredient icons — tap an unlocked one for the full recipe.
/// "Unlocked" here means ever mixed (lifetime, see
/// progression_service.dart's loadMixedCocktailIds), not just available
/// — a cocktail stays a silhouette until the player has actually made it
/// at least once.
class CocktailsScreen extends ConsumerStatefulWidget {
  const CocktailsScreen({super.key});

  @override
  ConsumerState<CocktailsScreen> createState() => _CocktailsScreenState();
}

class _CocktailsScreenState extends ConsumerState<CocktailsScreen> {
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

    return SubmenuScaffold(
      title: tr(locale, 'cocktails'),
      ribbonTop: 76,
      panelTop: 100,
      panelBottom: 58,
      backgroundAssetPath: backgroundAssetPathForLevel(kInfoLevels[_levelIndex].level),
      child: FutureBuilder<Set<String>>(
        future: loadMixedCocktailIds(),
        builder: (context, snapshot) {
          final mixedIds = snapshot.data ?? const <String>{};
          return LevelPager(
            itemCount: kInfoLevels.length,
            initialPage: (board.highestLevelReached - 1).clamp(0, kInfoLevels.length - 1),
            levelName: (i) => kInfoLevels[i].name,
            levelReached: (i) => kInfoLevels[i].level <= board.highestLevelReached,
            lockedNoun: tr(locale, 'cocktails').toLowerCase(),
            onPageChanged: (i) => setState(() => _levelIndex = i),
            pageBuilder: (context, i) {
              final level = kInfoLevels[i];
              final mixedInLevel = level.recipes.where((r) => mixedIds.contains(r.id)).length;
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CountRow(label: tr(locale, 'mixed_label'), value: '$mixedInLevel / ${level.recipes.length}'),
                    const SizedBox(height: 2),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: level.recipes.length,
                      // Squeezed from 8/6 spacing and a 116 row height —
                      // 4 rows of 7 recipes plus the CountRow above could
                      // exceed the panel's available height on a shorter
                      // device, forcing a scroll to see the last row.
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 4,
                        mainAxisExtent: 106,
                      ),
                      itemBuilder: (context, index) {
                        final recipe = level.recipes[index];
                        final unlocked = mixedIds.contains(recipe.id);
                        return _CocktailCard(
                          recipe: recipe,
                          unlocked: unlocked,
                          locale: locale,
                          onTap: unlocked
                              ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CocktailDetailScreen(recipe: recipe)))
                              : null,
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CocktailCard extends StatefulWidget {
  final CocktailRecipe recipe;
  final bool unlocked;
  final AppLocale locale;
  final VoidCallback? onTap;
  const _CocktailCard({required this.recipe, required this.unlocked, required this.locale, this.onTap});

  @override
  State<_CocktailCard> createState() => _CocktailCardState();
}

class _CocktailCardState extends State<_CocktailCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final sprite = Image.asset(
      widget.recipe.assetPath,
      width: 51,
      height: 46,
      fit: BoxFit.contain,
      // Source art decodes at full resolution otherwise, just to shrink
      // to this small a card — see GlassVisual's matching comment.
      cacheWidth: (51 * 2.2 * MediaQuery.devicePixelRatioOf(context)).round(),
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.local_bar_rounded, size: 34, color: Colors.white54),
    );
    final card = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SubmenuColors.gold, width: 2),
        gradient: widget.unlocked
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom])
            : null,
        color: widget.unlocked ? null : SubmenuColors.lockedCard,
        boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 48, child: Center(child: widget.unlocked ? sprite : lockedSilhouette(sprite, lockSize: 18))),
          Text(
            widget.unlocked ? widget.recipe.name : '???',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            // Explicit tight line-height — Lilita One's default metrics
            // reserve noticeably more vertical space than its fontSize
            // alone suggests, which blew the squeezed card's budget by
            // 10px (confirmed on-device) despite the arithmetic looking
            // fine on paper.
            style: TextStyle(
              fontFamily: 'Lilita One',
              fontSize: 14,
              height: 1.0,
              color: widget.unlocked ? Colors.white : SubmenuColors.textDisabled,
            ),
          ),
          const SizedBox(height: 2),
          if (widget.unlocked)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final id in widget.recipe.ingredientIds) ...[
                  if (id != widget.recipe.ingredientIds.first) const SizedBox(width: 2),
                  Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: SubmenuColors.lockedCard),
                    child: Center(child: GlassVisual(ingredient: findIngredientById(id), size: 12, applyDisplayScale: false)),
                  ),
                ],
              ],
            )
          else
            Text(
              tr(widget.locale, 'keep_playing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: submenuNunito(size: 11, weight: FontWeight.w800, color: SubmenuColors.textDisabled, height: 1.0),
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
