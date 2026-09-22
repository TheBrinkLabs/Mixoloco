import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/league_scoring.dart';

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
  const LeagueLeaderboardEntry({required this.uid, required this.nickname, required this.score});
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
  Future<void> submitWeeklyScore({required String uid, required int score, DateTime? playedAt}) async {
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
      final score = (scoreSnap.data()?['bestScore'] as int?) ?? 0;
      return LeagueLeaderboardEntry(uid: uid, nickname: nickname, score: score);
    }));

    entries.sort((a, b) => (b.score - a.score) != 0 ? b.score - a.score : a.uid.compareTo(b.uid));
    return entries;
  }
}
