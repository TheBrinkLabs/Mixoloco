import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/league_scoring.dart';
import '../models/ingredient.dart';

final leagueRepositoryProvider = Provider<LeagueRepository>((ref) {
  return LeagueRepository(FirebaseFirestore.instance);
});

/// One room member, ready for the leaderboard — a player doc's profile
/// fields joined with their current-week score doc. Composed client-side
/// (see [LeagueRepository.fetchRoomLeaderboard]) rather than needing a
/// denormalized copy of the score on the room doc itself, since a room's
/// membership only changes weekly but scores change constantly through
/// the week.
class LeagueLeaderboardEntry {
  final String uid;
  final String nickname;
  final int score;

  /// The bar level (1 or 2) this entry's score was set on — written
  /// alongside bestScore at submit time (see
  /// [LeagueRepository.submitWeeklyScore]), so an older score doc from
  /// before this field existed just reads back as 1 (the default every
  /// run starts on).
  final int level;

  /// This player's lifetime-highest evolution tier per level, same shape
  /// as [BoardState.highestTiers]/[highestLevelReached] — resolve the
  /// actual Ingredient to show with [evolutionIngredient] rather than
  /// indexing the chains directly at every call site.
  /// Per-level lifetime highest tier, index 0 = Level 1.
  final List<int> highestTiers;
  final int highestLevelReached;

  const LeagueLeaderboardEntry({
    required this.uid,
    required this.nickname,
    required this.score,
    this.level = 1,
    this.highestTiers = const [],
    this.highestLevelReached = 1,
  });

  /// The ingredient to show as this entry's "Evolution" badge — same
  /// higher-level-outranks-lower rule the main menu's own Unlocked tab
  /// uses (see menu_screen.dart).
  Ingredient get evolutionIngredient {
    final chain = evolutionChainForLevel(highestLevelReached);
    final tier = highestTierFor(highestTiers, highestLevelReached);
    return chain[tier.clamp(0, chain.length - 1)];
  }
}

/// A snapshot of a player's lifetime economy/evolution progress — the
/// Google-account backup (see [LeagueRepository.pushProgress]/
/// [fetchProgress]), not anything league-ranking-related (that's
/// [LeagueLeaderboardEntry]/submitWeeklyScore's job). Same field shapes as
/// [BoardState]'s own lifetime fields plus the local high-scores list (see
/// high_scores_service.dart).
class PlayerProgress {
  final int credits;

  /// Per-level lifetime highest tier, index 0 = Level 1.
  final List<int> highestTiers;
  final int highestLevelReached;
  final List<int> highScores;

  /// Lifetime cocktail-mixed ids (see progression_service.dart's
  /// loadMixedCocktailIds) — the Guide/Cocktails screens' own "ever
  /// mixed" set, backed up the same way every other lifetime field is.
  final List<String> mixedCocktailIds;

  /// When this snapshot was last written (see [LeagueRepository.
  /// pushProgress]'s own `FieldValue.serverTimestamp()`) — null only for
  /// a snapshot written before this field existed. [progress_sync.dart]
  /// uses this to tell "another device pushed more recently than we last
  /// synced" apart from "we're the freshest," since credits (unlike the
  /// lifetime tier/level fields) isn't safe to merge with a plain max().
  final DateTime? updatedAt;

  const PlayerProgress({
    required this.credits,
    required this.highestTiers,
    required this.highestLevelReached,
    required this.highScores,
    this.mixedCocktailIds = const [],
    this.updatedAt,
  });
}

/// Mirrors Capitle's own league_repository.dart, simplified for
/// Mixoloco's single game mode: there's one score per player per week
/// (players/{uid}/scores/{weekId}, a single `bestScore` field — the
/// player's HIGHEST single run that week, not a sum across several game
/// modes the way Capitle's trivia format needs), and no country-flag
/// profile field (see the nickname-only setup screen).
class LeagueRepository {
  final FirebaseFirestore _db;
  LeagueRepository(this._db);

  CollectionReference<Map<String, dynamic>> get _players => _db.collection('players');

  String currentWeekId() => isoWeekId(DateTime.now().toUtc());

