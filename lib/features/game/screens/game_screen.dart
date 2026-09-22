import 'dart:math' show min;
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/widgets/ad_break_screen.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/continue_fallback_video_screen.dart';
import '../../../core/widgets/game_logo.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../board_geometry.dart';
import '../mixoloco_game.dart';
import '../providers/game_state_provider.dart';
import 'level_up_overlay.dart';

/// cosmopolitan.png/cocktail_shaker.png/alcohol_free.png sit inside a
/// fixed-size square empty_tab.png tile each (see _ActionButton) rather
/// than being sized off their own aspect ratio — they're real photo
/// icons with very different shapes (portrait, near-square, landscape),
/// which a shared aspect-based sizing couldn't handle well. Unlike the
/// wood-sign buttons these replaced, none of this art has any text
/// painted into it, so each button carries its own code-rendered label
/// (and cost, where one applies) inside the tile too.

/// Core gameplay: drag anywhere on the table to aim the staged glass,
/// release to drop it — it falls (see MixolocoGame's gravity) toward the
/// far edge and rolls to rest against whatever's already there. Two
/// touching glasses of the same evolution tier merge into the next tier
/// up; a cocktail order completes when its required ingredients end up
/// touching in one cluster. A pile that reaches the line near the
/// staging edge for two drops running ends the run.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> with WidgetsBindingObserver {
  late final MixolocoGame _game;

  /// PopScope blocks every pop attempt by default — including the Android
  /// edge-swipe-back gesture, which was otherwise firing constantly just
  /// from dragging near the screen edge to aim a throw — and this flips
  /// true only for the split second the explicit home button actually
  /// requests one, so that's the only way off this screen.
  bool _allowPop = false;

  bool _showCocktailMenu = false;
  bool _showingAdPlaceholder = false;
  bool _showingAdBreak = false;
  bool _showingLevelUp = false;

  /// Bumped on every Shake purchase so BarBackdrop's table image can
  /// react with its own visual shake, in step with the physics jostle.
  final ValueNotifier<int> _tableShakeSignal = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No banner while actually playing — see banner_ad_widget.dart.
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.hidden;
    final notifier = ref.read(gameStateProvider.notifier);
    _game = MixolocoGame(
      onMerge: notifier.registerMerge,
      onCocktailComplete: notifier.registerCocktailComplete,
      onGameOver: notifier.registerGameOver,
      onThrowCommitted: notifier.advanceQueue,
      onTierSeen: notifier.registerTierSeen,
      initialItems: ref.read(gameStateProvider).placedItems,
      sfxEnabled: ref.read(audioSettingsProvider).sfxEnabled,
      level: ref.read(gameStateProvider).level,
    );
    // Music now plays through gameplay too (picking up the same playlist
    // position, not restarting) — see MenuScreen.initState for the other
    // side of this and _goHome below for handing it back on the way out.
    // Rooftop tracks once Level 2, same as the background swap below.
    ref.read(audioSettingsProvider.notifier).playGameMusic(rooftop: ref.read(gameStateProvider).level >= 2);
  }

  /// Home isn't the only way a run in progress can end — backgrounding
  /// or fully closing the app (swiping it away, the OS reclaiming it)
  /// never calls dispose() in time to save anything, but Flutter does
  /// reliably deliver `paused` first. Snapshotting here too means "pick
  /// up again tomorrow" actually works instead of only "leave and come
  /// back within the same session". Nothing's ever pushed on top of
  /// GameScreen (the Cocktail Menu is an in-screen overlay, not a
  /// route), so it's always safe to act unconditionally here — unlike
  /// MenuScreen, which can be covered by this very screen and has to
  /// check it's actually the visible route first.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      ref.read(gameStateProvider.notifier).savePlacedItems(_game.capturePlacedItems());
    } else if (state == AppLifecycleState.resumed) {
      // The OS can silently stop background playback without the app
      // ever finding out — re-assert it on resume rather than leaving
      // silence until the player happens to navigate somewhere that
      // calls playGameMusic() again.
      ref.read(audioSettingsProvider.notifier).playGameMusic(rooftop: ref.read(gameStateProvider).level >= 2);
    }
  }

  void _goHome() {
    // Captured here, before teardown starts — not in dispose(), since by
    // then Flame may already have torn down the physics world/bodies
    // this depends on reading (canPop being false the rest of the time
    // means this is also the *only* path off this screen, so there's
    // nowhere else this needs to happen).
    ref.read(gameStateProvider.notifier).savePlacedItems(_game.capturePlacedItems());
    ref.read(audioSettingsProvider.notifier).playMenuMusic();
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _playAgain() {
    _game.clearBoard();
    ref.read(gameStateProvider.notifier).restart();
  }

  void _useCherryBomb() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kCherryBombCost)) {
      _game.cherryBomb();
    }
  }

  void _useShaker() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kShakerCost)) {
      _game.shakeTable();
      _tableShakeSignal.value++;
    }
  }

  void _useMegaShaker() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kMegaShakeCost)) {
      _game.megaShakeTable();
      _tableShakeSignal.value++;
    }
  }

  void _useAlcoholFree() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kAlcoholFreeCost)) {
      _game.clearAlcoholic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ref.read(bannerPositionProvider.notifier).state = BannerPosition.bottom;
    _tableShakeSignal.dispose();
    super.dispose();
  }

  void _watchAdToContinue() {
    setState(() => _showingAdPlaceholder = true);
    adService.showRewardedAd(
      RewardedAdSlot.continueGame,
      onReward: () {
        if (!mounted) return;
        _game.clearAlcoholicAndResume();
        ref.read(gameStateProvider.notifier).continueAfterAd();
        setState(() => _showingAdPlaceholder = false);
      },
      onDismissedWithoutReward: () {
        // Closed before finishing — game stays over, same as declining
        // the offer outright.
        if (!mounted) return;
        ref.read(gameStateProvider.notifier).declineContinue();
        setState(() => _showingAdPlaceholder = false);
      },
      // No real ad available (not configured yet, or no fill) — rather
      // than leaving the offer as a dead end (tap it, nothing visibly
      // happens), fall back to a short video the player can watch
      // instead, same "minimum watch, then continue" shape as a real
      // rewarded ad would have.
      onNotReady: () async {
        if (!mounted) return;
        setState(() => _showingAdPlaceholder = false);
        final watched = await showContinueFallbackVideo(context, ref.read(localeProvider));
        if (!mounted) return;
        if (watched) {
          _game.clearAlcoholicAndResume();
          ref.read(gameStateProvider.notifier).continueAfterAd();
        } else {
          ref.read(gameStateProvider.notifier).declineContinue();
        }
      },
    );
  }

  /// Every [kAdBreakScoreThreshold] points, a short MREC ad break — the
  /// physics world pauses underneath while it's up so nothing keeps
  /// falling/merging out of view, then resumes once dismissed.
  Future<void> _runAdBreak(AppLocale locale) async {
    if (!mounted) return;
    _game.pauseEngine();
    await showAdBreakScreen(context, locale);
    if (!mounted) return;
    ref.read(gameStateProvider.notifier).acknowledgeAdBreak();
    _game.resumeEngine();
    _showingAdBreak = false;
  }

  /// The end-of-level celebration → interstitial sequence (see
  /// level_up_overlay.dart) — same pause/resume treatment as the ad
  /// break, since this also covers the table for several seconds.
  Future<void> _runLevelUp(AppLocale locale) async {
    if (!mounted) return;
    _game.pauseEngine();
    // Both sides of the reset happen now, while the celebration overlay
    // is about to cover the whole screen — by the time it's dismissed,
    // the table's already cleared and reconfigured for Level 2 rather
    // than the player seeing it happen.
    ref.read(gameStateProvider.notifier).enterLevel(2);
    _game.switchToLevel(2);
    ref.read(audioSettingsProvider.notifier).playGameMusic(rooftop: true);
    await showLevelUpOverlay(context, locale);
    if (!mounted) return;
    ref.read(gameStateProvider.notifier).acknowledgeLevelUpCelebration();
    _game.resumeEngine();
    _showingLevelUp = false;
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(gameStateProvider);
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final rooftop = board.level >= 2;
    final geometry = BoardGeometry.of(screenSize, rooftop: rooftop);
    if (!geometry.isValid) return const SizedBox.shrink();

    _game.updateGeometry(geometry);
    _game.syncBoard(board);

    // Level-up takes priority — if both somehow trip on the same frame,
    // the ad break just waits for the next score check once level-up's
    // interstitial has already covered the ad slot for this moment.
    if (board.level == 2 && !board.levelUpCelebrationShown && !_showingLevelUp) {
      _showingLevelUp = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runLevelUp(locale));
    } else if (board.pendingAdBreak && !_showingAdBreak && !_showingLevelUp) {
      _showingAdBreak = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAdBreak(locale));
    }

    final showContinueOffer = board.gameOver && !board.continueOfferUsed && !_showingAdPlaceholder;
    final showGameOver = board.gameOver && board.continueOfferUsed && !_showingAdPlaceholder;
    final blockInput = board.gameOver || _showCocktailMenu || _showingAdPlaceholder || _showingAdBreak || _showingLevelUp;

    final boardRect = headerBoardRect(screenSize);
    final upNudge1pc = screenSize.height * 0.01;
    final upNudge3pc = screenSize.height * 0.03;
    // The five action buttons (Cherry Bomb, Shake, Mega-Shake, Alcohol-
    // Free, Menu, left to right) sit in one row up from the board's
    // bottom edge, each an equal gap from its neighbor. Nudged up from
    // a plain 25%-from-bottom center so the buttons' bottom edges don't
    // hang down toward the board's own bottom edge, then up another 3%
    // of the screen on top of that.
    // 21% up from the board's bottom edge, i.e. 79% down from its top —
    // net nudge is 3% up, then 1% back down per follow-up feedback.
    final iconRowCenterY = boardRect.top + boardRect.height * 0.79 - upNudge3pc + upNudge1pc;
    const statLeftInset = 55.0;
    // Each action button is a fixed-size square empty_tab.png tile —
    // cosmopolitan.png/alcohol_free.png/cocktail_shaker.png are real
    // photo icons with very different aspect ratios (portrait, near-
    // square, landscape respectively), so sizing the tile off any one
    // icon's own aspect (like the wood-sign buttons these replaced
    // could) doesn't work; a fixed square tile sidesteps that entirely
    // and matches the progress-tabs row's own tile language besides.
    // Sized to fit all five left-to-right, spanning the board's full
    // width now that the highest-evolution-unlocked icon that used to
    // sit to their left is gone — that freed-up space is what lets them
    // sit slightly bigger than before.
    const actionTileCount = 5;
    const actionTileGap = 4.0;
    // Its own (smaller) margin rather than reusing statLeftInset — that
    // was leaving real spare room on the board unused on both sides,
    // per feedback that the row (and so its tiles) could still go a
    // little bigger. Same value both sides keeps the row centered.
    const actionRowMargin = 28.0;
    final actionRowLeft = actionRowMargin;
    final actionRowRight = boardRect.width - actionRowMargin;
    final actionTileSize = (actionRowRight - actionRowLeft - actionTileGap * (actionTileCount - 1)) / actionTileCount;
    final statTop = boardRect.top + boardRect.height * 0.29 - 17 - upNudge1pc;

    // The 8-tab progress row — 7 cocktails plus the jug — sits in the
    // sand gap between the header board and the table, small enough
    // that all 8 fit across with a slim gap between each. Margin/gap
    // trimmed down from 16/5 to free up a little extra width for the
    // 20%-bigger tabs below, since 8-across-the-full-screen-width
    // leaves no room for a clean proportional 20% width increase
    // otherwise — height still gets the full 20% on top of that.
    const progressTabMargin = 10.0;
    const progressTabGap = 3.0;
    final progressTabWidth = (screenSize.width - progressTabMargin * 2 - progressTabGap * 7) / 8;
    final progressTabHeight = (progressTabWidth / kEmptyTabAspect) * 1.2;
    // Same gap above the row (to the header board) as between each tab,
    // rather than a bigger one — reads as one consistently-spaced group.
    final progressTabsTop = boardRect.top + boardRect.height + progressTabGap;

    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        body: BarBackdrop(
          backgroundAssetPath: rooftop ? 'assets/images/rooftop_background.png' : 'assets/images/beach_background.png',
          shakeTrigger: _tableShakeSignal,
          rooftop: rooftop,
          child: Stack(
            children: [
              // Logo + status banner — top center. Tapping the logo goes
              // home, replacing the old dedicated button. Positioned
              // (not Align) so it can shift above the natural safe-area
              // top by the 1%-of-screen nudge.
              Positioned(
                left: 0,
                right: 0,
                top: -upNudge1pc,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(onTap: _goHome, child: const GameLogo(height: 60)),
                        const SizedBox(height: 8),
                        _GameStatusBanner(board: board, locale: locale),
                      ],
                    ),
                  ),
                ),
              ),
              // Credits/Score sit directly on the header board's own wood
              // — no chip background — inset enough to clear the board
              // art's own tapered corners, left and right respectively.
              Positioned(
                left: statLeftInset,
                top: statTop,
                child: _BoardStat(label: tr(locale, 'credits'), value: '${board.credits}'),
              ),
              Positioned(
                right: statLeftInset,
                top: statTop,
                child: _BoardStat(label: tr(locale, 'score_label'), value: '${board.score}'),
              ),
              Positioned(
                left: actionRowLeft,
                top: iconRowCenterY - actionTileSize / 2,
                child: _ActionButton(
                  asset: 'assets/images/ingredient_cherry.png',
                  size: actionTileSize,
                  label: tr(locale, 'cherry_bomb_label'),
                  cost: kCherryBombCost,
                  enabled: board.credits >= kCherryBombCost,
                  onTap: _useCherryBomb,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap),
                top: iconRowCenterY - actionTileSize / 2,
                child: _ActionButton(
                  asset: 'assets/images/cocktail_shaker.png',
                  size: actionTileSize,
                  label: tr(locale, 'shake_label'),
                  cost: kShakerCost,
                  enabled: board.credits >= kShakerCost,
                  onTap: _useShaker,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 2,
                top: iconRowCenterY - actionTileSize / 2,
                child: _ActionButton(
                  asset: 'assets/images/cocktail_shaker.png',
                  size: actionTileSize,
                  label: tr(locale, 'mega_shake_label'),
                  cost: kMegaShakeCost,
                  enabled: board.credits >= kMegaShakeCost,
                  onTap: _useMegaShaker,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 3,
                top: iconRowCenterY - actionTileSize / 2,
                child: _ActionButton(
                  asset: 'assets/images/alcohol_free.png',
                  size: actionTileSize,
                  label: tr(locale, 'alcohol_free_label'),
                  cost: kAlcoholFreeCost,
                  enabled: board.credits >= kAlcoholFreeCost,
                  onTap: _useAlcoholFree,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 4,
                top: iconRowCenterY - actionTileSize / 2,
                child: _ActionButton(
                  asset: 'assets/images/cosmopolitan.png',
                  size: actionTileSize,
                  label: tr(locale, 'menu_label'),
                  // Disabled whenever an order (the free starter counts)
                  // is already in progress — buying a different one would
                  // just abandon whatever cluster's been built toward the
                  // current one. registerCocktailComplete already nulls
                  // board.order out the moment one finishes, so this opens
                  // back up exactly when there's something to buy for.
                  enabled: board.order == null,
                  onTap: () => setState(() => _showCocktailMenu = true),
                ),
              ),
              Positioned(
                left: progressTabMargin,
                top: progressTabsTop,
                child: _ProgressTabsRow(
                  board: board,
                  tabWidth: progressTabWidth,
                  tabHeight: progressTabHeight,
                  gap: progressTabGap,
                ),
              ),
              Positioned(
                left: geometry.playAreaRect.left,
                top: geometry.playAreaRect.top,
                width: geometry.playAreaRect.width,
                height: geometry.playAreaRect.height,
                child: IgnorePointer(
                  ignoring: blockInput,
                  child: GameWidget(game: _game),
                ),
              ),
              // The table's own front-face apron, below the playing
              // surface — no separate tray strip anymore, so Next/Order
              // dock directly on that face instead, left and right.
              Positioned(
                left: 16,
                right: 0,
                top: screenSize.height * tableSurfaceNearFraction(screenSize.width, screenSize.height, rooftop: rooftop),
                bottom: 0,
                child: Align(alignment: Alignment.centerLeft, child: _NextCard(next: board.upcoming.first, locale: locale)),
              ),
              Positioned(
                left: 0,
                right: 16,
                top: screenSize.height * tableSurfaceNearFraction(screenSize.width, screenSize.height, rooftop: rooftop),
                bottom: 0,
                child: Align(alignment: Alignment.centerRight, child: _OrderCard(board: board)),
              ),
              if (showContinueOffer)
                _ContinueOfferOverlay(
                  onWatchAd: _watchAdToContinue,
                  onEndGame: () => ref.read(gameStateProvider.notifier).declineContinue(),
                  locale: locale,
                ),
              if (showGameOver) _GameOverOverlay(board: board, onHome: _goHome, onPlayAgain: _playAgain, locale: locale),
              if (_showingAdPlaceholder) _AdPlaceholderOverlay(locale: locale),
              if (_showCocktailMenu) _CocktailMenuOverlay(onClose: () => setState(() => _showCocktailMenu = false)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label + value pair sitting directly on the header board's own wood
/// grain — no chip/tile behind it, just a text shadow for legibility
/// against the busy texture (same technique the home-screen menu tiles
/// use over the beach photo).
class _BoardStat extends StatelessWidget {
  final String label;
  final String value;
  const _BoardStat({required this.label, required this.value});

  static const _shadow = [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1))];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w800, shadows: _shadow),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 18, color: AppColors.textLight, fontWeight: FontWeight.w800, shadows: _shadow),
        ),
      ],
    );
  }
}

