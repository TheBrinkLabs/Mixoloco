import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/utils/league_scoring.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/league_local_service.dart';
import '../../game/providers/game_state_provider.dart';

/// Everything the league screen needs, loaded together — this player's
/// tier/room standing, their current room's live leaderboard, and last
/// week's result (with its credit reward claimed exactly once). Kept as
/// one cohesive controller rather than several fragmented providers,
/// matching how GameStateNotifier is the one source of truth for the
/// game screen — the league screen has the same "load a handful of
/// related things together, once" shape.
class LeagueState {
  final bool loading;
  final String? error;
  final String? uid;
  final String? nickname;
  final String tier; // 'bronze' / 'silver' / 'gold'
  final bool pendingJoin; // signed up, not yet placed in a room
  final String? roomId;
  final List<LeagueLeaderboardEntry> leaderboard;
  final int myWeeklyBestScore;
  final Map<String, dynamic>? lastWeekResult; // weekHistory doc, if any
  final bool lastWeekResultIsNew; // true only long enough to show the celebration once

  const LeagueState({
    this.loading = true,
    this.error,
    this.uid,
    this.nickname,
    this.tier = 'bronze',
    this.pendingJoin = true,
    this.roomId,
    this.leaderboard = const [],
    this.myWeeklyBestScore = 0,
    this.lastWeekResult,
    this.lastWeekResultIsNew = false,
  });

  LeagueState copyWith({
    bool? loading,
    String? error,
    String? uid,
    String? nickname,
    String? tier,
    bool? pendingJoin,
    String? roomId,
    List<LeagueLeaderboardEntry>? leaderboard,
    int? myWeeklyBestScore,
    Map<String, dynamic>? lastWeekResult,
    bool? lastWeekResultIsNew,
  }) {
    return LeagueState(
      loading: loading ?? this.loading,
      error: error,
      uid: uid ?? this.uid,
      nickname: nickname ?? this.nickname,
      tier: tier ?? this.tier,
      pendingJoin: pendingJoin ?? this.pendingJoin,
      roomId: roomId ?? this.roomId,
      leaderboard: leaderboard ?? this.leaderboard,
      myWeeklyBestScore: myWeeklyBestScore ?? this.myWeeklyBestScore,
      lastWeekResult: lastWeekResult ?? this.lastWeekResult,
      lastWeekResultIsNew: lastWeekResultIsNew ?? this.lastWeekResultIsNew,
    );
  }
}

class LeagueController extends Notifier<LeagueState> {
  @override
  LeagueState build() => const LeagueState();

  /// Whether this player has ever completed the nickname setup screen —
  /// checked locally first (no network needed for the common case of a
  /// returning player), matches [LeagueLocalService]'s own trade-off.
  Future<bool> hasLocalNickname() async => (await loadNickname())?.isNotEmpty ?? false;

  /// Loads everything the league screen shows: this player's own
  /// standing, their current room's leaderboard (if they're placed in
  /// one yet), and last week's result — claiming its credit reward
  /// exactly once if it hasn't been claimed already (see
  /// league_local_service.dart's loadLastClaimedWeekId).
  Future<void> refresh() async {
    state = state.copyWith(loading: true, error: null);

    final uid = authService.uid;
    if (uid == null) {
      state = state.copyWith(loading: false, error: 'not_signed_in', uid: null);
      return;
    }

    try {
      final repo = ref.read(leagueRepositoryProvider);
      final weekId = repo.currentWeekId();

      final playerSnap = await repo.getPlayer(uid);
      final playerData = playerSnap.data();
      final tier = (playerData?['tier'] as String?) ?? 'bronze';
      final pendingJoin = (playerData?['pendingJoin'] as bool?) ?? true;
      final roomId = playerData?['roomId'] as String?;
      final nickname = (playerData?['nickname'] as String?) ?? await loadNickname();

      final leaderboard = roomId != null ? await repo.fetchRoomLeaderboard(roomId: roomId, weekId: weekId) : const <LeagueLeaderboardEntry>[];
      final myBest = await repo.myWeeklyBestScore(uid);

      // Last week's result, if the rollover job has run for it yet — a
      // brand new player, or one who joined mid-week, may simply have
      // none, which is fine (pendingJoin/leaderboard already say enough
      // in that case).
      final lastWeekId = isoWeekId(currentWeekStartUtc().subtract(const Duration(days: 1)));
      final lastWeekResult = await repo.weekResult(uid, lastWeekId);

      var lastWeekResultIsNew = false;
      if (lastWeekResult != null) {
        final creditsAwarded = (lastWeekResult['creditsAwarded'] as int?) ?? 0;
        final alreadyClaimed = await loadLastClaimedWeekId();
        if (creditsAwarded > 0 && alreadyClaimed != lastWeekId) {
          ref.read(gameStateProvider.notifier).addLeagueCredits(creditsAwarded);
          await saveLastClaimedWeekId(lastWeekId);
          lastWeekResultIsNew = true;
        }
      }

      state = LeagueState(
        loading: false,
        uid: uid,
        nickname: nickname,
        tier: tier,
        pendingJoin: pendingJoin,
        roomId: roomId,
        leaderboard: leaderboard,
        myWeeklyBestScore: myBest,
        lastWeekResult: lastWeekResult,
        lastWeekResultIsNew: lastWeekResultIsNew,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }
}

final leagueControllerProvider = NotifierProvider<LeagueController, LeagueState>(LeagueController.new);
