// Shared domain computations + row -> contract-shape mappers.
// Everything here is pure w.r.t. the DB (reads only) and fully deterministic.

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

export function getUser(db, id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id) ?? null;
}

// --------------------------------------------------------------- friendship

export function areFriends(db, a, b) {
  const row = db.prepare('SELECT 1 AS x FROM friendships WHERE user_id = ? AND friend_id = ?').get(a, b);
  return !!row;
}

export function friendIds(db, userId) {
  return db.prepare('SELECT friend_id FROM friendships WHERE user_id = ?').all(userId).map((r) => r.friend_id);
}

export function mutualFriendCount(db, a, b) {
  const row = db
    .prepare(
      `SELECT COUNT(*) AS n FROM friendships f1
         JOIN friendships f2 ON f1.friend_id = f2.friend_id
        WHERE f1.user_id = ? AND f2.user_id = ?`
    )
    .get(a, b);
  return row ? row.n : 0;
}

export function addFriendship(db, a, b, at) {
  const stmt = db.prepare(
    'INSERT INTO friendships (user_id, friend_id, created_at) VALUES (?, ?, ?) ON CONFLICT DO NOTHING'
  );
  stmt.run(a, b, at);
  stmt.run(b, a, at);
}

/** relationship: self | friend | request_sent | request_received | none */
export function relationshipTo(db, meId, otherId) {
  if (meId === otherId) return 'self';
  if (areFriends(db, meId, otherId)) return 'friend';
  const sent = db
    .prepare("SELECT 1 AS x FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'")
    .get(meId, otherId);
  if (sent) return 'request_sent';
  const received = db
    .prepare("SELECT 1 AS x FROM friend_requests WHERE from_user_id = ? AND to_user_id = ? AND status = 'pending'")
    .get(otherId, meId);
  if (received) return 'request_received';
  return 'none';
}

// ------------------------------------------------------------------ habits

export function getHabit(db, id) {
  return db.prepare('SELECT * FROM habits WHERE id = ?').get(id) ?? null;
}

export function listHabitRows(db, userId) {
  return db.prepare('SELECT * FROM habits WHERE user_id = ? ORDER BY created_at ASC, id ASC').all(userId);
}

export function progressFor(db, habitId, date) {
  const row = db.prepare('SELECT progress FROM habit_logs WHERE habit_id = ? AND date = ?').get(habitId, date);
  return row ? row.progress : 0;
}

/** 7 booleans, oldest first, index 6 === `endDate`. */
export function habitWeekData(db, habitId, target, endDate) {
  const start = addDays(endDate, -6);
  const rows = db
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
export function habitStreak(db, habitId, target, endDate) {
  const rows = db
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

/** Habit shape from the contract (own habit). */
export function habitToJson(db, row, date) {
  const progress = progressFor(db, row.id, date);
  return {
    id: row.id,
    name: row.name,
    icon: row.icon,
    color: row.color,
    target: row.target,
    unit: row.unit,
    progress,
    weekData: habitWeekData(db, row.id, row.target, date),
    streak: habitStreak(db, row.id, row.target, date),
    completedToday: progress >= row.target,
  };
}

/** FriendHabit shape (read-only view of someone else's habit). */
export function friendHabitToJson(db, row, date) {
  const progress = progressFor(db, row.id, date);
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
function userCompleteDates(db, userId, endDate) {
  const total = db.prepare('SELECT COUNT(*) AS n FROM habits WHERE user_id = ?').get(userId).n;
  if (total === 0) return new Set();
  const rows = db
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
export function userStreak(db, userId, endDate) {
  return walkStreak(userCompleteDates(db, userId, endDate), endDate);
}

/** 7 booleans of "completed every habit that day", oldest first. */
export function userWeekData(db, userId, endDate) {
  const complete = userCompleteDates(db, userId, endDate);
  const out = [];
  for (let i = 6; i >= 0; i--) out.push(complete.has(addDays(endDate, -i)));
  return out;
}

export function userDayStats(db, userId, date) {
  const habits = listHabitRows(db, userId);
  let completed = 0;
  for (const h of habits) if (progressFor(db, h.id, date) >= h.target) completed += 1;
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
export function friendSummary(db, userRow, date) {
  const stats = userDayStats(db, userRow.id, date);
  return {
    id: userRow.id,
    username: userRow.username,
    name: userRow.name,
    avatarColor: userRow.avatar_color,
    streakDays: userStreak(db, userRow.id, date),
    completionPercentage: stats.completionPercentage,
    habitsCompleted: stats.habitsCompleted,
    habitsTotal: stats.habitsTotal,
    weekData: userWeekData(db, userRow.id, date),
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

export function buildComparison(db, meRow, friendRow, date) {
  const mine = habitsByName(listHabitRows(db, meRow.id));
  const theirs = habitsByName(listHabitRows(db, friendRow.id));

  const habits = [];
  let myScore = 0;
  let friendScore = 0;

  for (const [key, myHabit] of mine) {
    const theirHabit = theirs.get(key);
    if (!theirHabit) continue;
    const myProgress = progressFor(db, myHabit.id, date);
    const friendProgress = progressFor(db, theirHabit.id, date);
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

  return {
    me: {
      id: meRow.id,
      name: meRow.name,
      avatarColor: meRow.avatar_color,
      score: myScore,
      streakDays: userStreak(db, meRow.id, date),
    },
    friend: {
      id: friendRow.id,
      name: friendRow.name,
      avatarColor: friendRow.avatar_color,
      score: friendScore,
      streakDays: userStreak(db, friendRow.id, date),
    },
    habits,
    sharedHabitCount: habits.length,
    verdict,
  };
}

// ------------------------------------------------------------------ match

/** Habit names two users share (case-insensitive), returned in the caller's casing. */
export function sharedHabitNames(db, meId, otherId) {
  const mine = habitsByName(listHabitRows(db, meId));
  const theirs = habitsByName(listHabitRows(db, otherId));
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

export function friendRequestToJson(db, row) {
  const from = getUser(db, row.from_user_id);
  const to = getUser(db, row.to_user_id);
  return {
    id: row.id,
    fromUser: from ? userStub(from) : null,
    toUser: to ? userStub(to) : null,
    status: row.status,
    mutualFriends: mutualFriendCount(db, row.from_user_id, row.to_user_id),
    createdAt: row.created_at,
    respondedAt: row.responded_at ?? null,
  };
}