  /// Creates the players/{uid} document the first time a player finishes
  /// the nickname setup screen. Every new player starts pendingJoin=true,
  /// tier=bronze — the weekly/daily rollover jobs are the only things
  /// ever allowed to change tier/roomId/pendingJoin after this. A no-op
  /// if the document already exists (e.g. re-running setup to change a
  /// nickname).
  ///
  /// isTestAccount is stamped from kDebugMode at creation time — debug
  /// builds are dev/test devices, not real players, and without real
  /// uninstall detection they'd otherwise sit in the production league
  /// forever like any other player. The daily join job deletes accounts
  /// flagged this way after 72h — see assignNewJoiners.js.
  Future<void> ensurePlayerDocument({required String uid, required String nickname, String? deviceId}) async {
    // Same timeout reasoning as pushProgress/fetchProgress above — this
    // is the very first Firestore round trip every new player's
    // nickname-setup flow makes, so a hang here (rather than a clean
    // failure the screen's own try/catch can show an error for) was the
    // single most commonly hit "perpetual loading" dead end in the app.
    const timeout = Duration(seconds: 20);
    final ref = _players.doc(uid);
    final snap = await ref.get().timeout(timeout);
    if (snap.exists) return;
    await ref
        .set({
          'nickname': nickname,
          'nicknameLower': nickname.toLowerCase(),
          'tier': 'bronze',
          'roomId': null,
          'pendingJoin': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'isTestAccount': kDebugMode,
          if (deviceId != null) 'deviceId': deviceId,
        })
        .timeout(timeout);
  }

