'use strict';

// Weekly Mixoloco league payout — runs Monday 00:00 UTC. The league is one
// global board: the 10 highest weekly best scores worldwide
// (players/{uid}/scores/{weekId}.bestScore, written by the app via a
// max-if-greater transaction — see league_repository.dart). This job
// closes the week that just ended: it finds that week's top 10, writes
// each one a players/{uid}/weekHistory/{weekId} doc carrying their place
// and credit reward (the app reads it and claims the credits once), and
// names 1st place the week's World Champion. Nothing needs "opening" for
// the new week — the board simply starts reading the new weekId's score
// docs, which fill up as people play.
//
// Ties break on uid for a deterministic, if arbitrary, order.

const admin = require('firebase-admin');
const { isoWeekId, currentWeekStartUtc, addDays } = require('./isoWeek');

const TOP_N = 10;

// Credits by finishing place (index 0 = 1st). Must match what the app
// tells players (release notes / league screen subtitle).
const PLACE_CREDITS = [1000, 500, 300, 100, 100, 100, 100, 100, 100, 100];

// The week's top N real players, highest first. Needs the collection-group
// index on scores (weekId ASC, bestScore DESC) — the same one the app's
// live board uses. Over-fetches so test accounts (debug builds stamp
// isTestAccount: true) and orphaned score docs can be skipped without
// leaving the board short.
async function weeklyTop(db, weekId) {
  const snap = await db.collectionGroup('scores')
    .where('weekId', '==', weekId)
    .orderBy('bestScore', 'desc')
    .limit(TOP_N + 40)
    .get();

  const rows = [];
  for (const doc of snap.docs) {
    const playerRef = doc.ref.parent.parent;
    if (!playerRef) continue;
    const score = doc.data().bestScore || 0;
    if (score <= 0) continue;
    // No profile doc is fine — players on older app versions never got
    // one unless they opened the Global tab; they're still paid.
    const player = await playerRef.get();
    if (player.exists && player.data().isTestAccount === true) continue;
    rows.push({ uid: playerRef.id, score });
  }
  rows.sort((a, b) => (b.score - a.score) || a.uid.localeCompare(b.uid));
  return rows.slice(0, TOP_N);
}

async function main() {
  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) throw new Error('FIREBASE_SERVICE_ACCOUNT env var is not set');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountRaw)) });
  const db = admin.firestore();

  const now = new Date();
  // Triggered Monday 00:00 UTC — the week that "just ended" is the one
  // whose Monday was 7 days ago.
  const justEndedWeekId = isoWeekId(addDays(currentWeekStartUtc(now), -7));
  const nextWeekId = isoWeekId(currentWeekStartUtc(now));

  console.log(`Rollover run at ${now.toISOString()} — closing ${justEndedWeekId}, opening ${nextWeekId}`);

  // ── Idempotency guard ────────────────────────────────────────────────
  const logRef = db.collection('leagueMeta').doc('rolloverLog').collection('weeks').doc(justEndedWeekId);
  const logSnap = await logRef.get();
  if (logSnap.exists && logSnap.data().status === 'completed') {
    console.log(`${justEndedWeekId} already rolled over — exiting.`);
    return;
  }
  await logRef.set({ status: 'in-progress', startedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });

  try {
    // ── 1. Pay last week's top 10 ───────────────────────────────────────
    const top = await weeklyTop(db, justEndedWeekId);
    console.log(`Top ${top.length} for ${justEndedWeekId}`);

    let totalCreditsAwarded = 0;
    const batch = db.batch();
    top.forEach((entry, i) => {
      const rank = i + 1;
      const isWinner = rank === 1;
      const creditsAwarded = PLACE_CREDITS[i];
      totalCreditsAwarded += creditsAwarded;

      const playerRef = db.collection('players').doc(entry.uid);
      batch.set(playerRef.collection('weekHistory').doc(justEndedWeekId), {
        score: entry.score,
        rank,
        outcome: 'top10',
        isWinner,
        isWorldChampion: isWinner,
        creditsAwarded,
      });
      if (isWinner) {
        batch.set(playerRef, {
          worldChampionCount: admin.firestore.FieldValue.increment(1),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      console.log(`#${rank} ${entry.uid} — ${entry.score} → ${creditsAwarded} credits`);
    });
    await batch.commit();

    // ── 2. Update the authoritative "current week" pointer ──────────────
    const nextWeekStart = currentWeekStartUtc(now);
    await db.collection('leagueMeta').doc('currentWeek').set({
      weekId: nextWeekId,
      weekStart: admin.firestore.Timestamp.fromDate(nextWeekStart),
      weekEnd: admin.firestore.Timestamp.fromDate(addDays(nextWeekStart, 7)),
    });

    await logRef.set({
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      playersPaid: top.length,
      totalCreditsAwarded,
      worldChampionUid: top.length > 0 ? top[0].uid : null,
    }, { merge: true });

    console.log(`Rollover complete: ${top.length} players paid, ${totalCreditsAwarded} credits awarded.`);
  } catch (err) {
    console.error('Rollover failed:', err);
    await logRef.set({
      status: 'failed',
      error: String((err && err.message) || err),
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
