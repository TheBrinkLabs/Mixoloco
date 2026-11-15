import 'dart:async' show Timer, unawaited;
import 'dart:math' show cos, max, pi, sin;
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart' show LevelPlay;
import '../../../core/i18n/strings.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/ad_service.dart';
import '../../../core/services/audio_settings_provider.dart';
import '../../../core/services/cocktail_mode_provider.dart';
import '../../../core/services/locale_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/outlined_label.dart';
import '../../../core/widgets/ad_break_screen.dart';
import '../../../core/widgets/banner_ad_widget.dart';
import '../../../core/widgets/bar_backdrop.dart';
import '../../../core/widgets/continue_fallback_video_screen.dart';
import '../../../core/widgets/glass_visual.dart';
import '../../../core/widgets/hud_kit.dart';
import '../../../core/widgets/notification_tablet.dart';
import '../../../core/widgets/submenu_kit.dart' show SubmenuColors, RibbonTitle, SubmenuPanel, InsetList, SubmenuRow;
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../../menu/info_level_data.dart';
import '../../shop/widgets/get_credits_dialog.dart';
import '../board_geometry.dart';
import '../mixoloco_game.dart';
import '../providers/game_state_provider.dart';
import 'game_complete_overlay.dart';
import 'level_up_overlay.dart';
import '../widgets/end_game_bonus_button.dart';

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

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver {
  late final MixolocoGame _game;

  /// PopScope blocks every pop attempt by default — including the Android
  /// edge-swipe-back gesture, which was otherwise firing constantly just
  /// from dragging near the screen edge to aim a throw — and this flips
  /// true only for the split second the explicit home button actually
  /// requests one, so that's the only way off this screen.
  bool _allowPop = false;

  bool _showCocktailMenu = false;
  bool _showingAdPlaceholder = false;

  /// The end-of-game +500 credits ad (see [EndGameBonusButton]): one per
  /// game, so held here rather than in the overlay, which can rebuild.
  bool _endBonusClaimed = false;
  bool _endBonusWatching = false;
  bool _showingAdBreak = false;
  bool _showingLevelUp = false;

  /// Bumped on every Shake purchase so BarBackdrop's table image can
  /// react with its own visual shake, in step with the physics jostle.
  final ValueNotifier<int> _tableShakeSignal = ValueNotifier(0);

  /// Restores the bottom banner; captured in initState because Riverpod 3
  /// throws if ref is used inside dispose().
  late final void Function() _restoreBanner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No banner while actually playing — see banner_ad_widget.dart.
    // Deferred a microtask past this build: writing this synchronously
    // here triggers PersistentBannerAd (mounted above the Navigator) to
    // rebuild and initialize adFreeProvider for the first time right
    // inside *this* widget's own still-in-progress mount, which Riverpod
    // flags as "tried to modify a provider while the widget tree was
    // building" — pre-existing, reproducible on an unmodified checkout
    // too, not introduced by the gameplay redesign. The notifier itself
    // is captured now (safe — it's independent of this widget's ref)
    // and only its `.state` write is deferred.
    final bannerNotifier = ref.read(bannerPositionProvider.notifier);
    Future.microtask(() => bannerNotifier.state = BannerPosition.hidden);
    _restoreBanner = () => Future.microtask(() => bannerNotifier.state = BannerPosition.bottom);
    final notifier = ref.read(gameStateProvider.notifier);
    _game = MixolocoGame(
      onMerge: notifier.registerMerge,
      onCocktailComplete: notifier.registerCocktailComplete,
      onGameOver: notifier.registerGameOver,
      onGameComplete: notifier.registerGameComplete,
      onFinalMerge: notifier.registerFinalMerge,
      onThrowCommitted: notifier.advanceQueue,
      onTierSeen: notifier.registerTierSeen,
      initialItems: ref.read(gameStateProvider).placedItems,
      sfxEnabled: ref.read(audioSettingsProvider).effectiveSfxEnabled,
      level: ref.read(gameStateProvider).level,
    );
    // Music now plays through gameplay too (picking up the same playlist
    // position, not restarting) — see MenuScreen.initState for the other
    // side of this and _goHome below for handing it back on the way out.
    // Rooftop/safari tracks once Level 2/3, same as the background swap
    // below.
    ref
        .read(audioSettingsProvider.notifier)
        .playGameMusic(level: ref.read(gameStateProvider).level);
    _autosave = Timer.periodic(const Duration(seconds: 20), (_) => _autosaveTable());
  }

  /// Saves the table every [_autosave] tick, so a crash or force-close
  /// (no `paused` delivered, so nothing else saves) loses at most a few
  /// seconds. Skipped mid level-change or ad, before the table's loaded,
  /// mid-merge or mid-shake, and after the game's over.
  Timer? _autosave;

  void _autosaveTable() {
    if (!mounted || _showingLevelUp || _showingAdBreak || _showingAdPlaceholder) return;
    if (ref.read(gameStateProvider).gameOver) return;
    // Not before the saved table has been rebuilt (it would save an empty
    // one over it), nor mid-merge or mid-shake (items missing or squished).
    if (!_game.isLoaded || _game.isAnimating || _game.shakeActive.value) return;
    unawaited(ref.read(gameStateProvider.notifier).savePlacedItems(_game.capturePlacedItems()));
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
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // `inactive` fires the instant the app starts losing focus — well
      // before `paused` — so kicking the save off here instead of
      // waiting for `paused` gives the (still unawaited, since this
      // override's signature can't block the OS either way) disk write
      // the most possible lead time to actually finish before Android
      // reclaims the process. Harmless to call twice in a row (paused
      // always follows inactive), since this just re-snapshots the same
      // table.
      unawaited(
        ref
            .read(gameStateProvider.notifier)
            .savePlacedItems(_game.capturePlacedItems()),
      );
    } else if (state == AppLifecycleState.resumed) {
      // The OS can silently stop background playback without the app
      // ever finding out — re-assert it on resume rather than leaving
      // silence until the player happens to navigate somewhere that
      // calls playGameMusic() again.
      ref
          .read(audioSettingsProvider.notifier)
          .playGameMusic(level: ref.read(gameStateProvider).level);
      // A Monthly/Yearly ad-removal subscription can lapse while the app
      // was backgrounded — re-check on every resume rather than only on
      // a cold start (see PurchaseService's own doc comment on why this
      // on-device re-check, not instant, is the current limit).
      purchaseService.refresh();
    }
  }

  void _goHome() {
    // Captured here, before teardown starts — not in dispose(), since by
    // then Flame may already have torn down the physics world/bodies
    // this depends on reading (canPop being false the rest of the time
    // means this is also the *only* path off this screen, so there's
    // nowhere else this needs to happen).
    unawaited(
      ref
          .read(gameStateProvider.notifier)
          .savePlacedItems(_game.capturePlacedItems()),
    );
    ref.read(audioSettingsProvider.notifier).playMenuMusic();
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  void _useCherryBomb() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kCherryBombCost)) {
      analyticsService.spendCoins(item: 'bomb', amount: kCherryBombCost);
      _game.cherryBomb();
    }
  }

  /// Debug-only (see kDebugMode guard at the call site) — opens the
  /// collision calibration testbed: a bottom sheet listing every unique
  /// ingredient across all 5 chains, so a physical-vs-visual mismatch
  /// can be checked and fixed one at a time (see MixolocoGame's
  /// debugSpawnIngredient/debugShowerProbes/debugClearTable).
  void _openCollisionTestbed() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14202E),
      builder: (context) => _CollisionTestbedSheet(
        onSpawn: _game.debugSpawnIngredient,
        onShower: _game.debugShowerProbes,
        onClear: _game.debugClearTable,
      ),
    );
  }

  void _useShaker() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kShakerCost)) {
      analyticsService.spendCoins(item: 'shake', amount: kShakerCost);
      _game.shakeTable();
      _tableShakeSignal.value++;
    }
  }

  void _useMegaShaker() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kMegaShakeCost)) {
      analyticsService.spendCoins(item: 'mega_shake', amount: kMegaShakeCost);
      _game.megaShakeTable();
      _tableShakeSignal.value++;
    }
  }

  void _useMiniShots() {
    if (ref.read(gameStateProvider.notifier).spendCredits(kMiniShotsCost)) {
      analyticsService.spendCoins(item: 'slam_mini_shots', amount: kMiniShotsCost);
      _game.clearMiniShots();
    }
  }

  /// The top-left mute button — overrides music/SFX regardless of the
  /// individual Settings toggles, see AudioSettingsNotifier.setAllSoundMuted.
  Future<void> _toggleAllSoundMuted() async {
    final next = !ref.read(audioSettingsProvider).allSoundMuted;
    await ref.read(audioSettingsProvider.notifier).setAllSoundMuted(next);
    if (!mounted) return;
    _game.sfxEnabled = ref.read(audioSettingsProvider).effectiveSfxEnabled;
    if (!next) {
      // Un-muting doesn't resume anything on its own (see that method's
      // own doc) — this screen is the one place that needs to.
      ref
          .read(audioSettingsProvider.notifier)
          .playGameMusic(level: ref.read(gameStateProvider).level);
    }
  }

  /// Credits "+" opens the same quick get-credits popup the main menu's
  /// HUD uses — this is now the only way into the Shop from this screen
  /// (see GetCreditsDialog) — paused/resumed the same way _openSettings
  /// is, since a rewarded ad or purchase flow taking over deserves the
  /// same "nothing moves underneath" treatment.
  Future<void> _openGetCredits() async {
    _game.pauseEngine();
    await showDialog<void>(
      context: context,
      builder: (_) => const GetCreditsDialog(),
    );
    if (!mounted) return;
    _game.resumeEngine();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Same deferral as initState's own write above, and for the same
    // reason — dispose() is on Riverpod's own list of life-cycles a
    // provider write isn't safe to happen synchronously inside.
    _restoreBanner();
    _tableShakeSignal.dispose();
    super.dispose();
  }

  Widget _endBonusButton(AppLocale locale) => EndGameBonusButton(
    claimed: _endBonusClaimed,
    watching: _endBonusWatching,
    onWatch: _watchAdForEndBonus,
    locale: locale,
  );

  void _watchAdForEndBonus() {
    if (_endBonusClaimed || _endBonusWatching) return;
    setState(() => _endBonusWatching = true);
    void grant() {
      ref.read(gameStateProvider.notifier).addAdCredits(kEndGameAdCreditReward);
      if (mounted) setState(() { _endBonusClaimed = true; _endBonusWatching = false; });
    }
    adService.showRewardedAd(
      RewardedAdSlot.shopCredits,
      onReward: grant,
      onDismissedWithoutReward: () {
        if (mounted) setState(() => _endBonusWatching = false);
      },
      // No real ad available — the same short fallback video the Shop and
      // the continue offer use, same reward for watching it through.
      onNotReady: () async {
        if (!mounted) return;
        final watched = await showContinueFallbackVideo(context, ref.read(localeProvider), restoreBannerOnExit: false);
        if (!mounted) return;
        if (watched) {
          grant();
        } else {
          setState(() => _endBonusWatching = false);
        }
      },
    );
  }

  void _watchAdToContinue() {
    setState(() => _showingAdPlaceholder = true);
    adService.showRewardedAd(
      RewardedAdSlot.continueGame,
      onReward: () {
        if (!mounted) return;
        _game.clearMiniShotsAndResume();
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
        final watched = await showContinueFallbackVideo(
          context,
          ref.read(localeProvider),
          // This screen hides the banner for its own entire lifetime
          // (initState) and only its own dispose should bring it back
          // — see showContinueFallbackVideo's doc.
          restoreBannerOnExit: false,
        );
        if (!mounted) return;
        if (watched) {
          _game.clearMiniShotsAndResume();
          ref.read(gameStateProvider.notifier).continueAfterAd();
        } else {
          ref.read(gameStateProvider.notifier).declineContinue();
        }
      },
    );
  }

  /// Every 10,000 points (20,000 once the level's 7th evo is made), a short MREC ad break — the
  /// physics world pauses underneath while it's up so nothing keeps
  /// falling/merging out of view, then resumes once dismissed.
  ///
  /// [_showingAdBreak] is already true (set by the caller before this
  /// runs) for this whole method, including the wait below — blockInput
  /// already covers that flag, so the player can't start a new throw
  /// during the wait either; the staged item just sits there untouched
  /// until [MixolocoGame.resumeEngine] at the end, same as it would
  /// during the ad itself.
  Future<void> _runAdBreak(AppLocale locale) async {
    if (!mounted) return;
    // Ad-free purchase active — mark the milestone handled without ever
    // pausing/showing anything, same as if the ad had just played.
    if (purchaseService.isAdFree) {
      ref.read(gameStateProvider.notifier).acknowledgeAdBreak();
      _showingAdBreak = false;
      return;
    }
    // Let any in-flight merge/cocktail-reveal animation finish playing
    // out first, rather than freezing the engine mid-burst — a merge
    // crossing the score threshold shouldn't cut its own explosion short.
    while (_game.isAnimating) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    // The final merge of the combo (producing the jug/cocktail) may have
    // landed on the very frame that unblocked the wait above — that
    // raises the level past celebratedLevel while this was mid-wait, and
    // the celebration takes over the ad slot entirely in that case (see
    // _runLevelUp's doc). Bail without showing or acknowledging
    // anything; pendingAdBreak stays true and this re-fires on its own
    // once the celebration's done and _showingAdBreak resets below.
    final boardNow = ref.read(gameStateProvider);
    if (boardNow.level > boardNow.celebratedLevel) {
      _showingAdBreak = false;
      return;
    }
    _game.pauseEngine();
    await showAdBreakScreen(context, locale);
    if (!mounted) return;
    ref.read(gameStateProvider.notifier).acknowledgeAdBreak();
    _game.resumeEngine();
    _showingAdBreak = false;
  }

  /// The end-of-level celebration → interstitial sequence (see
  /// level_up_overlay.dart) — same pause/resume treatment as the ad
  /// break, since this also covers the table for several seconds. Also
  /// waits out any in-flight animation first, same as _runAdBreak —
  /// without this, a level completed by the final merge producing the
  /// jug/cocktail (CocktailRevealComponent still mid-flight) would get
  /// its reveal cut short by switchToLevel() clearing the world under it.
  Future<void> _runLevelUp(AppLocale locale, int level) async {
    if (!mounted) return;
    while (_game.isAnimating) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    _game.pauseEngine();
    // Both sides of the reset happen now, while the celebration overlay
    // is about to cover the whole screen — by the time it's dismissed,
    // the table's already cleared and reconfigured for the new level
    // rather than the player seeing it happen.
    ref.read(gameStateProvider.notifier).enterLevel(level);
    _game.switchToLevel(level);
    ref.read(audioSettingsProvider.notifier).playGameMusic(level: level);
    await showLevelUpOverlay(context, locale, level: level);
    if (!mounted) return;
    ref.read(gameStateProvider.notifier).acknowledgeLevelUpCelebration();
    _game.resumeEngine();
    _showingLevelUp = false;
  }

  @override
  Widget build(BuildContext context) {
    final board = ref.watch(gameStateProvider);
    final locale = ref.watch(localeProvider);
    final cocktailModeEnabled = ref.watch(cocktailModeProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final rooftop = barForLevel(board.level) >= 2;
    // Level 3's own table/header-board art hasn't landed yet (more to
    // come) — reuses the rooftop's for now via [rooftop] above, but the
    // background photo itself is ready (see backgroundAssetPathForLevel),
    // so it swaps in as soon as a run ever reaches level 3.
    final backgroundAssetPath = backgroundAssetPathForLevel(board.level);
    final geometry = BoardGeometry.of(screenSize, rooftop: rooftop);
    if (!geometry.isValid) return const SizedBox.shrink();

    _game.updateGeometry(geometry);
    _game.cocktailMode = cocktailModeEnabled;
    _game.syncBoard(board);

    // Level-up takes priority — if both somehow trip on the same frame,
    // the ad break just waits for the next score check once level-up's
    // interstitial has already covered the ad slot for this moment.
    // `>` (not a single bool latch) so every transition re-fires this,
    // not just the first — see BoardState.celebratedLevel's doc for the
    // bug a one-shot flag caused here.
    if (board.level > board.celebratedLevel && !_showingLevelUp) {
      _showingLevelUp = true;
      final targetLevel = board.level;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _runLevelUp(locale, targetLevel),
      );
    } else if (board.pendingAdBreak && !_showingAdBreak && !_showingLevelUp) {
      _showingAdBreak = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runAdBreak(locale));
    }

    final showContinueOffer =
        board.gameOver && !board.continueOfferUsed && !_showingAdPlaceholder;
    final showGameOver =
        board.gameOver && board.continueOfferUsed && !_showingAdPlaceholder;
    final blockInput =
        board.gameOver ||
        _showCocktailMenu ||
        _showingAdPlaceholder ||
        _showingAdBreak ||
        _showingLevelUp;
    // IgnorePointer below only stops a *new* gesture from starting — see
    // MixolocoGame.inputBlocked's own doc for why a drag already in
    // flight needs this second, explicit check too.
    _game.inputBlocked = blockInput;

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
    final iconRowCenterY =
        boardRect.top + boardRect.height * 0.79 - upNudge3pc + upNudge1pc;
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
    final actionTileSize =
        (actionRowRight -
            actionRowLeft -
            actionTileGap * (actionTileCount - 1)) /
        actionTileCount;
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
    final progressTabWidth =
        (screenSize.width - progressTabMargin * 2 - progressTabGap * 7) / 8;
    final progressTabHeight = (progressTabWidth / kEmptyTabAspect) * 1.2;
    // Same gap above the row (to the header board) as between each tab,
    // rather than a bigger one — reads as one consistently-spaced group.
    final progressTabsTop = boardRect.top + boardRect.height + progressTabGap;

    return PopScope(
      canPop: _allowPop,
      child: Scaffold(
        body: BarBackdrop(
          backgroundAssetPath: backgroundAssetPath,
          shakeTrigger: _tableShakeSignal,
          rooftop: rooftop,
          tableFinish: tableFinishForLevel(board.level),
          night: isAfterDarkLevel(board.level),
          child: Stack(
            children: [
              // Logo + status banner — top center. Tapping the logo goes
              // home. Positioned (not Align) so it can shift above the
              // natural safe-area top by the 1%-of-screen nudge.
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
                        GestureDetector(
                          onTap: _goHome,
                          child: Image.asset(
                            'assets/images/menu_logo_sticker.png',
                            height: 44,
                            // See GlassVisual's matching comment.
                            cacheHeight: (44 * MediaQuery.devicePixelRatioOf(context)).round(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _GameStatusBanner(board: board, locale: locale),
                      ],
                    ),
                  ),
                ),
              ),
              // Mute button — very top-left corner, overriding whatever
              // the individual music/SFX Settings toggles say (see
              // AudioSettingsNotifier.setAllSoundMuted).
              Positioned(
                left: 0,
                top: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12, top: 20),
                    child: _SoundToggleButton(
                      muted: ref.watch(audioSettingsProvider).allSoundMuted,
                      onTap: _toggleAllSoundMuted,
                    ),
                  ),
                ),
              ),
              // Credits/Score pills — same navy-pill language as the main
              // menu's HUD (see hud_kit.dart), at the same anchor points
              // the old plain-text stats used.
              Positioned(
                left: statLeftInset - 38,
                top: statTop - 17,
                child: _GameCreditsPill(
                  credits: board.credits,
                  onBuyCredits: _openGetCredits,
                ),
              ),
              Positioned(
                right: statLeftInset - 40,
                top: statTop - 17,
                child: _GameScorePill(score: board.score),
              ),
              Positioned(
                left: actionRowLeft,
                top: iconRowCenterY - actionTileSize / 2,
                child: _PowerUpTile(
                  // Same underlying sweep-and-delete power everywhere
                  // (see MixolocoGame.cherryBomb), reskinned per level to
                  // match whatever that level's own tier-0 ingredient
                  // actually is — Piazza's is blackcurrant, Jungle's is
                  // a sugar cube, not a cherry.
                  asset: switch (evolutionChainForLevel(board.level).first.id) {
                    'sugar_cube' => 'assets/images/ingredient_sugar_cube.png',
                    'blackcurrant' => 'assets/images/ingredient_blackcurrant.png',
                    _ => 'assets/images/game/i_cherry.png',
                  },
                  size: actionTileSize,
                  label: tr(locale, switch (evolutionChainForLevel(board.level).first.id) {
                    'sugar_cube' => 'sugar_bomb_label',
                    'blackcurrant' => 'currant_bomb_label',
                    _ => 'cherry_bomb_label',
                  }),
                  cost: kCherryBombCost,
                  enabled: board.credits >= kCherryBombCost,
                  onTap: _useCherryBomb,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap),
                top: iconRowCenterY - actionTileSize / 2,
                child: _PowerUpTile(
                  asset: 'assets/images/game/p_shaker.png',
                  size: actionTileSize,
                  label: tr(locale, 'shake_label'),
                  cost: kShakerCost,
                  enabled: board.credits >= kShakerCost,
                  onTap: _useShaker,
                  activeGlow: _game.shakeActive,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 2,
                top: iconRowCenterY - actionTileSize / 2,
                child: _PowerUpTile(
                  asset: 'assets/images/game/p_shaker.png',
                  size: actionTileSize,
                  label: tr(locale, 'mega_shake_label'),
                  cost: kMegaShakeCost,
                  enabled: board.credits >= kMegaShakeCost,
                  onTap: _useMegaShaker,
                  badgeEmoji: '\u{1F4AA}',
                  activeGlow: _game.shakeActive,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 3,
                top: iconRowCenterY - actionTileSize / 2,
                child: _PowerUpTile(
                  asset: 'assets/images/game/i_vodka.png',
                  size: actionTileSize,
                  label: tr(locale, 'mini_shots_label'),
                  cost: kMiniShotsCost,
                  enabled: board.credits >= kMiniShotsCost,
                  onTap: _useMiniShots,
                  noSign: true,
                ),
              ),
              Positioned(
                left: actionRowLeft + (actionTileSize + actionTileGap) * 4,
                top: iconRowCenterY - actionTileSize / 2,
                child: _PowerUpTile(
                  asset: 'assets/images/game/p_cosmopolitan.png',
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
                  blueTile: true,
                ),
              ),
              // Cocktail Mode off: cocktails can still be made/scored
              // (the order card/Cocktail Menu above are untouched), but
              // this progress-tracking row doesn't mean anything when
              // completing them isn't what levels you up anymore.
              if (cocktailModeEnabled)
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
                top:
                    screenSize.height *
                    tableSurfaceNearFraction(
                      screenSize.width,
                      screenSize.height,
                      rooftop: rooftop,
                    ),
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _NextCard(next: board.upcoming.first, locale: locale),
                ),
              ),
              Positioned(
                left: 0,
                right: 16,
                top:
                    screenSize.height *
                    tableSurfaceNearFraction(
                      screenSize.width,
                      screenSize.height,
                      rooftop: rooftop,
                    ),
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _OrderCard(board: board),
                ),
              ),
              if (showContinueOffer)
                _ContinueOfferOverlay(
                  onWatchAd: _watchAdToContinue,
                  onEndGame: () =>
                      ref.read(gameStateProvider.notifier).declineContinue(),
                  locale: locale,
                ),
              if (showGameOver)
                if (board.gameCompleted)
                  GameCompleteOverlay(board: board, onHome: _goHome, locale: locale, bonus: _endBonusButton(locale))
                else
                  _GameOverOverlay(board: board, onHome: _goHome, locale: locale, bonus: _endBonusButton(locale)),
              if (_showingAdPlaceholder) _AdPlaceholderOverlay(locale: locale),
              if (_showCocktailMenu)
                _CocktailMenuOverlay(
                  onClose: () => setState(() => _showCocktailMenu = false),
                ),
              if (kDebugMode)
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _DebugCollisionTestbedButton(onTap: _openCollisionTestbed),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One navy HUD pill — same look as the main menu's own HUD row (see
/// hud_kit.dart), at fixed pixel sizes per the gameplay redesign handoff
/// rather than the menu's frame-relative scale (this screen's HUD chrome
/// was already fixed/boardRect-relative sizes, never the menu's 390-wide
/// frame system, so fixed sizes here stay consistent with everything
/// else on it).
class _GamePill extends StatelessWidget {
  final double leftPad;
  final double rightPad;
  final Widget badge;
  final double badgeSize;
  final double badgeLeft;
  final double badgeTop;
  final Widget content;
  final Widget? topRight;

