// Accounts are provisioned with no credentials on first launch, and may later
// be claimed with an email and/or phone. There is no sign-up wall.
import test, { after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend, addHabit } from './helpers.js';

const apps = [];
async function app() {
  const a = await makeApp();
  apps.push(a);
  return a;
}
after(async () => {
  for (const a of apps) await a.close();
});

/** Provision an anonymous account and return a user-shaped helper. */
async function anon(a, body = {}) {
  const res = await a.post('/api/auth/anonymous', { body });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const token = res.body.token;
  return {
    token,
    user: res.body.user,
    id: res.body.user.id,
    get: (p, o = {}) => a.get(p, { token, ...o }),
    post: (p, o = {}) => a.post(p, { token, ...o }),
    patch: (p, o = {}) => a.patch(p, { token, ...o }),
    del: (p, o = {}) => a.del(p, { token, ...o }),
  };
}

describe('anonymous provisioning', () => {
  test('needs no credentials and returns a usable session', async () => {
    const a = await app();
    const res = await a.post('/api/auth/anonymous', { body: {} });

    assert.equal(res.status, 201);
    assert.equal(typeof res.body.token, 'string');
    assert.ok(res.body.token.length >= 32);

    const u = res.body.user;
    assert.equal(typeof u.id, 'string');
    assert.equal(typeof u.username, 'string');
    assert.equal(typeof u.name, 'string');
    assert.ok(u.name.length > 0, 'an auto account still needs a display name');
    assert.equal(u.email, null);
    assert.equal(u.phone, null);
    assert.equal(u.isAnonymous, true);
    assert.match(u.avatarColor, /^#[0-9A-Fa-f]{6}$/);

    // The token works immediately.
    const me = await a.get('/api/me', { token: res.body.token });
    assert.equal(me.status, 200);
    assert.equal(me.body.user.id, u.id);
  });

  test('no body at all is fine', async () => {
    const a = await app();
    const res = await a.post('/api/auth/anonymous');
    assert.equal(res.status, 201);
  });

  test('handles are unique across many accounts', async () => {
    const a = await app();
    const seen = new Set();
    for (let i = 0; i < 40; i++) {
      const res = await a.post('/api/auth/anonymous', { body: {} });
      assert.equal(res.status, 201);
      const name = res.body.user.username;
      assert.ok(!seen.has(name), `duplicate handle: ${name}`);
      assert.match(name, /^[a-z0-9_]{3,20}$/, `bad handle: ${name}`);
      seen.add(name);
    }
  });

  test('an optional display name is honoured', async () => {
    const a = await app();
    const res = await a.post('/api/auth/anonymous', { body: { name: 'Narinder' } });
    assert.equal(res.body.user.name, 'Narinder');
    // A junk name falls back rather than 400ing — provisioning must not fail.
    const junk = await a.post('/api/auth/anonymous', { body: { name: '   ' } });
    assert.equal(junk.status, 201);
    assert.ok(junk.body.user.name.length > 0);
  });

  test('an anonymous account is a first-class user everywhere', async () => {
    const a = await app();
    const me = await anon(a, { name: 'Anon Me' });
    const friend = await makeUser(a, { name: 'Registered' });

    // Habits.
    const habit = await addHabit(me, { name: 'Steps', target: 100, unit: 'steps' });
    await me.post(`/api/habits/${habit.id}/log`, { body: { progress: 100 } });
    assert.equal((await me.get('/api/habits')).body.habits[0].streak, 1);

    // Friending, in both directions.
    await befriend(me, friend);
    assert.equal((await me.get('/api/friends')).body.friends.length, 1);
    assert.equal((await friend.get('/api/friends')).body.friends.length, 1);

    // Discoverable by handle.
    const found = await friend.get(`/api/users/search?q=${me.user.username}`);
    assert.ok(found.body.users.some((u) => u.id === me.id));

    // Nudgeable and notifiable.
    const nudge = await friend.post('/api/nudges', {
      body: { toUserId: me.id, habitName: 'Steps' },
    });
    assert.equal(nudge.status, 201);
    assert.ok((await me.get('/api/notifications')).body.unreadCount > 0);
  });

  test('an anonymous account cannot be logged into by guessing its handle', async () => {
    const a = await app();
    const me = await anon(a);
    for (const password of ['', 'password123', 'x'.repeat(8)]) {
      const res = await a.post('/api/auth/login', {
        body: { usernameOrEmail: me.user.username, password },
      });
      assert.equal(res.status, res.status === 400 ? 400 : 401);
      assert.notEqual(res.status, 200, 'an unclaimed account must not be reachable by login');
    }
  });
});

describe('claiming an account', () => {
  test('link with an email, then log in with it from a "new device"', async () => {
    const a = await app();
    const me = await anon(a);
    const originalId = me.id;

    const linked = await me.post('/api/auth/link', {
      body: { email: 'Me@Example.com', password: 'hunter2hunter2' },
    });
    assert.equal(linked.status, 200, JSON.stringify(linked.body));
    assert.equal(linked.body.user.id, originalId, 'claiming must not create a new account');
    assert.equal(linked.body.user.email, 'me@example.com', 'email should be lowercased');
    assert.equal(linked.body.user.isAnonymous, false);

    // A fresh session, as a reinstall would do.
    const login = await a.post('/api/auth/login', {
      body: { usernameOrEmail: 'me@example.com', password: 'hunter2hunter2' },
    });
    assert.equal(login.status, 200);
    assert.equal(login.body.user.id, originalId, 'logged into a different account!');
  });

  test('link with a phone, and log in by phone', async () => {
    const a = await app();
    const me = await anon(a);

    const linked = await me.post('/api/auth/link', {
      body: { phone: '+91 98765 43210', password: 'hunter2hunter2' },
    });
    assert.equal(linked.status, 200);
    assert.equal(linked.body.user.phone, '+919876543210', 'phone should be normalised');
    assert.equal(linked.body.user.email, null);
    assert.equal(linked.body.user.isAnonymous, false);

    const login = await a.post('/api/auth/login', {
      body: { usernameOrEmail: '+91 98765 43210', password: 'hunter2hunter2' },
    });
    assert.equal(login.status, 200);
    assert.equal(login.body.user.id, me.id);
  });

  test('everything the account owned survives the claim', async () => {
    const a = await app();
    const me = await anon(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    const habit = await addHabit(me, { name: 'Water', target: 8, unit: 'cups' });
    await me.post(`/api/habits/${habit.id}/log`, { body: { progress: 8 } });

    await me.post('/api/auth/link', {
      body: { email: 'keeps@example.com', password: 'hunter2hunter2' },
    });

    assert.equal((await me.get('/api/friends')).body.friends.length, 1);
    const habits = (await me.get('/api/habits')).body.habits;
    assert.equal(habits.length, 1);
    assert.equal(habits[0].progress, 8);
  });

  test('the existing session keeps working after linking', async () => {
    const a = await app();
    const me = await anon(a);
    await me.post('/api/auth/link', {
      body: { email: 'still@example.com', password: 'hunter2hunter2' },
    });
    assert.equal((await me.get('/api/me')).status, 200);
  });

  test('a handle can be chosen at claim time', async () => {
    const a = await app();
    const me = await anon(a);
    const res = await me.post('/api/auth/link', {
      body: { email: 'h@example.com', password: 'hunter2hunter2', username: 'narinder' },
    });
    assert.equal(res.status, 200);
    assert.equal(res.body.user.username, 'narinder');

    const login = await a.post('/api/auth/login', {
      body: { usernameOrEmail: 'narinder', password: 'hunter2hunter2' },
    });
    assert.equal(login.status, 200);
  });

  test('rejects a taken email, phone, or handle without altering the account', async () => {
    const a = await app();
    const taken = await makeUser(a, { username: 'takenname', email: 'taken@example.com' });
    const me = await anon(a);

    const dupEmail = await me.post('/api/auth/link', {
      body: { email: 'taken@example.com', password: 'hunter2hunter2' },
    });
    assert.equal(dupEmail.status, 409);

    const dupHandle = await me.post('/api/auth/link', {
      body: { email: 'fresh@example.com', password: 'hunter2hunter2', username: 'takenname' },
    });
    assert.equal(dupHandle.status, 409);

    // Still anonymous and still usable.
    const meNow = await me.get('/api/me');
    assert.equal(meNow.body.user.isAnonymous, true);
    assert.equal(meNow.body.user.email, null);
    assert.ok(taken.id);
  });

  test('validation: needs a password, needs email or phone, rejects junk', async () => {
    const a = await app();
    const me = await anon(a);

    assert.equal((await me.post('/api/auth/link', { body: {} })).status, 400);
    assert.equal(
      (await me.post('/api/auth/link', { body: { password: 'hunter2hunter2' } })).status,
      400,
      'neither email nor phone supplied'
    );
    assert.equal(
      (await me.post('/api/auth/link', { body: { email: 'a@b.com', password: 'short' } })).status,
      400
    );
    assert.equal(
      (await me.post('/api/auth/link', { body: { email: 'not-an-email', password: 'hunter2hunter2' } })).status,
      400
    );
    assert.equal(
      (await me.post('/api/auth/link', { body: { phone: '123', password: 'hunter2hunter2' } })).status,
      400
    );
  });

  test('an already-claimed account cannot be re-claimed', async () => {
    const a = await app();
    const me = await anon(a);
    await me.post('/api/auth/link', {
      body: { email: 'once@example.com', password: 'hunter2hunter2' },
    });
    const again = await me.post('/api/auth/link', {
      body: { email: 'twice@example.com', password: 'hunter2hunter2' },
    });
    assert.equal(again.status, 409);
  });

  test('linking requires auth', async () => {
    const a = await app();
    const res = await a.post('/api/auth/link', {
      body: { email: 'x@y.com', password: 'hunter2hunter2' },
    });
    assert.equal(res.status, 401);
  });
});

describe('schema v2 migration', () => {
  test('a v1 database is rebuilt with the new columns and existing users preserved', async () => {
    const { DatabaseSync } = await import('node:sqlite');
    const { migrate } = await import('../src/db.js');

    // Hand-build the v1 users table, exactly as it was.
    const db = new DatabaseSync(':memory:');
    db.exec(`
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        avatar_color TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_active_at TEXT NOT NULL
      );
      INSERT INTO meta (key, value) VALUES ('schema_version', '1');
      INSERT INTO users VALUES
        ('u_1','olduser','Old User','old@example.com','salt:hash','#2DD4BF','2026-01-01','2026-01-01');
    `);

    migrate(db);

    const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
    assert.ok(columns.includes('phone'), 'phone column missing after migration');
    assert.ok(columns.includes('is_anonymous'), 'is_anonymous column missing');

    const row = db.prepare('SELECT * FROM users WHERE id = ?').get('u_1');
    assert.equal(row.username, 'olduser');
    assert.equal(row.email, 'old@example.com');
    assert.equal(row.password_hash, 'salt:hash');
    assert.equal(row.is_anonymous, 0, 'a pre-existing credentialed user is not anonymous');

    // An anonymous row is now insertable where v1 would have rejected the NULLs.
    db.prepare(
      `INSERT INTO users (id, username, name, email, phone, password_hash, is_anonymous,
                          avatar_color, created_at, last_active_at)
       VALUES ('u_2','anon_one','Anon One',NULL,NULL,NULL,1,'#A855F7','2026-01-02','2026-01-02')`
    ).run();
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 2);

    // Re-running is a no-op.
    migrate(db);
    assert.equal(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 2);
    db.close();
  });
});
