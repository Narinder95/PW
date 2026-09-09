import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../models/app_notification.dart';
import '../models/json.dart';
import 'api/api_exception.dart';
import 'api/pw_api.dart';

/// A push message as delivered by the OS layer.
///
/// Mirrors the provider-neutral payload in `docs/API_CONTRACT.md` ("Push
/// delivery"). FCM requires every `data` value to be a string, so all fields
/// here parse from strings.
@immutable
class PushMessage {
  final String? notificationId;
  final NotificationType type;
  final RefType refType;
  final String? refId;
  final String? actorId;
  final String? title;
  final String? body;

  const PushMessage({
    this.notificationId,
    this.type = NotificationType.unknown,
    this.refType = RefType.none,
    this.refId,
    this.actorId,
    this.title,
    this.body,
  });

  /// Parses the `data` map of a push (plus optional `title`/`body` from the
  /// notification half of the payload). Total — an unrecognised `type` or
  /// `refType` degrades rather than throwing inside a platform callback,
  /// where an exception would be swallowed and the tap silently lost.
  factory PushMessage.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) =>
      PushMessage(
        notificationId: asStringOrNull(data['notificationId']),
        type: NotificationType.parse(data['type']),
        refType: RefType.parse(data['refType']),
        refId: asStringOrNull(data['refId']),
        actorId: asStringOrNull(data['actorId']),
        title: title ?? asStringOrNull(data['title']),
        body: body ?? asStringOrNull(data['body']),
      );

  @override
  String toString() =>
      'PushMessage($notificationId, ${type.wire}, ${refType.wire}:$refId)';
}

/// Emitted when the user taps a push and the app routes it.
///
/// Deliberately carries the same `refType`/`refId` pair as [AppNotification]
/// so the UI can hand both to one routing function — a push tap and an in-app
/// notification tap must never diverge.
@immutable
class PushOpen {
  final PushMessage message;

  /// True when the tap cold-launched the app (as opposed to resuming it).
  /// The UI may want to wait for its first frame before navigating.
  final bool fromColdStart;

  const PushOpen({required this.message, this.fromColdStart = false});

  NotificationType get type => message.type;
  RefType get refType => message.refType;
  String? get refId => message.refId;
  String? get notificationId => message.notificationId;

  /// Whether there is somewhere to navigate to.
  bool get isDeepLinkable => refType != RefType.none && refId != null;

  @override
  String toString() =>
      'PushOpen(${message.refType.wire}:${message.refId}, cold: $fromColdStart)';
}

/// The platform push SDK, behind an interface.
///
/// Everything above this boundary — device registration, the `/api/devices`
/// round trip, token-refresh re-registration, sign-in/sign-out wiring, and
/// deep-linking a tapped notification — is written and working. Swapping the
/// implementation is the whole of the release-day change.
///
/// The three members without a body are the ones a real implementation must
/// provide. The three with bodies default to "this platform never delivers
/// messages", which is exactly right for the stub.
abstract class PushTokenSource {
  const PushTokenSource();

  /// The device's current push token, or null if there is none (permission
  /// denied, no Play Services, simulator, stub).
  Future<String?> getToken();

  /// Fires whenever the platform rotates the token. The new token must be
  /// re-registered with the backend.
  Stream<String> get onTokenRefresh;

  /// Requests notification permission. Returns whether it was granted.
  /// Must be safe to call repeatedly.
  Future<bool> requestPermission();

  /// Messages that arrive while the app is in the foreground. The OS does not
  /// draw a tray notification for these; `NotificationService` surfaces them
  /// as an in-app banner instead.
  Stream<PushMessage> get onForegroundMessage =>
      const Stream<PushMessage>.empty();

  /// Taps on a tray notification that resumed the app from the background.
  Stream<PushMessage> get onNotificationOpened =>
      const Stream<PushMessage>.empty();

  /// The message that cold-launched the app, if it was launched by a tap.
  /// Returns null on a normal launch, and must only return a given message
  /// once.
  Future<PushMessage?> initialMessage() async => null;

  /// `android` | `ios` | `web`, per the contract's `platform` field.
  String get platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return 'web';
    }
  }

  /// Releases any platform subscriptions.
  Future<void> dispose() async {}
}

