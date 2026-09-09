import 'package:flutter/material.dart';

import '../../models/app_notification.dart';
import '../../models/comparison.dart';
import '../../models/friend.dart';
import '../../models/friend_activity.dart';
import '../../models/friend_habit.dart';
import '../../models/friend_request.dart';
import '../../models/habit.dart';
import '../../models/habit_month_progress.dart';
import '../../models/json.dart';
import '../../models/match_suggestion.dart';
import '../../models/nudge.dart';
import '../../models/user_profile.dart';
import '../../models/walking_challenge.dart';
import 'api_client.dart';

/// One typed method per endpoint in `docs/API_CONTRACT.md`.
///
/// Every method returns a model (or a small result record below) and throws
/// `ApiException` on failure. No caching, no state, no `ChangeNotifier` — the
/// services layer above owns all of that.
class PwApi {
  final ApiClient client;

  PwApi(this.client);

  /// Convenience for `PwApi(ApiClient(httpClient: ...))`.
  factory PwApi.withClient(ApiClient client) => PwApi(client);

  // ------------------------------------------------------------------ health

  /// `GET /api/health` — no auth. Used by the connection-check screen.
  Future<HealthStatus> health() async {
    final json = await client.get('/api/health');
    return HealthStatus.fromJson(json);
  }

  // -------------------------------------------------------------------- auth

  /// `POST /api/auth/anonymous` -> `201 {token, user}`.
  ///
  /// Provisions an account with no credentials. This is what the app calls on
  /// first launch: there is no sign-up screen, so the user is never asked for
  /// anything before they can start using the app.
  Future<AuthResult> registerAnonymous({String? name}) async {
    final json = await client.post('/api/auth/anonymous', body: {
      if (name != null) 'name': name,
    });
    return AuthResult.fromJson(json);
  }

  /// `POST /api/auth/link` -> `200 {user}`.
  ///
  /// Claims the current anonymous account so it survives a reinstall or moves
  /// to another device. At least one of [email] / [phone] is required.
  Future<UserProfile> linkAccount({
    String? email,
    String? phone,
    required String password,
    String? username,
  }) async {
    final json = await client.post('/api/auth/link', body: {
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      'password': password,
      if (username != null) 'username': username,
    });
    return UserProfile.fromJson(asMap(asMap(json)['user']));
  }

  /// `POST /api/auth/register` -> `201 {token, user}`.
  Future<AuthResult> register({
    required String username,
    required String name,
    required String email,
    required String password,
  }) async {
    final json = await client.post('/api/auth/register', body: {
      'username': username,
      'name': name,
      'email': email,
      'password': password,
    });
    return AuthResult.fromJson(json);
  }

  /// `POST /api/auth/login` -> `200 {token, user}`.
  /// [usernameOrEmail] accepts either, per the contract.
  Future<AuthResult> login({
    required String usernameOrEmail,
    required String password,
  }) async {
    final json = await client.post('/api/auth/login', body: {
      'usernameOrEmail': usernameOrEmail,
      'password': password,
    });
    return AuthResult.fromJson(json);
  }

  /// `POST /api/auth/logout` -> `204`. Revokes the token server-side.
  Future<void> logout() => client.post('/api/auth/logout');

  /// `DELETE /api/me` -> `204`. Permanently deletes the account and
  /// everything attached to it - not reversible, and not just this device's
  /// session. Callers must confirm with the user before calling this.
  Future<void> deleteAccount() => client.delete('/api/me');

  /// `GET /api/me` -> `200 {user}` (includes `email`).
  Future<UserProfile> me() async {
    final json = await client.get('/api/me');
    return UserProfile.fromJson(asMap(json['user']));
  }

  /// `PATCH /api/me`. Omitted arguments are left unchanged server-side.
  Future<UserProfile> updateMe({String? name, Color? avatarColor}) async {
    final json = await client.patch(
      '/api/me',
      body: compactJson({
        'name': name,
        'avatarColor': avatarColor == null ? null : colorToHex(avatarColor),
      }),
    );
    return UserProfile.fromJson(asMap(json['user']));
  }

