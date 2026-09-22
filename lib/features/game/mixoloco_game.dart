import 'dart:async' show unawaited;
import 'dart:math' show Random, pi, sin, sqrt;
import 'package:flame/components.dart' show Anchor;
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart' show Color, Colors, Curves;
import '../../core/widgets/bar_backdrop.dart' show kTableFarToNearWidthRatio;
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
import 'providers/game_state_provider.dart' show BoardState, PlacedItem;

/// The physics world is laid out in meters (Box2D's own comfortable
/// range), with the table's width fixed at this many of them — its
/// height then follows whatever the screen's own aspect ratio is, so the
/// table never looks stretched.
const kWorldWidthMeters = 4.0;

/// Tier 0 (mint)'s radius, in meters — every later tier grows from this
/// by [kTierGrowthFactor] per step. 5% smaller than the original 0.19,
/// per feedback that Level 1 played a little too hard — since every
/// tier's size is derived from this one constant (both chains share it),
/// shrinking it here shrinks every ingredient on the table by the same
/// 5%, giving the board more breathing room before it fills up.
const kBaseRadiusMeters = 0.19 * 0.95;

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

/// How much smaller an item renders at the far edge than the same tier
/// right at the staging edge — purely a visual depth cue (real-world
/// perspective: distant things look smaller), never the physics radius,
/// so it doesn't touch collision or merge sizing at all. Kept subtle —
/// see [perspectiveScaleForY].
const kFarPerspectiveScale = 0.85;

