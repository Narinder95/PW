import test from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend, addHabit, dayOffset } from './helpers.js';

test('habits', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('create -> list -> patch -> delete', async () => {
    const u = await makeUser(app);

    const created = await u.post('/api/habits', {
      body: { name: 'Steps', icon: 'R', color: '#2e7d32', target: 10000, unit: 'steps' },
    });
    assert.equal(created.status, 201);
    const habit = created.body.habit;
    assert.equal(habit.name, 'Steps');
    assert.equal(habit.color, '#2E7D32');
    assert.equal(habit.target, 10000);
    assert.equal(habit.progress, 0);
    assert.equal(habit.streak, 0);
    assert.equal(habit.completedToday, false);
    assert.equal(habit.weekData.length, 7);
    assert.deepEqual(habit.weekData, [false, false, false, false, false, false, false]);

    const listed = await u.get('/api/habits');
    assert.equal(listed.status, 200);
    assert.equal(listed.body.habits.length, 1);
    assert.equal(listed.body.habits[0].id, habit.id);

    const patched = await u.patch(`/api/habits/${habit.id}`, { body: { name: 'Daily Steps', target: 8000 } });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.habit.name, 'Daily Steps');
    assert.equal(patched.body.habit.target, 8000);
    assert.equal(patched.body.habit.unit, 'steps'); // untouched

    const removed = await u.del(`/api/habits/${habit.id}`);
    assert.equal(removed.status, 204);
    assert.equal((await u.get('/api/habits')).body.habits.length, 0);
    assert.equal((await u.del(`/api/habits/${habit.id}`)).status, 404);
  });

  await t.test('defaults fill in for optional fields', async () => {
    const u = await makeUser(app);
    const res = await u.post('/api/habits', { body: { name: 'Journal', target: 1 } });
    assert.equal(res.status, 201);
    assert.equal(res.body.habit.unit, '');
    assert.match(res.body.habit.color, /^#[0-9A-F]{6}$/);
    assert.ok(res.body.habit.icon.length > 0);
  });

  await t.test('target 0 -> 400, negative target -> 400, missing name -> 400', async () => {
    const u = await makeUser(app);

    const zero = await u.post('/api/habits', { body: { name: 'Nope', target: 0 } });
    assert.equal(zero.status, 400);
    assert.equal(zero.body.error.code, 'validation_error');
    assert.equal(zero.body.error.field, 'target');

    assert.equal((await u.post('/api/habits', { body: { name: 'Nope', target: -5 } })).status, 400);
    assert.equal((await u.post('/api/habits', { body: { name: 'Nope', target: 1.5 } })).status, 400);
    assert.equal((await u.post('/api/habits', { body: { name: 'Nope', target: '10' } })).status, 400);
    assert.equal((await u.post('/api/habits', { body: { target: 10 } })).status, 400);
    assert.equal((await u.post('/api/habits', { body: { name: '   ', target: 10 } })).status, 400);

    const created = await u.post('/api/habits', { body: { name: 'Fine', target: 3 } });
    assert.equal((await u.patch(`/api/habits/${created.body.habit.id}`, { body: { target: 0 } })).status, 400);
  });

  await t.test('negative progress -> 400', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Water', target: 8, unit: 'glasses' });

    const neg = await u.post(`/api/habits/${habit.id}/log`, { body: { progress: -1 } });
    assert.equal(neg.status, 400);
    assert.equal(neg.body.error.field, 'progress');

    assert.equal((await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 1.5 } })).status, 400);
    assert.equal((await u.post(`/api/habits/${habit.id}/log`, { body: {} })).status, 400);
    assert.equal((await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 1, date: 'yesterday' } })).status, 400);

    // 0 is explicitly allowed.
    assert.equal((await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 0 } })).status, 200);
  });

  await t.test('log SETS progress, it does not increment', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Read', target: 20, unit: 'pages' });

    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 5 } });
    const second = await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 7 } });
    assert.equal(second.body.habit.progress, 7);
    assert.equal(second.body.habit.completedToday, false);
    assert.equal(second.body.activity, null);
  });

  await t.test('crossing the target creates exactly ONE activity, however many times it is called', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);

    const habit = await addHabit(me, { name: '5k Run', icon: 'T', color: '#FB923C', target: 5, unit: 'km' });

    const under = await me.post(`/api/habits/${habit.id}/log`, { body: { progress: 3 } });
    assert.equal(under.body.activity, null);

    const crossing = await me.post(`/api/habits/${habit.id}/log`, { body: { progress: 5 } });
    assert.ok(crossing.body.activity, 'crossing the target returns the activity');
    assert.equal(crossing.body.activity.completion, '5/5 km');
    assert.equal(crossing.body.activity.friendId, me.id);
    assert.equal(crossing.body.habit.completedToday, true);

    // Hammer it: exactly-target, over, back under target, over again.
    for (const progress of [5, 6, 3, 12, 5]) {
      const again = await me.post(`/api/habits/${habit.id}/log`, { body: { progress } });
      assert.equal(again.status, 200);
      assert.equal(again.body.activity, null, `progress ${progress} must not create a second activity`);
    }

    const rows = app.db.prepare('SELECT * FROM activities WHERE habit_id = ?').all(habit.id);
    assert.equal(rows.length, 1, 'exactly one activities row');

    // ...and exactly one friend_activity notification for the one friend.
    const notes = await friend.get('/api/notifications');
    const activityNotes = notes.body.notifications.filter((n) => n.type === 'friend_activity');
    assert.equal(activityNotes.length, 1);
    assert.equal(activityNotes[0].refType, 'activity');
    assert.equal(activityNotes[0].refId, rows[0].id);
    assert.equal(activityNotes[0].actorId, me.id);
  });

  await t.test('a separate day gets its own activity', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Pushups', target: 10, unit: 'reps' });

    const today = await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 10 } });
    const yesterday = await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 10, date: dayOffset(-1) } });
    assert.ok(today.body.activity);
    assert.ok(yesterday.body.activity);
    assert.equal(app.db.prepare('SELECT COUNT(*) AS n FROM activities WHERE habit_id = ?').get(habit.id).n, 2);
  });

  await t.test('weekData is 7 long, oldest first, index 6 = today', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Meditate', target: 10, unit: 'min' });

    for (const offset of [-6, -4, -1, 0]) {
      await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 10, date: dayOffset(offset) } });
    }
    // A day logged but short of target must read as false.
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 9, date: dayOffset(-5) } });
    // A day outside the window must not shift anything.
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 10, date: dayOffset(-9) } });

    const listed = await u.get('/api/habits');
    const fresh = listed.body.habits.find((h) => h.id === habit.id);
    assert.equal(fresh.weekData.length, 7);
    //                       -6     -5     -4     -3     -2     -1    today
    assert.deepEqual(fresh.weekData, [true, false, true, false, false, true, true]);
    assert.equal(fresh.completedToday, true);
  });

  await t.test('streak: consecutive complete days ending today', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Streaky', target: 1 });
    for (const offset of [-3, -2, -1, 0]) {
      await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 1, date: dayOffset(offset) } });
    }
    const res = await u.get('/api/habits');
    assert.equal(res.body.habits.find((h) => h.id === habit.id).streak, 4);
  });

  await t.test('streak: today incomplete counts back from yesterday', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Yesterday', target: 5 });
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 5, date: dayOffset(-2) } });
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 5, date: dayOffset(-1) } });
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 2 } }); // today still short

    const fresh = (await u.get('/api/habits')).body.habits.find((h) => h.id === habit.id);
    assert.equal(fresh.streak, 2);
    assert.equal(fresh.completedToday, false);
  });

  await t.test('streak: a gap two days ago resets it', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Gappy', target: 1 });
    for (const offset of [-4, -3, -1, 0]) {
      await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 1, date: dayOffset(offset) } });
    }
    const fresh = (await u.get('/api/habits')).body.habits.find((h) => h.id === habit.id);
    assert.equal(fresh.streak, 2);
  });

  await t.test('?date= reads a past day', async () => {
    const u = await makeUser(app);
    const habit = await addHabit(u, { name: 'Backfill', target: 4 });
    await u.post(`/api/habits/${habit.id}/log`, { body: { progress: 4, date: dayOffset(-2) } });

    const past = await u.get(`/api/habits?date=${dayOffset(-2)}`);
    assert.equal(past.body.habits[0].progress, 4);
    assert.equal(past.body.habits[0].completedToday, true);

    const now = await u.get('/api/habits');
    assert.equal(now.body.habits[0].progress, 0);
    assert.equal(now.body.habits[0].completedToday, false);

    assert.equal((await u.get('/api/habits?date=2026-13-99')).status, 400);
  });

  await t.test('you cannot touch another user\'s habit', async () => {
    const owner = await makeUser(app);
    const stranger = await makeUser(app);
    const habit = await addHabit(owner, { name: 'Private', target: 10 });

    assert.equal((await stranger.patch(`/api/habits/${habit.id}`, { body: { name: 'Hacked' } })).status, 404);
    assert.equal((await stranger.del(`/api/habits/${habit.id}`)).status, 404);
    assert.equal((await stranger.post(`/api/habits/${habit.id}/log`, { body: { progress: 10 } })).status, 404);
    assert.equal((await stranger.get('/api/habits')).body.habits.length, 0);

    // Untouched.
    const fresh = (await owner.get('/api/habits')).body.habits[0];
    assert.equal(fresh.name, 'Private');
    assert.equal(fresh.progress, 0);
  });

  await t.test('unknown habit id -> 404', async () => {
    const u = await makeUser(app);
    assert.equal((await u.post('/api/habits/h_nope/log', { body: { progress: 1 } })).status, 404);
    assert.equal((await u.patch('/api/habits/h_nope', { body: { name: 'x' } })).status, 404);
  });

  await t.test('habits require auth', async () => {
    assert.equal((await app.get('/api/habits')).status, 401);
    assert.equal((await app.post('/api/habits', { body: { name: 'x', target: 1 } })).status, 401);
  });
});