/// The default [PushTokenSource]: no platform SDK, no token, no messages.
///
/// Every call succeeds and does nothing, so the entire push path runs in
/// development and in tests without Firebase installed. A null token makes
/// `PushService.registerDevice()` a silent no-op — never an error the user
/// sees. See [FirebaseMessagingTokenSource] for the real implementation.
class StubPushTokenSource extends PushTokenSource {
  const StubPushTokenSource();

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();

  /// Returns false: without a platform SDK there is no permission to grant.
  /// Callers must treat false as "no push", not as an error.
  @override
  Future<bool> requestPermission() async => false;
}

/// The real [PushTokenSource], backed by Firebase Cloud Messaging.
///
/// Requires `await Firebase.initializeApp()` to have already run (done once
/// in `main()`, before this class or anything else touches
/// `FirebaseMessaging` — see the platform config files under
/// `android/app/google-services.json` and
/// `ios/Runner/GoogleService-Info.plist`, and `docs/PUSH_SETUP.md`).
class FirebaseMessagingTokenSource extends PushTokenSource {
  FirebaseMessagingTokenSource();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// `getInitialMessage()` keeps returning the same cold-start message on
  /// every call - the contract this class implements requires it be
  /// consumed exactly once, so a local flag tracks whether that has
  /// happened yet.
  bool _initialMessageConsumed = false;

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage
      .map((m) => PushMessage.fromData(
            m.data,
            title: m.notification?.title,
            body: m.notification?.body,
          ));

  @override
  Stream<PushMessage> get onNotificationOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => PushMessage.fromData(
            m.data,
            title: m.notification?.title,
            body: m.notification?.body,
          ));

  @override
  Future<PushMessage?> initialMessage() async {
    if (_initialMessageConsumed) return null;
    _initialMessageConsumed = true;
    final message = await _messaging.getInitialMessage();
    if (message == null) return null;
    return PushMessage.fromData(
      message.data,
      title: message.notification?.title,
      body: message.notification?.body,
    );
  }
}

/// Owns the client half of push notifications.
///
/// Responsibilities: asking for permission, registering the device token with
/// `POST /api/devices`, unregistering it on sign-out, re-registering when the
/// platform rotates the token, and turning a tapped notification into a
/// [PushOpen] the UI can route.
///
/// Everything degrades silently when the token source yields no token, which
/// is the state the app ships in until Firebase credentials arrive. A push
/// failure must never surface as a user-visible error: push is an enhancement,
/// and the SSE stream in `NotificationService` already covers the foreground
/// case.
class PushService {
  final PwApi api;
  final PushTokenSource tokenSource;

  /// App version reported to `/api/devices`, for delivery diagnostics.
  final String? appVersion;

  final StreamController<PushOpen> _opens =
      StreamController<PushOpen>.broadcast();

  StreamSubscription<String>? _refreshSub;
  StreamSubscription<PushMessage>? _openedSub;
  StreamSubscription<PushMessage>? _foregroundSub;

  /// The token currently registered with the backend, so [unregisterDevice]
  /// can delete the right one even after the platform has rotated it.
  String? _registeredToken;

  bool _permissionGranted = false;
  bool _started = false;
  bool _disposed = false;

  PushService({
    required this.api,
    this.tokenSource = const StubPushTokenSource(),
    this.appVersion,
  });

  /// Fires when the user taps a push. Broadcast, so both a router and a
  /// badge-clearing listener can subscribe.
  Stream<PushOpen> get onOpen => _opens.stream;

  /// Foreground pushes, for an in-app banner. The OS draws nothing for these.
  ///
  /// Distinct from [onOpen]: arriving is not the same as being tapped.
  Stream<PushMessage> get onForegroundMessage =>
      _foregroundMessages.stream;

  final StreamController<PushMessage> _foregroundMessages =
      StreamController<PushMessage>.broadcast();

  /// The token last registered with the backend, or null. Test seam.
  String? get registeredToken => _registeredToken;

  bool get hasPermission => _permissionGranted;

  /// Requests notification permission.
  ///
  /// Idempotent and safe to call on every launch: the platform only shows the
  /// system prompt once. Returns false — never throws — when there is no
  /// platform SDK.
  Future<bool> ensurePermission() async {
    if (_disposed) return false;
    try {
      _permissionGranted = await tokenSource.requestPermission();
    } on Exception {
      // A platform channel failure is not the user's problem.
      _permissionGranted = false;
    }
    return _permissionGranted;
  }

