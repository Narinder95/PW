// Deterministic, idempotent DEV/TEST fixture data.
//
//   node src/seed.js            seeds backend/data/pw.db
//   node src/seed.js --db :memory:
//
// This is BACKEND fixture data only - the Flutter app must ship with none of it.
// There is no Math.random() here (or anywhere in src/): every "random-looking"
// value comes from an FNV-1a hash of a stable key, so re-running produces the
// exact same database.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from './db.js';
import { createUser } from './auth.js';
import { addDays, todayISO } from './domain.js';
import { createNotification } from './notifications.js';

export const DEMO_PASSWORD = 'password123';
export const PRIMARY_DEMO = 'alexr';

/** FNV-1a. Deterministic pseudo-randomness from a stable string key. */
function h32(str) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

const USERS = [
  { id: 'u_seed_alex',   username: 'alexr',   name: 'Alex Rivera',  email: 'alex@pw.app',   color: '#A855F7', ageDays: 92 },
  { id: 'u_seed_taylor', username: 'taylorm', name: 'Taylor Mills', email: 'taylor@pw.app', color: '#FB923C', ageDays: 140 },
  { id: 'u_seed_jordan', username: 'jordanp', name: 'Jordan Park',  email: 'jordan@pw.app', color: '#2DD4BF', ageDays: 75 },
  { id: 'u_seed_sam',    username: 'samk',    name: 'Sam Keller',   email: 'sam@pw.app',    color: '#4ADE80', ageDays: 40 },
  { id: 'u_seed_priya',  username: 'priyan',  name: 'Priya Nair',   email: 'priya@pw.app',  color: '#60A5FA', ageDays: 110 },
  { id: 'u_seed_devon',  username: 'devong',  name: 'Devon Grant',  email: 'devon@pw.app',  color: '#F472B6', ageDays: 3 },
];

// Habit sets. Order matters: index 0 is the "anchor" habit that is deliberately
// left incomplete on a non-streak day, which is what keeps the streaks exact.
const HABITS = {
  alexr: [
    { key: 'steps',    name: 'Steps',    icon: 'R', color: '#2E7D32', target: 10000, unit: 'steps' },
    { key: 'water',    name: 'Water',    icon: 'D', color: '#2DD4BF', target: 8,     unit: 'glasses' },
    { key: 'read',     name: 'Read',     icon: 'B', color: '#F59E0B', target: 20,    unit: 'pages' },
    { key: 'meditate', name: 'Meditate', icon: 'M', color: '#A855F7', target: 10,    unit: 'min' },
  ],
  taylorm: [
    { key: 'steps',   name: 'Steps',   icon: 'R', color: '#2E7D32', target: 8000, unit: 'steps' },
    { key: 'water',   name: 'Water',   icon: 'D', color: '#2DD4BF', target: 8,    unit: 'glasses' },
    { key: 'run',     name: '5k Run',  icon: 'T', color: '#FB923C', target: 5,    unit: 'km' },
    { key: 'read',    name: 'Read',    icon: 'B', color: '#F59E0B', target: 30,   unit: 'pages' },
    { key: 'sleep',   name: 'Sleep',   icon: 'S', color: '#818CF8', target: 8,    unit: 'h' },
    { key: 'stretch', name: 'Stretch', icon: 'Y', color: '#F472B6', target: 15,   unit: 'min' },
  ],
  jordanp: [
    { key: 'steps',    name: 'Steps',    icon: 'R', color: '#2E7D32', target: 12000, unit: 'steps' },
    { key: 'meditate', name: 'Meditate', icon: 'M', color: '#A855F7', target: 15,    unit: 'min' },
    { key: 'journal',  name: 'Journal',  icon: 'J', color: '#60A5FA', target: 1,     unit: 'entry' },
  ],
  samk: [
    { key: 'water',   name: 'Water',   icon: 'D', color: '#2DD4BF', target: 6,  unit: 'glasses' },
    { key: 'pushups', name: 'Pushups', icon: 'P', color: '#F87171', target: 50, unit: 'reps' },
    { key: 'read',    name: 'Read',    icon: 'B', color: '#F59E0B', target: 15, unit: 'pages' },
  ],
  priyan: [
    { key: 'steps', name: 'Steps', icon: 'R', color: '#2E7D32', target: 9000, unit: 'steps' },
    { key: 'water', name: 'Water', icon: 'D', color: '#2DD4BF', target: 8,    unit: 'glasses' },
    { key: 'yoga',  name: 'Yoga',  icon: 'Y', color: '#34D399', target: 30,   unit: 'min' },
    { key: 'read',  name: 'Read',  icon: 'B', color: '#F59E0B', target: 25,   unit: 'pages' },
  ],
  devong: [], // deliberately empty: exercises habitsTotal 0 / streak 0
};