  // ------------------------------------------------------------------ habits

  /// `GET /api/habits?date=YYYY-MM-DD` (defaults to today server-side).
  Future<List<Habit>> getHabits({DateTime? date}) async {
    final json = await client.get(
      '/api/habits',
      query: {if (date != null) 'date': asDateOnly(date)},
    );
    return asModelList(json['habits'], Habit.fromJson);
  }

  /// `POST /api/habits` -> `201 {habit}`. [target] must be >= 1.
  Future<Habit> createHabit({
    required String name,
    required int target,
    String? icon,
    Color? color,
    String? unit,
  }) async {
    final json = await client.post(
      '/api/habits',
      body: compactJson({
        'name': name,
        'target': target,
        'icon': icon,
        'color': color == null ? null : colorToHex(color),
        'unit': unit,
      }),
    );
    return Habit.fromJson(asMap(json['habit']));
  }

  /// `PATCH /api/habits/:id`. Omitted arguments are left unchanged.
  Future<Habit> updateHabit(
    String habitId, {
    String? name,
    String? icon,
    Color? color,
    int? target,
    String? unit,
  }) async {
    final json = await client.patch(
      '/api/habits/${Uri.encodeComponent(habitId)}',
      body: compactJson({
        'name': name,
        'icon': icon,
        'color': color == null ? null : colorToHex(color),
        'target': target,
        'unit': unit,
      }),
    );
    return Habit.fromJson(asMap(json['habit']));
  }

  /// `DELETE /api/habits/:id` -> `204`.
  Future<void> deleteHabit(String habitId) =>
      client.delete('/api/habits/${Uri.encodeComponent(habitId)}');

  /// `POST /api/habits/:id/log` -> `200 {habit, activity|null}`.
  ///
  /// **Sets** the day's progress, it does not increment. `activity` is
  /// non-null only the first time a log crosses `progress >= target` on that
  /// date; re-logging a completed habit the same day returns null.
  Future<HabitLogResult> logHabit(
    String habitId, {
    required int progress,
    DateTime? date,
  }) async {
    final json = await client.post(
      '/api/habits/${Uri.encodeComponent(habitId)}/log',
      body: compactJson({
        'progress': progress,
        'date': date == null ? null : asDateOnly(date),
      }),
    );
    return HabitLogResult.fromJson(json);
  }

  /// `GET /api/habits/month?month=YYYY-MM` (defaults to the current month
  /// server-side). Powers the Journal tab's radial monthly-progress card.
  Future<HabitMonthReport> getHabitsMonth({DateTime? month}) async {
    final json = await client.get(
      '/api/habits/month',
      query: {if (month != null) 'month': asYearMonth(month)},
    );
    return HabitMonthReport.fromJson(json);
  }

  // ----------------------------------------------------------------- friends

  /// `GET /api/friends` — streak desc, then name asc. Order is preserved.
  Future<List<Friend>> getFriends() async {
    final json = await client.get('/api/friends');
    return asModelList(json['friends'], Friend.fromJson);
  }

  /// `GET /api/friends/:id` -> `{friend, habits}`.
  /// A non-friend id throws `403 forbidden`; an unknown id throws `404`.
  Future<FriendDetail> getFriend(String friendId) async {
    final json = await client.get('/api/friends/${Uri.encodeComponent(friendId)}');
    return FriendDetail.fromJson(json);
  }

  /// `DELETE /api/friends/:id` -> `204`. Removes both directions.
  Future<void> removeFriend(String friendId) =>
      client.delete('/api/friends/${Uri.encodeComponent(friendId)}');

