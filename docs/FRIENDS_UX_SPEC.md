# Friends, Matching & Notifications — UI spec

Companion to `docs/API_CONTRACT.md`. This describes what the Flutter UI must
render for every state. **The app ships with zero sample data.** Every list is
either real backend data, a loading skeleton, an empty state, or an error state.

## Design language

Reuse `JournalTheme.of(context)` for everything. Do not hard-code
`Colors.white.withOpacity(...)` for card fills — the existing Friends widgets do
this and it makes cards invisible in light mode. Replace those with
`t.surface` / `t.surfaceBright` / `t.outline` / `t.shadow`.

Per-user accent colour comes from `Friend.avatarColor` (server-assigned), passed
through `t.accent(...)` so deep colours stay legible on the dark ground.

## Navigation

Bottom nav stays 4 tabs: Journal, Journey, Friends, Profile.

The Friends tab AppBar gains a **notification bell** on the right with an unread
badge (dot when 1–9, `9+` cap). Tapping opens `NotificationsScreen`. The badge
count comes from `NotificationService.unreadCount` and must update live.

An **add-friend** action (person_add icon) sits to the left of the bell and
opens `AddFriendScreen`.

## Screens

### 1. `FriendsScreen` (rewrite)

Sections, in order:

1. **Pending friend requests** — only when `incoming.isNotEmpty`. Each row:
   avatar, name, `@username`, `N mutual friends`, Accept / Decline buttons.
   Accept optimistically moves the person into the friends rail.
2. **Friend Activity** — horizontal rail of `FriendCard`.
3. **Nudges Received** — only when non-empty.
4. **Recent Activity** — vertical feed, paged (`before` cursor) with
   infinite scroll.

States:
- **Loading**: shimmer/skeleton placeholders, not a bare spinner.
- **Signed out**: prompt to sign in (routes to `LoginScreen`).
- **Backend unreachable** (`ApiException.isNetwork`): a retry panel naming the
  configured base URL, plus a "Change server" affordance that writes
  `ApiConfig.baseUrl`. This is what a QA agent or a developer on a real device
  needs when `localhost` is wrong.
- **No friends yet**: an illustration-free empty state — headline "No friends
  yet", body "Find people who are building the same habits.", primary button
  "Find friends" -> `AddFriendScreen`. **This is the state the app is in on a
  fresh account, so it has to look deliberate, not broken.**
- **Friends but no activity**: the rail renders; the feed shows "No activity in
  the last few days."

Pull-to-refresh refreshes friends + requests + nudges + activity together.

### 2. `AddFriendScreen` (new) — "matching"

Two tabs:
- **Suggested** — `GET /api/match/suggestions`. Each row: avatar, name,
  `@username`, the `reason` string, a match-score ring (0–100), shared-habit
  chips, and an **Add** button that becomes "Requested" (disabled) after
  `POST /api/friend-requests`. If the server returns `autoAccepted: true`, show
  "You're now friends with X" and move the row out.
- **Search** — debounced 300 ms over `GET /api/users/search`. The **Add** button
  varies by `relationship`: `none` -> Add, `requestSent` -> Requested (disabled),
  `requestReceived` -> Accept, `friend` -> Friends (disabled), `self` -> hidden.

Empty states: "Search for a username" before typing; "No one matches
'<q>'" after. Suggestions empty -> "No suggestions yet — search by username."

A third section (or an app-bar action) lists **outgoing pending requests** with
a Cancel button.

### 3. `FriendDetailScreen` (rewrite)

Loads `GET /api/friends/:id` — the hard-coded Steps/Hydration/Workout list and
the fake "4/6 Habits" must go.

- Header: avatar, name, `@username`, streak badge, `habitsCompleted/habitsTotal`.
- Today's Progress: real ratio, guarded against `habitsTotal == 0`.
- Weekly Momentum: real `weekData`, oldest-first with index 6 = today. Day
  letters must be derived from the actual dates, not a hard-coded `M T W T F S S`
  (use `JournalTheme.weekdayLetter`).
- Today's Habits: real `FriendHabit` list. Button is **Cheer** when
  `status == completed`, else **Nudge**. On `429 rate_limited`, show
  "Already nudged — try again in N min" instead of a generic error.
- **Compare** button -> `CompareScreen`.
- Overflow menu: **Remove friend** with a confirm dialog.
- Replace the floating back-button FAB with a normal `AppBar` back button; the
  FAB overlaps content and is non-standard.
- Empty: friend has no habits -> "X hasn't set up any habits yet."

### 4. `CompareScreen` (new) — head-to-head

`GET /api/friends/:id/compare`. Per shared habit, a two-sided bar (me left,
friend right) with the winner's side highlighted. Header shows both scores and
the verdict ("You're ahead", "Taylor's ahead", "Dead even"). Zero shared habits
-> "No habits in common yet — add one they track to compare."

### 5. `NotificationsScreen` (new)

Grouped by day (Today / Yesterday / date). Each row: actor avatar, title, body,
relative time, unread dot. Unread rows get a tinted background.

- Tap -> mark read + deep-link by `refType`:
  `nudge` -> Friends tab nudges section; `friend_request` -> AddFriendScreen
  requests; `user`/`activity` -> that friend's detail screen; null -> no-op.
- Swipe to dismiss -> `DELETE /api/notifications/:id`, with undo via SnackBar.
- AppBar action: "Mark all read".
- Unknown `type` must render with a generic icon, never crash.
- Empty: "You're all caught up."

### 6. `LoginScreen` (new)

Sign in / register toggle. Fields validated client-side before submit
(username charset, password length, email shape) so the round trip is not the
first feedback. Server `validation_error` maps its `field` onto the right input.
`AuthService.restoreSession()` runs on boot behind a splash so a returning user
never sees this screen.

### 7. In-app notification banner

`NotificationService`'s new-notification stream drives a top banner
(`MaterialBanner` or an overlay) on whichever screen is visible, auto-dismissing
after 4s, tappable to deep-link. This is the in-app half of the notification
system.

## Notification delivery — what is built

| Layer | Status |
|---|---|
| Server-side notification records for every social event | built |
| Unread counts + read/dismiss | built |
| Live in-app delivery over SSE, with polling fallback | built |
| In-app banner + bell badge | built |
| Device token registration + de-registration | built |
| Server-side push fan-out, retry, dead-token cleanup | built, provider-swappable |
| FCM HTTP v1 provider (Android **and** iOS via APNs-through-FCM) | built, inert until keys are set |
| Firebase/APNs credentials | supplied at release — see `docs/PUSH_SETUP.md` |

Push is switched on by configuration alone (`PUSH_PROVIDER=fcm` plus the
service-account file), not by a code change. On the client, the token source
sits behind `PushTokenSource`; the release swap is a `FirebaseMessagingTokenSource`
implementation plus two pubspec entries. Everything downstream of the token —
registration, deep-linking a tapped push, foreground/background branching — is
already written and tested against a stub source.

A **tapped push and a tapped in-app notification must route through the same
deep-link function**, keyed on `refType`/`refId`. Do not write that logic twice.

## Accessibility & robustness rules

- Every tappable target >= 44 px.
- No `friend.name[0]` on a possibly-empty string — guard it (the current
  `FriendCard` and `ActivityCard` both crash on an empty name).
- No unguarded division by `target` or `habitsTotal`.
- Long names must ellipsize, not overflow.
- Everything must render in BOTH light and dark mode.
