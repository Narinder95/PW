// Simple in-memory, fixed-window rate limiting for auth endpoints.
//
// In-memory is fine here: Render's free tier runs a single instance, so
// there is no multi-process state to share. If this ever moves to more than
// one instance, this needs to move to a shared store (Postgres, Redis) or
// the limits become per-instance instead of global.
import { ApiError } from './http.js';

/**
 * One limiter's worth of state. Scoped per server instance (held on `ctx`,
 * the same way `db`/`hub`/`push` are) rather than a bare module-level
 * singleton - every test file spins up its own server on 127.0.0.1, and a
 * shared global map would let one file's login/register attempts trip
 * another's limit.
 */
export function createRateLimiter() {
  const buckets = new Map(); // key -> { count, resetAt }

  // Sweeps expired buckets so a long-running process doesn't accumulate one
  // entry per IP forever. Unref'd so it never keeps the process alive on its
  // own, matching the pattern SseHub's ping timer already uses.
  const sweepTimer = setInterval(() => {
    const now = Date.now();
    for (const [key, bucket] of buckets) {
      if (now >= bucket.resetAt) buckets.delete(key);
    }
  }, 10 * 60 * 1000);
  if (typeof sweepTimer.unref === 'function') sweepTimer.unref();

  return {
    /**
     * Throws `ApiError.rateLimited` once `key` has been called `max` times
     * within `windowMs`. Each distinct key (e.g. `login:<ip>`) tracks its
     * own window, independent of every other key.
     */
    check(key, { max, windowMs }) {
      const now = Date.now();
      const bucket = buckets.get(key);
      if (!bucket || now >= bucket.resetAt) {
        buckets.set(key, { count: 1, resetAt: now + windowMs });
        return;
      }
      if (bucket.count >= max) {
        const retryAfterSeconds = Math.max(1, Math.ceil((bucket.resetAt - now) / 1000));
        throw ApiError.rateLimited('Too many attempts. Try again later.', retryAfterSeconds);
      }
      bucket.count += 1;
    },
    close() {
      clearInterval(sweepTimer);
    },
  };
}

/**
 * The caller's IP, trusting `X-Forwarded-For` when present - Render (like
 * most PaaS) terminates TLS and proxies requests, so `req.socket` would
 * otherwise report the proxy's own address for every request.
 */
export function clientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.length > 0) {
    return forwarded.split(',')[0].trim();
  }
  return req.socket?.remoteAddress ?? 'unknown';
}
