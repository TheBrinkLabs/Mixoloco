import 'package:flutter/foundation.dart';
import '../../data/repositories/league_repository.dart';
import '../../data/services/high_scores_service.dart';
import '../../data/services/progression_service.dart';

/// Reconciles this player's local lifetime progress (credits, evolution
/// tiers, highest level reached, local high scores — all plain
/// SharedPreferences values, nothing server-backed on its own) against
/// their Google-account backup (see LeagueRepository.pushProgress/
/// fetchProgress). Field-by-field max-merge rather than wholesale
/// either-or: whichever side is ahead on a given field wins for that
/// field, so a player who played a bunch anonymously before signing in
/// keeps that progress, AND a player restoring onto a fresh install gets
/// their old progress back — never a net loss in either direction, and no
/// need to reason about which side is more recent.
///
/// Always pushes the merged result back to the server too, even when
/// nothing local changed — so a device that was behind catches the
/// server up immediately rather than waiting for its next local progress
/// event (merge, tier-up, game over, ...).
///
/// Returns true if local state actually changed, so a caller (the
/// Settings sign-in row, or MenuScreen's own launch check) knows whether
/// to refresh anything reading those values and/or tell the player their
/// progress was restored.
Future<bool> syncProgress(LeagueRepository leagueRepo, String uid) async {
  try {
    final server = await leagueRepo.fetchProgress(uid);

    final localCredits = await loadCredits();
    final localTier1 = await loadHighestTier();
    final localTier2 = await loadHighestTierLevel2();
    final localTier3 = await loadHighestTierLevel3();
    final localLevel = await loadHighestLevelReached();
    final localScores = await loadHighScores();

    final mergedCredits = server == null ? localCredits : _max(localCredits, server.credits);
    final mergedTier1 = server == null ? localTier1 : _max(localTier1, server.highestTierUnlocked);
    final mergedTier2 = server == null ? localTier2 : _max(localTier2, server.highestTierUnlockedLevel2);
    final mergedTier3 = server == null ? localTier3 : _max(localTier3, server.highestTierUnlockedLevel3);
    final mergedLevel = server == null ? localLevel : _max(localLevel, server.highestLevelReached);

    final mergedScores = <int>{...localScores, ...?server?.highScores}.toList()..sort((a, b) => b.compareTo(a));
    final topScores = mergedScores.take(kMaxHighScores).toList();

    final changed =
        mergedCredits != localCredits ||
        mergedTier1 != localTier1 ||
        mergedTier2 != localTier2 ||
        mergedTier3 != localTier3 ||
        mergedLevel != localLevel ||
        !_sameList(topScores, localScores);

    if (changed) {
      await saveCredits(mergedCredits);
      await saveHighestTier(mergedTier1);
      await saveHighestTierLevel2(mergedTier2);
      await saveHighestTierLevel3(mergedTier3);
      await saveHighestLevelReached(mergedLevel);
      await saveHighScores(topScores);
    }

    await leagueRepo.pushProgress(
      uid: uid,
      progress: PlayerProgress(
        credits: mergedCredits,
        highestTierUnlocked: mergedTier1,
        highestTierUnlockedLevel2: mergedTier2,
        highestTierUnlockedLevel3: mergedTier3,
        highestLevelReached: mergedLevel,
        highScores: topScores,
      ),
    );

    return changed;
  } catch (e, st) {
    debugPrint('Progress sync failed (non-fatal): $e\n$st');
    return false;
  }
}

int _max(int a, int b) => a > b ? a : b;

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
