import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/widgets/submenu_kit.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../../../data/services/progression_service.dart';
import '../../game/providers/game_state_provider.dart';
import '../info_level_data.dart';
import 'cocktails_screen.dart';
import 'how_to_play_screen.dart';
import 'ingredients_screen.dart';
import 'songs_screen.dart';

/// The Guide hub — a 2×2 tile grid (Ingredients/Cocktails/Songs/How to
/// Play) listing the reference sub-pages, each with a live subline
/// computed from real save data rather than the handoff's placeholder
/// counts. About is no longer on this screen (design_handoff_main_menu_v3
/// moved it into Settings; Guide's old "About" row from the previous
/// pass goes with it — About is still reachable from Settings).
class InfoScreen extends ConsumerWidget {
  const InfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final board = ref.watch(gameStateProvider);

    int bucketFor(int level) => highestTierBucketForLevel(
      level,
      l1: board.highestTierUnlocked,
      l2: board.highestTierUnlockedLevel2,
      l3: board.highestTierUnlockedLevel3,
      l4: board.highestTierUnlockedLevel4,
      l5: board.highestTierUnlockedLevel5,
    );

    var ingredientsCollected = 0, ingredientsTotal = 0;
    var cocktailsTotal = 0;
    var songsUnlocked = 0;
    for (final level in kInfoLevels) {
      final bucket = bucketFor(level.level);
      ingredientsCollected += (bucket + 1).clamp(0, level.chain.length);
      ingredientsTotal += level.chain.length;
      cocktailsTotal += level.recipes.length;
      if (bucket >= 0) songsUnlocked += level.songs.length;
    }

    return SubmenuScaffold(
      title: tr(locale, 'guide'),
      panelTop: 146,
      ribbonTop: 122,
      child: FutureBuilder<Set<String>>(
        future: loadMixedCocktailIds(),
        builder: (context, snapshot) {
          final mixed = snapshot.data?.length ?? 0;
          return GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              mainAxisExtent: 160,
            ),
            children: [
              _GuideTile(
                iconAsset: findIngredientById('lime').assetPath!,
                label: tr(locale, 'ingredients'),
                subline: tr(locale, 'guide_ingredients_subline')
                    .replaceFirst('{x}', '$ingredientsCollected')
                    .replaceFirst('{y}', '$ingredientsTotal'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IngredientsScreen())),
              ),
              _GuideTile(
                iconAsset: kCocktailRecipes.firstWhere((r) => r.id == 'blue_hawaiian').assetPath,
                label: tr(locale, 'cocktails'),
                subline: tr(locale, 'guide_cocktails_subline')
                    .replaceFirst('{x}', '$mixed')
                    .replaceFirst('{y}', '$cocktailsTotal'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CocktailsScreen())),
              ),
              _GuideTile(
                iconAsset: 'assets/images/icon_songs.png',
                label: tr(locale, 'songs'),
                subline: tr(locale, 'guide_songs_subline').replaceFirst('{x}', '$songsUnlocked'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SongsScreen())),
              ),
              _GuideTile(
                iconAsset: 'assets/images/icon_guide.png',
                label: tr(locale, 'how_to_play'),
                subline: tr(locale, 'how_to_play_subline'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HowToPlayScreen())),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideTile extends StatefulWidget {
  final String iconAsset;
  final String label;
  final String subline;
  final VoidCallback onTap;
  const _GuideTile({required this.iconAsset, required this.label, required this.subline, required this.onTap});

  @override
  State<_GuideTile> createState() => _GuideTileState();
}

class _GuideTileState extends State<_GuideTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  height: 118,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: SubmenuColors.gold, width: 3),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.0, 0.7, 1.0],
                      colors: [Color(0xFF3480BD), Color(0xFF225A8C), Color(0xFF1B4B77)],
                    ),
                    boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 6))],
                  ),
                ),
                Positioned(
                  bottom: 18,
                  child: Image.asset(
                    widget.iconAsset,
                    width: 100,
                    height: 94,
                    fit: BoxFit.contain,
                    // See GlassVisual's matching comment.
                    cacheWidth: (100 * MediaQuery.devicePixelRatioOf(context)).round(),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, 15),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: SubmenuColors.goldEdge, width: 2),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [SubmenuColors.goldTop, SubmenuColors.goldBottom],
                      ),
                    ),
                    child: OutlinedLabel(
                      text: widget.label.toUpperCase(),
                      fontSize: 15,
                      fill: Colors.white,
                      stroke: SubmenuColors.goldEdge,
                      strokeWidth: 3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.subline,
              textAlign: TextAlign.center,
              style: submenuNunito(size: 12, weight: FontWeight.w800, color: SubmenuColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
