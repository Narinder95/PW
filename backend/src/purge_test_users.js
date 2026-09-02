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
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.PW_DB_PATH ?? path.join(here, '..', 'data', 'pw.db');
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

const db = openDb(dbPath);

const candidates = [];
for (const pattern of PATTERNS) {
  const rows = db
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
  process.exit(0);
}

console.log(`Found ${candidates.length} ephemeral test account(s).`);
if (dryRun) {
  for (const c of candidates.slice(0, 20)) console.log(`  ${c.username}`);
  if (candidates.length > 20) console.log(`  ... and ${candidates.length - 20} more`);
  console.log('\nDry run — nothing deleted. Re-run without --dry to remove them.');
  process.exit(0);
}

// Child rows first, then the user. Wrapped so a failure cannot half-delete.
const ids = candidates.map((c) => c.id);
const holes = ids.map(() => '?').join(',');

db.exec('BEGIN');
try {
  db.prepare(
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
    try {
      db.prepare(`${sql} (${holes})`).run(...ids);
    } catch (err) {
      // A table that does not exist in this schema version is not fatal.
      if (!/no such table/i.test(err.message)) throw err;
    }
  }

  // Relationship tables reference users from either side.
  const twoSided = [
    ['friendships', 'user_id', 'friend_id'],
    ['friend_requests', 'from_user', 'to_user'],
    ['nudges', 'from_user', 'to_user'],
    ['notifications', 'actor_id', null],
  ];
  for (const [table, colA, colB] of twoSided) {
    try {
      db.prepare(`DELETE FROM ${table} WHERE ${colA} IN (${holes})`).run(...ids);
      if (colB) db.prepare(`DELETE FROM ${table} WHERE ${colB} IN (${holes})`).run(...ids);
    } catch (err) {
      if (!/no such table|no such column/i.test(err.message)) throw err;
    }
  }

  db.prepare(`DELETE FROM users WHERE id IN (${holes})`).run(...ids);
  db.exec('COMMIT');
} catch (err) {
  db.exec('ROLLBACK');
  console.error('Purge failed, rolled back:', err.message);
  process.exit(1);
}

const left = db.prepare('SELECT COUNT(*) AS n FROM users').get().n;
console.log(`Deleted ${candidates.length}. ${left} user(s) remain.`);
