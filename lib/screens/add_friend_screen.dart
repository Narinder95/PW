import 'dart:async';

import 'package:flutter/material.dart';

import '../models/friend_request.dart';
import '../models/match_suggestion.dart';
import '../models/user_profile.dart';
import '../services/api/api_exception.dart';
import '../services/friends_repository.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/pw_avatar.dart';
import '../widgets/friends/state_panels.dart';
import '../widgets/nudge_card.dart';

/// Finding people: ranked suggestions, username search, and the requests
/// already in flight.
class AddFriendScreen extends StatefulWidget {
  /// 0 = Suggested, 1 = Search, 2 = Requests.
  final int initialTabIndex;

  const AddFriendScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 2),
  );

  final TextEditingController _query = TextEditingController();
  Timer? _debounce;

  AppServices? _services;
  bool _bootstrapped = false;

  List<SearchResult> _results = const <SearchResult>[];
  bool _searching = false;
  bool _hasSearched = false;
  String _lastQuery = '';
  ApiException? _searchError;

  /// Relationship changes applied locally after an Add/Accept, so a row
  /// updates without re-running the search.
  final Map<String, Relationship> _relationshipOverrides =
      <String, Relationship>{};

  /// User ids with a request action in flight.
  final Set<String> _busyUsers = <String>{};

  /// Request ids with an accept/decline/cancel in flight.
  final Set<String> _busyRequests = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    if (!_bootstrapped) {
      _bootstrapped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        services.friends.loadSuggestions();
        services.friends.loadRequests();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _tabs.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- search

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _results = const <SearchResult>[];
        _searching = false;
        _hasSearched = false;
        _lastQuery = '';
        _searchError = null;
      });
      return;
    }

    setState(() => _searching = true);
    // 300 ms, per the spec — a keystroke-per-request search hammers the API.
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    final services = _services;
    if (services == null) return;
    try {
      final results = await services.friends.searchUsers(query, limit: 25);
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _results = results;
        _searching = false;
        _hasSearched = true;
        _lastQuery = query;
        _searchError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasSearched = true;
        _lastQuery = query;
        _searchError = error;
      });
    }
  }

  // -------------------------------------------------------------- mutations

  Relationship _relationshipFor(SearchResult user) =>
      _relationshipOverrides[user.id] ?? user.relationship;

  Future<void> _sendRequest(SearchResult user) async {
    final services = _services;
    if (services == null) return;
    setState(() => _busyUsers.add(user.id));
    try {
      final result = await services.friends.sendFriendRequest(user.id);
      if (!mounted) return;
      setState(() {
        _relationshipOverrides[user.id] =
            result.autoAccepted ? Relationship.friend : Relationship.requestSent;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.autoAccepted
                  ? "You're now friends with ${user.name}"
                  : 'Request sent to ${user.name}',
            ),
          ),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not send that request.');
    } finally {
      if (mounted) setState(() => _busyUsers.remove(user.id));
    }
  }

  /// Accepts the pending request this user already sent us. The id comes from
  /// the repository's incoming list rather than from the search row, which
  /// only carries the relationship.
  Future<void> _acceptFrom(SearchResult user) async {
    final services = _services;
    if (services == null) return;

    FriendRequest? match;
    for (final request in services.friends.incomingRequests) {
      if (request.fromUser.id == user.id) {
        match = request;
        break;
      }
    }
    if (match == null) {
      // The list is stale — refetch and let the Requests tab handle it.
      await services.friends.loadRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That request is no longer pending.')),
      );
      return;
    }

    setState(() => _busyUsers.add(user.id));
    try {
      await services.friends.acceptFriendRequest(match.id);
      if (!mounted) return;
      setState(() => _relationshipOverrides[user.id] = Relationship.friend);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text("You're now friends with ${user.name}")),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not accept.');
    } finally {
      if (mounted) setState(() => _busyUsers.remove(user.id));
    }
  }

  Future<void> _requestAction(
    FriendRequest request,
    Future<void> Function() action,
    String failure,
  ) async {
    setState(() => _busyRequests.add(request.id));
    try {
      await action();
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: failure);
    } finally {
      if (mounted) setState(() => _busyRequests.remove(request.id));
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        title: Text(
          'Find friends',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: t.action,
          unselectedLabelColor: t.textMuted,
          indicatorColor: t.action,
          tabs: const [
            Tab(text: 'Suggested'),
            Tab(text: 'Search'),
            Tab(text: 'Requests'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: services.friends,
        builder: (context, _) => TabBarView(
          controller: _tabs,
          children: [
            _buildSuggested(t, services.friends),
            _buildSearch(t),
            _buildRequests(t, services.friends),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- suggested

  Widget _buildSuggested(JournalTheme t, FriendsRepository repo) {
    if (repo.suggestions.isEmpty) {
      if (repo.isLoadingSuggestions) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: RowListSkeleton(count: 4),
        );
      }
      final error = repo.lastError;
      if (error != null && error.isNetwork) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            ErrorPanel(error: error, onRetry: () => repo.loadSuggestions()),
          ],
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          EmptyStateView(
            icon: Icons.auto_awesome_outlined,
            headline: 'No suggestions yet',
            body: 'No suggestions yet — search by username.',
            actionLabel: 'Search',
            onAction: () => _tabs.animateTo(1),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => repo.loadSuggestions(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: repo.suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _buildSuggestionTile(t, repo.suggestions[index]),
      ),
    );
  }

  Widget _buildSuggestionTile(JournalTheme t, MatchSuggestion suggestion) {
    final user = suggestion.user;

    return PwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PwAvatar(name: user.name, color: user.avatarColor, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name.trim().isEmpty ? 'Unknown' : user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    if (user.handle.isNotEmpty)
                      Text(
                        user.handle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: t.textSecondary),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ScoreRing(score: suggestion.matchScore, color: user.avatarColor),
            ],
          ),
          if (suggestion.reason.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              suggestion.reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: t.textSecondary),
            ),
          ],
          if (suggestion.sharedHabits.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final habit in suggestion.sharedHabits)
                  PwChip(label: habit, color: user.avatarColor),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _buildRelationshipButton(t, user, fullWidth: true),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- search

  Widget _buildSearch(JournalTheme t) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            controller: _query,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            style: TextStyle(color: t.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by username or name',
              hintStyle: TextStyle(color: t.textMuted),
              prefixIcon: Icon(Icons.search, color: t.textMuted),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: Icon(Icons.close, color: t.textMuted),
                      onPressed: () {
                        _query.clear();
                        _onQueryChanged('');
                      },
                    ),
              filled: true,
              fillColor: t.surfaceBright,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                borderSide: BorderSide(color: t.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                borderSide: BorderSide(color: t.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                borderSide: BorderSide(color: t.action, width: 2),
              ),
            ),
          ),
        ),
        Expanded(child: _buildSearchResults(t)),
      ],
    );
  }

  Widget _buildSearchResults(JournalTheme t) {
    final error = _searchError;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ErrorPanel(
            error: error,
            onRetry: () {
              final query = _query.text.trim();
              if (query.isEmpty) return;
              setState(() => _searching = true);
              _runSearch(query);
            },
          ),
        ],
      );
    }

    if (_searching) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: RowListSkeleton(count: 3),
      );
    }

    if (!_hasSearched) {
      return const EmptyStateView(
        icon: Icons.search,
        headline: 'Search for a username',
        body: 'Type at least one character to look someone up.',
      );
    }

    if (_results.isEmpty) {
      return EmptyStateView(
        icon: Icons.person_search_outlined,
        headline: 'No matches',
        body: "No one matches '$_lastQuery'",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildSearchTile(t, _results[index]),
    );
  }

  Widget _buildSearchTile(JournalTheme t, SearchResult user) {
    return PwCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PwAvatar(name: user.name, color: user.avatarColor, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.trim().isEmpty ? 'Unknown' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                if (user.handle.isNotEmpty)
                  Text(
                    user.handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                if (user.mutualLabel.isNotEmpty)
                  Text(
                    user.mutualLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildRelationshipButton(t, user),
        ],
      ),
    );
  }

  /// The Add button, which varies by `relationship` exactly as the spec
  /// describes. `self` renders nothing at all.
  Widget _buildRelationshipButton(
    JournalTheme t,
    SearchResult user, {
    bool fullWidth = false,
  }) {
    if (_busyUsers.contains(user.id)) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final relationship = _relationshipFor(user);

    switch (relationship) {
      case Relationship.self:
        return const SizedBox.shrink();

      case Relationship.friend:
        return _disabledPill(t, 'Friends', fullWidth: fullWidth);

      case Relationship.requestSent:
        return _disabledPill(t, 'Requested', fullWidth: fullWidth);

      case Relationship.requestReceived:
        return _actionPill(
          t,
          'Accept',
          () => _acceptFrom(user),
          fullWidth: fullWidth,
        );

      case Relationship.none:
        return _actionPill(
          t,
          'Add',
          () => _sendRequest(user),
          fullWidth: fullWidth,
        );

      case Relationship.unknown:
        // Never offer an action we cannot guarantee the server will accept.
        return const SizedBox.shrink();
    }
  }

  Widget _actionPill(
    JournalTheme t,
    String label,
    VoidCallback onPressed, {
    required bool fullWidth,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: t.action,
        foregroundColor: t.onAccent(t.action),
        elevation: 0,
        minimumSize: Size(fullWidth ? double.infinity : 0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _disabledPill(JournalTheme t, String label, {required bool fullWidth}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      height: 44,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: t.inertCell,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: t.outline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: t.textMuted,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- requests

  Widget _buildRequests(JournalTheme t, FriendsRepository repo) {
    final incoming = repo.incomingRequests;
    final outgoing = repo.outgoingRequests;

    if (incoming.isEmpty && outgoing.isEmpty) {
      if (repo.isLoadingRequests) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: RowListSkeleton(count: 2),
        );
      }
      return const EmptyStateView(
        icon: Icons.mark_email_read_outlined,
        headline: 'No pending requests',
        body: 'Requests you send or receive will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => repo.loadRequests(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          if (incoming.isNotEmpty) ...[
            const SectionHeader(title: 'Incoming'),
            const SizedBox(height: 12),
            for (final request in incoming) ...[
              FriendRequestTile(
                name: request.fromUser.name,
                handle: request.fromUser.handle,
                avatarColor: request.fromUser.avatarColor,
                subtitle: request.mutualLabel,
                busy: _busyRequests.contains(request.id),
                onAccept: () => _requestAction(
                  request,
                  () => repo.acceptFriendRequest(request.id),
                  'Could not accept.',
                ),
                onDecline: () => _requestAction(
                  request,
                  () => repo.declineFriendRequest(request.id),
                  'Could not decline.',
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
          ],
          if (outgoing.isNotEmpty) ...[
            const SectionHeader(title: 'Sent'),
            const SizedBox(height: 12),
            for (final request in outgoing) ...[
              _buildOutgoingTile(t, repo, request),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOutgoingTile(
    JournalTheme t,
    FriendsRepository repo,
    FriendRequest request,
  ) {
    final user = request.toUser;
    final busy = _busyRequests.contains(request.id);

    return PwCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PwAvatar(name: user.name, color: user.avatarColor, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.trim().isEmpty ? 'Unknown' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  user.handle.isEmpty
                      ? 'Pending · ${request.timeAgo}'
                      : '${user.handle} · ${request.timeAgo}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            OutlinedButton(
              onPressed: () => _requestAction(
                request,
                () => repo.cancelFriendRequest(request.id),
                'Could not cancel.',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textSecondary,
                side: BorderSide(color: t.outline),
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
