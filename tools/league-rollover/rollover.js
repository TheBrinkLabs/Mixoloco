'use strict';

// Weekly Mixoloco league rollover — scores the week that just ended,
// promotes/relegates, opens next week's rooms, and awards league credits.
// Ported from Capitle's own tools/league-rollover/rollover.js (same
// weekly-cycle/room-bucketing/promotion-relegation shape), with three
// deliberate differences from that original, all per direct request:
//
//   1. Score is a single per-week BEST score (players/{uid}/scores/{weekId}
//      holds one `bestScore` field, written client-side via a
//      max-if-greater transaction — see league_repository.dart), not a
//      sum across several daily game-mode docs the way Capitle's trivia
//      format needs. There's only one game mode here.
//   2. Tiers "evolve" — Bronze never promotes anyone into Silver (and
//      Silver never promotes into Gold) until this week's crop of
//      promotable candidates would actually be enough, combined with
//      whoever's already there, to form one legitimate room in the tier
//      above (see TIER_GATE_MIN / tierGateOpen below). Capitle's own
//      boosted-promotion-fraction idea (promote a bigger slice while a
//      destination tier is thin) is kept for the *rate* once the gate is
//      open — this just adds a hard floor before it opens AT ALL.
//   3. Promotion and a room win each pay real credits (see TIER_REWARDS),
//      stamped onto the weekHistory doc the client already reads — pure
//      cosmetic in Capitle (tier badges only), not a currency there.
//
// No "streak" concept here (that's Capitle's daily-puzzle mechanic) —
// ties break on uid for a deterministic, if arbitrary, order.

const admin = require('firebase-admin');
const { isoWeekId, currentWeekStartUtc, addDays } = require('./isoWeek');
const { assignRoomsForTier, MIN_SIZE, TARGET_SIZE } = require('./assignRooms');

const TIERS = ['bronze', 'silver', 'gold'];

// A player who hasn't submitted a single score in this long doesn't get
// carried into a new room next week — cleans up reinstall "ghost"
// identities (an orphaned anonymous UID superseded by a fresh one stops
// submitting scores forever the moment that happens) as well as
// genuinely inactive players. Two weekly cycles' worth of grace.
const INACTIVITY_DAYS = 14;

function isInactive(playerData, now) {
  const reference = playerData.lastActiveAt || playerData.createdAt;
  if (!reference) return false; // defensive — shouldn't happen, never prune on missing data
  const ageMs = now.getTime() - reference.toDate().getTime();
  return ageMs > INACTIVITY_DAYS * 24 * 60 * 60 * 1000;
}

function tierAbove(tier) {
  const i = TIERS.indexOf(tier);
  return i < TIERS.length - 1 ? TIERS[i + 1] : null;
}
function tierBelow(tier) {
  const i = TIERS.indexOf(tier);
  return i > 0 ? TIERS[i - 1] : null;
}

// Promotion/relegation zone size scales with room size instead of a flat
// 3 — a flat 3 in a small room means the whole room moves at once, which
// isn't a meaningful result when there's nobody left to have actually
// beaten. Below 5 players, nobody moves at all; scales up to the
// original flat-3 behaviour once a room reaches a normal size (rooms
// target 7-14 members — see assignRooms.js).
function zoneSize(roomSize) {
  return Math.min(3, Math.floor(roomSize * 0.2));
}

// Same boosted-promotion-rate idea as Capitle: promote a bigger slice
// while the destination tier is still thin, tapering to the standard 20%
// once it's healthy (TARGET_SIZE members). This only controls the RATE —
// see tierGateOpen below for the hard floor on whether promotion happens
// into a tier AT ALL this week.
const PROMOTION_BOOST_FRACTION = 0.4;
const PROMOTION_BASE_FRACTION = 0.2; // matches zoneSize's rate
const PROMOTION_FULL_THRESHOLD = TARGET_SIZE;

function boostedPromotionFraction(currentDestTierCount) {
  const t = Math.min(1, currentDestTierCount / PROMOTION_FULL_THRESHOLD);
  return PROMOTION_BOOST_FRACTION - (PROMOTION_BOOST_FRACTION - PROMOTION_BASE_FRACTION) * t;
}