  /// `GET /api/friends/:id/compare` -> `{comparison}`.
  Future<FriendComparison> compareWithFriend(String friendId) async {
    final json = await client
        .get('/api/friends/${Uri.encodeComponent(friendId)}/compare');
    return FriendComparison.fromJson(json);
  }

  // -------------------------------------------------------- match / discovery

  /// `GET /api/users/search?q=&limit=`.
  ///
  /// [query] must be at least 1 character — an empty one is a `400` from the
  /// server, so it is rejected here rather than burning a round trip.
  Future<List<SearchResult>> searchUsers(String query, {int? limit}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <SearchResult>[];
    final json = await client.get(
      '/api/users/search',
      query: {'q': trimmed, if (limit != null) 'limit': limit},
    );
    return asModelList(json['users'], SearchResult.fromJson);
  }

  /// `GET /api/match/suggestions?limit=`.
  /// Ranked server-side by `matchScore` desc then username asc — do not re-sort.
  Future<List<MatchSuggestion>> matchSuggestions({int? limit}) async {
    final json = await client.get(
      '/api/match/suggestions',
      query: {if (limit != null) 'limit': limit},
    );
    return asModelList(json['suggestions'], MatchSuggestion.fromJson);
  }

  // --------------------------------------------------------- friend requests

  /// `GET /api/friend-requests` -> `{incoming, outgoing}` (pending only).
  Future<FriendRequestInbox> getFriendRequests() async {
    final json = await client.get('/api/friend-requests');
    return FriendRequestInbox.fromJson(json);
  }

  /// `POST /api/friend-requests`.
  ///
  /// Normally `201 {request}`. If the target already had a pending request out
  /// to you, the server **auto-accepts** and returns
  /// `200 {request, friend, autoAccepted: true}` — check
  /// [SendRequestResult.autoAccepted] before showing "request sent".
  Future<SendRequestResult> sendFriendRequest(String toUserId) async {
    final json = await client
        .post('/api/friend-requests', body: {'toUserId': toUserId});
    return SendRequestResult.fromJson(json);
  }

  /// `POST /api/friend-requests/:id/accept` -> `200 {friend}`.
  Future<Friend> acceptFriendRequest(String requestId) async {
    final json = await client
        .post('/api/friend-requests/${Uri.encodeComponent(requestId)}/accept');
    return Friend.fromJson(asMap(json['friend']));
  }

  /// `POST /api/friend-requests/:id/decline` -> `204`. Notifies nobody.
  Future<void> declineFriendRequest(String requestId) => client
      .post('/api/friend-requests/${Uri.encodeComponent(requestId)}/decline');

  /// `DELETE /api/friend-requests/:id` -> `204`. Sender-only.
  Future<void> cancelFriendRequest(String requestId) =>
      client.delete('/api/friend-requests/${Uri.encodeComponent(requestId)}');

  // ---------------------------------------------------------------- activity

  /// `GET /api/activity?limit=&before=` — friends' activity only, newest
  /// first. [before] is a cursor: only strictly-older rows are returned.
  Future<List<FriendActivity>> getActivity({int? limit, DateTime? before}) async {
    final json = await client.get(
      '/api/activity',
      query: {
        if (limit != null) 'limit': limit,
        if (before != null) 'before': before.toUtc().toIso8601String(),
      },
    );
    return asModelList(json['activities'], FriendActivity.fromJson);
  }

  // ------------------------------------------------------------------ nudges

  /// `GET /api/nudges` -> `{received, sent}`.
  /// `received` is pending only; `sent` is the 30 most recent, any status.
  Future<NudgeInbox> getNudges() async {
    final json = await client.get('/api/nudges');
    return NudgeInbox.fromJson(json);
  }

