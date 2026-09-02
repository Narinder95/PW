// Wires a real account into the seeded demo social graph, so the Friends page
// has something in it while you test.
//
//     node src/make_test_account.js              # newest account (usually yours)
//     node src/make_test_account.js --handle bob # a specific handle
//     node src/make_test_account.js --list       # just show recent accounts
//
// Why it targets the NEWEST account: the app has no login screen. It
// provisions an anonymous account on first launch, so the account you are
// looking at on the handset is simply the most recently created one. Open the
// app, then run this, then pull-to-refresh.
//
// Idempotent: re-running refreshes rather than duplicating.

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './db.js';
import { createSession } from './auth.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const dbPath = process.env.PW_DB_PATH ?? path.join(here, '..', 'data', 'pw.db');
const BASE = process.env.PW_BASE_URL ?? 'http://localhost:8080';

const args = process.argv.slice(2);
const listOnly = args.includes('--list');
const handleIndex = args.indexOf('--handle');
const wantedHandle = handleIndex >= 0 ? args[handleIndex + 1] : null;

const SEED_PASSWORD = 'password123';
const FRIENDS = ['alexr', 'taylorm', 'priyan'];
const REQUESTER = 'samk';
const STRANGER = 'jordanp';

const HABITS = [
  { name: 'Steps', icon: '👟', color: '#2E7D32', target: 10000, unit: 'steps' },
  { name: 'Water', icon: '💧', color: '#0097A7', target: 8, unit: 'cups' },
  { name: 'Exercise', icon: '💪', color: '#FF7043', target: 30, unit: 'min' },
  { name: 'Reading', icon: '📚', color: '#FFA726', target: 20, unit: 'min' },
];

async function api(method, p, { token, body } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  let res;
  try {
    res = await fetch(BASE + p, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch (err) {
    throw new Error(
      `Cannot reach ${BASE}. Start the server first:\n    cd backend && node src/index.js\n(${err.message})`
    );
  }
  const text = await res.text();
  let parsed = null;
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = text;
    }
  }
  return { status: res.status, body: parsed };
}

function dayOffset(n) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const db = openDb(dbPath);

// Every account seed.js creates, so none of them is ever mistaken for the
// handset's own account.
const SEEDED = new Set([...FRIENDS, REQUESTER, STRANGER, 'devong']);

function recentAccounts(limit = 10) {
  return db
    .prepare('SELECT id, username, name, is_anonymous, created_at FROM users ORDER BY created_at DESC, id DESC LIMIT ?')
    .all(limit);
}

if (listOnly) {
  console.log('Recent accounts (newest first):\n');
  for (const u of recentAccounts(60).filter((u) => !/^ztest\d+$/.test(u.username)).slice(0, 15)) {
    const tag = u.is_anonymous ? 'anonymous' : 'linked';
    const seeded = SEEDED.has(u.username) ? ' [seed]' : '';
    console.log(`  ${u.username.padEnd(22)} ${tag.padEnd(10)} ${u.created_at}${seeded}`);
  }
  process.exit(0);
}

// Pick the target account.
let target;
if (wantedHandle) {
  target = db.prepare('SELECT * FROM users WHERE username = ?').get(wantedHandle.toLowerCase());
  if (!target) {
    console.error(`No account with handle "${wantedHandle}". Try --list.`);
    process.exit(1);
  }
} else {
  // Newest non-seed, non-ephemeral account: the one the app just provisioned.
  // `ztest*` rows are throwaway accounts left by the Flutter live tests and
  // would otherwise shadow the real handset account.
  target = recentAccounts(60).find(
    (u) => !SEEDED.has(u.username) && !/^ztest\d+$/.test(u.username)
  );
  if (!target) {
    console.error(
      'No non-seed account found.\n' +
        'Open the app once so it provisions an account, then re-run this.\n' +
        'Or pass --handle <username>. Use --list to see what exists.'
    );
    process.exit(1);
  }
  target = db.prepare('SELECT * FROM users WHERE id = ?').get(target.id);
}

