import test from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser } from './helpers.js';
import { hashPassword, verifyPassword } from '../src/auth.js';

test('auth', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('health needs no auth and reports the push provider', async () => {
    const res = await app.get('/api/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.version, '1');
    assert.equal(res.body.pushProvider, 'memory');
    assert.ok(res.body.time);
  });

  await t.test('register happy path returns 201 + token + user', async () => {
    const res = await app.post('/api/auth/register', {
      body: { username: 'AlexR', name: 'Alex Rivera', email: 'Alex@Example.com', password: 'password123' },
    });
    assert.equal(res.status, 201);
    assert.equal(typeof res.body.token, 'string');
    assert.equal(res.body.token.length, 64); // 32 random bytes, hex
    assert.equal(res.body.user.username, 'alexr'); // lowercased server-side
    assert.equal(res.body.user.name, 'Alex Rivera');
    assert.match(res.body.user.avatarColor, /^#[0-9A-F]{6}$/);
    assert.ok(res.body.user.createdAt);
    assert.equal(res.body.user.password, undefined);
    assert.equal(res.body.user.passwordHash, undefined);
  });

  await t.test('duplicate username -> 409', async () => {
    const res = await app.post('/api/auth/register', {
      body: { username: 'alexr', name: 'Other', email: 'other@example.com', password: 'password123' },
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'conflict');
  });

  await t.test('duplicate email -> 409', async () => {
    const res = await app.post('/api/auth/register', {
      body: { username: 'alexr2', name: 'Other', email: 'alex@example.com', password: 'password123' },
    });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'conflict');
  });

  await t.test('short password -> 400 with field', async () => {
    const res = await app.post('/api/auth/register', {
      body: { username: 'shorty', name: 'S', email: 's@example.com', password: 'short' },
    });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'validation_error');
    assert.equal(res.body.error.field, 'password');
  });

  await t.test('bad username charset -> 400', async () => {
    for (const username of ['bad name', 'Bad-Name!', 'ab', 'x'.repeat(21), 'hé']) {
      const res = await app.post('/api/auth/register', {
        body: { username, name: 'N', email: `${Math.random()}@example.com`.replace('0.', ''), password: 'password123' },
      });
      assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(username)}`);
      assert.equal(res.body.error.field, 'username');
    }
  });

  await t.test('email without @ -> 400, name too long -> 400', async () => {
    const noAt = await app.post('/api/auth/register', {
      body: { username: 'noat', name: 'N', email: 'nope', password: 'password123' },
    });
    assert.equal(noAt.status, 400);
    assert.equal(noAt.body.error.field, 'email');

    const longName = await app.post('/api/auth/register', {
      body: { username: 'longname', name: 'x'.repeat(41), email: 'ln@example.com', password: 'password123' },
    });
    assert.equal(longName.status, 400);
    assert.equal(longName.body.error.field, 'name');
  });

  await t.test('login by username', async () => {
    const res = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'alexr', password: 'password123' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.username, 'alexr');
    assert.equal(typeof res.body.token, 'string');
  });

  await t.test('login by email, case-insensitively', async () => {
    const res = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'ALEX@example.com', password: 'password123' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.username, 'alexr');
  });

  await t.test('wrong password -> 401', async () => {
    const res = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'alexr', password: 'not-the-password' },
    });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'unauthorized');
  });

  await t.test('unknown user -> 401 (same shape, no enumeration)', async () => {
    const res = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'ghost', password: 'password123' },
    });
    assert.equal(res.status, 401);
    assert.equal(res.body.error.message, 'Incorrect username or password');
  });

  await t.test('no token -> 401', async () => {
    const res = await app.get('/api/me');
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'unauthorized');
  });

  await t.test('garbage token -> 401', async () => {
    for (const token of ['nonsense', 'a'.repeat(64), '']) {
      const res = await app.get('/api/me', { token: token || undefined, headers: token ? {} : { Authorization: 'Bearer' } });
      assert.equal(res.status, 401);
    }
  });

  await t.test('GET /api/me includes email; PATCH updates name and colour', async () => {
    const login = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'alexr', password: 'password123' },
    });
    const token = login.body.token;

    const me = await app.get('/api/me', { token });
    assert.equal(me.status, 200);
    assert.equal(me.body.user.email, 'alex@example.com');

    const patched = await app.patch('/api/me', { token, body: { name: 'Alex R.', avatarColor: '#a855f7' } });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.user.name, 'Alex R.');
    assert.equal(patched.body.user.avatarColor, '#A855F7');

    const badColor = await app.patch('/api/me', { token, body: { avatarColor: 'purple' } });
    assert.equal(badColor.status, 400);
    assert.equal(badColor.body.error.field, 'avatarColor');
  });

  await t.test('logout invalidates the token', async () => {
    const login = await app.post('/api/auth/login', {
      body: { usernameOrEmail: 'alexr', password: 'password123' },
    });
    const token = login.body.token;
    assert.equal((await app.get('/api/me', { token })).status, 200);

    const out = await app.post('/api/auth/logout', { token });
    assert.equal(out.status, 204);

    assert.equal((await app.get('/api/me', { token })).status, 401);
  });

  await t.test('logout only kills the token used, not every session', async () => {
    const a = await app.post('/api/auth/login', { body: { usernameOrEmail: 'alexr', password: 'password123' } });
    const b = await app.post('/api/auth/login', { body: { usernameOrEmail: 'alexr', password: 'password123' } });
    await app.post('/api/auth/logout', { token: a.body.token });
    assert.equal((await app.get('/api/me', { token: a.body.token })).status, 401);
    assert.equal((await app.get('/api/me', { token: b.body.token })).status, 200);
  });

  await t.test('malformed JSON body -> 400, not 500', async () => {
    const res = await fetch(`${app.base}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{not json',
    });
    assert.equal(res.status, 400);
    const body = await res.json();
    assert.equal(body.error.code, 'validation_error');
  });

  await t.test('unknown route -> 404 envelope', async () => {
    const res = await app.get('/api/nope');
    assert.equal(res.status, 404);
    assert.equal(res.body.error.code, 'not_found');
  });

  await t.test('CORS preflight is answered', async () => {
    const res = await fetch(`${app.base}/api/habits`, { method: 'OPTIONS' });
    assert.equal(res.status, 204);
    assert.equal(res.headers.get('access-control-allow-origin'), '*');
    assert.ok(res.headers.get('access-control-allow-headers').includes('Authorization'));
  });
});

