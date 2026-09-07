import 'package:flutter/foundation.dart';

import '../models/walking_challenge.dart';
import 'api/api_exception.dart';
import 'api/pw_api.dart';
import 'step_source.dart';

/// Caches the walking-challenge state and drives the device sync.
///
/// Same shape as `FriendsRepository`: a private cache, a loading flag, and
/// `lastError`, all behind a `ChangeNotifier` so `WalkingChallengeCard` can
/// rebuild with a `ListenableBuilder`. The server is the sole source of
/// truth for level/streak (see `WalkingChallenge`'s doc comment) — this class
/// only fetches and syncs, it never computes promotion/demotion itself.
class WalkingChallengeService extends ChangeNotifier {
  final PwApi api;
  final StepSource stepSource;

  WalkingChallengeService({
    required this.api,
    this.stepSource = const StubStepSource(),
  });

  WalkingChallenge? _challenge;
  bool _isLoading = false;
  bool _permissionDenied = false;
  ApiException? _lastError;
  bool _disposed = false;

  WalkingChallenge? get challenge => _challenge;
  bool get isLoading => _isLoading;

  /// True once [syncFromDevice] has been denied step-data access. The UI can
  /// use this to show a "connect Health" prompt instead of a bare empty state.
  bool get permissionDenied => _permissionDenied;

  ApiException? get lastError => _lastError;

  /// `GET /api/challenge`. Reads the server's last-computed state without
  /// touching the device.
  Future<void> refresh() async {
    if (_disposed) return;
    _isLoading = true;
    _notify();
    try {
      _challenge = await api.getChallenge();
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Requests device permission, reads the last week+today of step data, and
  /// syncs it to the server in one round trip.
  ///
  /// Falls back to [refresh] when permission is denied, so the card still
  /// shows the server's last-known state instead of going blank. Never
  /// throws — a sync failure leaves the previous [challenge] in place.
  Future<void> syncFromDevice() async {
    if (_disposed) return;
    _isLoading = true;
    _notify();
    try {
      final granted = await stepSource.requestAuthorization();
      _permissionDenied = !granted;
      if (!granted) {
        await _refreshQuietly();
        return;
      }

      final days = await stepSource.readDailySteps();
      if (days.isEmpty) {
        await _refreshQuietly();
        return;
      }

      _challenge = await api.syncSteps(days);
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      _challenge = await api.getChallenge();
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    }
  }

  /// Drops the cache. Call on sign-out, mirroring `FriendsRepository.clear()`.
  void clear() {
    _challenge = null;
    _permissionDenied = false;
    _lastError = null;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
