import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/cocktail_mode_provider.dart';
import '../../../core/services/purchase_service.dart';
import '../../../data/models/cocktail_recipe.dart';
import '../../../data/models/ingredient.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/game_save_service.dart';
import '../../../data/services/high_scores_service.dart';
import '../../../data/services/progression_service.dart';

/// Score for a same-tier merge at [tier] — 10 for the very first tier,
/// doubling each step up ("For the lowest evolution items 10 point, next
/// 20, next 40, doubling each time").
int scoreForMerge(int tier) => 10 * (1 << tier);

/// Score for completing a cocktail order — 10x its credit price, so a
/// cocktail always pays back more in score than it cost in credits.
int scoreForCocktail(CocktailRecipe recipe) => recipe.price * 10;

/// The highest level with content — once a run reaches this, there's
/// nothing further to advance to (see _checkLevelUp).
const kMaxLevel = kLevelCount;

/// Credits awarded for reaching a new highest evolution tier, ever.
/// Halved from 200 — per feedback, climbing a whole 12-step chain (2400
/// credits at the old rate) handed out roughly 1000-1200 more than
/// buying every cocktail on that chain actually costs, well past
/// "enough to afford what you've unlocked" into "credits piling up
/// regardless."
const kTierUnlockReward = 100;

/// Credits awarded for every [kScoreCreditThreshold] points of score
/// reached within a single game — a repeatable, per-run milestone
/// (unlike the once-ever highest-tier reward), so it resets each game
/// along with the score itself.
const kScoreCreditThreshold = 20000;
const kScoreCreditReward = 100;

/// Score interval between MREC ad breaks within a single run — every
/// [kAdBreakScoreThreshold] points, GameScreen shows showAdBreakScreen()
/// (see BoardState.pendingAdBreak/GameStateNotifier.acknowledgeAdBreak).
const kAdBreakScoreThreshold = 20000;

/// Credits awarded for watching a rewarded ad from the Shop.
const kShopAdCreditReward = 200;

/// Credits to remove every cherry currently on the table, from the
/// Cherry Bomb button.
const kCherryBombCost = 50;

/// Credits for the original Shake — impulse pulses only, no size change
/// — from the Shake button.
const kShakerCost = 100;

/// Credits for Mega-Shake — the same impulse pulses as Shake, plus every
/// item shrinking/wobbling/flexing for the duration — from the
/// Mega-Shake button.
const kMegaShakeCost = 400;

/// Credits to clear every Vodka, Melon Liqueur, Gin, and Coffee Liqueur
/// item currently on the table from the Slam Mini-Shots button (see
/// Ingredient.isMiniShot) — replaced the old, broader Alcohol-Free button.
const kMiniShotsCost = 300;

/// Sentinel default for [BoardState.copyWith]'s [order] param, so passing
/// `order: null` explicitly clears the active order (buying nothing sets
/// it) while omitting the argument leaves it untouched — a plain
/// `T? ?? this.field` copyWith can't tell those two cases apart.
class _Unset {
  const _Unset();
}

const _unset = _Unset();

/// The live game, as far as ordinary Flutter widgets need to know it: the
/// ingredient staged to drop next, the next few queued up (shown on the
/// "up next" card), the cocktail order in progress (null once the starter
/// order's been made and nothing's been bought since), running score,
/// game-over state, and the persistent economy (credits, highest tier
/// ever unlocked). Everything actually on the table — physics bodies,
/// merges, cocktail clusters — is normally owned by MixolocoGame itself;
/// [placedItems] only exists so a snapshot of the table survives
/// MixolocoGame itself being torn down and rebuilt (leaving GameScreen
/// and coming back) — see GameScreen.dispose and savePlacedItems.
class BoardState {
  final Ingredient current;
  final List<Ingredient> upcoming;
  final CocktailRecipe? order;
  final int cocktailsMade;
  final int score;
  final bool gameOver;
  final List<PlacedItem> placedItems;

  /// Whether this run ended by actually finishing the final level — two
  /// items at the very top of its chain merged, with nothing higher to
  /// become (see MixolocoGame._tryMerge) — rather than the table simply
  /// filling up. [gameOver] is still set true alongside this (it drives
  /// the same end-of-run overlay/persistence), so this only exists to
  /// let that overlay show "Game Complete" instead of "Game Over."
  /// Resets every game.
  final bool gameCompleted;

  /// Credits earned/spent this game and every game before it — persists
  /// to disk, see progression_service.dart.
  final int credits;

  /// The highest evolution tier ever reached on each level, across every
  /// game ever played — index 0 = Level 1 (see [highestTierFor]). Level 1
  /// starts at 0; every later level at -1 ("never reached"). Persists to
  /// disk (progression_service.dart).
  final List<int> highestTiers;

  /// The highest bar level ever reached, lifetime (1 or 2) — once this
  /// is 2, every new game starts there directly (see _freshGame) instead
  /// of back on the beach, and the home screen's "Unlocked" display shows
  /// a Level 2 ingredient regardless of that level's own [highestTiers]
  /// value, since even Level 2's lowest tier outranks every Level 1 one.
  final int highestLevelReached;

  /// Whether this game's one-time "clear all shots for an ad" offer has
  /// already been shown (accepted or declined) — resets every game.
  final bool continueOfferUsed;

  /// How many [kScoreCreditThreshold]-point milestones this game's score
  /// has already been credited for — resets every game along with
  /// [score] itself, so the reward is per-run, not lifetime.
  final int scoreCreditThresholdsAwarded;

  /// Which recipe ids have been completed at least once this run — the
  /// progress-tabs row ticks a cocktail off the first time it's made,
  /// not once per repeat. Resets every game.
  final Set<String> completedCocktailIds;

  /// Whether the top of the evolution chain (the jug) has appeared on
  /// the table this run — the 8th progress tab. Resets every game
  /// (unlike [highestTiers], which is a lifetime record).
  final bool jugReached;

  /// The current run's level — 1 (the beach bar) until every cocktail
  /// plus the jug have been completed, then 2 (the rooftop bar). Resets
  /// every game.
  final int level;

  /// How many [kAdBreakScoreThreshold]-point milestones this game has
  /// already shown the MREC ad break for — same "count of thresholds
  /// already handled" shape as [scoreCreditThresholdsAwarded], just
  /// driving an ad break instead of a credit reward. Resets every game.
  final int adBreakThresholdsShown;

