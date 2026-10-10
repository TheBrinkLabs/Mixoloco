import 'package:flutter/foundation.dart';
import '../../data/repositories/league_repository.dart';
import '../../data/services/high_scores_service.dart';
import '../../data/services/progression_service.dart';

/// Reconciles this player's local lifetime progress (credits, evolution
/// tiers, highest level reached, local high scores — all plain
/// SharedPreferences values, nothing server-backed on its own) against
/// their Google-account backup (see LeagueRepository.pushProgress/
/// fetchProgress).
///
/// The tier/level fields and high scores are genuine lifetime bests —
/// they only ever go up, so a field-by-field max-merge is always safe:
/// whichever side is ahead wins, so a player who played a bunch
/// anonymously before signing in keeps that progress, AND a player
/// restoring onto a fresh install gets their old progress back.
///
/// Credits is different — it's a *current balance*, not a best-ever
/// record, and spending it is a legitimate decrease. Treating it like
/// the tier fields broke on two devices sharing one Google account: spend
/// on the phone (pushed to the server immediately), then open a tablet
/// that's been sitting on a stale, higher local balance — a max-merge
/// would resurrect the pre-spend number on both. Instead this compares
/// [PlayerProgress.updatedAt] against [loadLastProgressSyncAt] (this
/// device's own "last time I was confirmed in sync" marker, set at the
/// end of this function): if the server was pushed to more recently than
/// this device last synced, another device has moved things forward
/// since, so the server's credits win; otherwise this device is the
/// freshest copy and its own local credits win (and get pushed up). A
/// device that's never synced before (no marker yet, or the server
/// snapshot predates this field) falls back to the same safe max-merge
/// every other field uses, so first-time linking still can't lose
/// anonymous-earned credits.
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
    final lastSyncAt = await loadLastProgressSyncAt();

    final localCredits = await loadCredits();
    final localTier1 = await loadHighestTier();
    final localTier2 = await loadHighestTierLevel2();
    final localTier3 = await loadHighestTierLevel3();
    final localTier4 = await loadHighestTierLevel4();
    final localLevel = await loadHighestLevelReached();
    final localScores = await loadHighScores();

    int mergedCredits;
    if (server == null) {
      mergedCredits = localCredits;
    } else if (lastSyncAt != null && server.updatedAt != null) {
      mergedCredits = server.updatedAt!.isAfter(lastSyncAt) ? server.credits : localCredits;
    } else {
      // No local sync marker yet (first-ever sync on this device) or a
      // pre-updatedAt server snapshot — same safe max-merge as the other
      // fields rather than guessing which side is "right."
      mergedCredits = _max(localCredits, server.credits);
    }
    final mergedTier1 = server == null ? localTier1 : _max(localTier1, server.highestTierUnlocked);
    final mergedTier2 = server == null ? localTier2 : _max(localTier2, server.highestTierUnlockedLevel2);
    final mergedTier3 = server == null ? localTier3 : _max(localTier3, server.highestTierUnlockedLevel3);
    final mergedTier4 = server == null ? localTier4 : _max(localTier4, server.highestTierUnlockedLevel4);
    final mergedLevel = server == null ? localLevel : _max(localLevel, server.highestLevelReached);

    final mergedScores = <int>{...localScores, ...?server?.highScores}.toList()..sort((a, b) => b.compareTo(a));
    final topScores = mergedScores.take(kMaxHighScores).toList();

    final changed =
        mergedCredits != localCredits ||
        mergedTier1 != localTier1 ||
        mergedTier2 != localTier2 ||
        mergedTier3 != localTier3 ||
        mergedTier4 != localTier4 ||
        mergedLevel != localLevel ||
        !_sameList(topScores, localScores);

    if (changed) {
      await saveCredits(mergedCredits);
      await saveHighestTier(mergedTier1);
      await saveHighestTierLevel2(mergedTier2);
      await saveHighestTierLevel3(mergedTier3);
      await saveHighestTierLevel4(mergedTier4);
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
        highestTierUnlockedLevel4: mergedTier4,
        highestLevelReached: mergedLevel,
        highScores: topScores,
      ),
    );
    // This device's credits (merged or not) are now known to match what
    // was just pushed — marks the point future syncs compare the
    // server's own updatedAt against.
    await saveLastProgressSyncAt(DateTime.now());

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
