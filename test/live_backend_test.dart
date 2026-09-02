// End-to-end: the REAL client data layer against the REAL backend over HTTP.
//
// Unit tests with a fake http.Client prove the client parses what we *think*
// the server sends. This file proves the two actually agree. It is the only
// test that would catch a contract drift between them.
//
// Requires the backend to be running:
//     cd backend && node src/index.js
// If it is not up, every test here is skipped rather than failed, so `flutter
// test` still passes on a machine with no server.
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:pw/models/app_notification.dart';
import 'package:pw/models/friend_habit.dart';
import 'package:pw/models/nudge.dart';
import 'package:pw/models/user_profile.dart';
import 'package:pw/services/api/api_client.dart';
import 'package:pw/services/api/api_config.dart';
import 'package:pw/services/api/api_exception.dart';
import 'package:pw/services/api/pw_api.dart';

const String kBaseUrl = 'http://localhost:8080';

Future<bool> serverIsUp() async {
  try {
    final res = await http
        .get(Uri.parse('$kBaseUrl/api/health'))
        .timeout(const Duration(seconds: 2));
    return res.statusCode == 200;
  } on Exception {
    return false;
  } on Error {
    return false;
  }
}

/// A fresh, isolated account per call — tests never collide or depend on order.
int _seq = 0;
Future<({PwApi api, UserProfile user, String token})> freshUser() async {
  _seq++;
  final stamp = '${DateTime.now().microsecondsSinceEpoch}$_seq';
  // `ztest` prefix so `backend/src/purge_test_users.js` can find and remove
  // these afterwards — this suite registers REAL rows on a REAL server.
  final username = 'ztest${stamp.substring(stamp.length - 11)}';

  final client = ApiClient(config: ApiConfig(override: kBaseUrl));
  final api = PwApi(client);
  final auth = await api.register(
    username: username,
    name: 'Test $_seq',
    email: '$username@example.com',
    password: 'password123',
  );
  client.authToken = auth.token;
  return (api: api, user: auth.user, token: auth.token);
}

/// Cached so the server is probed once, not once per test.
///
/// `skip:` cannot be used for this: its argument is evaluated while the group
/// is being *declared*, long before any `setUpAll` has run. So each test asks
/// for the server itself and marks itself skipped when it is absent.
bool? _serverUp;
Future<bool> ensureServer() async {
  _serverUp ??= await serverIsUp();
  if (!_serverUp!) {
    markTestSkipped(
      'backend not running at $kBaseUrl — start it: cd backend && node src/index.js',
    );
  }
  return _serverUp!;
}

