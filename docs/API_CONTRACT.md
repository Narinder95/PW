# PW Backend API Contract v1

Single source of truth for the PW backend and the Flutter client. Both sides are
built against this document. **If you need to change a shape, change it here
first**, then update both sides.

- Base URL (dev): `http://localhost:8080`
- Android emulator reaches the host at `http://10.0.2.2:8080`
- All request and response bodies are JSON (`Content-Type: application/json`).
- All timestamps are ISO-8601 UTC strings, e.g. `2026-08-31T09:14:00.000Z`.
- All dates (day-granularity) are `YYYY-MM-DD`.
- Colors are `#RRGGBB` strings (client parses to `Color`).
- IDs are opaque strings. Never assume they are numeric.

## Auth

Every endpoint except `/api/health`, `/api/auth/anonymous`,
`/api/auth/register` and `/api/auth/login` requires:

```
Authorization: Bearer <token>
```

Missing/invalid token -> `401 { "error": { "code": "unauthorized", ... } }`.

## Error envelope

Non-2xx responses always use:

```json
{ "error": { "code": "validation_error", "message": "target must be > 0", "field": "target" } }
```

| code | status | meaning |
|---|---|---|
| `validation_error` | 400 | bad/missing input |
| `unauthorized` | 401 | no/expired token, bad credentials |
| `forbidden` | 403 | authenticated but not allowed (e.g. not friends) |
| `not_found` | 404 | unknown id |
| `conflict` | 409 | duplicate (username taken, already friends, request exists) |
| `rate_limited` | 429 | nudge cooldown hit |
| `internal` | 500 | unexpected |

## Object shapes

### User (public)
```json
{
  "id": "u_ab12",
  "username": "alexr",
  "name": "Alex Rivera",
  "avatarColor": "#2DD4BF",
  "createdAt": "2026-08-01T00:00:00.000Z"
}
```
`GET /api/me` additionally returns `"email"`, `"phone"` (both nullable, both
null until the account is claimed) and `"isAnonymous"` (bool).

### Habit (own)
```json
{
  "id": "h_1",
  "name": "Steps",
  "icon": "R",
  "color": "#2E7D32",
  "target": 10000,
  "unit": "steps",
  "progress": 6500,
  "weekData": [true, true, false, true, true, true, false],
  "streak": 2,
  "completedToday": false
}
```
`icon` is an emoji string. `weekData` is always length 7, **oldest first,
index 6 = today**.

`streak` is computed **server-side over the full log history, not over the
7-day `weekData` window**, so a 30-day streak reports as `30`. The client MUST
use the server's `streak` value and must NOT re-derive it from `weekData`
(doing so silently caps every streak at 7). `weekData` is for the week strip
only. `completedToday` is likewise authoritative from the server, which knows
the user's timezone-local day boundary.

### HabitMonth
```json
{
  "month": "2026-05",
  "days": 31,
  "habits": [
    {
      "id": "h_1",
      "name": "Steps",
      "icon": "👟",
      "color": "#2E7D32",
      "monthData": [true, false, null, "…"],
      "progressData": [8342, 0, null, "…"]
    }
  ]
}
```
`monthData` has length `days`, oldest first (index 0 = the 1st of the month).
Each entry is `true` (target met that day), `false` (logged short, or not
logged, on a day that already happened), or `null` for a day before the habit
was created or after today — **no data**, which the client must render
differently from a miss.

`progressData` is the same length and day alignment as `monthData`, but holds
the raw `progress` actually logged that day instead of a target comparison.
An entry is `null` whenever there is no log row for that date — no log ever
made, a day before the habit existed, or a day in the future — **never** `0`
for "not logged"; `0` means the user logged zero. Averages and other
aggregates must be computed only over non-null entries, otherwise an unlogged
day silently drags the average down as if it were a real zero.