  /// `POST /api/nudges` -> `201 {nudge}`.
  ///
  /// Throws `403` if [toUserId] is not a friend, `400` for self-nudge, and
  /// `429` with `retryAfterSeconds` if the 60-minute cooldown for this
  /// sender/recipient/[habitName] triple has not elapsed.
  Future<Nudge> sendNudge({
    required String toUserId,
    required String habitName,
    String? habitId,
    String? habitIcon,
    Color? habitColor,
    NudgeType type = NudgeType.nudge,
    String? message,
  }) async {
    final json = await client.post(
      '/api/nudges',
      body: compactJson({
        'toUserId': toUserId,
        'habitName': habitName,
        'habitId': habitId,
        'habitIcon': habitIcon,
        'habitColor': habitColor == null ? null : colorToHex(habitColor),
        'type': type.wire,
        'message': message,
      }),
    );
    return Nudge.fromJson(asMap(json['nudge']));
  }

  /// `POST /api/nudges/:id/accept` -> `200 {nudge}`. Recipient only;
  /// accepting twice throws `409 conflict`.
  Future<Nudge> acceptNudge(String nudgeId) async {
    final json =
        await client.post('/api/nudges/${Uri.encodeComponent(nudgeId)}/accept');
    return Nudge.fromJson(asMap(json['nudge']));
  }

  // ----------------------------------------------------------- notifications

  /// `GET /api/notifications?limit=&unreadOnly=`.
  /// [NotificationPage.unreadCount] is the caller's *total* unread count,
  /// independent of `limit`/`unreadOnly`.
  Future<NotificationPage> getNotifications({int? limit, bool? unreadOnly}) async {
    final json = await client.get(
      '/api/notifications',
      query: {
        if (limit != null) 'limit': limit,
        if (unreadOnly != null) 'unreadOnly': unreadOnly,
      },
    );
    return NotificationPage.fromJson(json);
  }

  /// `GET /api/notifications/unread-count` -> `{count}`.
  /// Also the SSE fallback poll.
  Future<int> getUnreadCount() async {
    final json = await client.get('/api/notifications/unread-count');
    return asInt(json['count']);
  }

  /// `POST /api/notifications/:id/read` -> `204`. Idempotent.
  /// Someone else's notification throws `404`, never `403`.
  Future<void> markNotificationRead(String notificationId) => client
      .post('/api/notifications/${Uri.encodeComponent(notificationId)}/read');

  /// `POST /api/notifications/read-all` -> `200 {updated}`.
  /// Returns how many rows changed.
  Future<int> markAllNotificationsRead() async {
    final json = await client.post('/api/notifications/read-all');
    return asInt(json['updated']);
  }

  /// `DELETE /api/notifications/:id` -> `204`.
  Future<void> deleteNotification(String notificationId) =>
      client.delete('/api/notifications/${Uri.encodeComponent(notificationId)}');

  /// URI for the SSE stream, `GET /api/notifications/stream`.
  ///
  /// Pass [token] to put it in the query string — the contract allows that
  /// because `EventSource` cannot set headers. `NotificationService` uses
  /// `http.Request` and sends the `Authorization` header instead, so it leaves
  /// [token] null and keeps the credential out of URLs and server logs.
  Uri notificationStreamUri({String? token}) => client.config.resolve(
        '/api/notifications/stream',
        {if (token != null) 'token': token},
      );

  // ------------------------------------------------------- walking challenge

  /// `GET /api/challenge`. Cheap read of the server's last-computed state,
  /// without syncing any new step data.
  Future<WalkingChallenge> getChallenge() async {
    final json = await client.get('/api/challenge');
    return WalkingChallenge.fromJson(asMap(json['challenge']));
  }

  /// `POST /api/steps/sync` -> `200 {challenge}`.
  ///
  /// [stepsByDate] maps `YYYY-MM-DD` -> total steps for that day, as read
  /// from the device's own health data. 1-31 entries. The server takes the
  /// **larger** of the existing and new value per date, so a resync of a
  /// partial day can never lose steps.
  Future<WalkingChallenge> syncSteps(Map<String, int> stepsByDate) async {
    final json = await client.post(
      '/api/steps/sync',
      body: {
        'days': stepsByDate.entries
            .map((e) => {'date': e.key, 'steps': e.value})
            .toList(growable: false),
      },
    );
    return WalkingChallenge.fromJson(asMap(json['challenge']));
  }

