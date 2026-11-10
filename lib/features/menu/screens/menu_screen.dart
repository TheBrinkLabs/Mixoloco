import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/i18n/strings.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/outlined_label.dart';
import '../../../core/utils/progress_sync.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/hud_kit.dart';
import '../../../core/widgets/notification_tablet.dart';
import '../../../data/models/ingredient.dart';
import '../../../data/repositories/league_repository.dart';
import '../../game/providers/game_state_provider.dart';
import '../../game/screens/game_screen.dart';
import '../../league/providers/league_provider.dart';
import '../../league/screens/rankings_screen.dart';
import '../../shop/screens/shop_screen.dart';
import '../../shop/widgets/get_credits_dialog.dart';
import '../../../data/services/high_scores_service.dart' show loadHighScores;
import '../../../data/services/game_save_service.dart' show loadGameJson;
import '../../../data/services/progression_service.dart' show loadHighestTierForLevel, loadHowToPlaySeen, saveHowToPlaySeen;
import 'how_to_play_screen.dart';
import 'info_screen.dart';
import 'settings_screen.dart';

/// Start screen — the redesigned main menu: a top HUD row (level, credits,
/// unlocked drink), a floating logo, a 2x2 icon grid of menu options, a
/// glossy Play button and an About link, over the beach backdrop. See
/// design_handoff_main_menu/README.md for the full spec this was built
/// from.
class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuide());
  }

  /// Opens the How to Play walkthrough once, the first time a new player
  /// reaches the menu. A player who's already played — a recorded score,
  /// a game in progress, or any merge on Level 1 (i.e. updating from
  /// before the walkthrough existed) — is just marked as having seen it.
  Future<void> _maybeShowGuide() async {
    if (await loadHowToPlaySeen()) return;
    final played = (await loadHighScores()).isNotEmpty ||
        await loadGameJson() != null ||
        await loadHighestTierForLevel(1) > 0;
    if (!mounted) return;
    if (!played) _push(MaterialPageRoute(builder: (_) => const HowToPlayScreen()));
    await saveHowToPlaySeen();
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
    final outcome = await syncProgress(ref.read(leagueRepositoryProvider), uid);
    if (outcome == ProgressSyncOutcome.changed && mounted) {
      await ref
          .read(gameStateProvider.notifier)
          .refreshLifetimeFieldsFromDisk();
    }
    // A failure here is silent by design (no snackbar — this fires on
    // every launch, unprompted, so there's no good moment to interrupt
    // with an error) but no longer a dead end: the Settings "Google
    // Backup" row's own tap handler retries this same sync and *does*
    // surface a failure, so a player who notices something's missing
    // always has a visible way to try again.
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
  /// turned off) the actually-visible screen already re-asserted.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (state == AppLifecycleState.resumed && isCurrent) {
      ref.read(audioSettingsProvider.notifier).playMenuMusic();
    }
  }

  Future<void> _push(Route<void> route) async {
    await Navigator.of(context).push(route);
  }

  void _openSettings() {
    _push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openRankings() {
    _push(MaterialPageRoute(builder: (_) => const RankingsScreen()));
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
    final inProgress =
        !board.gameOver && (board.score > 0 || board.placedItems.isNotEmpty);
    if (!inProgress) {
      await _startNewGame();
      return;
    }
    final locale = ref.read(localeProvider);
    final choice = await showDialog<_PlayChoice>(
      context: context,
      builder: (_) => _PlayChoiceDialog(locale: locale),
    );
    if (!mounted || choice == null) return;
    if (choice == _PlayChoice.continueGame) {
      _push(MaterialPageRoute(builder: (_) => const GameScreen()));
    } else {
      // A real run was actually in progress (that's how we got here —
      // see the inProgress check above), so New Game means throwing it
      // away — confirm before doing that, same as Settings' own Reset
      // Progress confirm.
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _LoseProgressDialog(locale: locale),
      );
      if (!mounted || confirmed != true) return;
      await _startNewGame();
    }
  }

  Future<void> _startNewGame() async {
    final board = ref.read(gameStateProvider);
    var level = board.highestLevelReached;
    // Debug builds can pick any level, for testing the later ones.
    final pickable = kDebugMode ? kMaxLevel : board.highestLevelReached;
    if (pickable >= 2) {
      final locale = ref.read(localeProvider);
      final chosen = await showDialog<int>(
        context: context,
        builder: (_) => _LevelPickerDialog(
          locale: locale,
          maxLevel: pickable,
          initialLevel: board.highestLevelReached,
        ),
      );
      if (!mounted || chosen == null) return; // cancelled — stay on the menu
      level = chosen;
    }
    ref.read(gameStateProvider.notifier).startNewGameAtLevel(level);
    if (!mounted) return;
    _push(MaterialPageRoute(builder: (_) => const GameScreen()));
  }

  /// The ingredient art for whichever drink is currently the player's
  /// highest-unlocked, across every evolution chain — same lookup the old
  /// HUD board used. Kept data-driven (rather than the handoff mock's
  /// static level-1 pineapple) so the badge is right at every level, not
  /// just the first.
  Ingredient _unlockedIngredient(BoardState board) {
    final chain = evolutionChainForLevel(board.highestLevelReached);
    final tier = highestTierFor(board.highestTiers, board.highestLevelReached);
    return chain[tier.clamp(0, chain.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final board = ref.watch(gameStateProvider);
    final locale = ref.watch(localeProvider);

    // The handoff is drawn on a 390x844 portrait frame; scaling every
    // measurement by the same factor keeps the whole design's
    // proportions intact instead of stretching it unevenly. Scaling by
    // width alone overflows on phones whose safe-area height is short
    // relative to their width (observed on a real device: the grid and
    // Play button overlapped) — taking whichever of width/height scale
    // is smaller, then centering the scaled 390-wide column, keeps the
    // whole layout on-screen either way; see the README's own
    // "Coordinate system" note ("scale ... or centre a 390-wide column").
    final safeAreaPadding = MediaQuery.paddingOf(context);
    final availableHeight =
        screenSize.height - safeAreaPadding.top - safeAreaPadding.bottom;
    final s = math.min(screenSize.width / 390.0, availableHeight / 844.0);

    return Scaffold(
      body: BarBackdrop(
        showTable: false,
        child: Stack(
          children: [
            const Positioned.fill(child: _ToneGradient()),
            const Positioned.fill(child: _Vignette()),
            SafeArea(
              child: Center(
                child: SizedBox(
                  width: 390 * s,
                  height: availableHeight,
                  child: Stack(
                    // The logo now sits slightly above this box's own top
                    // (see its negative `top` below) to tuck it closer to
                    // the HUD row — Clip.none so that isn't hard-clipped.
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        // Its own row now, above the Settings button sitting
                        // in the row above this one (see that Positioned
                        // below) — back to the full width Settings used to
                        // share with this row, so it no longer needs
                        // squeezing in. The FittedBox/ConstrainedBox pair
                        // stays on as a safety net (e.g. for a longer
                        // translation than English budgets for) even
                        // though it should render at 1:1 scale now that
                        // there's no deficit.
                        top: 48 * s,
                        left: 20 * s,
                        right: 10 * s,
                        child: LayoutBuilder(
                          builder: (context, constraints) => FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: constraints.maxWidth,
                              ),
                              child: _HudRow(
                                scale: s,
                                locale: locale,
                                board: board,
                                unlockedIngredient: _unlockedIngredient(board),
                                onBuyCredits: () => showDialog<void>(
                                  context: context,
                                  builder: (_) => const GetCreditsDialog(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        // Its own row above Level/Credits/Unlocked now,
                        // rather than sharing that row's right edge —
                        // frees the full row width back up for those 3
                        // pills.
                        top: 2 * s,
                        right: 20 * s,
                        child: _SettingsButton(scale: s, onTap: _openSettings),
                      ),
                      Positioned(
                        // Shifted down by the same amount the HUD row
                        // below it moved (40*s, to make room for the new
                        // Settings row above) so the gap between logo and
                        // HUD row stays the same as before, plus a further
                        // 5% of the 390x844 reference frame's own height
                        // (42*s) per feedback that the logo sat too high.
                        top: (-19 + 42) * s,
                        left: 0,
                        right: 0,
                        // IgnorePointer — ShadowedAsset defaults its
                        // hit-testable box to width×width (no explicit
                        // height given here), a full 350*s square even
                        // though the logo art itself is much shorter.
                        // Painted after (so on top of, for hit-testing
                        // purposes) the HUD row above, that oversized
                        // invisible square was silently swallowing every
                        // tap landing on the credits pill's "+" button —
                        // Stack hit-testing stops at the first (topmost)
                        // child whose bounds contain the point. The logo
                        // has no tap behavior of its own, so excluding it
                        // from hit-testing entirely is strictly correct.
                        child: IgnorePointer(
                          child: Center(
                            child: _FloatingLogo(
                              scale: s,
                              reduceMotion: reduceMotion,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 24 * s,
                        right: 24 * s,
                        // Was 206*s — nudged up a bit now that the HUD
                        // row/logo above have both moved down to make
                        // room for the new Settings row.
                        bottom: 220 * s,
                        child: _TileRow(
                          scale: s,
                          locale: locale,
                          rankingsUnseen: ref
                              .watch(leagueControllerProvider)
                              .lastWeekResultIsNew,
                          onShop: () => _push(
                            MaterialPageRoute(
                              builder: (_) => const ShopScreen(),
                            ),
                          ),
                          onRankings: _openRankings,
                          onGuide: () => _push(
                            MaterialPageRoute(
                              builder: (_) => const InfoScreen(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        // Left/right match the tile row's own (24*s each)
                        // so the Play bar's width equals the 3 combined
                        // tiles' span, rather than its old narrower 40*s
                        // inset.
                        left: 24 * s,
                        right: 24 * s,
                        bottom: 115 * s,
                        child: _PlayButton(
                          scale: s,
                          level: board.level,
                          locale: locale,
                          reduceMotion: reduceMotion,
                          onTap: _playGame,
                        ),
                      ),
                    ],
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

/// Layer 2 of the backdrop — a vertical tone wash from deep night-blue up
/// top, through the sunset's own colours in the middle, down to a dark
/// plum at the bottom, sat over the beach photo.
class _ToneGradient extends StatelessWidget {
  const _ToneGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.18, 0.55, 0.78, 1.0],
          colors: [
            Color(0x8C0E2846),
            Color(0x000E2846),
            Color(0x00FFAA50),
            Color(0x2E783214),
            Color(0x8C28141E),
          ],
        ),
      ),
    );
  }
}

/// Layer 3 of the backdrop — a soft radial darkening toward the edges,
/// centred slightly above the screen's own middle.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.0, -0.1),
          radius: 0.9,
          stops: [0.0, 0.6, 1.0],
          colors: [Colors.transparent, Colors.transparent, Color(0x47140A00)],
        ),
      ),
    );
  }
}

/// The three HUD pills (Level, Credits, Unlocked) in a spaceBetween row.
class _HudRow extends StatelessWidget {
  final double scale;
  final AppLocale locale;
  final BoardState board;
  final Ingredient unlockedIngredient;
  final VoidCallback onBuyCredits;

  const _HudRow({
    required this.scale,
    required this.locale,
    required this.board,
    required this.unlockedIngredient,
    required this.onBuyCredits,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HudPill(
          scale: s,
          // 50 (was 46) — design_handoff_main_menu_v3 §2: the badge was
          // covering the first "L" of LEVEL at the old padding.
          leftPad: 50 * s,
          rightPad: 10 * s,
          badgeSize: 48 * s,
          badgeLeft: -6 * s,
          badgeTop: -8 * s,
          badge: layeredCircle(
            size: 48 * s,
            shadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: Offset(0, 3 * s),
              ),
            ],
            rings: [
              HudRing(width: 2 * s, color: HudColors.hudBorder),
              HudRing(width: 3 * s, color: Colors.white),
            ],
            fill: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  radius: 1.0,
                  stops: [0.0, 0.6, 1.0],
                  colors: [
                    HudColors.goldTop,
                    HudColors.goldMid,
                    HudColors.goldBottom,
                  ],
                ),
              ),
              child: Center(
                child: OutlinedLabel(
                  text: '${board.level}',
                  fontSize: 24 * s,
                  fill: Colors.white,
                  stroke: HudColors.goldNumberStroke,
                  strokeWidth: 4 * s,
                ),
              ),
            ),
          ),
          content: OutlinedLabel(
            text: tr(locale, 'level').toUpperCase(),
            fontSize: 13 * s,
            fill: Colors.white,
            letterSpacing: 0.78 * s,
          ),
        ),
        _HudPill(
          scale: s,
          leftPad: 40 * s,
          rightPad: 34 * s,
          badgeSize: 40 * s,
          badgeLeft: -4 * s,
          badgeTop: -4 * s,
          badge: layeredCircle(
            size: 40 * s,
            rings: [
              HudRing(width: 2 * s, color: HudColors.coinRim),
              HudRing(
                width: 4 * s,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ],
            fill: DecoratedBox(
              // Blue (was the same gold as the coins art itself) — the
              // gold coins were hard to make out against a gold badge.
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment(-0.3, -0.4),
                  radius: 1.0,
                  stops: [0.0, 0.6, 1.0],
                  colors: [
                    HudColors.plateTop,
                    HudColors.plateMid,
                    HudColors.plateBottom,
                  ],
                ),
              ),
              // See game_screen.dart's matching _GameCreditsPill comment —
              // coins.png's own canvas has a lot of transparent padding
              // around the actual coin stack, so BoxFit.cover (clipped to
              // the circle) fills the badge properly where
              // BoxFit.contain left it tiny.
              child: ClipOval(
                child: Image.asset(
                  'assets/images/coins.png',
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  // This badge never renders bigger than ~40*s logical
                  // px — see GlassVisual's matching comment.
                  cacheWidth: (40 * s * MediaQuery.devicePixelRatioOf(context)).round(),
                ),
              ),
            ),
          ),
          content: OutlinedLabel(
            text: _formatCredits(board.credits),
            fontSize: 19 * s,
            fill: Colors.white,
            stroke: HudColors.hudBorder,
            strokeWidth: 3 * s,
          ),
          topRight: Positioned(
            top: 2 * s,
            right: 2 * s,
            child: GestureDetector(
              onTap: onBuyCredits,
              child: Container(
                width: 28 * s,
                height: 28 * s,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9 * s),
                  border: Border.all(color: HudColors.plusBorder, width: 2 * s),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [HudColors.plusTop, HudColors.plusBottom],
                  ),
                ),
                alignment: Alignment.center,
                child: OutlinedLabel(
                  text: '+',
                  fontSize: 22 * s,
                  fill: Colors.white,
                  stroke: HudColors.plusBorder,
                  strokeWidth: 3 * s,
                ),
              ),
            ),
          ),
        ),
        _HudPill(
          scale: s,
          // 50 (was 44) — same badge-covers-the-first-letter fix as the
          // Level pill above, per design_handoff_main_menu_v3 §2.
          leftPad: 50 * s,
          rightPad: 10 * s,
          marginLeft: 8 * s,
          badgeSize: 48 * s,
          badgeLeft: -6 * s,
          badgeTop: -8 * s,
          badge: layeredCircle(
            size: 48 * s,
            shadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: Offset(0, 3 * s),
              ),
            ],
            rings: [
              HudRing(width: 2 * s, color: HudColors.hudBorder),
              HudRing(
                width: 3 * s,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [HudColors.creamTop, HudColors.creamBottom],
                ),
              ),
            ],
            fill: DecoratedBox(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [HudColors.creamInnerTop, HudColors.creamInnerBottom],
                ),
              ),
              child: Center(
                child: GlassVisual(
                  ingredient: unlockedIngredient,
                  size: 48 * s * 0.82,
                  // This badge is a small cosmetic preview circle, not the
                  // physics table — applying gameplay's contact-matching
                  // displayScale/displayScaleX here (some ingredients
                  // stretch well past 1.0, e.g. Vodka's 1.652x) bled the
                  // art outside the circle for several ingredients.
                  applyDisplayScale: false,
                ),
              ),
            ),
          ),
          content: OutlinedLabel(
            text: tr(locale, 'unlocked').toUpperCase(),
            fontSize: 13 * s,
            fill: Colors.white,
            letterSpacing: 0.78 * s,
          ),
        ),
      ],
    );
  }

  static String _formatCredits(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// One rounded HUD pill with a badge poking out of its left edge.
class _HudPill extends StatelessWidget {
  final double scale;
  final double leftPad;
  final double rightPad;
  final double marginLeft;
  final double badgeSize;
  final double badgeLeft;
  final double badgeTop;
  final Widget badge;
  final Widget content;
  final Widget? topRight;

  const _HudPill({
    required this.scale,
    required this.leftPad,
    required this.rightPad,
    this.marginLeft = 0,
    required this.badgeSize,
    required this.badgeLeft,
    required this.badgeTop,
    required this.badge,
    required this.content,
    this.topRight,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Padding(
      padding: EdgeInsets.only(left: marginLeft),
      child: Container(
        height: 36 * s,
        constraints: BoxConstraints(minWidth: (leftPad + rightPad) + 20 * s),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18 * s),
          border: Border.all(color: HudColors.hudBorder, width: 2 * s),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [HudColors.hudNavyTop, HudColors.hudNavyBottom],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              offset: Offset(0, 3 * s),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 1 * s,
              left: 12 * s,
              right: 12 * s,
              child: Container(
                height: 2 * s,
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: leftPad, right: rightPad),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(fit: BoxFit.scaleDown, child: content),
              ),
            ),
            Positioned(
              left: badgeLeft,
              top: badgeTop,
              child: SizedBox(
                width: badgeSize,
                height: badgeSize,
                child: badge,
              ),
            ),
            ?topRight,
          ],
        ),
      ),
    );
  }
}

