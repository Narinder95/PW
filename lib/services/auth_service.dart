import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/pw_api.dart';
import 'push_service.dart';

/// Where the session stands.
enum AuthState {
  /// Before [AuthService.restoreSession] has finished. The UI must show a
  /// splash here, not the sign-in screen — flashing login at a signed-in user
  /// on every cold start is the bug this state exists to prevent.
  unknown,

  signedOut,
  signedIn,
}

/// Owns the bearer token and the signed-in [UserProfile].
///
/// Persists only the token; the profile is re-fetched from `/api/me` on
/// restore, so a name or avatar changed on another device is picked up.
class AuthService extends ChangeNotifier {
  /// shared_preferences key for the bearer token.
  static const String tokenKey = 'pw.auth.token';

  final ApiClient client;
  final PwApi api;

  /// Registers/unregisters the device token around sign-in and sign-out.
  /// Optional: a test can omit it entirely.
  final PushService? pushService;

  AuthState _state = AuthState.unknown;
  UserProfile? _user;
  String? _token;
  bool _disposed = false;

  /// Set when a restore or sign-in failed for a reason worth showing.
  ApiException? _lastError;

  AuthService({
    required this.client,
    PwApi? api,
    this.pushService,
  }) : api = api ?? PwApi(client) {
    // Any 401 from anywhere in the app forces a sign-out. Registered once,
    // here, so no individual call site has to remember.
    client.onUnauthorized = _onUnauthorized;
  }

  AuthState get state => _state;
  UserProfile? get user => _user;
  String? get token => _token;
  ApiException? get lastError => _lastError;

  bool get isSignedIn => _state == AuthState.signedIn;
  bool get isResolved => _state != AuthState.unknown;

  /// Reads a persisted token, applies it to the client, and validates it
  /// against `/api/me`.
  ///
  /// Ends in [AuthState.signedIn] or [AuthState.signedOut] — never leaves the
  /// app stuck on [AuthState.unknown], including when the network is down. A
  /// network failure keeps the token (it may still be valid) but reports
  /// signed-out for this launch; only a real 401 discards it.
  Future<void> restoreSession() async {
    final stored = await _readStoredToken();

    if (stored == null || stored.isEmpty) {
      _applySignedOut();
      return;
    }

    _token = stored;
    client.authToken = stored;

    try {
      final profile = await api.me();
      _user = profile;
      _state = AuthState.signedIn;
      _lastError = null;
      _notify();
      await _registerPush();
    } on ApiException catch (error) {
      _lastError = error;
      if (error.isUnauthorized) {
        // The token is genuinely dead — drop it so the next launch is fast.
        await _clearStoredToken();
        _applySignedOut();
      } else {
        // Offline, or the backend is down. Keep the token for the next launch
        // but do not claim a session we could not verify.
        _token = null;
        client.authToken = null;
        _state = AuthState.signedOut;
        _notify();
      }
    }
  }

  /// Guarantees there is a usable account, provisioning one if needed.
  ///
  /// This is the app's entire sign-in story. There is no login screen: on
  /// first launch we silently create an anonymous account so the user can
  /// start immediately. The account is real — it has an id, a handle, habits
  /// and friends — it simply has no credentials until the user chooses to
  /// claim it with an email or phone (see [linkAccount]).
  ///
  /// Order matters: restore an existing session first, so a returning user is
  /// never handed a second, empty account.
  ///
  /// Ends in [AuthState.signedIn] on success. On a network failure it ends in
  /// [AuthState.signedOut] with [lastError] set, and the UI shows its retry
  /// panel — it must NOT silently create a duplicate account just because the
  /// server was briefly unreachable.
  Future<void> ensureAccount() async {
    await restoreSession();
    if (_state == AuthState.signedIn) return;

    // A stored token that failed for a non-auth reason (offline) is kept by
    // restoreSession. Provisioning now would strand the real account, so only
    // provision when there is genuinely no token on this device.
    final stored = await _readStoredToken();
    if (stored != null && stored.isNotEmpty) return;

    try {
      await _authenticate(() => api.registerAnonymous());
    } on ApiException catch (error) {
      _lastError = error;
      _applySignedOut();
    }
  }

  /// Claims the current anonymous account with an email and/or phone plus a
  /// password, so it can be recovered after a reinstall or on another device.
  ///
  /// Keeps the same account and the same session — nothing is lost. Throws
  /// [ApiException]: `409 conflict` if the email/phone/handle is taken,
  /// `400 validation_error` with [ApiException.field] naming the bad input.
  Future<UserProfile> linkAccount({
    String? email,
    String? phone,
    required String password,
    String? username,
  }) async {
    final updated = await api.linkAccount(
      email: email,
      phone: phone,
      password: password,
      username: username,
    );
    _user = updated;
    _lastError = null;
    _notify();
    return updated;
  }