  // ----------------------------------------------------------------- devices

  /// `POST /api/devices` -> `201 {device}`.
  ///
  /// Idempotent on `(user, token)`; a token registered under another user is
  /// reassigned to the caller, so a shared handset stops receiving the
  /// previous account's pushes.
  Future<PushDevice> registerDevice({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    final json = await client.post(
      '/api/devices',
      body: compactJson({
        'token': token,
        'platform': platform,
        'appVersion': appVersion,
      }),
    );
    return PushDevice.fromJson(asMap(json['device']));
  }

  /// `DELETE /api/devices/:token` -> `204`. Called on sign-out, **before** the
  /// bearer token is cleared — the request is authenticated.
  Future<void> deleteDevice(String token) =>
      client.delete('/api/devices/${Uri.encodeComponent(token)}');
}

// ---------------------------------------------------------------------------
// Result records
//
// Small envelopes for endpoints that return more than one model. They live
// here rather than in lib/models because they describe a *response*, not a
// domain object the UI holds onto.
// ---------------------------------------------------------------------------

/// `GET /api/health`.
@immutable
class HealthStatus {
  final bool ok;
  final String version;
  final DateTime? time;

  const HealthStatus({
    required this.ok,
    this.version = '',
    this.time,
  });

  factory HealthStatus.fromJson(Map<String, dynamic> json) => HealthStatus(
        ok: asBool(json['ok']),
        version: asString(json['version']),
        time: asDateTimeOrNull(json['time']),
      );

  @override
  String toString() => 'HealthStatus(ok: $ok, version: $version)';
}

/// `POST /api/auth/register` and `/login`.
@immutable
class AuthResult {
  final String token;
  final UserProfile user;

  const AuthResult({required this.token, required this.user});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: asString(json['token']),
        user: UserProfile.fromJson(asMap(json['user'])),
      );

  @override
  String toString() => 'AuthResult(${user.id})';
}

/// `POST /api/habits/:id/log`.
@immutable
class HabitLogResult {
  final Habit habit;

  /// Non-null only when this log first crossed the target for that date.
  final FriendActivity? activity;

  const HabitLogResult({required this.habit, this.activity});

  /// Whether this log completed the habit for the first time today — the
  /// trigger for a celebration animation.
  bool get justCompleted => activity != null;

  factory HabitLogResult.fromJson(Map<String, dynamic> json) {
    final activityJson = asMapOrNull(json['activity']);
    return HabitLogResult(
      habit: Habit.fromJson(asMap(json['habit'])),
      activity: activityJson == null || activityJson.isEmpty
          ? null
          : FriendActivity.fromJson(activityJson),
    );
  }

  @override
  String toString() => 'HabitLogResult(${habit.id}, activity: $justCompleted)';
}

/// `GET /api/friends/:id`.
@immutable
class FriendDetail {
  final Friend friend;
  final List<FriendHabit> habits;

  const FriendDetail({
    required this.friend,
    this.habits = const <FriendHabit>[],
  });

  factory FriendDetail.fromJson(Map<String, dynamic> json) => FriendDetail(
        friend: Friend.fromJson(asMap(json['friend'])),
        habits: asModelList(json['habits'], FriendHabit.fromJson),
      );

  @override
  String toString() => 'FriendDetail(${friend.id}, ${habits.length} habits)';
}

/// `GET /api/friend-requests`.
@immutable
class FriendRequestInbox {
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;

  const FriendRequestInbox({
    this.incoming = const <FriendRequest>[],
    this.outgoing = const <FriendRequest>[],
  });

  bool get isEmpty => incoming.isEmpty && outgoing.isEmpty;

