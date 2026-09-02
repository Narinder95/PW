# PW backend

The API behind the PW app's Journal and Friends features: habits, friends,
friend requests, match suggestions, nudges, the activity feed, and the whole
notification system (records, unread counts, live SSE delivery, and push).

**Zero npm dependencies.** Node builtins only — `node:http`, `node:sqlite`,
`node:crypto`, `node:test`. There is nothing to `npm install`.

## Requirements

Node **>= 24** (for a stable `node:sqlite`). Check with `node --version`.

## Run it

```bash
cd backend
node src/seed.js      # optional: demo users and 30 days of history
node src/index.js     # listens on 0.0.0.0:8080
```

```bash
curl -s http://localhost:8080/api/health
```

| script | does |
|---|---|
| `npm start` | run the server |
| `npm run dev` | run with `--watch` |
| `npm test` | `node --test test/*.test.js` |
| `npm run seed` | (re)seed `data/pw.db` — idempotent |
| `npm run test-account` | wire your handset's account into the demo social graph (below) |
| `npm run purge` | delete throwaway accounts left by the Flutter live tests |

`PORT` overrides the port. The server binds `0.0.0.0`, so an Android emulator
reaches it at **`http://10.0.2.2:8080`** (`localhost` inside the emulator is the
emulator itself). The Flutter client picks the right host automatically.

Data lives in `backend/data/pw.db` (gitignored). Delete the file for a clean
slate, then re-seed.

## Demo accounts

These exist so the social graph is not empty. Password for every seeded
account: **`password123`** — though note the **app has no login screen**, so
these are reached by scripts and tests, not by signing in on the handset.

| username | name | why it exists |
|---|---|---|
| `alexr` | Alex Rivera | **primary demo** — 9-day streak, 4 habits, 3 friends, 1 incoming friend request, 2 pending nudges, unread notifications |
| `taylorm` | Taylor Mills | 22-day streak, 6 habits — proves streaks outlive the 7-day window |
| `jordanp` | Jordan Park | 5-day streak, today already complete |
| `samk` | Sam Keller | *not* Alex's friend — shows up as a match suggestion |
| `priyan` | Priya Nair | 14-day streak, 100% today |
| `devong` | Devon Grant | **no habits at all** — the zero-state friend (streak 0, 0/0). Use it to catch divide-by-zero in the UI. |

### Testing with a real account — there is no login screen

The app provisions an **anonymous account** on first launch (`POST
/api/auth/anonymous`), so you never sign in. That account starts empty, which
makes the Friends page look bare. To wire whichever account your handset just
created into the seeded social graph:

```bash
node src/seed.js && node src/index.js   # one shell
# now open the app once, so it provisions its account
npm run test-account                    # another shell
```

It targets the newest non-seed account, mints a session for it directly (an
anonymous account has no password to log in with), and gives it:

- 4 habits with 12 days of history — two done today, two in progress
- 3 friends (Taylor 22-day streak, Priya 14, Alex 9)
- 1 incoming friend request from `samk`
- 2 pending nudges (one nudge, one cheer)
- unread notifications
- `jordanp` left a stranger, so search and suggestions have something to find

Then pull-to-refresh in the app.

| flag | does |
|---|---|
| `--list` | show recent accounts without changing anything |
| `--handle <username>` | target a specific account instead of the newest |

The older `test` / `test1234` account still exists and is *linked*, but with no
login screen the app cannot reach it — use `--handle test` if you want to keep
using it.

### The seed is date-anchored — re-seed if it looks stale

`seed.js` writes habit logs relative to **the day you run it**, and it
deliberately leaves "today" partially complete. Come back tomorrow and that
partial day is a genuine missed day, so streaks legitimately collapse to 0.
That is the streak logic working correctly, not a bug.

If the demo data looks wrong after a day or two, rebuild it:

```bash
rm -f data/pw.db && node src/seed.js && npm run test-account
```

The server holds the file open, so stop it first.

### Keep the demo database clean

`test/live_backend_test.dart` runs the real Flutter client against this
server, so every run **registers real accounts** (prefixed `ztest`). Left
alone they pile up and pollute search results and match suggestions. After
running the Flutter suite:

```bash
npm run purge
```

It only removes accounts matching the ephemeral pattern; the seeded users and
`test` are protected explicitly.

## API

`docs/API_CONTRACT.md` (repo root) is the authoritative spec — request/response
shapes, error codes, and every edge-case rule. Summary:

```
GET    /api/health

POST   /api/auth/anonymous       POST /api/auth/link
POST   /api/auth/register        POST /api/auth/login       POST /api/auth/logout
GET    /api/me                   PATCH /api/me

GET    /api/habits               POST /api/habits
PATCH  /api/habits/:id           DELETE /api/habits/:id
POST   /api/habits/:id/log

GET    /api/friends              GET  /api/friends/:id
DELETE /api/friends/:id          GET  /api/friends/:id/compare

GET    /api/users/search?q=      GET  /api/match/suggestions

GET    /api/friend-requests      POST /api/friend-requests
POST   /api/friend-requests/:id/accept
POST   /api/friend-requests/:id/decline
DELETE /api/friend-requests/:id

GET    /api/activity

GET    /api/nudges               POST /api/nudges
POST   /api/nudges/:id/accept

GET    /api/notifications        GET  /api/notifications/unread-count
POST   /api/notifications/:id/read
POST   /api/notifications/read-all
DELETE /api/notifications/:id
GET    /api/notifications/stream        (SSE)

POST   /api/devices              DELETE /api/devices/:token
```

