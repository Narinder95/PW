// Regressions for bugs that a naive implementation would ship and that a
// week-scoped test suite would never catch.
import test, { after, describe } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, befriend, addHabit, dayOffset } from './helpers.js';

const apps = [];
async function app() {
  const a = await makeApp();
  apps.push(a);
  return a;
}
after(async () => {
  for (const a of apps) await a.close();
});

describe('streaks longer than the 7-day window', () => {
  test('a 30-day streak reports 30, not 7', async () => {
    const a = await app();
    const me = await makeUser(a);
    const habit = await addHabit(me, { name: 'Steps', target: 100, unit: 'steps' });

    // Complete it every day for the last 30 days, inclusive of today.
    for (let d = 29; d >= 0; d--) {
      const res = await me.post(`/api/habits/${habit.id}/log`, {
        body: { progress: 100, date: dayOffset(-d) },
      });
      assert.equal(res.status, 200);
    }

    const habits = (await me.get('/api/habits')).body.habits;
    const steps = habits.find((h) => h.id === habit.id);
    assert.equal(
      steps.streak,
      30,
      'streak is capped by the 7-day weekData window instead of the full log history'
    );
    // weekData stays a 7-day strip regardless.
    assert.equal(steps.weekData.length, 7);
    assert.ok(steps.weekData.every(Boolean));
  });

  test('user-level streakDays also spans beyond a week', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a, { name: 'Streaky' });
    await befriend(me, friend);

    const h = await addHabit(friend, { name: 'Water', target: 8, unit: 'cups' });
    for (let d = 20; d >= 0; d--) {
      await friend.post(`/api/habits/${h.id}/log`, {
        body: { progress: 8, date: dayOffset(-d) },
      });
    }

    const friends = (await me.get('/api/friends')).body.friends;
    const streaky = friends.find((f) => f.id === friend.id);
    assert.ok(streaky, 'friend missing from the list');
    assert.equal(streaky.streakDays, 21, `expected 21, got ${streaky.streakDays}`);
  });

  test('a gap 10 days back still truncates the streak correctly', async () => {
    const a = await app();
    const me = await makeUser(a);
    const habit = await addHabit(me, { name: 'Read', target: 10, unit: 'min' });

    for (let d = 20; d >= 0; d--) {
      if (d === 10) continue; // one missed day, outside the 7-day window
      await me.post(`/api/habits/${habit.id}/log`, {
        body: { progress: 10, date: dayOffset(-d) },
      });
    }

    const steps = (await me.get('/api/habits')).body.habits.find((h) => h.id === habit.id);
    assert.equal(steps.streak, 10, 'streak did not stop at the gap 10 days back');
  });
});

describe('activity feed follows the CURRENT friendship set', () => {
  test("an ex-friend's activity disappears from the feed", async () => {
    const a = await app();
    const me = await makeUser(a);
    const soonToGo = await makeUser(a, { name: 'Leaver' });
    await befriend(me, soonToGo);

    const habit = await addHabit(soonToGo, { name: 'Steps', target: 100, unit: 'steps' });
    await soonToGo.post(`/api/habits/${habit.id}/log`, { body: { progress: 100 } });

    const before = (await me.get('/api/activity')).body.activities;
    assert.ok(
      before.some((x) => x.friendId === soonToGo.id),
      'the activity never showed up in the first place'
    );

    assert.equal((await me.del(`/api/friends/${soonToGo.id}`)).status, 204);

    const after = (await me.get('/api/activity')).body.activities;
    assert.ok(
      !after.some((x) => x.friendId === soonToGo.id),
      "an ex-friend's activity is still being served"
    );
  });

  test('re-friending brings the history back', async () => {
    const a = await app();
    const me = await makeUser(a);
    const other = await makeUser(a);
    await befriend(me, other);

    const habit = await addHabit(other, { name: 'Water', target: 8, unit: 'cups' });
    await other.post(`/api/habits/${habit.id}/log`, { body: { progress: 8 } });

    await me.del(`/api/friends/${other.id}`);
    assert.equal((await me.get('/api/activity')).body.activities.length, 0);

    await befriend(me, other);
    const back = (await me.get('/api/activity')).body.activities;
    assert.ok(back.some((x) => x.friendId === other.id), 'history did not return after re-friending');
  });

  test('unfriending is symmetric for the feed', async () => {
    const a = await app();
    const alice = await makeUser(a);
    const bob = await makeUser(a);
    await befriend(alice, bob);

    const ha = await addHabit(alice, { name: 'Run', target: 5, unit: 'km' });
    const hb = await addHabit(bob, { name: 'Run', target: 5, unit: 'km' });
    await alice.post(`/api/habits/${ha.id}/log`, { body: { progress: 5 } });
    await bob.post(`/api/habits/${hb.id}/log`, { body: { progress: 5 } });

    // Bob does the unfriending; Alice's feed must lose Bob too.
    await bob.del(`/api/friends/${alice.id}`);

    assert.equal((await alice.get('/api/activity')).body.activities.length, 0);
    assert.equal((await bob.get('/api/activity')).body.activities.length, 0);
  });
});

describe('zero-state users do not break anything', () => {
  test('a friend with no habits reports 0/0 and never divides by zero', async () => {
    const a = await app();
    const me = await makeUser(a);
    const empty = await makeUser(a, { name: 'Devon' });
    await befriend(me, empty);

    const summary = (await me.get('/api/friends')).body.friends.find((f) => f.id === empty.id);
    assert.equal(summary.habitsTotal, 0);
    assert.equal(summary.habitsCompleted, 0);
    assert.equal(summary.completionPercentage, 0);
    assert.equal(summary.streakDays, 0);
    assert.ok(Number.isFinite(summary.completionPercentage), 'completionPercentage is NaN/Infinity');

    const detail = await me.get(`/api/friends/${empty.id}`);
    assert.equal(detail.status, 200);
    assert.deepEqual(detail.body.habits, []);
    assert.equal(detail.body.friend.weekData.length, 7);

    const cmp = await me.get(`/api/friends/${empty.id}/compare`);
    assert.equal(cmp.status, 200);
    assert.deepEqual(cmp.body.comparison.habits, []);
    assert.equal(cmp.body.comparison.verdict, 'tie');
  });

  test('completionPercentage is always a finite number in [0,1]', async () => {
    const a = await app();
    const me = await makeUser(a);
    for (let i = 0; i < 3; i++) {
      const f = await makeUser(a);
      await befriend(me, f);
      if (i > 0) {
        const h = await addHabit(f, { name: 'H', target: 10, unit: 'x' });
        await f.post(`/api/habits/${h.id}/log`, { body: { progress: i * 7 } });
      }
    }
    for (const f of (await me.get('/api/friends')).body.friends) {
      assert.ok(Number.isFinite(f.completionPercentage), `not finite: ${f.completionPercentage}`);
      assert.ok(f.completionPercentage >= 0 && f.completionPercentage <= 1);
    }
  });

  test('over-logging past the target does not push percentage above 1', async () => {
    const a = await app();
    const me = await makeUser(a);
    const over = await makeUser(a);
    await befriend(me, over);
    const h = await addHabit(over, { name: 'Steps', target: 100, unit: 'steps' });
    await over.post(`/api/habits/${h.id}/log`, { body: { progress: 100000 } });

    const summary = (await me.get('/api/friends')).body.friends.find((f) => f.id === over.id);
    assert.ok(summary.completionPercentage <= 1, `got ${summary.completionPercentage}`);

    const detail = await me.get(`/api/friends/${over.id}`);
    assert.equal(detail.body.habits[0].status, 'completed');
  });
});
