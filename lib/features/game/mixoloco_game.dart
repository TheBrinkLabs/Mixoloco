import 'dart:async' show unawaited;
import 'dart:math' show Random, cos, pi, sin;
import 'package:flame/components.dart' show Anchor;
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart'
    show Color, Colors, Curves, ValueNotifier;
import '../../core/widgets/bar_backdrop.dart' show kAimConvergenceRatio;
import '../../data/models/cocktail_recipe.dart';
import '../../data/models/ingredient.dart';
import 'board_geometry.dart';
import 'components/cocktail_reveal_component.dart';
import 'components/game_over_line_component.dart';
import 'components/ingredient_body_component.dart';
import 'components/ingredient_sprite.dart';
import 'components/merge_explosion_component.dart';
import 'components/staging_component.dart';
import 'components/table_boundary_component.dart';
import 'providers/game_state_provider.dart'
    show BoardState, PlacedItem, kMaxLevel;

/// The physics world is laid out in meters (Box2D's own comfortable
/// range), with the table's width fixed at this many of them — its
/// height then follows whatever the screen's own aspect ratio is, so the
/// table never looks stretched.
const kWorldWidthMeters = 4.0;

/// Tier 0 (mint)'s radius, in meters — every later tier grows from this
/// by [kTierGrowthFactor] per step. Two successive 5% cuts from the
/// original 0.19 (first per feedback that Level 1 played a little too
/// hard, then a further "another 5%" pass) — since every tier's size is
/// derived from this one constant (both chains share it), shrinking it
/// here shrinks every ingredient on the table by the same amount,
/// giving the board more breathing room before it fills up.
const kBaseRadiusMeters = 0.19 * 0.95 * 0.95;

/// Every item on the game table, art and collision shape alike — the
/// average size the old far-to-near depth shrink (85%..100%) used to
/// give, kept now that items draw at one consistent size everywhere.
const kTableItemScale = 0.925;

/// How much bigger Level 2 (rooftop) plays than Level 1, per tier — 1%
/// for tier 0, 2% for tier 1, 3% for tier 2, and so on (tier index + 1,
/// as a percent), rather than one flat factor across every tier. Started
/// as a flat 5% for every tier per earlier feedback, then changed to
/// this progressive step per further feedback.
double _level2SizeMultiplier(int tier) => 1.0 + (tier + 1) * 0.01;

/// How much bigger Level 3 (safari) plays than Level 1, flat across every
/// tier — per feedback the safari table was reading too easy; unlike
/// Level 2's progressive per-tier bump above, this is a straightforward
/// flat increase at every tier.
const kLevel3SizeMultiplier = 1.15;

/// Pulls items toward the far/serving edge (small y) — "the table slopes
/// away from us," so a dropped item accelerates that direction on its
/// own the same way a dropped item accelerates downward in a normal
/// falling-block game; no throw arc is needed; see StagingComponent.
const kGravityMagnitude = 15.0;

/// How far up from the near/staging edge the game-over line sits, as a
/// fraction of the table's height — "a line 25% from the bottom."
const kGameOverLineFraction = 0.25;

/// A body slower than this (m/s) counts as "settled" for the overflow
/// check — see [MixolocoGame._checkOverflow]. Well below anything a
/// freely-falling drop reaches under kGravityMagnitude within its first
/// moments, but comfortably above the tiny residual creep a resting,
/// friction-damped pile can have.
const kRestSpeedThreshold = 0.35;

/// The largest single dt (seconds) ever handed to the physics step — see
/// MixolocoGame.update. A locked screen or backgrounded app can hand
/// back a dt of many seconds on the next frame; this caps it so the
/// simulation catches up smoothly instead of in one unstable leap.
const kMaxPhysicsStepSeconds = 1 / 20;

/// Played once for every same-tier merge — relative to FlameAudio's
/// default 'assets/audio/' prefix, see pubspec.yaml.
const kMergeSoundFile = 'bubble_pop.wav';

/// Played once a cocktail order completes, alongside CocktailRevealComponent.
const kCocktailSoundFile = 'pour.wav';

/// The table's physical near edge sits at the true bottom of the world
/// (y = world height); the staged glass hovers this far above it.
/// Nudged up (a bigger inset) by roughly what 2% of screen height works
/// out to in world meters at this world's scale (kWorldWidthMeters=4
/// over a typical ~2.2:1 phone aspect ratio).
const kStagingInset = 0.5;

/// The physical bar table: a Box2D world where items fall (accelerated by
/// [kGravityMagnitude] toward the far edge, exactly like a Suika-style
/// merge game mirrored top/bottom), roll to rest against the curved
/// TableBoundaryComponent, and merge on contact when two touching items
/// share a tier. Game *state* (score, the staged/upcoming ingredients,
/// the cocktail order in progress) stays owned by GameStateNotifier —
/// this owns everything physically on the table and reports outcomes
/// back via its callbacks.
class MixolocoGame extends Forge2DGame {
  MixolocoGame({
    required this.onMerge,
    required this.onCocktailComplete,
    required this.onGameOver,
    required this.onGameComplete,
    required this.onThrowCommitted,
    required this.onTierSeen,
    this.initialItems = const [],
    this.sfxEnabled = true,
    int level = 1,
  }) : _level = level,
       super(gravity: Vector2(0, -kGravityMagnitude));

  /// Which evolution chain/cocktail list is currently active — 1 for the
  /// beach bar ([kEvolutionChain]/[kCocktailRecipes]), 2 for the rooftop
  /// bar ([kEvolutionChainLevel2]/[kCocktailRecipesLevel2]), 3 for the
  /// safari bar ([kEvolutionChainLevel3]/[kCocktailRecipesLevel3]). All
  /// three chains' art is preloaded upfront in onLoad regardless of
  /// which is active at construction, so [switchToLevel] never needs an
  /// async await mid-game.
  int _level;
  List<Ingredient> get _chain => evolutionChainForLevel(_level);

  /// The actual physics radius for [tier], including both
  /// [Ingredient.sizeMultiplier] and whichever per-level bump applies —
  /// Level 2's progressive per-tier bump (see [_level2SizeMultiplier])
  /// or Level 3's flat [kLevel3SizeMultiplier]. The single source every
  /// radius computation below reads from, so neither rule can drift out
  /// of sync between them.
  double _radiusForTier(int tier, Ingredient ingredient) =>
      radiusForTier(tier, kBaseRadiusMeters) *
      kTableItemScale *
      ingredient.sizeMultiplier *
      (_level == 2
          ? _level2SizeMultiplier(tier)
          : (_level == 3 ? kLevel3SizeMultiplier : 1.0));

  /// Items to recreate on the table as soon as the world's ready — a
  /// snapshot taken via [capturePlacedItems] the last time this screen
  /// was left, so leaving and coming back doesn't wipe the table.
  final List<PlacedItem> initialItems;

  /// The Settings sound-effects toggle, combined with the gameplay
  /// screen's own top-left mute override (see
  /// AudioSettings.effectiveSfxEnabled) — mutable (not a one-time
  /// snapshot) since GameScreen updates this live the moment either one
  /// changes, rather than only reflecting whatever it was set to when
  /// this game was constructed.
  bool sfxEnabled;

