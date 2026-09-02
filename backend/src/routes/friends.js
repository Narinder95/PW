import { ApiError, sendJson, sendNoContent, parseDate } from '../http.js';
import {
  todayISO, getUser, areFriends, friendIds, listHabitRows,
  friendSummary, friendHabitToJson, buildComparison,
} from '../domain.js';

/**
 * Resolve `:id` to a user the caller is allowed to look at.
 * Unknown id -> 404. Known but not a friend -> 403 (never leak their habits).
 */
function friendOr403(db, meId, otherId) {
  const other = getUser(db, otherId);
  if (!other) throw ApiError.notFound('User not found');
  if (other.id === meId) throw ApiError.forbidden('That is you, not a friend');
  if (!areFriends(db, meId, otherId)) throw ApiError.forbidden('You are not friends with that user');
  return other;
}

export function registerFriendRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/friends', async ({ res, url, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const friends = friendIds(db, me.id)
      .map((id) => getUser(db, id))
      .filter(Boolean)
      .map((row) => friendSummary(db, row, date))
      // streak desc, then name asc
      .sort((a, b) => b.streakDays - a.streakDays || a.name.localeCompare(b.name));
    sendJson(res, 200, { friends });
  }, { auth: true });

  router.get('/api/friends/:id', async ({ res, url, params, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const other = friendOr403(db, me.id, params.id);
    const habits = listHabitRows(db, other.id).map((h) => friendHabitToJson(db, h, date));
    sendJson(res, 200, { friend: friendSummary(db, other, date), habits });
  }, { auth: true });

  router.delete('/api/friends/:id', async ({ res, params, me }) => {
    const other = friendOr403(db, me.id, params.id);
    const stmt = db.prepare('DELETE FROM friendships WHERE user_id = ? AND friend_id = ?');
    stmt.run(me.id, other.id);
    stmt.run(other.id, me.id);
    sendNoContent(res);
  }, { auth: true });

  router.get('/api/friends/:id/compare', async ({ res, url, params, me }) => {
    const date = parseDate(url.searchParams.get('date')) ?? todayISO();
    const other = friendOr403(db, me.id, params.id);
    sendJson(res, 200, { comparison: buildComparison(db, me, other, date) });
  }, { auth: true });
}