// dayOffset 0 = today. Returns true when EVERY habit is completed that day,
// which is exactly what drives streakDays.
const FULLY_COMPLETE = {
  // today still in progress -> streak counts back from yesterday
  alexr:   (d) => d >= 1 && d <= 9,
  taylorm: (d) => d >= 1 && d <= 22,
  jordanp: (d) => d <= 4,          // includes today -> streak 5
  samk:    (d) => d >= 1 && d <= 2,
  priyan:  (d) => d <= 13,         // includes today -> streak 14
  devong:  () => false,
};

const LOG_DAYS = 32;

const FRIENDSHIPS = [
  ['u_seed_alex', 'u_seed_taylor'],
  ['u_seed_alex', 'u_seed_jordan'],
  ['u_seed_alex', 'u_seed_priya'],
  ['u_seed_taylor', 'u_seed_jordan'],
  ['u_seed_taylor', 'u_seed_priya'],
  ['u_seed_jordan', 'u_seed_sam'], // gives Sam a mutual friend with Alex
];

function isoAt(date, hour, minute) {
  const hh = String(hour).padStart(2, '0');
  const mm = String(minute).padStart(2, '0');
  return `${date}T${hh}:${mm}:00.000Z`;
}

export function seed(db, { log = () => {} } = {}) {
  const today = todayISO();
  const ctx = { db, hub: null, push: null, logger: console };

  // --- reset -------------------------------------------------------------
  // Deleting the seeded users cascades to their habits, logs, activities,
  // friendships, requests, nudges, notifications and devices, which is what
  // makes re-running this script produce an identical database.
  const del = db.prepare('DELETE FROM users WHERE id = ?');
  for (const u of USERS) del.run(u.id);

  // --- users -------------------------------------------------------------
  const byUsername = new Map();
  for (const u of USERS) {
    const row = createUser(db, {
      id: u.id,
      username: u.username,
      name: u.name,
      email: u.email,
      password: DEMO_PASSWORD,
      avatarColor: u.color,
      createdAt: `${addDays(today, -u.ageDays)}T09:00:00.000Z`,
    });
    db.prepare('UPDATE users SET last_active_at = ? WHERE id = ?')
      .run(isoAt(addDays(today, u.username === 'devong' ? -2 : 0), 8, 15), row.id);
    byUsername.set(u.username, row);
  }

  // --- habits ------------------------------------------------------------
  const habitRows = [];
  const insertHabit = db.prepare(
    'INSERT INTO habits (id, user_id, name, icon, color, target, unit, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
  );
  for (const u of USERS) {
    const defs = HABITS[u.username] ?? [];
    defs.forEach((h, index) => {
      const id = `h_seed_${u.username}_${h.key}`;
      const createdAt = `${addDays(today, -Math.min(u.ageDays, LOG_DAYS + 5))}T09:00:00.000Z`;
      insertHabit.run(id, u.id, h.name, h.icon, h.color, h.target, h.unit, createdAt);
      habitRows.push({ ...h, id, index, userId: u.id, username: u.username });
    });
  }

  // --- habit logs --------------------------------------------------------
  const insertLog = db.prepare(
    'INSERT INTO habit_logs (id, habit_id, user_id, date, progress, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
  );
  const completions = []; // {habit, date, progress} for every completed habit-day

  for (const habit of habitRows) {
    const rule = FULLY_COMPLETE[habit.username];
    for (let d = LOG_DAYS - 1; d >= 0; d--) {
      const date = addDays(today, -d);
      const seedKey = `${habit.id}:${date}`;
      const noise = h32(seedKey);

      let progress;
      if (rule(d)) {
        // Complete: land on or just above target.
        progress = habit.target + (noise % 7 === 0 ? Math.max(1, Math.round(habit.target * 0.04)) : 0);
      } else if (habit.index === 0) {
        // The anchor habit is always short on a non-streak day, so the day
        // cannot accidentally count as complete.
        progress = Math.floor(habit.target * ((noise % 85) / 100));
      } else if (noise % 100 < 40) {
        progress = habit.target;
      } else {
        progress = Math.floor(habit.target * ((noise % 90) / 100));
      }

      insertLog.run(`hl_seed_${habit.id}_${date}`, habit.id, habit.userId, date, progress, isoAt(date, 20, 0));
      if (progress >= habit.target) completions.push({ habit, date, progress, offset: d });
    }
  }

  // --- friendships -------------------------------------------------------
  const insertFriendship = db.prepare(
    'INSERT INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING'
  );
  for (const [a, b] of FRIENDSHIPS) {
    const at = `${addDays(today, -30)}T12:00:00.000Z`;
    insertFriendship.run(a, b, at);
    insertFriendship.run(b, a, at);
  }

  // --- activity feed -----------------------------------------------------
  // Recent completions become activity rows, newest last.
  const insertActivity = db.prepare(
    `INSERT INTO activities (id, user_id, habit_id, habit_name, habit_icon, habit_color, completion, date, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
  );
  const recent = completions
    .filter((c) => c.offset <= 2)
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.habit.id.localeCompare(b.habit.id)));
  for (const c of recent) {
    const hour = 7 + (h32(`t${c.habit.id}${c.date}`) % 12);
    const minute = h32(`m${c.habit.id}${c.date}`) % 60;
    insertActivity.run(
      `a_seed_${c.habit.id}_${c.date}`,
      c.habit.userId,
      c.habit.id,
      c.habit.name,
      c.habit.icon,
      c.habit.color,
      c.habit.unit ? `${c.progress}/${c.habit.target} ${c.habit.unit}` : `${c.progress}/${c.habit.target}`,
      c.date,
      isoAt(c.date, hour, minute)
    );
  }

  // --- friend requests ---------------------------------------------------
  const alex = byUsername.get('alexr');
  const devon = byUsername.get('devong');
  const taylor = byUsername.get('taylorm');
  const jordan = byUsername.get('jordanp');
  const priya = byUsername.get('priyan');

  const requestId = 'fr_seed_devon_alex';
  const requestAt = isoAt(today, 7, 40);
  db.prepare(
    "INSERT INTO friend_requests (id, from_user_id, to_user_id, status, created_at, responded_at) VALUES (?, ?, ?, 'pending', ?, NULL)"
  ).run(requestId, devon.id, alex.id, requestAt);
  createNotification(ctx, {
    id: 'nt_seed_request',
    userId: alex.id,
    type: 'friend_request',
    title: `${devon.name} sent you a friend request`,
    body: `${devon.name} (@${devon.username}) wants to be friends`,
    actorId: devon.id,
    actorName: devon.name,
    avatarColor: devon.avatar_color,
    refType: 'friend_request',
    refId: requestId,
  });

  // --- nudges ------------------------------------------------------------
  const insertNudge = db.prepare(
    `INSERT INTO nudges (id, type, from_user_id, to_user_id, habit_id, habit_name, habit_icon, habit_color,
                         message, status, created_at, accepted_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL)`
  );

  insertNudge.run(
    'n_seed_taylor_alex', 'nudge', taylor.id, alex.id, 'h_seed_alexr_meditate',
    'Meditate', 'M', '#A855F7', null, isoAt(today, 8, 5)
  );
  createNotification(ctx, {
    id: 'nt_seed_nudge',
    userId: alex.id,
    type: 'nudge',
    title: `${taylor.name} nudged you`,
    body: `${taylor.name} nudged you to Meditate`,
    actorId: taylor.id,
    actorName: taylor.name,
    avatarColor: taylor.avatar_color,
    icon: 'M',
    color: '#A855F7',
    refType: 'nudge',
    refId: 'n_seed_taylor_alex',
  });

  insertNudge.run(
    'n_seed_priya_alex', 'cheer', priya.id, alex.id, 'h_seed_alexr_steps',
    'Steps', 'R', '#2E7D32', 'Nine days straight - keep going!', isoAt(today, 8, 30)
  );
  createNotification(ctx, {
    id: 'nt_seed_cheer',
    userId: alex.id,
    type: 'cheer',
    title: `${priya.name} cheered you on`,
    body: 'Nine days straight - keep going!',
    actorId: priya.id,
    actorName: priya.name,
    avatarColor: priya.avatar_color,
    icon: 'R',
    color: '#2E7D32',
    refType: 'nudge',
    refId: 'n_seed_priya_alex',
  });

  // One outgoing nudge so Alex's "sent" list is not empty.
  insertNudge.run(
    'n_seed_alex_jordan', 'nudge', alex.id, jordan.id, 'h_seed_jordanp_journal',
    'Journal', 'J', '#60A5FA', 'Your turn!', isoAt(today, 9, 0)
  );
  createNotification(ctx, {
    id: 'nt_seed_nudge_out',
    userId: jordan.id,
    type: 'nudge',
    title: `${alex.name} nudged you`,
    body: 'Your turn!',
    actorId: alex.id,
    actorName: alex.name,
    avatarColor: alex.avatar_color,
    icon: 'J',
    color: '#60A5FA',
    refType: 'nudge',
    refId: 'n_seed_alex_jordan',
  });

  // --- friend activity + milestone notifications for Alex ----------------
  const alexFriendIds = new Set(
    db.prepare('SELECT friend_id FROM friendships WHERE user_id = ?').all(alex.id).map((r) => r.friend_id)
  );
  const todaysFriendActivity = db
    .prepare('SELECT * FROM activities WHERE date = ? ORDER BY created_at DESC')
    .all(today)
    .filter((a) => alexFriendIds.has(a.user_id))
    .slice(0, 4);

  todaysFriendActivity.forEach((a, i) => {
    const actor = db.prepare('SELECT * FROM users WHERE id = ?').get(a.user_id);
    createNotification(ctx, {
      id: `nt_seed_activity_${i}`,
      userId: alex.id,
      type: 'friend_activity',
      title: `${actor.name} completed ${a.habit_name}`,
      body: `${actor.name} finished ${a.completion}`,
      actorId: actor.id,
      actorName: actor.name,
      avatarColor: actor.avatar_color,
      icon: a.habit_icon,
      color: a.habit_color,
      refType: 'activity',
      refId: a.id,
    });
  });

  createNotification(ctx, {
    id: 'nt_seed_milestone',
    userId: alex.id,
    type: 'streak_milestone',
    title: 'Nine day streak',
    body: 'You have completed every habit nine days running.',
    refType: null,
    refId: null,
  });

  // A couple already read, so unreadCount is not simply "everything".
  db.prepare('UPDATE notifications SET read = 1 WHERE id IN (?, ?)').run('nt_seed_activity_3', 'nt_seed_milestone');

  const summary = {
    users: USERS.length,
    habits: habitRows.length,
    habitLogs: habitRows.length * LOG_DAYS,
    activities: recent.length,
    friendships: FRIENDSHIPS.length,
    pendingRequests: 1,
    pendingNudges: 3,
  };
  log(summary);
  return summary;
}

// ---------------------------------------------------------------- CLI entry

function isMain() {
  return process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
}

if (isMain()) {
  const argIndex = process.argv.indexOf('--db');
  const here = path.dirname(fileURLToPath(import.meta.url));
  const dbPath =
    argIndex !== -1 && process.argv[argIndex + 1]
      ? process.argv[argIndex + 1]
      : process.env.PW_DB_PATH ?? path.resolve(here, '..', 'data', 'pw.db');

  const db = openDb(dbPath === ':memory:' ? ':memory:' : path.resolve(dbPath));
  const summary = seed(db);

  console.log(`Seeded ${dbPath}`);
  console.log(
    `  ${summary.users} users, ${summary.habits} habits, ~${summary.habitLogs} habit logs, ` +
      `${summary.activities} activities, ${summary.friendships} friendships`
  );
  console.log('');
  console.log('Demo logins (password for all: password123)');
  console.log('  username   name           notes');
  console.log('  ---------- -------------- ------------------------------------------');
  console.log('  alexr      Alex Rivera    PRIMARY DEMO - 9 day streak, 4 habits,');
  console.log('                            3 friends, 1 incoming friend request,');
  console.log('                            2 pending nudges, unread notifications');
  console.log('  taylorm    Taylor Mills   22 day streak, 6 habits');
  console.log('  jordanp    Jordan Park    5 day streak (today already complete)');
  console.log('  samk       Sam Keller     2 day streak, not Alex\'s friend (suggestion)');
  console.log('  priyan     Priya Nair     14 day streak');
  console.log('  devong     Devon Grant    no habits at all - streak 0, 0%');
  console.log('');
  console.log('  Log in with the username OR the email (e.g. alex@pw.app).');
  db.close();
}
