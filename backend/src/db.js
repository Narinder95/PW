// Database layer: Postgres (via `pg`), replacing the original node:sqlite
// layer. Every table/column name is unchanged, and `prepare(sql)` below
// keeps node:sqlite's exact calling convention (`.get(...)/.all(...)/.run(...)`
// with positional `?` placeholders) - only *async* - so every call site
// elsewhere in the codebase needed `await` added, never a rewritten query.
import pg from 'pg';
import crypto from 'node:crypto';

// v2: accounts are created anonymously (no email, no password) and may later
//     be *claimed* by linking an email and/or phone. `email` and
//     `password_hash` therefore became nullable, and `phone` / `is_anonymous`
//     were added.
const SCHEMA_VERSION = 2;

const DDL = `
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- email/password_hash/phone are NULL for an anonymous account. They are filled
-- in when the user claims the account via POST /api/auth/link.
CREATE TABLE IF NOT EXISTS users (
  id             TEXT PRIMARY KEY,
  username       TEXT NOT NULL UNIQUE,
  name           TEXT NOT NULL,
  email          TEXT UNIQUE,
  phone          TEXT UNIQUE,
  password_hash  TEXT,                    -- scrypt: "<saltHex>:<hashHex>"
  is_anonymous   INTEGER NOT NULL DEFAULT 1,
  avatar_color   TEXT NOT NULL,
  created_at     TEXT NOT NULL,
  last_active_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username);
-- Partial indexes: many rows legitimately share NULL, which a plain UNIQUE
-- index allows, but being explicit documents the intent.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;

CREATE TABLE IF NOT EXISTS sessions (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);

CREATE TABLE IF NOT EXISTS habits (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  icon       TEXT NOT NULL,
  color      TEXT NOT NULL,
  target     INTEGER NOT NULL,
  unit       TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_habits_user ON habits(user_id);
-- A user's habit name must be unique case/whitespace-insensitively (the
-- client keys habits by name.trim().toLowerCase() to line them up with the
-- catalogue). With node:sqlite this was enforced only at the app layer,
-- which was safe because a request handler with no internal await could
-- never interleave with another. Postgres queries are genuinely async, so
-- that safety no longer holds - this index is the real guarantee, and the
-- app-layer check in habits.js is now just a friendlier error message ahead
-- of the constraint violation this index would otherwise throw.
CREATE UNIQUE INDEX IF NOT EXISTS idx_habits_user_name ON habits(user_id, lower(trim(name)));

CREATE TABLE IF NOT EXISTS habit_logs (
  id         TEXT PRIMARY KEY,
  habit_id   TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date       TEXT NOT NULL,               -- YYYY-MM-DD (UTC)
  progress   INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE(habit_id, date)
);
CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, date);
CREATE INDEX IF NOT EXISTS idx_habit_logs_user_date  ON habit_logs(user_id, date);

-- UNIQUE(habit_id, date) is what makes POST /habits/:id/log idempotent w.r.t.
-- activity creation: crossing the target twice on one day cannot insert twice.
-- seq is a pure insertion-order tiebreaker for the feed's ORDER BY - the
-- SQLite original used the implicit rowid for this, which Postgres has no
-- equivalent of.
CREATE TABLE IF NOT EXISTS activities (
  id          TEXT PRIMARY KEY,
  seq         BIGSERIAL,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id    TEXT REFERENCES habits(id) ON DELETE CASCADE,
  habit_name  TEXT NOT NULL,
  habit_icon  TEXT NOT NULL,
  habit_color TEXT NOT NULL,
  completion  TEXT NOT NULL,
  date        TEXT NOT NULL,
  created_at  TEXT NOT NULL,
  UNIQUE(habit_id, date)
);
CREATE INDEX IF NOT EXISTS idx_activities_user_created ON activities(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS friendships (
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  friend_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, friend_id)
);
CREATE INDEX IF NOT EXISTS idx_friendships_user   ON friendships(user_id);
CREATE INDEX IF NOT EXISTS idx_friendships_friend ON friendships(friend_id);

CREATE TABLE IF NOT EXISTS friend_requests (
  id           TEXT PRIMARY KEY,
  from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status       TEXT NOT NULL DEFAULT 'pending',  -- pending|accepted|declined|cancelled
  created_at   TEXT NOT NULL,
  responded_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_fr_to   ON friend_requests(to_user_id, status);
CREATE INDEX IF NOT EXISTS idx_fr_from ON friend_requests(from_user_id, status);
-- Two concurrent POST /api/friend-requests between the same pair could both
-- pass the "no pending request yet" check before either had inserted - safe
-- under the old synchronous node:sqlite (no interleaving was possible), not
-- safe against genuinely async Postgres queries. This is the real guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS idx_fr_pending_pair
  ON friend_requests(from_user_id, to_user_id) WHERE status = 'pending';

CREATE TABLE IF NOT EXISTS nudges (
  id           TEXT PRIMARY KEY,
  type         TEXT NOT NULL DEFAULT 'nudge',    -- nudge|cheer
  from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  to_user_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  habit_id     TEXT,
  habit_name   TEXT NOT NULL,
  habit_icon   TEXT,
  habit_color  TEXT,
  message      TEXT,
  status       TEXT NOT NULL DEFAULT 'pending',  -- pending|accepted
  created_at   TEXT NOT NULL,
  accepted_at  TEXT
);
CREATE INDEX IF NOT EXISTS idx_nudges_to       ON nudges(to_user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nudges_from     ON nudges(from_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nudges_cooldown ON nudges(from_user_id, to_user_id, habit_name, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id           TEXT PRIMARY KEY,
  seq          BIGSERIAL, -- insertion-order tiebreaker; see the note on activities.seq above
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type         TEXT NOT NULL,
  title        TEXT NOT NULL,
  body         TEXT NOT NULL,
  actor_id     TEXT,
  actor_name   TEXT,
  avatar_color TEXT,
  icon         TEXT,
  color        TEXT,
  ref_type     TEXT,
  ref_id       TEXT,
  read         INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON notifications(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read    ON notifications(user_id, read);

-- token is globally UNIQUE (not just per user) so that a handset which changes
-- accounts can be reassigned to the new owner instead of double-registering.
CREATE TABLE IF NOT EXISTS devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token        TEXT NOT NULL UNIQUE,
  platform     TEXT NOT NULL,                  -- android|ios|web
  app_version  TEXT,
  created_at   TEXT NOT NULL,
  last_seen_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id);

-- One row per user per calendar day, upserted from the device's health data
-- (Health Connect / HealthKit) via POST /api/steps/sync. Drives the walking
-- challenge state computed in domain.js — there is no separate "current
-- level" row to keep in sync, it's recomputed from this history every time.
CREATE TABLE IF NOT EXISTS daily_steps (
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date       TEXT NOT NULL,               -- YYYY-MM-DD (UTC), same convention as habit_logs
  steps      INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, date)
);

CREATE TABLE IF NOT EXISTS push_deliveries (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL,
  device_id       TEXT NOT NULL,
  notification_id TEXT NOT NULL,
  provider        TEXT NOT NULL,
  status          TEXT NOT NULL,  -- queued|sent|skipped|failed|invalid_token
  error           TEXT,
  created_at      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_user   ON push_deliveries(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_notif  ON push_deliveries(notification_id);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_status ON push_deliveries(status);
`;