  /// The highest level whose level-up celebration (see
  /// level_up_screen.dart) has already been shown/handled this run —
  /// guards against re-showing it (or re-running [enterLevel]/
  /// [MixolocoGame.switchToLevel]) if the game rebuilds while still on
  /// that level. Was a one-shot bool until a bug surfaced: it latched
  /// true after the first (1->2) transition and then never reset, so
  /// GameScreen's `board.level > 1 && !levelUpCelebrationShown` guard
  /// silently skipped every *later* transition's celebration *and* its
  /// enterLevel/switchToLevel reset — [BoardState.level] kept climbing
  /// (2->3->4) while the physics table and ingredient queue stayed
  /// frozen on whichever level the guard last actually fired for. An
  /// int watermark compared against [level] (`level > celebratedLevel`)
  /// fires correctly on every transition, not just the first. Resets
  /// every game (there's nothing to guard once level resets too).
  final int celebratedLevel;

  /// The highest evolution tier reached on *this run's current level*
  /// (by drop or merge, either counts — same trigger as
  /// [registerTierSeen]) — the Game Over plaque's "Max Evo" line.
  /// Deliberately separate from the lifetime [highestTiers]
  /// fields (which only bump on a genuinely new personal best): this is
  /// per-run, resets to 0 on every fresh game and again on every
  /// [GameStateNotifier.enterLevel] (so it reflects the climb on
  /// whichever chain the run actually ended on, not a tier number
  /// carried over from a different level's chain).
  final int runHighestTier;

  /// Whether this run's final [score] beat every previous local high
  /// score — set once, at [GameStateNotifier._finalizeScore], for the
  /// Game Over plaque's "PB" badge. Resets every game.
  final bool isNewHighScore;

  const BoardState({
    required this.current,
    required this.upcoming,
    required this.order,
    required this.cocktailsMade,
    required this.score,
    required this.gameOver,
    this.gameCompleted = false,
    required this.credits,
    this.highestTiers = const [],
    this.highestLevelReached = 1,
    this.continueOfferUsed = false,
    this.scoreCreditThresholdsAwarded = 0,
    this.placedItems = const [],
    this.completedCocktailIds = const {},
    this.jugReached = false,
    this.level = 1,
    this.adBreakThresholdsShown = 0,
    this.celebratedLevel = 1,
    this.runHighestTier = 0,
    this.isNewHighScore = false,
  });

  /// Whether the score has crossed a new [kAdBreakScoreThreshold]
  /// milestone that hasn't shown its ad break yet — GameScreen watches
  /// this and pushes [showAdBreakScreen] when it flips true.
  bool get pendingAdBreak =>
      score ~/ kAdBreakScoreThreshold > adBreakThresholdsShown;

  BoardState copyWith({
    Ingredient? current,
    List<Ingredient>? upcoming,
    Object? order = _unset,
    int? cocktailsMade,
    int? score,
    bool? gameOver,
    bool? gameCompleted,
    int? credits,
    List<int>? highestTiers,
    int? highestLevelReached,
    bool? continueOfferUsed,
    int? scoreCreditThresholdsAwarded,
    List<PlacedItem>? placedItems,
    Set<String>? completedCocktailIds,
    bool? jugReached,
    int? level,
    int? adBreakThresholdsShown,
    int? celebratedLevel,
    int? runHighestTier,
    bool? isNewHighScore,
  }) {
    return BoardState(
      current: current ?? this.current,
      upcoming: upcoming ?? this.upcoming,
      order: identical(order, _unset) ? this.order : order as CocktailRecipe?,
      cocktailsMade: cocktailsMade ?? this.cocktailsMade,
      score: score ?? this.score,
      gameOver: gameOver ?? this.gameOver,
      gameCompleted: gameCompleted ?? this.gameCompleted,
      credits: credits ?? this.credits,
      highestTiers: highestTiers ?? this.highestTiers,
      highestLevelReached: highestLevelReached ?? this.highestLevelReached,
      continueOfferUsed: continueOfferUsed ?? this.continueOfferUsed,
      scoreCreditThresholdsAwarded:
          scoreCreditThresholdsAwarded ?? this.scoreCreditThresholdsAwarded,
      placedItems: placedItems ?? this.placedItems,
      completedCocktailIds: completedCocktailIds ?? this.completedCocktailIds,
      jugReached: jugReached ?? this.jugReached,
      level: level ?? this.level,
      adBreakThresholdsShown:
          adBreakThresholdsShown ?? this.adBreakThresholdsShown,
      celebratedLevel: celebratedLevel ?? this.celebratedLevel,
      runHighestTier: runHighestTier ?? this.runHighestTier,
      isNewHighScore: isNewHighScore ?? this.isNewHighScore,
    );
  }
}

/// One item's tier and position, snapshotted from a live physics body —
/// see [BoardState.placedItems]. Position is in MixolocoGame's world
/// coordinates (meters), which are stable across navigation since
/// kWorldWidthMeters is fixed and the same device gives the same aspect
/// ratio back on return.
class PlacedItem {
  final int tier;
  final double x;
  final double y;
  final double angle;
  /// The ingredient id, so a restore can find its tier even if the
  /// chain order changed in an update (null in older saves).
  final String? id;
  const PlacedItem({required this.tier, required this.x, required this.y, this.angle = 0, this.id});
}

class GameStateNotifier extends Notifier<BoardState> {
  final _random = Random();

  /// Shuffled draw-pile for [_randomIngredient] — plain independent random
  /// picks are "truly random" but read as unfair over a short session
  /// (the same ingredient popping up twice in a row, another one not
  /// showing for ages purely by chance), so this deals from a shuffled
  /// copy of the throwable tiers instead (see [throwableIngredientsFor] —
  /// grows by one once the player's reached Cranberry): every one is
  /// guaranteed to appear once per refill, which happens with a fresh
  /// shuffle (never repeating the seam draw) once exhausted.
  List<Ingredient> _ingredientBag = [];
  Ingredient? _lastDrawnIngredient;

