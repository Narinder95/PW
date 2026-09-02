import 'package:flutter/material.dart';

import 'json.dart';

/// Kinds of notification the server emits.
///
/// [unknown] exists so a server that ships a new type before the client does
/// renders a generic row instead of crashing the notification list. Never
/// `switch` on this without a default arm.
enum NotificationType {
  friendRequest('friend_request'),
  friendRequestAccepted('friend_request_accepted'),
  nudge('nudge'),
  cheer('cheer'),
  nudgeAccepted('nudge_accepted'),
  friendActivity('friend_activity'),
  streakMilestone('streak_milestone'),
  matchSuggestion('match_suggestion'),

  /// Anything the client does not recognise.
  unknown('unknown');

  const NotificationType(this.wire);

  final String wire;

  static const Map<String, NotificationType> _byWire =
      <String, NotificationType>{
    'friend_request': NotificationType.friendRequest,
    'friend_request_accepted': NotificationType.friendRequestAccepted,
    'nudge': NotificationType.nudge,
    'cheer': NotificationType.cheer,
    'nudge_accepted': NotificationType.nudgeAccepted,
    'friend_activity': NotificationType.friendActivity,
    'streak_milestone': NotificationType.streakMilestone,
    'match_suggestion': NotificationType.matchSuggestion,
  };

  static NotificationType parse(Object? value) =>
      asEnum(value, _byWire, NotificationType.unknown);

  /// Material icon used when the server sends no `icon` emoji.
  IconData get fallbackIcon {
    switch (this) {
      case NotificationType.friendRequest:
        return Icons.person_add_alt_1_outlined;
      case NotificationType.friendRequestAccepted:
        return Icons.how_to_reg_outlined;
      case NotificationType.nudge:
        return Icons.waving_hand_outlined;
      case NotificationType.cheer:
        return Icons.celebration_outlined;
      case NotificationType.nudgeAccepted:
        return Icons.task_alt_outlined;
      case NotificationType.friendActivity:
        return Icons.bolt_outlined;
      case NotificationType.streakMilestone:
        return Icons.local_fire_department_outlined;
      case NotificationType.matchSuggestion:
        return Icons.group_add_outlined;
      case NotificationType.unknown:
        return Icons.notifications_none_outlined;
    }
  }

  /// Accent used when the server sends no `color`.
  Color get fallbackColor {
    switch (this) {
      case NotificationType.friendRequest:
      case NotificationType.friendRequestAccepted:
      case NotificationType.matchSuggestion:
        return const Color(0xFF2DD4BF);
      case NotificationType.nudge:
      case NotificationType.nudgeAccepted:
        return const Color(0xFFA855F7);
      case NotificationType.cheer:
      case NotificationType.streakMilestone:
        return const Color(0xFFFB923C);
      case NotificationType.friendActivity:
        return const Color(0xFF4ADE80);
      case NotificationType.unknown:
        return kFallbackColor;
    }
  }
}

/// What [AppNotification.refId] points at, so the UI can deep-link.
enum RefType {
  nudge('nudge'),
  friendRequest('friend_request'),
  user('user'),
  activity('activity'),
  habit('habit'),

  /// Explicitly null in the payload, or a target this client cannot route to.
  none('none');

  const RefType(this.wire);

  final String wire;

  static const Map<String, RefType> _byWire = <String, RefType>{
    'nudge': RefType.nudge,
    'friend_request': RefType.friendRequest,
    'user': RefType.user,
    'activity': RefType.activity,
    'habit': RefType.habit,
  };

  static RefType parse(Object? value) => asEnum(value, _byWire, RefType.none);
}

/// A row in the notification centre (`GET /api/notifications`), and the
/// payload of an `event: notification` SSE frame.
///
/// The contract says `actorId`, `actorName`, `avatarColor`, `icon`, `color`,
/// `refId` and `refType` are **all** nullable and that a notification must
/// render with every one of them null. This class holds them nullable and
/// offers [resolvedIcon] / [resolvedColor] so the UI never has to branch.
@immutable
class AppNotification {
  final String id;
  final NotificationType type;
  final String title;
  final String body;

  final String? actorId;
  final String? actorName;
  final Color? avatarColor;

  /// Emoji supplied by the server. Null -> use [fallbackIcon].
  final String? icon;

  final Color? color;

  final RefType refType;
  final String? refId;

  final bool read;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.actorId,
    this.actorName,
    this.avatarColor,
    this.icon,
    this.color,
    this.refType = RefType.none,
    this.refId,
    this.read = false,
    required this.createdAt,
  });

  /// True when [refType]/[refId] together identify something routable.
  bool get isDeepLinkable => refType != RefType.none && refId != null;

  /// Emoji to draw, or null if the UI should fall back to [fallbackIcon].
  String? get emoji => (icon != null && icon!.isNotEmpty) ? icon : null;

  /// Material icon to draw when [emoji] is null.
  IconData get fallbackIcon => type.fallbackIcon;

  /// Accent for the row, never null.
  Color get resolvedColor => color ?? avatarColor ?? type.fallbackColor;

  /// Avatar tint for the actor bubble, never null.
  Color get resolvedAvatarColor => avatarColor ?? resolvedColor;

  /// Initial for the actor bubble; `?` when the actor is unknown.
  String get actorInitial {
    final name = actorName?.trim() ?? '';
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  String get timeAgo => relativeTimeLabel(createdAt);

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: asString(json['id']),
        type: NotificationType.parse(json['type']),
        title: asString(json['title']),
        body: asString(json['body']),
        actorId: asStringOrNull(json['actorId']),
        actorName: asStringOrNull(json['actorName']),
        avatarColor: asColorOrNull(json['avatarColor']),
        icon: asStringOrNull(json['icon']),
        color: asColorOrNull(json['color']),
        refType: RefType.parse(json['refType']),
        refId: asStringOrNull(json['refId']),
        read: asBool(json['read']),
        createdAt: asDateTime(json['createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.wire,
        'title': title,
        'body': body,
        'actorId': actorId,
        'actorName': actorName,
        'avatarColor': avatarColor == null ? null : colorToHex(avatarColor!),
        'icon': icon,
        'color': color == null ? null : colorToHex(color!),
        'refType': refType == RefType.none ? null : refType.wire,
        'refId': refId,
        'read': read,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  AppNotification copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    String? actorId,
    String? actorName,
    Color? avatarColor,
    String? icon,
    Color? color,
    RefType? refType,
    String? refId,
    bool? read,
    DateTime? createdAt,
  }) =>
      AppNotification(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        body: body ?? this.body,
        actorId: actorId ?? this.actorId,
        actorName: actorName ?? this.actorName,
        avatarColor: avatarColor ?? this.avatarColor,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        refType: refType ?? this.refType,
        refId: refId ?? this.refId,
        read: read ?? this.read,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          other.id == id &&
          other.type == type &&
          other.title == title &&
          other.body == body &&
          other.actorId == actorId &&
          other.actorName == actorName &&
          other.avatarColor == avatarColor &&
          other.icon == icon &&
          other.color == color &&
          other.refType == refType &&
          other.refId == refId &&
          other.read == read &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        title,
        body,
        actorId,
        actorName,
        avatarColor,
        icon,
        color,
        refType,
        refId,
        read,
        createdAt,
      );

  @override
  String toString() =>
      'AppNotification($id, ${type.wire}, read: $read, "$title")';
}
