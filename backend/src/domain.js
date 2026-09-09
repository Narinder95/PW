// Shared domain computations + row -> contract-shape mappers.
// Everything here is read-only w.r.t. the DB and fully deterministic. Every
// function that touches `db` is `async` now that the DB layer is Postgres
// (see db.js) rather than the synchronous node:sqlite it started on.

// ------------------------------------------------------------------- dates
// Day-granularity everywhere is UTC, so the server behaves the same wherever
// it runs and tests are stable.

export function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

export function addDays(dateStr, n) {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

// ------------------------------------------------------------------- users

export const AVATAR_PALETTE = [
  '#2DD4BF', '#FB923C', '#A855F7', '#4ADE80', '#60A5FA',
  '#F472B6', '#FACC15', '#F87171', '#34D399', '#818CF8',
];

/** Deterministic avatar colour from a username - no randomness. */
export function avatarColorFor(seed) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return AVATAR_PALETTE[h % AVATAR_PALETTE.length];
}

export function publicUser(row) {
  return {
    id: row.id,
    username: row.username,
    name: row.name,
    avatarColor: row.avatar_color,
    createdAt: row.created_at,
  };
}

export function privateUser(row) {
  return {
    ...publicUser(row),
    email: row.email ?? null,
    phone: row.phone ?? null,
    // An anonymous account exists only on this device until it is claimed.
    isAnonymous: row.is_anonymous === undefined ? false : !!row.is_anonymous,
  };
}

/** The tiny {id, username, name, avatarColor} stub used inside FriendRequest. */
export function userStub(row) {
  return { id: row.id, username: row.username, name: row.name, avatarColor: row.avatar_color };
}

export async function getUser(db, id) {
  return (await db.prepare('SELECT * FROM users WHERE id = ?').get(id)) ?? null;
}

// --------------------------------------------------------------- friendship

export async function areFriends(db, a, b) {
  const row = await db.prepare('SELECT 1 AS x FROM friendships WHERE user_id = ? AND friend_id = ?').get(a, b);
  return !!row;
}

export async function friendIds(db, userId) {
  const rows = await db.prepare('SELECT friend_id FROM friendships WHERE user_id = ?').all(userId);
  return rows.map((r) => r.friend_id);
}

export async function mutualFriendCount(db, a, b) {
  const row = await db
    .prepare(
      `SELECT COUNT(*) AS n FROM friendships f1
         JOIN friendships f2 ON f1.friend_id = f2.friend_id
        WHERE f1.user_id = ? AND f2.user_id = ?`
    )
    .get(a, b);
  return row ? Number(row.n) : 0;
}

export async function addFriendship(db, a, b, at) {
  const stmt = db.prepare(
    'INSERT INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING'
  );
  await stmt.run(a, b, at);
  await stmt.run(b, a, at);
}

/** relationship: self | friend | request_sent | request_received | none */
export async function relationshipTo(db, meId, otherId) {
  if (meId === otherId) return 'self';
  if (await areFriends(db, meId, otherId)) return 'friend';
  const sent = await db
    .prepare("SELECT 1 AS x FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'")
    .get(meId, otherId);
  if (sent) return 'request_sent';
  const received = await db
    .prepare("SELECT 1 AS x FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'")
    .get(otherId, meId);
  if (received) return 'request_received';
  return 'none';
}

// ------------------------------------------------------------------ habits

export async function getHabit(db, id) {
  return (await db.prepare('SELECT * FROM habits WHERE id = ?').get(id)) ?? null;
}

export async function listHabitRows(db, userId) {
  return db.prepare('SELECT * FROM habits WHERE user_id = ? ORDER BY created_at ASC, id ASC').all(userId);
}

export async function progressFor(db, habitId, date) {
  const row = await db.prepare('SELECT progress FROM habit_logs WHERE habit_id = ? AND date = ?').get(habitId, date);
  return row ? row.progress : 0;
}

/** 7 booleans, oldest first, index 6 === `endDate`. */
export async function habitWeekData(db, habitId, target, endDate) {
  const start = addDays(endDate, -6);
  const rows = await db
    .prepare('SELECT date, progress FROM habit_logs WHERE habit_id = ? AND date >= ? AND date <= ?')
    .all(habitId, start, endDate);
  const byDate = new Map(rows.map((r) => [r.date, r.progress]));
  const out = [];
  for (let i = 6; i >= 0; i--) {
    const d = addDays(endDate, -i);
    out.push((byDate.get(d) ?? 0) >= target);
  }
  return out;
}

