// Provider selection + the dispatcher that fans a notification out to devices.
import { newId, nowISO } from '../http.js';
import { NoneProvider, LogProvider, MemoryProvider } from './providers.js';
import { FcmProvider, loadServiceAccount } from './fcm.js';

export { NoneProvider, LogProvider, MemoryProvider, FcmProvider, loadServiceAccount };

/**
 * Build the provider named by PUSH_PROVIDER. Never throws: a misconfigured
 * `fcm` provider logs a warning and degrades to `none` so the server still boots.
 */
export function createPushProvider(env = process.env, logger = console) {
  const name = String(env.PUSH_PROVIDER ?? 'none').trim().toLowerCase();
  switch (name) {
    case 'log':
      return new LogProvider(logger);
    case 'memory':
      return new MemoryProvider();
    case 'fcm': {
      const file = env.FCM_SERVICE_ACCOUNT_FILE;
      const projectId = env.FCM_PROJECT_ID;
      try {
        if (!file) throw new Error('FCM_SERVICE_ACCOUNT_FILE is not set');
        const serviceAccount = loadServiceAccount(file);
        return new FcmProvider({
          projectId: projectId || serviceAccount.project_id,
          serviceAccount,
          logger,
        });
      } catch (err) {
        logger.warn(
          `[push] PUSH_PROVIDER=fcm but credentials are unusable (${err.message}). ` +
            'Falling back to PUSH_PROVIDER=none. See docs/PUSH_SETUP.md.'
        );
        return new NoneProvider();
      }
    }
    case 'none':
      return new NoneProvider();
    default:
      logger.warn(`[push] unknown PUSH_PROVIDER "${name}", using "none".`);
      return new NoneProvider();
  }
}

const DEFAULT_RETRY_DELAYS = [1000, 4000]; // 2 retries after the first attempt

/**
 * Fans notifications out to a user's registered devices.
 *
 * Contract with the rest of the app: `dispatch()` is fire-and-forget and can
 * never throw or reject into the caller, so a push problem cannot fail the API
 * request that created the notification.
 */
export class PushDispatcher {
  constructor({ db, provider, logger = console, retryDelays = DEFAULT_RETRY_DELAYS }) {
    this.db = db;
    this.provider = provider;
    this.logger = logger;
    this.retryDelays = retryDelays;
    this.inFlight = new Set();
    this.closed = false;
  }

  /** Payload handed to the provider. All `data` values are strings (FCM requires it). */
  buildPayload(device, notification, badge) {
    const data = {
      notificationId: notification.id,
      type: notification.type,
    };
    // Nullable fields are omitted rather than stringified as "null".
    if (notification.ref_type != null) data.refType = String(notification.ref_type);
    if (notification.ref_id != null) data.refId = String(notification.ref_id);
    if (notification.actor_id != null) data.actorId = String(notification.actor_id);

    const collapseKey = notification.actor_id
      ? `${notification.type}:${notification.actor_id}`
      : notification.type;

    return {
      deviceToken: device.token,
      platform: device.platform,
      title: notification.title,
      body: notification.body,
      data,
      badge,
      collapseKey,
    };
  }

  async unreadCount(userId) {
    const row = await this.db
      .prepare('SELECT COUNT(*) AS n FROM notifications WHERE user_id = ? AND read = 0')
      .get(userId);
    return row ? Number(row.n) : 0;
  }

  /**
   * Enqueue one push per registered device of `notification.user_id`.
   *
   * Callers never `await` this - it stays a synchronous-looking, fire-and-
   * forget call (the bookkeeping below is genuinely async against Postgres,
   * but its own promise chain is caught right here so it can never reject
   * into, or block, the API request that created the notification).
   *
   * The bookkeeping promise is tracked in `inFlight` *synchronously*, before
   * any of it has actually run: `_dispatch` doesn't reach a `track()` call
   * for the individual per-device sends until after its own first `await`
   * (the device lookup) resolves, so without this, `idle()` called right
   * after `dispatch()` could see an empty `inFlight` and return immediately,
   * before the device lookup - let alone any send - had even started.
   */
  dispatch(notification) {
    if (this.closed) return;
    const bookkeeping = this._dispatch(notification).catch((err) => {
      this.logger.error('[push] dispatch bookkeeping failed:', err.message);
    });
    this.track(bookkeeping);
  }

  async _dispatch(notification) {
    const devices = await this.db
      .prepare('SELECT * FROM devices WHERE user_id = ? ORDER BY created_at ASC, id ASC')
      .all(notification.user_id);
    if (devices.length === 0) return; // clean no-op

    const badge = await this.unreadCount(notification.user_id);
    const insert = this.db.prepare(
      `INSERT INTO push_deliveries
         (id, user_id, device_id, notification_id, provider, status, error, created_at)
       VALUES (?, ?, ?, ?, ?, 'queued', NULL, ?)`
    );

    for (const device of devices) {
      const deliveryId = newId('pd');
      await insert.run(
        deliveryId,
        notification.user_id,
        device.id,
        notification.id,
        this.provider.name,
        nowISO()
      );
      const payload = this.buildPayload(device, notification, badge);
      this.track(this.deliver(deliveryId, device, payload));
    }
  }

  track(promise) {
    const p = promise
      .catch((err) => this.logger.error('[push] delivery crashed:', err?.message ?? err))
      .finally(() => this.inFlight.delete(p));
    this.inFlight.add(p);
  }

  /** Resolves once every queued send (including retries) has settled. */
  async idle() {
    while (this.inFlight.size > 0) {
      await Promise.allSettled([...this.inFlight]);
    }
  }

  async deliver(deliveryId, device, payload) {
    const attempts = this.retryDelays.length + 1;
    let last = { status: 'failed', error: 'not attempted' };

    for (let attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await this.sleep(this.retryDelays[attempt - 1]);
      if (this.closed) break;

      try {
        const result = await this.provider.send(payload);
        last = result && typeof result.status === 'string' ? result : { status: 'failed', error: 'bad provider result' };
      } catch (err) {
        // A provider that throws is treated exactly like a failed send.
        last = { status: 'failed', error: `provider threw: ${err?.message ?? err}` };
      }

      if (last.status === 'sent' || last.status === 'skipped' || last.status === 'invalid_token') break;
    }

    if (last.status === 'invalid_token') {
      // Dead token - self-clean so we stop pushing into the void.
      try {
        await this.db.prepare('DELETE FROM devices WHERE id = ?').run(device.id);
      } catch (err) {
        this.logger.error('[push] could not delete dead device:', err.message);
      }
    }

    await this.finish(deliveryId, last);
    return last;
  }

  async finish(deliveryId, result) {
    try {
      await this.db
        .prepare('UPDATE push_deliveries SET status = ?, error = ? WHERE id = ?')
        .run(result.status, result.error ?? null, deliveryId);
    } catch (err) {
      this.logger.error('[push] could not record delivery:', err.message);
    }
  }

  sleep(ms) {
    return new Promise((resolve) => {
      // unref()'d so a pending retry never keeps the process alive.
      const t = setTimeout(resolve, ms);
      if (typeof t.unref === 'function') t.unref();
    });
  }

  close() {
    this.closed = true;
  }
}
