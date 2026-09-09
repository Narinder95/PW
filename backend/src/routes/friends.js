import { ApiError, sendJson, sendNoContent, parseDate } from '../http.js';
import {
  todayISO, getUser, areFriends, friendIds, listHabitRows,
  friendSummary, friendHabitToJson, buildComparison,
} from '../domain.js';

/**
 * Resolve `:id` to a user the caller is allowed to look at.
 * Unknown id -> 404. Known but not a friend -> 403 (never leak their habits).
 */
async function friendOr403(db, meId, otherId) {
  const other = await getUser(db, otherId);
  if (!other) throw ApiError.notFound('User not found');
  if (other.id === meId) throw ApiError.forbidden('That is you, not a friend');
  if (!(await areFriends(db, meId, otherId))) throw ApiError.forbidden('You are not friends with that user');
  return other;
}

export function registerFriendRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/friends', async ({ res, url, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const ids = await friendIds(db, me.id);
    const rows = (await Promise.all(ids.map((id) => getUser(db, id)))).filter(Boolean);
    const friends = (await Promise.all(rows.map((row) => friendSummary(db, row, date))))
      // streak desc, then name asc
      .sort((a, b) => b.streakDays - a.streakDays || a.name.localeCompare(b.name));
    sendJson(res, 200, { friends });
  }, { auth: true });

  router.get('/api/friends/:id', async ({ res, url, params, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const other = await friendOr403(db, me.id, params.id);
    const rows = await listHabitRows(db, other.id);
    const habits = await Promise.all(rows.map((h) => friendHabitToJson(db, h, date)));
    sendJson(res, 200, { friend: await friendSummary(db, other, date), habits });
  }, { auth: true });

  router.delete('/api/friends/:id', async ({ res, params, me }) => {
    const other = await friendOr403(db, me.id, params.id);
    const stmt = db.prepare('DELETE FROM friendships WHERE user_id = ? AND friend_id = ?');
    await stmt.run(me.id, other.id);
    await stmt.run(other.id, me.id);
    sendNoContent(res);
  }, { auth: true });

  router.get('/api/friends/:id/compare', async ({ res, url, params, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const other = await friendOr403(db, me.id, params.id);
    sendJson(res, 200, { comparison: await buildComparison(db, me, other, date) });
  }, { auth: true });
}