function boostedPromotionCount(roomSize, currentDestTierCount) {
  return Math.floor(roomSize * boostedPromotionFraction(currentDestTierCount));
}

// Gold is the top tier — no competition-integrity cost to a promotion
// into it being "too easy" (nothing above it to over-dilute), so it runs
// on looser room bounds than the standard target-10/7-14 used everywhere
// else: consolidate into fewer, livelier rooms instead of spreading a
// small top-tier population thin.
const GOLD_ROOM_BOUNDS = { target: 15, min: 7, max: 17 };

// ── Evolving tiers ──────────────────────────────────────────────────
// The whole point of "evolving" leagues: Silver doesn't exist as a real
// competition until there's enough of a population to fill even one
// legitimate room, and same again for Gold. Each destination tier's own
// MIN room size (see assignRooms.js / GOLD_ROOM_BOUNDS) IS that bar —
// no separately-tuned constant, so it can never drift out of sync with
// what assignRoomsForTier would actually accept as a real room.
function tierGateMin(destTier) {
  return destTier === 'gold' ? GOLD_ROOM_BOUNDS.min : MIN_SIZE;
}

// currentDestCount is this destination tier's population BEFORE this
// run's promotions; candidatePoolSize is how many players Would be
// promoted into it this run if the gate were already open (summed across
// every source room, at the normal boosted rate). If those two together
// still wouldn't clear the bar, promotion into this tier is withheld
// entirely for every room this week — the top scorers stay in their
// current tier and get another shot next week, by which point more
// signups/candidates may have accumulated. Re-checked every week (not
// just once at first-ever opening), so a tier that's cratered back below
// its own minimum via relegation/inactivity pruning re-gates the same way
// until it recovers.
function tierGateOpen(destTier, currentDestCount, candidatePoolSize) {
  return currentDestCount + candidatePoolSize >= tierGateMin(destTier);
}

// ── Credit rewards ──────────────────────────────────────────────────
// Bronze/Silver: promoted this week, or won your room outright (rank 1
// with a nonzero score — a strict superset of "promoted" whenever the
// gate above is open, since rank 1 is always inside the promote zone
// once promoteCount >= 1; a room win still pays out even when the gate
// is closed and nobody got promoted this week at all). Gold: no
// promotion to be had (top tier) — only the win reward applies.
const TIER_REWARDS = {
  bronze: { promoted: 150, win: 200 },
  silver: { promoted: 300, win: 400 },
  gold: { promoted: 0, win: 750 },
};

function creditsFor(tier, isWinner, isPromoted) {
  if (isWinner) return TIER_REWARDS[tier].win;
  if (isPromoted) return TIER_REWARDS[tier].promoted;
  return 0;
}

