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

/** Give A a few notifications by having B do things to them. */
async function seedNotifications(a) {
  const me = await makeUser(a, { name: 'Me' });
  const friend = await makeUser(a, { name: 'Buddy' });
  await befriend(me, friend); // -> me gets friend_request? no: me sent it. see below
  // befriend() has `me` send and `friend` accept, so ME gets friend_request_accepted.
  await friend.post('/api/nudges', { body: { toUserId: me.id, habitName: 'Water' } });
  await friend.post('/api/nudges', { body: { toUserId: me.id, habitName: 'Steps' } });
  return { me, friend };
}

describe('notifications', () => {
  test('list is newest-first and unreadCount is accurate', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);

    const res = await me.get('/api/notifications');
    assert.equal(res.status, 200);
    const list = res.body.notifications;
    assert.ok(list.length >= 3, `expected >= 3 notifications, got ${list.length}`);

    const times = list.map((n) => new Date(n.createdAt).getTime());
    const sorted = [...times].sort((x, y) => y - x);
    assert.deepEqual(times, sorted, 'notifications are not newest-first');

    assert.equal(res.body.unreadCount, list.filter((n) => !n.read).length);
  });

  test('unread-count endpoint agrees with the list', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const list = await me.get('/api/notifications');
    const count = await me.get('/api/notifications/unread-count');
    assert.equal(count.status, 200);
    assert.equal(count.body.count, list.body.unreadCount);
  });

  test('unreadCount is a total, independent of limit and unreadOnly', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const full = await me.get('/api/notifications');
    const limited = await me.get('/api/notifications?limit=1');
    assert.equal(limited.body.notifications.length, 1);
    assert.equal(limited.body.unreadCount, full.body.unreadCount);

    const unreadOnly = await me.get('/api/notifications?unreadOnly=true');
    assert.ok(unreadOnly.body.notifications.every((n) => n.read === false));
    assert.equal(unreadOnly.body.unreadCount, full.body.unreadCount);
  });

  test('mark read is idempotent and moves the count', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const before = (await me.get('/api/notifications/unread-count')).body.count;
    const target = (await me.get('/api/notifications')).body.notifications.find((n) => !n.read);
    assert.ok(target, 'need an unread notification');

    assert.equal((await me.post(`/api/notifications/${target.id}/read`)).status, 204);
    assert.equal((await me.get('/api/notifications/unread-count')).body.count, before - 1);

    // Second call changes nothing.
    assert.equal((await me.post(`/api/notifications/${target.id}/read`)).status, 204);
    assert.equal((await me.get('/api/notifications/unread-count')).body.count, before - 1);
  });

  test('read-all zeroes the count and reports how many it changed', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const before = (await me.get('/api/notifications/unread-count')).body.count;
    assert.ok(before > 0);

    const res = await me.post('/api/notifications/read-all');
    assert.equal(res.status, 200);
    assert.equal(res.body.updated, before);
    assert.equal((await me.get('/api/notifications/unread-count')).body.count, 0);

    // Idempotent: nothing left to update.
    assert.equal((await me.post('/api/notifications/read-all')).body.updated, 0);
  });

  test('delete removes it from the list', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const list = (await me.get('/api/notifications')).body.notifications;
    const victim = list[0];

    assert.equal((await me.del(`/api/notifications/${victim.id}`)).status, 204);
    const after = (await me.get('/api/notifications')).body.notifications;
    assert.ok(!after.some((n) => n.id === victim.id));
    assert.equal(after.length, list.length - 1);
  });

  test("another user's notification is 404, not 403 - existence is not confirmed", async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const outsider = await makeUser(a);
    const mine = (await me.get('/api/notifications')).body.notifications[0];

    assert.equal((await outsider.post(`/api/notifications/${mine.id}/read`)).status, 404);
    assert.equal((await outsider.del(`/api/notifications/${mine.id}`)).status, 404);
    // And it is untouched.
    const still = (await me.get('/api/notifications')).body.notifications;
    assert.ok(still.some((n) => n.id === mine.id));
  });

  test('unknown notification id -> 404', async () => {
    const a = await app();
    const me = await makeUser(a);
    assert.equal((await me.post('/api/notifications/nt_nope/read')).status, 404);
    assert.equal((await me.del('/api/notifications/nt_nope')).status, 404);
  });

  test('limit clamps to 100 and rejects nonsense', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    const big = await me.get('/api/notifications?limit=99999');
    assert.equal(big.status, 200);
    assert.ok(big.body.notifications.length <= 100);

    const zero = await me.get('/api/notifications?limit=0');
    assert.ok([200, 400].includes(zero.status));
    const junk = await me.get('/api/notifications?limit=abc');
    assert.ok([200, 400].includes(junk.status));
  });

  test('a fresh user has an empty list and a zero count', async () => {
    const a = await app();
    const lonely = await makeUser(a);
    const res = await lonely.get('/api/notifications');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.notifications, []);
    assert.equal(res.body.unreadCount, 0);
  });

  test('every notification carries the fields the client renders', async () => {
    const a = await app();
    const { me } = await seedNotifications(a);
    for (const n of (await me.get('/api/notifications')).body.notifications) {
      assert.equal(typeof n.id, 'string');
      assert.equal(typeof n.type, 'string');
      assert.equal(typeof n.title, 'string');
      assert.equal(typeof n.body, 'string');
      assert.equal(typeof n.read, 'boolean');
      assert.ok(!Number.isNaN(Date.parse(n.createdAt)), `bad createdAt: ${n.createdAt}`);
      // Nullable, but the key must exist so the client never sees `undefined`.
      for (const k of ['actorId', 'actorName', 'avatarColor', 'icon', 'color', 'refType', 'refId']) {
        assert.ok(k in n, `missing key ${k}`);
      }
    }
  });

  test('completing a habit notifies friends but never yourself', async () => {
    const a = await app();
    const me = await makeUser(a, { name: 'Doer' });
    const watcher = await makeUser(a);
    await befriend(me, watcher);
    await watcher.post('/api/notifications/read-all');

    const habit = await addHabit(me, { name: 'Steps', target: 100, unit: 'steps' });
    await me.post(`/api/habits/${habit.id}/log`, { body: { progress: 100 } });

    const theirs = (await watcher.get('/api/notifications')).body.notifications;
    assert.ok(
      theirs.some((n) => n.type === 'friend_activity' && n.actorId === me.id),
      'friend should have been notified'
    );

    const mine = (await me.get('/api/notifications')).body.notifications;
    assert.ok(
      !mine.some((n) => n.type === 'friend_activity' && n.actorId === me.id),
      'you must not be notified about your own activity'
    );
  });

  test('notifications require auth', async () => {
    const a = await app();
    assert.equal((await a.get('/api/notifications')).status, 401);
    assert.equal((await a.get('/api/notifications/unread-count')).status, 401);
    assert.equal((await a.post('/api/notifications/read-all')).status, 401);
  });
});

