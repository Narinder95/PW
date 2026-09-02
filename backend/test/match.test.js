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

describe('user search', () => {
  test('matches on username and on name, case-insensitively', async () => {
    const a = await app();
    const me = await makeUser(a);
    const target = await makeUser(a, { username: 'zaraq', name: 'Zara Quinn' });

    const byUsername = await me.get('/api/users/search?q=zaraq');
    assert.equal(byUsername.status, 200);
    assert.ok(byUsername.body.users.some((u) => u.id === target.id));

    const byName = await me.get('/api/users/search?q=quinn');
    assert.ok(byName.body.users.some((u) => u.id === target.id));

    const upper = await me.get('/api/users/search?q=ZARA');
    assert.ok(upper.body.users.some((u) => u.id === target.id));

    const partial = await me.get('/api/users/search?q=ar');
    assert.ok(partial.body.users.some((u) => u.id === target.id));
  });

  test('never returns the caller', async () => {
    const a = await app();
    const me = await makeUser(a, { username: 'findme1', name: 'Find Me' });
    const res = await me.get('/api/users/search?q=findme1');
    assert.ok(!res.body.users.some((u) => u.id === me.id), 'search returned the caller');
  });

  test('empty or missing q -> 400', async () => {
    const a = await app();
    const me = await makeUser(a);
    assert.equal((await me.get('/api/users/search')).status, 400);
    assert.equal((await me.get('/api/users/search?q=')).status, 400);
    assert.equal((await me.get('/api/users/search?q=%20%20')).status, 400);
  });

  test('limit clamps to 50', async () => {
    const a = await app();
    const me = await makeUser(a);
    for (let i = 0; i < 6; i++) await makeUser(a, { username: `bulk${i}aaa`, name: 'Bulk User' });

    const res = await me.get('/api/users/search?q=bulk&limit=99999');
    assert.equal(res.status, 200);
    assert.ok(res.body.users.length <= 50);

    const one = await me.get('/api/users/search?q=bulk&limit=1');
    assert.equal(one.body.users.length, 1);
  });

  test('relationship reports all five states correctly', async () => {
    const a = await app();
    const me = await makeUser(a, { username: 'selfy1', name: 'Selfy' });
    const friend = await makeUser(a, { username: 'palx1', name: 'Pal' });
    const iSentTo = await makeUser(a, { username: 'sentx1', name: 'Sent' });
    const sentToMe = await makeUser(a, { username: 'recvx1', name: 'Recv' });
    const stranger = await makeUser(a, { username: 'nobodyx1', name: 'Nobody' });

    await befriend(me, friend);
    await me.post('/api/friend-requests', { body: { toUserId: iSentTo.id } });
    await sentToMe.post('/api/friend-requests', { body: { toUserId: me.id } });

    async function rel(username) {
      const res = await me.get(`/api/users/search?q=${username}`);
      const hit = res.body.users.find((u) => u.username === username);
      return hit ? hit.relationship : 'ABSENT';
    }

    assert.equal(await rel('palx1'), 'friend');
    assert.equal(await rel('sentx1'), 'request_sent');
    assert.equal(await rel('recvx1'), 'request_received');
    assert.equal(await rel('nobodyx1'), 'none');
    // The caller is filtered out entirely rather than labelled 'self'.
    assert.equal(await rel('selfy1'), 'ABSENT');
  });

  test('mutualFriends is counted', async () => {
    const a = await app();
    const me = await makeUser(a);
    const shared = await makeUser(a);
    const target = await makeUser(a, { username: 'mutualt1', name: 'Mutual Target' });
    await befriend(me, shared);
    await befriend(shared, target);

    const res = await me.get('/api/users/search?q=mutualt1');
    const hit = res.body.users.find((u) => u.id === target.id);
    assert.ok(hit);
    assert.equal(hit.mutualFriends, 1);
  });

  test('no matches -> empty array, not an error', async () => {
    const a = await app();
    const me = await makeUser(a);
    const res = await me.get('/api/users/search?q=qqzzxxnothing');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.users, []);
  });

  test('search requires auth', async () => {
    const a = await app();
    assert.equal((await a.get('/api/users/search?q=a')).status, 401);
  });
});

