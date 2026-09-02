import 'package:flutter/material.dart';

import 'json.dart';

/// Lifecycle of a friend request.
///
/// `GET /api/friend-requests` only ever returns [pending]; the other values
/// arrive on the response to an accept/decline/cancel.
enum RequestStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  cancelled('cancelled'),

  /// Unrecognised spelling — treated as terminal, never as actionable.
  unknown('unknown');

  const RequestStatus(this.wire);

  final String wire;

  static const Map<String, RequestStatus> _byWire = <String, RequestStatus>{
    'pending': RequestStatus.pending,
    'accepted': RequestStatus.accepted,
    'declined': RequestStatus.declined,
    'cancelled': RequestStatus.cancelled,
  };

  static RequestStatus parse(Object? value) =>
      asEnum(value, _byWire, RequestStatus.unknown);

  bool get isPending => this == RequestStatus.pending;
}

/// The trimmed user shape embedded in a [FriendRequest] (`fromUser`/`toUser`).
///
/// Deliberately not [UserProfile]: the contract's request payload carries no
/// `createdAt` and no `email`, and modelling it separately keeps a request
/// from ever being mistaken for a full account record.
@immutable
class UserRef {
  final String id;
  final String username;
  final String name;
  final Color avatarColor;

  const UserRef({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarColor,
  });

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  String get handle => username.isEmpty ? '' : '@$username';

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
        id: asString(json['id']),
        username: asString(json['username']),
        name: asString(json['name']),
        avatarColor: asColor(json['avatarColor']),
      );

  /// Tolerates a missing `fromUser`/`toUser` object entirely.
  factory UserRef.fromDynamic(Object? value) =>
      UserRef.fromJson(asMap(value));

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'name': name,
        'avatarColor': colorToHex(avatarColor),
      };

  UserRef copyWith({
    String? id,
    String? username,
    String? name,
    Color? avatarColor,
  }) =>
      UserRef(
        id: id ?? this.id,
        username: username ?? this.username,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserRef &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarColor == avatarColor;

  @override
  int get hashCode => Object.hash(id, username, name, avatarColor);

  @override
  String toString() => 'UserRef($id, @$username)';
}

/// A pending or resolved friend request (`GET /api/friend-requests`).
@immutable
class FriendRequest {
  final String id;
  final UserRef fromUser;
  final UserRef toUser;
  final RequestStatus status;
  final int mutualFriends;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const FriendRequest({
    required this.id,
    required this.fromUser,
    required this.toUser,
    this.status = RequestStatus.pending,
    this.mutualFriends = 0,
    required this.createdAt,
    this.respondedAt,
  });

  bool get isPending => status.isPending;

  /// Whether [meId] is the recipient — i.e. this belongs in the *incoming*
  /// list and may be accepted or declined (never cancelled).
  bool isIncomingFor(String meId) => toUser.id == meId;

  /// The party that is not [meId]. Falls back to [fromUser] when [meId]
  /// matches neither side.
  UserRef counterpartFor(String meId) =>
      fromUser.id == meId ? toUser : fromUser;

  String get mutualLabel => mutualFriends <= 0
      ? ''
      : '$mutualFriends mutual friend${mutualFriends == 1 ? '' : 's'}';

  String get timeAgo => relativeTimeLabel(createdAt);

  factory FriendRequest.fromJson(Map<String, dynamic> json) => FriendRequest(
        id: asString(json['id']),
        fromUser: UserRef.fromDynamic(json['fromUser']),
        toUser: UserRef.fromDynamic(json['toUser']),
        status: RequestStatus.parse(json['status']),
        mutualFriends: asInt(json['mutualFriends']),
        createdAt: asDateTime(json['createdAt']),
        respondedAt: asDateTimeOrNull(json['respondedAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'fromUser': fromUser.toJson(),
        'toUser': toUser.toJson(),
        'status': status.wire,
        'mutualFriends': mutualFriends,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'respondedAt': isoOrNull(respondedAt),
      };

  FriendRequest copyWith({
    String? id,
    UserRef? fromUser,
    UserRef? toUser,
    RequestStatus? status,
    int? mutualFriends,
    DateTime? createdAt,
    DateTime? respondedAt,
  }) =>
      FriendRequest(
        id: id ?? this.id,
        fromUser: fromUser ?? this.fromUser,
        toUser: toUser ?? this.toUser,
        status: status ?? this.status,
        mutualFriends: mutualFriends ?? this.mutualFriends,
        createdAt: createdAt ?? this.createdAt,
        respondedAt: respondedAt ?? this.respondedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendRequest &&
          other.id == id &&
          other.fromUser == fromUser &&
          other.toUser == toUser &&
          other.status == status &&
          other.mutualFriends == mutualFriends &&
          other.createdAt == createdAt &&
          other.respondedAt == respondedAt;

  @override
  int get hashCode => Object.hash(
        id,
        fromUser,
        toUser,
        status,
        mutualFriends,
        createdAt,
        respondedAt,
      );

  @override
  String toString() =>
      'FriendRequest($id, ${fromUser.id} -> ${toUser.id}, ${status.wire})';
}
