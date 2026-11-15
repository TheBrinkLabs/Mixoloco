'use strict';

// Daily league housekeeping (league-daily-join.yml). The league used to
// have rooms that mid-week signups were placed into here — it's now one
// global weekly top 10 (see rollover.js), so there's nothing to assign
// any more and the file name is historical. What's left is clean-up,
// so dead accounts never take a place on the board:
//
//   • stale debug/test accounts are deleted;
//   • duplicate accounts left behind by a reinstall on the same device
//     are deleted (only the newest one is kept).
//
// Naturally idempotent — a re-run just finds nothing left to delete.

const admin = require('firebase-admin');

// Debug builds stamp isTestAccount: true at signup (see
// LeagueRepository.ensurePlayerDocument) — dev/test devices, not real
// players. Purge anything still flagged isTestAccount once it's old
// enough that it's clearly not a live testing session anymore.
const TEST_ACCOUNT_MAX_AGE_HOURS = 72;

async function deletePlayer(doc) {
  const scores = await doc.ref.collection('scores').listDocuments();
  for (const weekDoc of scores) await weekDoc.delete();
  await doc.ref.delete();
}

async function pruneStaleTestAccounts(db) {
  const cutoff = new Date(Date.now() - TEST_ACCOUNT_MAX_AGE_HOURS * 60 * 60 * 1000);
  const snap = await db.collection('players').where('isTestAccount', '==', true).get();

  let pruned = 0;
  for (const doc of snap.docs) {
    const createdAt = doc.data().createdAt;
    if (!createdAt || createdAt.toDate() > cutoff) continue;
    await deletePlayer(doc);
    pruned++;
  }
  console.log(`Pruned ${pruned} stale test account(s) (older than ${TEST_ACCOUNT_MAX_AGE_HOURS}h).`);
}

// Reinstall churn: a player who reinstalls (or clears app data) gets a
// fresh anonymous uid and a brand-new players/{uid} doc, orphaning the
// old one. The app stamps a per-device deviceId at signup specifically
// so this job can spot that pattern: multiple player docs sharing the
// same device. Deletion only ever happens here, server-side — see
// firestore.rules: players/{uid} delete is always false client-side.
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

    // Newest createdAt wins (the currently-active install). A missing
    // createdAt sorts as oldest (epoch 0).
    docs.sort((a, b) => {
      const ta = a.data().createdAt?.toMillis() ?? 0;
      const tb = b.data().createdAt?.toMillis() ?? 0;
      return tb - ta;
    });
    const [keep, ...stale] = docs;
    console.log(`Device ${deviceId}: keeping ${keep.id}, pruning ${stale.length} older duplicate(s)`);
    for (const doc of stale) {
      await deletePlayer(doc);
      pruned++;
    }
  }
  console.log(`Pruned ${pruned} duplicate-device account(s).`);
}

async function main() {
  const serviceAccountRaw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!serviceAccountRaw) throw new Error('FIREBASE_SERVICE_ACCOUNT env var is not set');
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(serviceAccountRaw)) });
  const db = admin.firestore();

  console.log(`Daily league clean-up at ${new Date().toISOString()}`);
  await pruneStaleTestAccounts(db);
  await pruneDuplicateDeviceAccounts(db);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