  /// Subscribes to platform message streams and delivers any cold-start tap.
  ///
  /// Call once, after sign-in. Repeat calls are no-ops.
  Future<void> start() async {
    if (_disposed || _started) return;
    _started = true;

    _refreshSub = tokenSource.onTokenRefresh.listen(
      _onTokenRefreshed,
      // A dead refresh stream must not take down the app; the existing token
      // stays registered and still works.
      onError: (Object _) {},
      cancelOnError: false,
    );

    _openedSub = tokenSource.onNotificationOpened.listen(
      (message) => _emitOpen(PushOpen(message: message)),
      onError: (Object _) {},
      cancelOnError: false,
    );

    _foregroundSub = tokenSource.onForegroundMessage.listen(
      (message) {
        if (!_disposed && _foregroundMessages.hasListener) {
          _foregroundMessages.add(message);
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );

    // A tap that cold-launched the app is not on any stream — it has to be
    // pulled explicitly, exactly once.
    try {
      final initial = await tokenSource.initialMessage();
      if (initial != null) {
        _emitOpen(PushOpen(message: initial, fromColdStart: true));
      }
    } on Exception {
      // Nothing to route; a normal launch is indistinguishable from a failed
      // lookup here, and neither is an error.
    }
  }

  /// Registers this device's push token with the backend.
  ///
  /// Called after sign-in and after session restore. A null token (no
  /// permission, no SDK, simulator) is a silent no-op, as is any API failure:
  /// the app works fine without push.
  ///
  /// Returns the token registered, or null if nothing was.
  Future<String?> registerDevice() async {
    if (_disposed) return null;

    String? token;
    try {
      token = await tokenSource.getToken();
    } on Exception {
      return null;
    }
    if (token == null || token.isEmpty) return null;

    try {
      await api.registerDevice(
        token: token,
        platform: tokenSource.platform,
        appVersion: appVersion,
      );
      _registeredToken = token;
      return token;
    } on ApiException catch (error) {
      // 401 is worth surfacing to AuthService via ApiClient.onUnauthorized,
      // which has already fired by now. Everything else is swallowed: a
      // failed device registration costs the user nothing today.
      debugPrint('PushService.registerDevice failed: $error');
      return null;
    }
  }

  /// Deletes this device's token from the backend.
  ///
  /// **Must be called before the bearer token is cleared** — `DELETE
  /// /api/devices/:token` is an authenticated request. `AuthService.logout()`
  /// does this in the right order.
  ///
  /// Never throws: a sign-out must complete even if the network is down. The
  /// server also self-cleans dead tokens when a send returns `invalid_token`.
  Future<void> unregisterDevice() async {
    if (_disposed) return;

    final token = _registeredToken ?? await _tokenQuietly();
    if (token == null || token.isEmpty) return;

    try {
      await api.deleteDevice(token);
    } on ApiException catch (error) {
      debugPrint('PushService.unregisterDevice failed: $error');
    } finally {
      _registeredToken = null;
    }
  }

  Future<String?> _tokenQuietly() async {
    try {
      return await tokenSource.getToken();
    } on Exception {
      return null;
    }
  }

  /// Re-registers when the platform rotates the token, and retires the old one
  /// so the user does not accumulate dead device rows.
  Future<void> _onTokenRefreshed(String token) async {
    if (_disposed || token.isEmpty) return;

    final previous = _registeredToken;
    try {
      await api.registerDevice(
        token: token,
        platform: tokenSource.platform,
        appVersion: appVersion,
      );
      _registeredToken = token;

      if (previous != null && previous != token) {
        try {
          await api.deleteDevice(previous);
        } on ApiException {
          // The server drops it on the next `invalid_token` result anyway.
        }
      }
    } on ApiException catch (error) {
      debugPrint('PushService token refresh failed: $error');
    }
  }

  void _emitOpen(PushOpen open) {
    if (_disposed || _opens.isClosed) return;
    _opens.add(open);
  }

  /// Cancels every subscription and closes both streams. Safe to call more
  /// than once, and safe to call while a register/unregister is in flight —
  /// the `_disposed` guard makes those complete as no-ops.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
    _refreshSub = null;
    _openedSub = null;
    _foregroundSub = null;

    await _opens.close();
    await _foregroundMessages.close();
    await tokenSource.dispose();
  }
}
