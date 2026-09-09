import 'dart:async';

import 'package:flutter/material.dart';

import '../models/comparison.dart';
import '../models/friend.dart';
import '../models/friend_activity.dart';
import '../models/friend_request.dart';
import '../models/match_suggestion.dart';
import '../models/nudge.dart';
import '../models/user_profile.dart';
import 'api/api_exception.dart';
import 'api/pw_api.dart';

/// Caches everything the Friends tab shows, and keeps that cache coherent
/// across mutations.
///
/// The coherence rule: a successful mutation updates every cache it affects,
/// in memory, without a refetch. Accepting a request inserts the new friend
/// *and* drops the request; removing a friend drops them from the list. A
/// screen that just calls `loadAll()` again would work, but it would flash an
/// empty state and cost a round trip per tap.
class FriendsRepository extends ChangeNotifier {
  final PwApi api;

  FriendsRepository({required this.api});

  // ------------------------------------------------------------------ caches

  List<Friend> _friends = const <Friend>[];
  List<FriendActivity> _activity = const <FriendActivity>[];
  List<Nudge> _receivedNudges = const <Nudge>[];
  List<Nudge> _sentNudges = const <Nudge>[];
  List<FriendRequest> _incomingRequests = const <FriendRequest>[];
  List<FriendRequest> _outgoingRequests = const <FriendRequest>[];
  List<MatchSuggestion> _suggestions = const <MatchSuggestion>[];

  /// Per-friend habit detail, keyed by friend id. Populated lazily by
  /// [loadFriendDetail] so opening a friend twice does not refetch.
  final Map<String, FriendDetail> _details = <String, FriendDetail>{};

  bool _loadingFriends = false;
  bool _loadingActivity = false;
  bool _loadingNudges = false;
  bool _loadingRequests = false;
  bool _loadingSuggestions = false;
  bool _disposed = false;

  ApiException? _lastError;

  List<Friend> get friends => List<Friend>.unmodifiable(_friends);
  List<FriendActivity> get activity =>
      List<FriendActivity>.unmodifiable(_activity);
  List<Nudge> get receivedNudges => List<Nudge>.unmodifiable(_receivedNudges);
  List<Nudge> get sentNudges => List<Nudge>.unmodifiable(_sentNudges);
  List<FriendRequest> get incomingRequests =>
      List<FriendRequest>.unmodifiable(_incomingRequests);
  List<FriendRequest> get outgoingRequests =>
      List<FriendRequest>.unmodifiable(_outgoingRequests);
  List<MatchSuggestion> get suggestions =>
      List<MatchSuggestion>.unmodifiable(_suggestions);

  bool get isLoadingFriends => _loadingFriends;
  bool get isLoadingActivity => _loadingActivity;
  bool get isLoadingNudges => _loadingNudges;
  bool get isLoadingRequests => _loadingRequests;
  bool get isLoadingSuggestions => _loadingSuggestions;

  /// True while any section is in flight.
  bool get isLoading =>
      _loadingFriends ||
      _loadingActivity ||
      _loadingNudges ||
      _loadingRequests ||
      _loadingSuggestions;

  /// Most recent failure, for an error state. Cleared by the next success.
  ApiException? get lastError => _lastError;

  /// Badge count for the Friends tab: pending nudges plus incoming requests.
  int get actionableCount => _receivedNudges.length + _incomingRequests.length;

  /// Cached detail for [friendId], or null if it has not been loaded.
  FriendDetail? detailFor(String friendId) => _details[friendId];

  /// Cached friend record by id, or null.
  Friend? friendById(String friendId) {
    for (final friend in _friends) {
      if (friend.id == friendId) return friend;
    }
    return null;
  }

  bool isFriend(String userId) => friendById(userId) != null;

  // ------------------------------------------------------------------- loads

