import { ApiError, sendJson, nowISO, requireInt, parseDate } from '../http.js';
import { todayISO, walkingChallengeState, walkingChallengeToJson } from '../domain.js';

const MAX_SYNC_DAYS = 31;

function currentChallenge(db, userId) {
  return walkingChallengeToJson(walkingChallengeState(db, userId, todayISO()));
}

export function registerStepsRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/challenge', async ({ res, me }) => {
    sendJson(res, 200, { challenge: currentChallenge(db, me.id) });
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
    const upsert = db.prepare(
      `INSERT INTO daily_steps (user_id, date, steps, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id, date) DO UPDATE SET
         steps = MAX(steps, excluded.steps),
         updated_at = excluded.updated_at`
    );

    for (const entry of days) {
      const date = parseDate(entry?.date);
      if (!date) throw ApiError.validation('each day requires a valid date', 'days');
      const steps = requireInt(entry, 'steps', { min: 0, max: 200_000 });
      upsert.run(me.id, date, steps, updatedAt);
    }

    sendJson(res, 200, { challenge: currentChallenge(db, me.id) });
  }, { auth: true });
}