  /// `POST /api/auth/register`. Signs the new account straight in.
  ///
  /// Retained for account recovery on a new device; the app no longer shows a
  /// registration screen.
  ///
  /// Throws [ApiException] — `409 conflict` for a taken username or email,
  /// `400 validation_error` with [ApiException.field] naming the bad input.
  Future<UserProfile> register({
    required String username,
    required String name,
    required String email,
    required String password,
  }) async {
    return _authenticate(
      () => api.register(
        username: username,
        name: name,
        email: email,
        password: password,
      ),
    );
  }

  /// `POST /api/auth/login`. [usernameOrEmail] accepts either.
  ///
  /// Throws [ApiException] with `unauthorized` on bad credentials.
  Future<UserProfile> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    return _authenticate(
      () => api.login(
        usernameOrEmail: usernameOrEmail,
        password: password,
      ),
    );
  }

  Future<UserProfile> _authenticate(Future<AuthResult> Function() call) async {
    try {
      final result = await call();
      _token = result.token;
      _user = result.user;
      client.authToken = result.token;
      _state = AuthState.signedIn;
      _lastError = null;
      await _persistToken(result.token);
      _notify();
      await _registerPush();
      return result.user;
    } on ApiException catch (error) {
      _lastError = error;
      _notify();
      rethrow;
    }
  }

  /// Signs out: unregisters the push device, tells the server to revoke the
  /// token, then clears local state.
  ///
  /// The order matters. `DELETE /api/devices/:token` and `POST
  /// /api/auth/logout` are both authenticated, so both must happen while the
  /// bearer token is still set. Neither is allowed to block the sign-out —
  /// a user who taps "Sign out" on a plane still gets signed out.
  Future<void> logout() async {
    // 1. Retire the push token while we are still authenticated. Otherwise
    //    the DELETE is unauthenticated and this device keeps receiving the
    //    previous account's notifications.
    await pushService?.unregisterDevice();

    // 2. Revoke server-side. Best-effort.
    try {
      await api.logout();
    } on ApiException catch (error) {
      debugPrint('AuthService.logout: server revoke failed: $error');
    }

    // 3. Clear locally. This part always happens.
    await _clearStoredToken();
    _applySignedOut();
  }

  /// Updates the signed-in user's own profile and refreshes local state.
  Future<UserProfile> updateProfile({String? name, Color? avatarColor}) async {
    final updated = await api.updateMe(name: name, avatarColor: avatarColor);
    _user = updated;
    _notify();
    return updated;
  }

  /// Re-reads `/api/me` without touching the token. Cheap way for a settings
  /// screen to pick up a change made elsewhere.
  Future<UserProfile?> refreshProfile() async {
    if (!isSignedIn) return null;
    try {
      final profile = await api.me();
      _user = profile;
      _notify();
      return profile;
    } on ApiException catch (error) {
      _lastError = error;
      return null;
    }
  }

  /// Forces a signed-out state without calling the server.
  ///
  /// Wired to [ApiClient.onUnauthorized], so an expired token discovered by
  /// *any* request drops the session immediately. Does not attempt the device
  /// unregister: the token is already dead, so the DELETE would 401 too.
  void forceSignOut() => _onUnauthorized();

  void _onUnauthorized() {
    if (_disposed) return;
    if (_state == AuthState.signedOut && _token == null) return;
    // Fire-and-forget: this is called from inside a response handler, which
    // cannot await.
    unawaited(_clearStoredToken());
    _applySignedOut();
  }

  void _applySignedOut() {
    _token = null;
    _user = null;
    client.authToken = null;
    _state = AuthState.signedOut;
    _notify();
  }

  /// Registers the device for push. Never allowed to fail a sign-in.
  Future<void> _registerPush() async {
    final push = pushService;
    if (push == null) return;
    try {
      await push.start();
      await push.registerDevice();
    } on Exception catch (error) {
      debugPrint('AuthService: push registration skipped: $error');
    }
  }

  Future<String?> _readStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(tokenKey);
    } on Exception {
      // No plugin (unit test) or unreadable store: treat as signed out rather
      // than hanging on AuthState.unknown forever.
      return null;
    }
  }

  Future<void> _persistToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, token);
    } on Exception catch (error) {
      // The session still works for this run; it just will not survive a
      // restart.
      debugPrint('AuthService: could not persist token: $error');
    }
  }

  Future<void> _clearStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(tokenKey);
    } on Exception {
      // Nothing useful to do — the in-memory token is cleared regardless.
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // Drop the callback so a late response cannot resurrect a disposed
    // service.
    if (identical(client.onUnauthorized, _onUnauthorized)) {
      client.onUnauthorized = null;
    }
    super.dispose();
  }
}