/// One of the three action buttons (Menu/Shake/Alcohol-Free) — a square
/// empty_tab.png tile (the same wood-block art the progress-tabs row and
/// home-screen HUD row use), with the icon (cosmopolitan.png/
/// alcohol_free.png/cocktail_shaker.png — plain photo icons, no text
/// baked in like the wood-sign buttons these replaced) plus a label
/// (and cost, for the two that spend credits) laid out inside it.
/// Everything's fit to the tile's own fixed [size]: the icon gets a
/// fixed share of the height, and the label/cost each get their own
/// fixed-height slot (the cost slot stays reserved-but-empty on the
/// Menu tile, which has none) — every tile's text renders at the same
/// size this way, rather than a tile with only one line of text (Menu)
/// getting stretched bigger by a FittedBox filling the same space a
/// two-line tile's text fills.
class _ActionButton extends StatelessWidget {
  final String asset;
  final double size;
  final String label;
  final int? cost;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.asset,
    required this.size,
    required this.label,
    this.cost,
    required this.enabled,
    required this.onTap,
  });

  static const _textShadow = [Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1))];

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.14);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.45,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // Dialed back 60% (alpha/blur/offset all scaled together)
            // per feedback that it read too heavy.
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 2, offset: const Offset(0.6, 1))],
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset('assets/images/empty_tab.png', fit: BoxFit.fill),
                  Padding(
                    // Extra top padding (vs. a plain symmetric inset) —
                    // the icon sat right at the tile's own top edge
                    // otherwise, reading as if it were falling off; this
                    // nudges the whole icon+text block down a little,
                    // taken from the bottom inset instead so the total
                    // content block stays the same height.
                    padding: EdgeInsets.fromLTRB(size * 0.08, size * 0.13, size * 0.08, size * 0.03),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: size * 0.4, child: Image.asset(asset, fit: BoxFit.contain)),
                        SizedBox(
                          height: size * 0.2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textLight, shadows: _textShadow),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: size * 0.18,
                          child: cost == null
                              ? null
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    '$cost',
                                    maxLines: 1,
                                    // White (not the gold used elsewhere
                                    // for costs) — the gold read too
                                    // close to the wood tile's own color
                                    // to stay legible at this size.
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textLight, shadows: _textShadow),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final BoardState board;
  const _OrderCard({required this.board});

  @override
  Widget build(BuildContext context) {
    final order = board.order;
    if (order == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      constraints: const BoxConstraints(minWidth: 120),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            order.name,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textLight),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in order.ingredientIds)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _OrderIcon(ingredient: findIngredientById(id)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The 8-tab run-progress row — one tab per cocktail recipe plus a final
/// one for the current level's capstone ingredient (Jug on Level 1,
/// Champagne on Level 2), each ticked off the first time it's completed/
/// reached. Reaching all 8 is what levels the run up (see
/// GameStateNotifier._checkLevelUp) into the rooftop bar; on Level 2
/// itself these track that chain's own recipes/Champagne instead (both
/// reset by GameStateNotifier.enterLevel — a fresh set to chase on the
/// new chain, not a continuation of Level 1's).
class _ProgressTabsRow extends StatelessWidget {
  final BoardState board;
  final double tabWidth;
  final double tabHeight;
  final double gap;
  const _ProgressTabsRow({required this.board, required this.tabWidth, required this.tabHeight, required this.gap});

  @override
  Widget build(BuildContext context) {
    final recipes = board.level >= 2 ? kCocktailRecipesLevel2 : kCocktailRecipes;
    final capstone = board.level >= 2 ? kEvolutionChainLevel2.last : kEvolutionChain.last;
    return Row(
      children: [
        for (var i = 0; i < recipes.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          _ProgressTab(
            imagePath: recipes[i].assetPath,
            completed: board.completedCocktailIds.contains(recipes[i].id),
            width: tabWidth,
            height: tabHeight,
          ),
        ],
        SizedBox(width: gap),
        _ProgressTab(
          imagePath: capstone.assetPath!,
          completed: board.jugReached,
          width: tabWidth,
          height: tabHeight,
        ),
      ],
    );
  }
}

class _ProgressTab extends StatelessWidget {
  final String imagePath;
  final bool completed;
  final double width;
  final double height;
  const _ProgressTab({required this.imagePath, required this.completed, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          Image.asset('assets/images/empty_tab.png', fit: BoxFit.fill),
          Padding(
            // Fully visible while it's still something to aim for; fades
            // back once it's done and the checkmark takes over as the
            // main thing to notice. Scaled up from its inset box (rather
            // than just shrinking the inset) since shrinking alone caps
            // out short of the desired size before the picture would
            // fill the whole tab — the small overflow this leaves lands
            // safely inside the gap between tabs. 1.5x dialed back 25%
            // (-> 1.125x) per feedback that the pictures read too big.
            padding: EdgeInsets.all(width * 0.15),
            child: Opacity(
              opacity: completed ? 0.4 : 1.0,
              child: Transform.scale(scale: 1.125, child: Image.asset(imagePath, fit: BoxFit.contain)),
            ),
          ),
          if (completed)
            Center(
              child: Opacity(
                opacity: 0.62,
                child: Icon(Icons.check_rounded, size: min(width, height) * 0.85, color: AppColors.mint),
              ),
            ),
        ],
      ),
    );
  }
}

