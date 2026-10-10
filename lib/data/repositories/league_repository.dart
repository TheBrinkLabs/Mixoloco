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

  /// This player's lifetime-highest evolution tier reached, same shape
  /// as [BoardState.highestTierUnlocked]/[highestTierUnlockedLevel2]/
  /// [highestTierUnlockedLevel3]/[highestLevelReached] — resolve the
  /// actual Ingredient to show with [evolutionIngredient] rather than
  /// indexing the chains directly at every call site.
  final int highestTierUnlocked;
  final int highestTierUnlockedLevel2;
  final int highestTierUnlockedLevel3;
  final int highestTierUnlockedLevel4;
  final int highestLevelReached;

  const LeagueLeaderboardEntry({
    required this.uid,
    required this.nickname,
    required this.score,
    this.level = 1,
    this.highestTierUnlocked = 0,
    this.highestTierUnlockedLevel2 = -1,
    this.highestTierUnlockedLevel3 = -1,
    this.highestTierUnlockedLevel4 = -1,
    this.highestLevelReached = 1,
  });

  /// The ingredient to show as this entry's "Evolution" badge — same
  /// higher-level-outranks-lower rule the main menu's own Unlocked tab
  /// uses (see menu_screen.dart).
  Ingredient get evolutionIngredient {
    if (highestLevelReached >= 4) {
      return kEvolutionChainLevel4[highestTierUnlockedLevel4.clamp(0, kEvolutionChainLevel4.length - 1)];
    }
    if (highestLevelReached >= 3) {
      return kEvolutionChainLevel3[highestTierUnlockedLevel3.clamp(0, kEvolutionChainLevel3.length - 1)];
    }
    if (highestLevelReached >= 2) {
      return kEvolutionChainLevel2[highestTierUnlockedLevel2.clamp(0, kEvolutionChainLevel2.length - 1)];
    }
    return kEvolutionChain[highestTierUnlocked.clamp(0, kEvolutionChain.length - 1)];
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
  final int highestTierUnlocked;
  final int highestTierUnlockedLevel2;
  final int highestTierUnlockedLevel3;
  final int highestTierUnlockedLevel4;
  final int highestLevelReached;
  final List<int> highScores;

  /// When this snapshot was last written (see [LeagueRepository.
  /// pushProgress]'s own `FieldValue.serverTimestamp()`) — null only for
  /// a snapshot written before this field existed. [progress_sync.dart]
  /// uses this to tell "another device pushed more recently than we last
  /// synced" apart from "we're the freshest," since credits (unlike the
  /// lifetime tier/level fields) isn't safe to merge with a plain max().
  final DateTime? updatedAt;

  const PlayerProgress({
    required this.credits,
    required this.highestTierUnlocked,
    required this.highestTierUnlockedLevel2,
    required this.highestTierUnlockedLevel3,
    required this.highestTierUnlockedLevel4,
    required this.highestLevelReached,
    required this.highScores,
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
    final ref = _players.doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'nickname': nickname,
      'nicknameLower': nickname.toLowerCase(),
      'tier': 'bronze',
      'roomId': null,
      'pendingJoin': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isTestAccount': kDebugMode,
      if (deviceId != null) 'deviceId': deviceId,
    });
  }

  Future<void> syncNickname({required String uid, required String nickname}) async {
    await _players.doc(uid).update({
      'nickname': nickname,
      'nicknameLower': nickname.toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getPlayer(String uid) => _players.doc(uid).get();

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
  /// [level]/[highestTierUnlocked]/[highestTierUnlockedLevel2]/
  /// [highestTierUnlockedLevel3]/[highestLevelReached] are this player's
  /// own progress at submit time — purely informational extras on top of
  /// bestScore (see [LeagueLeaderboardEntry]), not subject to
  /// firestore.rules' bestScore-only validation, so they're free-form
  /// here.
  Future<void> submitWeeklyScore({
    required String uid,
    required int score,
    DateTime? playedAt,
    int level = 1,
    int highestTierUnlocked = 0,
    int highestTierUnlockedLevel2 = -1,
    int highestTierUnlockedLevel3 = -1,
    int highestTierUnlockedLevel4 = -1,
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
        'highestTierUnlocked': highestTierUnlocked,
        'highestTierUnlockedLevel2': highestTierUnlockedLevel2,
        'highestTierUnlockedLevel3': highestTierUnlockedLevel3,
        'highestTierUnlockedLevel4': highestTierUnlockedLevel4,
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
        highestTierUnlocked: (scoreData?['highestTierUnlocked'] as int?) ?? 0,
        highestTierUnlockedLevel2: (scoreData?['highestTierUnlockedLevel2'] as int?) ?? -1,
        highestTierUnlockedLevel3: (scoreData?['highestTierUnlockedLevel3'] as int?) ?? -1,
        highestTierUnlockedLevel4: (scoreData?['highestTierUnlockedLevel4'] as int?) ?? -1,
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
    await _players.doc(uid).collection('progress').doc('current').set({
      'credits': progress.credits,
      'highestTierUnlocked': progress.highestTierUnlocked,
      'highestTierUnlockedLevel2': progress.highestTierUnlockedLevel2,
      'highestTierUnlockedLevel3': progress.highestTierUnlockedLevel3,
      'highestTierUnlockedLevel4': progress.highestTierUnlockedLevel4,
      'highestLevelReached': progress.highestLevelReached,
      'highScores': progress.highScores,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Reads this player's backed-up progress, or null if they've never
  /// pushed one (never signed in with Google, or signed in but nothing's
  /// synced yet).
  Future<PlayerProgress?> fetchProgress(String uid) async {
    final doc = await _players.doc(uid).collection('progress').doc('current').get();
    final data = doc.data();
    if (data == null) return null;
    return PlayerProgress(
      credits: (data['credits'] as int?) ?? 0,
      highestTierUnlocked: (data['highestTierUnlocked'] as int?) ?? 0,
      highestTierUnlockedLevel2: (data['highestTierUnlockedLevel2'] as int?) ?? -1,
      highestTierUnlockedLevel3: (data['highestTierUnlockedLevel3'] as int?) ?? -1,
      highestTierUnlockedLevel4: (data['highestTierUnlockedLevel4'] as int?) ?? -1,
      highestLevelReached: (data['highestLevelReached'] as int?) ?? 1,
      highScores: ((data['highScores'] as List?) ?? const []).cast<int>(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
