import test from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend, addHabit, dayOffset } from './helpers.js';

test('friend requests', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('full lifecycle: send -> notify -> accept -> mutual -> sender notified', async () => {
    const alex = await makeUser(app, { name: 'Alex' });
    const taylor = await makeUser(app, { name: 'Taylor' });

    const sent = await alex.post('/api/friend-requests', { body: { toUserId: taylor.id } });
    assert.equal(sent.status, 201);
    const request = sent.body.request;
    assert.equal(request.status, 'pending');
    assert.equal(request.fromUser.id, alex.id);
    assert.equal(request.toUser.id, taylor.id);
    assert.equal(request.mutualFriends, 0);
    assert.equal(request.respondedAt, null);

    // The recipient is notified.
    const notes = await taylor.get('/api/notifications');
    const invite = notes.body.notifications.find((n) => n.type === 'friend_request');
    assert.ok(invite, 'friend_request notification exists');
    assert.equal(invite.actorId, alex.id);
    assert.equal(invite.refType, 'friend_request');
    assert.equal(invite.refId, request.id);
    assert.equal(invite.read, false);

    // It shows up as incoming for one and outgoing for the other.
    const taylorPending = await taylor.get('/api/friend-requests');
    assert.equal(taylorPending.body.incoming.length, 1);
    assert.equal(taylorPending.body.outgoing.length, 0);
    const alexPending = await alex.get('/api/friend-requests');
    assert.equal(alexPending.body.incoming.length, 0);
    assert.equal(alexPending.body.outgoing.length, 1);

    const accepted = await taylor.post(`/api/friend-requests/${request.id}/accept`);
    assert.equal(accepted.status, 200);
    assert.equal(accepted.body.friend.id, alex.id);
    assert.equal(typeof accepted.body.friend.streakDays, 'number');
    assert.equal(accepted.body.friend.weekData.length, 7);

    // Both directions.
    const alexFriends = await alex.get('/api/friends');
    const taylorFriends = await taylor.get('/api/friends');
    assert.deepEqual(alexFriends.body.friends.map((f) => f.id), [taylor.id]);
    assert.deepEqual(taylorFriends.body.friends.map((f) => f.id), [alex.id]);

    // The sender is notified of the acceptance.
    const alexNotes = await alex.get('/api/notifications');
    const ok = alexNotes.body.notifications.find((n) => n.type === 'friend_request_accepted');
    assert.ok(ok);
    assert.equal(ok.actorId, taylor.id);
    assert.equal(ok.refType, 'user');
    assert.equal(ok.refId, taylor.id);

    // No longer pending for either party.
    assert.equal((await taylor.get('/api/friend-requests')).body.incoming.length, 0);
    assert.equal((await alex.get('/api/friend-requests')).body.outgoing.length, 0);
  });

  await t.test('decline: nobody is notified and no friendship appears', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });

    const before = (await a.get('/api/notifications')).body.notifications.length;
    const declined = await b.post(`/api/friend-requests/${sent.body.request.id}/decline`);
    assert.equal(declined.status, 204);

    assert.equal((await a.get('/api/notifications')).body.notifications.length, before);
    assert.equal((await a.get('/api/friends')).body.friends.length, 0);
    assert.equal((await b.get('/api/friend-requests')).body.incoming.length, 0);

    // A declined request does not block a fresh one.
    const again = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal(again.status, 201);
  });

  await t.test('cancel: only the sender may, and it frees a new request', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    const id = sent.body.request.id;

    assert.equal((await b.del(`/api/friend-requests/${id}`)).status, 403);
    assert.equal((await a.del(`/api/friend-requests/${id}`)).status, 204);
    assert.equal((await b.get('/api/friend-requests')).body.incoming.length, 0);

    const again = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal(again.status, 201);
  });

  await t.test('self-request -> 400', async () => {
    const a = await makeUser(app);
    const res = await a.post('/api/friend-requests', { body: { toUserId: a.id } });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'validation_error');
    assert.equal(res.body.error.field, 'toUserId');
  });

  await t.test('unknown toUserId -> 404, missing toUserId -> 400', async () => {
    const a = await makeUser(app);
    assert.equal((await a.post('/api/friend-requests', { body: { toUserId: 'u_ghost' } })).status, 404);
    assert.equal((await a.post('/api/friend-requests', { body: {} })).status, 400);
  });

  await t.test('duplicate pending request -> 409', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    assert.equal((await a.post('/api/friend-requests', { body: { toUserId: b.id } })).status, 201);
    const dup = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.error.code, 'conflict');
  });

  await t.test('a reciprocal request auto-accepts', async () => {
    const a = await makeUser(app, { name: 'Ana' });
    const b = await makeUser(app, { name: 'Ben' });

    await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    const reciprocal = await b.post('/api/friend-requests', { body: { toUserId: a.id } });

    assert.equal(reciprocal.status, 200);
    assert.equal(reciprocal.body.autoAccepted, true);
    assert.equal(reciprocal.body.request.status, 'accepted');
    assert.equal(reciprocal.body.friend.id, a.id);

    assert.deepEqual((await a.get('/api/friends')).body.friends.map((f) => f.id), [b.id]);
    assert.deepEqual((await b.get('/api/friends')).body.friends.map((f) => f.id), [a.id]);

    // Nothing is left pending on either side.
    assert.equal((await a.get('/api/friend-requests')).body.incoming.length, 0);
    assert.equal((await a.get('/api/friend-requests')).body.outgoing.length, 0);
    assert.equal((await b.get('/api/friend-requests')).body.incoming.length, 0);

    // The original sender learns about it.
    const aNotes = await a.get('/api/notifications');
    assert.ok(aNotes.body.notifications.some((n) => n.type === 'friend_request_accepted' && n.actorId === b.id));
  });

  await t.test('already friends -> 409', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    await befriend(a, b);
    const res = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal(res.status, 409);
  });

  await t.test('accepting someone else\'s request -> 403', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    const c = await makeUser(app);
    const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });

    const byThirdParty = await c.post(`/api/friend-requests/${sent.body.request.id}/accept`);
    assert.equal(byThirdParty.status, 403);
    assert.equal(byThirdParty.body.error.code, 'forbidden');

    // The sender cannot accept their own request either.
    assert.equal((await a.post(`/api/friend-requests/${sent.body.request.id}/accept`)).status, 403);
    assert.equal((await c.post(`/api/friend-requests/${sent.body.request.id}/decline`)).status, 403);
  });

  await t.test('accepting twice -> 409; unknown request -> 404', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal((await b.post(`/api/friend-requests/${sent.body.request.id}/accept`)).status, 200);
    const twice = await b.post(`/api/friend-requests/${sent.body.request.id}/accept`);
    assert.equal(twice.status, 409);
    assert.equal((await b.post('/api/friend-requests/fr_ghost/accept')).status, 404);
  });

  await t.test('mutualFriends is counted on the request', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    const shared = await makeUser(app);
    await befriend(a, shared);
    await befriend(b, shared);

    const sent = await a.post('/api/friend-requests', { body: { toUserId: b.id } });
    assert.equal(sent.body.request.mutualFriends, 1);
  });
});

