// Database layer: open/migrate SQLite via node:sqlite (no npm deps).
// openDb(':memory:') is fully in-memory so tests never touch the filesystem.
import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

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
-- index allows in SQLite, but being explicit documents the intent.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;

-- sessions.token is the PRIMARY KEY, which in SQLite is itself a unique index,
-- so token lookups (the hot path on every request) are already indexed.
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
CREATE TABLE IF NOT EXISTS activities (
  id          TEXT PRIMARY KEY,
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

/**
 * Open (and migrate) the database.
 * @param {string} filePath absolute path, or ':memory:' for an in-memory db.
 */
export function openDb(filePath = ':memory:') {
  if (filePath !== ':memory:') {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
  }
  const db = new DatabaseSync(filePath);
  if (filePath !== ':memory:') {
    try {
      db.exec('PRAGMA journal_mode = WAL;');
    } catch {
      /* WAL is a nicety, not a requirement */
    }
  }
  db.exec('PRAGMA foreign_keys = ON;');
  migrate(db);
  return db;
}

export function migrate(db) {
  // `meta` first and alone: we must know the schema version *before* running
  // the full DDL, because the v2 DDL creates an index on `users.phone`, a
  // column a v1 database does not have yet. `CREATE TABLE IF NOT EXISTS users`
  // is a no-op on an existing table, so the index would fail against v1.
  db.exec('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);');
  const row = db.prepare('SELECT value FROM meta WHERE key = ?').get('schema_version');
  const current = row ? Number(row.value) : 0;

  if (current > 0 && current < 2) migrateV1toV2(db);

  db.exec(DDL);

  if (current < SCHEMA_VERSION) {
    db.prepare('INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
      .run('schema_version', String(SCHEMA_VERSION));
  }
  return SCHEMA_VERSION;
}

/**
 * v1 -> v2: drop NOT NULL from `email`/`password_hash`, add `phone` and
 * `is_anonymous`.
 *
 * SQLite cannot relax NOT NULL with ALTER TABLE, so the table is rebuilt.
 * Existing rows all had real credentials, so they become `is_anonymous = 0`.
 */
function migrateV1toV2(db) {
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  if (columns.includes('is_anonymous')) return; // already rebuilt

  db.exec('PRAGMA foreign_keys = OFF;');
  db.exec('BEGIN');
  try {
    db.exec(`
      CREATE TABLE users_v2 (
        id             TEXT PRIMARY KEY,
        username       TEXT NOT NULL UNIQUE,
        name           TEXT NOT NULL,
        email          TEXT UNIQUE,
        phone          TEXT UNIQUE,
        password_hash  TEXT,
        is_anonymous   INTEGER NOT NULL DEFAULT 1,
        avatar_color   TEXT NOT NULL,
        created_at     TEXT NOT NULL,
        last_active_at TEXT NOT NULL
      );
      INSERT INTO users_v2
        (id, username, name, email, phone, password_hash, is_anonymous,
         avatar_color, created_at, last_active_at)
      SELECT id, username, name, email, NULL, password_hash, 0,
             avatar_color, created_at, last_active_at
        FROM users;
      DROP TABLE users;
      ALTER TABLE users_v2 RENAME TO users;
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username);
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(email) WHERE email IS NOT NULL;
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
    `);
    db.exec('COMMIT');
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  } finally {
    db.exec('PRAGMA foreign_keys = ON;');
  }
}

export { SCHEMA_VERSION };