Auth is `Authorization: Bearer <token>`. The SSE stream also accepts
`?token=` because `EventSource` cannot set headers.

## How streaks are defined

A **habit** streak is the number of consecutive days, ending today, on which
that habit hit its target. If today is not complete yet the count runs back
from yesterday, so an in-progress day never zeroes out the streak you already
earned.

A **user** streak (`streakDays`) is the same idea applied to *all* of that
user's active habits: days on which every habit was completed. A user with no
habits has a streak of 0.

Both are computed over the **full log history**, not the 7-day `weekData`
window — a 30-day streak reports `30`. `weekData` is only the week strip.
`test/regressions.test.js` pins this down.

## Push notifications

Fully implemented behind a provider interface and **inert until credentials
are supplied**. Select with `PUSH_PROVIDER`:

| value | behaviour |
|---|---|
| `none` *(default)* | no-op, but still records the attempt in `push_deliveries` as `skipped`, so the path stays observable |
| `log` | prints the rendered payload — the best way to see push working with no credentials |
| `memory` | in-process capture, used by the tests |
| `fcm` | real Firebase Cloud Messaging HTTP v1 (Android **and** iOS via APNs-through-FCM) |

```bash
PUSH_PROVIDER=fcm
FCM_PROJECT_ID=your-firebase-project-id
FCM_SERVICE_ACCOUNT_FILE=./secrets/fcm-service-account.json
```

`GET /api/health` reports the provider actually in use. A misconfigured `fcm`
provider logs a warning and degrades to `none` rather than taking down the
server on boot.

FCM auth is a self-signed RS256 JWT built with `node:crypto` and exchanged for
an OAuth2 token — no `firebase-admin`, no dependency.

Delivery is fire-and-forget: **a push failure can never fail the API request
that created the notification.** Failures retry twice (1s, 4s); an
`invalid_token` result deletes the device row so dead tokens self-clean.

**What you must supply at release, and where it goes: `docs/PUSH_SETUP.md`.**
Never commit `backend/secrets/`.

## Tests

```bash
npm test
```

136 tests across 11 suites, all against an in-memory database and a real HTTP
server on an ephemeral port — no fixtures on disk, no network, no ordering
dependencies between tests.

| suite | covers |
|---|---|
| `auth` | registration/login validation, token lifecycle, password hashing, no user enumeration, malformed JSON, CORS |
| `habits` | CRUD, log-sets-not-increments, exactly-one-activity on completion, weekData layout, streak maths |
| `friends` | list ordering, detail, habit status, unfriending both directions, zero-habit friends |
| `requests` | full lifecycle, decline, cancel, reciprocal auto-accept, permission rules |
| `compare` | winner/verdict maths, no-shared-habits, zero-habit users |
| `activity` | friends-only, ordering, cursor paging, limit clamping |
| `nudges` | cooldown + `retryAfterSeconds`, per-habit/per-recipient scoping, accept permissions, unfriend revokes |
| `notifications` | unread accounting, read/read-all/delete, cross-user isolation (404, not 403), **live SSE delivery** |
| `match` | search matching, all relationship states, mutual friends, suggestion ranking, **determinism** |
| `push` | provider selection, FCM misconfiguration degrading safely, badge counts, retries, dead-token cleanup, and that a crashing provider never breaks the API |
| `regressions` | streaks beyond 7 days, ex-friends dropping out of the feed, zero-state users, over-logging |

## Layout

```
src/
  index.js          entrypoint (file-backed db, listens)
  server.js         createServer(db, opts) -> http.Server  (tests use this directly)
  db.js             schema, migrations, indexes; openDb(':memory:') for tests
  router.js         method + path-pattern router
  http.js           body parsing with a size cap, JSON helpers, ApiError
  auth.js           register/login/logout, requireAuth
  domain.js         streaks, weekData, summaries, match scoring
  notifications.js  createNotification() + the SSE hub
  seed.js           deterministic demo data
  push/
    index.js        provider selection + the dispatcher
    providers.js    none / log / memory
    fcm.js          FCM HTTP v1, JWT signing, token cache
  routes/           habits, friends, requests, nudges, notifications, match, activity, devices
test/               node:test suites + helpers.js (in-memory app factory)
```

## Security notes

Appropriate for development, **not** for public deployment as-is:

- Passwords are scrypt-hashed with a per-user salt and compared in constant
  time; plaintext is never stored or logged (there is a test asserting this).
- Session tokens are 32 random bytes, revoked on logout.
- CORS is permissive for local development — lock it down before shipping.
- There is no rate limiting on login, no password reset, and no email
  verification. Add these before exposing the server to the internet.
- Serve over TLS in production; tokens are bearer credentials.