test('friends list, detail and unfriend', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('list is sorted by streak desc then name asc', async () => {
    const me = await makeUser(app);
    const zero = await makeUser(app, { name: 'Zoe' });     // streak 0
    const alsoZero = await makeUser(app, { name: 'Aaron' }); // streak 0
    const streaky = await makeUser(app, { name: 'Mia' });

    for (const f of [zero, alsoZero, streaky]) await befriend(me, f);

    const habit = await addHabit(streaky, { name: 'Steps', target: 100 });
    for (const offset of [-2, -1, 0]) {
      await streaky.post(`/api/habits/${habit.id}/log`, { body: { progress: 100, date: dayOffset(offset) } });
    }

    const friends = (await me.get('/api/friends')).body.friends;
    assert.deepEqual(friends.map((f) => f.name), ['Mia', 'Aaron', 'Zoe']);
    assert.equal(friends[0].streakDays, 3);
    assert.equal(friends[0].habitsTotal, 1);
    assert.equal(friends[0].habitsCompleted, 1);
    assert.equal(friends[0].completionPercentage, 1);
  });

  await t.test('a friend with zero habits reports 0 / 0 / 0', async () => {
    const me = await makeUser(app);
    const empty = await makeUser(app, { name: 'Empty' });
    await befriend(me, empty);

    const detail = await me.get(`/api/friends/${empty.id}`);
    assert.equal(detail.status, 200);
    assert.deepEqual(detail.body.habits, []);
    assert.equal(detail.body.friend.habitsTotal, 0);
    assert.equal(detail.body.friend.habitsCompleted, 0);
    assert.equal(detail.body.friend.completionPercentage, 0);
    assert.equal(detail.body.friend.streakDays, 0);
    assert.deepEqual(detail.body.friend.weekData, [false, false, false, false, false, false, false]);
    assert.ok(detail.body.friend.lastActiveAt);
  });

  await t.test('friend habit status: not_started | in_progress | completed', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);

    const none = await addHabit(friend, { name: 'Untouched', target: 10 });
    const partial = await addHabit(friend, { name: 'Partial', target: 10 });
    const done = await addHabit(friend, { name: 'Done', target: 10 });
    await friend.post(`/api/habits/${partial.id}/log`, { body: { progress: 4 } });
    await friend.post(`/api/habits/${done.id}/log`, { body: { progress: 11 } });

    const habits = (await me.get(`/api/friends/${friend.id}`)).body.habits;
    const byId = Object.fromEntries(habits.map((h) => [h.id, h]));
    assert.equal(byId[none.id].status, 'not_started');
    assert.equal(byId[partial.id].status, 'in_progress');
    assert.equal(byId[done.id].status, 'completed');
    assert.equal(byId[done.id].progress, 11);
    // The read-only shape must not leak the owner's private habit fields.
    assert.equal(byId[done.id].weekData, undefined);
    assert.equal(byId[done.id].completedToday, undefined);
  });

  await t.test('non-friend -> 403, unknown user -> 404, yourself -> 403', async () => {
    const me = await makeUser(app);
    const stranger = await makeUser(app);
    await addHabit(stranger, { name: 'Secret', target: 1 });

    for (const path of [`/api/friends/${stranger.id}`, `/api/friends/${stranger.id}/compare`]) {
      const res = await me.get(path);
      assert.equal(res.status, 403, path);
      assert.equal(res.body.error.code, 'forbidden');
    }
    assert.equal((await me.del(`/api/friends/${stranger.id}`)).status, 403);

    const ghost = await me.get('/api/friends/u_does_not_exist');
    assert.equal(ghost.status, 404);
    assert.equal(ghost.body.error.code, 'not_found');

    assert.equal((await me.get(`/api/friends/${me.id}`)).status, 403);
  });

  await t.test('unfriend removes both directions', async () => {
    const a = await makeUser(app);
    const b = await makeUser(app);
    await befriend(a, b);

    assert.equal((await a.get('/api/friends')).body.friends.length, 1);
    assert.equal((await a.del(`/api/friends/${b.id}`)).status, 204);
    assert.equal((await a.get('/api/friends')).body.friends.length, 0);
    assert.equal((await b.get('/api/friends')).body.friends.length, 0);
    assert.equal((await b.get(`/api/friends/${a.id}`)).status, 403);

    // ...and they can be friends again afterwards.
    await befriend(a, b);
    assert.equal((await a.get('/api/friends')).body.friends.length, 1);
  });
});

