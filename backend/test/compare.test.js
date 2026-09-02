import test from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend, addHabit, dayOffset } from './helpers.js';

test('friend comparison', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('no shared habits -> empty list, 0-0, tie', async () => {
    const me = await makeUser(app, { name: 'Me' });
    const friend = await makeUser(app, { name: 'You' });
    await befriend(me, friend);

    await addHabit(me, { name: 'Steps', target: 10 });
    await addHabit(friend, { name: 'Yoga', target: 10 });

    const c = (await me.get(`/api/friends/${friend.id}/compare`)).body.comparison;
    assert.deepEqual(c.habits, []);
    assert.equal(c.sharedHabitCount, 0);
    assert.equal(c.me.score, 0);
    assert.equal(c.friend.score, 0);
    assert.equal(c.verdict, 'tie');
    assert.equal(c.me.id, me.id);
    assert.equal(c.friend.id, friend.id);
  });

  await t.test('both with zero habits -> tie', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);
    const c = (await me.get(`/api/friends/${friend.id}/compare`)).body.comparison;
    assert.deepEqual(c.habits, []);
    assert.equal(c.verdict, 'tie');
  });

  await t.test('winner is decided on the clamped completion ratio, verdict on score', async () => {
    const me = await makeUser(app, { name: 'Me' });
    const friend = await makeUser(app, { name: 'You' });
    await befriend(me, friend);

    // Shared, I win: 0.65 vs 0.30
    const mySteps = await addHabit(me, { name: 'Steps', icon: 'R', color: '#2E7D32', target: 10000, unit: 'steps' });
    const theirSteps = await addHabit(friend, { name: '  steps ', target: 10000, unit: 'steps' }); // matched trimmed + case-insensitively
    await me.post(`/api/habits/${mySteps.id}/log`, { body: { progress: 6500 } });
    await friend.post(`/api/habits/${theirSteps.id}/log`, { body: { progress: 3000 } });

    // Shared, they win: 0.25 vs 1.0 - different targets are fine, ratios decide.
    const myWater = await addHabit(me, { name: 'Water', target: 8, unit: 'glasses' });
    const theirWater = await addHabit(friend, { name: 'Water', target: 4, unit: 'glasses' });
    await me.post(`/api/habits/${myWater.id}/log`, { body: { progress: 2 } });
    await friend.post(`/api/habits/${theirWater.id}/log`, { body: { progress: 4 } });

    // Shared, tie because both are clamped to 1.0 despite different raw numbers.
    const myRead = await addHabit(me, { name: 'Read', target: 10, unit: 'pages' });
    const theirRead = await addHabit(friend, { name: 'Read', target: 10, unit: 'pages' });
    await me.post(`/api/habits/${myRead.id}/log`, { body: { progress: 10 } });
    await friend.post(`/api/habits/${theirRead.id}/log`, { body: { progress: 40 } });

    // Not shared - must be ignored entirely.
    await addHabit(me, { name: 'Meditate', target: 10 });
    await addHabit(friend, { name: 'Sleep', target: 8 });

    const c = (await me.get(`/api/friends/${friend.id}/compare`)).body.comparison;
    assert.equal(c.sharedHabitCount, 3);
    assert.equal(c.habits.length, 3);

    const byName = Object.fromEntries(c.habits.map((h) => [h.name, h]));
    assert.equal(byName.Steps.winner, 'me');
    assert.equal(byName.Steps.myProgress, 6500);
    assert.equal(byName.Steps.myTarget, 10000);
    assert.equal(byName.Steps.friendProgress, 3000);
    assert.equal(byName.Steps.friendTarget, 10000);
    assert.equal(byName.Steps.unit, 'steps');
    assert.equal(byName.Steps.icon, 'R');
    assert.equal(byName.Steps.color, '#2E7D32');

    assert.equal(byName.Water.winner, 'friend');
    assert.equal(byName.Water.myTarget, 8);
    assert.equal(byName.Water.friendTarget, 4);

    assert.equal(byName.Read.winner, 'tie');

    assert.equal(c.me.score, 1);
    assert.equal(c.friend.score, 1);
    assert.equal(c.verdict, 'tie');
  });

  await t.test('me_ahead and friend_ahead', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);

    const a1 = await addHabit(me, { name: 'A', target: 10 });
    const a2 = await addHabit(friend, { name: 'A', target: 10 });
    const b1 = await addHabit(me, { name: 'B', target: 10 });
    const b2 = await addHabit(friend, { name: 'B', target: 10 });

    await me.post(`/api/habits/${a1.id}/log`, { body: { progress: 10 } });
    await me.post(`/api/habits/${b1.id}/log`, { body: { progress: 10 } });
    await friend.post(`/api/habits/${a2.id}/log`, { body: { progress: 1 } });
    await friend.post(`/api/habits/${b2.id}/log`, { body: { progress: 1 } });

    const mine = (await me.get(`/api/friends/${friend.id}/compare`)).body.comparison;
    assert.equal(mine.me.score, 2);
    assert.equal(mine.friend.score, 0);
    assert.equal(mine.verdict, 'me_ahead');

    // The same comparison from the other side is exactly mirrored.
    const theirs = (await friend.get(`/api/friends/${me.id}/compare`)).body.comparison;
    assert.equal(theirs.me.score, 0);
    assert.equal(theirs.friend.score, 2);
    assert.equal(theirs.verdict, 'friend_ahead');
  });

  await t.test('streakDays are carried on both sides', async () => {
    const me = await makeUser(app);
    const friend = await makeUser(app);
    await befriend(me, friend);

    const h = await addHabit(friend, { name: 'Solo', target: 1 });
    for (const offset of [-1, 0]) {
      await friend.post(`/api/habits/${h.id}/log`, { body: { progress: 1, date: dayOffset(offset) } });
    }

    const c = (await me.get(`/api/friends/${friend.id}/compare`)).body.comparison;
    assert.equal(c.me.streakDays, 0);
    assert.equal(c.friend.streakDays, 2);
  });
});
