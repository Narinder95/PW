import {
  ApiError, sendJson, sendNoContent, newId, nowISO,
  requireString, optionalString, requireInt, normalizeColor, parseDate, parseMonth,
} from '../http.js';
import {
  todayISO, getHabit, listHabitRows, habitToJson, habitMonthData, habitMonthProgressData,
  daysInMonth, friendIds,
} from '../domain.js';
import { createNotification } from '../notifications.js';
import { upsertDailySteps } from './steps.js';
import { UNIQUE_VIOLATION } from '../db.js';

const DEFAULT_ICON = '*';
const DEFAULT_COLOR = '#2DD4BF';

/** Load a habit, 404 if unknown, 404 if it belongs to someone else. */
async function ownHabitOr404(db, habitId, userId) {
  const habit = await getHabit(db, habitId);
  // A habit you do not own is indistinguishable from one that does not exist.
  if (!habit || habit.user_id !== userId) throw ApiError.notFound('Habit not found');
  return habit;
}

function formatCompletion(progress, target, unit) {
  const base = `${progress}/${target}`;
  return unit ? `${base} ${unit}` : base;
}

// The client (Journal and Journey tabs alike) keys its own habits by
// `name.trim().toLowerCase()` to line them up with the catalogue and with
// the "Steps" habit's walking-challenge sync. Two habits colliding on that
// key would make one silently disappear from the UI, so it is rejected here
// rather than left for the client to cope with. `idx_habits_user_name` (see
// db.js) is the real guarantee under concurrency; this is just the friendly
// error ahead of that constraint violation.
async function assertNameAvailable(db, userId, name, excludeHabitId = null) {
  const key = name.trim().toLowerCase();
  const rows = await listHabitRows(db, userId);
  const collides = rows.some(
    (h) => h.id !== excludeHabitId && h.name.trim().toLowerCase() === key
  );
  if (collides) {
    throw ApiError.conflict(`You already have a habit named "${name}"`);
  }
}

