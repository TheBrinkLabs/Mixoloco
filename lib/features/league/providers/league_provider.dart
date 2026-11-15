import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/utils/league_scoring.dart';
import '../../../data/repositories/league_repository.dart';
import '../../../data/services/league_local_service.dart';
import '../../game/providers/game_state_provider.dart';

/// Everything the league screen needs, loaded together — this week's
/// global top 10, this player's own best, and last week's result (with
/// its credit reward claimed exactly once). Kept as one cohesive
/// controller rather than several fragmented providers, matching how
/// GameStateNotifier is the one source of truth for the game screen.
class LeagueState {
  final bool loading;
  final String? error;
  final String? uid;
  final String? nickname;
  final List<LeagueLeaderboardEntry> leaderboard;
  final int myWeeklyBestScore;
  final Map<String, dynamic>? lastWeekResult; // weekHistory doc, if any
  final bool lastWeekResultIsNew; // true only long enough to show the celebration once

  const LeagueState({
    this.loading = true,
    this.error,
    this.uid,
    this.nickname,
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
  ///
  /// Falls back to Firestore when the local cache is empty but the
  /// player is signed in — being Google-linked (see Settings' own
  /// "backed up" check, [AuthService.isLinkedToGoogle]) and having a
  /// local nickname cached are two completely independent facts. A
  /// player who links Google from Settings without ever having opened
  /// Rankings first (e.g. restoring an existing account on a fresh
  /// install) already has a `players/{uid}` profile server-side, but
  /// nothing ever wrote `league_nickname` locally — without this
  /// fallback they'd be routed to the nickname-setup screen despite
  /// already being fully set up, and it would loop forever since
  /// setup's own "Sign in with Google" button has nothing left to do.
  Future<bool> hasNickname() async {
    final local = await loadNickname();
    if (local != null && local.isNotEmpty) return true;
    final uid = authService.uid;
    if (uid == null) return false;
    try {
      final snap = await ref.read(leagueRepositoryProvider).getPlayer(uid);
      final remoteNickname = snap.data()?['nickname'] as String?;
      if (remoteNickname != null && remoteNickname.isNotEmpty) {
        await saveNickname(remoteNickname);
        return true;
      }
    } catch (_) {
      // Offline/error — fall through, same as "not set up yet."
    }
    return false;
  }

  /// Loads everything the league screen shows: this week's global top
  /// 10, this player's own best, and last week's result — claiming its
  /// credit reward exactly once if it hasn't been claimed already (see
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
      final nickname = (playerSnap.data()?['nickname'] as String?) ?? await loadNickname();

      final leaderboard = await repo.fetchWeeklyTop(weekId: weekId);
      final myBest = await repo.myWeeklyBestScore(uid);

      // Last week's result — only written by the Monday job for that
      // week's top 10, so most players simply have none.
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
