import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { makeApp, makeUser } from './helpers.js';
import { RESET_REQUEST_RATE_LIMIT, RESET_CONFIRM_RATE_LIMIT } from '../src/auth.js';

/** Pulls the raw token out of the plain-text mail body the memory provider captured. */
function tokenFromMail(message) {
  const match = message.text.match(/[0-9a-f]{64}/);
  assert.ok(match, `mail body did not contain a token: ${message.text}`);
  return match[0];
}

test('password reset', async (t) => {
  // Each subtest gets its own app/rate limiter (RESET_REQUEST_RATE_LIMIT is
  // only 5/hour) - see the "rate limiting" block in auth.test.js for why a
  // shared app across subtests would trip that limit well before the file
  // finishes and fail later tests for a reason unrelated to what they assert.
  await t.test('request for an unknown email is 204 and sends nothing', async () => {
    const app = await makeApp();
    try {
      const res = await app.post('/api/auth/password-reset/request', {
        body: { email: 'nobody-here@example.com' },
      });
      assert.equal(res.status, 204);
      assert.equal(app.mailProvider.sent.length, 0);
    } finally {
      await app.close();
    }
  });

  await t.test('request for a real account sends a token and confirm sets the new password', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetflow', password: 'oldpassword1' });
      const sentBeforeRequest = app.mailProvider.sent.length; // registering already sent a verification email

      const reqRes = await app.post('/api/auth/password-reset/request', {
        body: { email: user.email },
      });
      assert.equal(reqRes.status, 204);
      assert.equal(app.mailProvider.sent.length, sentBeforeRequest + 1);
      assert.equal(app.mailProvider.sent.at(-1).to, user.email);
      const token = tokenFromMail(app.mailProvider.sent.at(-1));

      const confirmRes = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'brandnewpassword1' },
      });
      assert.equal(confirmRes.status, 204);

      const oldLogin = await app.post('/api/auth/login', {
        body: { usernameOrEmail: user.username, password: 'oldpassword1' },
      });
      assert.equal(oldLogin.status, 401);

      const newLogin = await app.post('/api/auth/login', {
        body: { usernameOrEmail: user.username, password: 'brandnewpassword1' },
      });
      assert.equal(newLogin.status, 200);
    } finally {
      await app.close();
    }
  });

  await t.test('confirm invalidates every existing session, not just future logins', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetsessions', password: 'oldpassword1' });
      const meBefore = await user.get('/api/me');
      assert.equal(meBefore.status, 200);

      await app.post('/api/auth/password-reset/request', { body: { email: user.email } });
      const token = tokenFromMail(app.mailProvider.sent.at(-1));
      await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'brandnewpassword1' },
      });

      const meAfter = await user.get('/api/me');
      assert.equal(meAfter.status, 401);
    } finally {
      await app.close();
    }
  });

  await t.test('confirm with an unknown token is 400, not 500', async () => {
    const app = await makeApp();
    try {
      const res = await app.post('/api/auth/password-reset/confirm', {
        body: { token: 'a'.repeat(64), password: 'brandnewpassword1' },
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'validation_error');
    } finally {
      await app.close();
    }
  });

  await t.test('a token cannot be redeemed twice', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetreplay', password: 'oldpassword1' });
      await app.post('/api/auth/password-reset/request', { body: { email: user.email } });
      const token = tokenFromMail(app.mailProvider.sent.at(-1));

      const first = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'brandnewpassword1' },
      });
      assert.equal(first.status, 204);

      const replay = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'yetanotherpassword1' },
      });
      assert.equal(replay.status, 400);
      assert.equal(replay.body.error.code, 'validation_error');
    } finally {
      await app.close();
    }
  });

  await t.test('an expired token is rejected', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetexpired', password: 'oldpassword1' });
      await app.post('/api/auth/password-reset/request', { body: { email: user.email } });
      const token = tokenFromMail(app.mailProvider.sent.at(-1));

      const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
      await app.db
        .prepare('UPDATE password_reset_tokens SET expires_at = ? WHERE token_hash = ?')
        .run(new Date(Date.now() - 1000).toISOString(), tokenHash);

      const res = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'brandnewpassword1' },
      });
      assert.equal(res.status, 400);
    } finally {
      await app.close();
    }
  });

  await t.test('confirm rejects a too-short password before touching the token', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetshortpw', password: 'oldpassword1' });
      await app.post('/api/auth/password-reset/request', { body: { email: user.email } });
      const token = tokenFromMail(app.mailProvider.sent.at(-1));

      const res = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'short' },
      });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.field, 'password');

      // The token must still be usable - the rejected attempt didn't burn it.
      const retry = await app.post('/api/auth/password-reset/confirm', {
        body: { token, password: 'longenoughpassword1' },
      });
      assert.equal(retry.status, 204);
    } finally {
      await app.close();
    }
  });

  await t.test('a mail provider failure does not turn the request into a 500', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'resetmailfail', password: 'oldpassword1' });
      app.mailProvider.throwTimes = 1;
      const res = await app.post('/api/auth/password-reset/request', {
        body: { email: user.email },
      });
      assert.equal(res.status, 204);
    } finally {
      await app.close();
    }
  });
});

test('password reset rate limiting', async (t) => {
  await t.test('request: one attempt past the configured max is rate-limited', async () => {
    const app = await makeApp();
    try {
      for (let i = 0; i < RESET_REQUEST_RATE_LIMIT.max; i++) {
        const res = await app.post('/api/auth/password-reset/request', {
          body: { email: `nobody${i}@example.com` },
        });
        assert.equal(res.status, 204, `attempt ${i + 1} should go through`);
      }
      const blocked = await app.post('/api/auth/password-reset/request', {
        body: { email: 'nobody-over@example.com' },
      });
      assert.equal(blocked.status, 429);
      assert.equal(blocked.body.error.code, 'rate_limited');
    } finally {
      await app.close();
    }
  });

  await t.test('confirm: one attempt past the configured max is rate-limited', async () => {
    const app = await makeApp();
    try {
      for (let i = 0; i < RESET_CONFIRM_RATE_LIMIT.max; i++) {
        const res = await app.post('/api/auth/password-reset/confirm', {
          body: { token: 'a'.repeat(64), password: 'brandnewpassword1' },
        });
        assert.equal(res.status, 400, `attempt ${i + 1} should be a normal invalid-token 400`);
      }
      const blocked = await app.post('/api/auth/password-reset/confirm', {
        body: { token: 'a'.repeat(64), password: 'brandnewpassword1' },
      });
      assert.equal(blocked.status, 429);
    } finally {
      await app.close();
    }
  });
});
