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

describe('nudges', () => {
  test('send to a friend -> 201, appears in received/sent, notifies recipient', async () => {
    const a = await app();
    const alex = await makeUser(a, { name: 'Alex' });
    const taylor = await makeUser(a, { name: 'Taylor' });
    await befriend(alex, taylor);

    const res = await alex.post('/api/nudges', {
      body: {
        toUserId: taylor.id,
        habitName: 'Meditate',
        habitIcon: 'M',
        habitColor: '#A855F7',
      },
    });
    assert.equal(res.status, 201);
    const nudge = res.body.nudge;
    assert.equal(nudge.type, 'nudge');
    assert.equal(nudge.status, 'pending');
    assert.equal(nudge.fromUserId, alex.id);
    assert.equal(nudge.toUserId, taylor.id);
    assert.equal(nudge.habitName, 'Meditate');
    assert.equal(nudge.acceptedAt, null);

    // Recipient sees it as received; sender sees it as sent.
    const mine = await taylor.get('/api/nudges');
    assert.equal(mine.body.received.length, 1);
    assert.equal(mine.body.received[0].id, nudge.id);
    assert.equal(mine.body.received[0].fromUserName, 'Alex');
    assert.equal(mine.body.sent.length, 0);

    const theirs = await alex.get('/api/nudges');
    assert.equal(theirs.body.sent.length, 1);
    assert.equal(theirs.body.received.length, 0);

    // And a notification landed for the recipient.
    const notes = await taylor.get('/api/notifications');
    const n = notes.body.notifications.find((x) => x.type === 'nudge');
    assert.ok(n, 'expected a nudge notification');
    assert.equal(n.refType, 'nudge');
    assert.equal(n.refId, nudge.id);
    assert.equal(n.actorId, alex.id);
    assert.equal(n.read, false);
  });

  test('cheer is a distinct type and notifies as a cheer', async () => {
    const a = await app();
    const x = await makeUser(a, { name: 'Xavi' });
    const y = await makeUser(a);
    await befriend(x, y);

    const res = await x.post('/api/nudges', {
      body: { toUserId: y.id, habitName: 'Steps', type: 'cheer' },
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.nudge.type, 'cheer');

    const notes = await y.get('/api/notifications');
    assert.ok(notes.body.notifications.some((n) => n.type === 'cheer'));
  });

  test('nudging a stranger -> 403, yourself -> 400', async () => {
    const a = await app();
    const me = await makeUser(a);
    const stranger = await makeUser(a);

    const s = await me.post('/api/nudges', {
      body: { toUserId: stranger.id, habitName: 'Steps' },
    });
    assert.equal(s.status, 403);
    assert.equal(s.body.error.code, 'forbidden');

    const self = await me.post('/api/nudges', {
      body: { toUserId: me.id, habitName: 'Steps' },
    });
    assert.equal(self.status, 400);
    assert.equal(self.body.error.code, 'validation_error');
  });

  test('missing habitName -> 400; unknown recipient -> 404; message over 140 -> 400', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);

    const noHabit = await me.post('/api/nudges', { body: { toUserId: friend.id } });
    assert.equal(noHabit.status, 400);

    const unknown = await me.post('/api/nudges', {
      body: { toUserId: 'u_nope', habitName: 'Steps' },
    });
    assert.ok([403, 404].includes(unknown.status), `got ${unknown.status}`);

    const long = await me.post('/api/nudges', {
      body: { toUserId: friend.id, habitName: 'Steps', message: 'x'.repeat(141) },
    });
    assert.equal(long.status, 400);
  });

  test('cooldown: same sender+recipient+habit inside 60 min -> 429 with retryAfterSeconds', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);

    const first = await me.post('/api/nudges', {
      body: { toUserId: friend.id, habitName: 'Water' },
    });
    assert.equal(first.status, 201);

    const second = await me.post('/api/nudges', {
      body: { toUserId: friend.id, habitName: 'Water' },
    });
    assert.equal(second.status, 429);
    assert.equal(second.body.error.code, 'rate_limited');
    assert.equal(typeof second.body.error.retryAfterSeconds, 'number');
    assert.ok(
      second.body.error.retryAfterSeconds > 0 && second.body.error.retryAfterSeconds <= 3600,
      `retryAfterSeconds out of range: ${second.body.error.retryAfterSeconds}`
    );
  });

  test('cooldown is scoped per habit and per recipient, not global', async () => {
    const a = await app();
    const me = await makeUser(a);
    const f1 = await makeUser(a);
    const f2 = await makeUser(a);
    await befriend(me, f1);
    await befriend(me, f2);

    assert.equal(
      (await me.post('/api/nudges', { body: { toUserId: f1.id, habitName: 'Water' } })).status,
      201
    );
    // Different habit, same person -> allowed.
    assert.equal(
      (await me.post('/api/nudges', { body: { toUserId: f1.id, habitName: 'Steps' } })).status,
      201
    );
    // Same habit, different person -> allowed.
    assert.equal(
      (await me.post('/api/nudges', { body: { toUserId: f2.id, habitName: 'Water' } })).status,
      201
    );
  });

  test('accept: recipient only, notifies the sender, drops out of received', async () => {
    const a = await app();
    const sender = await makeUser(a, { name: 'Sender' });
    const recipient = await makeUser(a, { name: 'Recip' });
    const bystander = await makeUser(a);
    await befriend(sender, recipient);

    const created = await sender.post('/api/nudges', {
      body: { toUserId: recipient.id, habitName: 'Meditate' },
    });
    const id = created.body.nudge.id;

    // Only the recipient may accept: everyone else gets 403 (contract rule).
    assert.equal((await bystander.post(`/api/nudges/${id}/accept`)).status, 403);
    assert.equal((await sender.post(`/api/nudges/${id}/accept`)).status, 403);

    const ok = await recipient.post(`/api/nudges/${id}/accept`);
    assert.equal(ok.status, 200);
    assert.equal(ok.body.nudge.status, 'accepted');
    assert.ok(ok.body.nudge.acceptedAt);

    // Gone from the pending inbox.
    const inbox = await recipient.get('/api/nudges');
    assert.equal(inbox.body.received.length, 0);

    // Original sender was told.
    const notes = await sender.get('/api/notifications');
    const n = notes.body.notifications.find((x) => x.type === 'nudge_accepted');
    assert.ok(n, 'expected nudge_accepted notification for the sender');
    assert.equal(n.actorId, recipient.id);
  });

  test('double accept -> 409; unknown nudge -> 404', async () => {
    const a = await app();
    const s = await makeUser(a);
    const r = await makeUser(a);
    await befriend(s, r);
    const created = await s.post('/api/nudges', {
      body: { toUserId: r.id, habitName: 'Sleep' },
    });
    const id = created.body.nudge.id;

    assert.equal((await r.post(`/api/nudges/${id}/accept`)).status, 200);
    assert.equal((await r.post(`/api/nudges/${id}/accept`)).status, 409);
    assert.equal((await r.post('/api/nudges/n_missing/accept')).status, 404);
  });

  test('unfriending stops further nudges', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    assert.equal(
      (await me.post('/api/nudges', { body: { toUserId: friend.id, habitName: 'Run' } })).status,
      201
    );
    assert.equal((await me.del(`/api/friends/${friend.id}`)).status, 204);
    const after = await me.post('/api/nudges', {
      body: { toUserId: friend.id, habitName: 'Cycle' },
    });
    assert.equal(after.status, 403);
  });

  test('unfriending after a nudge is sent blocks accepting it', async () => {
    const a = await app();
    const sender = await makeUser(a);
    const recipient = await makeUser(a);
    await befriend(sender, recipient);
    const created = await sender.post('/api/nudges', {
      body: { toUserId: recipient.id, habitName: 'Run' },
    });
    const id = created.body.nudge.id;

    assert.equal((await sender.del(`/api/friends/${recipient.id}`)).status, 204);

    const accept = await recipient.post(`/api/nudges/${id}/accept`);
    assert.equal(accept.status, 403);
  });

  test('a nudge can reference a real habit id', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    await befriend(me, friend);
    const habit = await addHabit(friend, { name: 'Yoga', target: 20, unit: 'min' });

    const res = await me.post('/api/nudges', {
      body: { toUserId: friend.id, habitId: habit.id, habitName: 'Yoga' },
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.nudge.habitId, habit.id);
  });

  test('nudges require auth', async () => {
    const a = await app();
    assert.equal((await a.get('/api/nudges')).status, 401);
    assert.equal((await a.post('/api/nudges', { body: {} })).status, 401);
  });
});