/// The floating Mixoloco wordmark — menu_logo_sticker.png (the same art
/// as mixoloco_logo.png with the sticker outline/shadow baked in, see
/// tools/bake_menu_logo_outline.dart) with a soft drop shadow and a slow
/// bob-and-tilt loop.
class _FloatingLogo extends StatefulWidget {
  final double scale;
  final bool reduceMotion;
  const _FloatingLogo({required this.scale, required this.reduceMotion});

  @override
  State<_FloatingLogo> createState() => _FloatingLogoState();
}

class _FloatingLogoState extends State<_FloatingLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _FloatingLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (widget.reduceMotion) {
        _controller.stop();
        _controller.value = 0;
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final width = 350 * s;
    final logo = ShadowedAsset(
      path: 'assets/images/menu_logo_sticker.png',
      width: width,
      shadows: [
        SpriteShadow(
          offset: Offset(0, 14 * s),
          blur: 18 * s,
          color: Colors.black.withValues(alpha: 0.35),
        ),
      ],
    );
    if (widget.reduceMotion) return logo;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // A half-cosine wave, 0 -> 1 -> 0 over one loop: y 0 -> -7 -> 0 and
        // rotate -1.5deg -> +1deg -> -1.5deg, matching the handoff's own
        // float keyframes.
        final wave = (1 - math.cos(_controller.value * 2 * math.pi)) / 2;
        final lift = -7 * s * wave;
        final angle = (-1.5 + 2.5 * wave) * math.pi / 180;
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.rotate(angle: angle, child: child),
        );
      },
      child: logo,
    );
  }
}

