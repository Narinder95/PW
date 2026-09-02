import 'package:flutter/foundation.dart';

import 'json.dart';
import 'user_profile.dart';

/// A discovery suggestion from `GET /api/match/suggestions`.
///
/// The server guarantees the ranking is deterministic (no randomness), so the
/// client never re-sorts: showing a different order than the server computed
/// would make "why is this person suggested" unanswerable.
@immutable
class MatchSuggestion {
  /// The suggested user, in the same shape as a search result — so an "Add"
  /// button can read [SearchResult.relationship] without a second lookup.
  final SearchResult user;

  /// Names of habits both users have (case-insensitive, trimmed match).
  final List<String> sharedHabits;

  /// Integer 0-100: `min(100, shared*20 + mutual*15 + streakAffinity)`.
  final int matchScore;

  /// Server-rendered explanation, e.g.
  /// "3 habits in common - 2 mutual friends".
  final String reason;

  const MatchSuggestion({
    required this.user,
    this.sharedHabits = const <String>[],
    this.matchScore = 0,
    this.reason = '',
  });

  int get sharedHabitCount => sharedHabits.length;

  /// [matchScore] as a `[0,1]` ratio, for a progress ring.
  double get scoreRatio => (matchScore / 100).clamp(0.0, 1.0).toDouble();

  factory MatchSuggestion.fromJson(Map<String, dynamic> json) =>
      MatchSuggestion(
        user: SearchResult.fromJson(asMap(json['user'])),
        sharedHabits: asStringList(json['sharedHabits']),
        // Clamped: the contract says 0-100, and a rogue 4000 would blow out
        // any ring or bar drawn from it.
        matchScore: asInt(json['matchScore']).clamp(0, 100),
        reason: asString(json['reason']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'user': user.toJson(),
        'sharedHabits': sharedHabits,
        'matchScore': matchScore,
        'reason': reason,
      };

  MatchSuggestion copyWith({
    SearchResult? user,
    List<String>? sharedHabits,
    int? matchScore,
    String? reason,
  }) =>
      MatchSuggestion(
        user: user ?? this.user,
        sharedHabits: sharedHabits ?? this.sharedHabits,
        matchScore: matchScore ?? this.matchScore,
        reason: reason ?? this.reason,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchSuggestion &&
          other.user == user &&
          listEquals(other.sharedHabits, sharedHabits) &&
          other.matchScore == matchScore &&
          other.reason == reason;

  @override
  int get hashCode =>
      Object.hash(user, Object.hashAll(sharedHabits), matchScore, reason);

  @override
  String toString() => 'MatchSuggestion(${user.id}, score $matchScore)';
}