### FriendSummary
```json
{
  "id": "u_cd34",
  "username": "taylorm",
  "name": "Taylor",
  "avatarColor": "#FB923C",
  "streakDays": 22,
  "completionPercentage": 0.95,
  "habitsCompleted": 5,
  "habitsTotal": 6,
  "weekData": [true, true, true, true, true, true, false],
  "lastActiveAt": "2026-08-31T08:00:00.000Z"
}
```
`completionPercentage` is a double in `[0,1]`. `habitsTotal` may be `0` (new
friend with no habits) - clients must not divide by it blindly.

### FriendHabit (friend's habit, read-only)
```json
{
  "id": "h_9",
  "name": "Hydration",
  "icon": "D",
  "color": "#2DD4BF",
  "progress": 1300,
  "target": 2000,
  "unit": "mL",
  "status": "in_progress"
}
```
`status` is one of `not_started` | `in_progress` | `completed`.

### FriendActivity
```json
{
  "id": "a_1",
  "friendId": "u_cd34",
  "friendName": "Taylor",
  "avatarColor": "#FB923C",
  "habitName": "5k Run",
  "habitIcon": "T",
  "habitColor": "#FB923C",
  "completion": "5/5 km",
  "createdAt": "2026-08-31T08:45:00.000Z"
}
```

### Nudge
```json
{
  "id": "n_1",
  "type": "nudge",
  "fromUserId": "u_ab12",
  "fromUserName": "Alex",
  "toUserId": "u_me",
  "habitId": "h_5",
  "habitName": "Meditate",
  "habitIcon": "M",
  "habitColor": "#A855F7",
  "message": null,
  "status": "pending",
  "createdAt": "2026-08-31T09:00:00.000Z",
  "acceptedAt": null
}
```
`type`: `nudge` (do this) | `cheer` (well done). `status`: `pending` | `accepted`.

### Notification
```json
{
  "id": "nt_1",
  "type": "nudge",
  "title": "Alex nudged you",
  "body": "Alex nudged you to Meditate",
  "actorId": "u_ab12",
  "actorName": "Alex",
  "avatarColor": "#2DD4BF",
  "icon": "M",
  "color": "#A855F7",
  "refType": "nudge",
  "refId": "n_1",
  "read": false,
  "createdAt": "2026-08-31T09:00:00.000Z"
}
```
`type` is one of:
`friend_request` | `friend_request_accepted` | `nudge` | `cheer` |
`nudge_accepted` | `friend_activity` | `streak_milestone` | `match_suggestion`.

`refType` tells the client what `refId` points at, so it can deep-link:
`nudge` | `friend_request` | `user` | `activity` | `habit` | `null`.

`actorId`, `actorName`, `avatarColor`, `icon`, `color`, `refId`, `refType` are
all nullable. Clients must render a notification with every one of them null.

### WalkingChallenge
```json
{
  "level": "bronze",
  "streakDays": 1,
  "target": 10000,
  "nextLevel": "silver",
  "daysToNextLevel": 2,
  "todaySteps": 6200,
  "todayStatus": "warning",
  "history": [
    { "date": "2026-08-30", "steps": 8100, "target": 8000, "status": "met" }
  ]
}
```
`level` is one of `none` | `bronze` | `silver` | `gold` - `none` means no
tier has been earned yet. `target` is the step count that applies **today**,
given the committed level (bronze pursues the 10,000 silver target, gold
maintains 12,000 forever). `nextLevel` is `null` once at gold.
`daysToNextLevel` is `null` at gold, otherwise how many more full-target days
are needed (counting a frozen `warning`/`no_data` day as unchanged, not reset).

`todayStatus` / each `history[].status` is one of:
- `met` - hit the day's target.
- `warning` - hit 80-99% of the target; the streak freezes for that day
  (neither advances nor resets).
- `shortfall` - a synced day under 80% of target; demotes one level
  (`gold`→`silver`→`bronze`→`none`) and resets the streak to 0.