/// The Shop/Rankings/Guide tile row (design_handoff_main_menu_v3 §4) —
/// replaces the old 2x2 Shop/Best Scores/Info/Leaderboard grid now that
/// Best Scores and Leaderboard are one merged Rankings screen and About
/// has moved into Settings.
class _TileRow extends StatelessWidget {
  final double scale;
  final AppLocale locale;
  final bool rankingsUnseen;
  final VoidCallback onShop;
  final VoidCallback onRankings;
  final VoidCallback onGuide;

  const _TileRow({
    required this.scale,
    required this.locale,
    required this.rankingsUnseen,
    required this.onShop,
    required this.onRankings,
    required this.onGuide,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _MenuTile(
          scale: s,
          label: tr(locale, 'shop'),
          iconAsset: 'assets/images/icon_shop.png',
          onTap: onShop,
        ),
        _MenuTile(
          scale: s,
          label: tr(locale, 'rankings'),
          iconAsset: 'assets/images/icon_rankings.png',
          onTap: onRankings,
          showCountDot: rankingsUnseen,
        ),
        _MenuTile(
          scale: s,
          label: tr(locale, 'guide'),
          iconAsset: 'assets/images/icon_guide.png',
          onTap: onGuide,
        ),
      ],
    );
  }
}

/// One tile — a gold-rimmed navy "plate" with its icon breaking out the
/// top and a gold ribbon label overlapping the bottom, per the v3
/// handoff's §4a-d. `showCountDot` shows the small red unseen-count
/// badge (Rankings only, driven by [LeagueState.lastWeekResultIsNew] —
/// there's no real "shop has new stock" concept anywhere in the data
/// model yet, so that NEW-badge slot from the handoff is deliberately
/// not wired up here).
class _MenuTile extends StatefulWidget {
  final double scale;
  final String label;
  final String iconAsset;
  final VoidCallback onTap;
  final bool showCountDot;
  const _MenuTile({
    required this.scale,
    required this.label,
    required this.iconAsset,
    required this.onTap,
    this.showCountDot = false,
  });

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 104 * s,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomCenter,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 98 * s,
                        height: 88 * s,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26 * s),
                          border: Border.all(
                            color: HudColors.goldRim,
                            width: 3 * s,
                          ),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              HudColors.plateTop,
                              HudColors.plateMid,
                              HudColors.plateBottom,
                            ],
                            stops: [0.0, 0.7, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: HudColors.hudBorder,
                              offset: Offset(0, 6 * s),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              offset: Offset(0, 12 * s),
                              blurRadius: 18 * s,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 6 * s,
                        left: 6 * s,
                        right: 6 * s,
                        height: 88 * s * 0.3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20 * s),
                              bottom: Radius.circular(30 * s),
                            ),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 14 * s,
                        child: ShadowedAsset(
                          path: widget.iconAsset,
                          width: 92 * s,
                          height: 84 * s,
                          shadows: [
                            SpriteShadow(
                              offset: Offset(0, 3 * s),
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            SpriteShadow(
                              offset: Offset(0, 5 * s),
                              blur: 6 * s,
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Transform.translate(
                    offset: Offset(0, -14 * s),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        12 * s,
                        3 * s,
                        12 * s,
                        4 * s,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10 * s),
                        border: Border.all(
                          color: HudColors.ribbonStroke,
                          width: 2 * s,
                        ),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [HudColors.ribbonTop, HudColors.ribbonBottom],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: HudColors.ribbonStroke,
                            offset: Offset(0, 3 * s),
                          ),
                        ],
                      ),
                      // FittedBox (not a bare label) — "RANKINGS" at this
                      // ribbon's width otherwise wraps to two lines
                      // instead of shrinking to fit on one, same fix the
                      // old grid tiles' labels already needed.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: OutlinedLabel(
                          text: widget.label.toUpperCase(),
                          fontSize: 15 * s,
                          fill: Colors.white,
                          stroke: HudColors.ribbonStroke,
                          strokeWidth: 3 * s,
                          letterSpacing: 0.6 * s,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.showCountDot)
                Positioned(
                  top: -6 * s,
                  right: 2 * s,
                  child: Container(
                    width: 18 * s,
                    height: 18 * s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HudColors.badgeRed,
                      border: Border.all(color: Colors.white, width: 2 * s),
                      boxShadow: [
                        BoxShadow(
                          color: HudColors.badgeRedEdge,
                          offset: Offset(0, 2 * s),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The new top-right round Settings button (design_handoff_main_menu_v3
/// §1) — replaces the old bare bottom-corner gear icon.
class _SettingsButton extends StatefulWidget {
  final double scale;
  final VoidCallback onTap;
  const _SettingsButton({required this.scale, required this.onTap});

  @override
  State<_SettingsButton> createState() => _SettingsButtonState();
}

class _SettingsButtonState extends State<_SettingsButton> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: layeredCircle(
          size: 42 * s,
          shadow: [
            BoxShadow(color: HudColors.hudBorder, offset: Offset(0, 4 * s)),
          ],
          rings: [
            HudRing(width: 2 * s, color: HudColors.hudBorder),
            HudRing(width: 3 * s, color: HudColors.goldRim),
          ],
          fill: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [HudColors.settingsPlateTop, HudColors.hudNavyBottom],
              ),
            ),
            child: Center(
              child: ShadowedAsset(
                // 26 (was 34) — smaller gear within the same 42*s circle.
                path: 'assets/images/icon_settings.png',
                width: 26 * s,
                shadows: [
                  SpriteShadow(
                    offset: Offset(0, 2 * s),
                    blur: 2 * s,
                    color: Colors.black.withValues(alpha: 0.4),
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

/// The main Play call-to-action: a layered 3D button (base edge, glossy
/// face, animated shine sweep, overflowing Play icon, PLAY/LEVEL n text),
/// with a 5px press-down.
class _PlayButton extends StatefulWidget {
  final double scale;
  final int level;
  final AppLocale locale;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _PlayButton({
    required this.scale,
    required this.level,
    required this.locale,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    const height = 96.0;
    final faceHeight = (height - 8) * s;

    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: SizedBox(
        height: height * s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Base / 3D edge.
            Container(
              height: height * s,
              decoration: BoxDecoration(
                color: HudColors.greenEdge,
                borderRadius: BorderRadius.circular(30 * s),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF143C0A).withValues(alpha: 0.45),
                    offset: Offset(0, 14 * s),
                    blurRadius: 26 * s,
                  ),
                ],
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOut,
              top: _pressed ? 5 * s : 0,
              left: 0,
              right: 0,
              // Stack (not just the ClipRRect directly) — the play icon
              // below is deliberately positioned to overlap past the
              // button's own rounded edge, which a ClipRRect would cut
              // clean off. Keeping the icon as a later sibling OUTSIDE
              // the ClipRRect (rather than inside, where it used to live)
              // both avoids that clipping and puts it in front of
              // everything else, as it should be.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30 * s),
                    child: Container(
                      height: faceHeight,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: HudColors.greenEdge,
                          width: 3 * s,
                        ),
                        borderRadius: BorderRadius.circular(30 * s),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: [0.0, 0.45, 1.0],
                          colors: [
                            HudColors.greenTop,
                            HudColors.greenMid,
                            HudColors.greenBottom,
                          ],
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 3 * s,
                            left: 10 * s,
                            right: 10 * s,
                            child: Container(
                              height: 3 * s,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 10 * s,
                            right: 10 * s,
                            child: Container(
                              height: 6 * s,
                              color: const Color(
                                0xFF003C00,
                              ).withValues(alpha: 0.18),
                            ),
                          ),
                          Positioned(
                            left: 10 * s,
                            right: 10 * s,
                            top: 5 * s,
                            height: faceHeight * 0.34,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(22 * s),
                                  topRight: Radius.circular(22 * s),
                                  bottomLeft: Radius.circular(40 * s),
                                  bottomRight: Radius.circular(40 * s),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.5),
                                    Colors.white.withValues(alpha: 0.08),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (!widget.reduceMotion)
                            Positioned.fill(
                              child: _ShineSweep(bandWidthFraction: 0.3),
                            ),
                          Positioned.fill(
                            left: 96 * s,
                            child: Center(
                              // scaleDown as a safety net in case some locale's
                              // 'play' string still runs wider than this button
                              // budgets for at the design's own 46*s size.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedLabel(
                                      text: tr(
                                        widget.locale,
                                        'play',
                                      ).toUpperCase(),
                                      fontSize: 46 * s,
                                      fill: Colors.white,
                                      stroke: HudColors.greenEdge,
                                      strokeWidth: 7 * s,
                                      letterSpacing: 1.4 * s,
                                      shadowOffset: Offset(0, 4 * s),
                                      shadowColor: HudColors.greenEdge,
                                    ),
                                    SizedBox(height: 2 * s),
                                    OutlinedLabel(
                                      text:
                                          '${tr(widget.locale, 'level').toUpperCase()} ${widget.level}',
                                      fontSize: 14 * s,
                                      fill: HudColors.playSubLabel,
                                      stroke: HudColors.greenEdge,
                                      strokeWidth: 3 * s,
                                      letterSpacing: 1.4 * s,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Painted after (so in front of) the ClipRRect above —
                  // and outside it, so the part that deliberately
                  // overlaps past the button's rounded top-left corner
                  // no longer gets clipped off.
                  Positioned(
                    left: -11.2 * s,
                    top: -19.2 * s,
                    child: ShadowedAsset(
                      path: 'assets/images/icon_play.png',
                      width: 94.4 * s,
                      rotation: -8 * math.pi / 180,
                      shadows: [
                        SpriteShadow(
                          offset: Offset(0, 4 * s),
                          color: const Color(0xFF14460A).withValues(alpha: 0.6),
                        ),
                        SpriteShadow(
                          offset: Offset(0, 8 * s),
                          blur: 10 * s,
                          color: Colors.black.withValues(alpha: 0.25),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The animated diagonal highlight band that sweeps across the Play
/// button's face — rests just off the left edge for the first 60% of its
/// 3.2s loop, then sweeps across to past the right edge.
class _ShineSweep extends StatefulWidget {
  final double bandWidthFraction;
  const _ShineSweep({required this.bandWidthFraction});

  @override
  State<_ShineSweep> createState() => _ShineSweepState();
}

class _ShineSweepState extends State<_ShineSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          final progress = t < 0.6 ? 0.0 : (t - 0.6) / 0.4;
          final position = -1.4 + progress * (2.6 - -1.4);
          return LayoutBuilder(
            builder: (context, constraints) {
              final bandWidth = constraints.maxWidth * widget.bandWidthFraction;
              return Transform.translate(
                offset: Offset(position * bandWidth, 0),
                child: Transform(
                  transform: Matrix4.skewX(-20 * math.pi / 180),
                  child: Container(
                    width: bandWidth,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textOnStone,
              ),
            ),
            const SizedBox(height: 20),
            StoneButton(
              onTap: () => Navigator.of(context).pop(_PlayChoice.continueGame),
              child: Text(
                tr(locale, 'continue_label'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 10),
            StoneButton(
              onTap: () => Navigator.of(context).pop(_PlayChoice.newGame),
              child: Text(
                tr(locale, 'new_game'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
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
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textOnStone,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(locale, 'lose_progress_body'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textOnStoneMuted,
              ),
            ),
            const SizedBox(height: 20),
            StoneButton(
              onTap: () => Navigator.of(context).pop(true),
              child: Text(
                tr(locale, 'yes_new_game'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 10),
            StoneButton(
              onTap: () => Navigator.of(context).pop(false),
              height: 40,
              child: Text(
                tr(locale, 'cancel'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
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
  const _LevelPickerDialog({
    required this.locale,
    required this.maxLevel,
    required this.initialLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: NotificationTablet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(locale, 'choose_level'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textOnStone,
              ),
            ),
            const SizedBox(height: 18),
            // Scrolls once there are more levels than fit — up to ten.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.55),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var level = maxLevel; level >= 1; level--) ...[
                      if (level != maxLevel) const SizedBox(height: 10),
                      StoneButton(
                        onTap: () => Navigator.of(context).pop(level),
                        selected: level == initialLevel,
                        height: 48,
                        child: Text(
                          '${tr(locale, 'level')} $level — ${levelName(level)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
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