export function registerHabitRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/habits', async ({ res, url, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const rows = await listHabitRows(db, me.id);
    const habits = await Promise.all(rows.map((h) => habitToJson(db, h, date)));
    sendJson(res, 200, { habits });
  }, { auth: true });

  /** For the radial monthly-progress card: every own habit's daily record for one month. */
  router.get('/api/habits/month', async ({ res, url, me }) => {
    const month = parseMonth(url.searchParams.get('month')) ?? todayISO().slice(0, 7);
    const today = todayISO();
    const rows = await listHabitRows(db, me.id);
    const habits = await Promise.all(rows.map(async (row) => ({
      id: row.id,
      name: row.name,
      icon: row.icon,
      color: row.color,
      monthData: await habitMonthData(db, row.id, row.target, row.created_at, month, today),
      progressData: await habitMonthProgressData(db, row.id, month),
    })));
    sendJson(res, 200, { month, days: daysInMonth(month), habits });
  }, { auth: true });

  router.post('/api/habits', async ({ res, body, me }) => {
    const name = requireString(body, 'name', { min: 1, max: 60 });
    const target = requireInt(body, 'target', { min: 1, max: 1_000_000_000 });
    const icon = optionalString(body, 'icon', { max: 16 }) || DEFAULT_ICON;
    const color = normalizeColor(body.color, 'color') ?? DEFAULT_COLOR;
    const unit = optionalString(body, 'unit', { max: 20 }) ?? '';
    await assertNameAvailable(db, me.id, name);

    const row = {
      id: newId('h'),
      user_id: me.id,
      name,
      icon,
      color,
      target,
      unit,
      created_at: nowISO(),
    };
    try {
      await db.prepare(
        'INSERT INTO habits (id, user_id, name, icon, color, target, unit, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
      ).run(row.id, row.user_id, row.name, row.icon, row.color, row.target, row.unit, row.created_at);
    } catch (err) {
      if (err?.code === UNIQUE_VIOLATION) throw ApiError.conflict(`You already have a habit named "${name}"`);
      throw err;
    }

    sendJson(res, 201, { habit: await habitToJson(db, row, todayISO()) });
  }, { auth: true });

  router.patch('/api/habits/:id', async ({ res, body, params, me }) => {
    const habit = await ownHabitOr404(db, params.id, me.id);
    const updates = {};
    if (body.name !== undefined) {
      updates.name = requireString(body, 'name', { min: 1, max: 60 });
      await assertNameAvailable(db, me.id, updates.name, habit.id);
    }
    if (body.icon !== undefined) updates.icon = optionalString(body, 'icon', { max: 16 }) || DEFAULT_ICON;
    if (body.color !== undefined) updates.color = normalizeColor(body.color, 'color') ?? habit.color;
    if (body.target !== undefined) updates.target = requireInt(body, 'target', { min: 1, max: 1_000_000_000 });
    if (body.unit !== undefined) updates.unit = optionalString(body, 'unit', { max: 20 }) ?? '';

    if (Object.keys(updates).length > 0) {
      const sets = Object.keys(updates).map((k) => `${k} = ?`).join(', ');
      try {
        await db.prepare(`UPDATE habits SET ${sets} WHERE id = ?`).run(...Object.values(updates), habit.id);
      } catch (err) {
        if (err?.code === UNIQUE_VIOLATION) throw ApiError.conflict(`You already have a habit named "${updates.name}"`);
        throw err;
      }
    }
    const fresh = await getHabit(db, habit.id);
    sendJson(res, 200, { habit: await habitToJson(db, fresh, todayISO()) });
  }, { auth: true });

  router.delete('/api/habits/:id', async ({ res, params, me }) => {
    const habit = await ownHabitOr404(db, params.id, me.id);
    await db.prepare('DELETE FROM habits WHERE id = ?').run(habit.id);
    sendNoContent(res);
  }, { auth: true });

  router.post('/api/habits/:id/log', async ({ res, body, params, me }) => {
    const habit = await ownHabitOr404(db, params.id, me.id);
    const progress = requireInt(body, 'progress', { min: 0, max: 1_000_000_000 });
    const date = parseDate(body.date) ?? todayISO();

    await db.prepare(
      `INSERT INTO habit_logs (id, habit_id, user_id, date, progress, updated_at)
       VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(habit_id, date) DO UPDATE SET progress = excluded.progress, updated_at = excluded.updated_at`
    ).run(newId('hl'), habit.id, me.id, date, progress, nowISO());

    // The "Steps" habit is the app's one manual step-entry point. Feed the
    // same total into daily_steps so the walking-challenge (Journey tab)
    // reflects it too, instead of the two ever-so-similarly-named counters
    // silently disagreeing. Uses the same MAX-of-existing-and-new upsert as
    // device sync, so a manual entry can raise today's total without ever
    // clobbering a larger value the device already reported.
    if (habit.name.trim().toLowerCase() === 'steps') {
      await upsertDailySteps(db, me.id, date, progress);
    }

    let activity = null;
    if (progress >= habit.target) {
      // UNIQUE(habit_id, date) makes this idempotent: repeated logs of an
      // already-complete habit cannot produce a second activity row.
      const existing = await db
        .prepare('SELECT 1 AS x FROM activities WHERE habit_id = ? AND date = ?')
        .get(habit.id, date);
      if (!existing) {
        const row = {
          id: newId('a'),
          user_id: me.id,
          habit_id: habit.id,
          habit_name: habit.name,
          habit_icon: habit.icon,
          habit_color: habit.color,
          completion: formatCompletion(progress, habit.target, habit.unit),
          date,
          created_at: nowISO(),
        };
        await db.prepare(
          `INSERT INTO activities
             (id, user_id, habit_id, habit_name, habit_icon, habit_color, completion, date, created_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`
        ).run(
          row.id, row.user_id, row.habit_id, row.habit_name, row.habit_icon,
          row.habit_color, row.completion, row.date, row.created_at
        );

        activity = {
          id: row.id,
          friendId: me.id,
          friendName: me.name,
          avatarColor: me.avatar_color,
          habitName: row.habit_name,
          habitIcon: row.habit_icon,
          habitColor: row.habit_color,
          completion: row.completion,
          createdAt: row.created_at,
        };

        const fids = await friendIds(db, me.id);
        for (const fid of fids) {
          await createNotification(ctx, {
            userId: fid,
            type: 'friend_activity',
            title: `${me.name} completed ${habit.name}`,
            body: `${me.name} finished ${row.completion}`,
            actorId: me.id,
            actorName: me.name,
            avatarColor: me.avatar_color,
            icon: habit.icon,
            color: habit.color,
            refType: 'activity',
            refId: row.id,
          });
        }
      }
    }

    sendJson(res, 200, { habit: await habitToJson(db, habit, date), activity });
  }, { auth: true });
}
