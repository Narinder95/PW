import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_request.dart';
import '../services/api/api_exception.dart';
import '../services/friends_repository.dart';
import '../services/notification_service.dart';
import '../utils/journal_theme.dart';
import '../widgets/activity_card.dart';
import '../widgets/app_scope.dart';
import '../widgets/friend_card.dart';
import '../widgets/friends/state_panels.dart';
import '../widgets/nudge_card.dart';
import 'add_friend_screen.dart';
import 'friend_detail_screen.dart';
import 'notifications_screen.dart';

/// The Friends tab.
///
/// Every list on this screen is real backend data, a skeleton, an empty state
/// or an error state — there is no sample data anywhere in it.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _nudgesKey = GlobalKey();

  AppServices? _services;
  bool _bootstrapped = false;
  bool _loadingMore = false;
  bool _activityExhausted = false;

  /// Request ids with an accept/decline in flight, so the row can show a
  /// spinner instead of accepting twice.
  final Set<String> _busyRequests = <String>{};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;

    _services?.pendingNudgeFocus.removeListener(_onNudgeFocus);
    _services = services;
    services.pendingNudgeFocus.addListener(_onNudgeFocus);

    if (!_bootstrapped && services.auth.isSignedIn) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
    // The deep-link may have fired before this screen was mounted.
    _onNudgeFocus();
  }

  @override
  void dispose() {
    _services?.pendingNudgeFocus.removeListener(_onNudgeFocus);
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loads

  Future<void> _refresh() async {
    final services = _services;
    if (services == null) return;
    _activityExhausted = false;
    await services.friends.loadAll();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels < position.maxScrollExtent - 320) return;
    _maybeLoadMore();
  }

  void _maybeLoadMore() {
    if (_loadingMore || _activityExhausted) return;
    final repo = _services?.friends;
    if (repo == null || repo.activity.isEmpty || repo.isLoadingActivity) return;

    _loadingMore = true;
    final before = repo.activity.length;
    repo.loadMoreActivity(limit: 20).whenComplete(() {
      if (!mounted) {
        _loadingMore = false;
        return;
      }
      setState(() {
        _loadingMore = false;
        // No new rows came back: the cursor has reached the end of the feed.
        _activityExhausted = repo.activity.length == before;
      });
    });
  }

  /// Scrolls the nudges section into view when a notification deep-links here,
  /// then clears the pending flag so it fires once per link.
  void _onNudgeFocus() {
    final services = _services;
    if (services == null || !services.pendingNudgeFocus.value) return;
    services.pendingNudgeFocus.value = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _nudgesKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    });
  }

  // -------------------------------------------------------------- mutations

  Future<void> _acceptRequest(FriendRequest request) async {
    final services = _services;
    if (services == null) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await services.friends.acceptFriendRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text("You're now friends with ${request.fromUser.name}"),
          ),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not accept.');
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _declineRequest(FriendRequest request) async {
    final services = _services;
    if (services == null) return;
    setState(() => _busyRequests.add(request.id));
    try {
      await services.friends.declineFriendRequest(request.id);
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not decline.');
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  Future<void> _acceptNudge(String nudgeId, String label) async {
    final services = _services;
    if (services == null) return;
    // The repository applies this optimistically and rolls back itself.
    await services.friends.acceptNudge(nudgeId);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Accepted — $label')));
  }

  // ----------------------------------------------------------------- routes

  void _openFriend(Friend friend) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendDetailScreen(
          friendId: friend.id,
          initialFriend: friend,
        ),
      ),
    );
  }

  void _openAddFriend({int tab = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AddFriendScreen(initialTabIndex: tab),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Friends'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: t.textPrimary,
        ),
        actions: [
          IconButton(
            onPressed: _openAddFriend,
            tooltip: 'Add friend',
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          _NotificationBell(
            service: services.notifications,
            onTap: _openNotifications,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: services.auth,
        builder: (context, _) {
          if (!services.auth.isSignedIn) return _buildSignedOut(t);
          return ListenableBuilder(
            listenable: services.friends,
            builder: (context, __) => _buildBody(t, services.friends),
          );
        },
      ),
    );
  }

  Widget _buildSignedOut(JournalTheme t) {
    return EmptyStateView(
      icon: Icons.lock_outline,
      headline: 'Signed out',
      body: 'Sign in to see your friends, nudges and activity.',
      actionLabel: 'Sign in',
      onAction: () => _services?.auth.forceSignOut(),
    );
  }

  Widget _buildBody(JournalTheme t, FriendsRepository repo) {
    final error = repo.lastError;
    final nothingLoaded = repo.friends.isEmpty &&
        repo.activity.isEmpty &&
        repo.incomingRequests.isEmpty &&
        repo.receivedNudges.isEmpty;

    // A hard failure with nothing cached: the whole tab is the error state.
    if (error != null && nothingLoaded && !repo.isLoading) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [ErrorPanel(error: error, onRetry: _refresh)],
        ),
      );
    }

    if (nothingLoaded && repo.isLoading) return _buildSkeleton();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate.fixed(
                _buildTopSections(t, repo),
              ),
            ),
          ),
          _buildActivitySliver(t, repo),
          SliverToBoxAdapter(
            child: SizedBox(height: _loadingMore ? 12 : 28),
          ),
          if (_loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 28),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildTopSections(JournalTheme t, FriendsRepository repo) {
    final children = <Widget>[];

    // 1. Pending friend requests -------------------------------------------
    if (repo.incomingRequests.isNotEmpty) {
      children
        ..add(SectionHeader(
          title: 'Friend requests (${repo.incomingRequests.length})',
        ))
        ..add(const SizedBox(height: 12));
      for (final request in repo.incomingRequests) {
        children
          ..add(FriendRequestTile(
            name: request.fromUser.name,
            handle: request.fromUser.handle,
            avatarColor: request.fromUser.avatarColor,
            subtitle: request.mutualLabel,
            busy: _busyRequests.contains(request.id),
            onAccept: () => _acceptRequest(request),
            onDecline: () => _declineRequest(request),
          ))
          ..add(const SizedBox(height: 12));
      }
      children.add(const SizedBox(height: 12));
    }

    // 2. Friend rail --------------------------------------------------------
    children
      ..add(SectionHeader(
        title: 'Friend Activity',
        trailing: repo.friends.isEmpty
            ? null
            : TextButton(
                onPressed: _openAddFriend,
                style: TextButton.styleFrom(
                  foregroundColor: t.action,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Find friends'),
              ),
      ))
      ..add(const SizedBox(height: 12));

    if (repo.friends.isEmpty) {
      children.add(
        repo.isLoadingFriends
            ? const FriendRailSkeleton()
            : EmptyStateView(
                icon: Icons.group_outlined,
                headline: 'No friends yet',
                body: 'Find people who are building the same habits.',
                actionLabel: 'Find friends',
                onAction: _openAddFriend,
              ),
      );
    } else {
      children.add(
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: repo.friends.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final friend = repo.friends[index];
              return FriendCard(
                friend: friend,
                onTap: () => _openFriend(friend),
              );
            },
          ),
        ),
      );
    }
    children.add(const SizedBox(height: 24));

    // 3. Nudges -------------------------------------------------------------
    children.add(KeyedSubtree(key: _nudgesKey, child: const SizedBox.shrink()));
    if (repo.receivedNudges.isNotEmpty) {
      children
        ..add(const SectionHeader(title: 'Nudges Received'))
        ..add(const SizedBox(height: 12));
      for (final nudge in repo.receivedNudges) {
        children
          ..add(NudgeCard(
            nudge: nudge,
            onAccept: () => _acceptNudge(nudge.id, nudge.habitName),
          ))
          ..add(const SizedBox(height: 12));
      }
      children.add(const SizedBox(height: 12));
    }

    // 4. Recent activity header --------------------------------------------
    children
      ..add(const SectionHeader(title: 'Recent Activity'))
      ..add(const SizedBox(height: 12));

    return children;
  }

  Widget _buildActivitySliver(JournalTheme t, FriendsRepository repo) {
    if (repo.activity.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverToBoxAdapter(
          child: repo.isLoadingActivity
              ? const RowListSkeleton()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    repo.friends.isEmpty
                        ? 'Activity from your friends will show up here.'
                        : 'No activity in the last few days.',
                    style: TextStyle(fontSize: 14, color: t.textMuted),
                  ),
                ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: repo.activity.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = repo.activity[index];
          return ActivityCard(
            activity: item,
            onTap: item.friendId.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            FriendDetailScreen(friendId: item.friendId),
                      ),
                    ),
          );
        },
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: const [
        SectionHeader(title: 'Friend Activity'),
        SizedBox(height: 12),
        FriendRailSkeleton(),
        SizedBox(height: 24),
        SectionHeader(title: 'Recent Activity'),
        SizedBox(height: 12),
        RowListSkeleton(count: 4),
      ],
    );
  }
}

/// Bell with a live unread badge: a dot with the count for 1-9, `9+` above.
class _NotificationBell extends StatelessWidget {
  final NotificationService service;
  final VoidCallback onTap;

  const _NotificationBell({required this.service, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final count = service.unreadCount;
        return IconButton(
          onPressed: onTap,
          tooltip: count > 0 ? '$count unread notifications' : 'Notifications',
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: t.incomplete,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: t.background, width: 1.5),
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