const MAX_STREAK_LOOKBACK = 400;

/**
 * Consecutive completed days ending at `endDate`. If `endDate` itself is not
 * complete yet, the streak is counted back from the day before (so an
 * in-progress today does not zero out yesterday's streak).
 */
export async function habitStreak(db, habitId, target, endDate) {
  const rows = await db
    .prepare('SELECT date FROM habit_logs WHERE habit_id = ? AND progress >= ? AND date <= ?')
    .all(habitId, target, endDate);
  return walkStreak(new Set(rows.map((r) => r.date)), endDate);
}

function walkStreak(completeDates, endDate) {
  let cursor = completeDates.has(endDate) ? endDate : addDays(endDate, -1);
  let n = 0;
  while (completeDates.has(cursor) && n < MAX_STREAK_LOOKBACK) {
    n += 1;
    cursor = addDays(cursor, -1);
  }
  return n;
}

/** Number of days in `month` (`YYYY-MM`). */
export function daysInMonth(month) {
  const [year, mon] = month.split('-').map(Number);
  return new Date(Date.UTC(year, mon, 0)).getUTCDate();
}

/**
 * One entry per day of `month` (`YYYY-MM`), oldest first (index 0 = the
 * 1st): `true` (target met), `false` (logged short, or not logged, on a day
 * that already happened), or `null` for a day before `createdAt` or after
 * `todayDate` — no data to report, distinct from a miss.
 */
export async function habitMonthData(db, habitId, target, createdAt, month, todayDate) {
  const total = daysInMonth(month);
  const first = `${month}-01`;
  const last = `${month}-${String(total).padStart(2, '0')}`;
  const rows = await db
    .prepare('SELECT date, progress FROM habit_logs WHERE habit_id = ? AND date >= ? AND date <= ?')
    .all(habitId, first, last);
  const byDate = new Map(rows.map((r) => [r.date, r.progress]));
  const createdDate = createdAt.slice(0, 10);
  const out = [];
  for (let day = 1; day <= total; day++) {
    const date = `${month}-${String(day).padStart(2, '0')}`;
    if (byDate.has(date)) {
      // An actual log row is truthful even for a backfilled date outside the
      // creation/today window (the log endpoint does not forbid that).
      out.push(byDate.get(date) >= target);
    } else {
      out.push(date < createdDate || date > todayDate ? null : false);
    }
  }
  return out;
}

/**
 * One entry per day of `month` (`YYYY-MM`), oldest first (index 0 = the
 * 1st): the raw `progress` actually logged that day, or `null` if nothing was
 * ever logged for it. Unlike [habitMonthData] this never infers `false` for
 * an unlogged past day — there is no real number to show for it, so it must
 * read as "no data" rather than "0 logged".
 */
export async function habitMonthProgressData(db, habitId, month) {
  const total = daysInMonth(month);
  const first = `${month}-01`;
  const last = `${month}-${String(total).padStart(2, '0')}`;
  const rows = await db
    .prepare('SELECT date, progress FROM habit_logs WHERE habit_id = ? AND date >= ? AND date <= ?')
    .all(habitId, first, last);
  const byDate = new Map(rows.map((r) => [r.date, r.progress]));
  const out = [];
  for (let day = 1; day <= total; day++) {
    const date = `${month}-${String(day).padStart(2, '0')}`;
    out.push(byDate.has(date) ? byDate.get(date) : null);
  }
  return out;
}

/** Habit shape from the contract (own habit). */
export async function habitToJson(db, row, date) {
  const [progress, weekData, streak] = await Promise.all([
    progressFor(db, row.id, date),
    habitWeekData(db, row.id, row.target, date),
    habitStreak(db, row.id, row.target, date),
  ]);
  return {
    id: row.id,
    name: row.name,
    icon: row.icon,
    color: row.color,
    target: row.target,
    unit: row.unit,
    progress,
    weekData,
    streak,
    completedToday: progress >= row.target,
  };
}

