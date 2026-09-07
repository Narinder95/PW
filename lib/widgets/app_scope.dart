import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../screens/add_friend_screen.dart';
import '../screens/friend_detail_screen.dart';
import '../services/animation/journey_scene.dart';
import '../services/api/api_client.dart';
import '../services/api/pw_api.dart';
import '../services/auth_service.dart';
import '../services/friends_repository.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/walking_challenge_service.dart';

/// Index of the Friends tab in the bottom nav. Named so the deep-link router
/// does not hard-code a bare `2` in four places.
const int kJournalTab = 0;
const int kJourneyTab = 1;
const int kFriendsTab = 2;

/// Every long-lived service, constructed once in `main()` and handed down the
/// tree by [AppScope].
///
/// There is no state-management package in this project by design. The
/// services are all [ChangeNotifier]s (or plain objects), so a screen reads
/// them with `AppScope.of(context)` and rebuilds with a `ListenableBuilder`.
class AppServices {
  final ApiClient client;
  final PwApi api;
  final AuthService auth;
  final FriendsRepository friends;
  final NotificationService notifications;
  final PushService push;
  final WalkingChallengeService walkingChallenge;

  /// The Journey pet's step bank. Held here — not on `JourneyScene` — because
  /// switching away from the Journey tab tears down its canvas (and scene)
  /// entirely; this object outlives that so a tab round-trip can't refill
  /// steps the pet already walked off. See [PetStepBank]'s doc comment.
  final PetStepBank petStepBank = PetStepBank();

  /// Root navigator, so a push tap can route without a [BuildContext].
  final GlobalKey<NavigatorState> navigatorKey;

  /// Which bottom-nav tab `HomeScreen` is showing.
  final ValueNotifier<int> tab = ValueNotifier<int>(kJournalTab);

  /// Set when the Friends tab should scroll its nudges section into view.
  ///
  /// A *pending* flag rather than an event: the deep-link may arrive before
  /// `FriendsScreen` is even mounted, so the screen consumes this on attach as
  /// well as on change, and clears it once handled.
  final ValueNotifier<bool> pendingNudgeFocus = ValueNotifier<bool>(false);

  AppServices({
    required this.client,
    required this.api,
    required this.auth,
    required this.friends,
    required this.notifications,
    required this.push,
    required this.walkingChallenge,
    required this.navigatorKey,
  });

  /// The configured backend base URL, for the "can't reach the server" panel.
  String get baseUrl => client.config.baseUrl;

  /// **The** deep-link function.
  ///
  /// A tapped push and a tapped in-app notification both come through here, so
  /// the two can never drift apart. Keyed on `refType`/`refId` exactly as the
  /// contract describes; [actorId] carries the friend for an `activity` ref,
  /// whose `refId` points at the activity row rather than at a user.
  void openRef({
    required RefType refType,
    String? refId,
    String? actorId,
  }) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    switch (refType) {
      case RefType.nudge:
        _toFriendsRoot(navigator);
        pendingNudgeFocus.value = true;
        break;

      case RefType.friendRequest:
        _toFriendsRoot(navigator);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const AddFriendScreen(initialTabIndex: 2),
          ),
        );
        break;

      case RefType.user:
        _openFriend(navigator, refId);
        break;

      case RefType.activity:
        // `refId` is the activity, not the person — route by the actor.
        _openFriend(navigator, actorId);
        break;

      case RefType.habit:
        // A habit ref points at one of the user's own habits; the Journal tab
        // is the only place that can show it.
        navigator.popUntil((route) => route.isFirst);
        tab.value = kJournalTab;
        break;

      case RefType.none:
        // Nothing routable. Per the spec this is a deliberate no-op.
        break;
    }
  }

  /// Routes a tapped push through the same path as an in-app tap.
  void openPush(PushOpen open) => openRef(
        refType: open.refType,
        refId: open.refId,
        actorId: open.message.actorId,
      );

  void _toFriendsRoot(NavigatorState navigator) {
    navigator.popUntil((route) => route.isFirst);
    tab.value = kFriendsTab;
  }

  void _openFriend(NavigatorState navigator, String? friendId) {
    if (friendId == null || friendId.isEmpty) return;
    _toFriendsRoot(navigator);
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => FriendDetailScreen(friendId: friendId),
      ),
    );
  }

  /// Clears per-account caches. Called on sign-out.
  Future<void> onSignedOut() async {
    await notifications.stop();
    friends.clear();
    walkingChallenge.clear();
    tab.value = kJournalTab;
  }

  void dispose() {
    tab.dispose();
    pendingNudgeFocus.dispose();
    notifications.dispose();
    friends.dispose();
    walkingChallenge.dispose();
    auth.dispose();
    push.dispose();
    client.close();
  }
}

/// Provides [AppServices] to the whole tree.
///
/// The service identities never change for the life of the app, so this never
/// needs to notify — screens subscribe to the individual [ChangeNotifier]s
/// they actually care about instead of rebuilding on every unrelated change.
class AppScope extends InheritedWidget {
  final AppServices services;

  const AppScope({
    super.key,
    required this.services,
    required super.child,
  });

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found above this widget.');
    return scope!.services;
  }

  /// Non-listening lookup, for callbacks that run outside build.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found above this widget.');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      !identical(services, oldWidget.services);
}
