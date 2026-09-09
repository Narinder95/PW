import test, { after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend } from './helpers.js';
import { createPushProvider, NoneProvider, LogProvider, MemoryProvider } from '../src/push/index.js';
import { captureLogger } from './helpers.js';

const apps = [];
async function app(options) {
  const a = await makeApp(options);
  apps.push(a);
  return a;
}
after(async () => {
  for (const a of apps) await a.close();
});

async function deliveries(a, userId) {
  return a.db
    .prepare('SELECT * FROM push_deliveries WHERE user_id = ? ORDER BY created_at ASC, id ASC')
    .all(userId);
}

/** Register a device, then trigger one notification for `me` from `friend`. */
async function nudgeMe(friend, me, habitName = 'Water') {
  return friend.post('/api/nudges', { body: { toUserId: me.id, habitName } });
}

describe('push provider selection', () => {
  test('defaults to none; unknown names warn and degrade to none', () => {
    const logger = captureLogger();
    assert.equal(createPushProvider({}, logger).name, 'none');
    assert.equal(createPushProvider({ PUSH_PROVIDER: 'none' }, logger).name, 'none');
    assert.equal(createPushProvider({ PUSH_PROVIDER: 'LOG' }, logger).name, 'log');
    assert.equal(createPushProvider({ PUSH_PROVIDER: 'memory' }, logger).name, 'memory');

    const unknown = createPushProvider({ PUSH_PROVIDER: 'carrier-pigeon' }, logger);
    assert.equal(unknown.name, 'none');
    assert.ok(logger.lines.warn.some((l) => l.includes('carrier-pigeon')));
  });

  test('fcm without usable credentials warns and degrades instead of crashing', () => {
    const logger = captureLogger();
    const p = createPushProvider({ PUSH_PROVIDER: 'fcm' }, logger);
    assert.equal(p.name, 'none', 'a misconfigured fcm must not take down the server');
    assert.ok(logger.lines.warn.some((l) => l.includes('PUSH_SETUP.md')));

    const logger2 = captureLogger();
    const p2 = createPushProvider(
      { PUSH_PROVIDER: 'fcm', FCM_SERVICE_ACCOUNT_FILE: './does-not-exist.json' },
      logger2
    );
    assert.equal(p2.name, 'none');
  });

  test('the none provider skips and the log provider prints', async () => {
    assert.deepEqual(await new NoneProvider().send({}), { status: 'skipped' });
    const logger = captureLogger();
    const res = await new LogProvider(logger).send({ title: 'hi' });
    assert.equal(res.status, 'sent');
    assert.ok(logger.lines.log.some((l) => l.includes('[push:log]')));
  });
});