  /// A same-tier merge happened at [tier] (the tier of the two items that
  /// merged, not the tier they became) — award `10 * 2^tier`.
  final void Function(int tier) onMerge;

  /// [recipe]'s required ingredients finished touching/clustering on the
  /// table — award 10x its credit price in score and move on to a new
  /// order.
  final void Function(CocktailRecipe recipe) onCocktailComplete;

  /// The 25%-line has had an item entirely past it for two drops running
  /// — the run is over.
  final void Function() onGameOver;

  /// Two items at the very top of the *final* level's chain just
  /// merged — there's no higher tier for them to become, so this is the
  /// actual win condition rather than a no-op (see [_tryMerge]).
  final void Function() onGameComplete;

  /// A drop was actually committed to the table (spawned, not aborted by
  /// game-over) — advance the staged/upcoming ingredient queue.
  final void Function() onThrowCommitted;

  /// An item of [tier] just appeared on the table, by a drop or a merge
  /// — the provider only banks a reward the first time a given tier is
  /// ever seen, so this fires unconditionally and lets it decide.
  final void Function(int tier) onTierSeen;

  late StagingComponent staging;
  TableBoundaryComponent? _boundary;
  GameOverLineComponent? _gameOverLine;

  BoardGeometry _geometry = BoardGeometry.empty;
  double _worldHeight = kWorldWidthMeters;
  double get worldHeight => _worldHeight;
  CocktailRecipe? _currentOrder;
  Ingredient? _pendingIngredient;
  Ingredient? _latestIngredient;
  BoardGeometry? _pendingGeometry;

  /// A brief pause between committing a throw and the next glass becoming
  /// available — was effectively zero before (syncBoard reset [_busy]
  /// back to false on the very next board update, which happens almost
  /// the instant a throw commits), letting throws fire far faster than
  /// intended. [staging] plays a short slide-up-into-place reveal to sell
  /// the pause once it ends — see StagingComponent.ingredient.
  static const kThrowCooldown = 0.45;
  double _cooldownRemaining = 0;

  bool _busy = false;
  bool _gameOverTriggered = false;
  bool _gameCompleteTriggered = false;
  bool _initialItemsSpawned = false;
  int _overflowStreak = 0;

  /// Mirrors GameScreen's own `blockInput` (set every build — see its
  /// IgnorePointer) so [_handleDrop] can bail out even for a drag that's
  /// already past Flutter's hit-test. IgnorePointer only stops a *new*
  /// gesture from starting; once StagingComponent's drag recognizer has
  /// already won the gesture arena, Flutter keeps delivering that same
  /// drag's move/up events to it regardless of a later `ignoring` change
  /// (hit-testing isn't re-checked mid-gesture) — so a drag that began
  /// just before an ad-break/level-up/game-over flips blockInput true
  /// could otherwise still commit a throw after pauseEngine() runs.
  bool inputBlocked = false;

  /// How many merge-explosion/cocktail-reveal animations are currently
  /// mid-flight — GameScreen's ad-break trigger waits for this to hit zero
  /// before pausing the engine, so a score-threshold crossing mid-burst
  /// doesn't freeze the table on a half-played explosion.
  int _activeAnimations = 0;
  bool get isAnimating => _activeAnimations > 0;

  final Set<IngredientBodyComponent> _liveBodies = {};
  final Map<IngredientBodyComponent, Set<IngredientBodyComponent>> _adjacency =
      {};

  /// Set by handleContactBegin/End — Box2D can fire many contact events
  /// in a single frame (a heavy drop landing on a big pile, or a shake
  /// pulse), and _checkCocktailCompletion is a full graph walk over every
  /// live body; running it once per *event* rather than once per *frame*
  /// meant a busy frame could re-walk the whole table's contact graph
  /// dozens of times over, which is exactly the kind of cost that was
  /// invisible early in a run (few bodies) but got progressively laggier
  /// as more items piled up over a long session.
  bool _cocktailCheckDirty = false;

  /// _sweepForMerges is a fallback safety net for near-misses Box2D's own
  /// contact events didn't catch — it doesn't need to run every single
  /// physics tick (60/sec) to still catch those quickly; throttling it
  /// cuts its steady-state cost substantially on a table with a lot of
  /// bodies on it, for a barely-perceptible detection delay.
  static const _sweepInterval = 0.15;
  double _sweepTimer = 0;

  /// Set whenever a body is added to the table — the one event that can
  /// introduce a near-miss pair the settled-table check below wouldn't
  /// otherwise catch (a freshly spawned body is, for a frame or two,
  /// moving fast enough that the velocity check already covers it, but
  /// this also catches it the instant it's added, before it's even
  /// started moving). Cleared once a sweep has actually run.
  bool _bodiesChangedSinceSweep = true;

  /// A hard ceiling on how many bodies can ever be live on the table at
  /// once. TableBoundaryComponent lets a pile spread out sideways quite a
  /// bit before it ever reaches the near-edge overflow line (see
  /// _checkOverflow) — a long session where throws keep outpacing merges
  /// can accumulate far more bodies than that line alone would catch,
  /// and every per-frame pass here (physics, the merge sweep, the
  /// cocktail-cluster walk) scales with body count. This ends the run
  /// before that count ever gets large enough to matter, independent of
  /// where on the table the bodies actually are.
  static const kMaxLiveBodies = 90;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  void update(double dt) {
    // The screen locking (or the app being backgrounded) pauses Flutter's
    // frame callbacks entirely — Flame never calls update() while that's
    // happening. The moment it resumes, the next dt reflects the *whole*
    // gap, which can be seconds or minutes. Box2D's solver assumes small,
    // consistent steps; a single huge one makes it wildly unstable
    // (everything can leap/tunnel at once) and can leave the simulation
    // in a state so overlapped/extreme that it stays expensive — looking
    // like a hang — for a long time afterward. Capping the step here
    // turns "catch up in one giant leap" into "catch up smoothly over a
    // few frames" instead.
    final clampedDt = dt > kMaxPhysicsStepSeconds ? kMaxPhysicsStepSeconds : dt;
    super.update(clampedDt);
    _purgeCorruptedBodies();
    _resolvePops(clampedDt);
    _unstickContacts(clampedDt);
    _sweepTimer -= clampedDt;
    if (_sweepTimer <= 0) {
      _sweepTimer = _sweepInterval;
      _sweepForMerges();
    }
    if (_cocktailCheckDirty) {
      _cocktailCheckDirty = false;
      _checkCocktailCompletion();
    }
    _updateShake(clampedDt);

    if (_cooldownRemaining > 0) {
      _cooldownRemaining -= clampedDt;
      if (_cooldownRemaining <= 0) {
        _busy = false;
        final next = _latestIngredient;
        if (next != null) _setStagedIngredient(next);
      }
    }
  }