  @override
  BoardState build() {
    // Global, not screen-scoped — a purchase's PurchaseDetails event from
    // Play Billing can land well after whatever dialog started it has
    // closed, so crediting the player can't depend on that dialog still
    // being mounted to react to it.
    // Each event is a grant number (see PurchaseService._grantSequence);
    // the grant itself is already saved, so these just re-read it.
    ref.listen(creditPackPurchaseProvider, (previous, next) {
      if (next.hasValue) addPurchasedCredits();
    });
    ref.listen(unlockLevelPurchaseProvider, (previous, next) {
      if (next.hasValue) unlockNextLevelFromPurchase();
    });
    // Deferred — _loadPersisted's very first line reads `state`, which
    // Riverpod can't serve until this build() call has actually returned
    // and the provider is mounted. Calling it synchronously here threw
    // "Tried to read the state of an uninitialized provider" on every
    // single cold start (confirmed via logcat), silently aborting before
    // any disk read ever ran — the root cause of credits/progress
    // appearing lost after the app was fully closed and reopened, not a
    // save-side timing issue. Future.microtask defers it to right after
    // this method returns, by which point `state` is safely readable —
    // same fix already used for GameScreen's/LeagueScreen's own
    // during-build provider writes.
    Future.microtask(_loadPersisted);
    return _freshGame(
      credits: 0,
      highestTiers: const [],
      highestLevelReached: 1,
    );
  }