  Future<void> syncNickname({required String uid, required String nickname}) async {
    await _players
        .doc(uid)
        .update({
          'nickname': nickname,
          'nicknameLower': nickname.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getPlayer(String uid) =>
      _players.doc(uid).get().timeout(const Duration(seconds: 20));

  /// This player's recorded result for [weekId] — written by rollover.js
  /// to players/{uid}/weekHistory/{weekId} at the end of that week
  /// (score, rank, tier, roomSize, outcome, and creditsAwarded — the one
  /// field Capitle's own weekHistory doesn't have, since leagues are
  /// purely cosmetic there). A plain single-document read, not a query,
  /// so it needs no Firestore index. Returns null if that week never
  /// rolled over for this player (e.g. they joined after it ended, or
  /// the rollover hasn't run yet).
  Future<Map<String, dynamic>?> weekResult(String uid, String weekId) async {
    final doc = await _players.doc(uid).collection('weekHistory').doc(weekId).get();
    return doc.data();
  }

  /// This player's current-week best score, or 0 if they haven't
  /// submitted one yet.
  Future<int> myWeeklyBestScore(String uid) async {
    final doc = await _players.doc(uid).collection('scores').doc(currentWeekId()).get();
    return (doc.data()?['bestScore'] as int?) ?? 0;
  }

  /// Submits [score] as a candidate for this week's best — only actually
  /// raises players/{uid}/scores/{weekId}.bestScore if it beats whatever
  /// is already there (leagues rank on your HIGHEST score in the week,
  /// not a cumulative total), enforced both here (so a worse run never
  /// overwrites a better one already recorded) and again server-side in
  /// firestore.rules (bestScore may only ever increase) as defense in
  /// depth against a tampered client.
  ///
  /// [playedAt] defaults to now, but should be the ORIGINAL time the game
  /// was actually played for a retried/queued submission — otherwise a
  /// score earned late one night that only manages to submit the next
  /// morning would get filed under the wrong week entirely.
  ///
  /// [level]/[highestTiers]/[highestLevelReached] are this player's
  /// own progress at submit time — purely informational extras on top of
  /// bestScore (see [LeagueLeaderboardEntry]), not subject to
  /// firestore.rules' bestScore-only validation, so they're free-form
  /// here.
  Future<void> submitWeeklyScore({
    required String uid,
    required int score,
    DateTime? playedAt,
    int level = 1,
    List<int> highestTiers = const [],
    int highestLevelReached = 1,
  }) async {
    final playedAtUtc = (playedAt ?? DateTime.now()).toUtc();
    final weekId = isoWeekId(playedAtUtc);
    final scoreRef = _players.doc(uid).collection('scores').doc(weekId);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(scoreRef);
      final existing = (snap.data()?['bestScore'] as int?) ?? 0;
      if (score <= existing) return; // not a new best — nothing to do
      tx.set(scoreRef, {
        'bestScore': score,
        'weekId': weekId,
        'level': level,
        ...highestTierFields(highestTiers),
        'highestLevelReached': highestLevelReached,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    // Distinct from 'updatedAt' (which the rollover jobs also touch on
    // every player they reassign, win or lose, active or not — so it
    // can't be trusted as a genuine "last played" signal). This is ONLY
    // written when a real score is actually submitted, which is what
    // rollover.js's inactivity pruning depends on to tell a real player
    // on a break from an abandoned reinstall-ghost that will never play
    // again.
    final playerRef = _players.doc(uid);
    await playerRef.set({
      'lastActiveAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // A player pruned for inactivity (see rollover.js) is left "parked"
    // — roomId: null, pendingJoin: false — deliberately NOT re-queued
    // automatically, so the calendar ticking over doesn't undo the
    // prune. Actually playing again (this call) is the real "welcome
    // back" signal, so re-queue them for the next room-assignment
    // sweep here. (firestore.rules only allows this specific
    // false->true flip when the player is already in that exact parked
    // state.)
    final snap = await playerRef.get();
    final data = snap.data();
    if (data != null && data['roomId'] == null && data['pendingJoin'] != true) {
      await playerRef.set({'pendingJoin': true, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    }
  }

  /// Composes the current leaderboard for [roomId]: every member's
  /// nickname (from players/{uid}) joined with their score for [weekId]
  /// (from players/{uid}/scores/{weekId}), sorted highest-first. A room
  /// tops out at 19 members (see assignRooms.js's Gold bounds), so this
  /// is a small, one-shot fan-out rather than anything needing
  /// pagination or a denormalized copy.
  Future<List<LeagueLeaderboardEntry>> fetchRoomLeaderboard({required String roomId, required String weekId}) async {
    final roomSnap = await _db.collection('leagueRooms').doc(roomId).get();
    final memberUids = List<String>.from(roomSnap.data()?['memberUids'] as List? ?? const []);
    if (memberUids.isEmpty) return const [];

    final entries = await Future.wait(memberUids.map((uid) async {
      final playerSnap = await _players.doc(uid).get();
      final scoreSnap = await _players.doc(uid).collection('scores').doc(weekId).get();
      final nickname = (playerSnap.data()?['nickname'] as String?) ?? 'Player';
      final scoreData = scoreSnap.data();
      final score = (scoreData?['bestScore'] as int?) ?? 0;
      return LeagueLeaderboardEntry(
        uid: uid,
        nickname: nickname,
        score: score,
        level: (scoreData?['level'] as int?) ?? 1,
        highestTiers: readHighestTiers(scoreData),
        highestLevelReached: (scoreData?['highestLevelReached'] as int?) ?? 1,
      );
    }));

    entries.sort((a, b) => (b.score - a.score) != 0 ? b.score - a.score : a.uid.compareTo(b.uid));
    return entries;
  }

  /// Writes this player's full progress snapshot to
  /// players/{uid}/progress/current — the Google-account backup (see
  /// progress_sync.dart, which owns *when* this gets called and the
  /// merge logic around it). A plain overwrite, not a merge: every field
  /// is always supplied together, so there's no stale-field risk the way
  /// a partial merge could leave behind.
  Future<void> pushProgress({required String uid, required PlayerProgress progress}) async {
    // Same reasoning as AuthService.linkGoogle's own timeouts — a plain
    // Firestore call with nothing bounding it can hang indefinitely on a
    // bad connection, and progress_sync.dart's retry loop only actually
    // helps if each individual attempt eventually gives up and fails
    // rather than hanging forever.
    await _players
        .doc(uid)
        .collection('progress')
        .doc('current')
        .set({
          'credits': progress.credits,
          ...highestTierFields(progress.highestTiers),
          'highestLevelReached': progress.highestLevelReached,
          'highScores': progress.highScores,
          'mixedCocktailIds': progress.mixedCocktailIds,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 20));
  }

  /// Reads this player's backed-up progress, or null if they've never
  /// pushed one (never signed in with Google, or signed in but nothing's
  /// synced yet).
  Future<PlayerProgress?> fetchProgress(String uid) async {
    final doc = await _players.doc(uid).collection('progress').doc('current').get().timeout(const Duration(seconds: 20));
    final data = doc.data();
    if (data == null) return null;
    return PlayerProgress(
      credits: (data['credits'] as int?) ?? 0,
      highestTiers: readHighestTiers(data),
      highestLevelReached: (data['highestLevelReached'] as int?) ?? 1,
      highScores: ((data['highScores'] as List?) ?? const []).cast<int>(),
      mixedCocktailIds: ((data['mixedCocktailIds'] as List?) ?? const []).cast<String>(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// "Never reached" for [level]: Level 1 starts at tier 0, every later
/// level at -1 (so its first tier still counts as a new milestone).
int defaultHighestTier(int level) => level <= 1 ? 0 : -1;

/// [level]'s entry in a per-level tier list (index 0 = Level 1), or its
/// default if the list is shorter (an older save/snapshot).
int highestTierFor(List<int> tiers, int level) =>
    level >= 1 && level <= tiers.length ? tiers[level - 1] : defaultHighestTier(level);

/// Firestore field name for [level]'s record — Level 1 keeps the original
/// unsuffixed name, so every existing document still reads correctly.
String highestTierField(int level) =>
    level <= 1 ? 'highestTierUnlocked' : 'highestTierUnlockedLevel$level';

Map<String, int> highestTierFields(List<int> tiers) => {
  for (var level = 1; level <= kLevelCount; level++)
    highestTierField(level): highestTierFor(tiers, level),
};

List<int> readHighestTiers(Map<String, dynamic>? data) => [
  for (var level = 1; level <= kLevelCount; level++)
    (data?[highestTierField(level)] as int?) ?? defaultHighestTier(level),
];
