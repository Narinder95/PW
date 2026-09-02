import 'package:flutter/material.dart';

import 'json.dart';

/// A friend's habit progress for today, as served read-only alongside
/// `GET /api/friends/:id`.
enum HabitStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  completed('completed');

  const HabitStatus(this.wire);

  final String wire;

  static const Map<String, HabitStatus> _byWire = <String, HabitStatus>{
    'not_started': HabitStatus.notStarted,
    'in_progress': HabitStatus.inProgress,
    'completed': HabitStatus.completed,
  };

  /// Unknown spellings degrade to [notStarted] — the most conservative
  /// reading, since it never claims progress the friend has not made.
  static HabitStatus parse(Object? value) =>
      asEnum(value, _byWire, HabitStatus.notStarted);

  String get label {
    switch (this) {
      case HabitStatus.notStarted:
        return 'Not started';
      case HabitStatus.inProgress:
        return 'In progress';
      case HabitStatus.completed:
        return 'Completed';
    }
  }
}

/// One of a friend's habits. Read-only: the client can never log against it.
///
/// Deliberately not a [Habit]: there is no `weekData` here, so reusing
/// `Habit` would mean inventing a fake week strip for a friend's card.
@immutable
class FriendHabit {
  final String id;
  final String name;

  /// Emoji string.
  final String icon;

  final Color color;
  final int progress;

  /// May be `0` or negative on a malformed payload — [percentage] guards it.
  final int target;

  final String unit;
  final HabitStatus status;

  const FriendHabit({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.progress,
    required this.target,
    required this.unit,
    this.status = HabitStatus.notStarted,
  });

  /// Completion ratio in `[0,1]`.
  ///
  /// Guards `target <= 0`: `0/0` is NaN, and a NaN width aborts the whole
  /// render tree rather than just this card.
  double get percentage =>
      target <= 0 ? 0 : (progress / target).clamp(0.0, 1.0).toDouble();

  bool get isCompleted => status == HabitStatus.completed;

  /// e.g. `"1300 / 2000 mL"`.
  String get progressLabel {
    final suffix = unit.isEmpty ? '' : ' $unit';
    return '$progress / $target$suffix';
  }

  factory FriendHabit.fromJson(Map<String, dynamic> json) => FriendHabit(
        id: asString(json['id']),
        name: asString(json['name']),
        icon: asString(json['icon']),
        color: asColor(json['color']),
        progress: asInt(json['progress']),
        target: asInt(json['target']),
        unit: asString(json['unit']),
        status: HabitStatus.parse(json['status']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'icon': icon,
        'color': colorToHex(color),
        'progress': progress,
        'target': target,
        'unit': unit,
        'status': status.wire,
      };

  FriendHabit copyWith({
    String? id,
    String? name,
    String? icon,
    Color? color,
    int? progress,
    int? target,
    String? unit,
    HabitStatus? status,
  }) =>
      FriendHabit(
        id: id ?? this.id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        progress: progress ?? this.progress,
        target: target ?? this.target,
        unit: unit ?? this.unit,
        status: status ?? this.status,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendHabit &&
          other.id == id &&
          other.name == name &&
          other.icon == icon &&
          other.color == color &&
          other.progress == progress &&
          other.target == target &&
          other.unit == unit &&
          other.status == status;

  @override
  int get hashCode =>
      Object.hash(id, name, icon, color, progress, target, unit, status);

  @override
  String toString() => 'FriendHabit($id, $name, ${status.wire})';
}