- `no_data` - the device never reported a step count for that date; treated
  like `warning` (freezes, never demotes - a sync gap is not proof of
  inactivity).

**`streakDays`/`level`/`history` are computed server-side over the full
`daily_steps` history, the same way `Habit.streak` is** - the client must not
recompute promotion/demotion locally. The computation only ever commits
*yesterday and earlier*; today only ever shows as `todaySteps`/`todayStatus`,
a live preview that is not yet folded into the streak.

### FriendRequest
```json
{
  "id": "fr_1",
  "fromUser": { "id": "u_ab12", "username": "alexr", "name": "Alex", "avatarColor": "#2DD4BF" },
  "toUser":   { "id": "u_me",   "username": "me",    "name": "Me",   "avatarColor": "#A855F7" },
  "status": "pending",
  "mutualFriends": 3,
  "createdAt": "2026-08-31T09:00:00.000Z",
  "respondedAt": null
}
```
`status`: `pending` | `accepted` | `declined` | `cancelled`.

---

## Endpoints

### Health
`GET /api/health` -> `200 { "ok": true, "version": "1", "time": "..." }` (no auth)

### Auth

**There is no sign-up or login screen.** The app provisions an account
silently on first launch and the user starts using it immediately. Credentials
are optional and only ever collected later, to make the account recoverable.

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/auth/anonymous` | `{name?, avatarColor?}` | `201 {token, user}` |
| POST | `/api/auth/link` | `{email?, phone?, password, username?}` | `200 {user}` |
| POST | `/api/auth/register` | `{username, name, email, password}` | `201 {token, user}` |
| POST | `/api/auth/login` | `{usernameOrEmail, password}` | `200 {token, user}` |
| POST | `/api/auth/logout` | - | `204` |
| GET | `/api/me` | - | `200 {user}` |
| PATCH | `/api/me` | `{name?, avatarColor?}` | `200 {user}` |

`POST /api/auth/anonymous` takes no credentials. It mints a readable handle
(`swift_otter1234`), a display name and an avatar colour. The returned account
is a **first-class user** — it can own habits, be searched for, be friended,
nudged and notified. Its only limitation is that it has no credentials, so it
exists solely on the device holding the token.

`POST /api/auth/link` claims the caller's anonymous account:
- Requires `password` (>= 8 chars) and at least one of `email` / `phone`.
- `username` optionally replaces the auto-generated handle.
- Keeps the **same user id and the same session** — habits, friends, streaks
  and notifications are all retained. Verified by test.
- `409 conflict` if the email, phone or handle is taken; the account is left
  untouched and still anonymous.
- `409 conflict` if the account is already linked (no re-claiming).
- Phone numbers are normalised by stripping spaces, brackets, dots and dashes;
  the stored form matches `^\+?[0-9]{7,15}$`.

Validation: `username` 3-20 chars matching `[a-z0-9_]+` (lowercased
server-side, unique), `password` >= 8 chars, `email` unique and must contain
`@`, `name` 1-40 chars.

`POST /api/auth/login` accepts a username, an email **or** a phone number, and
exists for recovering a claimed account on a new device. An **anonymous account
can never be logged into** — it has no `password_hash`, and the endpoint
returns the same `401` it gives an unknown user, so handles cannot be probed.

`/api/me` returns `email`, `phone` (both nullable) and `isAnonymous`.

### Habits
| Method | Path | Body / Query | Response |
|---|---|---|---|
| GET | `/api/habits` | `?date=YYYY-MM-DD` (default today) | `200 {habits: Habit[]}` |
| POST | `/api/habits` | `{name, icon?, color?, target, unit?}` | `201 {habit}` |
| PATCH | `/api/habits/:id` | `{name?, icon?, color?, target?, unit?}` | `200 {habit}` |
| DELETE | `/api/habits/:id` | - | `204` |
| POST | `/api/habits/:id/log` | `{progress, date?}` | `200 {habit, activity\|null}` |
| GET | `/api/habits/month` | `?month=YYYY-MM` (default current month) | `200 HabitMonth` |

`target` must be an integer >= 1. `progress` must be an integer >= 0.

A habit's `name` must be unique per user, case/whitespace-insensitively.
`POST /api/habits` and `PATCH /api/habits/:id` (when changing `name`) return
`409 conflict` on a collision. This matches the client's own use of
`name.trim().toLowerCase()` to line habits up with the catalogue and with the
`Steps` habit below - without it, two colliding habits would make one
silently disappear from the Journal list.

`POST /log` **sets** (does not increment) that day's progress. When a log
crosses `progress >= target` for the first time on that date the server:
1. creates an `activities` row (returned as `activity`), and
2. creates a `friend_activity` notification for every friend.

Re-logging a completed habit the same day does not create a second activity.

Logging the habit named exactly `Steps` (case/whitespace-insensitive - the
catalogue entry every account starts with) also upserts that date's
`daily_steps` row via the same MAX-of-existing-and-new rule `POST
/api/steps/sync` uses (below), so a manual step log raises the walking
challenge's total too instead of the two counters silently disagreeing. Any
other habit's log never touches `daily_steps`.

### Friends
| Method | Path | Response |
|---|---|---|
| GET | `/api/friends` | `200 {friends: FriendSummary[]}` (streak desc, then name asc) |
| GET | `/api/friends/:id` | `200 {friend: FriendSummary, habits: FriendHabit[]}` |
| DELETE | `/api/friends/:id` | `204` (removes both directions) |
| GET | `/api/friends/:id/compare` | `200 {comparison}` |

A non-friend id -> `403 forbidden` (never leak another user's habits). An id
that does not exist at all -> `404 not_found`.

`GET /api/friends/:id/compare`:
```json
{
  "comparison": {
    "me":     { "id": "u_me", "name": "Me", "avatarColor": "#A855F7", "score": 4, "streakDays": 9 },
    "friend": { "id": "u_cd34", "name": "Taylor", "avatarColor": "#FB923C", "score": 5, "streakDays": 22 },
    "habits": [
      { "name": "Steps", "icon": "R", "color": "#2E7D32",
        "myProgress": 6500, "myTarget": 10000,
        "friendProgress": 10432, "friendTarget": 10000,
        "unit": "steps", "winner": "friend" }
    ],
    "sharedHabitCount": 4,
    "verdict": "friend_ahead"
  }
}
```
`winner`: `me` | `friend` | `tie`, decided on completion ratio
(`progress / target`, clamped to 1). `verdict`: `me_ahead` | `friend_ahead` |
`tie`, decided on `score` (count of habit wins). Only habits **both** users
have (case-insensitive, trimmed name match) are compared; with no shared
habits, `habits` is `[]`, both scores are `0` and `verdict` is `tie`.

### Matching / discovery
| Method | Path | Response |
|---|---|---|
| GET | `/api/users/search?q=&limit=` | `200 {users: SearchResult[]}` |
| GET | `/api/match/suggestions?limit=` | `200 {suggestions: Suggestion[]}` |

`q` matches username or name, case-insensitive substring, min length 1
(empty/missing `q` -> `400 validation_error`). Excludes the caller.
`limit` default 20, max 50.

SearchResult:
```json
{ "id":"u_x","username":"sam","name":"Sam","avatarColor":"#4ADE80",
  "mutualFriends": 2, "relationship": "none" }