/** `?` placeholders (node:sqlite style) -> `$1, $2, ...` (Postgres style). */
function toPositional(sql) {
  let i = 0;
  return sql.replace(/\?/g, () => `$${++i}`);
}

/**
 * Mirrors node:sqlite's `StatementSync` just enough for this codebase:
 * `.get(...params)` / `.all(...params)` / `.run(...params)`, but Promise-based.
 * Every call site was written against the synchronous node:sqlite API with
 * bare `?` placeholders; this shim is what lets every one of those SQL
 * strings keep working unmodified against Postgres - only `await` is new.
 */
class Statement {
  constructor(pool, sql) {
    this.pool = pool;
    this.sql = toPositional(sql);
  }

  async get(...params) {
    const { rows } = await this.pool.query(this.sql, params);
    return rows[0];
  }

  async all(...params) {
    const { rows } = await this.pool.query(this.sql, params);
    return rows;
  }

  async run(...params) {
    const res = await this.pool.query(this.sql, params);
    return { changes: res.rowCount };
  }
}

class Db {
  constructor(pool) {
    this.pool = pool;
  }

  prepare(sql) {
    return new Statement(this.pool, sql);
  }

  async exec(sql) {
    await this.pool.query(sql);
  }

  async close() {
    await this.pool.end();
  }