test('password hashing', async (t) => {
  await t.test('salted: the same password hashes differently each time', () => {
    const a = hashPassword('password123');
    const b = hashPassword('password123');
    assert.notEqual(a, b);
    assert.match(a, /^[0-9a-f]{32}:[0-9a-f]{128}$/);
    assert.ok(verifyPassword('password123', a));
    assert.ok(verifyPassword('password123', b));
  });

  await t.test('rejects wrong passwords and malformed hashes', () => {
    const stored = hashPassword('password123');
    assert.equal(verifyPassword('password124', stored), false);
    assert.equal(verifyPassword('', stored), false);
    assert.equal(verifyPassword('x', 'garbage'), false);
    assert.equal(verifyPassword('x', ''), false);
    assert.equal(verifyPassword('x', null), false);
  });

  await t.test('plaintext never reaches the users table', async () => {
    const app = await makeApp();
    try {
      const u = await makeUser(app, { password: 'sup3rSecretValue' });
      const row = app.db.prepare('SELECT * FROM users WHERE id = ?').get(u.id);
      assert.ok(!JSON.stringify(row).includes('sup3rSecretValue'));
      assert.match(row.password_hash, /^[0-9a-f]{32}:[0-9a-f]{128}$/);
    } finally {
      await app.close();
    }
  });
});