```
`relationship`: `friend` | `request_sent` | `request_received` | `none`.

The caller is **filtered out of search results entirely**, so `self` is never
returned in practice. The client's `Relationship` enum still carries a `self`
case (and an `unknown` fallback) so a future change cannot crash it, but no UI
should depend on receiving one.

Suggestion - users who are **not** yet friends and have no pending request,
ranked by `matchScore` desc then username asc:
```json
{ "user": { "...SearchResult..." },
  "sharedHabits": ["Steps","Water"],
  "matchScore": 78,
  "reason": "3 habits in common - 2 mutual friends" }
```
`matchScore = min(100, sharedHabits*20 + mutualFriends*15 + streakAffinity)`
where `streakAffinity = max(0, 10 - abs(myStreak - theirStreak))`. Integer
0-100, **deterministic - no randomness anywhere**.

### Friend requests
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/friend-requests` | - | `200 {incoming: FriendRequest[], outgoing: FriendRequest[]}` |
| POST | `/api/friend-requests` | `{toUserId}` | `201 {request}` |
| POST | `/api/friend-requests/:id/accept` | - | `200 {friend: FriendSummary}` |
| POST | `/api/friend-requests/:id/decline` | - | `204` |
| DELETE | `/api/friend-requests/:id` | - | `204` (cancel own outgoing) |