describe('device registration', () => {
  test('register -> 201, and re-registering the same token is idempotent', async () => {
    const a = await app();
    const me = await makeUser(a);

    const first = await me.post('/api/devices', { body: { token: 'tok-1', platform: 'android' } });
    assert.equal(first.status, 201);
    assert.equal(first.body.device.platform, 'android');

    const again = await me.post('/api/devices', { body: { token: 'tok-1', platform: 'android' } });
    assert.equal(again.status, 201);

    const rows = await a.db.prepare('SELECT * FROM devices WHERE user_id = ?').all(me.id);
    assert.equal(rows.length, 1, 're-registering created a duplicate device row');
  });

  test('a token registered by another user moves to the new owner', async () => {
    const a = await app();
    const first = await makeUser(a);
    const second = await makeUser(a);

    await first.post('/api/devices', { body: { token: 'shared-handset', platform: 'ios' } });
    await second.post('/api/devices', { body: { token: 'shared-handset', platform: 'ios' } });

    const rows = await a.db.prepare('SELECT * FROM devices WHERE token = ?').all('shared-handset');
    assert.equal(rows.length, 1);
    assert.equal(rows[0].user_id, second.id, 'the handset kept pushing to the previous account');
  });

  test('bad platform or missing token -> 400', async () => {
    const a = await app();
    const me = await makeUser(a);
    assert.equal((await me.post('/api/devices', { body: { platform: 'android' } })).status, 400);
    assert.equal(
      (await me.post('/api/devices', { body: { token: 't', platform: 'blackberry' } })).status,
      400
    );
  });

  test('delete removes it; logout removes it too', async () => {
    const a = await app();
    const me = await makeUser(a);
    await me.post('/api/devices', { body: { token: 'tok-del', platform: 'android' } });
    assert.equal((await me.del('/api/devices/tok-del')).status, 204);
    const deleted = await a.db.prepare('SELECT COUNT(*) n FROM devices WHERE token = ?').get('tok-del');
    assert.equal(Number(deleted.n), 0);

    await me.post('/api/devices', { body: { token: 'tok-logout', platform: 'android' } });
    await me.post('/api/auth/logout');
    const afterLogout = await a.db.prepare('SELECT COUNT(*) n FROM devices WHERE token = ?').get('tok-logout');
    assert.equal(Number(afterLogout.n), 0, 'logout left a live push token behind');
  });

  test('devices require auth', async () => {
    const a = await app();
    assert.equal((await a.post('/api/devices', { body: { token: 't', platform: 'ios' } })).status, 401);
  });
});