  const _GamePill({
    required this.leftPad,
    required this.rightPad,
    required this.badge,
    required this.badgeSize,
    required this.badgeLeft,
    required this.badgeTop,
    required this.content,
    this.topRight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      constraints: BoxConstraints(minWidth: leftPad + rightPad + 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: HudColors.hudBorder, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.hudNavyTop, HudColors.hudNavyBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 1,
            left: 10,
            right: 10,
            child: Container(
              height: 2,
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
            child: SizedBox(width: badgeSize, height: badgeSize, child: badge),
          ),
          ?topRight,
        ],
      ),
    );
  }
}

/// The credits pill — coin badge, value, and a "+" that's now the only
/// way into the Shop from this screen (see GameScreen._openGetCredits).
class _GameCreditsPill extends StatelessWidget {
  final int credits;
  final VoidCallback onBuyCredits;
  const _GameCreditsPill({required this.credits, required this.onBuyCredits});

  static String _formatCredits(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return _GamePill(
      leftPad: 38,
      rightPad: 30,
      badgeSize: 38,
      badgeLeft: -4,
      badgeTop: -4,
      badge: layeredCircle(
        size: 38,
        rings: [
          HudRing(width: 2, color: HudColors.coinRim),
          HudRing(width: 4, color: Colors.white.withValues(alpha: 0.35)),
        ],
        fill: DecoratedBox(
          // Blue (was gold, same as the coinTop/Mid/Bottom art it was
          // sitting behind) and the real coins logo — matches the home
          // screen's credits pill, the gold coins were hard to make out
          // against a gold badge.
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
          // coins.png's own canvas has a lot of transparent padding
          // around the actual coin graphic (a wide, short canvas with a
          // roughly-square coin stack centred in it) — BoxFit.contain
          // against that canvas left the coin stack itself tiny no
          // matter how big the box got. BoxFit.cover (clipped to the
          // circle) instead scales up until the canvas's *short* side
          // fills the box, then crops the excess width symmetrically,
          // which — since the coin art sits close to the canvas's own
          // centre — crops away the padding rather than the coins,
          // actually filling the badge.
          child: ClipOval(
            child: Image.asset(
              'assets/images/coins.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              // This badge never renders bigger than 38 logical px —
              // see GlassVisual's matching comment.
              cacheWidth: (38 * MediaQuery.devicePixelRatioOf(context)).round(),
            ),
          ),
        ),
      ),
      content: OutlinedLabel(
        text: _formatCredits(credits),
        fontSize: 18,
        fill: Colors.white,
        stroke: HudColors.hudBorder,
        strokeWidth: 3,
      ),
      topRight: Positioned(
        top: 2,
        right: 2,
        child: GestureDetector(
          onTap: onBuyCredits,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: HudColors.plusBorder, width: 2),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [HudColors.plusTop, HudColors.plusBottom],
              ),
            ),
            alignment: Alignment.center,
            child: const OutlinedLabel(
              text: '+',
              fontSize: 20,
              fill: Colors.white,
              stroke: HudColors.plusBorder,
              strokeWidth: 3,
            ),
          ),
        ),
      ),
    );
  }
}

