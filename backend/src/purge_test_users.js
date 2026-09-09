// Removes the throwaway accounts that `test/live_backend_test.dart` registers.
//
//     node src/purge_test_users.js          # delete them
//     node src/purge_test_users.js --dry    # just list them
//
// The live Flutter integration suite talks to a real running server, so every
// run leaves real rows behind. Left alone they pile up and pollute search
// results and match suggestions in the demo database.
//
// Only usernames matching the ephemeral test pattern are touched; the seeded
// demo accounts and the `test` account are never deleted.

import { openDb } from './db.js';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error('DATABASE_URL is not set. See backend/.env (gitignored) for local development.');
  process.exit(1);
}
const dryRun = process.argv.includes('--dry');

// `ztest<digits>` is the current prefix; `t<12 digits>` was the original one.
const PATTERNS = ['ztest%', 't__________%'];

/** Accounts that must survive no matter what. */
const PROTECTED = new Set([
  'alexr',
  'taylorm',
  'jordanp',
  'samk',
  'priyan',
  'devong',
  'test',
]);

const db = await openDb(databaseUrl);

const candidates = [];
for (const pattern of PATTERNS) {
  const rows = await db
    .prepare('SELECT id, username, created_at FROM users WHERE username LIKE ?')
    .all(pattern);
  for (const row of rows) {
    if (PROTECTED.has(row.username)) continue;
    // Guard the second pattern: only digits after the leading `t`.
    if (!/^ztest\d+$/.test(row.username) && !/^t\d+$/.test(row.username)) continue;
    if (!candidates.some((c) => c.id === row.id)) candidates.push(row);
  }
}

if (candidates.length === 0) {
  console.log('No ephemeral test accounts found. Nothing to do.');
  await db.close();
  process.exit(0);
}

console.log(`Found ${candidates.length} ephemeral test account(s).`);
if (dryRun) {
  for (const c of candidates.slice(0, 20)) console.log(`  ${c.username}`);
  if (candidates.length > 20) console.log(`  ... and ${candidates.length - 20} more`);
  console.log('\nDry run — nothing deleted. Re-run without --dry to remove them.');
  await db.close();
  process.exit(0);
}

// Child rows first, then the user. Wrapped so a failure cannot half-delete.
const ids = candidates.map((c) => c.id);
const holes = ids.map(() => '?').join(',');

// Postgres aborts an entire transaction on the first error in it - unlike
// the original SQLite version of this script, a per-statement try/catch
// inside the transaction cannot let it limp past a bad statement (every
// later statement would just fail with "current transaction is aborted").
// So this list must be exactly right, not defensively guessed at.
try {
  await db.withTransaction(async (tx) => {
    await tx.prepare(
      `DELETE FROM habit_logs WHERE habit_id IN (SELECT id FROM habits WHERE user_id IN (${holes}))`
    ).run(...ids);

    const perUser = [
      'DELETE FROM habits WHERE user_id IN',
      'DELETE FROM sessions WHERE user_id IN',
      'DELETE FROM notifications WHERE user_id IN',
      'DELETE FROM activities WHERE user_id IN',
      'DELETE FROM devices WHERE user_id IN',
      'DELETE FROM push_deliveries WHERE user_id IN',
    ];
    for (const sql of perUser) {
      await tx.prepare(`${sql} (${holes})`).run(...ids);
    }

    // Relationship tables reference users from either side.
    const twoSided = [
      ['friendships', 'user_id', 'friend_id'],
      ['friend_requests', 'from_user_id', 'to_user_id'],
      ['nudges', 'from_user_id', 'to_user_id'],
      ['notifications', 'actor_id', null],
    ];
    for (const [table, colA, colB] of twoSided) {
      await tx.prepare(`DELETE FROM ${table} WHERE ${colA} IN (${holes})`).run(...ids);
      if (colB) await tx.prepare(`DELETE FROM ${table} WHERE ${colB} IN (${holes})`).run(...ids);
    }

    await tx.prepare(`DELETE FROM users WHERE id IN (${holes})`).run(...ids);
  });
} catch (err) {
  console.error('Purge failed, rolled back:', err.message);
  await db.close();
  process.exit(1);
}

const left = await db.prepare('SELECT COUNT(*) AS n FROM users').get();
console.log(`Deleted ${candidates.length}. ${left.n} user(s) remain.`);
await db.close();
