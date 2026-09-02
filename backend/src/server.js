// createServer(db) -> http.Server. Everything is injectable so tests can run
// against an in-memory DB, a MemoryProvider and port 0.
import http from 'node:http';
import { ApiError, applyCors, readJson, sendJson, sendError, nowISO } from './http.js';
import { Router } from './router.js';
import { authenticate, registerAuthRoutes } from './auth.js';
import { SseHub } from './notifications.js';
import { createPushProvider, PushDispatcher } from './push/index.js';
import { registerHabitRoutes } from './routes/habits.js';
import { registerFriendRoutes } from './routes/friends.js';
import { registerRequestRoutes } from './routes/requests.js';
import { registerNudgeRoutes } from './routes/nudges.js';
import { registerNotificationRoutes } from './routes/notifications.js';
import { registerMatchRoutes } from './routes/match.js';
import { registerActivityRoutes } from './routes/activity.js';
import { registerDeviceRoutes } from './routes/devices.js';

export const API_VERSION = '1';

/**
 * @param {object} db  an open node:sqlite DatabaseSync
 * @param {object} [options]
 * @param {object} [options.pushProvider]  overrides PUSH_PROVIDER selection
 * @param {number[]} [options.retryDelays] push retry backoff (ms)
 */
export function createServer(db, options = {}) {
  const logger = options.logger ?? console;
  const hub = new SseHub({ pingIntervalMs: options.pingIntervalMs, logger });
  const provider = options.pushProvider ?? createPushProvider(options.env ?? process.env, logger);
  const push = new PushDispatcher({
    db,
    provider,
    logger,
    ...(options.retryDelays ? { retryDelays: options.retryDelays } : {}),
  });

  const ctx = { db, hub, push, provider, logger };
  const router = new Router();

  router.get('/api/health', async ({ res }) => {
    sendJson(res, 200, { ok: true, version: API_VERSION, time: nowISO(), pushProvider: provider.name });
  });

  registerAuthRoutes(router, ctx);
  registerHabitRoutes(router, ctx);
  registerFriendRoutes(router, ctx);
  registerRequestRoutes(router, ctx);
  registerNudgeRoutes(router, ctx);
  registerNotificationRoutes(router, ctx);
  registerMatchRoutes(router, ctx);
  registerActivityRoutes(router, ctx);
  registerDeviceRoutes(router, ctx);

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      // Last line of defence - handle() already catches, but never crash.
      logger.error('[http] unhandled:', err);
      if (!res.headersSent) sendError(res, ApiError.internal());
      else res.end();
    });
  });

  async function handle(req, res) {
    applyCors(res);

    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      res.end();
      return;
    }

    let url;
    try {
      url = new URL(req.url, 'http://localhost');
    } catch {
      return sendError(res, ApiError.validation('Malformed request URL'));
    }

    const { route, handler, params, allowed } = router.match(req.method, url.pathname);

    if (!handler) {
      if (allowed.size > 0) {
        res.setHeader('Allow', [...allowed].join(', '));
        return sendError(res, new ApiError(404, 'not_found', `${req.method} is not supported on ${url.pathname}`));
      }
      return sendError(res, ApiError.notFound(`No route for ${req.method} ${url.pathname}`));
    }

    try {
      let me = null;
      let token = null;
      if (route.auth) {
        const authed = authenticate(db, req, url);
        me = authed.user;
        token = authed.token;
      }

      const body = route.raw ? {} : await readJson(req);
      await handler({ req, res, url, params, body, me, token, ctx, db });

      // A handler that returned without writing anything is a bug; surface it
      // as a 500 rather than hanging the socket.
      if (!route.raw && !res.headersSent) {
        logger.error(`[http] handler for ${route.pattern} wrote no response`);
        sendError(res, ApiError.internal());
      }
    } catch (err) {
      if (err instanceof ApiError) {
        if (!res.headersSent) sendError(res, err);
        else res.end();
        return;
      }
      // Unexpected: log the full stack server-side, tell the client nothing.
      logger.error(`[http] ${req.method} ${url.pathname} failed:`, err);
      if (!res.headersSent) sendError(res, ApiError.internal());
      else res.end();
    }
  }

  server.on('close', () => {
    hub.closeAll();
    push.close();
  });

  // Exposed for tests and for index.js.
  server.ctx = ctx;
  server.hub = hub;
  server.push = push;
  server.provider = provider;
  server.router = router;
  return server;
}