  /// A body's position can (rarely) end up NaN from a degenerate physics
  /// case — see _spawnBody's jitter for the main defense against that.
  /// Once it happens, every future step involving that body corrupts
  /// too, since arithmetic with NaN stays NaN — that's what actually
  /// causes a hang (the solver churning on an unresolvable state)
  /// instead of a clean crash. Purging it here lets the game recover on
  /// its own rather than staying stuck.
  void _purgeCorruptedBodies() {
    // A read-only pass over the live set directly (no List.of() copy) —
    // this runs every single update() (60/sec), and a NaN body is rare
    // enough that the common case should cost nothing beyond the scan
    // itself. Only allocates a (tiny, almost-never-needed) removal list
    // on the rare frame one's actually found, and removes in a second
    // pass since _removeBody mutates _liveBodies and can't safely run
    // while iterating it directly.
    List<IngredientBodyComponent>? corrupted;
    for (final b in _liveBodies) {
      if (!b.isMounted) continue;
      final pos = b.body.position;
      if (pos.x.isNaN || pos.y.isNaN) {
        (corrupted ??= []).add(b);
      }
    }
    if (corrupted == null) return;
    for (final b in corrupted) {
      _removeBody(b);
    }
  }

  /// A safety net alongside beginContact-triggered merging: a same-tier
  /// pair can come to rest touching without Box2D firing a fresh begin
  /// event (e.g. one was rejected earlier while still a few mm apart).
  /// A cheap bounding-radius prefilter here; _tryMerge then requires the
  /// real shapes to actually be touching.
  ///
  /// A body added to [_liveBodies] this same frame may not be mounted
  /// yet — Flame mounts newly-added components on the *next* tick, not
  /// synchronously — and its `.body` isn't safe to touch until then,
  /// so those are skipped here (and picked up naturally once mounted,
  /// a frame later).
  void _sweepForMerges() {
    // The expensive part below is the per-tier pairwise distance check —
    // O(bodies-of-that-tier squared), run every _sweepInterval regardless
    // of whether the table's actually changed since the last pass. If
    // nothing's moved and no body's been added since then, a fresh sweep
    // can only find the exact same (already-resolved) pairs it found last
    // time, so it's safe to skip entirely. This first pass is still O(n)
    // over every live body, but a single velocity-length check per body
    // is far cheaper than the nested distance comparisons it's gating —
    // real savings on a table that's settled (the common case once a
    // combo's finished playing out) with a lot of bodies on it.
    if (!_bodiesChangedSinceSweep) {
      final anyMoving = _liveBodies.any(
        (b) => !b.consumed && b.isMounted && b.body.linearVelocity.length >= kRestSpeedThreshold,
      );
      if (!anyMoving) return;
    }
    _bodiesChangedSinceSweep = false;

    final byTier = <int, List<IngredientBodyComponent>>{};
    for (final b in _liveBodies) {
      if (b.consumed || !b.isMounted) continue;
      byTier.putIfAbsent(b.tier, () => []).add(b);
    }
    for (final group in byTier.values) {
      if (group.length < 2) continue;
      for (var i = 0; i < group.length; i++) {
        final a = group[i];
        if (a.consumed) continue;
        for (var j = i + 1; j < group.length; j++) {
          final b = group[j];
          if (b.consumed) continue;
          final reach = a.contactRadius + b.contactRadius + _mergeTouchTolerance;
          if (a.body.position.distanceTo(b.body.position) <= reach) {
            _tryMerge(a, b);
            if (a.consumed) break;
          }
        }
      }
    }
  }

