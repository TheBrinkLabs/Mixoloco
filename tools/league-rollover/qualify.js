'use strict';

// Only players who've actually played a real game are in the league: a
// week's best score must reach this to be placed in (or carried into) a
// room. Without it, everyone who ever set a nickname filled rooms with
// 0-point entries. Must match kLeagueMinScore in league_repository.dart,
// which hides anyone below it from the leaderboard.
const MIN_QUALIFYING_SCORE = 1000;

/** This player's best score for [weekId] (0 if none). */
async function weekBestScore(db, uid, weekId) {
  const doc = await db.collection('players').doc(uid).collection('scores').doc(weekId).get();
  return doc.exists ? (doc.data().bestScore || 0) : 0;
}

/** The subset of [uids] whose best score for [weekId] qualifies them. */
async function filterQualified(db, uids, weekId) {
  const scores = await Promise.all(uids.map((uid) => weekBestScore(db, uid, weekId)));
  return uids.filter((_, i) => scores[i] >= MIN_QUALIFYING_SCORE);
}

module.exports = { MIN_QUALIFYING_SCORE, weekBestScore, filterQualified };
