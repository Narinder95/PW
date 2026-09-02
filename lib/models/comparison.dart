import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'json.dart';

/// Who won a single compared habit, on completion ratio (clamped to 1).
enum Winner {
  me('me'),
  friend('friend'),
  tie('tie');

  const Winner(this.wire);

  final String wire;

  static const Map<String, Winner> _byWire = <String, Winner>{
    'me': Winner.me,
    'friend': Winner.friend,
    'tie': Winner.tie,
  };

  /// Unknown spellings degrade to [tie] — neutral, and never awards a win to
  /// the wrong person.
  static Winner parse(Object? value) => asEnum(value, _byWire, Winner.tie);
}

/// Who is ahead overall, on habit-win count.
enum Verdict {
  meAhead('me_ahead'),
  friendAhead('friend_ahead'),
  tie('tie');

  const Verdict(this.wire);

  final String wire;

  static const Map<String, Verdict> _byWire = <String, Verdict>{
    'me_ahead': Verdict.meAhead,
    'friend_ahead': Verdict.friendAhead,
    'tie': Verdict.tie,
  };

  static Verdict parse(Object? value) => asEnum(value, _byWire, Verdict.tie);
}

/// One side of a comparison — the `me` or `friend` object.
@immutable
class ComparisonSide {
  final String id;
  final String name;
  final Color avatarColor;

  /// Number of habit wins.
  final int score;

  final int streakDays;