/** FriendHabit shape (read-only view of someone else's habit). */
export async function friendHabitToJson(db, row, date) {
  const progress = await progressFor(db, row.id, date);
  let status = 'not_started';
  if (progress >= row.target) status = 'completed';
  else if (progress > 0) status = 'in_progress';
  return {
    id: row.id,
    name: row.name,
    icon: row.icon,
    color: row.color,
    progress,
    target: row.target,
    unit: row.unit,
    status,
  };
}

// -------------------------------------------------------------- user stats

/**
 * Every date <= endDate on which the user completed ALL of their habits.
 * A user with zero habits has no complete days at all.
 */
async function userCompleteDates(db, userId, endDate) {
  const countRow = await db.prepare('SELECT COUNT(*) AS n FROM habits WHERE user_id = ?').get(userId);
  const total = Number(countRow.n);
  if (total === 0) return new Set();
  const rows = await db
    .prepare(
      `SELECT hl.date AS date
         FROM habit_logs hl
         JOIN habits h ON h.id = hl.habit_id
        WHERE h.user_id = ? AND hl.date <= ? AND hl.progress >= h.target
        GROUP BY hl.date
       HAVING COUNT(*) >= ?`
    )
    .all(userId, endDate, total);
  return new Set(rows.map((r) => r.date));
}

/** streakDays: consecutive all-habits-complete days ending today (or yesterday). */
export async function userStreak(db, userId, endDate) {
  return walkStreak(await userCompleteDates(db, userId, endDate), endDate);
}

/** 7 booleans of "completed every habit that day", oldest first. */
export async function userWeekData(db, userId, endDate) {
  const complete = await userCompleteDates(db, userId, endDate);
  const out = [];
  for (let i = 6; i >= 0; i--) out.push(complete.has(addDays(endDate, -i)));
  return out;
}

export async function userDayStats(db, userId, date) {
  const habits = await listHabitRows(db, userId);
  let completed = 0;
  for (const h of habits) {
    if ((await progressFor(db, h.id, date)) >= h.target) completed += 1;
  }
  const total = habits.length;
  return {
    habitsTotal: total,
    habitsCompleted: completed,
    completionPercentage: total === 0 ? 0 : round4(completed / total),
  };
}

function round4(n) {
  return Math.round(n * 10000) / 10000;
}

/** FriendSummary shape. Also used for the caller's own stats in /compare. */
export async function friendSummary(db, userRow, date) {
  const [stats, streakDays, weekData] = await Promise.all([
    userDayStats(db, userRow.id, date),
    userStreak(db, userRow.id, date),
    userWeekData(db, userRow.id, date),
  ]);
  return {
    id: userRow.id,
    username: userRow.username,
    name: userRow.name,
    avatarColor: userRow.avatar_color,
    streakDays,
    completionPercentage: stats.completionPercentage,
    habitsCompleted: stats.habitsCompleted,
    habitsTotal: stats.habitsTotal,
    weekData,
    lastActiveAt: userRow.last_active_at,
  };
}

// -------------------------------------------------------------- comparison

const normName = (s) => s.trim().toLowerCase();

/** First-wins map of normalized habit name -> habit row. */
export function habitsByName(rows) {
  const m = new Map();
  for (const r of rows) {
    const k = normName(r.name);
    if (!m.has(k)) m.set(k, r);
  }
  return m;
}

export function ratio(progress, target) {
  if (!target || target <= 0) return 0;
  return Math.min(1, progress / target);
}