/// The score pill — trophy badge, value. Pulses once and counts up its
/// own digits whenever [score] increases (see _AnimatedScoreLabel) —
/// purely a rendering reaction to the same `board.score` this screen
/// already watches, not a change to how/when score itself is awarded.
class _GameScorePill extends StatelessWidget {
  final int score;
  const _GameScorePill({required this.score});

  @override
  Widget build(BuildContext context) {
    return _GamePill(
      leftPad: 40,
      rightPad: 12,
      badgeSize: 50,
      badgeLeft: -10,
      badgeTop: -12,
      badge: ShadowedAsset(
        path: 'assets/images/icon_best_scores.png',
        width: 50,
        shadows: [
          SpriteShadow(
            offset: const Offset(0, 2),
            color: Colors.white.withValues(alpha: 0.9),
          ),
          SpriteShadow(
            offset: const Offset(0, 3),
            blur: 4,
            color: Colors.black.withValues(alpha: 0.3),
          ),
        ],
      ),
      content: _AnimatedScoreLabel(score: score),
    );
  }
}

/// The gameplay screen's top-left mute toggle — same gold-rim-on-blue-plate
/// language as the main menu's Settings button (see MenuScreen's
/// _SettingsButton), with a red strike-through bar drawn across the
/// speaker icon when muted.
class _SoundToggleButton extends StatelessWidget {
  final bool muted;
  final VoidCallback onTap;
  const _SoundToggleButton({required this.muted, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: layeredCircle(
        size: 40,
        shadow: [BoxShadow(color: HudColors.hudBorder, offset: const Offset(0, 3))],
        rings: [
          HudRing(width: 2, color: HudColors.hudBorder),
          HudRing(width: 3, color: HudColors.goldRim),
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                ShadowedAsset(
                  path: 'assets/images/sound.png',
                  width: 24,
                  shadows: [
                    SpriteShadow(offset: const Offset(0, 2), blur: 2, color: Colors.black.withValues(alpha: 0.4)),
                  ],
                ),
                if (muted)
                  Transform.rotate(
                    angle: -pi / 4,
                    child: Container(
                      width: 28,
                      height: 3.5,
                      decoration: BoxDecoration(
                        color: HudColors.badgeRed,
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: Colors.white, width: 0.8),
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

class _AnimatedScoreLabel extends StatefulWidget {
  final int score;
  const _AnimatedScoreLabel({required this.score});

  @override
  State<_AnimatedScoreLabel> createState() => _AnimatedScoreLabelState();
}

class _AnimatedScoreLabelState extends State<_AnimatedScoreLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void didUpdateWidget(covariant _AnimatedScoreLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.score > oldWidget.score) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) =>
          Transform.scale(scale: _scale.value, child: child),
      child: OutlinedLabel(
        text: '${widget.score}',
        fontSize: 18,
        fill: Colors.white,
        stroke: HudColors.hudBorder,
        strokeWidth: 3,
      ),
    );
  }
}

/// One power-up tray tile — cream (blue for Menu) rounded tile with the
/// icon, a label below it, and (for the two credit-spending ones) a
/// price chip overlapping its bottom edge. [badge] adds the small "x2"
/// corner tag (Mega-Shake), [noSign] draws the red "can't do this right
/// now" ring over the icon (Mini-Shots), [activeGlow] — when provided —
/// shows a pulsing gold glow while true (Shake/Mega-Shake, driven by
/// MixolocoGame.shakeActive). Affordability/enabled logic and onTap are
/// unchanged from before — only how the tile is painted changed.
class _PowerUpTile extends StatefulWidget {
  final String asset;
  final double size;
  final String label;
  final int? cost;
  final bool enabled;
  final VoidCallback onTap;
  final String? badgeEmoji;
  final bool noSign;
  final bool blueTile;
  final ValueListenable<bool>? activeGlow;

  const _PowerUpTile({
    required this.asset,
    required this.size,
    required this.label,
    this.cost,
    required this.enabled,
    required this.onTap,
    this.badgeEmoji,
    this.noSign = false,
    this.blueTile = false,
    this.activeGlow,
  });

  @override
  State<_PowerUpTile> createState() => _PowerUpTileState();
}

class _PowerUpTileState extends State<_PowerUpTile> {
  bool _pressed = false;
  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final glow = widget.activeGlow;
    final tile = glow == null
        ? _tile()
        : ValueListenableBuilder<bool>(
            valueListenable: glow,
            builder: (context, active, child) =>
                _GlowWrap(active: active, size: widget.size, child: child!),
            child: _tile(),
          );
    // GameScreen rebuilds on every board change (a merge, a credit
    // spend, a score tick) — this tile's own look only ever depends on
    // its own widget.enabled/blueTile/activeGlow, not on most of what
    // triggers those rebuilds. A RepaintBoundary isolates its Opacity/
    // gradient/shadow painting as its own cached compositor layer so an
    // unrelated board change doesn't force it to re-rasterize, same
    // reasoning as BarBackdrop's table-tint boundary.
    return RepaintBoundary(
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: tile,
        ),
      ),
    );
  }

