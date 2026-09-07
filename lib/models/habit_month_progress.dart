import 'package:flutter/material.dart';

import 'json.dart';

/// One habit's daily completion for a single calendar month
/// (`GET /api/habits/month`), for the Journal tab's radial progress card.
@immutable
class HabitMonthProgress {
  final String id;
  final String name;
  final String icon;
  final Color color;

  /// One entry per day of the month, oldest first (index 0 = the 1st).
  /// `true` = target met, `false` = missed, `null` = no data (before the
  /// habit existed, or a day that hasn't happened yet).
  final List<bool?> monthData;

  /// The raw number actually logged each day, same length/alignment as
  /// [monthData]. `null` means no log row exists for that date — never `0`,
  /// which would mean the user logged zero. Averages must skip the nulls
  /// rather than counting them as zero.
  final List<int?> progressData;

  const HabitMonthProgress({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.monthData,
    this.progressData = const <int?>[],
  });

  factory HabitMonthProgress.fromJson(Map<String, dynamic> json) =>
      HabitMonthProgress(
        id: asString(json['id']),
        name: asString(json['name']),
        icon: asString(json['icon']),
        color: asColor(json['color']),
        monthData: asTriStateList(json['monthData']),
        progressData: asNullableIntList(json['progressData']),
      );

  @override
  String toString() =>
      'HabitMonthProgress($id, $name, ${monthData.length} days)';
}

/// A month's worth of every own habit's daily completion
/// (`GET /api/habits/month`).
@immutable
class HabitMonthReport {
  /// `YYYY-MM`.
  final String month;

  /// Number of days in [month]; every [HabitMonthProgress.monthData] is this
  /// long.
  final int days;

  final List<HabitMonthProgress> habits;

  const HabitMonthReport({
    required this.month,
    required this.days,
    this.habits = const <HabitMonthProgress>[],
  });

  factory HabitMonthReport.fromJson(Map<String, dynamic> json) =>
      HabitMonthReport(
        month: asString(json['month']),
        days: asInt(json['days']),
        habits: asModelList(json['habits'], HabitMonthProgress.fromJson),
      );

  @override
  String toString() => 'HabitMonthReport($month, ${habits.length} habits)';
}
