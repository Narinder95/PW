import 'package:flutter/foundation.dart';

import 'json.dart';

/// Tier of the walking challenge. `none` means no tier has been earned yet.
enum WalkingLevel {
  none('none'),
  bronze('bronze'),
  silver('silver'),
  gold('gold');

  const WalkingLevel(this.wire);

  final String wire;

  static const Map<String, WalkingLevel> _byWire = <String, WalkingLevel>{
    'none': WalkingLevel.none,
    'bronze': WalkingLevel.bronze,
    'silver': WalkingLevel.silver,
    'gold': WalkingLevel.gold,
  };

  /// Unknown spellings degrade to [WalkingLevel.none] rather than throwing.
  static WalkingLevel parse(Object? value) =>
      asEnum(value, _byWire, WalkingLevel.none);
}

/// Per-day (or "so far today") status against that day's target.
///
/// `warning` and `noData` both freeze the streak without resetting it;
/// `shortfall` is the only status that demotes a level. See
/// `docs/API_CONTRACT.md`'s `WalkingChallenge` section — this mirrors the
/// server's computation exactly and must not be re-derived on the client.
enum DayStepStatus {
  met('met'),
  warning('warning'),
  shortfall('shortfall'),
  noData('no_data');

  const DayStepStatus(this.wire);

  final String wire;

  static const Map<String, DayStepStatus> _byWire = <String, DayStepStatus>{
    'met': DayStepStatus.met,
    'warning': DayStepStatus.warning,
    'shortfall': DayStepStatus.shortfall,
    'no_data': DayStepStatus.noData,
  };

  static DayStepStatus parse(Object? value) =>
      asEnum(value, _byWire, DayStepStatus.noData);
}

/// One entry of `WalkingChallenge.history` — a single committed day.
@immutable
class StepDay {
  /// `YYYY-MM-DD`.
  final String date;
  final int steps;
  final int target;
  final DayStepStatus status;

  const StepDay({
    required this.date,
    required this.steps,
    required this.target,
    required this.status,
  });

  factory StepDay.fromJson(Map<String, dynamic> json) => StepDay(
        date: asString(json['date']),
        steps: asInt(json['steps']),
        target: asInt(json['target']),
        status: DayStepStatus.parse(json['status']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepDay &&
          other.date == date &&
          other.steps == steps &&
          other.target == target &&
          other.status == status;

  @override
  int get hashCode => Object.hash(date, steps, target, status);

  @override
  String toString() => 'StepDay($date, $steps/$target, ${status.wire})';
}

/// `GET /api/challenge`, `POST /api/steps/sync`.
///
/// Every field is server-computed over the full `daily_steps` history, the
/// same way `Habit.streak` is — the client must not recompute
/// promotion/demotion locally. [todaySteps]/[todayStatus] are a live preview
/// only; the committed [level]/[streakDays] only ever reflect yesterday and
/// earlier (see the contract doc).
@immutable
class WalkingChallenge {
  final WalkingLevel level;
  final int streakDays;

  /// The step target that applies today, given the committed [level].
  final int target;

  /// Null once at [WalkingLevel.gold] — there is nothing further to reach.
  final WalkingLevel? nextLevel;

  /// Null at gold. Otherwise how many more full-target days are needed.
  final int? daysToNextLevel;

  final int todaySteps;
  final DayStepStatus todayStatus;

  /// Trailing committed days, oldest first (server caps at 14).
  final List<StepDay> history;

  const WalkingChallenge({
    this.level = WalkingLevel.none,
    this.streakDays = 0,
    this.target = 0,
    this.nextLevel,
    this.daysToNextLevel,
    this.todaySteps = 0,
    this.todayStatus = DayStepStatus.noData,
    this.history = const <StepDay>[],
  });

  /// Whether the most recent committed day (or today, live) needs the user's
  /// attention — a frozen streak or a demotion just happened.
  bool get hasWarning =>
      todayStatus == DayStepStatus.warning ||
      todayStatus == DayStepStatus.shortfall ||
      (history.isNotEmpty &&
          (history.last.status == DayStepStatus.warning ||
              history.last.status == DayStepStatus.shortfall));

  factory WalkingChallenge.fromJson(Map<String, dynamic> json) {
    final nextLevelRaw = json['nextLevel'];
    return WalkingChallenge(
      level: WalkingLevel.parse(json['level']),
      streakDays: asInt(json['streakDays']),
      target: asInt(json['target']),
      nextLevel: nextLevelRaw == null ? null : WalkingLevel.parse(nextLevelRaw),
      daysToNextLevel: asIntOrNull(json['daysToNextLevel']),
      todaySteps: asInt(json['todaySteps']),
      todayStatus: DayStepStatus.parse(json['todayStatus']),
      history: asModelList(json['history'], StepDay.fromJson),
    );
  }

  @override
  String toString() =>
      'WalkingChallenge(${level.wire}, streak: $streakDays, today: $todaySteps/$target)';
}