  const ComparisonSide({
    required this.id,
    required this.name,
    required this.avatarColor,
    this.score = 0,
    this.streakDays = 0,
  });

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  factory ComparisonSide.fromJson(Map<String, dynamic> json) => ComparisonSide(
        id: asString(json['id']),
        name: asString(json['name']),
        avatarColor: asColor(json['avatarColor']),
        score: asInt(json['score']),
        streakDays: asInt(json['streakDays']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatarColor': colorToHex(avatarColor),
        'score': score,
        'streakDays': streakDays,
      };

  ComparisonSide copyWith({
    String? id,
    String? name,
    Color? avatarColor,
    int? score,
    int? streakDays,
  }) =>
      ComparisonSide(
        id: id ?? this.id,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
        score: score ?? this.score,
        streakDays: streakDays ?? this.streakDays,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComparisonSide &&
          other.id == id &&
          other.name == name &&
          other.avatarColor == avatarColor &&
          other.score == score &&
          other.streakDays == streakDays;

  @override
  int get hashCode => Object.hash(id, name, avatarColor, score, streakDays);

  @override
  String toString() => 'ComparisonSide($id, $name, score $score)';
}

/// One habit both users have, with each side's progress against their own
/// target. Targets can differ — never assume `myTarget == friendTarget`.
@immutable
class HabitComparison {
  final String name;
  final String icon;
  final Color color;
  final int myProgress;
  final int myTarget;
  final int friendProgress;
  final int friendTarget;
  final String unit;
  final Winner winner;

  const HabitComparison({
    required this.name,
    required this.icon,
    required this.color,
    required this.myProgress,
    required this.myTarget,
    required this.friendProgress,
    required this.friendTarget,
    required this.unit,
    this.winner = Winner.tie,
  });

  /// My completion ratio, guarding a zero/negative target.
  double get myRatio => myTarget <= 0
      ? 0
      : (myProgress / myTarget).clamp(0.0, 1.0).toDouble();

  /// The friend's completion ratio, guarding a zero/negative target.
  double get friendRatio => friendTarget <= 0
      ? 0
      : (friendProgress / friendTarget).clamp(0.0, 1.0).toDouble();

  bool get iWon => winner == Winner.me;
  bool get friendWon => winner == Winner.friend;

  factory HabitComparison.fromJson(Map<String, dynamic> json) =>
      HabitComparison(
        name: asString(json['name']),
        icon: asString(json['icon']),
        color: asColor(json['color']),
        myProgress: asInt(json['myProgress']),
        myTarget: asInt(json['myTarget']),
        friendProgress: asInt(json['friendProgress']),
        friendTarget: asInt(json['friendTarget']),
        unit: asString(json['unit']),
        winner: Winner.parse(json['winner']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'icon': icon,
        'color': colorToHex(color),
        'myProgress': myProgress,
        'myTarget': myTarget,
        'friendProgress': friendProgress,
        'friendTarget': friendTarget,
        'unit': unit,
        'winner': winner.wire,
      };

  HabitComparison copyWith({
    String? name,
    String? icon,
    Color? color,
    int? myProgress,
    int? myTarget,
    int? friendProgress,
    int? friendTarget,
    String? unit,
    Winner? winner,
  }) =>
      HabitComparison(
        name: name ?? this.name,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        myProgress: myProgress ?? this.myProgress,
        myTarget: myTarget ?? this.myTarget,
        friendProgress: friendProgress ?? this.friendProgress,
        friendTarget: friendTarget ?? this.friendTarget,
        unit: unit ?? this.unit,
        winner: winner ?? this.winner,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HabitComparison &&
          other.name == name &&
          other.icon == icon &&
          other.color == color &&
          other.myProgress == myProgress &&
          other.myTarget == myTarget &&
          other.friendProgress == friendProgress &&
          other.friendTarget == friendTarget &&
          other.unit == unit &&
          other.winner == winner;

  @override
  int get hashCode => Object.hash(
        name,
        icon,
        color,
        myProgress,
        myTarget,
        friendProgress,
        friendTarget,
        unit,
        winner,
      );

  @override
  String toString() => 'HabitComparison($name, ${winner.wire})';
}

/// The full payload of `GET /api/friends/:id/compare`.
///
/// With no shared habits the server sends `habits: []`, both scores `0` and
/// `verdict: "tie"` — [hasSharedHabits] is the flag to branch the empty state
/// on, not `habits.isEmpty` plus a guess.
@immutable
class FriendComparison {
  final ComparisonSide me;
  final ComparisonSide friend;
  final List<HabitComparison> habits;

  /// Server-computed count of shared habits. Normally `habits.length`, but
  /// trusted over it so a truncated list cannot misreport the total.
  final int sharedHabitCount;

  final Verdict verdict;

  const FriendComparison({
    required this.me,
    required this.friend,
    this.habits = const <HabitComparison>[],
    this.sharedHabitCount = 0,
    this.verdict = Verdict.tie,
  });

  bool get hasSharedHabits => habits.isNotEmpty;

  bool get isTie => verdict == Verdict.tie;

  /// One-line summary for the header, using the friend's real name.
  String get verdictLabel {
    switch (verdict) {
      case Verdict.meAhead:
        return "You're ahead";
      case Verdict.friendAhead:
        return '${friend.name} is ahead';
      case Verdict.tie:
        return hasSharedHabits ? 'Dead even' : 'No shared habits yet';
    }
  }

  /// Unwraps `{"comparison": {...}}` as well as a bare comparison object, so
  /// the same parser works on the endpoint envelope and on a nested copy.
  factory FriendComparison.fromJson(Map<String, dynamic> json) {
    final root = json.containsKey('comparison') ? asMap(json['comparison']) : json;
    return FriendComparison(
      me: ComparisonSide.fromJson(asMap(root['me'])),
      friend: ComparisonSide.fromJson(asMap(root['friend'])),
      habits: asModelList(root['habits'], HabitComparison.fromJson),
      sharedHabitCount: asInt(root['sharedHabitCount']),
      verdict: Verdict.parse(root['verdict']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'me': me.toJson(),
        'friend': friend.toJson(),
        'habits': habits.map((h) => h.toJson()).toList(),
        'sharedHabitCount': sharedHabitCount,
        'verdict': verdict.wire,
      };

  FriendComparison copyWith({
    ComparisonSide? me,
    ComparisonSide? friend,
    List<HabitComparison>? habits,
    int? sharedHabitCount,
    Verdict? verdict,
  }) =>
      FriendComparison(
        me: me ?? this.me,
        friend: friend ?? this.friend,
        habits: habits ?? this.habits,
        sharedHabitCount: sharedHabitCount ?? this.sharedHabitCount,
        verdict: verdict ?? this.verdict,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FriendComparison &&
          other.me == me &&
          other.friend == friend &&
          listEquals(other.habits, habits) &&
          other.sharedHabitCount == sharedHabitCount &&
          other.verdict == verdict;

  @override
  int get hashCode => Object.hash(
        me,
        friend,
        Object.hashAll(habits),
        sharedHabitCount,
        verdict,
      );

  @override
  String toString() =>
      'FriendComparison(${me.id} vs ${friend.id}, ${verdict.wire})';
}