  /// Loads every section the Friends tab needs, concurrently.
  ///
  /// Individual failures are absorbed into [lastError] rather than propagated,
  /// so one dead endpoint does not blank the whole tab.
  Future<void> loadAll() async {
    await Future.wait<void>(<Future<void>>[
      loadFriends(),
      loadActivity(),
      loadNudges(),
      loadRequests(),
    ]);
  }

  /// `GET /api/friends`. Server order (streak desc, name asc) is preserved.
  Future<void> loadFriends() async {
    if (_disposed) return;
    _loadingFriends = true;
    _notify();
    try {
      final result = await api.getFriends();
      if (_disposed) return;
      _friends = List<Friend>.unmodifiable(result);
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _loadingFriends = false;
      _notify();
    }
  }

  /// `GET /api/activity`. Pass [before] for the next page.
  Future<void> loadActivity({int? limit, DateTime? before}) async {
    if (_disposed) return;
    _loadingActivity = true;
    _notify();
    try {
      final result = await api.getActivity(limit: limit, before: before);
      if (_disposed) return;
      if (before == null) {
        _activity = List<FriendActivity>.unmodifiable(result);
      } else {
        // Paging: append, de-duplicating on id in case the cursor overlaps.
        final seen = _activity.map((a) => a.id).toSet();
        _activity = List<FriendActivity>.unmodifiable(<FriendActivity>[
          ..._activity,
          ...result.where((a) => !seen.contains(a.id)),
        ]);
      }
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _loadingActivity = false;
      _notify();
    }
  }

  /// Fetches the next page of activity using the oldest cached row as cursor.
  Future<void> loadMoreActivity({int? limit}) {
    if (_activity.isEmpty) return loadActivity(limit: limit);
    return loadActivity(limit: limit, before: _activity.last.createdAt);
  }

  /// `GET /api/nudges` -> received (pending) and sent.
  Future<void> loadNudges() async {
    if (_disposed) return;
    _loadingNudges = true;
    _notify();
    try {
      final inbox = await api.getNudges();
      if (_disposed) return;
      _receivedNudges = List<Nudge>.unmodifiable(inbox.received);
      _sentNudges = List<Nudge>.unmodifiable(inbox.sent);
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _loadingNudges = false;
      _notify();
    }
  }

  /// `GET /api/friend-requests` -> incoming and outgoing (pending only).
  Future<void> loadRequests() async {
    if (_disposed) return;
    _loadingRequests = true;
    _notify();
    try {
      final inbox = await api.getFriendRequests();
      if (_disposed) return;
      _incomingRequests = List<FriendRequest>.unmodifiable(inbox.incoming);
      _outgoingRequests = List<FriendRequest>.unmodifiable(inbox.outgoing);
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _loadingRequests = false;
      _notify();
    }
  }

  /// `GET /api/match/suggestions`. Server ranking is preserved.
  Future<void> loadSuggestions({int? limit}) async {
    if (_disposed) return;
    _loadingSuggestions = true;
    _notify();
    try {
      final result = await api.matchSuggestions(limit: limit);
      if (_disposed) return;
      _suggestions = List<MatchSuggestion>.unmodifiable(result);
      _lastError = null;
    } on ApiException catch (error) {
      _lastError = error;
    } finally {
      _loadingSuggestions = false;
      _notify();
    }
  }

  /// `GET /api/friends/:id` -> the friend plus their habits, cached.
  ///
  /// Set [force] to bypass the cache after a pull-to-refresh. Throws
  /// [ApiException] — the detail screen has a real error state to show, unlike
  /// the list sections.
  Future<FriendDetail> loadFriendDetail(
    String friendId, {
    bool force = false,
  }) async {
    final cached = _details[friendId];
    if (cached != null && !force) return cached;

    final detail = await api.getFriend(friendId);
    if (_disposed) return detail;

    _details[friendId] = detail;
    // The summary in the detail response is fresher than the list's copy.
    _replaceFriend(detail.friend);
    _notify();
    return detail;
  }

