import 'package:flutter/material.dart';

import 'json.dart';

/// One row of the friends activity feed (`GET /api/activity`).
///
/// The contract names the timestamp `createdAt`; [timestamp] is kept as a
/// getter (and as a constructor alias) so `ActivityCard` compiles unchanged.
@immutable
class FriendActivity {
  final String id;

  /// Who did it — needed to deep-link the row to a friend detail screen.
  final String friendId;

  final String friendName;

  /// The friend's avatar tint. Distinct from [habitColor]: the row shows the
  /// person on the left and the habit on the right.
  final Color avatarColor;

  final String habitName;
  final String habitIcon;
  final Color habitColor;

  /// Server-rendered completion blurb, e.g. `"5/5 km"`.
  final String completion;

  final DateTime createdAt;

  FriendActivity({
    required this.id,
    this.friendId = '',
    required this.friendName,
    Color? avatarColor,
    required this.habitName,
    required this.habitIcon,
    required this.habitColor,
    required this.completion,
    DateTime? createdAt,
    DateTime? timestamp,
  })  : avatarColor = avatarColor ?? habitColor,
        createdAt = createdAt ?? timestamp ?? kFallbackDateTime;

  /// Legacy alias for [createdAt], kept so existing widgets compile.
  DateTime get timestamp => createdAt;

  String get timeAgo => relativeTimeLabel(createdAt);

  String get initial =>
      friendName.trim().isEmpty ? '?' : friendName.trim()[0].toUpperCase();

  factory FriendActivity.fromJson(Map<String, dynamic> json) {
    final habitColor = asColor(json['habitColor']);
    return FriendActivity(
      id: asString(json['id']),
      friendId: asString(json['friendId']),
      friendName: asString(json['friendName']),
      // Falls back to the habit colour rather than to grey: an activity row
      // with no avatar tint still reads as belonging to that habit.
      avatarColor: asColor(json['avatarColor'], habitColor),
      habitName: asString(json['habitName']),
      habitIcon: asString(json['habitIcon']),
      habitColor: habitColor,
      completion: asString(json['completion']),
      createdAt: asDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'friendId': friendId,
        'friendName': friendName,
        'avatarColor': colorToHex(avatarColor),
        'habitName': habitName,
        'habitIcon': habitIcon,
        'habitColor': colorToHex(habitColor),
        'completion': completion,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  FriendActivity copyWith({
    String? id,
    String? friendId,
    String? friendName,
    Color? avatarColor,
    String? habitName,
    String? habitIcon,
    Color? habitColor,
    String? completion,
    DateTime? createdAt,
  }) =>
      FriendActivity(
        id: id ?? this.id,
        friendId: friendId ?? this.friendId,
        friendName: friendName ?? this.friendName,
        avatarColor: avatarColor ?? this.avatarColor,
        habitName: habitName ?? this.habitName,
        habitIcon: habitIcon ?? this.habitIcon,
        habitColor: habitColor ?? this.habitColor,
        completion: completion ?? this.completion,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendActivity &&
          other.id == id &&
          other.friendId == friendId &&
          other.friendName == friendName &&
          other.avatarColor == avatarColor &&
          other.habitName == habitName &&
          other.habitIcon == habitIcon &&
          other.habitColor == habitColor &&
          other.completion == completion &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        friendId,
        friendName,
        avatarColor,
        habitName,
        habitIcon,
        habitColor,
        completion,
        createdAt,
      );

  @override
  String toString() => 'FriendActivity($id, $friendName, $habitName)';
}
