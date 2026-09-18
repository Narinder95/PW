import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/json.dart';
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

  /// Live-tick sensor updates are batched into a `POST /api/steps/sync` no
  /// more than this often, so a burst of steps costs one API hit rather than
  /// one per tick.
  static const Duration _liveSyncDebounce = Duration(seconds: 20);

  /// ...unless the running total has jumped by at least this many steps
  /// since the last sync, in which case it goes out immediately instead of
  /// waiting out the debounce — otherwise continuous walking (a tick every
  /// few steps) would keep resetting the timer and never actually sync.
  static const int _liveSyncStepFloor = 100;

  WalkingChallenge? _challenge;
  bool _isLoading = false;
  bool _permissionDenied = false;
  ApiException? _lastError;
  bool _disposed = false;

  StreamSubscription<int>? _liveSub;
  Timer? _liveSyncTimer;
  int? _lastSyncedTodaySteps;

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

  /// Reflects a manually-logged Steps habit in the cached challenge the
  /// instant it's saved, rather than leaving the Journey card showing a
  /// stale [WalkingChallenge.todaySteps] until the next [refresh] /
  /// [syncFromDevice]. The habit log itself already persisted server-side
  /// (`upsertDailySteps`, same MAX-of-existing rule as a device sync), so
  /// this only needs to update the local cache and then reconcile the
  /// derived fields (status/level/streak) from the server right after.
  ///
  /// A no-op if nothing has been loaded into [challenge] yet — there's
  /// nothing to bump, and the next [refresh] will pick the value up anyway.
  Future<void> applyManualSteps(int steps) async {
    if (_disposed) return;
    final current = _challenge;
    if (current == null) return;

    if (steps > current.todaySteps) {
      _challenge = current.copyWith(todaySteps: steps);
      _notify();
    }

    try {
      _challenge = await api.getChallenge();
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    }
    _notify();
  }

  /// Starts listening to the device's live step sensor (when [stepSource]
  /// offers one) so the Journey card moves the instant a step is counted,
  /// instead of waiting for the next poll. Safe to call repeatedly — a
  /// second call while already listening is a no-op. Call [stopLiveTracking]
  /// when the Journey tab is no longer visible.
  void startLiveTracking() {
    if (_disposed || _liveSub != null) return;
    final stream = stepSource.liveTodaySteps();
    if (stream == null) return;
    _liveSub = stream.listen(_onLiveTick, onError: (_) {});
  }

  /// Stops the live subscription and flushes any step count that hasn't
  /// made it to the server yet, so a step taken right before backgrounding
  /// isn't lost to a debounce timer that never gets to fire.
  Future<void> stopLiveTracking() async {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    final sub = _liveSub;
    _liveSub = null;
    await sub?.cancel();

    final steps = _challenge?.todaySteps;
    if (steps != null && steps != _lastSyncedTodaySteps) {
      await _pushLiveSteps(steps);
    }
  }

  void _onLiveTick(int todaySteps) {
    if (_disposed) return;
    final current = _challenge;
    if (current == null) {
      _challenge = WalkingChallenge(todaySteps: todaySteps);
      _notify();
    } else if (todaySteps > current.todaySteps) {
      _challenge = current.copyWith(todaySteps: todaySteps);
      _notify();
    }
    _scheduleBackendSync(todaySteps);
  }

  void _scheduleBackendSync(int todaySteps) {
    final delta = todaySteps - (_lastSyncedTodaySteps ?? 0);
    if (delta >= _liveSyncStepFloor) {
      _liveSyncTimer?.cancel();
      _liveSyncTimer = null;
      unawaited(_pushLiveSteps(todaySteps));
      return;
    }
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer(_liveSyncDebounce, () => unawaited(_pushLiveSteps(todaySteps)));
  }

  /// The actual `POST /api/steps/sync` for a live-tracked value. Errors are
  /// swallowed into [lastError] rather than thrown — a dropped background
  /// sync must not crash the live-tracking loop; the next tick (or the next
  /// [syncFromDevice]) will simply try again with a larger total.
  Future<void> _pushLiveSteps(int todaySteps) async {
    if (_disposed) return;
    _lastSyncedTodaySteps = todaySteps;
    try {
      final today = asDateOnly(DateTime.now());
      _challenge = await api.syncSteps({today: todaySteps});
      _lastError = null;
      _notify();
    } on ApiException catch (error) {
      _lastError = error;
    }
  }

  /// Drops the cache. Call on sign-out, mirroring `FriendsRepository.clear()`.
  void clear() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
    unawaited(_liveSub?.cancel());
    _liveSub = null;
    _lastSyncedTodaySteps = null;
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
    _liveSyncTimer?.cancel();
    unawaited(_liveSub?.cancel());
    super.dispose();
  }
}