  /// `GET /api/friends/:id/compare`. Not cached: it is a live head-to-head,
  /// and a stale one is worse than a spinner.
  Future<FriendComparison> compareWith(String friendId) =>
      api.compareWithFriend(friendId);

  /// `GET /api/users/search`. Not cached — results are query-scoped.
  Future<List<SearchResult>> searchUsers(String query, {int? limit}) =>
      api.searchUsers(query, limit: limit);

  // --------------------------------------------------------------- mutations

  /// `DELETE /api/friends/:id`. Drops the friend, their cached detail, and
  /// their rows from the activity feed.
  Future<void> removeFriend(String friendId) async {
    await api.removeFriend(friendId);
    if (_disposed) return;

    _friends = List<Friend>.unmodifiable(
      _friends.where((f) => f.id != friendId),
    );
    _details.remove(friendId);
    // Their activity is no longer visible to us — the server would stop
    // returning it on the next load, so drop it now rather than showing rows
    // for someone who is no longer a friend.
    _activity = List<FriendActivity>.unmodifiable(
      _activity.where((a) => a.friendId != friendId),
    );
    _suggestions = List<MatchSuggestion>.unmodifiable(
      _suggestions.where((s) => s.user.id != friendId),
    );
    _notify();
  }

  /// `POST /api/friend-requests`.
  ///
  /// Handles both outcomes: a normal pending request lands in
  /// [outgoingRequests], while an auto-accept (the target had already
  /// requested you) inserts the friend and clears the matching incoming
  /// request instead.
  Future<SendRequestResult> sendFriendRequest(String toUserId) async {
    final result = await api.sendFriendRequest(toUserId);
    if (_disposed) return result;

    if (result.autoAccepted) {
      final friend = result.friend;
      if (friend != null) _insertFriend(friend);
      // Their pending request to us has been consumed by the auto-accept.
      _incomingRequests = List<FriendRequest>.unmodifiable(
        _incomingRequests.where((r) => r.fromUser.id != toUserId),
      );
      _dropSuggestion(toUserId);
    } else {
      final request = result.request;
      if (request != null) {
        _outgoingRequests = List<FriendRequest>.unmodifiable(
          <FriendRequest>[request, ..._outgoingRequests],
        );
      }
      _markSuggestionRelationship(toUserId, Relationship.requestSent);
    }
    _notify();
    return result;
  }

  /// `POST /api/friend-requests/:id/accept`.
  ///
  /// Inserts the new friend and drops the request in one step, so the UI never
  /// shows a request and a friendship for the same person.
  Future<Friend> acceptFriendRequest(String requestId) async {
    final friend = await api.acceptFriendRequest(requestId);
    if (_disposed) return friend;

    _insertFriend(friend);
    _incomingRequests = List<FriendRequest>.unmodifiable(
      _incomingRequests.where((r) => r.id != requestId),
    );
    _dropSuggestion(friend.id);
    _notify();
    return friend;
  }

  /// `POST /api/friend-requests/:id/decline`. Drops it from incoming.
  Future<void> declineFriendRequest(String requestId) async {
    await api.declineFriendRequest(requestId);
    if (_disposed) return;
    _incomingRequests = List<FriendRequest>.unmodifiable(
      _incomingRequests.where((r) => r.id != requestId),
    );
    _notify();
  }

  /// `DELETE /api/friend-requests/:id`. Drops it from outgoing.
  Future<void> cancelFriendRequest(String requestId) async {
    final cancelled = _findRequest(_outgoingRequests, requestId);
    await api.cancelFriendRequest(requestId);
    if (_disposed) return;
    _outgoingRequests = List<FriendRequest>.unmodifiable(
      _outgoingRequests.where((r) => r.id != requestId),
    );
    // The target becomes addable again.
    if (cancelled != null) {
      _markSuggestionRelationship(cancelled.toUser.id, Relationship.none);
    }
    _notify();
  }

