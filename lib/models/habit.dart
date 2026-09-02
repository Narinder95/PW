import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'json.dart';

/// One of the signed-in user's own habits (`GET /api/habits`).
///
/// Every getter below predates the backend and is relied on by `HabitCard`,
/// `JournalScreen` and `StatsDashboard` — their behaviour is unchanged.
@immutable
class Habit {
  final String id;
  final String name;

  /// Emoji string.
  final String icon;

  final Color color;

  /// Server enforces `>= 1`, but the client still guards division.
  final int target;

  final String unit;
  final int progress;

  /// 7 days of completion data, oldest first, index 6 = today.
  final List<bool> weekData;

  /// Streak as computed by the server over the **full** log history.
  ///
  /// Null for a habit built locally that has never round-tripped (the
  /// add-habit dialog), in which case [streak] falls back to deriving from
  /// [weekData].
  final int? serverStreak;

  /// `completedToday` as computed by the server, which owns the user's
  /// timezone-local day boundary. Null for a locally-built habit.
  final bool? serverCompletedToday;

  const Habit({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.target,
    required this.unit,
    required this.progress,
    required this.weekData,
    this.serverStreak,
    this.serverCompletedToday,
  });

  // Calculate completion percentage
  // Guards target <= 0: 0/0 is NaN, which throws when used as a layout width.
  double get completionPercentage =>
      target <= 0 ? 0 : (progress / target).clamp(0, 1).toDouble();

  /// Consecutive completed days ending today.
  ///
  /// Prefers the server's value: [weekData] is only a 7-day window, so
  /// deriving from it silently caps every streak at 7 and would render a
  /// 30-day streak as "7". Falls back to the window only for a habit that has
  /// never been to the server.
  int get streak => serverStreak ?? _derivedStreak;

  int get _derivedStreak {
    int count = 0;
    for (int i = weekData.length - 1; i >= 0; i--) {
      if (weekData[i]) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  // Get completion count for the week
  int get weekCompletions => weekData.where((completed) => completed).length;

  // Check if today's habit is completed
  bool get completedToday =>
      serverCompletedToday ?? (weekData.isNotEmpty ? weekData.last : false);

  /// Parses the contract's `Habit` shape.
  ///
  /// `streak` and `completedToday` are stored as sent. Per the contract the
  /// server computes them over the full log history and against the user's
  /// local day boundary, so they are authoritative and must not be
  /// re-derived from the 7-day [weekData] window.
  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
        id: asString(json['id']),
        name: asString(json['name']),
        icon: asString(json['icon']),
        color: asColor(json['color']),
        target: asInt(json['target']),
        unit: asString(json['unit']),
        progress: asInt(json['progress']),
        weekData: asWeekData(json['weekData']),
        serverStreak: json['streak'] == null ? null : asInt(json['streak']),
        serverCompletedToday:
            json['completedToday'] == null ? null : asBool(json['completedToday']),
      );

  /// Includes the derived `streak`/`completedToday` so a round-tripped habit
  /// matches the wire shape the server would have produced.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'icon': icon,
        'color': colorToHex(color),
        'target': target,
        'unit': unit,
        'progress': progress,
        'weekData': weekData,
        'streak': streak,
        'completedToday': completedToday,
      };

  Habit copyWith({
    String? id,
    String? name,
    String? icon,
    Color? color,
    int? target,
    String? unit,
    int? progress,
    List<bool>? weekData,
    int? serverStreak,
    bool? serverCompletedToday,
  }) =>
      Habit(
        id: id ?? this.id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        target: target ?? this.target,
        unit: unit ?? this.unit,
        progress: progress ?? this.progress,
        weekData: weekData ?? this.weekData,
        serverStreak: serverStreak ?? this.serverStreak,
        serverCompletedToday: serverCompletedToday ?? this.serverCompletedToday,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Habit &&
          other.id == id &&
          other.name == name &&
          other.icon == icon &&
          other.color == color &&
          other.target == target &&
          other.unit == unit &&
          other.progress == progress &&
          other.serverStreak == serverStreak &&
          other.serverCompletedToday == serverCompletedToday &&
          listEquals(other.weekData, weekData);

  @override
  int get hashCode => Object.hash(
        id,
        name,
        icon,
        color,
        target,
        unit,
        progress,
        Object.hashAll(weekData),
        serverStreak,
        serverCompletedToday,
      );

  @override
  String toString() => 'Habit($id, $name, $progress/$target $unit)';
}
