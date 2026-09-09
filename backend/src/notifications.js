// Notification creation + the SSE hub.
//
// createNotification() is the single funnel for every notification in the app:
// it writes the row, publishes to any live SSE listeners, and enqueues a push.
import { newId, nowISO } from './http.js';
import { notificationToJson } from './domain.js';

const PING_INTERVAL_MS = 25_000;

/** Per-server hub of live SSE responses, keyed by user id. */
export class SseHub {
  constructor({ pingIntervalMs = PING_INTERVAL_MS, logger = console } = {}) {
    this.subscribers = new Map(); // userId -> Set<ServerResponse>
    this.pingIntervalMs = pingIntervalMs;
    this.logger = logger;
    this.timers = new Set();
    this.closed = false;
  }

  get size() {
    let n = 0;
    for (const set of this.subscribers.values()) n += set.size;
    return n;
  }

  countFor(userId) {
    return this.subscribers.get(userId)?.size ?? 0;
  }

  /** Attach an SSE response. Returns an unsubscribe function. */
  subscribe(userId, res) {
    let set = this.subscribers.get(userId);
    if (!set) {
      set = new Set();
      this.subscribers.set(userId, set);
    }
    set.add(res);

    const timer = setInterval(() => {
      this.write(res, 'ping', { t: nowISO() });
    }, this.pingIntervalMs);
    // unref() so a live stream timer never blocks process exit.
    if (typeof timer.unref === 'function') timer.unref();
    this.timers.add(timer);

    const cleanup = () => {
      clearInterval(timer);
      this.timers.delete(timer);
      const s = this.subscribers.get(userId);
      if (s) {
        s.delete(res);
        if (s.size === 0) this.subscribers.delete(userId);
      }
    };
    res.on('close', cleanup);
    res.on('error', cleanup);
    return cleanup;
  }

  write(res, event, data) {
    if (res.writableEnded || res.destroyed) return false;
    try {
      res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      return true;
    } catch {
      return false;
    }
  }

  publish(userId, notificationJson) {
    const set = this.subscribers.get(userId);
    if (!set || set.size === 0) return 0;
    let delivered = 0;
    for (const res of [...set]) {
      if (this.write(res, 'notification', notificationJson)) delivered += 1;
    }
    return delivered;
  }

  closeAll() {
    this.closed = true;
    for (const timer of this.timers) clearInterval(timer);
    this.timers.clear();
    for (const set of this.subscribers.values()) {
      for (const res of [...set]) {
        try {
          res.end();
        } catch {
          /* already gone */
        }
      }
    }
    this.subscribers.clear();
  }
}

/**
 * Create a notification for one user.
 *
 * @param {{db: object, hub: SseHub, push?: object, logger?: object}} ctx
 * @returns {object} the Notification in contract shape
 */
export async function createNotification(ctx, params) {
  const {
    userId,
    type,
    title,
    body = '',
    actorId = null,
    actorName = null,
    avatarColor = null,
    icon = null,
    color = null,
    refType = null,
    refId = null,
  } = params;

  const row = {
    id: params.id ?? newId('nt'), // `id` is only passed by the seeder
    user_id: userId,
    type,
    title,
    body,
    actor_id: actorId,
    actor_name: actorName,
    avatar_color: avatarColor,
    icon,
    color,
    ref_type: refType,
    ref_id: refId,
    read: 0,
    created_at: nowISO(),
  };

  await ctx.db
    .prepare(
      `INSERT INTO notifications
         (id, user_id, type, title, body, actor_id, actor_name, avatar_color,
          icon, color, ref_type, ref_id, read, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`
    )
    .run(
      row.id, row.user_id, row.type, row.title, row.body, row.actor_id, row.actor_name,
      row.avatar_color, row.icon, row.color, row.ref_type, row.ref_id, row.created_at
    );

  const json = notificationToJson(row);

  // Neither of the fan-outs below may break the API call that got us here.
  try {
    ctx.hub?.publish(userId, json);
  } catch (err) {
    (ctx.logger ?? console).error('[sse] publish failed:', err?.message ?? err);
  }
  try {
    ctx.push?.dispatch(row);
  } catch (err) {
    (ctx.logger ?? console).error('[push] dispatch failed:', err?.message ?? err);
  }

  return json;
}
