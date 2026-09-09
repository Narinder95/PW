import { ApiError, sendJson, parseLimit } from '../http.js';
import {
  todayISO, relationshipTo, mutualFriendCount, sharedHabitNames,
  matchScore, matchReason, userStreak,
} from '../domain.js';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;

async function searchResult(db, meId, row) {
  const [mutualFriends, relationship] = await Promise.all([
    mutualFriendCount(db, meId, row.id),
    relationshipTo(db, meId, row.id),
  ]);
  return {
    id: row.id,
    username: row.username,
    name: row.name,
    avatarColor: row.avatar_color,
    mutualFriends,
    relationship,
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
    const rows = await db
      .prepare(
        `SELECT * FROM users
          WHERE id != ?
            AND (LOWER(username) LIKE ? ESCAPE '\\' OR LOWER(name) LIKE ? ESCAPE '\\')
          ORDER BY username ASC
          LIMIT ?`
      )
      .all(me.id, like, like, limit);

    const users = await Promise.all(rows.map((r) => searchResult(db, me.id, r)));
    sendJson(res, 200, { users });
  }, { auth: true });

  router.get('/api/match/suggestions', async ({ res, url, me }) => {
    const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT);
    const date = todayISO();
    const myStreak = await userStreak(db, me.id, date);

    // Everyone who is not me, not already a friend, and has no pending request
    // in either direction.
    const candidates = await db
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

    const suggestions = (await Promise.all(candidates.map(async (row) => {
      const [shared, mutual, theirStreak] = await Promise.all([
        sharedHabitNames(db, me.id, row.id),
        mutualFriendCount(db, me.id, row.id),
        userStreak(db, row.id, date),
      ]);
      const score = matchScore({
        sharedHabits: shared.length,
        mutualFriends: mutual,
        myStreak,
        theirStreak,
      });
      return {
        user: await searchResult(db, me.id, row),
        sharedHabits: shared,
        matchScore: score,
        reason: matchReason(shared.length, mutual),
      };
    })))
      // matchScore desc, then username asc - fully deterministic.
      .sort((a, b) => b.matchScore - a.matchScore || a.user.username.localeCompare(b.user.username))
      .slice(0, limit);

    sendJson(res, 200, { suggestions });
  }, { auth: true });
}
