import { ApiError, sendJson, parseLimit } from '../http.js';
import { activityToJson } from '../domain.js';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

export function registerActivityRoutes(router, ctx) {
  const { db } = ctx;

  router.get('/api/activity', async ({ res, url, me }) => {
    const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT);
    const beforeRaw = url.searchParams.get('before');
    let before = null;
    if (beforeRaw) {
      const d = new Date(beforeRaw);
      if (Number.isNaN(d.getTime())) throw ApiError.validation('before must be an ISO-8601 timestamp', 'before');
      before = d.toISOString();
    }

    // Friends' activity only - never the caller's own.
    const sql = `
      SELECT a.*, u.name AS friend_name, u.avatar_color AS avatar_color
        FROM activities a
        JOIN friendships f ON f.friend_id = a.user_id AND f.user_id = ?
        JOIN users u ON u.id = a.user_id
       WHERE a.user_id != ?
         ${before ? 'AND a.created_at < ?' : ''}
       ORDER BY a.created_at DESC, a.seq DESC
       LIMIT ?`;
    const args = before ? [me.id, me.id, before, limit] : [me.id, me.id, limit];
    const rows = await db.prepare(sql).all(...args);
    sendJson(res, 200, { activities: rows.map(activityToJson) });
  }, { auth: true });
}
