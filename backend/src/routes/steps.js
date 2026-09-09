import { ApiError, sendJson, nowISO, requireInt, parseDate } from '../http.js';
import { todayISO, walkingChallengeState, walkingChallengeToJson } from '../domain.js';

const MAX_SYNC_DAYS = 31;
export const MAX_DAILY_STEPS = 200_000;

async function currentChallenge(db, userId) {
  return walkingChallengeToJson(await walkingChallengeState(db, userId, todayISO()));
}

/**
 * Upserts one `daily_steps` row, taking the **larger** of the existing and
 * new value - never the smaller. Shared by `/api/steps/sync` (device backfill,
 * which may resync a partial day more than once) and the manual "Steps" habit
 * log (`routes/habits.js`), so a manual entry can raise today's total without
 * ever clobbering a bigger value the device already reported.
 *
 * Clamped to [0, MAX_DAILY_STEPS] regardless of caller: `/sync` also rejects
 * an out-of-range value outright (a malformed device payload), but a habit
 * log's `progress` has no such ceiling of its own, and the MAX-of-existing-
 * and-new rule means one absurd value here would otherwise poison the row
 * forever - no legitimate future sync could ever bring it back down.
 */
export async function upsertDailySteps(db, userId, date, steps, updatedAt = nowISO()) {
  const clamped = Math.min(Math.max(steps, 0), MAX_DAILY_STEPS);
  await db.prepare(
    `INSERT INTO daily_steps (user_id, date, steps, updated_at)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(user_id, date) DO UPDATE SET
       steps = GREATEST(daily_steps.steps, excluded.steps),
       updated_at = excluded.updated_at`
  ).run(userId, date, clamped, updatedAt);
}

export function registerStepsRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/challenge', async ({ res, me }) => {
    sendJson(res, 200, { challenge: await currentChallenge(db, me.id) });
  }, { auth: true });

  router.post('/api/steps/sync', async ({ res, body, me }) => {
    const days = body?.days;
    if (!Array.isArray(days) || days.length === 0) {
      throw ApiError.validation('days must be a non-empty array', 'days');
    }
    if (days.length > MAX_SYNC_DAYS) {
      throw ApiError.validation(`days must have at most ${MAX_SYNC_DAYS} entries`, 'days');
    }

    const updatedAt = nowISO();
    for (const entry of days) {
      const date = parseDate(entry?.date);
      if (!date) throw ApiError.validation('each day requires a valid date', 'days');
      const steps = requireInt(entry, 'steps', { min: 0, max: MAX_DAILY_STEPS });
      await upsertDailySteps(db, me.id, date, steps, updatedAt);
    }

    sendJson(res, 200, { challenge: await currentChallenge(db, me.id) });
  }, { auth: true });
}
