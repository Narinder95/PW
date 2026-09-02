import { ApiError, sendJson, sendNoContent, parseLimit, parseBool, applyCors } from '../http.js';
import { notificationToJson } from '../domain.js';

const DEFAULT_LIMIT = 30;
const MAX_LIMIT = 100;

function unreadCount(db, userId) {
  return db.prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read = 0').get(userId).n;
}

/** Another user's notification must look like it does not exist at all. */
function ownNotificationOr404(db, id, userId) {
  const row = db.prepare('SELECT * FROM notifications WHERE id = ?').get(id);
  if (!row || row.user_id !== userId) throw ApiError.notFound('Notification not found');
  return row;
}

export function registerNotificationRoutes(router, ctx) {
  const { db, hub } = ctx;

  router.get('/api/notifications', async ({ res, url, me }) => {
    const limit = parseLimit(url.searchParams.get('limit'), DEFAULT_LIMIT, MAX_LIMIT);
    const unreadOnly = parseBool(url.searchParams.get('unreadOnly'));
    const sql = unreadOnly
      ? 'SELECT * FROM notifications WHERE user_id = ? AND read = 0 ORDER BY created_at DESC, rowid DESC LIMIT ?'
      : 'SELECT * FROM notifications WHERE user_id = ? ORDER BY created_at DESC, rowid DESC LIMIT ?';
    const notifications = db.prepare(sql).all(me.id, limit).map(notificationToJson);
    // unreadCount is always the caller's TOTAL unread, ignoring limit/unreadOnly.
    sendJson(res, 200, { notifications, unreadCount: unreadCount(db, me.id) });
  }, { auth: true });

  router.get('/api/notifications/unread-count', async ({ res, me }) => {
    sendJson(res, 200, { count: unreadCount(db, me.id) });
  }, { auth: true });

  router.post('/api/notifications/read-all', async ({ res, me }) => {
    const result = db.prepare('UPDATE notifications SET read = 1 WHERE user_id = ? AND read = 0').run(me.id);
    sendJson(res, 200, { updated: Number(result.changes) });
  }, { auth: true });

  router.post('/api/notifications/:id/read', async ({ res, params, me }) => {
    const row = ownNotificationOr404(db, params.id, me.id);
    db.prepare('UPDATE notifications SET read = 1 WHERE id = ?').run(row.id); // idempotent
    sendNoContent(res);
  }, { auth: true });

  router.delete('/api/notifications/:id', async ({ res, params, me }) => {
    const row = ownNotificationOr404(db, params.id, me.id);
    db.prepare('DELETE FROM notifications WHERE id = ?').run(row.id);
    sendNoContent(res);
  }, { auth: true });

  // SSE. `raw: true` -> this handler owns the response lifecycle.
  router.get('/api/notifications/stream', async ({ req, res, me }) => {
    applyCors(res);
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    if (typeof res.flushHeaders === 'function') res.flushHeaders();
    if (typeof req.socket?.setTimeout === 'function') req.socket.setTimeout(0);
    if (typeof req.socket?.setNoDelay === 'function') req.socket.setNoDelay(true);

    hub.subscribe(me.id, res);
    hub.write(res, 'ready', { ok: true });
  }, { auth: true, raw: true });
}