/// The render-size multiplier for an item resting at world [y], given
/// the table's [worldHeight] — 1.0 right at the near/staging edge,
/// [kFarPerspectiveScale] at the true far edge, linear in between.
double perspectiveScaleForY(double y, double worldHeight) {
  final t = (y / worldHeight).clamp(0.0, 1.0);
  return kFarPerspectiveScale + (1 - kFarPerspectiveScale) * t;
}

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
    required this.onThrowCommitted,
    required this.onTierSeen,
    this.initialItems = const [],
    this.sfxEnabled = true,
    int level = 1,
  }) : _level = level,
       super(gravity: Vector2(0, -kGravityMagnitude));

  /// Which evolution chain/cocktail list is currently active — 1 for the
  /// beach bar ([kEvolutionChain]/[kCocktailRecipes]), 2 for the rooftop
  /// bar ([kEvolutionChainLevel2]/[kCocktailRecipesLevel2]). Both
  /// chains' art is preloaded upfront in onLoad regardless of which is
  /// active at construction, so [switchToLevel] never needs an async
  /// await mid-game.
  int _level;
  List<Ingredient> get _chain => _level >= 2 ? kEvolutionChainLevel2 : kEvolutionChain;

  /// Items to recreate on the table as soon as the world's ready — a
  /// snapshot taken via [capturePlacedItems] the last time this screen
  /// was left, so leaving and coming back doesn't wipe the table.
  final List<PlacedItem> initialItems;

  /// A snapshot of the Settings sound-effects toggle at the moment this
  /// screen opened — Settings only ever opens from the menu screen, so
  /// there's no live game session for a mid-game toggle to react to;
  /// this just needs to reflect whatever it was set to going in.
  final bool sfxEnabled;

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
  bool _initialItemsSpawned = false;
  int _overflowStreak = 0;

  final Set<IngredientBodyComponent> _liveBodies = {};
  final Map<IngredientBodyComponent, Set<IngredientBodyComponent>> _adjacency = {};

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
    for (final b in List.of(_liveBodies)) {
      if (!b.isMounted) continue;
      final pos = b.body.position;
      if (pos.x.isNaN || pos.y.isNaN) {
        _removeBody(b);
      }
    }
  }

  /// A safety net alongside beginContact-triggered merging: two same-tier
  /// items resting near a third item (rather than directly against each
  /// other) can end up close enough to visually read as touching —
  /// especially since items are drawn at [kIngredientVisualPad] their
  /// true physics size to close the touching-items gap — without Box2D
  /// ever firing a contact event between that specific pair. This sweep
  /// catches that: same tolerance as the visual padding, so a merge
  /// fires whenever the art actually looks like it's touching, not only
  /// when the (smaller) physics circles are exactly touching.
  ///
  /// A body added to [_liveBodies] this same frame may not be mounted
  /// yet — Flame mounts newly-added components on the *next* tick, not
  /// synchronously — and its `.body` isn't safe to touch until then,
  /// so those are skipped here (and picked up naturally once mounted,
  /// a frame later).
  void _sweepForMerges() {
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
          final threshold = (a.radius + b.radius) * kIngredientVisualPad;
          if (a.body.position.distanceTo(b.body.position) <= threshold) {
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
    await preloadIngredientArt([...kEvolutionChain, ...kEvolutionChainLevel2]);
    await preloadImageAssets([for (final recipe in [...kCocktailRecipes, ...kCocktailRecipesLevel2]) recipe.assetPath]);
    try {
      _mergePool = await FlameAudio.createPool(kMergeSoundFile, minPlayers: 2, maxPlayers: 6);
      _cocktailPool = await FlameAudio.createPool(kCocktailSoundFile, minPlayers: 1, maxPlayers: 2);
    } catch (_) {
      // Soft failure — _playMergeSound/_playCocktailSound just no-op if
      // their pool never got created, same spirit as the art preloaders.
    }
    staging = StagingComponent(worldWidth: kWorldWidthMeters, worldHeight: _worldHeight, spawnY: _worldHeight - kStagingInset, onDrop: _handleDrop);
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
    staging.radius = radiusForTier(ingredient.tier, kBaseRadiusMeters) * ingredient.sizeMultiplier;
    staging.ingredient = ingredient;
  }

  void _applyGeometry(BoardGeometry geometry) {
    final changed = !_geometry.isValid || (geometry.width - _geometry.width).abs() > 0.5 || (geometry.height - _geometry.height).abs() > 0.5;
    _geometry = geometry;
    if (!changed && _boundary != null) return;

    _worldHeight = kWorldWidthMeters * (geometry.height / geometry.width);
    metersToPixels = geometry.width / kWorldWidthMeters;
    camera.viewfinder.anchor = Anchor.topLeft;
    camera.viewfinder.position = Vector2.zero();

    _boundary?.removeFromParent();
    _boundary = TableBoundaryComponent(worldWidth: kWorldWidthMeters, worldHeight: _worldHeight);
    world.add(_boundary!);

    _gameOverLine?.removeFromParent();
    _gameOverLine = GameOverLineComponent(worldWidth: kWorldWidthMeters, lineY: _worldHeight * (1 - kGameOverLineFraction));
    world.add(_gameOverLine!);

    staging.removeFromParent();
    staging = StagingComponent(worldWidth: kWorldWidthMeters, worldHeight: _worldHeight, spawnY: _worldHeight - kStagingInset, onDrop: _handleDrop);
    world.add(staging);
    final pending = _pendingIngredient;
    if (pending != null) _setStagedIngredient(pending);

    if (!_initialItemsSpawned) {
      _initialItemsSpawned = true;
      for (final item in initialItems) {
        _spawnBody(tier: item.tier, position: Vector2(item.x, item.y));
      }
    }
  }

  void _handleDrop(double aimX) {
    if (_busy || _gameOverTriggered) return;
    final ingredient = staging.ingredient;
    if (ingredient == null) return;

    _checkOverflow();
    if (_gameOverTriggered) return;

    _busy = true;
    _cooldownRemaining = kThrowCooldown;
    final tier = ingredient.tier;
    final radius = radiusForTier(tier, kBaseRadiusMeters) * ingredient.sizeMultiplier;
    final spawnPos = Vector2(aimX, staging.spawnY - radius * 1.1);
    // A small nudge toward the far edge — every drop otherwise starts
    // from a dead stop, which (rarely) can leave it sitting almost
    // exactly on the spawn point for a moment if something's already
    // resting right there; see _spawnBody's jitter for the other half
    // of this.
    _spawnBody(
      tier: tier,
      position: spawnPos,
      velocity: Vector2(0, -0.6),
      laneAccelX: _laneAccelXFor(aimX),
      laneAccelDuration: _laneAccelDuration,
    );
    onThrowCommitted();
  }

  /// A drop aimed away from center needs to end up further inward by the
  /// time it reaches the far edge — the table's side walls taper in to
  /// [kTableFarToNearWidthRatio] of the near width there (see
  /// TableBoundaryComponent) — but a *straight* line covering that isn't
  /// vertical, it's a line angled the same amount the table itself tapers.
  /// Starting from rest, a constant sideways acceleration held for exactly
  /// the time a freefall from the staging edge to the far edge takes
  /// produces exactly that straight line (displacement is proportional to
  /// acceleration when initial velocity is zero) — same idea
  /// StagingComponent's aim line traces to draw the matching guide.
  double _laneAccelXFor(double aimX) {
    final fallHeight = staging.spawnY - kTableFarInset;
    if (fallHeight <= 0) return 0;
    final center = kWorldWidthMeters / 2;
    final farX = center + (aimX - center) * kTableFarToNearWidthRatio;
    final dx = farX - aimX;
    return kGravityMagnitude * dx / fallHeight;
  }

  /// Time a freefall from the staging edge to the far edge takes under
  /// [kGravityMagnitude] — how long [_laneAccelXFor]'s sideways push
  /// needs to be held for its displacement to land exactly on the tapered
  /// target (see its own doc comment).
  double get _laneAccelDuration {
    final fallHeight = staging.spawnY - kTableFarInset;
    if (fallHeight <= 0) return 0;
    return sqrt(2 * fallHeight / kGravityMagnitude);
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
    double laneAccelX = 0,
    double laneAccelDuration = 0,
  }) {
    final ingredient = _chain[tier];
    final radius = radiusForTier(tier, kBaseRadiusMeters) * ingredient.sizeMultiplier;
    // A tiny random offset guarantees no two bodies are ever created at
    // *exactly* the same position — a drop landing on the same spot as
    // something already resting there, or a merge's result spawning
    // where another body happens to be. Box2D's contact-normal math
    // divides by the separation between two circles' centers, and two
    // perfectly coincident ones give it a zero-length vector to
    // normalize — that can produce NaN and poison the whole simulation
    // (freezing it, rather than just looking glitchy) instead of just
    // resolving as an ordinary overlap.
    final jitter = Vector2((_random.nextDouble() - 0.5) * 0.01, (_random.nextDouble() - 0.5) * 0.01);
    final body = IngredientBodyComponent(
      tier: tier,
      ingredient: ingredient,
      spawnPosition: position + jitter,
      radius: radius,
      initialVelocity: velocity,
      laneAccelX: laneAccelX,
      laneAccelDuration: laneAccelDuration,
    );
    world.add(body);
    _liveBodies.add(body);
    onTierSeen(tier);
    return body;
  }

  void _removeBody(IngredientBodyComponent c) {
    _liveBodies.remove(c);
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
  void handleContactBegin(IngredientBodyComponent a, IngredientBodyComponent b) {
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

  void _tryMerge(IngredientBodyComponent a, IngredientBodyComponent b) {
    if (a.consumed || b.consumed) return;
    if (a.tier != b.tier) return;
    final nextTier = a.tier + 1;
    if (nextTier >= _chain.length) return;

    a.consumed = true;
    b.consumed = true;
    final mergedTier = a.tier;
    final midpoint = (a.body.position + b.body.position) / 2;
    final ingredient = a.ingredient;
    _removeBody(a);
    _removeBody(b);
    unawaited(_playMergeSound());
    world.add(
      MergeExplosionComponent(position: midpoint, ingredient: ingredient, onSpawnReady: () => _spawnBody(tier: nextTier, position: midpoint)),
    );
    onMerge(mergedTier);
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
      if (start.consumed || !start.isMounted || visited.contains(start)) continue;
      final component = <IngredientBodyComponent>{};
      final queue = [start];
      visited.add(start);
      while (queue.isNotEmpty) {
        final current = queue.removeLast();
        component.add(current);
        for (final neighbor in _adjacency[current] ?? const <IngredientBodyComponent>{}) {
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

  void _completeCocktail(CocktailRecipe order, List<IngredientBodyComponent> pieces) {
    for (final p in pieces) {
      p.consumed = true;
    }
    final captured = [
      for (final p in pieces) (start: p.body.position.clone(), ingredient: p.ingredient, radius: p.radius),
    ];
    for (final p in pieces) {
      _removeBody(p);
    }
    final center = Vector2(kWorldWidthMeters / 2, _worldHeight / 2);
    unawaited(_playCocktailSound());
    world.add(CocktailRevealComponent(pieces: captured, center: center, cocktailAssetPath: order.assetPath, onComplete: () {}));
    onCocktailComplete(order);
  }

  /// Snapshots everything currently resting on the table — called from
  /// GameScreen.dispose so it can be handed back in as [initialItems]
  /// next time the table's built, since the physics world itself doesn't
  /// survive navigating away.
  List<PlacedItem> capturePlacedItems() => [
    for (final b in _liveBodies)
      if (!b.consumed && b.isMounted) PlacedItem(tier: b.tier, x: b.body.position.x, y: b.body.position.y),
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
    _adjacency.clear();
    _gameOverTriggered = false;
    _overflowStreak = 0;
    _busy = false;
    // Every body a mid-flight shake's squish was tracking is gone now
    // (bodies removed above) — drop that state too rather than let a
    // restore loop over an empty/stale _liveBodies do nothing useful,
    // or a leftover world.gravity multiplier survive into the new game.
    _shakeTimeRemaining = 0;
    _shakeSquishApplied = false;
    _shakeSettleElapsed = 0;
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
  /// Base 0.825 (17.5% smaller) +/- an 0.03 wobble spans 14.5%-20.5%
  /// smaller — the requested 15-20% band — per follow-up feedback that
  /// bumped this up from an initial 10-15%. The X/Y wobble is a full
  /// half-cycle (pi) out of phase with itself (see shakeSquishScaleFor)
  /// rather than a smaller offset, so as one axis shrinks toward the
  /// bottom of that band the other relatively grows toward the top of
  /// it — a genuine squash-stretch flex instead of both axes pulsing in
  /// near-lockstep, per feedback that it should "look a bit flexible."
  static const _shakeSquishBase = 0.825;
  static const _shakeShrinkInDuration = 0.18;
  static const _shakeSettleDuration = 0.35;
  static const _shakeWobbleAmplitude = 0.03;
  static const _shakeWobbleFrequency = 16.0;
  bool _shakeSquishApplied = false;
  double _shakeSettleElapsed = 0;

  void _startShakeImpulses() {
    _shakeTimeRemaining = _shakeDuration;
    _shakePulseTimer = 0;
    _shakeSettleElapsed = 0;
    world.gravity = Vector2(0, -kGravityMagnitude * _shakeGravityMultiplier);
  }

  /// The original Shake purchase — the impulse-pulse jostle only, no
  /// size change. See [megaShakeTable] for the shrink/wobble/flex
  /// version.
  void shakeTable() => _startShakeImpulses();

  /// Mega-Shake — the same impulse pulses as [shakeTable], plus every
  /// live item shrinking/wobbling/flexing for the duration (see
  /// _shakeSquishBase's doc and shakeSquishScaleFor).
  void megaShakeTable() {
    _startShakeImpulses();
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

  /// Removes every cherry (the lowest evolution tier) currently on the
  /// table — the Cherry Bomb purchase.
  void cherryBomb() {
    for (final b in List.of(_liveBodies)) {
      if (b.ingredient.id == 'cherry') {
        _removeBody(b);
      }
    }
  }

  void _updateShake(double dt) {
    if (_shakeTimeRemaining > 0) {
      _shakeTimeRemaining -= dt;
      if (_shakeTimeRemaining <= 0) {
        world.gravity = Vector2(0, -kGravityMagnitude);
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
          final horizontal = (_shakeRandom.nextDouble() - 0.5) * 2.4 * b.body.mass;
          final verticalSign = _shakeRandom.nextBool() ? 1.0 : -1.0;
          final vertical = verticalSign * (2.6 + _shakeRandom.nextDouble() * 2.2) * b.body.mass;
          b.body.applyLinearImpulse(Vector2(horizontal, vertical));
        }
      }
      return;
    }
    // The shake's own timer (and its impulse pulses) has ended, but
    // items are still shrunk — ease them back to full size over
    // _shakeSettleDuration, then restore the real physics radius once
    // that finishes (see shakeSquishScaleFor for the matching visual
    // curve during this window).
    if (!_shakeSquishApplied) return;
    _shakeSettleElapsed += dt;
    if (_shakeSettleElapsed >= _shakeSettleDuration) {
      _shakeSquishApplied = false;
      for (final b in _liveBodies) {
        if (b.isMounted) b.setPhysicsRadiusMultiplier(1.0);
      }
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
        final p = Curves.easeOut.transform((t / _shakeShrinkInDuration).clamp(0.0, 1.0));
        final s = 1.0 - p * (1.0 - _shakeSquishBase);
        return Vector2(s, s);
      }
      final localT = t - _shakeShrinkInDuration;
      final x = _shakeSquishBase + sin(localT * _shakeWobbleFrequency + phase) * _shakeWobbleAmplitude;
      // A full half-cycle out of phase with X (not a partial offset) —
      // when X is at its smallest, Y is at its biggest, and vice versa,
      // which is what actually reads as squashing/stretching rather
      // than everything just pulsing together.
      final y = _shakeSquishBase + sin(localT * _shakeWobbleFrequency + phase + pi) * _shakeWobbleAmplitude;
      return Vector2(x, y);
    }
    if (_shakeTimeRemaining > 0) {
      return wobbleAt(_shakeDuration - _shakeTimeRemaining);
    }
    final atShakeEnd = wobbleAt(_shakeDuration);
    final p = Curves.easeOut.transform((_shakeSettleElapsed / _shakeSettleDuration).clamp(0.0, 1.0));
    return Vector2(
      atShakeEnd.x + (1.0 - atShakeEnd.x) * p,
      atShakeEnd.y + (1.0 - atShakeEnd.y) * p,
    );
  }

  /// Removes every alcoholic item currently on the table (see
  /// Ingredient.isAlcoholic — three on the beach chain, six on the
  /// rooftop one) — shared by the Alcohol-Free purchase (mid-game,
  /// doesn't touch game-over state) and [clearAlcoholicAndResume] (the
  /// ad-continue flow, which also un-ends the game). A per-ingredient
  /// flag rather than a hardcoded id list, since the rooftop chain alone
  /// nearly doubles how many ingredients this needs to catch.
  void clearAlcoholic() {
    for (final b in List.of(_liveBodies)) {
      if (b.ingredient.isAlcoholic) {
        _removeBody(b);
      }
    }
  }

  /// The rewarded-ad "clear all shots" continue: removes every alcoholic
  /// item from the table and un-ends the game — called once the ad
  /// finishes playing; see GameScreen's continue-offer flow. Staging's
  /// own visibility follows board.gameOver via the next syncBoard call as
  /// normal, so nothing extra is needed for that here.
  void clearAlcoholicAndResume() {
    clearAlcoholic();
    _gameOverTriggered = false;
    _overflowStreak = 0;
  }
}