export async function buildComparison(db, meRow, friendRow, date) {
  const [mineRows, theirsRows] = await Promise.all([
    listHabitRows(db, meRow.id),
    listHabitRows(db, friendRow.id),
  ]);
  const mine = habitsByName(mineRows);
  const theirs = habitsByName(theirsRows);

  const habits = [];
  let myScore = 0;
  let friendScore = 0;

  for (const [key, myHabit] of mine) {
    const theirHabit = theirs.get(key);
    if (!theirHabit) continue;
    const [myProgress, friendProgress] = await Promise.all([
      progressFor(db, myHabit.id, date),
      progressFor(db, theirHabit.id, date),
    ]);
    const myRatio = ratio(myProgress, myHabit.target);
    const friendRatio = ratio(friendProgress, theirHabit.target);
    let winner = 'tie';
    if (myRatio > friendRatio) {
      winner = 'me';
      myScore += 1;
    } else if (friendRatio > myRatio) {
      winner = 'friend';
      friendScore += 1;
    }
    habits.push({
      name: myHabit.name,
      icon: myHabit.icon,
      color: myHabit.color,
      myProgress,
      myTarget: myHabit.target,
      friendProgress,
      friendTarget: theirHabit.target,
      unit: myHabit.unit,
      winner,
    });
  }

  let verdict = 'tie';
  if (myScore > friendScore) verdict = 'me_ahead';
  else if (friendScore > myScore) verdict = 'friend_ahead';

  const [myStreak, friendStreak] = await Promise.all([
    userStreak(db, meRow.id, date),
    userStreak(db, friendRow.id, date),
  ]);

  return {
    me: {
      id: meRow.id,
      name: meRow.name,
      avatarColor: meRow.avatar_color,
      score: myScore,
      streakDays: myStreak,
    },
    friend: {
      id: friendRow.id,
      name: friendRow.name,
      avatarColor: friendRow.avatar_color,
      score: friendScore,
      streakDays: friendStreak,
    },
    habits,
    sharedHabitCount: habits.length,
    verdict,
  };
}

// ------------------------------------------------------------------ match

/** Habit names two users share (case-insensitive), returned in the caller's casing. */
export async function sharedHabitNames(db, meId, otherId) {
  const [mineRows, theirsRows] = await Promise.all([listHabitRows(db, meId), listHabitRows(db, otherId)]);
  const mine = habitsByName(mineRows);
  const theirs = habitsByName(theirsRows);
  const out = [];
  for (const [key, habit] of mine) if (theirs.has(key)) out.push(habit.name);
  return out.sort((a, b) => a.localeCompare(b));
}

/**
 * matchScore = min(100, shared*20 + mutual*15 + streakAffinity)
 * streakAffinity = max(0, 10 - |myStreak - theirStreak|). Deterministic.
 */
export function matchScore({ sharedHabits, mutualFriends, myStreak, theirStreak }) {
  const affinity = Math.max(0, 10 - Math.abs(myStreak - theirStreak));
  return Math.min(100, sharedHabits * 20 + mutualFriends * 15 + affinity);
}

export function matchReason(sharedCount, mutualCount) {
  const parts = [];
  if (sharedCount > 0) parts.push(`${sharedCount} habit${sharedCount === 1 ? '' : 's'} in common`);
  if (mutualCount > 0) parts.push(`${mutualCount} mutual friend${mutualCount === 1 ? '' : 's'}`);
  if (parts.length === 0) return 'New on PW - say hello';
  return parts.join(' - ');
}

// ------------------------------------------------------------- walking challenge

export const WALKING_TARGETS = { bronze: 8000, silver: 10000, gold: 12000 };
const LEVEL_NEXT = { none: 'bronze', bronze: 'silver', silver: 'gold', gold: 'gold' };
const LEVEL_PREV = { gold: 'silver', silver: 'bronze', bronze: 'none', none: 'none' };
const MAX_WALK_LOOKBACK = 400; // same cap as MAX_STREAK_LOOKBACK above

function targetForLevel(level) {
  if (level === 'none') return WALKING_TARGETS.bronze;
  if (level === 'bronze') return WALKING_TARGETS.silver;
  return WALKING_TARGETS.gold; // silver -> pursuing gold; gold -> maintaining gold
}

/**
 * Walks daily_steps chronologically through **yesterday** (never today —
 * today is still in progress, so it must not trigger a promotion, warning or
 * demotion until the day rolls over; same reasoning `habitStreak` uses for an
 * incomplete "today"). Returns the committed level/streak plus a trailing
 * history, all derived fresh from the log every call - there is no separate
 * mutable "current state" row.
 *
 * A day with no synced row (the device never reported steps - the app may
 * not have been opened) is treated as a warning/freeze, never a demotion: a
 * sync gap is not proof the user fell short. Only a day with an actual
 * synced value under 80% of that day's target demotes.
 */