describe('push dispatch', () => {
  test('one push per registered device, with the right payload and badge', async () => {
    const a = await app();
    const me = await makeUser(a, { name: 'Me' });
    const friend = await makeUser(a, { name: 'Buddy' });
    await befriend(me, friend);
    await me.post('/api/notifications/read-all');

    await me.post('/api/devices', { body: { token: 'phone', platform: 'android' } });
    await me.post('/api/devices', { body: { token: 'tablet', platform: 'android' } });

    a.provider.reset();
    await nudgeMe(friend, me, 'Meditate');
    await a.push.idle();

    assert.equal(a.provider.sent.length, 2, 'expected one push per device');
    const tokens = a.provider.sent.map((p) => p.deviceToken).sort();
    assert.deepEqual(tokens, ['phone', 'tablet']);

    const payload = a.provider.sent[0];
    assert.equal(typeof payload.title, 'string');
    assert.equal(typeof payload.body, 'string');
    assert.equal(payload.badge, 1, 'badge should equal the unread count');
    assert.equal(payload.data.type, 'nudge');
    assert.equal(payload.data.refType, 'nudge');
    assert.equal(payload.data.actorId, friend.id);
    // FCM rejects non-string data values.
    for (const [k, v] of Object.entries(payload.data)) {
      assert.equal(typeof v, 'string', `data.${k} is ${typeof v}, must be string`);
    }
    assert.ok(payload.collapseKey.startsWith('nudge:'));

    for (const d of await deliveries(a, me.id)) assert.equal(d.status, 'sent');
  });

  test('badge tracks the unread count as it grows', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/notifications/read-all');
    await me.post('/api/devices', { body: { token: 'p', platform: 'ios' } });

    a.provider.reset();
    await nudgeMe(friend, me, 'Water');
    await a.push.idle();
    await nudgeMe(friend, me, 'Steps');
    await a.push.idle();

    assert.deepEqual(
      a.provider.sent.map((p) => p.badge),
      [1, 2]
    );
  });

  test('no registered devices is a clean no-op', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);

    a.provider.reset();
    const res = await nudgeMe(friend, me);
    await a.push.idle();

    assert.equal(res.status, 201, 'the API call must still succeed');
    assert.equal(a.provider.sent.length, 0);
    assert.equal((await deliveries(a, me.id)).length, 0);
  });

  test('a provider that THROWS does not fail the API call, and the notification survives', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'crashy', platform: 'android' } });

    a.provider.reset();
    a.provider.throwTimes = 99; // every attempt throws

    const res = await nudgeMe(friend, me, 'Sleep');
    assert.equal(res.status, 201, 'a push crash leaked into the API response');
    await a.push.idle();

    // The notification itself was still created and is still readable.
    const notes = await me.get('/api/notifications');
    assert.ok(notes.body.notifications.some((n) => n.type === 'nudge'));

    const rows = await deliveries(a, me.id);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].status, 'failed');
    assert.match(rows[0].error, /threw/);
  });

  test('retries a failure, then records sent', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'flaky', platform: 'android' } });

    a.provider.reset();
    a.provider.failTimes = 1; // fail once, succeed on retry

    await nudgeMe(friend, me, 'Run');
    await a.push.idle();

    assert.equal(a.provider.calls, 2, 'expected exactly one retry');
    const rows = await deliveries(a, me.id);
    assert.equal(rows[0].status, 'sent');
  });

  test('exhausting the retries records failed', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'dead', platform: 'android' } });

    a.provider.reset();
    a.provider.failTimes = 99;

    await nudgeMe(friend, me, 'Cycle');
    await a.push.idle();

    // 1 initial attempt + 2 retries (helpers.js sets retryDelays = [1, 2]).
    assert.equal(a.provider.calls, 3);
    assert.equal((await deliveries(a, me.id))[0].status, 'failed');
  });

  test('invalid_token deletes the device so we stop pushing into the void', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'uninstalled', platform: 'android' } });

    a.provider.reset();
    a.provider.tokenStatus.set('uninstalled', 'invalid_token');

    await nudgeMe(friend, me, 'Stretch');
    await a.push.idle();

    assert.equal((await deliveries(a, me.id))[0].status, 'invalid_token');
    const stillThere = await a.db.prepare('SELECT COUNT(*) n FROM devices WHERE token = ?').get('uninstalled');
    assert.equal(Number(stillThere.n), 0, 'a dead token was left registered');
    // It is not retried - one attempt only.
    assert.equal(a.provider.calls, 1);
  });

  test('the none provider still records the attempt as skipped', async () => {
    const a = await app({ provider: new NoneProvider() });
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'quiet', platform: 'ios' } });

    await nudgeMe(friend, me, 'Water');
    await a.push.idle();

    const rows = await deliveries(a, me.id);
    assert.equal(rows.length, 1, 'the path must stay observable even with no provider');
    assert.equal(rows[0].status, 'skipped');
    assert.equal(rows[0].provider, 'none');
  });

  test('friend requests and acceptances push too, not just nudges', async () => {
    const a = await app();
    const me = await makeUser(a);
    const other = await makeUser(a);
    await me.post('/api/devices', { body: { token: 'mine', platform: 'android' } });
    await other.post('/api/devices', { body: { token: 'theirs', platform: 'android' } });

    a.provider.reset();
    const req = await other.post('/api/friend-requests', { body: { toUserId: me.id } });
    await a.push.idle();
    assert.ok(
      a.provider.sent.some((p) => p.deviceToken === 'mine' && p.data.type === 'friend_request'),
      'no push for an incoming friend request'
    );

    a.provider.reset();
    await me.post(`/api/friend-requests/${req.body.request.id}/accept`);
    await a.push.idle();
    assert.ok(
      a.provider.sent.some(
        (p) => p.deviceToken === 'theirs' && p.data.type === 'friend_request_accepted'
      ),
      'no push for an accepted friend request'
    );
  });

  test('a MemoryProvider handed a bad result shape is treated as a failure, not a crash', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    await me.post('/api/devices', { body: { token: 'weird', platform: 'android' } });

    const broken = new MemoryProvider();
    broken.send = async () => ({ nonsense: true });
    a.push.provider = broken;

    const res = await nudgeMe(friend, me, 'Yoga');
    assert.equal(res.status, 201);
    await a.push.idle();
    assert.equal((await deliveries(a, me.id))[0].status, 'failed');
  });
});
