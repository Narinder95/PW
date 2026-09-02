// Registration, login, logout, /api/me, and the requireAuth middleware.
//
// Passwords: scrypt with a per-user 16-byte random salt, stored as
// "<saltHex>:<hashHex>". Verification is constant-time. Plaintext passwords are
// never stored and never logged.
import crypto from 'node:crypto';
import { ApiError, newId, nowISO, requireString, normalizeColor, sendJson, sendNoContent } from './http.js';
import { avatarColorFor, publicUser, privateUser } from './domain.js';

const SCRYPT_KEYLEN = 64;
const USERNAME_RE = /^[a-z0-9_]+$/;

export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, SCRYPT_KEYLEN);
  return `${salt.toString('hex')}:${hash.toString('hex')}`;
}

export function verifyPassword(password, stored) {
  if (typeof stored !== 'string' || !stored.includes(':')) return false;
  const [saltHex, hashHex] = stored.split(':');
  let expected;
  try {
    expected = Buffer.from(hashHex, 'hex');
  } catch {
    return false;
  }
  if (expected.length === 0) return false;
  let actual;
  try {
    actual = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length);
  } catch {
    return false;
  }
  if (actual.length !== expected.length) return false;
  return crypto.timingSafeEqual(actual, expected);
}

export function newToken() {
  return crypto.randomBytes(32).toString('hex');
}

export function createSession(db, userId) {
  const token = newToken();
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run(token, userId, nowISO());
  return token;
}

// --------------------------------------------------------------- validation

function validateUsername(raw) {
  if (typeof raw !== 'string') throw ApiError.validation('username is required', 'username');
  const username = raw.trim().toLowerCase();
  if (username.length < 3 || username.length > 20) {
    throw ApiError.validation('username must be 3-20 characters', 'username');
  }
  if (!USERNAME_RE.test(username)) {
    throw ApiError.validation('username may only contain a-z, 0-9 and _', 'username');
  }
  return username;
}

function validateEmail(raw) {
  if (typeof raw !== 'string') throw ApiError.validation('email is required', 'email');
  const email = raw.trim().toLowerCase();
  if (!email.includes('@') || email.length < 3 || email.length > 254) {
    throw ApiError.validation('email must be a valid address', 'email');
  }
  return email;
}

function validatePassword(raw) {
  if (typeof raw !== 'string') throw ApiError.validation('password is required', 'password');
  if (raw.length < 8) throw ApiError.validation('password must be at least 8 characters', 'password');
  if (raw.length > 200) throw ApiError.validation('password must be at most 200 characters', 'password');
  return raw;
}

// ------------------------------------------------------------------ helpers

/**
 * Create a user directly (used by /register and by the seeder).
 * @throws {ApiError} 409 on duplicate username/email.
 */
