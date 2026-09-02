# Push notifications — release checklist

The push path is **built and tested**. Nothing below requires a code change —
only credentials and platform config files. Until they are supplied the server
runs with `PUSH_PROVIDER=none`, which exercises the entire path and records
every would-be send in `push_deliveries` with `status='skipped'`.

We use **Firebase Cloud Messaging (FCM) HTTP v1 for both Android and iOS**.
Apple's APNs is reached *through* FCM, so there is one server integration, not
two.

---

## 1. What you need to provide

| # | Item | Where it comes from | Where it goes |
|---|---|---|---|
| 1 | Firebase **service account JSON** | Firebase console -> Project settings -> Service accounts -> *Generate new private key* | `backend/secrets/fcm-service-account.json` (gitignored) |
| 2 | Firebase **project ID** | same console page | `FCM_PROJECT_ID` env var |
| 3 | **`google-services.json`** | Firebase console -> Project settings -> Your apps -> Android app | `android/app/google-services.json` |
| 4 | **`GoogleService-Info.plist`** | Firebase console -> Your apps -> iOS app | `ios/Runner/GoogleService-Info.plist` |
| 5 | **APNs auth key** (`.p8`) + Key ID + Team ID | Apple Developer -> Certificates, IDs & Profiles -> Keys -> *+* -> Apple Push Notifications service | Uploaded **to the Firebase console** (Project settings -> Cloud Messaging -> APNs Authentication Key). Never goes on our server. |
| 6 | iOS **Push Notifications** capability + **Background Modes -> Remote notifications** | Xcode -> Runner target -> Signing & Capabilities | committed in `ios/Runner.xcodeproj` |
| 7 | An App ID with Push enabled + a provisioning profile that includes it | Apple Developer portal | Xcode signing |

The `.p8` key is downloadable exactly once — store it in the team password
manager the moment it is generated.

## 2. Turning it on

```bash
# backend/.env  (or real environment variables in the deploy target)
PUSH_PROVIDER=fcm
FCM_PROJECT_ID=your-firebase-project-id
FCM_SERVICE_ACCOUNT_FILE=./secrets/fcm-service-account.json
```

Restart the server. `GET /api/health` reports the active provider so you can
confirm it took effect. No rebuild, no code edit.

Auth to FCM is a self-signed RS256 JWT exchanged for an OAuth2 access token,
implemented with `node:crypto` — there is no `firebase-admin` dependency and
nothing to `npm install`. Tokens are cached until ~5 minutes before expiry.

## 3. Flutter side, at release

Three steps, all mechanical:

1. Add the plugin:
   ```yaml
   firebase_core: ^3.0.0
   firebase_messaging: ^15.0.0
   ```
2. Drop in files 3 and 4 from the table above.
3. `PushService` already exposes `registerDevice()` / `unregisterDevice()` and
   is wired into `AuthService` (register on sign-in, unregister on sign-out).
   The only edit is swapping its token source from the current stub to
   `FirebaseMessaging.instance.getToken()` and forwarding
   `onTokenRefresh`. The call sites, the `/api/devices` round trip, the
   deep-link handling of a tapped notification, and the foreground-vs-background
   branching are all already written.

Android also needs, in `android/app/build.gradle`, the
`com.google.gms.google-services` plugin, and on Android 13+ the
`POST_NOTIFICATIONS` runtime permission — `PushService.ensurePermission()`
already handles the request flow.

## 4. Verifying it works

1. `PUSH_PROVIDER=log` — send a nudge between two seeded users, confirm the
   rendered payload prints server-side. Proves the fan-out, badge count and
   `data` payload without any credentials.
2. `PUSH_PROVIDER=fcm` on a **physical device** (the iOS simulator cannot
   receive push; an Android emulator with Play Services can).
3. Confirm `push_deliveries` rows flip to `status='sent'`.
4. Kill the app entirely and send another nudge — this is the case SSE cannot
   cover and the only real proof push is live.
5. Uninstall the app, send again, confirm the row records `invalid_token` and
   the `devices` row is deleted automatically.

## 5. What is deliberately not automated

- Creating the Firebase project and Apple App ID.
- Uploading the `.p8` to Firebase.
- Xcode signing and provisioning.

These are one-time console actions tied to your Apple/Google accounts.