test('activity feed', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('shows friends only, newest first, never your own', async () => {
    const me = await makeUser(app, { name: 'Me' });
    const friend = await makeUser(app, { name: 'Friend' });
    const stranger = await makeUser(app, { name: 'Stranger' });
    await befriend(me, friend);

    const mine = await addHabit(me, { name: 'Mine', target: 1 });
    const theirs = await addHabit(friend, { name: 'Theirs', target: 2, unit: 'km' });
    const other = await addHabit(stranger, { name: 'Other', target: 1 });

    await me.post(`/api/habits/${mine.id}/log`, { body: { progress: 1 } });
    await friend.post(`/api/habits/${theirs.id}/log`, { body: { progress: 2 } });
    await stranger.post(`/api/habits/${other.id}/log`, { body: { progress: 1 } });

    const feed = (await me.get('/api/activity')).body.activities;
    assert.equal(feed.length, 1);
    assert.equal(feed[0].friendId, friend.id);
    assert.equal(feed[0].friendName, 'Friend');
    assert.equal(feed[0].habitName, 'Theirs');
    assert.equal(feed[0].completion, '2/2 km');
    assert.ok(feed[0].createdAt);
  });

  await t.test('limit clamps to 100 and before= is an exclusive cursor', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);

    for (let i = 0; i < 4; i++) {
      const h = await addHabit(friend, { name: `H${i}`, target: 1 });
      await friend.post(`/api/habits/${h.id}/log`, { body: { progress: 1 } });
    }

    const all = (await me.get('/api/activity')).body.activities;
    assert.equal(all.length, 4);

    const limited = (await me.get('/api/activity?limit=2')).body.activities;
    assert.equal(limited.length, 2);
    assert.deepEqual(limited.map((a) => a.id), all.slice(0, 2).map((a) => a.id));

    assert.equal((await me.get('/api/activity?limit=9999')).body.activities.length, 4);
    assert.equal((await me.get('/api/activity?limit=0')).body.activities.length, 1); // clamped up to 1
    assert.equal((await me.get('/api/activity?limit=abc')).body.activities.length, 4); // falls back to default

    const cursor = all[0].createdAt;
    const older = (await me.get(`/api/activity?before=${encodeURIComponent(cursor)}`)).body.activities;
    assert.ok(older.every((a) => a.createdAt < cursor), 'strictly older only');
    assert.ok(!older.some((a) => a.id === all[0].id));

    assert.equal((await me.get('/api/activity?before=not-a-date')).status, 400);
  });
});