describe('SSE stream', () => {
  test('handshake sends `ready`, then pushes a live notification', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);

    // EventSource cannot set headers, so the token rides in the query string.
    const controller = new AbortController();
    const res = await fetch(`${a.base}/api/notifications/stream?token=${me.token}`, {
      signal: controller.signal,
    });
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-type') ?? '', /text\/event-stream/);

    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    async function readUntil(pattern, budgetMs = 4000) {
      const deadline = Date.now() + budgetMs;
      while (Date.now() < deadline) {
        if (pattern.test(buffer)) return true;
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
      }
      return pattern.test(buffer);
    }

    assert.ok(await readUntil(/event: ready/), `no ready event; got: ${buffer}`);

    // Trigger a notification from the other side.
    await friend.post('/api/nudges', { body: { toUserId: me.id, habitName: 'Water' } });

    assert.ok(await readUntil(/event: notification/), `no notification event; got: ${buffer}`);
    const dataLine = buffer.split('\n').find((l) => l.startsWith('data:') && l.includes('"type"'));
    assert.ok(dataLine, 'no data line for the notification');
    const payload = JSON.parse(dataLine.slice(5).trim());
    assert.equal(payload.type, 'nudge');
    assert.equal(payload.refType, 'nudge');

    controller.abort();
    await reader.cancel().catch(() => {});
  });

  test('stream rejects a missing or bad token', async () => {
    const a = await app();
    const anon = await fetch(`${a.base}/api/notifications/stream`);
    assert.equal(anon.status, 401);
    await anon.body?.cancel().catch(() => {});

    const bad = await fetch(`${a.base}/api/notifications/stream?token=garbage`);
    assert.equal(bad.status, 401);
    await bad.body?.cancel().catch(() => {});
  });
});
