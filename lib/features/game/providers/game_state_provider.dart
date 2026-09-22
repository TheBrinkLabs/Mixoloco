import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_service.dart';
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

/// Credits awarded for reaching a new highest evolution tier, ever.
const kTierUnlockReward = 100;

/// Credits awarded each time a cocktail order is completed.
const kCocktailCreditReward = 100;

/// Credits awarded for every [kScoreCreditThreshold] points of score
/// reached within a single game — a repeatable, per-run milestone
/// (unlike the once-ever highest-tier reward), so it resets each game
/// along with the score itself.
const kScoreCreditThreshold = 10000;
const kScoreCreditReward = 100;

/// Score interval between MREC ad breaks within a single run — every
/// [kAdBreakScoreThreshold] points, GameScreen shows showAdBreakScreen()
/// (see BoardState.pendingAdBreak/GameStateNotifier.acknowledgeAdBreak).
const kAdBreakScoreThreshold = 20000;

/// Credits awarded for watching a rewarded ad from the Shop.
const kShopAdCreditReward = 200;

/// Credits to remove every cherry currently on the table, from the
/// Cherry Bomb button.
const kCherryBombCost = 100;

/// Credits for the original Shake — impulse pulses only, no size change
/// — from the Shake button.
const kShakerCost = 100;

/// Credits for Mega-Shake — the same impulse pulses as Shake, plus every
/// item shrinking/wobbling/flexing for the duration — from the
/// Mega-Shake button.
const kMegaShakeCost = 400;