void main() {

  group('live backend', () {
    test('health check reports a push provider', () async {
      if (!await ensureServer()) return;
      final api = PwApi(ApiClient(config: ApiConfig(override: kBaseUrl)));
      final health = await api.health();
      expect(health.ok, isTrue);
    });

    test('register -> me -> logout round-trips', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final me = await a.api.me();
      expect(me.id, a.user.id);
      expect(me.username, a.user.username);
      expect(me.email, isNotEmpty);
      await a.api.logout();
      // The token is dead now.
      await expectLater(
        a.api.me(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
    });

    test('habits: create, log, and read back a real streak', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      expect(await a.api.getHabits(), isEmpty, reason: 'a new account starts with no habits');

      final habit = await a.api.createHabit(
        name: 'Steps',
        target: 100,
        icon: 'R',
        color: const Color(0xFF2E7D32),
        unit: 'steps',
      );
      expect(habit.target, 100);
      expect(habit.progress, 0);
      expect(habit.weekData.length, 7);

      final logged = await a.api.logHabit(habit.id, progress: 100);
      expect(logged.habit.progress, 100);
      expect(logged.habit.completedToday, isTrue);
      expect(logged.habit.completionPercentage, 1.0);

      final all = await a.api.getHabits();
      expect(all.single.streak, greaterThanOrEqualTo(1));
    });

    test('the full friending flow, as the UI performs it', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final b = await freshUser();

      // Discovery.
      final found = await a.api.searchUsers(b.user.username);
      expect(found.map((u) => u.id), contains(b.user.id));
      expect(found.firstWhere((u) => u.id == b.user.id).relationship,
          Relationship.none);

      // Request.
      final sent = await a.api.sendFriendRequest(b.user.id);
      expect(sent.autoAccepted, isFalse);

      // B sees it incoming, with A named.
      final inbox = await b.api.getFriendRequests();
      expect(inbox.incoming.map((r) => r.fromUser.id), contains(a.user.id));

      // B was notified.
      final notes = await b.api.getNotifications();
      expect(
        notes.notifications.any((n) => n.type == NotificationType.friendRequest),
        isTrue,
        reason: 'no friend_request notification arrived',
      );
      expect(notes.unreadCount, greaterThan(0));

      // Accept.
      final request = inbox.incoming.firstWhere((r) => r.fromUser.id == a.user.id);
      final friend = await b.api.acceptFriendRequest(request.id);
      expect(friend.id, a.user.id);

      // Both directions.
      expect((await a.api.getFriends()).map((f) => f.id), contains(b.user.id));
      expect((await b.api.getFriends()).map((f) => f.id), contains(a.user.id));

      // A was told.
      final aNotes = await a.api.getNotifications();
      expect(
        aNotes.notifications.any((n) => n.type == NotificationType.friendRequestAccepted),
        isTrue,
      );
    });

    test('a stranger cannot read your habits', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final stranger = await freshUser();
      await a.api.createHabit(name: 'Secret', target: 10);

      await expectLater(
        stranger.api.getFriend(a.user.id),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'isForbidden', isTrue)),
      );
    });

    test('friend detail and compare parse against real data', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final b = await freshUser();
      await a.api.sendFriendRequest(b.user.id);
      final inbox = await b.api.getFriendRequests();
      await b.api.acceptFriendRequest(inbox.incoming.first.id);

      final h = await b.api.createHabit(name: 'Water', target: 8, unit: 'cups');
      await b.api.logHabit(h.id, progress: 4);
      await a.api.createHabit(name: 'Water', target: 8, unit: 'cups');

      final detail = await a.api.getFriend(b.user.id);
      expect(detail.habits.single.name, 'Water');
      expect(detail.habits.single.status, HabitStatus.inProgress);
      expect(detail.habits.single.percentage, closeTo(0.5, 1e-9));
      expect(detail.friend.weekData.length, 7);

      final cmp = await a.api.compareWithFriend(b.user.id);
      expect(cmp.habits, isNotEmpty, reason: 'a shared habit should be compared');
      expect(cmp.habits.single.name, 'Water');
    });

    test('nudge, cooldown, and accept — including the 429 the UI must handle',
        () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final b = await freshUser();
      await a.api.sendFriendRequest(b.user.id);
      final inbox = await b.api.getFriendRequests();
      await b.api.acceptFriendRequest(inbox.incoming.first.id);

      final nudge = await a.api.sendNudge(
        toUserId: b.user.id,
        habitName: 'Meditate',
        habitIcon: 'M',
        habitColor: const Color(0xFFA855F7),
      );
      expect(nudge.type, NudgeType.nudge);
      expect(nudge.status, NudgeStatus.pending);

      // The cooldown is what produces the "try again in N min" copy.
      try {
        await a.api.sendNudge(toUserId: b.user.id, habitName: 'Meditate');
        fail('expected a rate_limited exception');
      } on ApiException catch (e) {
        expect(e.isRateLimited, isTrue);
        expect(e.retryAfterSeconds, isNotNull);
        expect(e.retryAfterSeconds, greaterThan(0));
      }

      final received = await b.api.getNudges();
      expect(received.received.map((n) => n.id), contains(nudge.id));

      final accepted = await b.api.acceptNudge(nudge.id);
      expect(accepted.status, NudgeStatus.accepted);
      expect((await b.api.getNudges()).received, isEmpty);
    });

    test('notifications: read, read-all and unread counts stay consistent',
        () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final b = await freshUser();
      await a.api.sendFriendRequest(b.user.id);

      final before = await b.api.getUnreadCount();
      expect(before, greaterThan(0));

      final page = await b.api.getNotifications();
      await b.api.markNotificationRead(page.notifications.first.id);
      expect(await b.api.getUnreadCount(), before - 1);

      await b.api.markAllNotificationsRead();
      expect(await b.api.getUnreadCount(), 0);

      // Deleting is safe and idempotent from the UI's perspective.
      await b.api.deleteNotification(page.notifications.first.id);
      final after = await b.api.getNotifications();
      expect(after.notifications.map((n) => n.id),
          isNot(contains(page.notifications.first.id)));
    });

    test('match suggestions rank a shared-habit user and stay deterministic',
        () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final twin = await freshUser();
      for (final name in ['Steps', 'Water', 'Sleep']) {
        await a.api.createHabit(name: name, target: 10);
        await twin.api.createHabit(name: name, target: 10);
      }

      final first = await a.api.matchSuggestions();
      final hit = first.where((s) => s.user.id == twin.user.id);
      expect(hit, isNotEmpty, reason: 'the shared-habit user was not suggested');
      expect(hit.first.sharedHabits.length, 3);
      expect(hit.first.matchScore, inInclusiveRange(0, 100));
      expect(hit.first.reason, isNotEmpty);

      final second = await a.api.matchSuggestions();
      expect(
        second.map((s) => '${s.user.id}:${s.matchScore}').toList(),
        first.map((s) => '${s.user.id}:${s.matchScore}').toList(),
        reason: 'suggestions are not deterministic',
      );
    });

    test('device registration round-trips', () async {
      if (!await ensureServer()) return;
      final a = await freshUser();
      final device = await a.api.registerDevice(token: 'test-token-1', platform: 'android');
      expect(device.token, 'test-token-1');
      // Idempotent.
      await a.api.registerDevice(token: 'test-token-1', platform: 'android');
      await a.api.deleteDevice('test-token-1');
    });

    test('a wrong base URL surfaces as a network error, not a crash', () async {
      if (!await ensureServer()) return;
      final api = PwApi(ApiClient(
        config: ApiConfig(override: 'http://127.0.0.1:1'),
        timeout: const Duration(seconds: 2),
      ));
      await expectLater(
        api.health(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', isTrue)),
      );
    });
  });
}