`GET` returns pending requests only.

Rules:
- Self-request -> `400 validation_error`.
- Unknown `toUserId` -> `404 not_found`.
- Already friends -> `409 conflict`.
- Duplicate pending outgoing -> `409 conflict`.
- If the target already sent **you** a pending request, `POST /api/friend-requests`
  **auto-accepts** it and returns `200 {request, friend, autoAccepted: true}`.
- A previously `declined` or `cancelled` request does not block a new one.
- Only the recipient may accept/decline; only the sender may cancel -> else `403`.
- Accepting a non-pending request -> `409 conflict`.
- Creating a request notifies the recipient (`friend_request`).
- Accepting notifies the sender (`friend_request_accepted`).
- Declining notifies nobody.

### Activity feed
`GET /api/activity?limit=&before=` -> `200 {activities: FriendActivity[]}`

Friends' activity only (never your own), newest first. `limit` default 20,
max 100. `before` is an ISO timestamp cursor; only strictly-older rows return.

### Nudges
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/nudges` | - | `200 {received: Nudge[], sent: Nudge[]}` |
| POST | `/api/nudges` | `{toUserId, habitId?, habitName, habitIcon?, habitColor?, type?, message?}` | `201 {nudge}` |
| POST | `/api/nudges/:id/accept` | - | `200 {nudge}` |

`received` is pending only; `sent` is the 30 most recent regardless of status.
`type` defaults to `nudge`. `message` max 140 chars.

Rules:
- Recipient must be a friend -> else `403 forbidden`.
- Nudging yourself -> `400 validation_error`.
- Cooldown: same sender + recipient + habitName within 60 minutes -> `429` with
  `{ "error": { "code":"rate_limited", "message":"...", "retryAfterSeconds": 1800 } }`.
- Creating notifies the recipient (`nudge` or `cheer`).
- Accepting notifies the original sender (`nudge_accepted`).
- Only the recipient may accept -> else `403`. Accepting twice -> `409 conflict`.
- Accepting requires the sender and recipient to *still* be friends -> else
  `403 forbidden`. A nudge outlives the friendship it was sent under (there is
  no cleanup on unfriend), so this is checked again at accept time.

### Notifications
| Method | Path | Response |
|---|---|---|
| GET | `/api/notifications?limit=&unreadOnly=` | `200 {notifications: Notification[], unreadCount}` |
| GET | `/api/notifications/unread-count` | `200 {count}` |
| POST | `/api/notifications/:id/read` | `204` (idempotent) |
| POST | `/api/notifications/read-all` | `200 {updated}` |
| DELETE | `/api/notifications/:id` | `204` |
| GET | `/api/notifications/stream` | SSE stream |
| POST | `/api/devices` | `{token, platform}` -> `201 {device}` |

Newest first. `limit` default 30, max 100. `unreadCount` is always the caller's
total unread count, independent of `limit`/`unreadOnly`. Acting on another
user's notification -> `404 not_found` (do not confirm it exists).

SSE stream (`text/event-stream`). Because `EventSource` cannot set headers, the
token may be passed as `?token=` **or** the usual `Authorization` header:
```
event: ready
data: {"ok":true}

