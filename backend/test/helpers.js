// Test harness: an in-memory DB + a real http.Server on an ephemeral port.
import { openDb } from '../src/db.js';
import { createServer } from '../src/server.js';
import { MemoryProvider } from '../src/push/providers.js';

/** Swallows expected server-side logging so intentional-error tests stay quiet. */
export function captureLogger() {
  const lines = { log: [], warn: [], error: [] };
  return {
    lines,
    log: (...a) => lines.log.push(a.join(' ')),
    warn: (...a) => lines.warn.push(a.join(' ')),
    error: (...a) => lines.error.push(a.map(String).join(' ')),
  };
}

export async function makeApp(options = {}) {
  const db = openDb(':memory:');
  const provider = options.provider ?? new MemoryProvider();
  const logger = options.logger ?? captureLogger();
  const server = createServer(db, {
    pushProvider: provider,
    // Tiny backoff so retry tests do not take 5 real seconds.
    retryDelays: options.retryDelays ?? [1, 2],
    logger,
    pingIntervalMs: options.pingIntervalMs ?? 25_000,
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;

  async function api(method, path, { token = null, body = undefined, headers = {} } = {}) {
    const h = { ...headers };
    if (token) h.Authorization = `Bearer ${token}`;
    if (body !== undefined) h['Content-Type'] = 'application/json';
    const res = await fetch(base + path, {
      method,
      headers: h,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await res.text();
    let parsed = null;
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = text;
      }
    }
    return { status: res.status, body: parsed, headers: res.headers };
  }

  const app = {
    db,
    server,
    provider,
    logger,
    base,
    api,
    get: (p, o) => api('GET', p, o),
    post: (p, o) => api('POST', p, o),
    patch: (p, o) => api('PATCH', p, o),
    del: (p, o) => api('DELETE', p, o),
    push: server.push,
    hub: server.hub,
    async close() {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(resolve));
      try {
        db.close();
      } catch {
        /* already closed */
      }
    },
  };
  return app;
}

let seq = 0;

/** Register a throwaway user and return { token, user, ...helpers }. */
export async function makeUser(app, overrides = {}) {
  seq += 1;
  const username = overrides.username ?? `u${seq}z${Date.now().toString(36)}`;
  const payload = {
    username,
    name: overrides.name ?? `User ${seq}`,
    email: overrides.email ?? `${username}@example.com`,
    password: overrides.password ?? 'password123',
  };
  const res = await app.post('/api/auth/register', { body: payload });
  if (res.status !== 201) throw new Error(`register failed: ${JSON.stringify(res.body)}`);
  const token = res.body.token;
  return {
    token,
    user: res.body.user,
    id: res.body.user.id,
    username: res.body.user.username,
    password: payload.password,
    email: payload.email,
    get: (p, o = {}) => app.get(p, { token, ...o }),
    post: (p, o = {}) => app.post(p, { token, ...o }),
    patch: (p, o = {}) => app.patch(p, { token, ...o }),
    del: (p, o = {}) => app.del(p, { token, ...o }),
  };
}

/** Make two users friends via the real request/accept flow. */
export async function befriend(a, b) {
  const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
  if (sent.status !== 201) throw new Error(`request failed: ${JSON.stringify(sent.body)}`);
  const accepted = await b.post(`/api/friend-requests/${sent.body.request.id}/accept`);
  if (accepted.status !== 200) throw new Error(`accept failed: ${JSON.stringify(accepted.body)}`);
  return sent.body.request.id;
}

export async function addHabit(user, habit) {
  const res = await user.post('/api/habits', { body: habit });
  if (res.status !== 201) throw new Error(`habit failed: ${JSON.stringify(res.body)}`);
  return res.body.habit;
}

/** YYYY-MM-DD offsets from today (UTC), matching the server's day boundary. */
export function dayOffset(n) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
