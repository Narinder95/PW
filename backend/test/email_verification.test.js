import test from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { makeApp, makeUser } from './helpers.js';
import { EMAIL_VERIFY_RESEND_RATE_LIMIT, EMAIL_VERIFY_CONFIRM_RATE_LIMIT } from '../src/auth.js';

/** Pulls the raw token out of the plain-text mail body the memory provider captured. */
function tokenFromMail(message) {
  const match = message.text.match(/[0-9a-f]{64}/);
  assert.ok(match, `mail body did not contain a token: ${message.text}`);
  return match[0];
}

test('email verification', async (t) => {
  // Each subtest gets its own app/rate limiter - see password_reset.test.js
  // for why a shared app across subtests trips a tight limit
  // (EMAIL_VERIFY_RESEND_RATE_LIMIT is only 5/hour) well before the file
  // finishes, failing later tests for a reason unrelated to what they assert.

  await t.test('register sends a verification email and /api/me starts unverified', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyreg' });
      assert.equal(app.mailProvider.sent.length, 1);
      assert.equal(app.mailProvider.sent[0].to, user.email);

      const me = await user.get('/api/me');
      assert.equal(me.status, 200);
      assert.equal(me.body.user.emailVerified, false);
    } finally {
      await app.close();
    }
  });

  await t.test('an anonymous account has no email to verify', async () => {
    const app = await makeApp();
    try {
      const res = await app.post('/api/auth/anonymous', { body: {} });
      assert.equal(res.status, 201);
      assert.equal(res.body.user.emailVerified, null);
      assert.equal(app.mailProvider.sent.length, 0);
    } finally {
      await app.close();
    }
  });

  await t.test('confirm sets emailVerified and cannot be replayed', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyconfirm' });
      const token = tokenFromMail(app.mailProvider.sent[0]);

      const confirmRes = await app.post('/api/auth/verify-email/confirm', { body: { token } });
      assert.equal(confirmRes.status, 204);

      const me = await user.get('/api/me');
      assert.equal(me.body.user.emailVerified, true);

      const replay = await app.post('/api/auth/verify-email/confirm', { body: { token } });
      assert.equal(replay.status, 400);
      assert.equal(replay.body.error.code, 'validation_error');
    } finally {
      await app.close();
    }
  });

  await t.test('confirm with an unknown token is 400, not 500', async () => {
    const app = await makeApp();
    try {
      const res = await app.post('/api/auth/verify-email/confirm', { body: { token: 'a'.repeat(64) } });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'validation_error');
    } finally {
      await app.close();
    }
  });

  await t.test('an expired token is rejected', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyexpired' });
      const token = tokenFromMail(app.mailProvider.sent[0]);

      const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
      await app.db
        .prepare('UPDATE email_verification_tokens SET expires_at = ? WHERE token_hash = ?')
        .run(new Date(Date.now() - 1000).toISOString(), tokenHash);

      const res = await app.post('/api/auth/verify-email/confirm', { body: { token } });
      assert.equal(res.status, 400);

      const me = await user.get('/api/me');
      assert.equal(me.body.user.emailVerified, false);
    } finally {
      await app.close();
    }
  });

  await t.test('linking with an email sends a verification email; linking with only a phone does not', async () => {
    const app = await makeApp();
    try {
      const anon = await app.post('/api/auth/anonymous', { body: {} });
      const token = anon.body.token;
      assert.equal(app.mailProvider.sent.length, 0);

      const linked = await app.post('/api/auth/link', {
        token,
        body: { email: 'linked@example.com', password: 'password123' },
      });
      assert.equal(linked.status, 200);
      assert.equal(app.mailProvider.sent.length, 1);
      assert.equal(app.mailProvider.sent[0].to, 'linked@example.com');
      assert.equal(linked.body.user.emailVerified, false);
    } finally {
      await app.close();
    }
  });

  await t.test('resend sends a fresh token that also works', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyresend' });
      assert.equal(app.mailProvider.sent.length, 1);

      const resendRes = await user.post('/api/auth/verify-email/resend');
      assert.equal(resendRes.status, 204);
      assert.equal(app.mailProvider.sent.length, 2);

      const token = tokenFromMail(app.mailProvider.sent.at(-1));
      const confirmRes = await app.post('/api/auth/verify-email/confirm', { body: { token } });
      assert.equal(confirmRes.status, 204);
    } finally {
      await app.close();
    }
  });

  await t.test('resend is a no-op, not an error, once already verified', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyresenddone' });
      const token = tokenFromMail(app.mailProvider.sent[0]);
      await app.post('/api/auth/verify-email/confirm', { body: { token } });

      const resendRes = await user.post('/api/auth/verify-email/resend');
      assert.equal(resendRes.status, 204);
      assert.equal(app.mailProvider.sent.length, 1); // nothing new went out
    } finally {
      await app.close();
    }
  });

  await t.test('resend on an account with no email is 400', async () => {
    const app = await makeApp();
    try {
      const anon = await app.post('/api/auth/anonymous', { body: {} });
      const res = await app.post('/api/auth/verify-email/resend', { token: anon.body.token });
      assert.equal(res.status, 400);
      assert.equal(res.body.error.field, 'email');
    } finally {
      await app.close();
    }
  });

  await t.test('resend requires auth', async () => {
    const app = await makeApp();
    try {
      const res = await app.post('/api/auth/verify-email/resend');
      assert.equal(res.status, 401);
    } finally {
      await app.close();
    }
  });
});

test('email verification rate limiting', async (t) => {
  await t.test('resend: one attempt past the configured max is rate-limited', async () => {
    const app = await makeApp();
    try {
      const user = await makeUser(app, { username: 'verifyresendlimit' });
      for (let i = 0; i < EMAIL_VERIFY_RESEND_RATE_LIMIT.max; i++) {
        const res = await user.post('/api/auth/verify-email/resend');
        assert.equal(res.status, 204, `attempt ${i + 1} should go through`);
      }
      const blocked = await user.post('/api/auth/verify-email/resend');
      assert.equal(blocked.status, 429);
      assert.equal(blocked.body.error.code, 'rate_limited');
    } finally {
      await app.close();
    }
  });

  await t.test('confirm: one attempt past the configured max is rate-limited', async () => {
    const app = await makeApp();
    try {
      for (let i = 0; i < EMAIL_VERIFY_CONFIRM_RATE_LIMIT.max; i++) {
        const res = await app.post('/api/auth/verify-email/confirm', { body: { token: 'a'.repeat(64) } });
        assert.equal(res.status, 400, `attempt ${i + 1} should be a normal invalid-token 400`);
      }
      const blocked = await app.post('/api/auth/verify-email/confirm', { body: { token: 'a'.repeat(64) } });
      assert.equal(blocked.status, 429);
    } finally {
      await app.close();
    }
  });
});
