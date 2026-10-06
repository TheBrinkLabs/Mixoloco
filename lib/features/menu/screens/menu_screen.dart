import 'dart:math' as math;
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/colorful_plank_text.dart';
import '../../../core/utils/progress_sync.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/notification_tablet.dart';
import '../../../core/widgets/game_logo.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/wood_plank.dart';
import '../../../data/models/ingredient.dart';
import '../../../data/repositories/league_repository.dart';
import '../../game/providers/game_state_provider.dart';
import '../../game/screens/game_screen.dart';
import '../../league/providers/league_provider.dart';
import '../../league/screens/league_screen.dart';
import '../../onboarding/screens/nickname_setup_screen.dart';
import '../../shop/screens/shop_screen.dart';
import '../components/falling_ingredients_game.dart';
import 'high_scores_screen.dart';
import 'info_screen.dart';
import 'settings_screen.dart';

/// beach_sign.png, cropped tight to its own opaque content — a two-post
/// sign (crossbar plank + legs planted in the sand), replacing the flat
/// header_board.png just on this screen. Unlike that plank, the logo
/// can't just center in the whole image: the crossbar itself only
/// occupies the upper band of the picture (legs hang below it), so
/// [kBeachSignPlankTopFraction]/[kBeachSignPlankBottomFraction] (found
/// by scanning the art for where its opaque width jumps from "two
/// separate posts" to "one solid beam" and back) mark where that band
/// actually is.
const kBeachSignAspect = 1169 / 739;
const kBeachSignPlankTopFraction = 0.135;
const kBeachSignPlankBottomFraction = 0.521;

/// One leg's long cast shadow — a soft, fading streak pivoting at the
/// leg's own foot (see call sites in [MenuScreen.build] for the measured
/// fractions), leaning down-and-right away from the sun. [footFraction]
/// is the foot's position as an (x, y) fraction of (signWidth,
/// signHeight); [legWidthFraction] sets the streak's thickness relative
/// to signWidth, matching the real leg's own width.
Widget _legShadow({required Offset footFraction, required double legWidthFraction, required double signWidth, required double signHeight}) {
  final thickness = signWidth * legWidthFraction;
  final length = thickness * 5.5;
  return Positioned(
    left: signWidth * footFraction.dx,
    top: signHeight * footFraction.dy - thickness / 2,
    child: Transform.rotate(
      angle: 24 * math.pi / 180,
      alignment: Alignment.centerLeft,
      child: Container(
        width: length,
        height: thickness,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(thickness / 2),
          gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Colors.black.withValues(alpha: 0.45), Colors.black.withValues(alpha: 0.0)]),
        ),
      ),
    ),
  );
}

/// Gap between each stacked menu-option board — 0 so they sit flush,
/// touching edge to edge, reading as one continuous pile mounted on the
/// post behind them.
const kBoardGap = 0.0;