async function main() {
  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) throw new Error('FIREBASE_SERVICE_ACCOUNT env var is not set');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountRaw)) });
  const db = admin.firestore();

  const now = new Date();
  // Triggered Monday 00:00 UTC — the week that "just ended" is the one
  // whose Monday was 7 days ago.
  const justEndedWeekStart = addDays(currentWeekStartUtc(now), -7);
  const justEndedWeekId = isoWeekId(justEndedWeekStart);
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
    // ── 1. Score every room live during the week that just ended ───────
    const roomsSnap = await db.collection('leagueRooms').where('weekId', '==', justEndedWeekId).get();
    console.log(`Found ${roomsSnap.size} rooms for ${justEndedWeekId}`);

    const currentSilverCount = roomsSnap.docs
      .filter((d) => d.data().tier === 'silver')
      .reduce((sum, d) => sum + (d.data().memberUids || []).length, 0);
    const currentGoldCount = roomsSnap.docs
      .filter((d) => d.data().tier === 'gold')
      .reduce((sum, d) => sum + (d.data().memberUids || []).length, 0);

    // ── Pass 1: score every room, compute each one's RAW promote count
    // (the boosted-rate count, ignoring the tier gate for now) ─────────
    const roomResults = [];
    for (const roomDoc of roomsSnap.docs) {
      const room = roomDoc.data();
      const tier = room.tier;
      const memberUids = room.memberUids || [];

      const scored = await Promise.all(memberUids.map(async (uid) => {
        const scoreDoc = await db.collection('players').doc(uid)
          .collection('scores').doc(justEndedWeekId).get();
        const score = scoreDoc.exists ? (scoreDoc.data().bestScore || 0) : 0;

        const playerSnap = await db.collection('players').doc(uid).get();
        const exists = playerSnap.exists;
        const inactive = exists && isInactive(playerSnap.data(), now);
        return { uid, score, exists, inactive };
      }));

      scored.sort((a, b) => (b.score - a.score) || a.uid.localeCompare(b.uid));

      const destTier = tierAbove(tier);
      const rawPromoteCount = !destTier ? 0
        : tier === 'bronze' ? boostedPromotionCount(scored.length, currentSilverCount)
        : boostedPromotionCount(scored.length, currentGoldCount);
      const scoredCount = scored.filter((e) => e.score > 0).length;
      const cappedRawPromoteCount = Math.min(rawPromoteCount, scoredCount);

      roomResults.push({ roomDoc, tier, destTier, scored, cappedRawPromoteCount });
    }

    // ── Tier gate: does this week's combined candidate pool (existing
    // destination population + everyone who'd be promoted at the normal
    // rate) actually clear that destination tier's own minimum room
    // size? If not, withhold promotion into it entirely this run. ──────
    const candidatePoolFor = (destTier) => roomResults
      .filter((r) => r.destTier === destTier)
      .reduce((sum, r) => sum + r.cappedRawPromoteCount, 0);

    const silverGateOpen = tierGateOpen('silver', currentSilverCount, candidatePoolFor('silver'));
    const goldGateOpen = tierGateOpen('gold', currentGoldCount, candidatePoolFor('gold'));
    console.log(`Silver gate: ${silverGateOpen ? 'OPEN' : 'closed'} (${currentSilverCount} existing + ${candidatePoolFor('silver')} candidate(s), needs ${tierGateMin('silver')})`);
    console.log(`Gold gate: ${goldGateOpen ? 'OPEN' : 'closed'} (${currentGoldCount} existing + ${candidatePoolFor('gold')} candidate(s), needs ${tierGateMin('gold')})`);

    /** @type {Record<string, string[]>} incoming pool per NEXT tier */
    const incomingPools = { bronze: [], silver: [], gold: [] };
    let playersProcessed = 0;
    let totalCreditsAwarded = 0;

    // Rank-1 finisher from every top-tier (Gold) room this week — the
    // single best of these becomes the week's World Champion.
    const topTierCandidates = [];

    for (const { roomDoc, tier, destTier, scored, cappedRawPromoteCount } of roomResults) {
      const gateOpenForThisPromotion = destTier === 'silver' ? silverGateOpen : destTier === 'gold' ? goldGateOpen : false;
      const promoteCount = destTier && gateOpenForThisPromotion ? cappedRawPromoteCount : 0;
      const relegateCount = tierBelow(tier) ? Math.min(zoneSize(scored.length), Math.max(0, scored.length - promoteCount)) : 0;

      if (!destTier && scored.length > 0 && scored[0].exists && !scored[0].inactive && scored[0].score > 0) {
        topTierCandidates.push({ ...scored[0], roomId: roomDoc.id });
      }

      const batch = db.batch();
      let prunedThisRoom = 0;
      scored.forEach((entry, i) => {
        if (!entry.exists) return;

        const isPromoted = i < promoteCount;
        const isRelegated = i >= scored.length - relegateCount;
        const isWinner = i === 0 && entry.score > 0;
        const outcome = isPromoted ? 'promoted' : isRelegated ? 'relegated' : 'stayed';
        const nextTier = isPromoted ? destTier : isRelegated ? tierBelow(tier) : tier;
        const creditsAwarded = creditsFor(tier, isWinner, isPromoted);
        totalCreditsAwarded += creditsAwarded;

        const historyRef = db.collection('players').doc(entry.uid)
          .collection('weekHistory').doc(justEndedWeekId);
        batch.set(historyRef, {
          score: entry.score,
          rank: i + 1,
          tier,
          roomId: roomDoc.id,
          roomSize: scored.length,
          outcome,
          isWinner,
          creditsAwarded,
        });

        if (entry.inactive) {
          // Gone quiet for INACTIVITY_DAYS — don't carry them into a new
          // room. pendingJoin stays false (not true) so this same run's
          // step 2 below (and assignNewJoiners.js) don't immediately
          // sweep them back into a fresh room, undoing the prune. The
          // app flips pendingJoin back to true itself the next time they
          // actually submit a score — see LeagueRepository.
          batch.set(db.collection('players').doc(entry.uid), {
            tier: 'bronze', roomId: null, pendingJoin: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
          prunedThisRoom++;
        } else {
          incomingPools[nextTier].push(entry.uid);
        }
        playersProcessed++;
      });
      if (prunedThisRoom > 0) console.log(`${roomDoc.id}: pruned ${prunedThisRoom} inactive player(s)`);
      await batch.commit();
    }

    // ── World Champion: best rank-1 finisher across every Gold room ─────
    let worldChampionUid = null;
    if (topTierCandidates.length > 0) {
      topTierCandidates.sort((a, b) => (b.score - a.score) || a.uid.localeCompare(b.uid));
      const champion = topTierCandidates[0];
      worldChampionUid = champion.uid;

      await db.collection('players').doc(champion.uid)
        .collection('weekHistory').doc(justEndedWeekId)
        .set({ isWorldChampion: true }, { merge: true });
      await db.collection('players').doc(champion.uid).set({
        worldChampionCount: admin.firestore.FieldValue.increment(1),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      console.log(`World Champion for ${justEndedWeekId}: ${champion.uid} (score ${champion.score}, room ${champion.roomId})`);
    }

    // ── 2. New entrants join Bronze only ────────────────────────────────
    const pendingSnap = await db.collection('players').where('pendingJoin', '==', true).get();
    pendingSnap.forEach((doc) => incomingPools.bronze.push(doc.id));
    console.log(`${pendingSnap.size} new entrants joining Bronze`);

    // ── 3. Assign new rooms per tier ────────────────────────────────────
    let roomsCreated = 0;
    for (const tier of TIERS) {
      const pool = incomingPools[tier];
      const rooms = assignRoomsForTier(pool, nextWeekId, tier === 'gold' ? GOLD_ROOM_BOUNDS : undefined);
      for (let i = 0; i < rooms.length; i++) {
        const roomId = `${tier}_${nextWeekId}_${i}`;
        await db.collection('leagueRooms').doc(roomId).set({
          tier, weekId: nextWeekId, memberUids: rooms[i],
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        roomsCreated++;

        // Firestore batch writes cap at 500 — chunk defensively even
        // though a single room (max 19 members) never comes close.
        for (let c = 0; c < rooms[i].length; c += 450) {
          const chunk = rooms[i].slice(c, c + 450);
          const batch = db.batch();
          for (const uid of chunk) {
            batch.set(db.collection('players').doc(uid), {
              tier, roomId, pendingJoin: false,
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
          }
          await batch.commit();
        }
      }
      console.log(`${tier}: ${pool.length} players -> ${rooms.length} room(s)`);
    }

    // ── 4. Update the authoritative "current week" pointer ──────────────
    const nextWeekStart = currentWeekStartUtc(now);
    const nextWeekEnd = addDays(nextWeekStart, 7);
    await db.collection('leagueMeta').doc('currentWeek').set({
      weekId: nextWeekId,
      weekStart: admin.firestore.Timestamp.fromDate(nextWeekStart),
      weekEnd: admin.firestore.Timestamp.fromDate(nextWeekEnd),
    });

    await logRef.set({
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      roomsCreated,
      playersProcessed,
      totalCreditsAwarded,
      worldChampionUid,
    }, { merge: true });

    console.log(`Rollover complete: ${roomsCreated} rooms created, ${playersProcessed} players processed, ${totalCreditsAwarded} credits awarded.`);
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
