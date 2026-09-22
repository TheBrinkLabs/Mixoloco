'use strict';

// Lightweight daily companion to rollover.js — assigns players who signed
// up mid-week (pendingJoin still true) into a Bronze room, so a new
// signup waits at most ~24h to see a real room instead of up to 6 days
// for the next Monday rollover. Prefers topping up an existing
// under-capacity room over spinning up a new one, so a small (or lone)
// day's cohort doesn't end up stuck alone with no one to play against
// — see foldIntoExistingRooms below. Deliberately does NOT touch scoring,
// promotion, or relegation — those stay exclusively on the weekly cadence
// in rollover.js.
//
// Ported from Capitle's own assignNewJoiners.js — identical shape, minus
// the "modes" subcollection cleanup during pruning (Mixoloco stores one
// score doc per player per week, not one per game mode per day, since
// there's only one game mode here).
//
// Naturally idempotent: a re-run just finds fewer (or zero) pendingJoin
// players, since this script flips pendingJoin to false as it assigns
// them — no completion-log guard needed like rollover.js has.

const admin = require('firebase-admin');
const { isoWeekId, currentWeekStartUtc } = require('./isoWeek');
const { assignRoomsForTier, MAX_SIZE } = require('./assignRooms');

// Debug builds stamp isTestAccount: true at signup (see
// LeagueRepository.ensurePlayerDocument) — dev/test devices, not real
// players. Purge anything still flagged isTestAccount once it's old
// enough that it's clearly not a live testing session anymore. Runs
// before the pendingJoin sweep below so a stale test account never gets
// swept into a fresh room first.
const TEST_ACCOUNT_MAX_AGE_HOURS = 72;

async function pruneStaleTestAccounts(db) {
  const cutoff = new Date(Date.now() - TEST_ACCOUNT_MAX_AGE_HOURS * 60 * 60 * 1000);
  const snap = await db.collection('players').where('isTestAccount', '==', true).get();

  let pruned = 0;
  for (const doc of snap.docs) {
    const data = doc.data();
    const createdAt = data.createdAt;
    if (!createdAt || createdAt.toDate() > cutoff) continue;

    const scoresSnap = await doc.ref.collection('scores').listDocuments();
    for (const weekDoc of scoresSnap) await weekDoc.delete();
    await doc.ref.delete();

    if (data.roomId) {
      await db.collection('leagueRooms').doc(data.roomId).update({
        memberUids: admin.firestore.FieldValue.arrayRemove(doc.id),
      });
    }
    pruned++;
  }
  console.log(`Pruned ${pruned} stale test account(s) (older than ${TEST_ACCOUNT_MAX_AGE_HOURS}h).`);
}

// Reinstall churn: a player who reinstalls (or clears app data) gets a
// fresh anonymous uid and a brand-new players/{uid} doc, orphaning the
// old one — it just sits there forever with no way to ever be reached
// again, quietly bloating the league (an extra body in the room, extra
// weight in size-based rebalancing) without ever playing again. The app
// stamps a per-device deviceId at signup specifically so this job can
// spot that pattern: multiple player docs sharing the same device.
// Deletion only ever happens here, server-side — see firestore.rules:
// players/{uid} delete is always false client-side.
async function pruneDuplicateDeviceAccounts(db) {
  const snap = await db.collection('players').get();

  const byDevice = new Map();
  for (const doc of snap.docs) {
    const deviceId = doc.data().deviceId;
    if (!deviceId) continue;
    if (!byDevice.has(deviceId)) byDevice.set(deviceId, []);
    byDevice.get(deviceId).push(doc);
  }

  let pruned = 0;
  for (const [deviceId, docs] of byDevice.entries()) {
    if (docs.length < 2) continue;

    // Newest createdAt wins (the currently-active install) — every other
    // doc sharing this device is a stale duplicate from an earlier
    // install. A missing createdAt sorts as oldest (epoch 0).
    docs.sort((a, b) => {
      const ta = a.data().createdAt?.toMillis() ?? 0;
      const tb = b.data().createdAt?.toMillis() ?? 0;
      return tb - ta;
    });
    const [keep, ...stale] = docs;
    console.log(`Device ${deviceId}: keeping ${keep.id}, pruning ${stale.length} older duplicate(s)`);

    for (const doc of stale) {
      const data = doc.data();
      const scoresSnap = await doc.ref.collection('scores').listDocuments();
      for (const weekDoc of scoresSnap) await weekDoc.delete();
      await doc.ref.delete();

      if (data.roomId) {
        // .update() throws if the room doc doesn't exist — a real
        // possibility here, not a should-never-happen case, and one bad
        // reference shouldn't take down the rest of this run.
        try {
          await db.collection('leagueRooms').doc(data.roomId).update({
            memberUids: admin.firestore.FieldValue.arrayRemove(doc.id),
          });
        } catch (err) {
          console.warn(`Could not remove ${doc.id} from room ${data.roomId} (may not exist): ${err.message}`);
        }
      }
      pruned++;
    }
  }
  console.log(`Pruned ${pruned} duplicate-device account(s).`);
}

