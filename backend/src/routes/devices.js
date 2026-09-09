import { ApiError, sendJson, sendNoContent, newId, nowISO, requireString, optionalString } from '../http.js';
import { UNIQUE_VIOLATION } from '../db.js';

const PLATFORMS = new Set(['android', 'ios', 'web']);

function deviceToJson(row) {
  return {
    id: row.id,
    token: row.token,
    platform: row.platform,
    appVersion: row.app_version ?? null,
    createdAt: row.created_at,
    lastSeenAt: row.last_seen_at,
  };
}

export function registerDeviceRoutes(router, ctx) {
  const { db } = ctx;

  router.post('/api/devices', async ({ res, body, me }) => {
    const token = requireString(body, 'token', { min: 1, max: 4096 });
    const platformRaw = requireString(body, 'platform', { min: 1, max: 20 }).toLowerCase();
    if (!PLATFORMS.has(platformRaw)) {
      throw ApiError.validation("platform must be 'android', 'ios' or 'web'", 'platform');
    }
    const appVersion = optionalString(body, 'appVersion', { max: 40 });
    const at = nowISO();

    const existing = await db.prepare('SELECT * FROM devices WHERE token = ?').get(token);
    if (existing) {
      // Idempotent re-registration; also REASSIGNS the handset if it now
      // belongs to a different account, so the previous user stops getting
      // this device's pushes.
      await db.prepare('UPDATE devices SET user_id = ?, platform = ?, app_version = ?, last_seen_at = ? WHERE id = ?')
        .run(me.id, platformRaw, appVersion, at, existing.id);
      const fresh = await db.prepare('SELECT * FROM devices WHERE id = ?').get(existing.id);
      sendJson(res, 201, { device: deviceToJson(fresh) });
      return;
    }

    const row = {
      id: newId('d'),
      user_id: me.id,
      token,
      platform: platformRaw,
      app_version: appVersion,
      created_at: at,
      last_seen_at: at,
    };
    try {
      await db.prepare(
        `INSERT INTO devices (id, user_id, token, platform, app_version, created_at, last_seen_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).run(row.id, row.user_id, row.token, row.platform, row.app_version, row.created_at, row.last_seen_at);
    } catch (err) {
      if (err?.code === UNIQUE_VIOLATION) {
        // Lost a race with another registration of the same brand-new token
        // (the pre-check above found nothing yet) - reassign it, same as the
        // `existing` branch above, rather than surface a 500 for what is
        // really just the idempotent re-registration path.
        await db.prepare('UPDATE devices SET user_id = ?, platform = ?, app_version = ?, last_seen_at = ? WHERE token = ?')
          .run(me.id, platformRaw, appVersion, at, token);
        const fresh = await db.prepare('SELECT * FROM devices WHERE token = ?').get(token);
        sendJson(res, 201, { device: deviceToJson(fresh) });
        return;
      }
      throw err;
    }

    sendJson(res, 201, { device: deviceToJson(row) });
  }, { auth: true });

  router.delete('/api/devices/:token', async ({ res, params, me }) => {
    // Called on logout. Idempotent: unknown tokens still return 204.
    await db.prepare('DELETE FROM devices WHERE user_id = ? AND token = ?').run(me.id, params.token);
    sendNoContent(res);
  }, { auth: true });
}
