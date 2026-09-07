# Claude Project Guide - PW

## Project Overview

**PW** is a cross-platform mobile app (Android & iOS) built with Flutter. Single Dart codebase runs on both platforms.

## Tech Stack

| Layer | Tech | Status |
|-------|------|--------|
| Framework | Flutter (Dart) | Active |
| UI | Material Design 3 | Active |
| Platforms | Android & iOS | Both supported |
| Editor | VS Code | Primary |
| Backend | Node 24 + `node:sqlite` | Active, zero npm deps |
| Networking | `http` + `shared_preferences` | Active |
| Push | FCM HTTP v1 | Built; needs keys at release |

## Project Structure

```
PW/
├── lib/
│   ├── main.dart              # Entry point; builds & provides all services
│   ├── screens/               # Journal, Journey, Friends, FriendDetail,
│   │                          #   AddFriend, Compare, Notifications, Login
│   ├── widgets/               # Reusable widgets (+ widgets/friends/)
│   ├── models/                # Data models; every fromJson is total
│   ├── services/
│   │   ├── api/               # ApiClient, ApiConfig, PwApi, ApiException
│   │   ├── auth_service.dart
│   │   ├── notification_service.dart   # SSE + polling fallback
│   │   ├── friends_repository.dart
│   │   └── push_service.dart
│   └── utils/                 # journal_theme.dart (design tokens)
├── backend/                    # Node 24 API server, ZERO npm dependencies
│   ├── src/                    # routes/, push/, db, router, domain
│   └── test/                   # node:test suites (136 tests)
├── test/                       # Flutter tests (54)
├── docs/                       # API_CONTRACT, FRIENDS_UX_SPEC, PUSH_SETUP,
│                               #   FRIENDS_FEATURE
├── assets/
└── pubspec.yaml
```

## Development Setup

**Requirements:**
- Flutter SDK (3.0+)
- Dart SDK (included with Flutter)
- VS Code + Flutter extension

**Get Started:**
```bash
flutter pub get
flutter run
```

## Key Features

✓ **Bottom Navigation** - 3 tabs (Journal, Journey, Profile)
✓ **Material Design 3** - Modern UI with Material 3
✓ **Cross-platform** - Single codebase for Android & iOS
✓ **Hot Reload** - Fast development cycle

## App Structure

- **Journal Tab**: Track daily thoughts and experiences
- **Journey Tab**: Explore progress and achievements
- **Profile Tab**: Manage account and preferences

## Backend

The app talks to a real API. Start it before running the app:

```bash
cd backend && node src/seed.js && node src/index.js   # :8080
```

`docs/API_CONTRACT.md` is the authoritative spec — **change it before changing
either side.** Demo logins are in `backend/README.md`.

On a **physical** Android device, `10.0.2.2` is an emulator-only address: use
`adb reverse tcp:8080 tcp:8080` plus a `http://localhost:8080` override, or the
machine's LAN IP.

## Testing

```bash
flutter test          # 54 tests
cd backend && npm test # 136 tests
```

`flutter analyze` must stay at **0 errors, 0 warnings**.

`test/live_backend_test.dart` exercises the real client against the real server
and skips itself when no server is running.

## House rules

- **There is no login or sign-up screen.** An anonymous account is provisioned
  on first launch (`AuthService.ensureAccount()`), and can later be claimed
  with an email/phone via `LinkAccountScreen`. Do not reintroduce a login gate.
- **No dummy/sample data in `lib/`.** Every list is real data, a skeleton, an
  empty state, or an error state. This was deliberate cleanup — do not
  reintroduce placeholder people or stats.
- No state-management package. Services are `ChangeNotifier`s provided via
  `AppScope` (an `InheritedWidget`) and consumed with `ListenableBuilder`.
- `withOpacity` is deprecated here — use `.withValues(alpha: ...)`.
- Never re-derive `Habit.streak` from `weekData`: it is a 7-day window and
  would cap every streak at 7. Trust the server's value.
- Guard every async gap with `if (!mounted) return;` before touching `context`.

## Next Steps

1. Supply Firebase/APNs credentials and verify push on a real device
   (`docs/PUSH_SETUP.md`)
2. Harden the backend before any public deployment (CORS, login rate limiting,
   TLS, password reset)
3. Journey screen features
4. Analytics
5. Enable the "HealthKit" capability on the Runner target in Xcode (Signing &
   Capabilities) before an iOS build — required for the walking challenge's
   step sync (`lib/services/step_source.dart`). `Info.plist` already carries
   `NSHealthShareUsageDescription`; only the Xcode-side capability is missing,
   and that step needs a Mac.

## Important Notes

- No native code needed - Flutter handles Android & iOS
- Material Design 3 provides modern, consistent UI
- Use pubspec.yaml to manage all dependencies
- Test on both emulators/devices before publishing
- Hot reload for fast iteration during development
