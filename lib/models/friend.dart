import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'json.dart';

/// A friend as returned by `GET /api/friends` (contract: `FriendSummary`).
///
/// `streakColor` is retained as a getter over [avatarColor] so `FriendCard`
/// and `FriendDetailScreen` keep compiling unchanged; the constructor also
/// still accepts a `streakColor:` argument as an alias for `avatarColor:`.
@immutable
class Friend {
  /// Opaque user id. Never assume numeric.
  final String id;

  /// Handle, 3-20 chars of `[a-z0-9_]`. Empty only if the server omitted it.
  final String username;

  final String name;

  /// Avatar tint. Also drives the streak ring — see [streakColor].
  final Color avatarColor;

  final int streakDays;

  /// Documented as a double in `[0,1]`; parsed clamped to that range.
  final double completionPercentage;

  final int habitsCompleted;

  /// May legitimately be `0` for a friend with no habits. Never divide by this
  /// without a guard — see [habitsRatio].
  final int habitsTotal;

  /// Always length 7, oldest first, index 6 = today. Normalised on parse.
  final List<bool> weekData;

  /// Null until the friend has been seen since the field was introduced.
  final DateTime? lastActiveAt;

  const Friend({
    required this.id,
    this.username = '',
    required this.name,
    Color? avatarColor,
    Color? streakColor,
    required this.streakDays,
    required this.completionPercentage,
    this.habitsCompleted = 0,
    this.habitsTotal = 0,
    required this.weekData,
    this.lastActiveAt,
  }) : avatarColor = avatarColor ?? streakColor ?? kFallbackColor;

  /// Legacy alias kept so existing widgets compile. The design only ever had
  /// one per-friend colour; the contract calls it `avatarColor`.
  Color get streakColor => avatarColor;

  /// First initial for the avatar circle. `?` rather than a range error when
  /// the server sends an empty name.
  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  /// Habits done today as a ratio, guarding `habitsTotal == 0`.
  double get habitsRatio => habitsTotal <= 0
      ? 0
      : (habitsCompleted / habitsTotal).clamp(0.0, 1.0).toDouble();

  /// Days in the visible week the friend completed.
  int get weekCompletions => weekData.where((done) => done).length;

  factory Friend.fromJson(Map<String, dynamic> json) => Friend(
        id: asString(json['id']),
        username: asString(json['username']),
        name: asString(json['name']),
        avatarColor: asColor(json['avatarColor']),
        streakDays: asInt(json['streakDays']),
        completionPercentage: asRatio(json['completionPercentage']),
        habitsCompleted: asInt(json['habitsCompleted']),
        habitsTotal: asInt(json['habitsTotal']),
        weekData: asWeekData(json['weekData']),
        lastActiveAt: asDateTimeOrNull(json['lastActiveAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'name': name,
        'avatarColor': colorToHex(avatarColor),
        'streakDays': streakDays,
        'completionPercentage': completionPercentage,
        'habitsCompleted': habitsCompleted,
        'habitsTotal': habitsTotal,
        'weekData': weekData,
        'lastActiveAt': isoOrNull(lastActiveAt),
      };

  Friend copyWith({
    String? id,
    String? username,
    String? name,
    Color? avatarColor,
    int? streakDays,
    double? completionPercentage,
    int? habitsCompleted,
    int? habitsTotal,
    List<bool>? weekData,
    DateTime? lastActiveAt,
  }) =>
      Friend(
        id: id ?? this.id,
        username: username ?? this.username,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
        streakDays: streakDays ?? this.streakDays,
        completionPercentage:
            completionPercentage ?? this.completionPercentage,
        habitsCompleted: habitsCompleted ?? this.habitsCompleted,
        habitsTotal: habitsTotal ?? this.habitsTotal,
        weekData: weekData ?? this.weekData,
        lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Friend &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarColor == avatarColor &&
          other.streakDays == streakDays &&
          other.completionPercentage == completionPercentage &&
          other.habitsCompleted == habitsCompleted &&
          other.habitsTotal == habitsTotal &&
          listEquals(other.weekData, weekData) &&
          other.lastActiveAt == lastActiveAt;

  @override
  int get hashCode => Object.hash(
        id,
        username,
        name,
        avatarColor,
        streakDays,
        completionPercentage,
        habitsCompleted,
        habitsTotal,
        Object.hashAll(weekData),
        lastActiveAt,
      );

  @override
  String toString() => 'Friend($id, $name, streak $streakDays)';
}