event: notification
data: { ...Notification... }

event: ping
data: {"t":"2026-08-31T09:00:00.000Z"}
```
`ping` every 25s so intermediaries do not close the connection. Clients that
cannot hold an SSE connection fall back to polling
`GET /api/notifications/unread-count`.

### Walking challenge
| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/challenge` | - | `200 {challenge: WalkingChallenge}` |
| POST | `/api/steps/sync` | `{days: [{date, steps}, ...]}` | `200 {challenge: WalkingChallenge}` |

`POST /api/steps/sync` upserts one `daily_steps` row per entry (1-31 per
call, `steps` an integer 0-200000). Written from the device's own health data
(Health Connect on Android, HealthKit on iOS). The only other writer of
`daily_steps` is the `Steps` habit log, above. Re-syncing the same `date`
takes the **larger** of the existing and new value, never the smaller: a
client may resync a partial day more than once as the device backfills, and a
later, larger total must win - the same rule applies between a device sync and
a manual `Steps` log, so neither can accidentally lower the day's total.

### Push devices

| Method | Path | Body | Response |
|---|---|---|---|
| POST | `/api/devices` | `{token, platform, appVersion?}` | `201 {device}` |
| DELETE | `/api/devices/:token` | - | `204` |

`platform` is `android` | `ios` | `web`. Keyed by `(user, token)` -
re-registering the same token is idempotent and refreshes `lastSeenAt`. A token
that appears under a different user is **reassigned** to the caller (a shared
handset that changed accounts must not keep receiving the old user's pushes).
`DELETE` is called on logout.

## Push delivery

Push is **fully implemented server-side behind a provider interface**. It is
inert until credentials are supplied, and switches on with configuration alone -
no code change. See `docs/PUSH_SETUP.md` for the exact keys and where they go.

Every call to `createNotification()` also enqueues a push to each of the
recipient's registered devices. Dispatch is asynchronous and **must never fail
the originating API request** - a push error is logged and the HTTP response is
unaffected.

Provider selection via `PUSH_PROVIDER`:

| value | behaviour |
|---|---|
| `none` (default) | no-op sink; records the attempt in `push_deliveries` with `status='skipped'` so the whole path is still testable |
| `log` | writes the fully-rendered payload to stdout; used by tests and local dev |
| `fcm` | Firebase Cloud Messaging HTTP v1, for BOTH Android and iOS |
| `memory` | in-process capture, for assertions in `node:test` |

Payload shape handed to the provider (provider-neutral):

```json
{
  "deviceToken": "...",
  "platform": "android",
  "title": "Alex nudged you",
  "body": "Alex nudged you to Meditate",
  "data": {
    "notificationId": "nt_1",
    "type": "nudge",
    "refType": "nudge",
    "refId": "n_1",
    "actorId": "u_ab12"
  },
  "badge": 3,
  "collapseKey": "nudge:u_ab12"
}
```

`badge` is the recipient's unread count at send time. `data` values must all be
strings - FCM rejects non-string data values.

Delivery bookkeeping: a `push_deliveries` table records
`(id, user_id, device_id, notification_id, provider, status, error, created_at)`
with `status` in `queued|sent|skipped|failed|invalid_token`. A provider result of
`invalid_token` (FCM `UNREGISTERED` / `INVALID_ARGUMENT`) **deletes the device
row** so dead tokens self-clean.

Retry: failed sends retry twice with backoff (1s, 4s) before being marked
`failed`. Timers must be `unref()`d so the process can still exit.

---

## Non-goals for v1

- No password reset, email verification, or refresh tokens (tokens are opaque,
  long-lived, revoked on logout).
- No image avatars - `avatarColor` + first initial only.
- Push **credentials** are not included (see `docs/PUSH_SETUP.md`); the code
  path is complete and tested against the `memory` and `log` providers.