  /// Credits and the highest-tier records live on disk, not in this
  /// provider's initial (synchronous) state — this patches them in the
  /// moment they're loaded. A brief 0-credits flash on cold start is the
  /// tradeoff for keeping GameStateNotifier a plain, synchronous Notifier
  /// rather than an AsyncNotifier throughout. If a run was in progress
  /// last time the app closed (see persistGameState), that whole board
  /// replaces the fresh one this Notifier started with instead of just
  /// patching the lifetime fields onto it.
  ///
  /// [build] starts every session on a hard-coded zeroed [BoardState] (see
  /// its own doc — "a brief 0-credits flash") and relies entirely on this
  /// running to completion to patch in the real saved values. If any
  /// plugin-channel read below ever throws — a transient hiccup, more
  /// likely right after an app update (first-run odex/verification work
  /// slowing the engine's early frames) or waking from a long overnight
  /// idle (process cold-started under load) — an unguarded version of this
  /// function would abort silently and leave the whole session stuck on
  /// that zeroed default. Any gameplay from that point on
  /// (registerMerge/spendCredits/etc, all of which persist immediately)
  /// would then write the zeroed values straight over the real save on
  /// disk — permanent progress loss triggered by nothing more than one
  /// slow cold start, matching reports of progress resetting right after
  /// installing an update and again after leaving the app overnight.
  /// Retrying a few times with a short backoff costs nothing and makes a
  /// merely transient failure self-heal well within the time it'd take a
  /// player to even see the menu, let alone play far enough to persist
  /// anything.
  Future<void> _loadPersisted() async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _loadPersistedOnce();
        return;
      } catch (e, st) {
        debugPrint('_loadPersisted attempt $attempt/$maxAttempts failed: $e\n$st');
        if (attempt == maxAttempts) return;
        await Future.delayed(Duration(milliseconds: 200 * attempt));
      }
    }
  }

  Future<void> _loadPersistedOnce() async {
    // Snapshot of exactly what build() returned, captured before any
    // `await` below yields control back to the event loop — if `state`
    // is still this same instance once every disk read below finally
    // resolves, nothing else touched it in the meantime and the full
    // replace further down is safe. On a slow enough cold start, though,
    // a tap can land (and call registerMerge/spendCredits/etc, mutating
    // `state`) before these plugin-channel reads finish; blindly
    // overwriting `state` at that point would silently discard whatever
    // that tap just did. See the `identical` check below for the fix.
    final preLoadState = state;
    final credits = await loadCredits();
    final highestTiers = await loadHighestTiers(kLevelCount);
    final highestLevelReached = await loadHighestLevelReached();
    final savedJson = await loadGameJson();
    final restored = savedJson == null
        ? null
        : _decodeState(
            savedJson,
            credits: credits,
            highestTiers: highestTiers,
            highestLevelReached: highestLevelReached,
          );
    final raced = !identical(state, preLoadState);
    if (raced && restored == null) {
      // Something already happened on the default fresh board (a tap
      // landed before these disk reads resolved) — patch the now-loaded
      // lifetime fields onto whatever `state` has become instead of
      // discarding that interim gameplay outright. Doesn't also jump
      // level/current/upcoming to match a higher highestLevelReached (the
      // way _freshGame would) since the player may already be mid-throw
      // on the level-1 board build() started them on; that's a one-launch
      // cosmetic gap (they'd start on their usual level next time), far
      // better than losing a real merge/spend/score silently.
      state = state.copyWith(
        credits: credits,
        highestTiers: highestTiers,
        highestLevelReached: highestLevelReached,
      );
    } else {
      // Either nothing touched `state` while these reads were in flight
      // (the common case), or it did but there's a genuine saved run to
      // resume — resuming it is the stronger intent there, same
      // tiny-window tradeoff this replace always had, just now scoped to
      // the rarer case where a prior session actually exists to come
      // back to rather than every cold start. Falls back to a
      // freshly-built game (not just a copyWith patch onto the level-1
      // default build() started with) when there's no save to restore —
      // a copyWith patch would leave level/order/current/upcoming at
      // their level-1 defaults even when highestLevelReached says this
      // player should be starting straight on the rooftop bar.
      state =
          restored ??
          _freshGame(
            credits: credits,
            highestTiers: highestTiers,
            highestLevelReached: highestLevelReached,
          );
    }
    // A restored run can already satisfy _checkLevelUp's conditions
    // (jugReached + every cocktail) without anything here ever having
    // re-evaluated them — that only ever ran reactively, from
    // registerTierSeen/registerCocktailComplete, at the moment each one
    // was first satisfied. A player who hit both before this exact
    // check existed (the old level>=2 early-return bug, or simply
    // because nothing ever re-checks on its own) would otherwise stay
    // silently stuck on their current level forever, since nothing
    // about sitting at the capstone tier with every cocktail already
    // made generates a new tier-seen/cocktail-complete event to
    // re-trigger it — there's no higher tier to merge into, and no
    // uncompleted cocktail left to buy. Re-running it once after every
    // load is a cheap, idempotent way to unstick exactly that case
    // (every one of its own guards already make it a no-op otherwise).
    if (restored != null) _checkLevelUp();
  }

  /// Writes the entire current run to disk — called whenever the table's
  /// snapshotted (leaving via Home, or the app being backgrounded/closed
  /// mid-game, see GameScreen) so it survives a full app restart, not
  /// just navigating away and back within the same session.
  Future<void> persistGameState() async {
    await saveGameJson(jsonEncode(_encodeState(state)));
  }

  Map<String, dynamic> _encodeState(BoardState s) => {
    'currentId': s.current.id,
    'upcomingIds': s.upcoming.map((i) => i.id).toList(),
    'orderId': s.order?.id,
    'cocktailsMade': s.cocktailsMade,
    'score': s.score,
    'gameOver': s.gameOver,
    'gameCompleted': s.gameCompleted,
    'continueOfferUsed': s.continueOfferUsed,
    'scoreCreditThresholdsAwarded': s.scoreCreditThresholdsAwarded,
    'placedItems': s.placedItems
        .map((p) => {'tier': p.tier, 'x': p.x, 'y': p.y, 'angle': p.angle, 'id': p.id})
        .toList(),
    'completedCocktailIds': s.completedCocktailIds.toList(),
    'jugReached': s.jugReached,
    'level': s.level,
    'adBreakThresholdsShown': s.adBreakThresholdsShown,
    'celebratedLevel': s.celebratedLevel,
    'runHighestTier': s.runHighestTier,
    'saveVersion': 2,
  };

  /// Rebuilds a full BoardState from a previous [_encodeState] — wrapped
  /// in try/catch and returns null (falling back to a fresh game) rather
  /// than crashing on a corrupt save, or a stale one referencing an
  /// ingredient/recipe id a later content update removed (exactly what
  /// this session's own tonic/vodka_tonic removal would do to any save
  /// made before it). [orderId] is looked up against whichever recipe
  /// list matches the saved level, since Level 2 ids (e.g. 'martini')
  /// don't exist in [kCocktailRecipes].
  BoardState? _decodeState(
    String json, {
    required int credits,
    required List<int> highestTiers,
    required int highestLevelReached,
  }) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final orderId = map['orderId'] as String?;
      final level = map['level'] as int;
      final recipes = cocktailRecipesForLevel(level);
      // Resolved against *this save's own* level chain, not
      // findIngredientById's cross-chain search — a handful of ids
      // (lime, vodka, gin, tonic, cherry, prosecco) exist in more than
      // one chain with the same art but a different tier number, and
      // findIngredientById always returns whichever chain's copy comes
      // first (Level 1's). Since _spawnBody later re-resolves by tier
      // into *this* level's chain (`_chain[tier]`), restoring a Level 2+
      // save with the wrong chain's copy — right art, wrong tier — meant
      // the staged preview showed one ingredient but a completely
      // different one (whatever that tier is in the real chain) actually
      // spawned the moment it was thrown.
      final chain = evolutionChainForLevel(level);
      // Level 5 was reordered after build 20; a save from then stores its
      // tiers as positions in the old order (items carry no id).
      final legacyLevel5 = level == 5 && (map['saveVersion'] as int?) == null;
      Ingredient resolveIngredient(String id) =>
          chain.firstWhere((i) => i.id == id, orElse: () => findIngredientById(id));
      return BoardState(
        current: resolveIngredient(map['currentId'] as String),
        upcoming: (map['upcomingIds'] as List)
            .map((id) => resolveIngredient(id as String))
            .toList(),
        // An order that isn't on this level's menu can't be made (a
        // Level 5 run was once handed Level 4's Vodka Lemon starter) —
        // swap in the level's own starter instead of discarding the save.
        order: orderId == null
            ? null
            : recipes.firstWhere(
                (r) => r.id == orderId,
                orElse: () => starterCocktailForLevel(level),
              ),
        cocktailsMade: map['cocktailsMade'] as int,
        score: map['score'] as int,
        gameOver: map['gameOver'] as bool,
        // Absent in a save written before this field existed — false
        // (an ordinary table-full ending, not a win) is the correct
        // read for that case, same spirit as runHighestTier's fallback
        // below.
        gameCompleted: map['gameCompleted'] as bool? ?? false,
        credits: credits,
        highestTiers: highestTiers,
        highestLevelReached: highestLevelReached,
        continueOfferUsed: map['continueOfferUsed'] as bool,
        scoreCreditThresholdsAwarded:
            map['scoreCreditThresholdsAwarded'] as int,
        placedItems: (map['placedItems'] as List)
            .map(
              (p) => PlacedItem(
                tier: p['tier'] as int,
                x: (p['x'] as num).toDouble(),
                y: (p['y'] as num).toDouble(),
                angle: (p['angle'] as num?)?.toDouble() ?? 0,
                id: p['id'] as String? ?? (legacyLevel5 ? legacyLevel5Id(p['tier'] as int) : null),
              ),
            )
            .toList(),
        completedCocktailIds: (map['completedCocktailIds'] as List)
            .cast<String>()
            .toSet(),
        jugReached: map['jugReached'] as bool,
        level: level,
        adBreakThresholdsShown: map['adBreakThresholdsShown'] as int,
        // A save from before celebratedLevel existed only ever had the
        // old one-shot bool, which (correctly, back then) only ever
        // meant "level 2's celebration has been shown" — never a
        // higher level, since the bug this field replaces meant no
        // later transition's enterLevel/switchToLevel ever actually
        // ran. Reading it as 2 (not the save's possibly-bugged [level])
        // means the very next build correctly replays enterLevel/
        // switchToLevel for any level the old bug had silently skipped,
        // self-healing an already-corrupted in-progress save instead of
        // perpetuating the mismatch.
        celebratedLevel:
            map['celebratedLevel'] as int? ??
            ((map['levelUpCelebrationShown'] as bool?) == true ? 2 : 1),
        // Absent in a save written before this field existed — 0 (never
        // reached anything this run) is the correct read for that case,
        // same spirit as every other new-field fallback in this method.
        runHighestTier: switch (map['runHighestTier'] as int? ?? 0) {
          final t when legacyLevel5 => migrateLegacyLevel5Tier(t),
          final t => t,
        },
      );
    } catch (_) {
      return null;
    }
  }

  BoardState _freshGame({
    required int credits,
    required List<int> highestTiers,
    required int highestLevelReached,
    int? level,
  }) {
    _ingredientBag = [];
    _finalMerged = false;
    final resolvedLevel = level ?? highestLevelReached;
    final highestForLevel = highestTierFor(highestTiers, resolvedLevel);
    return BoardState(
      current: _randomIngredient(resolvedLevel, highestForLevel),
      upcoming: List.generate(
        3,
        (_) => _randomIngredient(resolvedLevel, highestForLevel),
      ),
      // Cocktail Mode off: no order auto-pursues in the background (see
      // enterLevel's matching comment on why) — the player can still buy
      // one from the Cocktail Menu whenever they want.
      order: ref.read(cocktailModeProvider) ? starterCocktailForLevel(resolvedLevel) : null,
      cocktailsMade: 0,
      score: 0,
      gameOver: false,
      credits: credits,
      highestTiers: highestTiers,
      highestLevelReached: highestLevelReached,
      level: resolvedLevel,
      // A fresh game that *starts* on Level N (because that's already the
      // lifetime record, or the player deliberately chose it — see
      // startNewGameAtLevel) isn't the moment of leveling up — that
      // already happened, in whatever earlier run first reached it.
      // Marking every level up to N pre-celebrated here is what stops
      // GameScreen's `board.level > board.celebratedLevel` check from
      // replaying the "Level Complete!" popup on every single new game
      // once a player's actually reached that bar; without this, only a
      // genuine mid-run transition (see enterLevel) should ever show it,
      // but every fresh start at that level would too.
      celebratedLevel: resolvedLevel,
    );
  }

  /// Starts a brand-new run at [level] — same lifetime-stat-carryover
  /// rules as [restart], but lets the player deliberately choose a level
  /// they've already reached rather than always jumping to their highest
  /// (see the Play Game level picker, main menu).
  void startNewGameAtLevel(int level) {
    _finalizeAbandonedRun();
    state = _freshGame(
      credits: state.credits,
      highestTiers: state.highestTiers,
      highestLevelReached: state.highestLevelReached,
      level: level,
    );
  }

  /// A run left unfinished — the player started a new game instead of
  /// ending this one (or never answered the continue offer) — still
  /// counts: its score goes to My Best and the weekly league, same as a
  /// run that ended. One that's already been finalized (declined
  /// continue, a second game over, a completed game) isn't counted twice.
  void _finalizeAbandonedRun() {
    final alreadyFinalized = state.gameOver && state.continueOfferUsed;
    if (alreadyFinalized || state.score <= 0) return;
    if (!state.gameOver) analyticsService.gameOver(level: state.level, score: state.score);
    _finalizeScore(abandoned: true);
  }

  /// Takes the level and its highest-tier record explicitly rather than
  /// reading `state.*` directly — this is called from [_freshGame] during
  /// [build] itself (via the Notifier's very first, synchronous state
  /// construction), and Riverpod throws if a Notifier tries to read its
  /// own `state` before that initial build has returned. That thrown
  /// exception was poisoning gameStateProvider entirely: every
  /// ref.watch(gameStateProvider) anywhere in the app (MenuScreen's build
  /// included) re-throws it on every rebuild, which is what a blank
  /// board/blank screen that occasionally "recovers" — whenever something
  /// happens to dodge that exact rebuild path — looks like from the
  /// outside.
  Ingredient _randomIngredient(int level, int highestTierUnlocked) {
    if (_ingredientBag.isEmpty) {
      final bag = List<Ingredient>.from(
        throwableIngredientsFor(level, highestTierUnlocked),
      )..shuffle(_random);
      if (bag.length > 1 && bag.first == _lastDrawnIngredient) {
        final swapWith = 1 + _random.nextInt(bag.length - 1);
        final first = bag[0];
        bag[0] = bag[swapWith];
        bag[swapWith] = first;
      }
      _ingredientBag = bag;
    }
    final drawn = _ingredientBag.removeAt(0);
    _lastDrawnIngredient = drawn;
    return drawn;
  }

  /// Advances the staged/queued ingredients after a drop is actually
  /// committed to the table (MixolocoGame calls this only once the item
  /// has really spawned — a drop that trips game-over never reaches
  /// this).
  void advanceQueue() {
    if (state.gameOver) return;
    final nextCurrent = state.upcoming.first;
    final highestForLevel = highestTierFor(state.highestTiers, state.level);
    final nextUpcoming = [
      ...state.upcoming.skip(1),
      _randomIngredient(state.level, highestForLevel),
    ];
    state = state.copyWith(current: nextCurrent, upcoming: nextUpcoming);
  }

  /// Adds [amount] to the score and, if that crosses one or more new
  /// [kScoreCreditThreshold] milestones, banks and persists the credit
  /// reward for each one crossed (a single big jump — a large cocktail
  /// bonus, say — can cross more than one at once).
  void _addScore(int amount) {
    final newScore = state.score + amount;
    final newThresholdCount = newScore ~/ kScoreCreditThreshold;
    final crossed = newThresholdCount - state.scoreCreditThresholdsAwarded;
    if (crossed > 0) {
      final newCredits = state.credits + crossed * kScoreCreditReward;
      state = state.copyWith(
        score: newScore,
        credits: newCredits,
        scoreCreditThresholdsAwarded: newThresholdCount,
      );
      saveCredits(newCredits);
      _pushProgressToServer();
    } else {
      state = state.copyWith(score: newScore);
    }
  }

  void registerMerge(int tier) {
    if (state.gameOver) return;
    _addScore(scoreForMerge(tier));
  }

  void registerCocktailComplete(CocktailRecipe recipe) {
    if (state.gameOver) return;
    // No more auto-cycling to a new order — the starter's a one-off, and
    // every order after it has to be bought from the Cocktail Menu.
    state = state.copyWith(
      cocktailsMade: state.cocktailsMade + 1,
      order: null,
      completedCocktailIds: {...state.completedCocktailIds, recipe.id},
    );
    // Fired right after the state mutation above, before anything else
    // that could throw (_addScore/_checkLevelUp) — this is fire-and-
    // forget, so if it ran last and something later in this method threw,
    // the Guide's lifetime "ever mixed" record would silently never see
    // this cocktail even though the player already saw it ticked off and
    // paid for in-game. Confirmed as the exact shape of a real report.
    _persistMixedCocktail(recipe.id);
    analyticsService.cocktailMade(cocktailId: recipe.id, level: state.level);
    _addScore(scoreForCocktail(recipe));
    _checkLevelUp();
  }

  /// Files [recipeId] into the lifetime "ever mixed" record (see
  /// progression_service.dart's own doc) — separate from the per-run
  /// [BoardState.completedCocktailIds] set above, which resets every new
  /// game/level. Load-merge-save rather than keeping an in-memory copy,
  /// same reasoning as the rest of this notifier's lifetime fields: this
  /// fires rarely (once per cocktail, ever) so the extra disk round trip
  /// isn't worth a dedicated cache.
  Future<void> _persistMixedCocktail(String recipeId) async {
    final ids = await loadMixedCocktailIds();
    if (ids.add(recipeId)) await saveMixedCocktailIds(ids);
  }

  /// [tier] just appeared on the table — by a drop or a merge, either
  /// counts, within whichever chain [state.level] is currently on. Two
  /// independent things can happen here: a new personal-best tier (for
  /// this level specifically) banks its (lifetime, not reset by
  /// [restart]) credit reward, and — regardless of whether this run has
  /// ever reached this tier before — hitting the very top of the current
  /// chain (Jug on Level 1, Champagne on Level 2) ticks off the 8th
  /// progress tab. These can't share an early-return guard: a player
  /// whose lifetime record already includes the capstone tier from a
  /// past run would otherwise never have [jugReached] set on a fresh run.
  void registerTierSeen(int tier) {
    final level = state.level;
    if (tier > state.runHighestTier) {
      state = state.copyWith(runHighestTier: tier);
    }
    final currentHighest = highestTierFor(state.highestTiers, level);
    if (tier > currentHighest) {
      final newCredits = state.credits + kTierUnlockReward;
      final tiers = [
        for (var l = 1; l <= kLevelCount; l++)
          l == level ? tier : highestTierFor(state.highestTiers, l),
      ];
      state = state.copyWith(highestTiers: tiers, credits: newCredits);
      saveHighestTierForLevel(level, tier);
      saveCredits(newCredits);
      _pushProgressToServer();
    }
    final chainLastTier = evolutionChainForLevel(level).last.tier;
    if (!state.jugReached && tier == chainLastTier) {
      state = state.copyWith(jugReached: true);
      analyticsService.finalItemReached(level: state.level);
      _checkLevelUp();
    }
  }

  /// Advances to the next level once it's earned. Cocktail Mode on (see
  /// cocktail_mode_provider.dart): every cocktail on the menu made, and the
  /// final item made once. Off: two final items merged (see
  /// registerFinalMerge). A no-op once already at [kMaxLevel]. Only flips
  /// [BoardState.level] itself; GameScreen notices that flip and calls
  /// [enterLevel] to actually reset the table/queue/order for the new
  /// chain once its celebration sequence has played out (see
  /// level_up_overlay.dart) — doing that heavy a reset from inside this
  /// callback, mid physics-contact-resolution, would be a bad time for
  /// the whole board to change under MixolocoGame's feet.
  void _checkLevelUp() {
    if (state.level >= kMaxLevel) return;
    if (ref.read(cocktailModeProvider)) {
      if (!state.jugReached) return;
      if (state.completedCocktailIds.length < cocktailRecipesForLevel(state.level).length) return;
    } else if (!_finalMerged) {
      return;
    }
    _finalMerged = false;
    state = state.copyWith(level: state.level + 1);
    analyticsService.levelUp(state.level);
  }

  /// Two final items merged this level (Cocktail Mode off) — not saved:
  /// the level-up it triggers happens at once.
  bool _finalMerged = false;

  /// Two of the level's final items merged (MixolocoGame.onFinalMerge).
  void registerFinalMerge() {
    _finalMerged = true;
    _checkLevelUp();
  }

  /// Actually moves the current run onto [level]'s own chain — clears the
  /// throwable shuffle-bag (so the next draw rebuilds from the new
  /// level's pool, not a stale one), regenerates the staged/upcoming
  /// ingredients and the active order from that level's starter cocktail,
  /// resets [jugReached]/[completedCocktailIds] (a fresh capstone/recipe
  /// set to chase on the new chain), and bumps the lifetime
  /// [highestLevelReached] record if this is further than it's ever been.
  /// Called by GameScreen once the level-up celebration begins (see
  /// GameScreen._runLevelUp), alongside MixolocoGame.switchToLevel which
  /// does the equivalent reset on the physics side.
  void enterLevel(int level) {
    _ingredientBag = [];
    _finalMerged = false;
    final highestForLevel = highestTierFor(state.highestTiers, level);
    final newCurrent = _randomIngredient(level, highestForLevel);
    final newUpcoming = List.generate(
      3,
      (_) => _randomIngredient(level, highestForLevel),
    );
    final newHighestLevelReached = level > state.highestLevelReached
        ? level
        : state.highestLevelReached;
    state = state.copyWith(
      level: level,
      current: newCurrent,
      upcoming: newUpcoming,
      // Cocktail Mode off: don't auto-assign a starter order the player
      // never chose — per feedback, that read as a surprise ("it made me
      // a screwdriver!?") since nothing about turning the mode off looked
      // like it should still be quietly pursuing/completing one in the
      // background. Buying one from the Cocktail Menu still works either
      // way (see GameScreen's `enabled: board.order == null` gate).
      order: ref.read(cocktailModeProvider) ? starterCocktailForLevel(level) : null,
      jugReached: false,
      completedCocktailIds: {},
      highestLevelReached: newHighestLevelReached,
      runHighestTier: 0,
      // The previous level's table — never restored onto this one.
      placedItems: const [],
    );
    saveHighestLevelReached(newHighestLevelReached);
    _pushProgressToServer();
  }

  /// Marks the current score-based ad-break milestone as shown — called
  /// once GameScreen has actually pushed showAdBreakScreen() for it, so
  /// [BoardState.pendingAdBreak] goes back to false until the next
  /// [kAdBreakScoreThreshold] is crossed.
  void acknowledgeAdBreak() {
    state = state.copyWith(
      adBreakThresholdsShown: state.score ~/ kAdBreakScoreThreshold,
    );
  }

  /// Marks the level-up celebration as shown for the level just entered
  /// — called once its full sequence (celebration → interstitial) has
  /// played out, by which point [enterLevel] has already bumped
  /// [BoardState.level] to the new level.
  void acknowledgeLevelUpCelebration() {
    state = state.copyWith(celebratedLevel: state.level);
  }

  /// Adds credits earned from a watched rewarded ad (Shop's "watch an ad
  /// for credits" offer) — separate from [spendCredits]'s mirror-image
  /// deduction, and from the lifetime/per-run reward paths above, since
  /// this one's triggered by AdService's reward callback rather than any
  /// in-game event.
  void addAdCredits(int amount) {
    final newCredits = state.credits + amount;
    state = state.copyWith(credits: newCredits);
    saveCredits(newCredits);
    _pushProgressToServer();
  }

  /// Adds credits claimed from a past league week's result (a promotion
  /// or room win — see rollover.js's creditsAwarded and
  /// LeagueController.claimPendingCredits, which guards against claiming
  /// the same week twice). Same shape as [addAdCredits], kept as its own
  /// method for a clearer credit-earning trail rather than reusing that
  /// one under a name that says "ad".
  void addLeagueCredits(int amount) {
    final newCredits = state.credits + amount;
    state = state.copyWith(credits: newCredits);
    saveCredits(newCredits);
    _pushProgressToServer();
  }

  /// Adds credits bought with real money (GetCreditsDialog's two credit
  /// packs) — same shape as [addAdCredits]/[addLeagueCredits], called
  /// from the global [creditPackPurchaseProvider] listener in [build]
  /// rather than directly from the dialog, so it fires whenever Play
  /// Billing actually reports the purchase, not just while that dialog
  /// happens to still be open.
  ///
  /// PurchaseService has already saved the new balance before announcing
  /// it, so this re-reads the saved value rather than adding the pack's
  /// amount again — the grant survives even if this listener wasn't attached yet.
  Future<void> addPurchasedCredits() async {
    final credits = await loadCredits();
    state = state.copyWith(credits: credits);
    _pushProgressToServer();
  }

  /// Raises [BoardState.highestLevelReached] by one (capped at
  /// [kMaxLevel]) for ShopScreen's "Unlock Next Level" purchase — called
  /// from the global [unlockLevelPurchaseProvider] listener in [build],
  /// same reasoning as [addPurchasedCredits]. Deliberately only touches
  /// that one lifetime record: evolution tiers, credits, and whatever
  /// run is currently in progress are all untouched — the player just
  /// gains the *option* to start a New Game at the newly-unlocked level
  /// whenever they choose, exactly as if they'd reached it by playing.
  ///
  /// Already saved by PurchaseService (see [addPurchasedCredits]) — this
  /// re-reads it.
  Future<void> unlockNextLevelFromPurchase() async {
    final reached = await loadHighestLevelReached();
    state = state.copyWith(highestLevelReached: reached);
    _pushProgressToServer();
  }

  /// Spends [amount] credits if there are enough; returns whether it
  /// went through. Used by both the Shaker Maker and the Cocktail Menu —
  /// callers only act on the physics/order side once this returns true.
  /// Also pushed to the server immediately (see _pushProgressToServer) —
  /// important here specifically, since the Google-backup merge is a
  /// max() per field (see progress_sync.dart): a spend is this provider's
  /// only path where credits ever go DOWN, and a sync running against a
  /// stale pre-spend server value would otherwise hand the spent credits
  /// right back. Pushing straight after narrows that window to "offline
  /// right at the moment of a spend," not a routinely hittable case.
  bool spendCredits(int amount) {
    if (state.credits < amount) return false;
    final newCredits = state.credits - amount;
    state = state.copyWith(credits: newCredits);
    saveCredits(newCredits);
    _pushProgressToServer();
    return true;
  }

  /// Buys [recipe] as the active order — replaces whatever order (if
  /// any) is already in progress. Returns whether the purchase went
  /// through (i.e. there were enough credits).
  bool buyCocktail(CocktailRecipe recipe) {
    if (!spendCredits(recipe.price)) return false;
    analyticsService.spendCoins(item: 'cocktail_order', amount: recipe.price);
    state = state.copyWith(order: recipe);
    return true;
  }

  void registerGameOver() {
    if (state.gameOver) return;
    state = state.copyWith(gameOver: true);
    analyticsService.gameOver(level: state.level, score: state.score);
    // Only record once the once-per-game continue offer is no longer in
    // play — the first time a run hits the table-full line,
    // continueOfferUsed is still false and GameScreen is about to show
    // the watch-ad-to-continue overlay (see showContinueOffer there), so
    // the player might keep playing and this score isn't final yet.
    // Recording it anyway was the bug: accepting the offer un-ends the
    // game (see continueAfterAd) and this method fires again later with
    // the real final score, leaving two high-score entries for what was
    // one session. The "decline" path finalizes via declineContinue
    // below instead, since registerGameOver never runs a second time
    // there. This branch is what finalizes the "accepted, then genuinely
    // ran out of table" path, where continueOfferUsed is already true by
    // the time this second call comes through.
    if (state.continueOfferUsed) {
      _finalizeScore();
    }
  }

  /// The final level's own capstone tier just merged with itself — the
  /// actual win condition (see MixolocoGame._tryMerge), not a table-full
  /// ending. Marks [continueOfferUsed] immediately rather than offering
  /// the watch-ad-to-continue overlay first: that offer exists to let a
  /// player who ran out of table space keep going, which doesn't apply
  /// to a finished run with plenty of room left.
  void registerGameComplete() {
    if (state.gameOver) return;
    state = state.copyWith(
      gameOver: true,
      gameCompleted: true,
      continueOfferUsed: true,
    );
    analyticsService.gameComplete(score: state.score);
    _finalizeScore();
  }

  /// Declines the once-per-game ad-continue offer — game stays over, but
  /// the offer itself won't be shown again this game. This is what
  /// actually finalizes the score for a run that ends here (see
  /// registerGameOver's own doc comment for the other, "accepted the
  /// offer" finalization path).
  void declineContinue() {
    state = state.copyWith(continueOfferUsed: true);
    _finalizeScore();
  }

  /// Accepts the ad-continue offer — called once the (placeholder) ad
  /// has finished playing. MixolocoGame clears the vodka/rum itself
  /// (GameScreen wires that up alongside this); this just un-ends the
  /// game and marks the offer used.
  void continueAfterAd() {
    state = state.copyWith(gameOver: false, continueOfferUsed: true);
  }

  /// Records the local high score and submits this run's league score —
  /// called exactly once per game, at whichever point the run is truly,
  /// finally over (see registerGameOver/declineContinue). The league
  /// submission is fire-and-forget (silently no-ops without a signed-in
  /// uid — offline cold start, Firebase not set up, or the player's
  /// never opened the league screen, see AuthService's own doc comment);
  /// the local high-score check is awaited just long enough to read the
  /// previous best *before* recordScore overwrites it, so
  /// [BoardState.isNewHighScore] (the Game Over plaque's "PB" badge) can
  /// be set correctly.
  ///
  /// The run is read up front: for an [abandoned] run the caller replaces
  /// [state] with a fresh game straight after calling this, so nothing
  /// below the first await may read it — and there's no Game Over plaque
  /// to show the "PB" badge on.
  Future<void> _finalizeScore({bool abandoned = false}) async {
    final score = state.score;
    final level = state.level;
    final runHighestTier = state.runHighestTier;
    final highestTiers = state.highestTiers;
    final highestLevelReached = state.highestLevelReached;
    final previousBest = await loadHighScores();
    if (!abandoned) {
      final isNewHighScore = score > 0 && (previousBest.isEmpty || score > previousBest.first);
      state = state.copyWith(isNewHighScore: isNewHighScore);
    }
    try {
      await recordScore(score, level: level, tier: runHighestTier);
    } catch (e, st) {
      // Unlike every neighboring call here (submitWeeklyScore's
      // catchError, _pushProgressToServer's own try/catch), this one had
      // no error handling at all — a corrupt high_scores JSON meant a
      // genuine new best quietly failed to save, with no log trail to
      // diagnose it from. Soft failure, same spirit as the rest of this
      // method: a local-save hiccup shouldn't block the league submission
      // or progress push below it.
      debugPrint('High score save failed (non-fatal): $e\n$st');
    }
    final uid = authService.uid;
    if (uid != null && score > 0) {
      ref
          .read(leagueRepositoryProvider)
          .submitWeeklyScore(
            uid: uid,
            score: score,
            level: level,
            highestTiers: highestTiers,
            highestLevelReached: highestLevelReached,
            runTier: runHighestTier,
          )
          .catchError((e) {});
    }
    _pushProgressToServer();
  }

  /// Backs up this player's lifetime progress (credits, evolution tiers,
  /// highest level, local high scores) to their Google-account doc — see
  /// progress_sync.dart for the matching restore/merge side. A no-op
  /// without a signed-in uid, same "unavailable for now" treatment as
  /// every other league/Firestore call in this file; silently swallows
  /// failures (offline, Firestore rules rejecting a malformed write) since
  /// this is a background backup, never something gameplay should block
  /// or visibly fail on. Called after every point above that already
  /// calls a local save* function — see each call site.
  void _pushProgressToServer() {
    final uid = authService.uid;
    if (uid == null) return;
    () async {
      try {
        final highScores = await loadHighScores();
        // mixedCocktailIds is included here too — this push does a plain
        // overwrite (see LeagueRepository.pushProgress's own doc), so
        // omitting it would silently wipe the server's copy back to
        // empty on every call, undoing whatever progress_sync.dart's own
        // merge had already restored.
        final mixedCocktailIds = await loadMixedCocktailIds();
        await ref
            .read(leagueRepositoryProvider)
            .pushProgress(
              uid: uid,
              progress: PlayerProgress(
                credits: state.credits,
                highestTiers: state.highestTiers,
                highestLevelReached: state.highestLevelReached,
                highScores: highScores,
                mixedCocktailIds: mixedCocktailIds.toList(),
              ),
            );
        // Keeps progress_sync.dart's own "last confirmed in sync" marker
        // accurate for every push, not just the ones it makes itself —
        // otherwise a stale marker here would just make a later sync
        // trust the server over local one time too many, which is still
        // safe (the server already reflects this exact local state) but
        // there's no reason to leave it stale when it's this cheap to keep
        // current.
        await saveLastProgressSyncAt(DateTime.now());
      } catch (e, st) {
        debugPrint('Progress push failed (non-fatal): $e\n$st');
      }
    }();
  }

  /// Snapshots whatever's currently on the table so it can be restored
  /// next time MixolocoGame is built — called whenever GameScreen goes
  /// away (Home, or the app itself being backgrounded/closed), since the
  /// physics world itself doesn't survive that. Also persists the whole
  /// run to disk in the same call, so this one snapshot point covers both
  /// "leave and come back this session" and "pick up again tomorrow".
  Future<void> savePlacedItems(List<PlacedItem> items) async {
    state = state.copyWith(placedItems: items);
    await persistGameState();
  }

  /// Full reset after a game-over — score/order/table reset, but credits
  /// and the highest-tier/level records carry forward, since those are
  /// lifetime stats, not per-run ones. Starts back on Level 2 directly if
  /// that's the player's lifetime record, per [_freshGame].
  void restart() {
    _finalizeAbandonedRun();
    state = _freshGame(
      credits: state.credits,
      highestTiers: state.highestTiers,
      highestLevelReached: state.highestLevelReached,
    );
  }

  /// Settings' "Reset Progress" — puts the evolution/level lifetime
  /// record back to a brand-new install's starting point and immediately
  /// starts a fresh Level 1 run reflecting that, overwriting whatever
  /// save was on disk so a cold restart afterward can't resurrect the
  /// pre-reset run. Credits are untouched — this is specifically the
  /// "evo and level" reset the Settings row promises, not a full wipe.
  /// Also pushed to the server (see _pushProgressToServer) — without
  /// this, a signed-in player's next sync would just pull the pre-reset
  /// tiers/level straight back down via the Google-backup's max() merge.
  Future<void> resetProgression() async {
    await resetTierProgression();
    state = _freshGame(
      credits: state.credits,
      highestTiers: const [],
      highestLevelReached: 1,
    );
    await persistGameState();
    _pushProgressToServer();
  }

  /// Re-reads the lifetime fields (credits, highest tiers, highest level)
  /// from disk into live state — called after progress_sync.dart merges a
  /// Google-account backup into SharedPreferences, since that write
  /// bypasses this notifier entirely and otherwise wouldn't show up until
  /// the next full app restart (state doesn't re-read from disk on its
  /// own). Deliberately leaves everything about the CURRENT run (score,
  /// table, order) untouched — only the lifetime stats actually came from
  /// the merge.
  Future<void> refreshLifetimeFieldsFromDisk() async {
    state = state.copyWith(
      credits: await loadCredits(),
      highestTiers: await loadHighestTiers(kLevelCount),
      highestLevelReached: await loadHighestLevelReached(),
    );
  }
}

final gameStateProvider = NotifierProvider<GameStateNotifier, BoardState>(
  GameStateNotifier.new,
);