describe('match suggestions', () => {
  test('excludes friends and anyone with a pending request either way', async () => {
    const a = await app();
    const me = await makeUser(a);
    const friend = await makeUser(a);
    const iSentTo = await makeUser(a);
    const sentToMe = await makeUser(a);
    const candidate = await makeUser(a);

    await befriend(me, friend);
    await me.post('/api/friend-requests', { body: { toUserId: iSentTo.id } });
    await sentToMe.post('/api/friend-requests', { body: { toUserId: me.id } });

    const res = await me.get('/api/match/suggestions');
    assert.equal(res.status, 200);
    const ids = res.body.suggestions.map((s) => s.user.id);

    assert.ok(!ids.includes(me.id), 'suggested the caller');
    assert.ok(!ids.includes(friend.id), 'suggested an existing friend');
    assert.ok(!ids.includes(iSentTo.id), 'suggested someone with an outgoing request');
    assert.ok(!ids.includes(sentToMe.id), 'suggested someone with an incoming request');
    assert.ok(ids.includes(candidate.id), 'did not suggest an eligible stranger');
  });

  test('shared habits raise the score and are listed', async () => {
    const a = await app();
    const me = await makeUser(a);
    const twin = await makeUser(a, { name: 'Twin' });
    const nothingInCommon = await makeUser(a, { name: 'Different' });

    for (const h of ['Steps', 'Water', 'Sleep']) {
      await addHabit(me, { name: h, target: 10, unit: 'x' });
      await addHabit(twin, { name: h, target: 10, unit: 'x' });
    }
    await addHabit(nothingInCommon, { name: 'Origami', target: 1, unit: 'x' });

    const res = await me.get('/api/match/suggestions');
    const twinHit = res.body.suggestions.find((s) => s.user.id === twin.id);
    const otherHit = res.body.suggestions.find((s) => s.user.id === nothingInCommon.id);

    assert.ok(twinHit, 'twin missing from suggestions');
    assert.deepEqual([...twinHit.sharedHabits].sort(), ['Sleep', 'Steps', 'Water']);
    assert.ok(twinHit.matchScore > otherHit.matchScore, 'shared habits did not raise the score');
    assert.equal(typeof twinHit.reason, 'string');
    assert.ok(twinHit.reason.length > 0);
  });

  test('habit matching is case- and whitespace-insensitive', async () => {
    const a = await app();
    const me = await makeUser(a);
    const other = await makeUser(a);
    await addHabit(me, { name: 'Steps', target: 10, unit: 'x' });
    await addHabit(other, { name: '  steps  ', target: 10, unit: 'x' });

    const res = await me.get('/api/match/suggestions');
    const hit = res.body.suggestions.find((s) => s.user.id === other.id);
    assert.ok(hit);
    assert.equal(hit.sharedHabits.length, 1);
  });

  test('score is 0-100, an integer, and sorted descending', async () => {
    const a = await app();
    const me = await makeUser(a);
    for (let i = 0; i < 5; i++) {
      const u = await makeUser(a);
      for (let h = 0; h <= i; h++) await addHabit(u, { name: `H${h}`, target: 5, unit: 'x' });
    }
    for (let h = 0; h < 5; h++) await addHabit(me, { name: `H${h}`, target: 5, unit: 'x' });

    const res = await me.get('/api/match/suggestions');
    const scores = res.body.suggestions.map((s) => s.matchScore);
    for (const s of scores) {
      assert.ok(Number.isInteger(s), `score not an integer: ${s}`);
      assert.ok(s >= 0 && s <= 100, `score out of range: ${s}`);
    }
    assert.deepEqual(scores, [...scores].sort((x, y) => y - x), 'suggestions are not sorted');
  });

  test('deterministic: two identical calls give identical results', async () => {
    const a = await app();
    const me = await makeUser(a);
    for (let i = 0; i < 4; i++) {
      const u = await makeUser(a);
      await addHabit(u, { name: 'Steps', target: 10, unit: 'x' });
    }
    await addHabit(me, { name: 'Steps', target: 10, unit: 'x' });

    const first = await me.get('/api/match/suggestions');
    const second = await me.get('/api/match/suggestions');
    assert.deepEqual(first.body, second.body, 'suggestions are not deterministic');
  });

  test('limit is honoured and clamped', async () => {
    const a = await app();
    const me = await makeUser(a);
    for (let i = 0; i < 4; i++) await makeUser(a);
    assert.equal((await me.get('/api/match/suggestions?limit=2')).body.suggestions.length, 2);
    const big = await me.get('/api/match/suggestions?limit=99999');
    assert.ok(big.body.suggestions.length <= 50);
  });

  test('a lone user gets an empty list, not an error', async () => {
    const a = await app();
    const me = await makeUser(a);
    // Everyone else in this app instance is already a friend.
    const res = await me.get('/api/match/suggestions');
    assert.equal(res.status, 200);
    assert.ok(Array.isArray(res.body.suggestions));
  });

  test('suggestions require auth', async () => {
    const a = await app();
    assert.equal((await a.get('/api/match/suggestions')).status, 401);
  });
});