async function main() {
  const health = await api('GET', '/api/health');
  if (health.status !== 200) throw new Error(`Server unhealthy: ${health.status}`);

  // Mint a session for the target directly — we cannot log in as an anonymous
  // account (by design: it has no password), and this is a dev-only script.
  const token = createSession(db, target.id);
  const me = {
    id: target.id,
    username: target.username,
    token,
    get: (p, o = {}) => api('GET', p, { token, ...o }),
    post: (p, o = {}) => api('POST', p, { token, ...o }),
    del: (p, o = {}) => api('DELETE', p, { token, ...o }),
  };

  console.log(`Wiring up @${target.username} (${target.is_anonymous ? 'anonymous' : 'linked'})`);

  const seeds = {};
  for (const username of SEEDED) {
    const login = await api('POST', '/api/auth/login', {
      body: { usernameOrEmail: username, password: SEED_PASSWORD },
    });
    if (login.status !== 200) {
      throw new Error(`Seeded user "${username}" missing. Run first:\n    node src/seed.js`);
    }
    seeds[username] = { token: login.body.token, user: login.body.user };
  }

  // ---------------------------------------------------------------- habits
  const existing = (await me.get('/api/habits')).body.habits ?? [];
  const byName = new Map(existing.map((h) => [h.name, h]));

  for (const spec of HABITS) {
    let habit = byName.get(spec.name);
    if (!habit) {
      const res = await me.post('/api/habits', { body: spec });
      if (res.status !== 201) {
        console.warn(`  ! ${spec.name}: ${JSON.stringify(res.body)}`);
        continue;
      }
      habit = res.body.habit;
    }
    // 12 days of history with one deliberate gap, and today left incomplete
    // for two habits so there is something to actually do in the app.
    for (let d = 11; d >= 0; d--) {
      if (d === 5) continue;
      const inProgress = d === 0 && (spec.name === 'Steps' || spec.name === 'Exercise');
      await me.post(`/api/habits/${habit.id}/log`, {
        body: {
          progress: inProgress ? Math.floor(spec.target * 0.55) : spec.target,
          date: dayOffset(-d),
        },
      });
    }
  }
  console.log(`  habits: ${HABITS.length}, 12 days of history each`);

  // --------------------------------------------------------------- friends
  const already = new Set(((await me.get('/api/friends')).body.friends ?? []).map((f) => f.username));
  for (const username of FRIENDS) {
    if (already.has(username)) continue;
    const them = seeds[username];
    const sent = await me.post('/api/friend-requests', { body: { toUserId: them.user.id } });
    if (sent.status === 409) continue;
    const inbox = await api('GET', '/api/friend-requests', { token: them.token });
    const pending = (inbox.body.incoming ?? []).find((r) => r.fromUser.id === me.id);
    if (pending) {
      await api('POST', `/api/friend-requests/${pending.id}/accept`, { token: them.token });
    }
  }
  console.log(`  friends: ${FRIENDS.join(', ')}`);

  // ------------------------------------------------ a pending friend request
  const mine = await me.get('/api/friend-requests');
  if (!(mine.body.incoming ?? []).some((r) => r.fromUser.username === REQUESTER)) {
    await api('POST', '/api/friend-requests', {
      token: seeds[REQUESTER].token,
      body: { toUserId: me.id },
    });
  }
  console.log(`  incoming friend request from @${REQUESTER}`);

  // --------------------------------------------------------------- nudges
  for (const n of [
    { from: 'alexr', habitName: 'Exercise', icon: '💪', color: '#FF7043', type: 'nudge' },
    { from: 'taylorm', habitName: 'Steps', icon: '👟', color: '#2E7D32', type: 'cheer' },
  ]) {
    const res = await api('POST', '/api/nudges', {
      token: seeds[n.from].token,
      body: {
        toUserId: me.id,
        habitName: n.habitName,
        habitIcon: n.icon,
        habitColor: n.color,
        type: n.type,
      },
    });
    if (res.status !== 201 && res.status !== 429) {
      console.warn(`  ! nudge from ${n.from}: ${JSON.stringify(res.body)}`);
    }
  }
  console.log('  2 pending nudges (one nudge, one cheer)');

  // ------------------------------------------------------ friends' activity
  for (const username of FRIENDS) {
    const them = seeds[username];
    const theirHabits = (await api('GET', '/api/habits', { token: them.token })).body.habits ?? [];
    const todo = theirHabits.find((h) => !h.completedToday);
    if (todo) {
      await api('POST', `/api/habits/${todo.id}/log`, {
        token: them.token,
        body: { progress: todo.target },
      });
    }
  }

  // ------------------------------------------------------------------ report
  const friends = (await me.get('/api/friends')).body.friends ?? [];
  const habits = (await me.get('/api/habits')).body.habits ?? [];
  const unread = (await me.get('/api/notifications/unread-count')).body.count;
  const suggestions = (await me.get('/api/match/suggestions')).body.suggestions ?? [];

  console.log('\n' + '='.repeat(58));
  console.log(`  READY — @${target.username}`);
  console.log('='.repeat(58));
  console.log(`  habits            ${habits.length}`);
  for (const h of habits) {
    console.log(
      `    ${h.icon} ${h.name.padEnd(10)} ${String(h.progress).padStart(6)}/${h.target}` +
        `  streak ${h.streak}${h.completedToday ? '  done' : ''}`
    );
  }
  console.log(`  friends           ${friends.length}`);
  for (const f of friends) {
    console.log(
      `    ${f.name.padEnd(14)} streak ${String(f.streakDays).padStart(3)}  ${f.habitsCompleted}/${f.habitsTotal} today`
    );
  }
  console.log(`  unread notifs     ${unread}`);
  console.log(`  match suggestions ${suggestions.length}`);
  console.log('-'.repeat(58));
  console.log('  Pull to refresh in the app, then try:');
  console.log(`    - Friends tab: accept @${REQUESTER}'s request`);
  console.log('    - Accept the 2 nudges');
  console.log('    - Tap a friend -> Compare');
  console.log('    - Bell icon -> notification centre');
  console.log(`    - Add friend -> search "${STRANGER}"`);
  console.log('    - Profile -> "Save my account" to link an email/phone');
  console.log('='.repeat(58) + '\n');
}

main().catch((err) => {
  console.error('\n' + err.message + '\n');
  process.exit(1);
});