  Widget _tile() {
    final s = widget.size;
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.45,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: s,
              height: s,
              padding: EdgeInsets.all(s * 0.1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(s * 0.28),
                border: Border.all(color: HudColors.hudBorder, width: 2),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: widget.blueTile
                      ? const [Color(0xFF9FDCF0), Color(0xFF4FA9D6)]
                      : const [HudColors.creamTop, HudColors.creamBottom],
                ),
                boxShadow: const [
                  BoxShadow(color: HudColors.hudBorder, offset: Offset(0, 3)),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 0,
                    left: s * 0.08,
                    right: s * 0.08,
                    child: Container(
                      height: 2,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: s * 0.42,
                        child: Center(
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ShadowedAsset(
                                path: widget.asset,
                                width: s * 0.42,
                                shadows: [
                                  SpriteShadow(
                                    offset: const Offset(0, 2),
                                    blur: 2,
                                    color: Colors.black.withValues(alpha: 0.25),
                                  ),
                                ],
                              ),
                              if (widget.noSign) _NoSign(size: s * 0.58),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: s * 0.22,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: OutlinedLabel(
                            text: widget.label.toUpperCase(),
                            fontSize: 11.5,
                            fill: Colors.white,
                            stroke: HudColors.labelStroke,
                            strokeWidth: 3,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.badgeEmoji != null)
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4.75,
                    vertical: 0.95,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6.65),
                    border: Border.all(
                      color: const Color(0xFF7A2408),
                      width: 1.9,
                    ),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8F3D), Color(0xFFFF5A22)],
                    ),
                  ),
                  child: Text(widget.badgeEmoji!, style: const TextStyle(fontSize: 12.35, height: 1.1)),
                ),
              ),
            if (widget.cost != null)
              Positioned(
                bottom: -9,
                left: 0,
                right: 0,
                child: Center(
                  child: _PriceChip(
                    cost: widget.cost!,
                    affordable: widget.enabled,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The small gold-coin-and-price pill overlapping a power-up tile's
/// bottom edge.
class _PriceChip extends StatelessWidget {
  final int cost;
  final bool affordable;
  const _PriceChip({required this.cost, required this.affordable});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: HudColors.hudNavyBottom,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: HudColors.hudBorder, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          layeredCircle(
            size: 12,
            rings: [HudRing(width: 1, color: HudColors.coinRim)],
            fill: const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [HudColors.coinTop, HudColors.coinBottom],
                ),
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            '$cost',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              // A dulled red (not the plain white every other pill's
              // numbers use) when this tile can't currently be afforded —
              // same signal the old in-tile cost text never had a way to
              // show, since it was always a flat colour regardless.
              color: affordable ? Colors.white : const Color(0xFFFF9A8A),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pulsing gold halo around a power-up tile while its effect is still
/// running (Shake/Mega-Shake) — a no-op wrapper (returns [child] as-is)
/// whenever [active] is false, so idle tiles pay nothing extra.
class _GlowWrap extends StatefulWidget {
  final bool active;
  final double size;
  final Widget child;
  const _GlowWrap({
    required this.active,
    required this.size,
    required this.child,
  });

  @override
  State<_GlowWrap> createState() => _GlowWrapState();
}

class _GlowWrapState extends State<_GlowWrap>
    with SingleTickerProviderStateMixin {
  // Only ticks while the glow is showing — an always-repeating
  // controller kept scheduling frames for the whole game.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _GlowWrap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size * 0.28 + 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD23F).withValues(alpha: 0.4 + 0.3 * t),
                blurRadius: 6 + 6 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// The red "can't do this right now" ring drawn over the Mini-Shots
/// tile's icon.
class _NoSign extends StatelessWidget {
  final double size;
  const _NoSign({required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _NoSignPainter()),
  );
}

class _NoSignPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final outerEdge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.09;
    canvas.drawCircle(center, radius, outerEdge);
    final ring = Paint()
      ..color = const Color(0xFFE3262B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.16;
    canvas.drawCircle(center, radius * 0.82, ring);
    final bar = Paint()
      ..color = const Color(0xFFE3262B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.16
      ..strokeCap = StrokeCap.round;
    final angle = 45 * pi / 180;
    final offset = Offset(radius * 0.7 * cos(angle), radius * 0.7 * sin(angle));
    canvas.drawLine(center - offset, center + offset, bar);
  }

  @override
  bool shouldRepaint(covariant _NoSignPainter oldDelegate) => false;
}

class _OrderCard extends StatelessWidget {
  final BoardState board;
  const _OrderCard({required this.board});

  @override
  Widget build(BuildContext context) {
    final order = board.order;
    if (order == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      // Capped (not just a min) so a long translated cocktail name (e.g.
      // Italian "Cosmopolitan") can't keep widening this pill into the
      // Next card docked on the other side of the table — the name
      // itself shrinks to fit instead, via the FittedBox below. The cap
      // itself grows with ingredient count (each _OrderIcon costs ~38px)
      // so a 4-ingredient recipe like Hugo Spritz still fits all its
      // icons instead of clipping — 150 was only ever sized for 2-3.
      constraints: BoxConstraints(minWidth: 120, maxWidth: max(150.0, order.ingredientIds.length * 38.0 + 28.0)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HudColors.hudBorder, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.hudNavyTop, HudColors.hudNavyBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 122,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: OutlinedLabel(
                text: order.name,
                fontSize: 13,
                fill: Colors.white,
                stroke: HudColors.hudBorder,
                strokeWidth: 2,
              ),
            ),
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
  const _ProgressTabsRow({
    required this.board,
    required this.tabWidth,
    required this.tabHeight,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    final recipes = cocktailRecipesForLevel(board.level);
    final capstone = evolutionChainForLevel(board.level).last;
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
  const _ProgressTab({
    required this.imagePath,
    required this.completed,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(width * 0.3),
              border: Border.all(color: HudColors.hudBorder, width: 2),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: completed
                    ? const [Color(0xFFE8F8DC), Color(0xFFC7ECB0)]
                    : const [HudColors.creamTop, HudColors.creamBottom],
              ),
              boxShadow: const [
                BoxShadow(color: HudColors.hudBorder, offset: Offset(0, 3)),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: width * 0.12,
                  right: width * 0.12,
                  child: Container(
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                // Fully visible while it's still something to aim for;
                // fades back once it's done and the checkmark badge
                // takes over as the main thing to notice.
                Center(
                  child: Opacity(
                    opacity: completed ? 0.4 : 1.0,
                    // Halved from 0.16 — the source cocktail photos used
                    // to carry a lot of their own transparent padding on
                    // top of this inset, compounding into icons that
                    // read as tiny; now that those are cropped tight to
                    // their own content (see assets/images/*.png's own
                    // history), a smaller inset here is enough to keep
                    // the tile's rounded corners clear.
                    child: Padding(
                      padding: EdgeInsets.all(width * 0.08),
                      child: Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      // See GlassVisual's matching comment.
                      cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
                    ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (completed)
            Positioned(
              top: -6,
              right: -6,
              child: layeredCircle(
                size: 20,
                rings: [HudRing(width: 2, color: HudColors.plusBorder)],
                fill: DecoratedBox(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [HudColors.plusTop, HudColors.plusBottom],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
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

  String? get _message =>
      board.gameOver ? tr(locale, 'table_full_banner') : null;

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
                border: Border.all(
                  color: AppColors.coral.withValues(alpha: 0.6),
                ),
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
  Widget build(BuildContext context) =>
      GlassVisual(ingredient: ingredient, size: 32);
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
    // A plain inline Row (text, gap, disc) rather than the handoff's own
    // "disc overflowing far past the pill's right edge" — that left a
    // big empty gap between "NEXT" and the disc, which on a real device
    // pushed the disc far enough right to land behind the Order card
    // (painted after this in the Stack) whenever one was showing. The
    // disc (58) is still a few px taller than the pill (52) for a slight
    // badge-like overflow — Container doesn't clip by default, so that
    // needs no extra Clip.none plumbing.
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 18, right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: HudColors.hudBorder, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [HudColors.hudNavyTop, HudColors.hudNavyBottom],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          OutlinedLabel(
            text: tr(locale, 'next').toUpperCase(),
            fontSize: 18,
            fill: Colors.white,
            stroke: HudColors.hudBorder,
            strokeWidth: 3,
            letterSpacing: 1.1,
          ),
          const SizedBox(width: 10),
          layeredCircle(
            size: 58,
            shadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                offset: const Offset(0, 4),
              ),
            ],
            rings: [
              HudRing(width: 2, color: HudColors.hudBorder),
              HudRing(
                width: 3,
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
              child: Center(child: GlassVisual(ingredient: next, size: 36)),
            ),
          ),
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
  const _ContinueOfferOverlay({
    required this.onWatchAd,
    required this.onEndGame,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          child: NotificationTablet(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(locale, 'table_full_title'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textOnStone,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(locale, 'table_full_body'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textOnStoneMuted,
                  ),
                ),
                const SizedBox(height: 18),
                StoneButton(
                  onTap: onWatchAd,
                  width: 230,
                  height: 50,
                  child: Text(
                    tr(locale, 'watch_ad_clear'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                StoneButton(
                  onTap: onEndGame,
                  width: 230,
                  height: 46,
                  child: Text(
                    tr(locale, 'end_game'),
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
              Text(
                tr(locale, 'ad_playing'),
                style: const TextStyle(
                  color: AppColors.textLight,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Debug-only entry point (see kDebugMode guard at its call site) for
/// the collision calibration testbed — a small, unobtrusive wrench FAB
/// rather than anything styled to match the real HUD, since this never
/// ships to a real player.
class _DebugCollisionTestbedButton extends StatelessWidget {
  final VoidCallback onTap;
  const _DebugCollisionTestbedButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(color: Colors.redAccent, width: 2),
        ),
        child: const Icon(Icons.build_rounded, color: Colors.redAccent, size: 20),
      ),
    );
  }
}

/// The collision calibration testbed's own panel — spawn any ingredient
/// from any level, shower small probe balls around it, and compare the
/// real fixture outline (drawn by IngredientBodyComponent.debugShowFixtures)
/// against its sprite. Debug-only, intentionally plain styling.
///
/// The search box exists purely to make driving this via adb (scripted
/// taps, no real finger) reliable — scrolling a 46-row list and guessing
/// a row's pixel offset from a screenshot is exactly the kind of thing
/// that silently taps the row above or below the intended one. Typing the
/// id and tapping the single filtered match removes that whole class of
/// mistake, which matters a lot across a 46-ingredient tuning pass.
class _CollisionTestbedSheet extends StatefulWidget {
  final void Function(String ingredientId) onSpawn;
  final void Function({String probeId, int count}) onShower;
  final VoidCallback onClear;
  const _CollisionTestbedSheet({
    required this.onSpawn,
    required this.onShower,
    required this.onClear,
  });

  @override
  State<_CollisionTestbedSheet> createState() => _CollisionTestbedSheetState();
}

class _CollisionTestbedSheetState extends State<_CollisionTestbedSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = _uniqueIngredientsByFirstLevel();
    final query = _query.trim().toLowerCase();
    final entries = query.isEmpty
        ? allEntries
        : allEntries
              .where(
                (e) =>
                    e.$1.id.toLowerCase().contains(query) ||
                    e.$1.label.toLowerCase().contains(query),
              )
              .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Collision Testbed',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  TextButton(
                    onPressed: () => widget.onShower(),
                    child: const Text('Shower probes'),
                  ),
                  TextButton(onPressed: widget.onClear, child: const Text('Clear')),
                  TextButton(
                    onPressed: LevelPlay.launchTestSuite,
                    child: const Text('Ads'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search id or name…',
                  hintStyle: TextStyle(color: Colors.white38),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                children: [
                  for (final entry in entries)
                    ListTile(
                      dense: true,
                      title: Text(entry.$1.label, style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                        '${entry.$1.id} · tier ${entry.$1.tier} · ${entry.$2}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      onTap: () => widget.onSpawn(entry.$1.id),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Every ingredient id across all 5 chains, deduped to wherever it
  /// first appears (same reuse pattern as findIngredientById itself),
  /// paired with that first-appearance level's name — so the list reads
  /// as "every ingredient, once" rather than 65 rows with duplicates.
  static List<(Ingredient, String)> _uniqueIngredientsByFirstLevel() {
    final seenIds = <String>{};
    final result = <(Ingredient, String)>[];
    for (final level in kInfoLevels) {
      for (final ingredient in level.chain) {
        if (seenIds.add(ingredient.id)) {
          result.add((ingredient, level.name));
        }
      }
    }
    return result;
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
    final panelWidth = screenSize.width * 0.88 > 420
        ? 420.0
        : screenSize.width * 0.88;
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
                constraints: BoxConstraints(
                  maxHeight: screenSize.height * 0.82,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: SubmenuColors.gold, width: 3),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [SubmenuColors.panelTop, SubmenuColors.panelBottom],
                  ),
                  boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 8))],
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
                          _MenuTitleTile(
                            title: tr(locale, 'cocktail_menu'),
                            icon: Icons.local_florist_rounded,
                            width: rowWidth,
                            height: rowHeight,
                          ),
                          const SizedBox(height: 8),
                          for (final recipe in cocktailRecipesForLevel(
                            board.level,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _MenuListRow(
                                recipe: recipe,
                                width: rowWidth,
                                height: rowHeight,
                                affordable: board.credits >= recipe.price,
                                isActive: board.order?.id == recipe.id,
                                madeBefore: board.completedCocktailIds
                                    .contains(recipe.id),
                                locale: locale,
                                onBuy: () {
                                  final bought = ref
                                      .read(gameStateProvider.notifier)
                                      .buyCocktail(recipe);
                                  if (bought) onClose();
                                },
                              ),
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
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: AppColors.textLight,
                            size: 18,
                          ),
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

/// The overlay's own title tile — gold-rimmed blue, matching
/// [_MenuListRow] below it, replacing the old WoodTitlePlank art.
class _MenuTitleTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double width;
  final double height;
  const _MenuTitleTile({required this.title, required this.icon, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SubmenuColors.gold, width: 2),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom],
        ),
        boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: SubmenuColors.gold, size: height * 0.4),
          const SizedBox(width: 10),
          OutlinedLabel(text: title.toUpperCase(), fontSize: height * 0.34, fill: Colors.white, stroke: SubmenuColors.ring, strokeWidth: 3),
        ],
      ),
    );
  }
}

/// One cocktail order's own row — a gold-rimmed blue tile (replacing
/// the old menu_board.png plank art), same "thick" full-height
/// proportions this screen's rows always used (the earlier app-wide
/// blue-tile thinning pass never touched the in-game Cocktail Menu).
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
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isActive ? AppColors.mint : SubmenuColors.gold, width: isActive ? 3 : 2),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [SubmenuColors.cardTop, SubmenuColors.cardBottom],
            ),
            boxShadow: [BoxShadow(color: SubmenuColors.ring, offset: const Offset(0, 3))],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    recipe.assetPath,
                    width: height * 0.7,
                    height: height * 0.7,
                    fit: BoxFit.contain,
                    // See GlassVisual's matching comment.
                    cacheWidth: (height * 0.7 * 2.2 * MediaQuery.devicePixelRatioOf(context)).round(),
                    // Some Level 3 recipes' art hasn't landed yet —
                    // see cocktails_screen.dart's matching comment.
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.local_bar_rounded,
                      size: height * 0.5,
                      color: SubmenuColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          recipe.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: Colors.white),
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
                          decoration: const BoxDecoration(
                            color: AppColors.mint,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isActive)
                  Text(
                    tr(locale, 'active').toUpperCase(),
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 13, color: AppColors.mint),
                  )
                else
                  Text(
                    '${recipe.price}',
                    style: const TextStyle(fontFamily: 'Lilita One', fontSize: 16, color: SubmenuColors.gold),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Deliberately light dim — per feedback the table/board behind should
/// stay "quite visible" rather than the old opaque-feeling card overlay,
/// since the whole point is the player can still see how the game ended.
/// A single gold-rimmed navy plaque (score, level, cocktails made, and
/// this run's own highest evolution reached — see
/// BoardState.runHighestTier) in the same ribbon-title/inset-row shape
/// as Settings, replacing the old per-locale "GAME OVER" banner photos
/// and wood-plank stat rows — this screen reads [tr] for its header
/// text now instead of needing a baked-text image per language. The
/// ribbon sits overlapping the panel's own top edge, same as
/// SubmenuScaffold's screens, rather than floating above it with a gap.
/// A "NEW BEST SCORE!" callout fills the space between the ribbon and
/// the stat rows when [BoardState.isNewHighScore] is set; Main Menu —
/// the single way out, there's no more Play Again here, restarting in
/// place read as skipping past what just happened — lives inside the
/// same panel, right under the stats, rather than as its own separate
/// button below it.
class _GameOverOverlay extends StatelessWidget {
  final BoardState board;
  final VoidCallback onHome;
  final AppLocale locale;
  final Widget bonus;
  const _GameOverOverlay({
    required this.board,
    required this.onHome,
    required this.locale,
    required this.bonus,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    const sideMargin = 28.0;
    final panelWidth = screenWidth - sideMargin * 2;
    final chain = evolutionChainForLevel(board.level);
    final maxEvoIngredient =
        chain[board.runHighestTier.clamp(0, chain.length - 1)];
    const valueStyle = TextStyle(fontFamily: 'Lilita One', fontSize: 18, color: SubmenuColors.gold);
    // The live HUD (credits/score pills, the 5 action tiles, the 8-tab
    // progress row) still shows through this overlay's partial dim —
    // same math GameScreen.build uses to place that row itself, reused
    // here so the plaque starts clear of it rather than overlapping, no
    // matter the screen size.
    final boardRect = headerBoardRect(screenSize);
    final progressTabWidth = (screenWidth - 20 - 21) / 8;
    final progressTabHeight = (progressTabWidth / kEmptyTabAspect) * 1.2;
    final topClearance = boardRect.top + boardRect.height + 3 + progressTabHeight + 14;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.28),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: topClearance),
              // The ribbon overlaps the panel's own top edge (which
              // reserves exactly this much top padding for it — see
              // SubmenuPanel) instead of sitting above it with a gap,
              // same "touching" look as every SubmenuScaffold screen's
              // own title/panel pair — a 24px relative offset between
              // the two, matching SubmenuScaffold's own ribbonTop/
              // panelTop spacing.
              Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: SizedBox(
                      width: panelWidth,
                      child: SubmenuPanel(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Reserved space right under the ribbon for
                            // the "NEW BEST SCORE!" callout — only filled
                            // when BoardState.isNewHighScore is actually
                            // set, otherwise the stats start right under
                            // the ribbon with just the panel's own
                            // padding.
                            if (board.isNewHighScore) ...[
                              OutlinedLabel(
                                text: tr(locale, 'new_best_score'),
                                fontSize: 20,
                                fill: SubmenuColors.gold,
                                stroke: SubmenuColors.goldEdge,
                                strokeWidth: 4,
                              ),
                              const SizedBox(height: 14),
                            ],
                            InsetList(
                              rows: [
                                SubmenuRow(
                                  icon: Icons.star_rounded,
                                  label: tr(locale, 'score_label'),
                                  trailing: Text('${board.score}', style: valueStyle),
                                ),
                                SubmenuRow(
                                  icon: Icons.flag_rounded,
                                  label: tr(locale, 'level'),
                                  trailing: Text('${board.level}', style: valueStyle),
                                ),
                                SubmenuRow(
                                  icon: Icons.auto_awesome_rounded,
                                  label: tr(locale, 'max_evo_label'),
                                  trailing: GlassVisual(ingredient: maxEvoIngredient, size: 34, applyDisplayScale: false),
                                ),
                                SubmenuRow(
                                  icon: Icons.local_bar_rounded,
                                  label: tr(locale, 'cocktails_made_label'),
                                  trailing: Text('${board.cocktailsMade}', style: valueStyle),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            bonus,
                            const SizedBox(height: 10),
                            StoneButton(
                              onTap: onHome,
                              height: 50,
                              child: Text(
                                tr(locale, 'main_menu'),
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.black),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RibbonTitle(text: tr(locale, 'game_over')),
                ],
              ),
              // Clears the table's own front-face Next/Order cards docked
              // at the very bottom (see the Positioned pair above in
              // GameScreen.build) — plain bottom SafeArea padding alone
              // isn't enough since those cards aren't a system inset.
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }
}