// A lone (or small) pending cohort shouldn't be stuck by itself in a
// brand-new room with no one to play against — top up whatever Bronze
// rooms already exist this week before ever creating a new one. Fills
// the smallest/loneliest rooms first. Returns whichever uids couldn't be
// placed (no existing room had spare capacity), for the caller to bucket
// into fresh rooms as before.
async function foldIntoExistingRooms(db, weekId, uids) {
  const roomsSnap = await db.collection('leagueRooms')
    .where('tier', '==', 'bronze')
    .where('weekId', '==', weekId)
    .get();

  const candidates = roomsSnap.docs
    .map((d) => ({ ref: d.ref, size: (d.data().memberUids || []).length }))
    .filter((r) => r.size < MAX_SIZE)
    .sort((a, b) => a.size - b.size);

  let remaining = uids.slice();
  for (const room of candidates) {
    if (remaining.length === 0) break;
    const take = remaining.splice(0, MAX_SIZE - room.size);
    if (take.length === 0) continue;

    await room.ref.update({ memberUids: admin.firestore.FieldValue.arrayUnion(...take) });
    const batch = db.batch();
    for (const uid of take) {
      batch.set(db.collection('players').doc(uid), {
        tier: 'bronze', roomId: room.ref.id, pendingJoin: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
    console.log(`Folded ${take.length} player(s) into existing room ${room.ref.id} (was ${room.size})`);
  }
  return remaining;
}

async function main() {
  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) throw new Error('FIREBASE_SERVICE_ACCOUNT env var is not set');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountRaw)) });
  const db = admin.firestore();

  const now = new Date();
  const weekId = isoWeekId(currentWeekStartUtc(now));
  const dateKey = now.toISOString().slice(0, 10); // YYYY-MM-DD, UTC

  console.log(`Daily join run at ${now.toISOString()} — week ${weekId}, date ${dateKey}`);

  await pruneStaleTestAccounts(db);
  await pruneDuplicateDeviceAccounts(db);

  const pendingSnap = await db.collection('players').where('pendingJoin', '==', true).get();
  const allUids = pendingSnap.docs.map((d) => d.id);
  console.log(`${allUids.length} player(s) pending Bronze assignment`);

  if (allUids.length === 0) {
    console.log('Nothing to do.');
    return;
  }

  const uids = await foldIntoExistingRooms(db, weekId, allUids);
  if (uids.length === 0) {
    console.log('Daily join complete: everyone folded into an existing room, no new rooms needed.');
    return;
  }

  // Distinct seed from the weekly rollover's own room-numbering scheme
  // (bronze_{weekId}_{i}) so today's ad-hoc cohort rooms can never
  // collide with rooms the Monday rollover created for this same week.
  const rooms = assignRoomsForTier(uids, `${weekId}_daily_${dateKey}`);

  let roomsCreated = 0;
  for (let i = 0; i < rooms.length; i++) {
    const roomId = `bronze_${weekId}_daily_${dateKey}_${i}`;
    await db.collection('leagueRooms').doc(roomId).set({
      tier: 'bronze', weekId, memberUids: rooms[i],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    roomsCreated++;

    const batch = db.batch();
    for (const uid of rooms[i]) {
      batch.set(db.collection('players').doc(uid), {
        tier: 'bronze', roomId, pendingJoin: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
  }

  console.log(`Daily join complete: ${roomsCreated} room(s) created for ${uids.length} player(s).`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