  /**
   * Runs `fn(txDb)` inside a real transaction, on one dedicated physical
   * connection - `fn` must issue every statement through the `txDb` it is
   * given, not the outer `db`. This matters specifically because a `pg.Pool`
   * hands out a different physical connection per `.query()` call in
   * general: without pinning to one connection, a `BEGIN` on one connection
   * would have no relationship to a later statement run on another.
   */
  async withTransaction(fn) {
    const isPool = this.pool instanceof pg.Pool;
    const client = isPool ? await this.pool.connect() : this.pool;
    const txDb = new Db(client);
    try {
      await txDb.exec('BEGIN');
      const result = await fn(txDb);
      await txDb.exec('COMMIT');
      return result;
    } catch (err) {
      try {
        await txDb.exec('ROLLBACK');
      } catch {
        /* connection may already be dead - the original error is what matters */
      }
      throw err;
    } finally {
      if (isPool) client.release();
    }
  }
}

/** Postgres error code for a unique-constraint violation. */
export const UNIQUE_VIOLATION = '23505';

/**
 * Neon (and most managed Postgres) expose both a pooled endpoint (hostname
 * has a `-pooler` segment) and the plain direct one behind it. Schema
 * isolation needs the direct one - see the note on `openDb`'s `schema`
 * option below for why.
 */
function directConnectionString(connectionString) {
  try {
    const url = new URL(connectionString);
    url.hostname = url.hostname.replace(/-pooler(?=[.-])/, '');
    return url.toString();
  } catch {
    return connectionString;
  }
}

/**
 * @param {string} connectionString a Postgres connection URI (e.g. Neon's).
 * @param {object} [opts]
 * @param {string} [opts.schema] isolate this connection to its own schema —
 *   tests use this the way they used to use SQLite's `:memory:`: one fresh,
 *   disposable namespace per test file, on the same shared database.
 *
 *   Implemented as a single dedicated `pg.Client` against the *direct*
 *   (non-pooled) connection string, not a `pg.Pool` and not the pooled
 *   endpoint the app itself uses. Two independent reasons, both fatal on
 *   their own:
 *     1. Neon's pooled endpoint (PgBouncer, transaction mode) rejects
 *        `search_path` as a *startup* parameter outright.
 *     2. Even setting it with a regular `SET search_path` query afterwards
 *        is not reliable through that pooler: transaction-mode pooling can
 *        hand a client's TCP connection a *different* backend Postgres
 *        process for its next statement, silently dropping whatever
 *        session state was set on the previous one. This is invisible at
 *        low concurrency (the pooler often happens to reuse the same
 *        backend) and shows up as a wave of unrelated-looking failures the
 *        moment several test files run at once. A *direct* connection has
 *        no such reassignment - the TCP connection *is* the backend
 *        session for its whole lifetime, so `SET search_path` sticks.
 */
export async function openDb(connectionString, { schema } = {}) {
  const conn = schema
    ? new pg.Client({ connectionString: directConnectionString(connectionString) })
    : new pg.Pool({ connectionString, max: 10 });
  if (schema) await conn.connect();

  const db = new Db(conn);
  db.schema = schema ?? null;

  if (schema) {
    await db.exec(`CREATE SCHEMA IF NOT EXISTS "${schema}"`);
    await db.exec(`SET search_path TO "${schema}", public`);
  }

  await migrate(db);
  return db;
}

/** Drops a schema created via `openDb(url, { schema })`. Test cleanup only. */
export async function dropSchema(connectionString, schema) {
  const pool = new pg.Pool({ connectionString, max: 1 });
  try {
    await pool.query(`DROP SCHEMA IF EXISTS "${schema}" CASCADE`);
  } finally {
    await pool.end();
  }
}

/** Random schema name for test isolation. Postgres identifiers can't start with a digit. */
export function randomSchemaName() {
  return `test_${crypto.randomBytes(8).toString('hex')}`;
}

export async function migrate(db) {
  await db.exec('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);');
  await db.exec(DDL);
  // `CREATE TABLE IF NOT EXISTS` never alters a table that already existed
  // under an earlier version of this DDL - unlike `CREATE INDEX IF NOT
  // EXISTS` above, which is safely re-run every time regardless. A column
  // added after a table's first deploy needs its own explicit step here.
  await db.exec('ALTER TABLE activities ADD COLUMN IF NOT EXISTS seq BIGSERIAL;');
  await db.exec('ALTER TABLE notifications ADD COLUMN IF NOT EXISTS seq BIGSERIAL;');
  await db
    .prepare('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
    .run('schema_version', String(SCHEMA_VERSION));
  return SCHEMA_VERSION;
}

export { SCHEMA_VERSION };
