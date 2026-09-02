import 'package:flutter/material.dart';

import 'json.dart';

/// `nudge` = "go do this"; `cheer` = "well done".
enum NudgeType {
  nudge('nudge'),
  cheer('cheer');

  const NudgeType(this.wire);

  /// Spelling used on the wire, per the contract.
  final String wire;

  static const Map<String, NudgeType> _byWire = <String, NudgeType>{
    'nudge': NudgeType.nudge,
    'cheer': NudgeType.cheer,
  };

  /// Unknown spellings degrade to [NudgeType.nudge] rather than throwing.
  static NudgeType parse(Object? value) =>
      asEnum(value, _byWire, NudgeType.nudge);
}

/// Lifecycle of a nudge. The contract only defines `pending` and `accepted`.
enum NudgeStatus {
  pending('pending'),
  accepted('accepted');

  const NudgeStatus(this.wire);

  final String wire;

  static const Map<String, NudgeStatus> _byWire = <String, NudgeStatus>{
    'pending': NudgeStatus.pending,
    'accepted': NudgeStatus.accepted,
  };

  static NudgeStatus parse(Object? value) =>
      asEnum(value, _byWire, NudgeStatus.pending);
}

/// A nudge or cheer (`GET /api/nudges`, `POST /api/nudges`).
///
/// `fromFriendName` and `isAccepted` are kept as getters (and as constructor
/// aliases) so `NudgeCard` and `FriendsScreen` compile against the renamed
/// contract fields.
@immutable
class Nudge {
  final String id;
  final NudgeType type;

  /// Sender. Empty on a payload that predates the field.
  final String fromUserId;
  final String fromUserName;

  /// Recipient — "me" for anything in the `received` list.
  final String toUserId;

  /// Nullable in the contract: a nudge may name a habit the sender does not
  /// have an id for.
  final String? habitId;

  final String habitName;
  final String habitIcon;
  final Color habitColor;

  /// Optional free text, max 140 chars server-side.
  final String? message;

  final NudgeStatus status;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  Nudge({
    required this.id,
    this.type = NudgeType.nudge,
    this.fromUserId = '',
    String? fromUserName,
    String? fromFriendName,
    this.toUserId = '',
    this.habitId,
    required this.habitName,
    required this.habitIcon,
    required this.habitColor,
    this.message,
    NudgeStatus? status,
    bool isAccepted = false,
    DateTime? createdAt,
    DateTime? timestamp,
    this.acceptedAt,
  })  : fromUserName = fromUserName ?? fromFriendName ?? '',
        status = status ??
            (isAccepted ? NudgeStatus.accepted : NudgeStatus.pending),
        createdAt = createdAt ?? timestamp ?? kFallbackDateTime;

  /// Legacy alias for [fromUserName], kept so existing widgets compile.
  String get fromFriendName => fromUserName;

  /// Legacy alias for `status == accepted`.
  bool get isAccepted => status == NudgeStatus.accepted;

  bool get isPending => status == NudgeStatus.pending;

  bool get isCheer => type == NudgeType.cheer;

  /// Legacy alias for [createdAt].
  DateTime get timestamp => createdAt;

  String get timeAgo => relativeTimeLabel(createdAt, justNow: 'Just now');

  factory Nudge.fromJson(Map<String, dynamic> json) => Nudge(
        id: asString(json['id']),
        type: NudgeType.parse(json['type']),
        fromUserId: asString(json['fromUserId']),
        fromUserName: asString(json['fromUserName']),
        toUserId: asString(json['toUserId']),
        habitId: asStringOrNull(json['habitId']),
        habitName: asString(json['habitName']),
        habitIcon: asString(json['habitIcon']),
        habitColor: asColor(json['habitColor']),
        message: asStringOrNull(json['message']),
        status: NudgeStatus.parse(json['status']),
        createdAt: asDateTime(json['createdAt']),
        acceptedAt: asDateTimeOrNull(json['acceptedAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.wire,
        'fromUserId': fromUserId,
        'fromUserName': fromUserName,
        'toUserId': toUserId,
        'habitId': habitId,
        'habitName': habitName,
        'habitIcon': habitIcon,
        'habitColor': colorToHex(habitColor),
        'message': message,
        'status': status.wire,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'acceptedAt': isoOrNull(acceptedAt),
      };

  Nudge copyWith({
    String? id,
    NudgeType? type,
    String? fromUserId,
    String? fromUserName,
    String? toUserId,
    String? habitId,
    String? habitName,
    String? habitIcon,
    Color? habitColor,
    String? message,
    NudgeStatus? status,
    DateTime? createdAt,
    DateTime? acceptedAt,
  }) =>
      Nudge(
        id: id ?? this.id,
        type: type ?? this.type,
        fromUserId: fromUserId ?? this.fromUserId,
        fromUserName: fromUserName ?? this.fromUserName,
        toUserId: toUserId ?? this.toUserId,
        habitId: habitId ?? this.habitId,
        habitName: habitName ?? this.habitName,
        habitIcon: habitIcon ?? this.habitIcon,
        habitColor: habitColor ?? this.habitColor,
        message: message ?? this.message,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        acceptedAt: acceptedAt ?? this.acceptedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Nudge &&
          other.id == id &&
          other.type == type &&
          other.fromUserId == fromUserId &&
          other.fromUserName == fromUserName &&
          other.toUserId == toUserId &&
          other.habitId == habitId &&
          other.habitName == habitName &&
          other.habitIcon == habitIcon &&
          other.habitColor == habitColor &&
          other.message == message &&
          other.status == status &&
          other.createdAt == createdAt &&
          other.acceptedAt == acceptedAt;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        fromUserId,
        fromUserName,
        toUserId,
        habitId,
        habitName,
        habitIcon,
        habitColor,
        message,
        status,
        createdAt,
        acceptedAt,
      );

  @override
  String toString() => 'Nudge($id, ${type.wire}, $habitName, ${status.wire})';
}
