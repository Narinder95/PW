import 'package:flutter/material.dart';

import 'json.dart';

/// How the signed-in user stands relative to a search result.
///
/// [unknown] is the fallback for an unrecognised spelling; the UI should treat
/// it like [none] but must not offer an action it cannot guarantee.
enum Relationship {
  self('self'),
  friend('friend'),
  requestSent('request_sent'),
  requestReceived('request_received'),
  none('none'),
  unknown('unknown');

  const Relationship(this.wire);

  final String wire;

  static const Map<String, Relationship> _byWire = <String, Relationship>{
    'self': Relationship.self,
    'friend': Relationship.friend,
    'request_sent': Relationship.requestSent,
    'request_received': Relationship.requestReceived,
    'none': Relationship.none,
  };

  static Relationship parse(Object? value) =>
      asEnum(value, _byWire, Relationship.unknown);

  /// Whether "Add friend" is a legal action for this row. [unknown] returns
  /// false: better to show nothing than to fire a request that 409s.
  bool get canSendRequest => this == Relationship.none;
}

/// The signed-in user's own account (`GET /api/me`).
///
/// Distinct from [SearchResult] because only this shape carries `email`.
@immutable
class UserProfile {
  final String id;
  final String username;
  final String name;

  /// Only present on `/api/me`. Null until the account is claimed.
  final String? email;

  /// Only present on `/api/me`. Null until the account is claimed.
  final String? phone;

  /// True for an account that was provisioned automatically and has no
  /// credentials yet. It lives only on this device: reinstall the app and it
  /// is gone. Claiming it (email/phone + password) makes it recoverable.
  final bool isAnonymous;

  final Color avatarColor;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    required this.username,
    required this.name,
    this.email,
    this.phone,
    this.isAnonymous = false,
    required this.avatarColor,
    this.createdAt,
  });

  /// Whether the account can be recovered on another device.
  bool get isClaimed => !isAnonymous;

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  /// `@handle` for display.
  String get handle => username.isEmpty ? '' : '@$username';

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: asString(json['id']),
        username: asString(json['username']),
        name: asString(json['name']),
        email: asStringOrNull(json['email']),
        phone: asStringOrNull(json['phone']),
        isAnonymous: asBool(json['isAnonymous']),
        avatarColor: asColor(json['avatarColor']),
        createdAt: asDateTimeOrNull(json['createdAt']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'name': name,
        'email': email,
        'phone': phone,
        'isAnonymous': isAnonymous,
        'avatarColor': colorToHex(avatarColor),
        'createdAt': isoOrNull(createdAt),
      };

  UserProfile copyWith({
    String? id,
    String? username,
    String? name,
    String? email,
    String? phone,
    bool? isAnonymous,
    Color? avatarColor,
    DateTime? createdAt,
  }) =>
      UserProfile(
        id: id ?? this.id,
        username: username ?? this.username,
        name: name ?? this.name,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        isAnonymous: isAnonymous ?? this.isAnonymous,
        avatarColor: avatarColor ?? this.avatarColor,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.email == email &&
          other.phone == phone &&
          other.isAnonymous == isAnonymous &&
          other.avatarColor == avatarColor &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
      id, username, name, email, phone, isAnonymous, avatarColor, createdAt);

  @override
  String toString() => 'UserProfile($id, @$username)';
}

/// A row from `GET /api/users/search` — a public user plus the caller's
/// relationship to them.
@immutable
class SearchResult {
  final String id;
  final String username;
  final String name;
  final Color avatarColor;
  final int mutualFriends;
  final Relationship relationship;

  const SearchResult({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarColor,
    this.mutualFriends = 0,
    this.relationship = Relationship.unknown,
  });

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  String get handle => username.isEmpty ? '' : '@$username';

  /// e.g. "2 mutual friends"; empty when there are none.
  String get mutualLabel => mutualFriends <= 0
      ? ''
      : '$mutualFriends mutual friend${mutualFriends == 1 ? '' : 's'}';

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        id: asString(json['id']),
        username: asString(json['username']),
        name: asString(json['name']),
        avatarColor: asColor(json['avatarColor']),
        mutualFriends: asInt(json['mutualFriends']),
        relationship: Relationship.parse(json['relationship']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'username': username,
        'name': name,
        'avatarColor': colorToHex(avatarColor),
        'mutualFriends': mutualFriends,
        'relationship': relationship.wire,
      };

  SearchResult copyWith({
    String? id,
    String? username,
    String? name,
    Color? avatarColor,
    int? mutualFriends,
    Relationship? relationship,
  }) =>
      SearchResult(
        id: id ?? this.id,
        username: username ?? this.username,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
        mutualFriends: mutualFriends ?? this.mutualFriends,
        relationship: relationship ?? this.relationship,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult &&
          other.id == id &&
          other.username == username &&
          other.name == name &&
          other.avatarColor == avatarColor &&
          other.mutualFriends == mutualFriends &&
          other.relationship == relationship;

  @override
  int get hashCode =>
      Object.hash(id, username, name, avatarColor, mutualFriends, relationship);

  @override
  String toString() =>
      'SearchResult($id, @$username, ${relationship.wire})';
}