/// Only surfaces for events worth calling out — no standing instructional
/// text, which just duplicated the order card above it.
class _GameStatusBanner extends StatelessWidget {
  final BoardState board;
  final AppLocale locale;
  const _GameStatusBanner({required this.board, required this.locale});

  String? get _message => board.gameOver ? tr(locale, 'table_full_banner') : null;

  @override
  Widget build(BuildContext context) {
    final message = _message;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: message == null
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey<String>(message),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.coral.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.coral.withValues(alpha: 0.6)),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
    );
  }
}

class _OrderIcon extends StatelessWidget {
  final Ingredient ingredient;
  const _OrderIcon({required this.ingredient});

  @override
  Widget build(BuildContext context) => GlassVisual(ingredient: ingredient, size: 32);
}

/// Just the single next ingredient — the table's front face is a narrow
/// band, not a full tray anymore, so this reads as a quick glance rather
/// than a queue.
class _NextCard extends StatelessWidget {
  final Ingredient next;
  final AppLocale locale;
  const _NextCard({required this.next, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              tr(locale, 'next'),
              style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.8),
            ),
          ),
          GlassVisual(ingredient: next, size: 44),
        ],
      ),
    );
  }
}

/// Shown once per game, the moment the table would otherwise end the
/// run — a standard "watch an ad to continue" offer, per the Cocktail
/// Menu/Shaker Maker's economy: only offered once, so it can't be farmed
/// as an infinite continue.
class _ContinueOfferOverlay extends StatelessWidget {
  final VoidCallback onWatchAd;
  final VoidCallback onEndGame;
  final AppLocale locale;
  const _ContinueOfferOverlay({required this.onWatchAd, required this.onEndGame, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(locale, 'table_full_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 8),
                Text(
                  tr(locale, 'table_full_body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: AppColors.textMuted),
                ),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: onWatchAd,
                  child: Container(
                    width: 230,
                    height: 50,
                    decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(16)),
                    child: Center(
                      child: Text(tr(locale, 'watch_ad_clear'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onEndGame,
                  child: Container(
                    width: 230,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Center(
                      child: Text(tr(locale, 'end_game'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Covers the table while the real rewarded ad (LevelPlay) is loading
/// and playing — the SDK's own full-screen ad view sits on top of
/// everything natively once it actually displays; this is just the
/// brief loading/request window before that happens.
class _AdPlaceholderOverlay extends StatelessWidget {
  final AppLocale locale;
  const _AdPlaceholderOverlay({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.sunsetGold),
              const SizedBox(height: 16),
              Text(tr(locale, 'ad_playing'), style: const TextStyle(color: AppColors.textLight, fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Cocktail Menu purchase overlay — used to be a single
/// Menu_List.png sign with prices/names baked into the art itself and
/// invisible tap rows positioned over it, so every recipe or price
/// change needed matching new art. Now each row renders its own
/// name/price as plain text over a menu_board.png plank (the same asset
/// the home screen's menu options use), so this stays correct on its own
/// whenever kCocktailRecipes changes, with no art dependency. The whole
/// width of each row is the tap target rather than a small button:
/// bigger, more forgiving touch targets. State is shown with a color
/// treatment instead of a separate label — a mint outline + "ACTIVE" tag
/// for the current order, a dark dimming overlay for anything not
/// affordable yet.
class _CocktailMenuOverlay extends ConsumerWidget {
  final VoidCallback onClose;
  const _CocktailMenuOverlay({required this.onClose});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(gameStateProvider);
    final locale = ref.watch(localeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = screenSize.width * 0.88 > 420 ? 420.0 : screenSize.width * 0.88;
    final rowWidth = panelWidth - 24;
    final rowHeight = rowWidth / kMenuBoardAspect;

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: Container(
          color: Colors.black.withValues(alpha: 0.75),
          child: Center(
            child: GestureDetector(
              // Swallow taps on the panel itself so they don't bubble up
              // to the backdrop's onClose above.
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: Container(
                width: panelWidth,
                constraints: BoxConstraints(maxHeight: screenSize.height * 0.82),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                // clipBehavior: Clip.none so the close button (positioned
                // just inside the padded corner, not outside it — see the
                // earlier bug where a button placed outside a sized box's
                // bounds could render but never actually receive taps)
                // still has room without the plank stack clipping it.
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    SingleChildScrollView(
                      // No gaps between planks at all — one continuous
                      // run of boards, title included, rather than
                      // separate floating tiles.
                      child: Column(
                        children: [
                          WoodTitlePlank(title: tr(locale, 'cocktail_menu'), icon: Icons.local_florist_rounded, width: rowWidth, height: rowHeight),
                          for (final recipe in board.level >= 2 ? kCocktailRecipesLevel2 : kCocktailRecipes)
                            _MenuListRow(
                              recipe: recipe,
                              width: rowWidth,
                              height: rowHeight,
                              affordable: board.credits >= recipe.price,
                              isActive: board.order?.id == recipe.id,
                              madeBefore: board.completedCocktailIds.contains(recipe.id),
                              locale: locale,
                              onBuy: () {
                                final bought = ref.read(gameStateProvider.notifier).buyCocktail(recipe);
                                if (bought) onClose();
                              },
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: onClose,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6)],
                          ),
                          child: const Icon(Icons.close_rounded, color: AppColors.textLight, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _MenuListRow extends StatelessWidget {
  final CocktailRecipe recipe;
  final double width;
  final double height;
  final bool affordable;
  final bool isActive;
  final bool madeBefore;
  final AppLocale locale;
  final VoidCallback onBuy;
  const _MenuListRow({
    required this.recipe,
    required this.width,
    required this.height,
    required this.affordable,
    required this.isActive,
    required this.madeBefore,
    required this.locale,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final canBuy = affordable && !isActive;
    return GestureDetector(
      onTap: canBuy ? onBuy : null,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: affordable || isActive ? 1.0 : 0.55,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/images/menu_board.png', fit: BoxFit.fill),
              if (isActive)
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.mint, width: 3),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.asset(recipe.assetPath, width: height * 0.7, height: height * 0.7, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: ColorfulPlankText(
                              text: recipe.name,
                              fontSize: 15,
                              variant: kPlankTextVariant,
                              font: kPlankTextFont,
                              shadowStyle: kPlankShadowStyle,
                            ),
                          ),
                          // This cocktail has been made at least once, but
                          // (unlike the progress tabs) it stays fully
                          // buyable — a quiet tick beside the name rather
                          // than anything that dims/covers the row.
                          if (madeBefore) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: AppColors.mint, shape: BoxShape.circle),
                              child: const Icon(Icons.check_rounded, size: 12, color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isActive)
                      Text(
                        tr(locale, 'active'),
                        style: GoogleFonts.luckiestGuy(
                          fontSize: 12,
                          color: AppColors.mint,
                          shadows: const [Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0.6, 1))],
                        ),
                      )
                    else
                      ColorfulPlankText(
                        text: '${recipe.price}',
                        fontSize: 15,
                        variant: PlankTextVariant.plainWhite,
                        font: kPlankTextFont,
                        shadowStyle: kPlankShadowStyle,
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

class _GameOverOverlay extends StatelessWidget {
  final BoardState board;
  final VoidCallback onHome;
  final VoidCallback onPlayAgain;
  final AppLocale locale;
  const _GameOverOverlay({required this.board, required this.onHome, required this.onPlayAgain, required this.locale});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr(locale, 'game_over'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                const SizedBox(height: 6),
                Text('${tr(locale, 'score_label')}: ${board.score}', style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                Text('${tr(locale, 'cocktails_made_label')}: ${board.cocktailsMade}', style: const TextStyle(fontSize: 16, color: AppColors.textMuted)),
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: onPlayAgain,
                  child: Container(
                    width: 200,
                    height: 50,
                    decoration: BoxDecoration(gradient: AppColors.gradientSunset, borderRadius: BorderRadius.circular(16)),
                    child: Center(
                      child: Text(tr(locale, 'play_again'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onHome,
                  child: Container(
                    width: 200,
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: Center(
                      child: Text(tr(locale, 'home'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textLight)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