  /// `POST /api/nudges`. Prepends to [sentNudges].
  ///
  /// Throws [ApiException] with `isRateLimited` and `retryAfterSeconds` when
  /// the 60-minute per-habit cooldown is still running — the caller should
  /// show that, not a generic failure.
  Future<Nudge> sendNudge({
    required String toUserId,
    required String habitName,
    String? habitId,
    String? habitIcon,
    Color? habitColor,
    NudgeType type = NudgeType.nudge,
    String? message,
  }) async {
    final nudge = await api.sendNudge(
      toUserId: toUserId,
      habitName: habitName,
      habitId: habitId,
      habitIcon: habitIcon,
      habitColor: habitColor,
      type: type,
      message: message,
    );
    if (_disposed) return nudge;

    _sentNudges = List<Nudge>.unmodifiable(<Nudge>[nudge, ..._sentNudges]);
    _notify();
    return nudge;
  }

  /// `POST /api/nudges/:id/accept`.
  ///
  /// Applied optimistically — the card animates out on tap — and rolled back
  /// if the server rejects it. `received` holds pending nudges only, so an
  /// accepted one leaves the list.
  Future<Nudge?> acceptNudge(String nudgeId) async {
    if (_disposed) return null;

    final index = _receivedNudges.indexWhere((n) => n.id == nudgeId);
    if (index < 0) return null;

    final previous = _receivedNudges;
    _receivedNudges = List<Nudge>.unmodifiable(
      _receivedNudges.where((n) => n.id != nudgeId),
    );
    _notify();

    try {
      final accepted = await api.acceptNudge(nudgeId);
      return accepted;
    } on ApiException catch (error) {
      if (_disposed) return null;
      // 409 means it was already accepted — the removal was correct.
      if (error.isConflict) return null;
      _receivedNudges = previous;
      _lastError = error;
      _notify();
      return null;
    }
  }

  /// Drops every cached list. Call on sign-out so the next account never sees
  /// the previous one's friends.
  void clear() {
    _friends = const <Friend>[];
    _activity = const <FriendActivity>[];
    _receivedNudges = const <Nudge>[];
    _sentNudges = const <Nudge>[];
    _incomingRequests = const <FriendRequest>[];
    _outgoingRequests = const <FriendRequest>[];
    _suggestions = const <MatchSuggestion>[];
    _details.clear();
    _lastError = null;
    _notify();
  }

  // ----------------------------------------------------------------- helpers

  /// Inserts or replaces [friend], preserving the server's sort order
  /// (streak desc, then name asc) so a newly accepted friend lands where the
  /// next refetch would put them.
  void _insertFriend(Friend friend) {
    final without =
        _friends.where((f) => f.id != friend.id).toList(growable: true);

    var index = without.length;
    for (var i = 0; i < without.length; i++) {
      final other = without[i];
      if (friend.streakDays > other.streakDays ||
          (friend.streakDays == other.streakDays &&
              friend.name.toLowerCase().compareTo(other.name.toLowerCase()) <
                  0)) {
        index = i;
        break;
      }
    }
    without.insert(index, friend);
    _friends = List<Friend>.unmodifiable(without);
  }

  void _replaceFriend(Friend friend) {
    if (!_friends.any((f) => f.id == friend.id)) return;
    _friends = List<Friend>.unmodifiable(
      _friends.map((f) => f.id == friend.id ? friend : f),
    );
  }

  void _dropSuggestion(String userId) {
    _suggestions = List<MatchSuggestion>.unmodifiable(
      _suggestions.where((s) => s.user.id != userId),
    );
  }

  void _markSuggestionRelationship(String userId, Relationship relationship) {
    if (!_suggestions.any((s) => s.user.id == userId)) return;
    _suggestions = List<MatchSuggestion>.unmodifiable(
      _suggestions.map(
        (s) => s.user.id == userId
            ? s.copyWith(user: s.user.copyWith(relationship: relationship))
            : s,
      ),
    );
  }

  FriendRequest? _findRequest(List<FriendRequest> list, String id) {
    for (final request in list) {
      if (request.id == id) return request;
    }
    return null;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