export async function walkingChallengeState(db, userId, todayDate) {
  const yesterday = addDays(todayDate, -1);
  const start = addDays(yesterday, -(MAX_WALK_LOOKBACK - 1));
  const [rows, todayRow] = await Promise.all([
    db
      .prepare('SELECT date, steps FROM daily_steps WHERE user_id = ? AND date >= ? AND date <= ? ORDER BY date ASC')
      .all(userId, start, yesterday),
    db.prepare('SELECT steps FROM daily_steps WHERE user_id = ? AND date = ?').get(userId, todayDate),
  ]);
  const stepsByDate = new Map(rows.map((r) => [r.date, r.steps]));

  let level = 'none';
  let streak = 0;
  const history = [];
  let cursor = start;
  while (cursor <= yesterday) {
    const hasRow = stepsByDate.has(cursor);
    const steps = stepsByDate.get(cursor) ?? 0;
    const target = targetForLevel(level);
    const stepRatio = target > 0 ? steps / target : 0;
    let status;
    if (steps >= target) {
      status = 'met';
      streak += 1;
      if (level !== 'gold' && streak >= 3) {
        level = LEVEL_NEXT[level];
        streak = 0;
      }
    } else if (stepRatio >= 0.8) {
      status = 'warning'; // frozen: streak unchanged
    } else if (!hasRow) {
      status = 'no_data'; // frozen: streak unchanged, never demotes
    } else {
      status = 'shortfall';
      if (level !== 'none') level = LEVEL_PREV[level];
      streak = 0;
    }
    history.push({ date: cursor, steps, target, status });
    cursor = addDays(cursor, 1);
  }

  const target = targetForLevel(level);
  const todaySteps = todayRow ? todayRow.steps : 0;
  const todayRatio = target > 0 ? todaySteps / target : 0;
  const todayStatus = todaySteps >= target ? 'met' : todayRatio >= 0.8 ? 'warning' : todayRow ? 'shortfall' : 'no_data';

  return {
    level,
    streakDays: streak,
    target,
    nextLevel: LEVEL_NEXT[level] === level ? null : LEVEL_NEXT[level],
    daysToNextLevel: level === 'gold' ? null : Math.max(0, 3 - streak),
    todaySteps,
    todayStatus,
    history: history.slice(-14),
  };
}

export function walkingChallengeToJson(state) {
  return {
    level: state.level,
    streakDays: state.streakDays,
    target: state.target,
    nextLevel: state.nextLevel,
    daysToNextLevel: state.daysToNextLevel,
    todaySteps: state.todaySteps,
    todayStatus: state.todayStatus,
    history: state.history,
  };
}

// ------------------------------------------------------------------ shapes

export function nudgeToJson(row) {
  return {
    id: row.id,
    type: row.type,
    fromUserId: row.from_user_id,
    fromUserName: row.from_user_name ?? null,
    toUserId: row.to_user_id,
    habitId: row.habit_id ?? null,
    habitName: row.habit_name,
    habitIcon: row.habit_icon ?? null,
    habitColor: row.habit_color ?? null,
    message: row.message ?? null,
    status: row.status,
    createdAt: row.created_at,
    acceptedAt: row.accepted_at ?? null,
  };
}

export function notificationToJson(row) {
  return {
    id: row.id,
    type: row.type,
    title: row.title,
    body: row.body,
    actorId: row.actor_id ?? null,
    actorName: row.actor_name ?? null,
    avatarColor: row.avatar_color ?? null,
    icon: row.icon ?? null,
    color: row.color ?? null,
    refType: row.ref_type ?? null,
    refId: row.ref_id ?? null,
    read: !!row.read,
    createdAt: row.created_at,
  };
}

export function activityToJson(row) {
  return {
    id: row.id,
    friendId: row.user_id,
    friendName: row.friend_name,
    avatarColor: row.avatar_color,
    habitName: row.habit_name,
    habitIcon: row.habit_icon,
    habitColor: row.habit_color,
    completion: row.completion,
    createdAt: row.created_at,
  };
}

export async function friendRequestToJson(db, row) {
  const [from, to, mutualFriends] = await Promise.all([
    getUser(db, row.from_user_id),
    getUser(db, row.to_user_id),
    mutualFriendCount(db, row.from_user_id, row.to_user_id),
  ]);
  return {
    id: row.id,
    fromUser: from ? userStub(from) : null,
    toUser: to ? userStub(to) : null,
    status: row.status,
    mutualFriends,
    createdAt: row.created_at,
    respondedAt: row.responded_at ?? null,
  };
}