  /// Badge count for the Friends tab — outgoing requests need no action.
  int get incomingCount => incoming.length;

  factory FriendRequestInbox.fromJson(Map<String, dynamic> json) =>
      FriendRequestInbox(
        incoming: asModelList(json['incoming'], FriendRequest.fromJson),
        outgoing: asModelList(json['outgoing'], FriendRequest.fromJson),
      );

  @override
  String toString() =>
      'FriendRequestInbox(in ${incoming.length}, out ${outgoing.length})';
}

/// `POST /api/friend-requests`, covering both the normal and auto-accept
/// responses.
@immutable
class SendRequestResult {
  /// The created (or auto-accepted) request. Null only on an off-contract
  /// response that omitted it.
  final FriendRequest? request;

  /// Populated only when [autoAccepted] is true.
  final Friend? friend;

  /// True when the target had already requested you and the server turned
  /// this into an immediate friendship.
  final bool autoAccepted;

  const SendRequestResult({
    this.request,
    this.friend,
    this.autoAccepted = false,
  });

  factory SendRequestResult.fromJson(Map<String, dynamic> json) {
    final requestJson = asMapOrNull(json['request']);
    final friendJson = asMapOrNull(json['friend']);
    return SendRequestResult(
      request: requestJson == null || requestJson.isEmpty
          ? null
          : FriendRequest.fromJson(requestJson),
      friend: friendJson == null || friendJson.isEmpty
          ? null
          : Friend.fromJson(friendJson),
      // Trust the flag, but a `friend` object is proof on its own — a server
      // that forgets the flag must not silently drop the new friendship.
      autoAccepted: asBool(json['autoAccepted']) ||
          (friendJson != null && friendJson.isNotEmpty),
    );
  }

  @override
  String toString() => 'SendRequestResult(autoAccepted: $autoAccepted)';
}

/// `GET /api/nudges`.
@immutable
class NudgeInbox {
  /// Pending nudges addressed to the signed-in user.
  final List<Nudge> received;

  /// The 30 most recent nudges the user sent, any status.
  final List<Nudge> sent;

  const NudgeInbox({
    this.received = const <Nudge>[],
    this.sent = const <Nudge>[],
  });

  bool get isEmpty => received.isEmpty && sent.isEmpty;

  factory NudgeInbox.fromJson(Map<String, dynamic> json) => NudgeInbox(
        received: asModelList(json['received'], Nudge.fromJson),
        sent: asModelList(json['sent'], Nudge.fromJson),
      );

  @override
  String toString() =>
      'NudgeInbox(received ${received.length}, sent ${sent.length})';
}

/// `GET /api/notifications`.
@immutable
class NotificationPage {
  final List<AppNotification> notifications;

  /// The caller's total unread count — **not** the unread count of this page.
  final int unreadCount;

  const NotificationPage({
    this.notifications = const <AppNotification>[],
    this.unreadCount = 0,
  });

  factory NotificationPage.fromJson(Map<String, dynamic> json) =>
      NotificationPage(
        notifications:
            asModelList(json['notifications'], AppNotification.fromJson),
        unreadCount: asInt(json['unreadCount']),
      );

  @override
  String toString() =>
      'NotificationPage(${notifications.length} rows, $unreadCount unread)';
}

/// `POST /api/devices`.
@immutable
class PushDevice {
  final String id;
  final String token;

  /// `android` | `ios` | `web`.
  final String platform;

  final DateTime? lastSeenAt;

  const PushDevice({
    required this.id,
    required this.token,
    required this.platform,
    this.lastSeenAt,
  });

  factory PushDevice.fromJson(Map<String, dynamic> json) => PushDevice(
        id: asString(json['id']),
        token: asString(json['token']),
        platform: asString(json['platform']),
        lastSeenAt: asDateTimeOrNull(json['lastSeenAt']),
      );

  @override
  String toString() => 'PushDevice($id, $platform)';
}