export function createUser(db, { username, name, email, password, avatarColor = null, id = null, createdAt = null }) {
  const u = validateUsername(username);
  const n = typeof name === 'string' ? name.trim() : '';
  if (n.length < 1 || n.length > 40) throw ApiError.validation('name must be 1-40 characters', 'name');
  const e = validateEmail(email);
  const p = validatePassword(password);

  if (db.prepare('SELECT 1 AS x FROM users WHERE username = ?').get(u)) {
    throw ApiError.conflict('That username is already taken');
  }
  if (db.prepare('SELECT 1 AS x FROM users WHERE email = ?').get(e)) {
    throw ApiError.conflict('That email is already registered');
  }

  const at = createdAt ?? nowISO();
  const row = {
    id: id ?? newId('u'),
    username: u,
    name: n,
    email: e,
    phone: null,
    password_hash: hashPassword(p),
    is_anonymous: 0,
    avatar_color: normalizeColor(avatarColor) ?? avatarColorFor(u),
    created_at: at,
    last_active_at: at,
  };
  db.prepare(
    `INSERT INTO users (id, username, name, email, phone, password_hash, is_anonymous,
                        avatar_color, created_at, last_active_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    row.id, row.username, row.name, row.email, row.phone, row.password_hash,
    row.is_anonymous, row.avatar_color, row.created_at, row.last_active_at
  );
  return row;
}

/** Uniform random integer in [0, max). Uses the CSPRNG we already import. */
function randomInt(max) {
  return crypto.randomInt(max);
}

/** Adjective-noun handles, so an auto-made account reads like a person. */
const HANDLE_ADJECTIVES = [
  'swift', 'calm', 'bright', 'brave', 'keen', 'sunny', 'bold', 'quiet',
  'lucky', 'nimble', 'steady', 'clever', 'warm', 'eager', 'kind',
];
const HANDLE_NOUNS = [
  'otter', 'falcon', 'cedar', 'comet', 'ember', 'river', 'fox', 'heron',
  'maple', 'orbit', 'pine', 'quartz', 'raven', 'sparrow', 'willow',
];

/**
 * Create an account with no credentials at all.
 *
 * This is how every user starts: the app provisions one silently on first
 * launch, so there is no sign-up wall. The account is real in every other
 * respect — it has an id, a handle, friends, habits. It simply cannot be
 * recovered on another device until it is claimed via [linkCredentials].
 */
export function createAnonymousUser(db, { name = null, avatarColor = null } = {}) {
  let username = null;
  for (let attempt = 0; attempt < 40 && username === null; attempt++) {
    const adjective = HANDLE_ADJECTIVES[randomInt(HANDLE_ADJECTIVES.length)];
    const noun = HANDLE_NOUNS[randomInt(HANDLE_NOUNS.length)];
    const suffix = String(randomInt(10000)).padStart(4, '0');
    const candidate = `${adjective}_${noun}${suffix}`.slice(0, 20);
    if (!db.prepare('SELECT 1 AS x FROM users WHERE username = ?').get(candidate)) {
      username = candidate;
    }
  }
  // Vanishingly unlikely, but never hand back a collision.
  username ??= `user_${newId('').replace(/[^a-z0-9]/gi, '').toLowerCase().slice(0, 14)}`;

  const displayName =
    typeof name === 'string' && name.trim().length >= 1 && name.trim().length <= 40
      ? name.trim()
      : username.split('_').map((p) => p.charAt(0).toUpperCase() + p.slice(1)).join(' ');

  const at = nowISO();
  const row = {
    id: newId('u'),
    username,
    name: displayName,
    email: null,
    phone: null,
    password_hash: null,
    is_anonymous: 1,
    avatar_color: normalizeColor(avatarColor) ?? avatarColorFor(username),
    created_at: at,
    last_active_at: at,
  };
  db.prepare(
    `INSERT INTO users (id, username, name, email, phone, password_hash, is_anonymous,
                        avatar_color, created_at, last_active_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).run(
    row.id, row.username, row.name, row.email, row.phone, row.password_hash,
    row.is_anonymous, row.avatar_color, row.created_at, row.last_active_at
  );
  return row;
}

/** Basic E.164-ish normalisation. Deliberately permissive — no SMS yet. */
export function validatePhone(phone) {
  if (typeof phone !== 'string') throw ApiError.validation('phone must be a string', 'phone');
  const cleaned = phone.replace(/[\s()\-.]/g, '');
  if (!/^\+?[0-9]{7,15}$/.test(cleaned)) {
    throw ApiError.validation('phone must be 7-15 digits, optionally starting with +', 'phone');
  }
  return cleaned;
}

/**
 * Claim an anonymous account by attaching an email and/or phone plus a
 * password, so it can be recovered on another device.
 */
export function linkCredentials(db, userId, { email, phone, password, username }) {
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
  if (!user) throw ApiError.notFound('No such user');
  if (!user.is_anonymous) {
    throw ApiError.conflict('This account is already linked');
  }
  if (email === undefined && phone === undefined) {
    throw ApiError.validation('Provide an email or a phone number', 'email');
  }

  const e = email === undefined || email === null ? null : validateEmail(email);
  const p = phone === undefined || phone === null ? null : validatePhone(phone);
  if (e === null && p === null) {
    throw ApiError.validation('Provide an email or a phone number', 'email');
  }
  const pw = validatePassword(password);

  if (e && db.prepare('SELECT 1 AS x FROM users WHERE email = ? AND id != ?').get(e, userId)) {
    throw ApiError.conflict('That email is already registered');
  }
  if (p && db.prepare('SELECT 1 AS x FROM users WHERE phone = ? AND id != ?').get(p, userId)) {
    throw ApiError.conflict('That phone number is already registered');
  }

  // Claiming is a natural moment to pick a real handle.
  let u = user.username;
  if (username !== undefined && username !== null) {
    u = validateUsername(username);
    if (u !== user.username &&
        db.prepare('SELECT 1 AS x FROM users WHERE username = ?').get(u)) {
      throw ApiError.conflict('That username is already taken');
    }
  }

  db.prepare(
    `UPDATE users
        SET email = ?, phone = ?, password_hash = ?, username = ?, is_anonymous = 0
      WHERE id = ?`
  ).run(e, p, hashPassword(pw), u, userId);

  return db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
}

/** Resolve a bearer token (header or ?token=) to a user row. */
export function authenticate(db, req, url) {
  const header = req.headers['authorization'] ?? req.headers['Authorization'];
  let token = null;
  if (typeof header === 'string' && header.toLowerCase().startsWith('bearer ')) {
    token = header.slice(7).trim();
  }
  // EventSource cannot set headers, so the contract also allows ?token=.
  if (!token && url) token = url.searchParams.get('token');
  if (!token) throw ApiError.unauthorized('Missing bearer token');

  const session = db.prepare('SELECT * FROM sessions WHERE token = ?').get(token);
  if (!session) throw ApiError.unauthorized('Invalid or expired token');
  const user = db.prepare('SELECT * FROM users WHERE id = ?').get(session.user_id);
  if (!user) throw ApiError.unauthorized('Invalid or expired token');

  const at = nowISO();
  db.prepare('UPDATE users SET last_active_at = ? WHERE id = ?').run(at, user.id);
  user.last_active_at = at;
  return { user, token };
}

// ------------------------------------------------------------------- routes

export function registerAuthRoutes(router, ctx) {
  const { db } = ctx;

  router.post('/api/auth/register', async ({ res, body }) => {
    const user = createUser(db, {
      username: body.username,
      name: body.name,
      email: body.email,
      password: body.password,
      avatarColor: body.avatarColor,
    });
    const token = createSession(db, user.id);
    sendJson(res, 201, { token, user: publicUser(user) });
  });

  /**
   * Provision an account with no credentials. This is what the app calls on
   * first launch instead of showing a sign-up screen.
   */
  router.post('/api/auth/anonymous', async ({ res, body }) => {
    const user = createAnonymousUser(db, {
      name: body?.name,
      avatarColor: body?.avatarColor,
    });
    const token = createSession(db, user.id);
    sendJson(res, 201, { token, user: privateUser(user) });
  });

  /** Claim the current anonymous account with an email and/or phone. */
  router.post('/api/auth/link', async ({ res, body, me }) => {
    const updated = linkCredentials(db, me.id, {
      email: body.email,
      phone: body.phone,
      password: body.password,
      username: body.username,
    });
    sendJson(res, 200, { user: privateUser(updated) });
  }, { auth: true });

  router.post('/api/auth/login', async ({ res, body }) => {
    const raw = body.usernameOrEmail;
    if (typeof raw !== 'string' || raw.trim().length === 0) {
      throw ApiError.validation('usernameOrEmail is required', 'usernameOrEmail');
    }
    if (typeof body.password !== 'string' || body.password.length === 0) {
      throw ApiError.validation('password is required', 'password');
    }
    const key = raw.trim().toLowerCase();
    const phoneKey = key.replace(/[\s()\-.]/g, '');
    const user =
      db.prepare('SELECT * FROM users WHERE username = ?').get(key) ??
      db.prepare('SELECT * FROM users WHERE email = ?').get(key) ??
      db.prepare('SELECT * FROM users WHERE phone = ?').get(phoneKey);

    // Same 401 whether the user is unknown, unclaimed, or the password is
    // wrong — an anonymous account has no password_hash and must never be
    // reachable by guessing its handle.
    if (!user || !user.password_hash || !verifyPassword(body.password, user.password_hash)) {
      throw ApiError.unauthorized('Incorrect username or password');
    }
    const token = createSession(db, user.id);
    sendJson(res, 200, { token, user: publicUser(user) });
  });

  router.post('/api/auth/logout', async ({ res, token, me }) => {
    db.prepare('DELETE FROM sessions WHERE token = ?').run(token);
    // A signed-out handset must stop receiving this account's pushes.
    db.prepare('DELETE FROM devices WHERE user_id = ?').run(me.id);
    sendNoContent(res);
  }, { auth: true });

  router.get('/api/me', async ({ res, me }) => {
    sendJson(res, 200, { user: privateUser(me) });
  }, { auth: true });

  router.patch('/api/me', async ({ res, body, me }) => {
    const updates = {};
    if (body.name !== undefined) updates.name = requireString(body, 'name', { min: 1, max: 40 });
    if (body.avatarColor !== undefined) updates.avatar_color = normalizeColor(body.avatarColor, 'avatarColor');
    if (Object.keys(updates).length > 0) {
      const sets = Object.keys(updates).map((k) => `${k} = ?`).join(', ');
      db.prepare(`UPDATE users SET ${sets} WHERE id = ?`).run(...Object.values(updates), me.id);
    }
    const fresh = db.prepare('SELECT * FROM users WHERE id = ?').get(me.id);
    sendJson(res, 200, { user: privateUser(fresh) });
  }, { auth: true });
}