  /// Pre-created, reused players for the merge sound — plain
  /// `FlameAudio.play()` creates a brand-new AudioPlayer (and its
  /// platform-channel listeners) on *every* call and nothing ever
  /// disposes them; merges happen very often, so over a long session
  /// that leaked one AudioPlayer per merge, growing with total merges
  /// (i.e. with score/playtime, not with how many items happen to be on
  /// the table right now) — a much better match for "gets laggier the
  /// longer/higher-scoring the session" than anything actually scaling
  /// with the live body count. AudioPool avoids this: it hands out
  /// players from a small fixed pool and recycles them once playback
  /// completes instead of creating a fresh one each time.
  AudioPool? _mergePool;
  AudioPool? _cocktailPool;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    await preloadIngredientArt([
      ...kEvolutionChain,
      ...kEvolutionChainLevel2,
      ...kEvolutionChainLevel3,
      ...kEvolutionChainLevel4,
      ...kEvolutionChainLevel5,
    ]);
    await preloadImageAssets([
      for (final recipe in [
        ...kCocktailRecipes,
        ...kCocktailRecipesLevel2,
        ...kCocktailRecipesLevel3,
        ...kCocktailRecipesLevel4,
        ...kCocktailRecipesLevel5,
      ])
        recipe.assetPath,
    ]);
    try {
      _mergePool = await FlameAudio.createPool(
        kMergeSoundFile,
        minPlayers: 2,
        maxPlayers: 6,
      );
      _cocktailPool = await FlameAudio.createPool(
        kCocktailSoundFile,
        minPlayers: 1,
        maxPlayers: 2,
      );
    } catch (_) {
      // Soft failure — _playMergeSound/_playCocktailSound just no-op if
      // their pool never got created, same spirit as the art preloaders.
    }
    staging = StagingComponent(
      worldWidth: kWorldWidthMeters,
      worldHeight: _worldHeight,
      spawnY: _worldHeight - kStagingInset,
      onDrop: _handleDrop,
    );
    world.add(staging);
    final geometry = _pendingGeometry;
    if (geometry != null) _applyGeometry(geometry);
  }

  void updateGeometry(BoardGeometry geometry) {
    if (!isLoaded) {
      _pendingGeometry = geometry;
      return;
    }
    _applyGeometry(geometry);
  }

  void syncBoard(BoardState board) {
    // Switching to a new order (e.g. Cocktail Mode's auto-pick) can land on
    // a recipe whose ingredients are already sitting on the table, already
    // touching — without dirtying the check here, nothing re-evaluates that
    // cluster until some unrelated contact begin/end event fires later,
    // which is what showed up as "had the ingredients but it took several
    // more throws to complete."
    if (board.order?.id != _currentOrder?.id) _cocktailCheckDirty = true;
    _currentOrder = board.order;
    _latestIngredient = board.current;
    if (!isLoaded) {
      _pendingIngredient = board.current;
      return;
    }
    // While a throw's cooldown is running, the cooldown's own completion
    // in update() reveals [_latestIngredient] instead — staging it here
    // too would skip the intended pause.
    if (_cooldownRemaining <= 0 && !_busy) {
      _setStagedIngredient(board.current);
    }
    if (board.gameOver && !_gameOverTriggered) {
      _gameOverTriggered = true;
      staging.hide();
    }
  }

  void _setStagedIngredient(Ingredient ingredient) {
    staging.radius = _radiusForTier(ingredient.tier, ingredient);
    staging.ingredient = ingredient;
  }

  void _applyGeometry(BoardGeometry geometry) {
    final changed =
        !_geometry.isValid ||
        (geometry.width - _geometry.width).abs() > 0.5 ||
        (geometry.height - _geometry.height).abs() > 0.5;
    _geometry = geometry;
    if (!changed && _boundary != null) return;

    _worldHeight = kWorldWidthMeters * (geometry.height / geometry.width);
    metersToPixels = geometry.width / kWorldWidthMeters;
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();

    _boundary?.removeFromParent();
    _boundary = TableBoundaryComponent(
      worldWidth: kWorldWidthMeters,
      worldHeight: _worldHeight,
    );
    world.add(_boundary!);

    _gameOverLine?.removeFromParent();
    _gameOverLine = GameOverLineComponent(
      worldWidth: kWorldWidthMeters,
      lineY: _worldHeight * (1 - kGameOverLineFraction),
    );
    world.add(_gameOverLine!);

    staging.removeFromParent();
    staging = StagingComponent(
      worldWidth: kWorldWidthMeters,
      worldHeight: _worldHeight,
      spawnY: _worldHeight - kStagingInset,
      onDrop: _handleDrop,
    );
    world.add(staging);
    final pending = _pendingIngredient;
    if (pending != null) _setStagedIngredient(pending);

    if (!_initialItemsSpawned) {
      _initialItemsSpawned = true;
      for (final item in initialItems) {
        _spawnBody(tier: item.tier, position: Vector2(item.x, item.y), angle: item.angle);
      }
    }
  }

  void _handleDrop(double aimX) {
    if (_busy || _gameOverTriggered || inputBlocked) return;
    final ingredient = staging.ingredient;
    if (ingredient == null) return;

    _checkOverflow();
    if (_gameOverTriggered) return;

    _busy = true;
    _cooldownRemaining = kThrowCooldown;
    final tier = ingredient.tier;
    final radius = _radiusForTier(tier, ingredient);
    final spawnPos = Vector2(aimX, staging.spawnY - radius * 1.1);
    // A small nudge toward the far edge — every drop otherwise starts
    // from a dead stop, which (rarely) can leave it sitting almost
    // exactly on the spawn point for a moment if something's already
    // resting right there; see _spawnBody's jitter for the other half
    // of this.
    final targetFarX = _farXFor(aimX);
    _spawnBody(
      tier: tier,
      position: spawnPos,
      velocity: Vector2(0, -0.6),
      throwTargetFarX: targetFarX,
    );
    onThrowCommitted();
  }

  /// A drop aimed away from center needs to end up further inward by the
  /// time it reaches the far edge, converging by [kAimConvergenceRatio] —
  /// the same target StagingComponent's aim line draws toward and
  /// IngredientBodyComponent continuously steers this drop's own flight
  /// toward (see its _steerTowardThrowLine).
  double _farXFor(double aimX) {
    final center = kWorldWidthMeters / 2;
    return center + (aimX - center) * kAimConvergenceRatio;
  }

  /// "If any item is entirely below this line for 2 throws, it's game
  /// over" — checked right before each new drop is committed, against
  /// whatever's currently settled on the table.
  ///
  /// Only counts bodies that are (a) actually at rest there, not just
  /// currently passing through that y on their way down — the staging
  /// spawn point itself sits past the line for any realistic table
  /// height, so a body fresh off a drop reads as "past the line" before
  /// gravity's even had a chance to move it — and (b) touching at least
  /// one other item. A lone body can end up resting against the
  /// near-edge backstop *wall* by itself (a stray bounce, say) without
  /// any pile behind it; that's not what "the table's full" means, and
  /// _adjacency only records item-to-item contacts, so a wall-only rest
  /// shows up as no neighbors at all.
  void _checkOverflow() {
    // The near-edge line only catches a pile that's grown tall enough to
    // reach back toward the staging edge — a wide table lets a lot of
    // bodies accumulate spread out sideways without ever tripping that,
    // especially over a long session where throws keep outpacing merges.
    // A hard count cap bounds the worst case regardless of layout, since
    // every per-frame pass here scales with how many bodies are live.
    if (_liveBodies.length >= kMaxLiveBodies) {
      _gameOverTriggered = true;
      staging.hide();
      onGameOver();
      return;
    }

    final lineY = _worldHeight * (1 - kGameOverLineFraction);
    final overflowing = _liveBodies.any(
      (c) =>
          !c.consumed &&
          c.isMounted &&
          (c.body.position.y - c.radius) > lineY &&
          c.body.linearVelocity.length < kRestSpeedThreshold &&
          (_adjacency[c]?.isNotEmpty ?? false),
    );
    _overflowStreak = overflowing ? _overflowStreak + 1 : 0;
    if (_overflowStreak >= 2) {
      _gameOverTriggered = true;
      staging.hide();
      onGameOver();
    }
  }

  final _random = Random();

  IngredientBodyComponent _spawnBody({
    required int tier,
    required Vector2 position,
    Vector2? velocity,
    double? throwTargetFarX,
    double angle = 0,
  }) {
    final ingredient = _chain[tier];
    final radius = _radiusForTier(tier, ingredient);
    // A tiny random offset guarantees no two bodies are ever created at
    // *exactly* the same position — a drop landing on the same spot as
    // something already resting there, or a merge's result spawning
    // where another body happens to be. Box2D's contact-normal math
    // divides by the separation between two circles' centers, and two
    // perfectly coincident ones give it a zero-length vector to
    // normalize — that can produce NaN and poison the whole simulation
    // (freezing it, rather than just looking glitchy) instead of just
    // resolving as an ordinary overlap.
    final jitter = Vector2(
      (_random.nextDouble() - 0.5) * 0.01,
      (_random.nextDouble() - 0.5) * 0.01,
    );
    final body = IngredientBodyComponent(
      tier: tier,
      ingredient: ingredient,
      spawnPosition: position + jitter,
      spawnAngle: angle,
      radius: radius,
      initialVelocity: velocity,
      throwTargetFarX: throwTargetFarX,
    );
    world.add(body);
    _liveBodies.add(body);
    _bodiesChangedSinceSweep = true;
    onTierSeen(tier);
    return body;
  }

  // ─────────────────────────────────────────────────────────────────
  // Collision calibration testbed — debug-only, wired up from
  // GameScreen's kDebugMode-gated panel. Spawns bypass onTierSeen
  // deliberately (unlike _spawnBody) so poking around here never grants
  // real credits/tier-unlock progress — these bodies are purely visual/
  // physics probes, not real gameplay events.
  // ─────────────────────────────────────────────────────────────────

  /// Where debug spawns are pinned, as a fraction of table height — mid
  /// table, on plain wood well clear of the edges and the staging area.
  static const _debugSpawnYFraction = 0.42;

  /// Spawns [ingredientId] (searched across every level's chain, not
  /// just the current one — see findIngredientById) near the table's
  /// staging edge (see [_debugSpawnYFraction]) with its real fixture
  /// outline drawn on top of its sprite.
  void debugSpawnIngredient(String ingredientId) {
    final ingredient = findIngredientById(ingredientId);
    final radius = _radiusForTier(ingredient.tier, ingredient);
    final body = IngredientBodyComponent(
      tier: ingredient.tier,
      ingredient: ingredient,
      spawnPosition: Vector2(kWorldWidthMeters / 2, _worldHeight * _debugSpawnYFraction),
      radius: radius,
      debugShowFixtures: true,
      debugPinned: true,
    );
    world.add(body);
    _liveBodies.add(body);
    _bodiesChangedSinceSweep = true;
  }

  /// Showers [count] small probe ingredients (default blackcurrant — a
  /// genuinely small tier-0 item) around the same near-edge spot
  /// debugSpawnIngredient uses (see [_debugSpawnYFraction]), each with
  /// its own fixture outline visible, so where they come to rest
  /// against whatever's already there shows the real collision boundary
  /// directly, not just a guess from how the sprite art lines up.
  void debugShowerProbes({String probeId = 'blackcurrant', int count = 24}) {
    final probeIngredient = findIngredientById(probeId);
    final radius = _radiusForTier(probeIngredient.tier, probeIngredient);
    final center = Vector2(kWorldWidthMeters / 2, _worldHeight * _debugSpawnYFraction);
    for (var i = 0; i < count; i++) {
      final angle = _random.nextDouble() * pi * 2;
      final distance = 0.6 + _random.nextDouble() * 0.6;
      final position = center + Vector2(cos(angle), sin(angle)) * distance;
      final velocity = Vector2(
        (_random.nextDouble() - 0.5) * 0.4,
        (_random.nextDouble() - 0.5) * 0.4,
      );
      final body = IngredientBodyComponent(
        tier: probeIngredient.tier,
        ingredient: probeIngredient,
        spawnPosition: position,
        radius: radius,
        initialVelocity: velocity,
        debugShowFixtures: true,
      );
      world.add(body);
      _liveBodies.add(body);
    }
    _bodiesChangedSinceSweep = true;
  }

  /// Removes every body currently on the table — the testbed's own
  /// reset, unconditional (unlike cherryBomb, which only sweeps one id).
  void debugClearTable() {
    for (final b in List.of(_liveBodies)) {
      _removeBody(b);
    }
  }

  /// A merge result spawns at full size where two smaller items were, so
  /// it can land deep inside a neighbour. Box2D can't untangle that with
  /// traced profiles: stacked slice pairs resolve along their thin
  /// vertical axis in opposite directions and cancel, leaving the items
  /// stuck overlapping. For a short window after each merge, anything
  /// genuinely penetrating the new item is nudged straight out along the
  /// line between their centres until it's clear.
  final Map<IngredientBodyComponent, double> _pops = {};
  static const _popDuration = 0.6;
  static const _popSlop = 0.004;
  static const _popMaxStep = 0.06;

  void _startPop(IngredientBodyComponent body) => _pops[body] = _popDuration;

  /// The same stuck-overlap problem as merge pops can arise from anything
  /// that puts two items deep inside each other — Mega-Shake regrowing
  /// everything at once, a fast throw, a restored table — so every
  /// touching pair (Box2D's own contact list, via _adjacency) is checked a
  /// few times a second and pushed apart if genuinely interpenetrating.
  static const _unstickInterval = 0.1;
  static const _unstickSlop = 0.01;
  double _unstickTimer = 0;

  void _unstickContacts(double dt) {
    _unstickTimer -= dt;
    if (_unstickTimer > 0) return;
    _unstickTimer = _unstickInterval;
    final seen = <IngredientBodyComponent>{};
    for (final entry in _adjacency.entries) {
      final a = entry.key;
      if (a.consumed || !a.isMounted) continue;
      seen.add(a);
      for (final b in entry.value) {
        if (seen.contains(b) || b.consumed || !b.isMounted) continue;
        final depth = IngredientBodyComponent.penetrationDepth(
          a.worldCollisionPieces(),
          b.worldCollisionPieces(),
        );
        if (depth <= _unstickSlop) continue;
        _separate(a, b, depth, aShare: 0.5);
      }
    }
  }

  /// Moves [b] away from [a] (and [a] back by its share) along the line
  /// between their centres, by up to [_popMaxStep] per call.
  void _separate(
    IngredientBodyComponent a,
    IngredientBodyComponent b,
    double depth, {
    required double aShare,
  }) {
    final aPos = a.body.position, bPos = b.body.position;
    var dir = bPos - aPos;
    if (dir.length2 < 1e-8) {
      final t = _random.nextDouble() * pi * 2;
      dir = Vector2(cos(t), sin(t));
    }
    dir.normalize();
    final step = depth < _popMaxStep ? depth : _popMaxStep;
    b.body.setTransform(bPos + dir * (step * (1 - aShare)), b.body.rotation);
    a.body.setTransform(aPos - dir * (step * aShare), a.body.rotation);
    a.body.isAwake = true;
    b.body.isAwake = true;
  }

  void _resolvePops(double dt) {
    if (_pops.isEmpty) return;
    for (final p in List.of(_pops.keys)) {
      if (!p.isMounted) continue;
      final remaining = _pops[p]! - dt;
      if (remaining <= 0 || p.consumed) {
        _pops.remove(p);
        continue;
      }
      _pops[p] = remaining;
      final pPieces = p.worldCollisionPieces();
      final pPos = p.body.position;
      for (final o in _liveBodies) {
        if (identical(o, p) || o.consumed || !o.isMounted) continue;
        final oPos = o.body.position;
        final reach = p.contactRadius + o.contactRadius;
        if ((oPos - pPos).length2 > reach * reach) continue;
        final depth = IngredientBodyComponent.penetrationDepth(
          pPieces,
          o.worldCollisionPieces(),
        );
        if (depth <= _popSlop) continue;
        _separate(p, o, depth, aShare: 0.3);
      }
    }
  }

  void _removeBody(IngredientBodyComponent c) {
    _liveBodies.remove(c);
    _pops.remove(c);
    // Only touch c's own recorded neighbors, not every entry in
    // _adjacency — this used to scan the whole map on every single
    // removal (every merge removes two bodies), which is O(bodies on the
    // table) per removal. Fine with a handful of items, but on a long
    // session where the table's accumulated dozens/hundreds of pieces,
    // that cost compounds every merge and was a real contributor to the
    // game getting progressively laggier the longer a run went.
    final neighbors = _adjacency.remove(c);
    if (neighbors != null) {
      for (final n in neighbors) {
        _adjacency[n]?.remove(c);
      }
    }
    c.removeFromParent();
  }

  /// Called by [IngredientBodyComponent.beginContact] for every pair of
  /// touching items — not just same-tier ones, since the cocktail-touch
  /// graph needs every contact to find connected clusters.
  void handleContactBegin(
    IngredientBodyComponent a,
    IngredientBodyComponent b,
  ) {
    // A compound collision shape (several circles — see
    // Ingredient.collisionProfile, used by prosecco/champagne/gin/
    // vermouth) means two touching bodies can share more than one
    // fixture-pair contact at once, each firing its own beginContact
    // this same step. Bailing out here once either body's already
    // consumed (its merge already resolved this step, even though Box2D
    // hasn't finished tearing the body down yet) keeps a duplicate event
    // from re-adding a stale adjacency entry for a body that's on its
    // way out.
    if (a.consumed || b.consumed) return;
    _adjacency.putIfAbsent(a, () => {}).add(b);
    _adjacency.putIfAbsent(b, () => {}).add(a);
    _tryMerge(a, b);
    _cocktailCheckDirty = true;
  }

  void handleContactEnd(IngredientBodyComponent a, IngredientBodyComponent b) {
    _adjacency[a]?.remove(b);
    _adjacency[b]?.remove(a);
    _cocktailCheckDirty = true;
  }

  /// How close (metres, ~2-3px on screen) two same-tier items' real
  /// collision shapes must be to merge. Box2D reports contacts up to its
  /// ~2cm speculative distance early, and the sweep's bounding-radius
  /// prefilter is looser still, so both paths are gated on the exact gap.
  static const _mergeTouchTolerance = 0.01;

  void _tryMerge(IngredientBodyComponent a, IngredientBodyComponent b) {
    if (a.consumed || b.consumed) return;
    if (a.tier != b.tier) return;
    if (!a.isMounted || !b.isMounted) return;
    final gap = IngredientBodyComponent.gapBetween(
      a.worldCollisionPieces(),
      b.worldCollisionPieces(),
    );
    if (gap > _mergeTouchTolerance) {
      // A near miss can still close up as things settle, after which no
      // new contact event fires — keep the sweep re-checking it.
      if (gap < _mergeTouchTolerance * 4) _bodiesChangedSinceSweep = true;
      return;
    }
    final nextTier = a.tier + 1;
    final chainExhausted = nextTier >= _chain.length;
    // Every level before the last one treats its own capstone tier as a
    // deliberate dead end (see kEvolutionChain's own "never appears
    // inside a recipe" doc) — two of those touching stays a no-op, same
    // as it's always been. Only the *final* level's capstone turns into
    // the actual win condition below, since there's no further level
    // for _checkLevelUp to advance into.
    if (chainExhausted && _level < kMaxLevel) return;
    if (chainExhausted && _gameCompleteTriggered) return;

    a.consumed = true;
    b.consumed = true;
    final mergedTier = a.tier;
    final midpoint = (a.body.position + b.body.position) / 2;
    final ingredient = a.ingredient;
    // The chain's own capstone (the "jug") is a one-off climax, not just
    // another step — give it the same fly-to-center/burst/reveal
    // treatment CocktailRevealComponent gives a completed order, instead
    // of the plain MergeExplosionComponent every ordinary tier-up gets.
    // Only on a genuine within-chain merge producing it (not the
    // already-exhausted jug+jug case just above, which either no-ops or
    // ends the game) — reached via this normal merge path specifically
    // because nextTier lands exactly on the chain's last index.
    final producesJug = !chainExhausted && nextTier == _chain.length - 1;
    if (producesJug) {
      final captured = [
        (start: a.body.position.clone(), ingredient: a.ingredient, radius: a.radius),
        (start: b.body.position.clone(), ingredient: b.ingredient, radius: b.radius),
      ];
      _removeBody(a);
      _removeBody(b);
      final center = Vector2(kWorldWidthMeters / 2, _worldHeight / 2);
      unawaited(_playCocktailSound());
      _activeAnimations++;
      world.add(
        CocktailRevealComponent(
          pieces: captured,
          center: center,
          cocktailAssetPath: _chain[nextTier].assetPath ?? '',
          onComplete: () {
            _startPop(_spawnBody(tier: nextTier, position: center));
            _activeAnimations--;
          },
        ),
      );
      onMerge(mergedTier);
      return;
    }
    _removeBody(a);
    _removeBody(b);
    unawaited(_playMergeSound());
    _activeAnimations++;
    if (chainExhausted) _gameCompleteTriggered = true;
    world.add(
      MergeExplosionComponent(
        position: midpoint,
        ingredient: ingredient,
        onSpawnReady: chainExhausted
            ? () {}
            : () => _startPop(_spawnBody(tier: nextTier, position: midpoint)),
        onFinished: () => _activeAnimations--,
      ),
    );
    onMerge(mergedTier);
    if (chainExhausted) onGameComplete();
  }

  Future<void> _playMergeSound() async {
    if (!sfxEnabled) return;
    try {
      await _mergePool?.start(volume: 0.7);
    } catch (_) {
      // Soft failure — sound playback issues should never affect gameplay.
    }
  }

  Future<void> _playCocktailSound() async {
    if (!sfxEnabled) return;
    try {
      await _cocktailPool?.start(volume: 0.7);
    } catch (_) {
      // Soft failure — sound playback issues should never affect gameplay.
    }
  }

  @override
  void onDispose() {
    _mergePool?.dispose();
    _cocktailPool?.dispose();
    super.onDispose();
  }

  void _checkCocktailCompletion() {
    final order = _currentOrder;
    if (order == null) return;
    final requiredIds = order.ingredientIds;

    final visited = <IngredientBodyComponent>{};
    for (final start in _liveBodies) {
      if (start.consumed || !start.isMounted || visited.contains(start)) {
        continue;
      }
      final component = <IngredientBodyComponent>{};
      final queue = [start];
      visited.add(start);
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        component.add(current);
        for (final neighbor
            in _adjacency[current] ?? const <IngredientBodyComponent>{}) {
          if (neighbor.consumed || visited.contains(neighbor)) continue;
          visited.add(neighbor);
          queue.add(neighbor);
        }
      }

      final claimed = <IngredientBodyComponent>{};
      final chosen = <IngredientBodyComponent>[];
      var satisfied = true;
      for (final id in requiredIds) {
        IngredientBodyComponent? match;
        for (final candidate in component) {
          if (claimed.contains(candidate)) continue;
          if (candidate.ingredient.id == id) {
            match = candidate;
            break;
          }
        }
        if (match == null) {
          satisfied = false;
          break;
        }
        claimed.add(match);
        chosen.add(match);
      }
      if (satisfied) {
        _completeCocktail(order, chosen);
        return;
      }
    }
  }

  void _completeCocktail(
    CocktailRecipe order,
    List<IngredientBodyComponent> pieces,
  ) {
    for (final p in pieces) {
      p.consumed = true;
    }
    final captured = [
      for (final p in pieces)
        (
          start: p.body.position.clone(),
          ingredient: p.ingredient,
          radius: p.radius,
        ),
    ];
    for (final p in pieces) {
      _removeBody(p);
    }
    final center = Vector2(kWorldWidthMeters / 2, _worldHeight / 2);
    unawaited(_playCocktailSound());
    _activeAnimations++;
    world.add(
      CocktailRevealComponent(
        pieces: captured,
        center: center,
        cocktailAssetPath: order.assetPath,
        onComplete: () => _activeAnimations--,
      ),
    );
    onCocktailComplete(order);
  }

  /// Snapshots everything currently resting on the table — called from
  /// GameScreen.dispose so it can be handed back in as [initialItems]
  /// next time the table's built, since the physics world itself doesn't
  /// survive navigating away.
  List<PlacedItem> capturePlacedItems() => [
    for (final b in _liveBodies)
      if (!b.consumed && b.isMounted)
        PlacedItem(tier: b.tier, x: b.body.position.x, y: b.body.position.y, angle: b.body.angle),
  ];

  /// Wipes the table for a fresh run — everything except the staging
  /// glass and the boundary itself, including any merge/cocktail
  /// animation still mid-flight, so a stray delayed callback can't spawn
  /// a leftover item onto the new game. GameScreen calls this on "Play
  /// Again," since GameStateNotifier.restart only resets score/order —
  /// it has no way to reach into the physics world itself.
  void clearBoard() {
    for (final child in List.of(world.children)) {
      if (child != staging && child != _boundary && child != _gameOverLine) {
        child.removeFromParent();
      }
    }
    _liveBodies.clear();
    _pops.clear();
    _adjacency.clear();
    _gameOverTriggered = false;
    _gameCompleteTriggered = false;
    _overflowStreak = 0;
    _busy = false;
    // Any merge-explosion/cocktail-reveal component just wiped above was
    // removed directly, not through its own onFinished/onComplete — reset
    // this alongside everything else rather than leaving it stuck above
    // zero forever (which would hang GameScreen's ad-break wait, which
    // polls isAnimating, indefinitely).
    _activeAnimations = 0;
    // Every body a mid-flight shake's squish was tracking is gone now
    // (bodies removed above) — drop that state too rather than let a
    // restore loop over an empty/stale _liveBodies do nothing useful,
    // or a leftover world.gravity multiplier survive into the new game.
    _shakeTimeRemaining = 0;
    shakeActive.value = false;
    _shakeSquishApplied = false;
    _shakeSettleElapsed = 0;
    _shakeRestoreStep = 0;
    _shakeRestoreStepTimer = 0;
    world.gravity = Vector2(0, -kGravityMagnitude);
  }

  /// Moves the physics side of the table onto [level]'s own chain —
  /// clears the board (Level 2's ingredients are a different chain
  /// entirely; nothing on a Level 1 table has a place on the rooftop
  /// one) and switches which chain [_spawnBody]/[_tryMerge] index into.
  /// Called by GameScreen once the level-up celebration begins (see
  /// level_up_overlay.dart), alongside GameStateNotifier.enterLevel
  /// which does the equivalent reset on the board-state side — both
  /// ingredient art sets were already preloaded in onLoad, so this needs
  /// no async work of its own.
  void switchToLevel(int level) {
    _level = level;
    clearBoard();
  }

  final _shakeRandom = Random();

  /// The Shaker Maker purchase used to be a single instant impulse burst —
  /// over in one physics tick. This makes it read as an actual multi-second
  /// shake instead: a run of smaller impulse pulses spread out over
  /// [_shakeDuration], each one jostling everything currently on the
  /// table into new contacts (any resulting same-tier touches get picked
  /// up as normal, by the contact system or the next proximity sweep).
  /// Duration bumped 50% (1.4 -> 2.1) and every pulse's impulse doubled
  /// ("twice as aggressive"), per feedback that it read as too gentle.
  static const _shakeDuration = 2.1;
  static const _shakePulseInterval = 0.1;
  double _shakeTimeRemaining = 0;
  double _shakePulseTimer = 0;

  /// Mirrors `_shakeTimeRemaining > 0` as a public, listenable signal —
  /// read-only (set only by this class, from the handful of places below
  /// that already change `_shakeTimeRemaining`) for GameScreen's
  /// power-up tray to show a pulsing glow on Shake/Mega-Shake while
  /// either effect is still running, per the gameplay redesign handoff.
  final shakeActive = ValueNotifier<bool>(false);

  /// World gravity doubles for the whole shake window on top of the
  /// stronger pulses — each pop then falls back down harder/faster
  /// instead of hanging in the air, reading as a heavier, more chaotic
  /// shake rather than just bigger floaty throws. Restored the instant
  /// the shake ends (see _updateShake).
  static const _shakeGravityMultiplier = 2.0;

  /// Every live item shrinks to this fraction of its normal radius for
  /// the shake — both the real physics collision circle (see
  /// IngredientBodyComponent.setPhysicsRadiusMultiplier, applied once at
  /// the start/end of a shake, not continuously) and, layered on top of
  /// that as a purely cosmetic render-time deformation, a per-item
  /// squash-stretch wobble while the shake's impulses are running (see
  /// shakeSquishScaleFor). Continuously destroying/recreating a Box2D
  /// shape every frame to make the *collision* boundary itself flex
  /// would be both expensive and a good way to destabilize the
  /// simulation, so only the one-time resize touches physics — the
  /// wobble/flex the shake actually reads as is all visual.
  ///
  /// Base 0.725 (27.5% smaller) +/- an 0.03 wobble spans 24.5%-30.5%
  /// smaller — bumped another 10 points per feedback that Mega-Shake
  /// wasn't effective enough (was 0.825/17.5%, itself bumped up from an
  /// initial 10-15%). The X/Y wobble is a full half-cycle (pi) out of
  /// phase with itself (see shakeSquishScaleFor) rather than a smaller
  /// offset, so as one axis shrinks toward the bottom of that band the
  /// other relatively grows toward the top of it — a genuine
  /// squash-stretch flex instead of both axes pulsing in near-lockstep,
  /// per feedback that it should "look a bit flexible."
  static const _shakeSquishBase = 0.725;
  static const _shakeShrinkInDuration = 0.18;
  static const _shakeSettleDuration = 0.35;
  static const _shakeWobbleAmplitude = 0.03;
  static const _shakeWobbleFrequency = 16.0;
  bool _shakeSquishApplied = false;
  double _shakeSettleElapsed = 0;

  /// The cosmetic squish (shakeSquishScaleFor) eases smoothly back to
  /// full size over _shakeSettleDuration, frame by frame — but the real
  /// physics radius used to jump from shrunk straight to full size in
  /// one single instant step, for every live body at once, the moment
  /// that window ended. A table full of items that had settled into
  /// positions valid at their *shrunk* size all suddenly becoming ~38%
  /// bigger in the same physics step left Box2D with a pile of genuinely
  /// overlapping bodies to resolve — which it deliberately does
  /// gradually, not instantly (a hard "pop apart in one step" would be
  /// its own visible glitch), so the overlap stayed visible for a real,
  /// noticeable stretch after a Mega-Shake. Restoring across a handful
  /// of discrete steps instead of one spreads that same total growth
  /// into several smaller jumps, each with a moment for the solver to
  /// resolve before the next — still just a few shape recreations total
  /// (not one every frame, which the single-resize design above
  /// deliberately avoids for cost/stability reasons), but enough to stop
  /// the overlap from being this visible.
  static const _shakeRestoreSteps = 4;
  static const _shakeRestoreStepInterval = 0.08;
  int _shakeRestoreStep = 0;
  double _shakeRestoreStepTimer = 0;

  /// Scales every impulse pulse in [_updateShake] — 1.0 for the plain
  /// Shake, higher for Mega-Shake (see [megaShakeTable]) so items fly
  /// around more during the pricier purchase without touching the
  /// cheaper one's feel.
  double _shakeImpulseMultiplier = 1.0;

  void _startShakeImpulses(double impulseMultiplier) {
    _shakeTimeRemaining = _shakeDuration;
    shakeActive.value = true;
    _shakePulseTimer = 0;
    _shakeSettleElapsed = 0;
    // A second Mega-Shake fired while the first's restore steps were
    // still mid-way through would otherwise resume from a stale non-zero
    // step/timer afterward, skipping straight to a later (bigger) jump
    // instead of starting the staggered restore clean.
    _shakeRestoreStep = 0;
    _shakeRestoreStepTimer = 0;
    _shakeImpulseMultiplier = impulseMultiplier;
    world.gravity = Vector2(0, -kGravityMagnitude * _shakeGravityMultiplier);
  }

  /// The original Shake purchase — the impulse-pulse jostle only, no
  /// size change. See [megaShakeTable] for the shrink/wobble/flex
  /// version.
  void shakeTable() => _startShakeImpulses(1.0);

  /// Mega-Shake — the same impulse pulses as [shakeTable] but 30%
  /// stronger ("fly around a little bit more"), plus every live item
  /// shrinking/wobbling/flexing for the duration (see _shakeSquishBase's
  /// doc and shakeSquishScaleFor).
  void megaShakeTable() {
    _startShakeImpulses(1.3);
    // Guarded — a second Mega-Shake purchase fired while the first's
    // items are still settling back to size would otherwise shrink
    // already-shrunk bodies a second time.
    if (!_shakeSquishApplied) {
      _shakeSquishApplied = true;
      for (final b in _liveBodies) {
        if (b.isMounted) b.setPhysicsRadiusMultiplier(_shakeSquishBase);
      }
    }
  }

  /// Removes every instance of the current level's own tier-0 ingredient
  /// currently on the table — the Cherry Bomb purchase (renamed per
  /// level in GameScreen's own power-up tile — Currant Bomb on Piazza,
  /// Sugar Bomb on Jungle — but the same underlying sweep-and-delete
  /// power everywhere, parameterized by id instead of hardcoded to
  /// literal cherries).
  void cherryBomb() {
    final targetId = _chain.first.id;
    for (final b in List.of(_liveBodies)) {
      if (b.ingredient.id == targetId) {
        _removeBody(b);
      }
    }
  }

  void _updateShake(double dt) {
    if (_shakeTimeRemaining > 0) {
      _shakeTimeRemaining -= dt;
      if (_shakeTimeRemaining <= 0) {
        world.gravity = Vector2(0, -kGravityMagnitude);
        shakeActive.value = false;
      }
      _shakePulseTimer -= dt;
      if (_shakePulseTimer <= 0) {
        _shakePulseTimer = _shakePulseInterval;
        for (final b in _liveBodies) {
          if (b.consumed || !b.isMounted) continue;
          // Vertical component deliberately much bigger than horizontal
          // — "make things jump up/down more" — so a pulse reads as a
          // hop along the table's depth axis (which is screen-vertical,
          // given the camera's angle) rather than a subtle
          // omnidirectional jitter. Every magnitude doubled ("twice as
          // aggressive") per feedback.
          final horizontal =
              (_shakeRandom.nextDouble() - 0.5) *
              2.4 *
              _shakeImpulseMultiplier *
              b.body.mass;
          final verticalSign = _shakeRandom.nextBool() ? 1.0 : -1.0;
          final vertical =
              verticalSign *
              (2.6 + _shakeRandom.nextDouble() * 2.2) *
              _shakeImpulseMultiplier *
              b.body.mass;
          b.body.applyLinearImpulse(Vector2(horizontal, vertical));
        }
      }
      return;
    }
    // The shake's own timer (and its impulse pulses) has ended, but
    // items are still shrunk — ease them back to full size over
    // _shakeSettleDuration (see shakeSquishScaleFor for the matching
    // visual curve during this window), then step the real physics
    // radius back up over a few more discrete jumps (see
    // _shakeRestoreSteps' own doc for why not one single jump).
    if (!_shakeSquishApplied) return;
    if (_shakeSettleElapsed < _shakeSettleDuration) {
      _shakeSettleElapsed += dt;
      return;
    }
    _shakeRestoreStepTimer -= dt;
    if (_shakeRestoreStepTimer > 0) return;
    _shakeRestoreStepTimer = _shakeRestoreStepInterval;
    _shakeRestoreStep++;
    final multiplier = _shakeRestoreStep >= _shakeRestoreSteps
        ? 1.0
        : _shakeSquishBase +
              (1.0 - _shakeSquishBase) *
                  (_shakeRestoreStep / _shakeRestoreSteps);
    for (final b in _liveBodies) {
      if (b.isMounted) b.setPhysicsRadiusMultiplier(multiplier);
    }
    if (_shakeRestoreStep >= _shakeRestoreSteps) {
      _shakeSquishApplied = false;
      _shakeRestoreStep = 0;
      _shakeRestoreStepTimer = 0;
    }
  }

  /// The render-time squash/stretch scale for one item during a shake —
  /// see [_shakeSquishBase]'s doc for why this is cosmetic-only, layered
  /// on top of the one-time physics resize. Eases in from (1, 1) at the
  /// very start, wobbles X and Y out of phase with each other (so as one
  /// axis shrinks the other relatively grows — a squash-stretch flex
  /// rather than a flat pulse) for as long as the shake's impulses are
  /// actively running, then eases back to (1, 1) once they stop. [c]'s
  /// own hash code seeds a fixed phase offset so every item on the table
  /// isn't wobbling in lockstep.
  Vector2 shakeSquishScaleFor(IngredientBodyComponent c) {
    if (!_shakeSquishApplied) return Vector2(1, 1);
    final phase = (c.hashCode & 0xFFF) / 0xFFF * pi * 2;
    Vector2 wobbleAt(double t) {
      if (t < _shakeShrinkInDuration) {
        final p = Curves.easeOut.transform(
          (t / _shakeShrinkInDuration).clamp(0.0, 1.0),
        );
        final s = 1.0 - p * (1.0 - _shakeSquishBase);
        return Vector2(s, s);
      }
      final localT = t - _shakeShrinkInDuration;
      final x =
          _shakeSquishBase +
          sin(localT * _shakeWobbleFrequency + phase) * _shakeWobbleAmplitude;
      // A full half-cycle out of phase with X (not a partial offset) —
      // when X is at its smallest, Y is at its biggest, and vice versa,
      // which is what actually reads as squashing/stretching rather
      // than everything just pulsing together.
      final y =
          _shakeSquishBase +
          sin(localT * _shakeWobbleFrequency + phase + pi) *
              _shakeWobbleAmplitude;
      return Vector2(x, y);
    }

    if (_shakeTimeRemaining > 0) {
      return wobbleAt(_shakeDuration - _shakeTimeRemaining);
    }
    final atShakeEnd = wobbleAt(_shakeDuration);
    final p = Curves.easeOut.transform(
      (_shakeSettleElapsed / _shakeSettleDuration).clamp(0.0, 1.0),
    );
    return Vector2(
      atShakeEnd.x + (1.0 - atShakeEnd.x) * p,
      atShakeEnd.y + (1.0 - atShakeEnd.y) * p,
    );
  }

  /// Removes every item currently on the table that's one of the Slam
  /// Mini-Shots ingredients (see Ingredient.isMiniShot: Vodka, Melon
  /// Liqueur, Gin, Coffee Liqueur) — the mid-game purchase, and also
  /// [clearMiniShotsAndResume] (the ad-continue flow). Deliberately
  /// narrower than every [Ingredient.isAlcoholic] item: that used to be
  /// what the ad-continue flow cleared, but on the rooftop chain that
  /// also swept up Whisky, which isn't a shot glass at all and reads as
  /// an odd thing for a "clear shots" offer to take — per feedback, this
  /// (not the broader alcoholic set) is what it should have been using.
  void clearMiniShots() {
    for (final b in List.of(_liveBodies)) {
      if (b.ingredient.isMiniShot) {
        _removeBody(b);
      }
    }
  }

  /// The rewarded-ad "clear all shots" continue: clears every Mini-Shots
  /// item from the table and un-ends the game — called once the ad
  /// finishes playing; see GameScreen's continue-offer flow. Staging's
  /// own visibility follows board.gameOver via the next syncBoard call as
  /// normal, so nothing extra is needed for that here.
  void clearMiniShotsAndResume() {
    clearMiniShots();
    _gameOverTriggered = false;
    _overflowStreak = 0;
  }
}
