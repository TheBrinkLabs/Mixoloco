import 'package:flutter/foundation.dart';
import '../../data/models/ingredient.dart' show kLevelCount;
import '../../data/repositories/league_repository.dart';
import '../../data/services/high_scores_service.dart';
import '../../data/services/league_local_service.dart';
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
/// Returns [ProgressSyncOutcome.changed] if local state actually changed,
/// [ProgressSyncOutcome.unchanged] if the sync completed but there was
/// nothing new to pull down, or [ProgressSyncOutcome.failed] if the whole
/// attempt (after retrying) never completed — a caller (the Settings
/// sign-in row, the nickname-setup "restore" option, or MenuScreen's own
/// launch check) needs this three-way split, not just a bool, so it can
/// tell the difference between "nothing to restore" and "we don't
/// actually know, this didn't work" — the UI should never claim "your
/// progress has been restored" off the back of a failed sync. A previous
/// version silently swallowed any failure (debugPrint + return false),
/// which combined with the Settings row showing "restored" purely off of
/// Firebase Auth having switched to the player's older linked account
/// (not off this function's own result) meant a transient failure right
/// after that account switch — exactly when the auth token most recently
/// changed and a permission-denied race is most likely — looked
/// identical to a genuinely empty backup: the player saw "welcome back,
/// restored!" while still sitting on a fresh Level 1 save. Retrying a
/// few times with a short backoff (same shape as GameStateNotifier.
/// _loadPersisted's own retry) makes a merely transient failure recover
/// on its own instead of surfacing as a false "nothing to restore."
Future<ProgressSyncOutcome> syncProgress(LeagueRepository leagueRepo, String uid) async {
  const maxAttempts = 3;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await _syncProgressOnce(leagueRepo, uid);
    } catch (e, st) {
      debugPrint('Progress sync attempt $attempt/$maxAttempts failed: $e\n$st');
      if (attempt == maxAttempts) return ProgressSyncOutcome.failed;
      await Future.delayed(Duration(milliseconds: 300 * attempt));
    }
  }
  return ProgressSyncOutcome.failed;
}

Future<ProgressSyncOutcome> _syncProgressOnce(LeagueRepository leagueRepo, String uid) async {
  final server = await leagueRepo.fetchProgress(uid);
  final lastSyncAt = await loadLastProgressSyncAt();

  final localCredits = await loadCredits();
  final localTiers = await loadHighestTiers(kLevelCount);
  final localLevel = await loadHighestLevelReached();
  final localScores = await loadHighScores();
  final localMixedCocktails = await loadMixedCocktailIds();

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
  final mergedTiers = [
    for (var level = 1; level <= kLevelCount; level++)
      server == null
          ? localTiers[level - 1]
          : _max(localTiers[level - 1], highestTierFor(server.highestTiers, level)),
  ];
  final mergedLevel = server == null ? localLevel : _max(localLevel, server.highestLevelReached);

  final mergedScores = <int>{...localScores, ...?server?.highScores}.toList()..sort((a, b) => b.compareTo(a));
  final topScores = mergedScores.take(kMaxHighScores).toList();

  // Same "only ever grows" reasoning as the tier/level fields — a union
  // rather than a max() since this is a set of distinct achievements,
  // not a single comparable number.
  final mergedMixedCocktails = <String>{...localMixedCocktails, ...?server?.mixedCocktailIds};

  final changed =
      mergedCredits != localCredits ||
      !_sameList(mergedTiers, localTiers) ||
      mergedLevel != localLevel ||
      !_sameList(topScores, localScores) ||
      mergedMixedCocktails.length != localMixedCocktails.length;

  if (changed) {
    await saveCredits(mergedCredits);
    for (var level = 1; level <= kLevelCount; level++) {
      await saveHighestTierForLevel(level, mergedTiers[level - 1]);
    }
    await saveHighestLevelReached(mergedLevel);
    await saveHighScores(topScores);
    await saveMixedCocktailIds(mergedMixedCocktails);
  }

  await leagueRepo.pushProgress(
    uid: uid,
    progress: PlayerProgress(
      credits: mergedCredits,
      highestTiers: mergedTiers,
      highestLevelReached: mergedLevel,
      highScores: topScores,
      mixedCocktailIds: mergedMixedCocktails.toList(),
    ),
  );
  // This device's credits (merged or not) are now known to match what
  // was just pushed — marks the point future syncs compare the
  // server's own updatedAt against.
  await saveLastProgressSyncAt(DateTime.now());

  // The nickname lives on players/{uid}, not in the progress snapshot —
  // the account's own name wins over whatever this device had (a fresh
  // install, or an anonymous fallback name). Never creates the player
  // document here: that would enrol this account in the league.
  final remoteNickname = (await leagueRepo.getPlayer(uid)).data()?['nickname'] as String?;
  if (remoteNickname != null && remoteNickname.isNotEmpty && remoteNickname != await loadNickname()) {
    await saveNickname(remoteNickname);
  }

  return changed ? ProgressSyncOutcome.changed : ProgressSyncOutcome.unchanged;
}

enum ProgressSyncOutcome { changed, unchanged, failed }

int _max(int a, int b) => a > b ? a : b;

bool _sameList(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
