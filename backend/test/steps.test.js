import test from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, makeUser, dayOffset } from './helpers.js';

test('walking challenge', async (t) => {
  const app = await makeApp();
  t.after(() => app.close());

  await t.test('GET /api/challenge for a brand new user', async () => {
    const u = await makeUser(app);
    const res = await u.get('/api/challenge');
    assert.equal(res.status, 200);
    const c = res.body.challenge;
    assert.equal(c.level, 'none');
    assert.equal(c.streakDays, 0);
    assert.equal(c.target, 8000);
    assert.equal(c.nextLevel, 'bronze');
    assert.equal(c.daysToNextLevel, 3);
    assert.equal(c.todaySteps, 0);
    assert.equal(c.todayStatus, 'no_data');
    assert.equal(c.history.length, 14);
    assert.ok(c.history.every((d) => d.status === 'no_data'));
  });

  await t.test('sync upserts and takes MAX on a resync of the same date', async () => {
    const u = await makeUser(app);
    const date = dayOffset(-1);

    await u.post('/api/steps/sync', { body: { days: [{ date, steps: 5000 }] } });
    let res = await u.post('/api/steps/sync', { body: { days: [{ date, steps: 3000 }] } });
    assert.equal(res.status, 200);
    assert.equal(res.body.challenge.history.at(-1).steps, 5000); // smaller resync ignored

    res = await u.post('/api/steps/sync', { body: { days: [{ date, steps: 7000 }] } });
    assert.equal(res.body.challenge.history.at(-1).steps, 7000); // larger resync wins
  });

  await t.test('3 days at bronze target, then 3 more at silver target -> promotes twice', async () => {
    const u = await makeUser(app);
    const days = [
      { date: dayOffset(-6), steps: 8000 },
      { date: dayOffset(-5), steps: 8000 },
      { date: dayOffset(-4), steps: 8000 }, // promotes to bronze here
      { date: dayOffset(-3), steps: 10000 },
      { date: dayOffset(-2), steps: 10000 },
      { date: dayOffset(-1), steps: 10000 }, // promotes to silver here
    ];
    const res = await u.post('/api/steps/sync', { body: { days } });
    assert.equal(res.status, 200);
    const c = res.body.challenge;
    assert.equal(c.level, 'silver');
    assert.equal(c.streakDays, 0);
    assert.equal(c.target, 12000);
    assert.equal(c.nextLevel, 'gold');
    assert.equal(c.daysToNextLevel, 3);
  });

  await t.test('a day at 85% of target warns and freezes the streak (no reset, no advance)', async () => {
    const u = await makeUser(app);
    const days = [
      { date: dayOffset(-3), steps: 8000 },
      { date: dayOffset(-2), steps: 8000 },
      { date: dayOffset(-1), steps: 6800 }, // 85% of 8000
    ];
    const res = await u.post('/api/steps/sync', { body: { days } });
    const c = res.body.challenge;
    assert.equal(c.level, 'none'); // never promoted
    assert.equal(c.streakDays, 2); // frozen at 2, not reset to 0
    assert.equal(c.target, 8000);
    assert.equal(c.history.at(-1).status, 'warning');
  });

  await t.test('a day below 80% of target demotes one level and resets the streak', async () => {
    const u = await makeUser(app);
    const days = [
      { date: dayOffset(-8), steps: 8000 },
      { date: dayOffset(-7), steps: 8000 },
      { date: dayOffset(-6), steps: 8000 }, // -> bronze
      { date: dayOffset(-5), steps: 10000 },
      { date: dayOffset(-4), steps: 10000 },
      { date: dayOffset(-3), steps: 10000 }, // -> silver
      { date: dayOffset(-2), steps: 12000 }, // streak 1 at silver, pursuing gold
      { date: dayOffset(-1), steps: 6000 }, // 50% of 12000 -> demote to bronze
    ];
    const res = await u.post('/api/steps/sync', { body: { days } });
    const c = res.body.challenge;
    assert.equal(c.level, 'bronze');
    assert.equal(c.streakDays, 0);
    assert.equal(c.target, 10000);
    assert.equal(c.history.at(-1).status, 'shortfall');
  });

  await t.test('a gap day with no synced row freezes but never demotes', async () => {
    const u = await makeUser(app);
    const days = [
      { date: dayOffset(-3), steps: 8000 },
      // dayOffset(-2) deliberately not synced
      { date: dayOffset(-1), steps: 8000 },
    ];
    const res = await u.post('/api/steps/sync', { body: { days } });
    const c = res.body.challenge;
    assert.equal(c.level, 'none');
    assert.equal(c.streakDays, 2); // the gap day did not reset the streak
    const gapEntry = c.history.find((d) => d.date === dayOffset(-2));
    assert.equal(gapEntry.status, 'no_data');
  });

  await t.test('GET /api/challenge reflects a prior sync without syncing again', async () => {
    const u = await makeUser(app);
    await u.post('/api/steps/sync', { body: { days: [{ date: dayOffset(-1), steps: 9000 }] } });
    const res = await u.get('/api/challenge');
    assert.equal(res.status, 200);
    assert.equal(res.body.challenge.history.at(-1).steps, 9000);
  });

  await t.test('validation: empty days, too many days, bad date, negative steps', async () => {
    const u = await makeUser(app);

    assert.equal((await u.post('/api/steps/sync', { body: { days: [] } })).status, 400);
    assert.equal(
      (await u.post('/api/steps/sync', { body: {} })).status,
      400
    );

    const tooMany = Array.from({ length: 32 }, (_, i) => ({ date: dayOffset(-i - 1), steps: 100 }));
    assert.equal((await u.post('/api/steps/sync', { body: { days: tooMany } })).status, 400);

    assert.equal(
      (await u.post('/api/steps/sync', { body: { days: [{ date: 'not-a-date', steps: 100 }] } })).status,
      400
    );

    assert.equal(
      (await u.post('/api/steps/sync', { body: { days: [{ date: dayOffset(-1), steps: -5 }] } })).status,
      400
    );
  });

  await t.test('unauthenticated requests are rejected', async () => {
    assert.equal((await app.get('/api/challenge')).status, 401);
    assert.equal((await app.post('/api/steps/sync', { body: { days: [] } })).status, 401);
  });
});
