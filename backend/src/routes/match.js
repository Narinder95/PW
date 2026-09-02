import { ApiError, sendJson, parseLimit } from '../http.js';
import {
  todayISO, relationshipTo, mutualFriendCount, sharedHabitNames,
  matchScore, matchReason, userStreak,
} from '../domain.js';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

function searchResult(db, meId, row) {
  return {
    id: row.id,
    username: row.username,
    name: row.name,
    avatarColor: row.avatar_color,
    mutualFriends: mutualFriendCount(db, meId, row.id),
    relationship: relationshipTo(db, meId, row.id),
  };
}

export function registerMatchRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/users/search', async ({ res, url, me }) => {
    const raw = url.searchParams.get('q');
    const q = typeof raw === 'string' ? raw.trim() : '';
    if (q.length < 1) throw ApiError.validation('q must be at least 1 character', 'q');
    const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT);

    const like = `%${q.toLowerCase().replace(/[\\%_]/g, (c) => `\\${c}`)}%`;
    const rows = db
      .prepare(
        `SELECT * FROM users
          WHERE id != ?
            AND (LOWER(username) LIKE ? ESCAPE '\\' OR LOWER(name) LIKE ? ESCAPE '\\')
          ORDER BY username ASC
          LIMIT ?`
      )
      .all(me.id, like, like, limit);

    sendJson(res, 200, { users: rows.map((r) => searchResult(db, me.id, r)) });
  }, { auth: true });

  router.get('/api/match/suggestions', async ({ res, url, me }) => {
    const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT);
    const date = todayISO();
    const myStreak = userStreak(db, me.id, date);

    // Everyone who is not me, not already a friend, and has no pending request
    // in either direction.
    const candidates = db
      .prepare(
        `SELECT * FROM users u
          WHERE u.id != ?
            AND NOT EXISTS (SELECT 1 FROM friendships f WHERE f.user_id = ? AND f.friend_id = u.id)
            AND NOT EXISTS (
                  SELECT 1 FROM friend_requests r
                   WHERE r.status = 'pending'
                     AND ((r.from_user_id = ? AND r.to_user_id = u.id)
                       OR (r.from_user_id = u.id AND r.to_user_id = ?)))
          ORDER BY u.username ASC`
      )
      .all(me.id, me.id, me.id, me.id);

    const suggestions = candidates
      .map((row) => {
        const shared = sharedHabitNames(db, me.id, row.id);
        const mutual = mutualFriendCount(db, me.id, row.id);
        const score = matchScore({
          sharedHabits: shared.length,
          mutualFriends: mutual,
          myStreak,
          theirStreak: userStreak(db, row.id, date),
        });
        return {
          user: searchResult(db, me.id, row),
          sharedHabits: shared,
          matchScore: score,
          reason: matchReason(shared.length, mutual),
        };
      })
      // matchScore desc, then username asc - fully deterministic.
      .sort((a, b) => b.matchScore - a.matchScore || a.user.username.localeCompare(b.user.username))
      .slice(0, limit);

    sendJson(res, 200, { suggestions });
  }, { auth: true });
}