/// Credits to clear every vodka, rum, and blue curaçao item currently on
/// the table from the Alcohol-Free button.
const kAlcoholFreeCost = 300;

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

  /// Credits earned/spent this game and every game before it — persists
  /// to disk, see progression_service.dart.
  final int credits;

  /// The highest evolution tier ever reached on the beach bar (Level 1),
  /// across every game ever played (0 = Cherry) — also persists to disk.
  final int highestTierUnlocked;

  /// The highest evolution tier ever reached on the rooftop bar (Level
  /// 2) — same shape as [highestTierUnlocked], separate chain. -1 means
  /// "never reached Level 2 at all" (0 = Cherry, same as Level 1's
  /// lowest, would otherwise be indistinguishable from "never played").
  final int highestTierUnlockedLevel2;

  /// The highest bar level ever reached, lifetime (1 or 2) — once this
  /// is 2, every new game starts there directly (see _freshGame) instead
  /// of back on the beach, and the home screen's "Unlocked" display shows
  /// a Level 2 ingredient regardless of [highestTierUnlockedLevel2]'s own
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
  /// (unlike [highestTierUnlocked], which is a lifetime record).
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

  /// Whether the level-up celebration (see level_up_screen.dart) has
  /// already been shown for this run's transition to level 2 — guards
  /// against re-showing it if the game rebuilds while it's still level 2.
  /// Resets every game (there's nothing to guard once level resets too).
  final bool levelUpCelebrationShown;

  const BoardState({
    required this.current,
    required this.upcoming,
    required this.order,
    required this.cocktailsMade,
    required this.score,
    required this.gameOver,
    required this.credits,
    required this.highestTierUnlocked,
    this.highestTierUnlockedLevel2 = -1,
    this.highestLevelReached = 1,
    this.continueOfferUsed = false,
    this.scoreCreditThresholdsAwarded = 0,
    this.placedItems = const [],
    this.completedCocktailIds = const {},
    this.jugReached = false,
    this.level = 1,
    this.adBreakThresholdsShown = 0,
    this.levelUpCelebrationShown = false,
  });

  /// Whether the score has crossed a new [kAdBreakScoreThreshold]
  /// milestone that hasn't shown its ad break yet — GameScreen watches
  /// this and pushes [showAdBreakScreen] when it flips true.
  bool get pendingAdBreak => score ~/ kAdBreakScoreThreshold > adBreakThresholdsShown;

  BoardState copyWith({
    Ingredient? current,
    List<Ingredient>? upcoming,
    Object? order = _unset,
    int? cocktailsMade,
    int? score,
    bool? gameOver,
    int? credits,
    int? highestTierUnlocked,
    int? highestTierUnlockedLevel2,
    int? highestLevelReached,
    bool? continueOfferUsed,
    int? scoreCreditThresholdsAwarded,
    List<PlacedItem>? placedItems,
    Set<String>? completedCocktailIds,
    bool? jugReached,
    int? level,
    int? adBreakThresholdsShown,
    bool? levelUpCelebrationShown,
  }) {
    return BoardState(
      current: current ?? this.current,
      upcoming: upcoming ?? this.upcoming,
      order: identical(order, _unset) ? this.order : order as CocktailRecipe?,
      cocktailsMade: cocktailsMade ?? this.cocktailsMade,
      score: score ?? this.score,
      gameOver: gameOver ?? this.gameOver,
      credits: credits ?? this.credits,
      highestTierUnlocked: highestTierUnlocked ?? this.highestTierUnlocked,
      highestTierUnlockedLevel2: highestTierUnlockedLevel2 ?? this.highestTierUnlockedLevel2,
      highestLevelReached: highestLevelReached ?? this.highestLevelReached,
      continueOfferUsed: continueOfferUsed ?? this.continueOfferUsed,
      scoreCreditThresholdsAwarded: scoreCreditThresholdsAwarded ?? this.scoreCreditThresholdsAwarded,
      placedItems: placedItems ?? this.placedItems,
      completedCocktailIds: completedCocktailIds ?? this.completedCocktailIds,
      jugReached: jugReached ?? this.jugReached,
      level: level ?? this.level,
      adBreakThresholdsShown: adBreakThresholdsShown ?? this.adBreakThresholdsShown,
      levelUpCelebrationShown: levelUpCelebrationShown ?? this.levelUpCelebrationShown,
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
  const PlacedItem({required this.tier, required this.x, required this.y});
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
    _loadPersisted();
    return _freshGame(credits: 0, highestTierUnlocked: 0, highestTierUnlockedLevel2: -1, highestLevelReached: 1);
  }

  /// Credits and the highest-tier records live on disk, not in this
  /// provider's initial (synchronous) state — this patches them in the
  /// moment they're loaded. A brief 0-credits flash on cold start is the
  /// tradeoff for keeping GameStateNotifier a plain, synchronous Notifier
  /// rather than an AsyncNotifier throughout. If a run was in progress
  /// last time the app closed (see persistGameState), that whole board
  /// replaces the fresh one this Notifier started with instead of just
  /// patching the lifetime fields onto it.
  Future<void> _loadPersisted() async {
    final credits = await loadCredits();
    final highest = await loadHighestTier();
    final highestLevel2 = await loadHighestTierLevel2();
    final highestLevelReached = await loadHighestLevelReached();
    final savedJson = await loadGameJson();
    final restored = savedJson == null
        ? null
        : _decodeState(
            savedJson,
            credits: credits,
            highestTierUnlocked: highest,
            highestTierUnlockedLevel2: highestLevel2,
            highestLevelReached: highestLevelReached,
          );
    // Falls back to a freshly-built game (not just a copyWith patch onto
    // the level-1 default build() started with) when there's no save to
    // restore — a copyWith patch would leave level/order/current/upcoming
    // at their level-1 defaults even when highestLevelReached says this
    // player should be starting straight on the rooftop bar.
    state =
        restored ??
        _freshGame(
          credits: credits,
          highestTierUnlocked: highest,
          highestTierUnlockedLevel2: highestLevel2,
          highestLevelReached: highestLevelReached,
        );
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
    'continueOfferUsed': s.continueOfferUsed,
    'scoreCreditThresholdsAwarded': s.scoreCreditThresholdsAwarded,
    'placedItems': s.placedItems.map((p) => {'tier': p.tier, 'x': p.x, 'y': p.y}).toList(),
    'completedCocktailIds': s.completedCocktailIds.toList(),
    'jugReached': s.jugReached,
    'level': s.level,
    'adBreakThresholdsShown': s.adBreakThresholdsShown,
    'levelUpCelebrationShown': s.levelUpCelebrationShown,
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
    required int highestTierUnlocked,
    required int highestTierUnlockedLevel2,
    required int highestLevelReached,
  }) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final orderId = map['orderId'] as String?;
      final level = map['level'] as int;
      final recipes = level >= 2 ? kCocktailRecipesLevel2 : kCocktailRecipes;
      return BoardState(
        current: findIngredientById(map['currentId'] as String),
        upcoming: (map['upcomingIds'] as List).map((id) => findIngredientById(id as String)).toList(),
        order: orderId == null ? null : recipes.firstWhere((r) => r.id == orderId),
        cocktailsMade: map['cocktailsMade'] as int,
        score: map['score'] as int,
        gameOver: map['gameOver'] as bool,
        credits: credits,
        highestTierUnlocked: highestTierUnlocked,
        highestTierUnlockedLevel2: highestTierUnlockedLevel2,
        highestLevelReached: highestLevelReached,
        continueOfferUsed: map['continueOfferUsed'] as bool,
        scoreCreditThresholdsAwarded: map['scoreCreditThresholdsAwarded'] as int,
        placedItems: (map['placedItems'] as List)
            .map((p) => PlacedItem(tier: p['tier'] as int, x: (p['x'] as num).toDouble(), y: (p['y'] as num).toDouble()))
            .toList(),
        completedCocktailIds: (map['completedCocktailIds'] as List).cast<String>().toSet(),
        jugReached: map['jugReached'] as bool,
        level: level,
        adBreakThresholdsShown: map['adBreakThresholdsShown'] as int,
        levelUpCelebrationShown: map['levelUpCelebrationShown'] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  BoardState _freshGame({
    required int credits,
    required int highestTierUnlocked,
    required int highestTierUnlockedLevel2,
    required int highestLevelReached,
  }) {
    _ingredientBag = [];
    final level = highestLevelReached;
    final highestForLevel = level >= 2 ? highestTierUnlockedLevel2 : highestTierUnlocked;
    return BoardState(
      current: _randomIngredient(level, highestForLevel),
      upcoming: List.generate(3, (_) => _randomIngredient(level, highestForLevel)),
      order: level >= 2 ? kStarterCocktailLevel2 : kStarterCocktail,
      cocktailsMade: 0,
      score: 0,
      gameOver: false,
      credits: credits,
      highestTierUnlocked: highestTierUnlocked,
      highestTierUnlockedLevel2: highestTierUnlockedLevel2,
      highestLevelReached: highestLevelReached,
      level: level,
      // A fresh game that *starts* on Level 2 (because that's already the
      // lifetime record) isn't the moment of leveling up — that already
      // happened, in whatever earlier run first reached it. Marking the
      // celebration pre-shown here is what stops GameScreen's
      // `board.level == 2 && !levelUpCelebrationShown` check from replaying
      // the "Level Complete!" popup on every single new game once a
      // player's actually reached the rooftop bar; without this, only a
      // genuine mid-run 1->2 transition (see enterLevel) should ever show
      // it, but every fresh Level 2 start did too.
      levelUpCelebrationShown: level >= 2,
    );
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
      final bag = List<Ingredient>.from(throwableIngredientsFor(level, highestTierUnlocked))..shuffle(_random);
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
    final highestForLevel = state.level >= 2 ? state.highestTierUnlockedLevel2 : state.highestTierUnlocked;
    final nextUpcoming = [...state.upcoming.skip(1), _randomIngredient(state.level, highestForLevel)];
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
      state = state.copyWith(score: newScore, credits: newCredits, scoreCreditThresholdsAwarded: newThresholdCount);
      saveCredits(newCredits);
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
    final newCredits = state.credits + kCocktailCreditReward;
    // No more auto-cycling to a new order — the starter's a one-off, and
    // every order after it has to be bought from the Cocktail Menu.
    state = state.copyWith(
      cocktailsMade: state.cocktailsMade + 1,
      order: null,
      credits: newCredits,
      completedCocktailIds: {...state.completedCocktailIds, recipe.id},
    );
    saveCredits(newCredits);
    _addScore(scoreForCocktail(recipe));
    _checkLevelUp();
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
    final isLevel2 = state.level >= 2;
    final currentHighest = isLevel2 ? state.highestTierUnlockedLevel2 : state.highestTierUnlocked;
    if (tier > currentHighest) {
      final newCredits = state.credits + kTierUnlockReward;
      if (isLevel2) {
        state = state.copyWith(highestTierUnlockedLevel2: tier, credits: newCredits);
        saveHighestTierLevel2(tier);
      } else {
        state = state.copyWith(highestTierUnlocked: tier, credits: newCredits);
        saveHighestTier(tier);
      }
      saveCredits(newCredits);
    }
    final chainLastTier = isLevel2 ? kEvolutionChainLevel2.last.tier : kEvolutionChain.last.tier;
    if (!state.jugReached && tier == chainLastTier) {
      state = state.copyWith(jugReached: true);
      _checkLevelUp();
    }
  }

  /// Every Level 1 cocktail recipe made at least once, plus the Jug
  /// reached, on this run — advances to Level 2. A no-op once already
  /// there (there's no Level 3 to advance to further). Only flips
  /// [BoardState.level] itself; GameScreen notices that flip and calls
  /// [enterLevel] to actually reset the table/queue/order for the new
  /// chain once its celebration sequence has played out (see
  /// level_up_overlay.dart) — doing that heavy a reset from inside this
  /// callback, mid physics-contact-resolution, would be a bad time for
  /// the whole board to change under MixolocoGame's feet.
  void _checkLevelUp() {
    if (state.level >= 2) return;
    if (state.jugReached && state.completedCocktailIds.length >= kCocktailRecipes.length) {
      state = state.copyWith(level: 2);
    }
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
    final highestForLevel = level >= 2 ? state.highestTierUnlockedLevel2 : state.highestTierUnlocked;
    final newCurrent = _randomIngredient(level, highestForLevel);
    final newUpcoming = List.generate(3, (_) => _randomIngredient(level, highestForLevel));
    final newHighestLevelReached = level > state.highestLevelReached ? level : state.highestLevelReached;
    state = state.copyWith(
      level: level,
      current: newCurrent,
      upcoming: newUpcoming,
      order: level >= 2 ? kStarterCocktailLevel2 : kStarterCocktail,
      jugReached: false,
      completedCocktailIds: {},
      highestLevelReached: newHighestLevelReached,
    );
    saveHighestLevelReached(newHighestLevelReached);
  }

  /// Marks the current score-based ad-break milestone as shown — called
  /// once GameScreen has actually pushed showAdBreakScreen() for it, so
  /// [BoardState.pendingAdBreak] goes back to false until the next
  /// [kAdBreakScoreThreshold] is crossed.
  void acknowledgeAdBreak() {
    state = state.copyWith(adBreakThresholdsShown: state.score ~/ kAdBreakScoreThreshold);
  }

  /// Marks the level-up celebration as shown — called once its full
  /// sequence (celebration → interstitial) has played out.
  void acknowledgeLevelUpCelebration() {
    state = state.copyWith(levelUpCelebrationShown: true);
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
  }

  /// Spends [amount] credits if there are enough; returns whether it
  /// went through. Used by both the Shaker Maker and the Cocktail Menu —
  /// callers only act on the physics/order side once this returns true.
  bool spendCredits(int amount) {
    if (state.credits < amount) return false;
    final newCredits = state.credits - amount;
    state = state.copyWith(credits: newCredits);
    saveCredits(newCredits);
    return true;
  }

  /// Buys [recipe] as the active order — replaces whatever order (if
  /// any) is already in progress. Returns whether the purchase went
  /// through (i.e. there were enough credits).
  bool buyCocktail(CocktailRecipe recipe) {
    if (!spendCredits(recipe.price)) return false;
    state = state.copyWith(order: recipe);
    return true;
  }

  void registerGameOver() {
    if (state.gameOver) return;
    state = state.copyWith(gameOver: true);
    // Fire-and-forget — the high-scores screen reloads from disk itself,
    // so nothing here needs to await this write.
    recordScore(state.score);

    // Also fire-and-forget, and silently skipped if there's no signed-in
    // uid yet (offline cold start, Firebase not set up, or the player
    // has never opened the league screen to sign in at all) — league
    // features treat a missing uid as "unavailable for now," same as
    // AuthService's own doc comment. submitWeeklyScore only actually
    // raises the stored value if this run beat the week's existing best.
    final uid = authService.uid;
    if (uid != null && state.score > 0) {
      ref.read(leagueRepositoryProvider).submitWeeklyScore(uid: uid, score: state.score).catchError((e) {});
    }
  }

  /// Declines the once-per-game ad-continue offer — game stays over, but
  /// the offer itself won't be shown again this game.
  void declineContinue() {
    state = state.copyWith(continueOfferUsed: true);
  }

  /// Accepts the ad-continue offer — called once the (placeholder) ad
  /// has finished playing. MixolocoGame clears the vodka/rum itself
  /// (GameScreen wires that up alongside this); this just un-ends the
  /// game and marks the offer used.
  void continueAfterAd() {
    state = state.copyWith(gameOver: false, continueOfferUsed: true);
  }

  /// Snapshots whatever's currently on the table so it can be restored
  /// next time MixolocoGame is built — called whenever GameScreen goes
  /// away (Home, or the app itself being backgrounded/closed), since the
  /// physics world itself doesn't survive that. Also persists the whole
  /// run to disk in the same call, so this one snapshot point covers both
  /// "leave and come back this session" and "pick up again tomorrow".
  void savePlacedItems(List<PlacedItem> items) {
    state = state.copyWith(placedItems: items);
    persistGameState();
  }

  /// Full reset after a game-over — score/order/table reset, but credits
  /// and the highest-tier/level records carry forward, since those are
  /// lifetime stats, not per-run ones. Starts back on Level 2 directly if
  /// that's the player's lifetime record, per [_freshGame].
  void restart() => state = _freshGame(
    credits: state.credits,
    highestTierUnlocked: state.highestTierUnlocked,
    highestTierUnlockedLevel2: state.highestTierUnlockedLevel2,
    highestLevelReached: state.highestLevelReached,
  );

  /// Settings' "Reset Progress" — puts the evolution/level lifetime
  /// record back to a brand-new install's starting point and immediately
  /// starts a fresh Level 1 run reflecting that, overwriting whatever
  /// save was on disk so a cold restart afterward can't resurrect the
  /// pre-reset run. Credits are untouched — this is specifically the
  /// "evo and level" reset the Settings row promises, not a full wipe.
  Future<void> resetProgression() async {
    await resetTierProgression();
    state = _freshGame(credits: state.credits, highestTierUnlocked: 0, highestTierUnlockedLevel2: -1, highestLevelReached: 1);
    await persistGameState();
  }
}

final gameStateProvider = NotifierProvider<GameStateNotifier, BoardState>(GameStateNotifier.new);
