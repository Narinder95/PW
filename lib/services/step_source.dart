import 'dart:async';
import 'dart:convert';

import 'package:health/health.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/json.dart';

/// The device's own step count, behind an interface.
///
/// Mirrors `PushTokenSource` in `push_service.dart`: the abstraction exists
/// so `WalkingChallengeService` and its tests never touch a platform plugin
/// directly, and so a permission denial or an unsupported platform degrades
/// silently instead of crashing the Journey tab.
abstract class StepSource {
  const StepSource();

  /// Requests read access to step data (Health Connect on Android, HealthKit
  /// on iOS). Returns whether it was granted. Must be safe to call
  /// repeatedly, and must never throw — a platform without Health Connect
  /// installed, or a simulator, is "not granted", not an error.
  Future<bool> requestAuthorization();

  /// Total steps per day for the last [days] days (today inclusive), keyed
  /// by `YYYY-MM-DD` in the device's local timezone. A day with no data is
  /// simply absent from the map, not a zero entry — `WalkingChallengeService`
  /// only syncs days it actually has a reading for.
  Future<Map<String, int>> readDailySteps({int days = 8});
}

/// Reads real step data via `package:health` (Health Connect / HealthKit).
class HealthStepSource extends StepSource {
  final Health _health = Health();

  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.STEPS,
  ];
  static const List<HealthDataAccess> _permissions = <HealthDataAccess>[
    HealthDataAccess.READ,
  ];

  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> requestAuthorization() async {
    try {
      await _ensureConfigured();
      final hasPermission =
          await _health.hasPermissions(_types, permissions: _permissions);
      if (hasPermission == true) return true;
      return await _health.requestAuthorization(_types, permissions: _permissions);
    } on Exception {
      // No Health Connect / HealthKit on this device, plugin not configured
      // natively yet, or the user declined — all "not granted", not an error.
      return false;
    }
  }

  @override
  Future<Map<String, int>> readDailySteps({int days = 8}) async {
    final out = <String, int>{};
    try {
      await _ensureConfigured();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (var i = days - 1; i >= 0; i--) {
        final dayStart = today.subtract(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final steps = await _health.getTotalStepsInInterval(dayStart, dayEnd);
        if (steps != null && steps >= 0) {
          out[asDateOnly(dayStart)] = steps;
        }
      }
    } on Exception {
      // Return whatever was collected before the failure rather than none of
      // it — a partial sync is still useful, and the caller must not crash.
    }
    return out;
  }
}

/// Reads the device's built-in step-counter sensor directly (via
/// `package:pedometer`), bypassing Health Connect/HealthKit entirely.
///
/// Fallback behind [CompositeStepSource] for when the primary health store
/// has no synced data — e.g. a Samsung phone where Samsung Health hasn't
/// been connected to Health Connect. The sensor only ever reports a
/// cumulative count since the device's last boot, so this class can only
/// build up its own day-by-day log from the first time it is read forward:
/// it cannot recover steps from before tracking started, nor steps taken
/// between midnight and the first read after a day rolls over while the app
/// is closed. Both are accepted trade-offs of a foreground-only reader with
/// no background service.
class NativeStepCounterSource extends StepSource {
  static const String _logKey = 'pw.step_source.native.daily_log';
  static const String _baselineDateKey = 'pw.step_source.native.baseline_date';
  static const String _baselineCounterKey =
      'pw.step_source.native.baseline_counter';
  static const Duration _readTimeout = Duration(seconds: 5);

  @override
  Future<bool> requestAuthorization() async {
    try {
      final status = await Permission.activityRecognition.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, int>> readDailySteps({int days = 8}) async {
    try {
      final reading = await Pedometer.stepCountStream.first.timeout(_readTimeout);
      await _recordReading(reading.steps);
    } catch (_) {
      // Sensor unavailable, permission missing, or timed out — fall through
      // and return whatever history was already recorded.
    }

    final log = await _loadLog();
    final today = DateTime.now();
    final out = <String, int>{};
    for (var i = days - 1; i >= 0; i--) {
      final date = asDateOnly(today.subtract(Duration(days: i)));
      final steps = log[date];
      if (steps != null) out[date] = steps;
    }
    return out;
  }

  Future<void> _recordReading(int rawCounter) async {
    final prefs = await SharedPreferences.getInstance();
    final today = asDateOnly(DateTime.now());
    final baselineDate = prefs.getString(_baselineDateKey);
    final baselineCounter = prefs.getInt(_baselineCounterKey);
    final log = await _loadLog(prefs: prefs);

    if (baselineDate == null || baselineCounter == null) {
      // First-ever reading: nothing to diff against yet.
      await prefs.setString(_baselineDateKey, today);
      await prefs.setInt(_baselineCounterKey, rawCounter);
      return;
    }

    if (baselineDate == today) {
      log[today] = (rawCounter - baselineCounter).clamp(0, 1 << 31);
    } else {
      // The day rolled over since the last reading: finalize the previous
      // day with whatever was last observed, then start a fresh baseline.
      log[baselineDate] = (rawCounter - baselineCounter).clamp(0, 1 << 31);
      log[today] = 0;
      await prefs.setString(_baselineDateKey, today);
      await prefs.setInt(_baselineCounterKey, rawCounter);
    }

    await _saveLog(prefs, log);
  }

  Future<Map<String, int>> _loadLog({SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final raw = p.getString(_logKey);
    if (raw == null) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return decoded.map((key, value) => MapEntry(key.toString(), asInt(value)));
    } catch (_) {
      return <String, int>{};
    }
  }

  Future<void> _saveLog(SharedPreferences prefs, Map<String, int> log) async {
    // Bound storage: keep only the most recent 60 days.
    final sortedDates = log.keys.toList()..sort();
    final kept = sortedDates.length > 60
        ? sortedDates.sublist(sortedDates.length - 60)
        : sortedDates;
    final bounded = {for (final date in kept) date: log[date]!};
    await prefs.setString(_logKey, jsonEncode(bounded));
  }
}

/// Tries [primary] first and only consults [fallback] when [primary] has
/// nothing to offer — the composition `main.dart` hands `WalkingChallenge
/// Service` so it never has to know its data came from Health Connect vs.
/// the raw sensor.
class CompositeStepSource extends StepSource {
  final StepSource primary;
  final StepSource fallback;

  const CompositeStepSource({required this.primary, required this.fallback});

  @override
  Future<bool> requestAuthorization() async {
    final primaryGranted = await primary.requestAuthorization();
    final fallbackGranted = await fallback.requestAuthorization();
    return primaryGranted || fallbackGranted;
  }

  @override
  Future<Map<String, int>> readDailySteps({int days = 8}) async {
    final primaryData = await primary.readDailySteps(days: days);
    if (primaryData.isNotEmpty) return primaryData;
    return fallback.readDailySteps(days: days);
  }
}

/// The default [StepSource]: no platform plugin calls, no data.
///
/// Used until `requestAuthorization()` has actually been granted by the real
/// source, and in tests. Every call succeeds and returns nothing, so the
/// Journey tab renders its empty/no-data state rather than erroring.
class StubStepSource extends StepSource {
  const StubStepSource();

  @override
  Future<bool> requestAuthorization() async => false;

  @override
  Future<Map<String, int>> readDailySteps({int days = 8}) async =>
      const <String, int>{};
}
