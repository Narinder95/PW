# Friends, matching & notifications — what shipped

Replaces the old `FRIENDS_PAGE_IMPLEMENTATION.md` / `UPDATES.md`, which
described the hard-coded Alex/Jordan/Taylor/Sam demo data that has since been
deleted.

## The short version

The Friends page used to be a static mock. It is now a real feature backed by a
real server: you find people, send friend requests, see their genuine daily
progress, nudge or cheer them, compare head-to-head, and get notified about all
of it.

**There is no sample data left in the app.** Every list is real backend data, a
loading skeleton, an empty state, or an error state.

## Documents

| Doc | What it is |
|---|---|
| `docs/API_CONTRACT.md` | Authoritative API spec — shapes, error codes, every edge-case rule |
| `docs/FRIENDS_UX_SPEC.md` | Every screen and every state it must render |
| `docs/PUSH_SETUP.md` | **Release checklist: the keys you must supply for push** |
| `backend/README.md` | Running, seeding, and testing the server |

## What was built

### Backend (`backend/`)
Node 24, **zero npm dependencies** — `node:http`, `node:sqlite`, `node:crypto`,
`node:test` only. Nothing to install.

Auth, habits, friends, friend requests, match suggestions, nudges, the activity
feed, notifications with a live SSE stream, and push fan-out.

### Client data layer (`lib/models/`, `lib/services/`)
Typed models whose `fromJson` is **total** — a malformed payload degrades to a
documented fallback and never throws. `ApiClient` maps every failure, including
an HTML error page or a dead socket, onto a typed `ApiException` the UI branches
on. `AuthService`, `NotificationService`, `FriendsRepository` and `PushService`
are `ChangeNotifier`s; every one takes an injectable `http.Client`.

### UI (`lib/screens/`, `lib/widgets/`)
`FriendsScreen`, `FriendDetailScreen`, `AddFriendScreen` (search + ranked
suggestions), `CompareScreen`, `NotificationsScreen`, `LoginScreen`, an in-app
notification banner, and a bell with a live unread badge.

No state-management package: services are provided by an `InheritedWidget`
(`AppScope`) and consumed with `ListenableBuilder`.

## "Matching" means two things, and both are built

1. **Finding people** — `AddFriendScreen`: search by username or name, plus
   ranked suggestions scored on shared habits, mutual friends and streak
   affinity. Deterministic; no randomness. This is how you get friends at all
   now that the fake ones are gone.
2. **Measuring up against them** — `CompareScreen`: head-to-head on habits you
   both track, with a per-habit winner and an overall verdict.

## Notifications

Server-side records for every social event; unread counts; read/dismiss;
**live in-app delivery over SSE** with a polling fallback and exponential
backoff; an in-app banner; a bell badge; and deep-linking from a tapped
notification via `refType`/`refId`.

A tapped push and a tapped in-app notification route through the **same**
deep-link function, so the two can never drift apart.

### Push status

Built end-to-end and **inert until credentials are supplied**. FCM HTTP v1
covers Android *and* iOS (APNs is reached through FCM, so there is one server
integration rather than two). Switching it on is configuration
(`PUSH_PROVIDER=fcm` + a service-account file), not a code change.

On the client, the token source sits behind `PushTokenSource` with a working
stub. At release the swap is: one `FirebaseMessagingTokenSource` class, one
constructor argument in `main.dart`, `Firebase.initializeApp()` in `main()`,
and two `pubspec.yaml` entries. Everything downstream — registration,
de-registration on logout, token refresh, deep-linking a tapped push — is
already written and tested.

**It has not been proven against a real device**, because that is the one step
credentials gate. `docs/PUSH_SETUP.md` §4 is the verification procedure.

## Bugs found and fixed along the way

- **Streaks were capped at 7.** The client derived `streak` from the 7-day
  `weekData` window, so a 30-day streak rendered as "7". The server was already
  correct. Now the server value is authoritative.
- **`name[0]` crashed on an empty name** in `FriendCard` and `ActivityCard`.
  Replaced with a `PwAvatar` widget that falls back to `?`.
- **Friends cards were invisible in light mode** — they used
  `Colors.white.withOpacity(...)` for fills instead of theme tokens.
- **Unguarded division** by `target` and `habitsTotal`. A friend with no habits
  produced `NaN`, which throws when used as a layout width. The `devong` seed
  account exists specifically to keep this fixed.
- `FriendDetailScreen`'s back-button FAB overlapped content; replaced with a
  normal AppBar back button.

## Testing

| Suite | Count | Command |
|---|---|---|
| Backend | 136 across 11 suites | `cd backend && npm test` |
| Flutter | 54 | `flutter test` |

`flutter analyze`: **0 errors, 0 warnings.** The 10 remaining infos are all
`avoid_print` in `lib/models/journey/journey_world.dart`, which predates this
work and was out of scope.

`test/live_backend_test.dart` runs the **real client data layer against the
real server over HTTP** — the only test that catches contract drift between the
two. It skips itself cleanly when no server is running, so `flutter test`
passes on a machine without one.

## Running it

```bash
cd backend && node src/seed.js && node src/index.js
```

```bash
flutter run
```

Demo logins are in `backend/README.md` (password `password123` for all).

**On a physical Android device** the default `10.0.2.2` is an *emulator*
address and will not connect. Either run `adb reverse tcp:8080 tcp:8080` and
set the server override to `http://localhost:8080`, or point it at your
machine's LAN IP. The Friends screen's network-error panel has a "change
server" affordance for exactly this.

## Known gaps

- OS-level push is unproven until credentials land (above).
- The backend is dev-grade: permissive CORS, no login rate limiting, no
  password reset, no email verification, HTTP not HTTPS. `backend/README.md`
  lists what to harden before exposing it publicly.
- The Journey tab was deliberately left untouched.