/// Start screen — bar/level select eventually lives here (dodgy bar ->
/// fancier bars as tiers unlock). For now it's the logo up top and five
/// stacked wooden-plank menu options below (no bare table — that's
/// reserved for actual gameplay).
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with WidgetsBindingObserver {
  // Created once and kept for the screen's whole lifetime rather than
  // inline in build() — build() reruns on every credits/score change
  // (this screen watches gameStateProvider), and a fresh
  // FallingIngredientsGame instance there would restart the whole
  // physics simulation — and the pile it's built up — from scratch on
  // every single one of those.
  final _fallingGame = FallingIngredientsGame();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Fires once per push onto the navigator stack — GameScreen stops
    // this on its own initState and MenuScreen isn't rebuilt (just
    // covered) while a pushed screen sits on top, so this doesn't
    // re-trigger just from returning here via _goHome; see GameScreen.
    ref.read(audioSettingsProvider.notifier).playMenuMusic();
    _maybeSyncProgress();
  }

  /// Pulls down this player's Google-account progress backup (if any) and
  /// merges it into local state on every launch — see progress_sync.dart.
  /// Only meaningful once actually linked (an unlinked anonymous player
  /// has nothing to restore and nowhere to push that would ever come
  /// back), and only worth doing once per app launch, not every time this
  /// screen re-mounts — same "fires once per push" reasoning as the
  /// menu-music call above, since MenuScreen is only ever pushed once.
  Future<void> _maybeSyncProgress() async {
    if (!authService.isLinkedToGoogle) return;
    final uid = authService.uid;
    if (uid == null) return;
    final changed = await syncProgress(ref.read(leagueRepositoryProvider), uid);
    if (changed && mounted) {
      await ref.read(gameStateProvider.notifier).refreshLifetimeFieldsFromDisk();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Unlike GameScreen (nothing's ever pushed on top of it), MenuScreen
  /// stays mounted-but-covered under Settings/Best Scores/GameScreen, so
  /// every one of those routes' resumes would ALSO fire this observer —
  /// only re-assert menu music if Menu itself is actually the visible
  /// route right now, otherwise this would stomp on whatever music
  /// context (game music, say, possibly with game music specifically
  /// turned off) the actually-visible screen already re-asserted. The
  /// falling-ingredients background is paused/resumed the same way, for
  /// the same reason — backgrounding the whole app (home button, lock
  /// screen, another app) shouldn't leave it quietly falling/spawning
  /// somewhere nobody's watching, but it also shouldn't resume here on
  /// an app-resume that's actually landing on a pushed screen instead.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (state == AppLifecycleState.resumed && isCurrent) {
      ref.read(audioSettingsProvider.notifier).playMenuMusic();
      _fallingGame.resumeFalling();
    } else if (state == AppLifecycleState.paused) {
      _fallingGame.pauseFalling();
    }
  }

  /// Pauses the falling-ingredients background before pushing [route],
  /// resuming it once that route's popped and this screen is genuinely
  /// visible again — shared by every push this screen makes (Settings,
  /// Best Scores, the game itself).
  Future<void> _pushAndPauseFalling(Route<void> route) async {
    _fallingGame.pauseFalling();
    await Navigator.of(context).push(route);
    if (mounted) _fallingGame.resumeFalling();
  }

  void _openSettings() {
    _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  /// League profile setup is one-time and lazy — only ever prompted the
  /// first time a player actually taps Leaderboard, rather than as part
  /// of any app-launch flow (Mixoloco has no first-launch onboarding
  /// carousel to hook it into the way Capitle's own profile setup does).
  Future<void> _openLeaderboard() async {
    final hasNickname = await ref.read(leagueControllerProvider.notifier).hasLocalNickname();
    if (!mounted) return;
    _pushAndPauseFalling(MaterialPageRoute(
      builder: (_) => hasNickname ? const LeagueScreen() : const NicknameSetupScreen(),
    ));
  }

  /// A game left via Home mid-run should be resumable as-is (that's the
  /// whole point of placedItems persistence) — offers Continue/New Game
  /// whenever there's actually something in progress to continue
  /// (non-zero score or a non-empty table, and not already game-over —
  /// a genuinely fresh/never-played state has nothing worth offering
  /// Continue for, so that case skips straight to New Game). Choosing
  /// New Game past Level 1 offers a level picker, defaulting to the
  /// highest the player's ever reached — see startNewGameAtLevel.
  Future<void> _playGame() async {
    final board = ref.read(gameStateProvider);
    final inProgress = !board.gameOver && (board.score > 0 || board.placedItems.isNotEmpty);
    if (!inProgress) {
      await _startNewGame();
      return;
    }
    final locale = ref.read(localeProvider);
    final choice = await showDialog<_PlayChoice>(context: context, builder: (_) => _PlayChoiceDialog(locale: locale));
    if (!mounted || choice == null) return;
    if (choice == _PlayChoice.continueGame) {
      _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const GameScreen()));
    } else {
      // A real run was actually in progress (that's how we got here —
      // see the inProgress check above), so New Game means throwing it
      // away — confirm before doing that, same as Settings' own Reset
      // Progress confirm.
      final confirmed = await showDialog<bool>(context: context, builder: (_) => _LoseProgressDialog(locale: locale));
      if (!mounted || confirmed != true) return;
      await _startNewGame();
    }
  }

  Future<void> _startNewGame() async {
    final board = ref.read(gameStateProvider);
    var level = board.highestLevelReached;
    if (board.highestLevelReached >= 2) {
      final locale = ref.read(localeProvider);
      final chosen = await showDialog<int>(
        context: context,
        builder: (_) => _LevelPickerDialog(locale: locale, maxLevel: board.highestLevelReached, initialLevel: board.highestLevelReached),
      );
      if (!mounted || chosen == null) return; // cancelled — stay on the menu
      level = chosen;
    }
    ref.read(gameStateProvider.notifier).startNewGameAtLevel(level);
    if (!mounted) return;
    _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final board = ref.watch(gameStateProvider);
    final locale = ref.watch(localeProvider);

    const sideMargin = 28.0;
    final maxPlankWidth = screenSize.width - sideMargin * 2;
    // menu_board_white.png's own aspect (975/328) is noticeably more
    // letterboxed than kMenuBoard3Aspect's (1045/281) — deriving height
    // from the full screen width the same way as before made each board
    // (and so the whole 5-board stack) run taller than the screen,
    // pushing Settings behind the HUD row. Deriving width FROM the same
    // height budget the stack has always used instead keeps its total
    // height exactly what it's always been; these boards just end up
    // narrower (centered) rather than stretched to some new height.
    // Squeezed 10% smaller than the budget below would otherwise give —
    // per feedback that adding a sixth option tile (Info) alongside the
    // existing five left the stack running too tall/crowded otherwise.
    final plankHeight = maxPlankWidth / kMenuBoard3Aspect * 0.9;
    // A deliberate stretch past the board's own true aspect (not just
    // scaled up — height stays exactly what the budget above gives it):
    // 5% per feedback that labels were wrapping more than they should,
    // then a further 15% on top of that per later feedback asking for
    // more room still — gives every tile's text more room before
    // ColorfulPlankText's own Wrap has to drop to a second line. Still
    // comfortably under maxPlankWidth (~91% of it), so this doesn't
    // overflow the screen's own side margins.
    final plankWidth = plankHeight * kMenuBoardWhiteAspect * 1.05 * 1.15;
    // Seven boards now — the six menu options (five original plus Info)
    // plus one more underneath Settings that just hosts the Credits/
    // Level/Unlocked row (see hudTabWidth/Height below) instead of
    // floating separately on the sand below the whole pile.
    final boardsColumnHeight = plankHeight * 7 + kBoardGap * 6;

    // Sized to fit ON that sixth board (with its own bit of padding)
    // rather than the old floating row's screen-width-derived size —
    // shrunk down a good deal from that, per direct feedback, now that
    // they're riding along on a board of their own instead of standing
    // alone.
    final hudBoardPadding = plankWidth * 0.045;
    const hudTabGap = 8.0;
    final hudTabWidthRaw = (plankWidth - hudBoardPadding * 2 - hudTabGap * 2) / 3;
    final hudTabHeightCap = plankHeight * 0.82;
    final hudTabHeight = hudTabWidthRaw > hudTabHeightCap ? hudTabHeightCap : hudTabWidthRaw;
    final hudTabWidth = hudTabHeight;

    // The beach_sign replacement for the header board — a two-post sign
    // with the crossbar plank only in its own upper band (see
    // kBeachSignPlankTopFraction/BottomFraction), legs hanging below.
    // Both the sign and the logo sitting on it are sized 15% larger than
    // their original fit (0.86 -> ~0.99 of screen width, 120 -> 138 logo
    // cap) per direct feedback that they read too small/cramped.
    final signWidth = screenSize.width * 0.86 * 1.15;
    final signHeight = signWidth / kBeachSignAspect;
    final plankTop = signHeight * kBeachSignPlankTopFraction;
    final plankBottom = signHeight * kBeachSignPlankBottomFraction;
    final plankBandHeight = plankBottom - plankTop;
    final logoHeight = plankBandHeight * 0.8 > 138 ? 138.0 : plankBandHeight * 0.8;

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        showHeaderBoard: false,
        child: Stack(
          children: [
            // Decorative only — sits first in the Stack (so everything
            // else, the sign and every board, paints over it) and never
            // intercepts taps (GameWidget itself doesn't request touch
            // input the way the real game's GameWidget's own gesture
            // detectors do — nothing here ever needs to be tapped).
            Positioned.fill(child: GameWidget(game: _fallingGame)),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: signWidth,
                    height: signHeight,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Long shadows for just the two legs (not the
                        // crossbar above them) — measured directly from
                        // beach_sign.png's own opaque bounds (leg centers
                        // at ~22%/78% of the width, feet at ~94% of the
                        // height). Each leans away from the sun (which
                        // sits upper-left in beach_background.png) toward
                        // the lower right, pivoting at the real leg's own
                        // foot so it reads as that leg's cast shadow
                        // rather than a floating shape.
                        _legShadow(footFraction: const Offset(0.2246, 0.945), legWidthFraction: 0.068, signWidth: signWidth, signHeight: signHeight),
                        _legShadow(footFraction: const Offset(0.7772, 0.945), legWidthFraction: 0.068, signWidth: signWidth, signHeight: signHeight),
                        Image.asset('assets/images/beach_sign.png', width: signWidth, height: signHeight, fit: BoxFit.contain),
                        Positioned(
                          top: plankTop + (plankBandHeight - logoHeight) / 2,
                          left: 0,
                          right: 0,
                          child: Center(child: GameLogo(height: logoHeight)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: signHeight + 12,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Transform.translate(
                  offset: Offset(0, -screenSize.height * 0.05),
                  child: Center(
                    // A slight counter-clockwise lean on the whole board
                    // pile + post together, pivoting from the bottom —
                    // rooted at the "ground" like a real post that's
                    // leaned over a little, rather than the boards tilting
                    // independently of what they're mounted on.
                    child: Transform.rotate(
                      angle: -3 * math.pi / 180,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        width: plankWidth,
                        child: Stack(
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.none,
                          children: [
                            // A signpost running behind the whole stack of
                            // boards, stretched tall enough that only its
                            // own top/bottom peek out past the topmost and
                            // bottommost board — the boards themselves
                            // (close together but with a slim gap, not
                            // fully flush) cover the rest of it, so it
                            // reads as one board pile mounted on a single
                            // post.
                            Positioned(
                              // Symmetric top/bottom overhang — pokes out
                              // above Play Game and below the new sixth
                              // (HUD) board the same amount each way. The
                              // HUD row used to float separately below
                              // the whole pile, which needed the post
                              // tuned to reach up behind it specifically;
                              // now it's just another board in the same
                              // Column, so the post threading behind
                              // every board including this one and
                              // poking out past its bottom edge is the
                              // natural default again.
                              top: -plankHeight * 0.6,
                              child: Image.asset('assets/images/post.png', width: plankWidth * 0.09, height: boardsColumnHeight + plankHeight * 1.2, fit: BoxFit.fill),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _MenuPlankTile(label: tr(locale, 'play_game'), icon: Icons.play_arrow_rounded, iconAsset: 'assets/images/play_button.png', width: plankWidth, height: plankHeight, onTap: _playGame, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                                SizedBox(height: kBoardGap),
                                _MenuPlankTile(
                                  label: tr(locale, 'best_scores'),
                                  icon: Icons.emoji_events_rounded,
                                  iconAsset: 'assets/images/best_scores.png',
                                  width: plankWidth,
                                  height: plankHeight,
                                  onTap: () => _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const HighScoresScreen())),
                                  variant: kPlankTextVariant,
                                  font: kPlankTextFont,
                                  shadowStyle: kPlankShadowStyle,
                                ),
                                SizedBox(height: kBoardGap),
                                _MenuPlankTile(label: tr(locale, 'leaderboard'), icon: Icons.leaderboard_rounded, iconAsset: 'assets/images/leaderboard.png', width: plankWidth, height: plankHeight, onTap: _openLeaderboard, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                                SizedBox(height: kBoardGap),
                                _MenuPlankTile(
                                  label: tr(locale, 'shop'),
                                  icon: Icons.storefront_rounded,
                                  iconAsset: 'assets/images/shop.png',
                                  width: plankWidth,
                                  height: plankHeight,
                                  onTap: () => _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const ShopScreen())),
                                  variant: kPlankTextVariant,
                                  font: kPlankTextFont,
                                  shadowStyle: kPlankShadowStyle,
                                ),
                                SizedBox(height: kBoardGap),
                                _MenuPlankTile(
                                  label: tr(locale, 'info'),
                                  icon: Icons.menu_book_rounded,
                                  iconAsset: 'assets/images/info.png',
                                  // 10% bigger again per feedback (was 1.2),
                                  // nudged left a touch so it doesn't read
                                  // as crowding the title text now that
                                  // it's bigger still.
                                  iconScale: 1.32,
                                  iconShiftLeft: 0.1,
                                  width: plankWidth,
                                  height: plankHeight,
                                  onTap: () => _pushAndPauseFalling(MaterialPageRoute(builder: (_) => const InfoScreen())),
                                  variant: kPlankTextVariant,
                                  font: kPlankTextFont,
                                  shadowStyle: kPlankShadowStyle,
                                ),
                                SizedBox(height: kBoardGap),
                                _MenuPlankTile(label: tr(locale, 'settings'), icon: Icons.settings_rounded, iconAsset: 'assets/images/settings.png', width: plankWidth, height: plankHeight, onTap: _openSettings, variant: kPlankTextVariant, font: kPlankTextFont, shadowStyle: kPlankShadowStyle),
                                SizedBox(height: kBoardGap),
                                SizedBox(
                                  width: plankWidth,
                                  height: plankHeight,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.asset('assets/images/menu_board_white.png', fit: BoxFit.fill),
                                      Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _HudTab(
                                              label: tr(locale, 'credits'),
                                              width: hudTabWidth,
                                              height: hudTabHeight,
                                              // 2x bigger and switched to
                                              // the same gold/orange
                                              // gradient wood-font as the
                                              // label above it, per
                                              // feedback that plain blue
                                              // text read too small and
                                              // out of place here.
                                              content: ColorfulPlankText(
                                                text: '${board.credits}',
                                                fontSize: hudTabHeight * 0.125 * 2,
                                                variant: PlankTextVariant.sunsetGradient,
                                                font: kPlankTextFont,
                                                shadowStyle: kPlankShadowStyle,
                                              ),
                                            ),
                                            SizedBox(width: hudTabGap),
                                            _HudTab(
                                              label: tr(locale, 'level'),
                                              width: hudTabWidth,
                                              height: hudTabHeight,
                                              content: ColorfulPlankText(
                                                text: '${board.level}',
                                                fontSize: hudTabHeight * 0.125 * 2,
                                                variant: PlankTextVariant.sunsetGradient,
                                                font: kPlankTextFont,
                                                shadowStyle: kPlankShadowStyle,
                                              ),
                                            ),
                                            SizedBox(width: hudTabGap),
                                            _HudTab(
                                              label: tr(locale, 'unlocked'),
                                              width: hudTabWidth,
                                              height: hudTabHeight,
                                              // Once a higher bar's ever been reached, its lowest
                                              // tier still outranks every lower-bar tier, so the
                                              // display switches over regardless of how far into
                                              // that chain the matching highestTierUnlockedLevelN
                                              // itself is (it can briefly be -1, right at the
                                              // moment of leveling up before that chain's first
                                              // tier's actually been seen — clamped to 0/Cherry
                                              // rather than crashing).
                                              content: GlassVisual(
                                                ingredient: board.highestLevelReached >= 3
                                                    ? kEvolutionChainLevel3[board.highestTierUnlockedLevel3.clamp(0, kEvolutionChainLevel3.length - 1)]
                                                    : board.highestLevelReached >= 2
                                                    ? kEvolutionChainLevel2[board.highestTierUnlockedLevel2.clamp(0, kEvolutionChainLevel2.length - 1)]
                                                    : kEvolutionChain[board.highestTierUnlocked],
                                                size: hudTabHeight * 0.4,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// One of the three bottom HUD tabs (Credits/Level/Unlocked) — an
/// empty_tab_white.png tile (a paler alternative used only for this
/// row, to match the whitewashed board it sits on) with a small label
/// and whatever content (a number, a picture) sits below it.
class _HudTab extends StatelessWidget {
  final String label;
  final Widget content;
  final double width;
  final double height;
  const _HudTab({required this.label, required this.content, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // fit: fill (not contain) — contain left the wood square
          // letterboxed by width whenever this box ran taller than the
          // tile art's own aspect, centered in that taller box, while
          // the text below stayed centered in the *full* box — the two
          // drifted apart and the text ended up spilling past the
          // wood's own visible edges. Filling the whole padded box
          // keeps the wood and the text sharing the same footprint.
          Padding(
            padding: EdgeInsets.all(width * 0.07),
            child: Image.asset('assets/images/empty_tab_white.png', fit: BoxFit.fill),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nudges the label down off the tile's own top edge —
                // per feedback it read too close to it.
                SizedBox(height: height * 0.07),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.06),
                  // Some translations (e.g. "DESBLOQUEADO") run longer
                  // than the English label the tab was sized for —
                  // shrink-to-fit on one line rather than wrapping.
                  // 1.5x bigger and switched from the old plain colored
                  // text to the app's own gold/orange gradient wood-font
                  // treatment, per feedback that it read too small and
                  // plain next to everything else.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ColorfulPlankText(
                      text: label.toUpperCase(),
                      fontSize: height * 0.077 * 1.5,
                      variant: PlankTextVariant.sunsetGradient,
                      font: kPlankTextFont,
                      shadowStyle: kPlankShadowStyle,
                    ),
                  ),
                ),
                SizedBox(height: height * 0.04),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.06),
                  child: FittedBox(fit: BoxFit.scaleDown, child: content),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One main-menu option — its own menu_board.png plank with a left-
/// aligned label burnt-in-looking directly on the wood, and a light
/// press-in animation on tap. [comingSoon] options render dimmed with a
/// small badge and don't respond to taps.
class _MenuPlankTile extends StatefulWidget {
  final String label;
  final IconData icon;

  /// A real picture standing in for [icon] when set — every tile has its
  /// own custom art now, so [icon] only ever renders as a fallback if
  /// one's ever added without matching art. Every tile using the same
  /// Image-based path (rather than a mix of Icon/Image) is also what
  /// keeps them all vertically aligned with each other — a plain
  /// Material [Icon] doesn't share an image's exact visual weight/center
  /// even at a matching nominal size.
  final String? iconAsset;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final bool comingSoon;
  final String soonLabel;
  final PlankTextVariant variant;
  final PlankFont font;
  final PlankShadowStyle shadowStyle;

  /// Grows [iconAsset]'s rendered size relative to the standard
  /// `height * 0.529` — Info, per feedback. 1.0 (every other tile) keeps
  /// the original size. Rendered inside a fixed-size slot (see build's
  /// own comment) so a scaled-up icon grows without shifting where the
  /// title text starts — every tile's title lines up regardless of
  /// iconScale.
  final double iconScale;

  /// Shifts the icon left within its slot, as a fraction of [height] —
  /// Info's own icon per feedback. 0 (every other tile) keeps it
  /// centered. Purely visual: doesn't move the title text, same
  /// decoupling as [iconScale].
  final double iconShiftLeft;

  const _MenuPlankTile({
    required this.label,
    required this.icon,
    this.iconAsset,
    required this.width,
    required this.height,
    required this.variant,
    this.font = PlankFont.fredoka,
    this.shadowStyle = PlankShadowStyle.soft,
    this.onTap,
    this.comingSoon = false,
    this.soonLabel = 'SOON',
    this.iconScale = 1.0,
    this.iconShiftLeft = 0.0,
  });

  @override
  State<_MenuPlankTile> createState() => _MenuPlankTileState();
}

class _MenuPlankTileState extends State<_MenuPlankTile> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    // No longer dimmed via Opacity when comingSoon — full-strength like
    // every other board, with just the SOON badge doing the work of
    // signalling the state, per feedback that the dimming read wrong.
    final tile = SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Image.asset('assets/images/menu_board_white.png', width: widget.width, height: widget.height, fit: BoxFit.fill),
          Padding(
            padding: EdgeInsets.only(left: widget.width * 0.09),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.iconAsset != null)
                  // A fixed-size slot at the *standard* (unscaled) icon
                  // size — iconScale grows the image drawn inside it,
                  // not the slot itself, so the title text after it
                  // (sized off the Row's total width) starts at the same
                  // x on every tile regardless of iconScale. iconShiftLeft
                  // nudges the image within that slot, same independence
                  // from the text's position.
                  SizedBox(
                    width: widget.height * 0.529,
                    height: widget.height * 0.529,
                    child: Transform.translate(
                      offset: Offset(-widget.height * widget.iconShiftLeft, 0),
                      child: Image.asset(
                        widget.iconAsset!,
                        width: widget.height * 0.529 * widget.iconScale,
                        height: widget.height * 0.529 * widget.iconScale,
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                else
                  Icon(
                    icon,
                    size: widget.height * 0.391,
                    color: plankAccentColor(widget.variant),
                    shadows: const [Shadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1.5))],
                  ),
                SizedBox(width: widget.width * 0.025),
                // Flexible — gives ColorfulPlankText's own Wrap a real
                // bounded width to measure against, so a translation
                // that runs wider than the English original (e.g.
                // "Mejores Puntuaciones" for "Best Scores") wraps to a
                // second line instead of overflowing past the board's
                // edge.
                Flexible(
                  child: ColorfulPlankText(text: widget.label, fontSize: widget.height * 0.3, variant: widget.variant, font: widget.font, shadowStyle: widget.shadowStyle),
                ),
              ],
            ),
          ),
          if (widget.comingSoon)
            Positioned(
              right: widget.width * 0.06,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: widget.width * 0.02, vertical: widget.height * 0.06),
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Text(
                  widget.soonLabel,
                  style: TextStyle(fontSize: widget.height * 0.16, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.textMuted),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.onTap == null) return tile;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(scale: _pressed ? 0.96 : 1.0, duration: const Duration(milliseconds: 90), curve: Curves.easeOut, child: tile),
    );
  }
}

enum _PlayChoice { continueGame, newGame }

/// Offered instead of jumping straight into GameScreen whenever there's
/// a run actually in progress — see MenuScreen._playGame.
class _PlayChoiceDialog extends StatelessWidget {
  final AppLocale locale;
  const _PlayChoiceDialog({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(locale, 'play_choice_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone),
            ),
            const SizedBox(height: 20),
            StoneButton(
              onTap: () => Navigator.of(context).pop(_PlayChoice.continueGame),
              child: Text(tr(locale, 'continue_label'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
            const SizedBox(height: 10),
            StoneButton(
              onTap: () => Navigator.of(context).pop(_PlayChoice.newGame),
              child: Text(tr(locale, 'new_game'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Are you sure?" gate on top of [_PlayChoiceDialog]'s own New Game
/// option specifically — picking New Game there means throwing away a
/// real run already in progress (that's the only way this dialog gets
/// offered at all), so it gets the same confirm-before-destroying
/// treatment as Settings' own Reset Progress row, not an instant wipe.
class _LoseProgressDialog extends StatelessWidget {
  final AppLocale locale;
  const _LoseProgressDialog({required this.locale});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(locale, 'lose_progress_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone),
            ),
            const SizedBox(height: 8),
            Text(
              tr(locale, 'lose_progress_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textOnStoneMuted),
            ),
            const SizedBox(height: 20),
            StoneButton(
              onTap: () => Navigator.of(context).pop(true),
              child: Text(tr(locale, 'yes_new_game'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(false),
              child: SizedBox(
                width: double.infinity,
                height: 40,
                child: Center(
                  child: Text(tr(locale, 'cancel'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textOnStoneMuted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the player pick which already-reached level a New Game starts
/// on, defaulting (highlighted) to the highest one — see
/// MenuScreen._startNewGame. Names match InfoLevelData's own (Beach/
/// Rooftop/Safari), the game's established level naming.
class _LevelPickerDialog extends StatelessWidget {
  final AppLocale locale;
  final int maxLevel;
  final int initialLevel;
  const _LevelPickerDialog({required this.locale, required this.maxLevel, required this.initialLevel});

  static String _levelName(int level) => switch (level) {
    1 => 'Beach',
    2 => 'Rooftop',
    _ => 'Safari',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(locale, 'choose_level'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textOnStone)),
            const SizedBox(height: 18),
            for (var level = maxLevel; level >= 1; level--) ...[
              if (level != maxLevel) const SizedBox(height: 10),
              StoneButton(
                onTap: () => Navigator.of(context).pop(level),
                selected: level == initialLevel,
                height: 48,
                child: Text(
                  '${tr(locale, 'level')} $level — ${_levelName(level)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
