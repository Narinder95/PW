import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_service.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/pw_avatar.dart';
import '../widgets/friends/state_panels.dart';

/// The notification centre, grouped by day.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  AppServices? _services;
  bool _bootstrapped = false;

  /// Rows swiped away but not yet committed to the server, so Undo can put
  /// them back. Committing is deferred rather than fired-and-reversed: the
  /// contract has no "un-delete" endpoint.
  final Set<String> _pendingDismiss = <String>{};
  final Map<String, Timer> _dismissTimers = <String, Timer>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    if (!_bootstrapped) {
      _bootstrapped = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => services.notifications.refresh());
    }
  }

  @override
  void dispose() {
    // Commit anything still in flight: the user swiped it away and walked off.
    for (final entry in _dismissTimers.entries) {
      entry.value.cancel();
      _services?.notifications.delete(entry.key);
    }
    _dismissTimers.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------- actions

  Future<void> _onTap(AppNotification notification) async {
    final services = _services;
    if (services == null) return;

    if (!notification.read) {
      await services.notifications.markRead(notification.id);
    }
    if (!mounted) return;

    if (!notification.isDeepLinkable && notification.actorId == null) return;

    // Leave the notification centre, then route. The same function a tapped
    // push goes through.
    Navigator.of(context).pop();
    services.openRef(
      refType: notification.refType,
      refId: notification.refId,
      actorId: notification.actorId,
    );
  }

  void _onDismiss(AppNotification notification) {
    final services = _services;
    if (services == null) return;

    setState(() => _pendingDismiss.add(notification.id));

    _dismissTimers[notification.id]?.cancel();
    _dismissTimers[notification.id] = Timer(
      const Duration(seconds: 4),
      () => _commitDismiss(notification.id),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Notification dismissed'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _undoDismiss(notification.id),
          ),
        ),
      );
  }

  void _commitDismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    final services = _services;
    if (services == null) return;
    // Fire and forget: the service is optimistic and rolls itself back.
    unawaited(services.notifications.delete(id));
    if (mounted) setState(() => _pendingDismiss.remove(id));
  }

  void _undoDismiss(String id) {
    _dismissTimers.remove(id)?.cancel();
    if (mounted) setState(() => _pendingDismiss.remove(id));
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
          'Notifications',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: services.notifications,
            builder: (context, _) => TextButton(
              onPressed: services.notifications.unreadCount == 0
                  ? null
                  : () => services.notifications.markAllRead(),
              style: TextButton.styleFrom(
                foregroundColor: t.action,
                minimumSize: const Size(0, 44),
              ),
              child: const Text('Mark all read'),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListenableBuilder(
        listenable: services.notifications,
        builder: (context, _) => _buildBody(t, services.notifications),
      ),
    );
  }

  Widget _buildBody(JournalTheme t, NotificationService service) {
    final visible = service.notifications
        .where((n) => !_pendingDismiss.contains(n.id))
        .toList(growable: false);

    if (visible.isEmpty) {
      if (service.isLoading) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: RowListSkeleton(count: 5),
        );
      }
      final error = service.lastError;
      if (error != null && service.notifications.isEmpty) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            ErrorPanel(error: error, onRetry: () => service.refresh()),
          ],
        );
      }
      return const EmptyStateView(
        icon: Icons.notifications_none_rounded,
        headline: "You're all caught up",
        body: 'New nudges, requests and friend activity will land here.',
      );
    }

    // Group by local day, preserving the server's newest-first order.
    final rows = <Widget>[];
    String? currentGroup;
    for (final notification in visible) {
      final group = _dayLabel(notification.createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        rows
          ..add(const SizedBox(height: 8))
          ..add(SectionHeader(title: group))
          ..add(const SizedBox(height: 8));
      }
      rows
        ..add(_buildRow(t, notification))
        ..add(const SizedBox(height: 10));
    }

    return RefreshIndicator(
      onRefresh: () => service.refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: rows,
      ),
    );
  }

  Widget _buildRow(JournalTheme t, AppNotification notification) {
    final accent = t.accent(notification.resolvedColor);
    final emoji = notification.emoji;

    return Dismissible(
      key: ValueKey<String>('notification-${notification.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _onDismiss(notification),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: t.incomplete.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        ),
        child: Icon(Icons.delete_outline, color: t.incomplete),
      ),
      child: PwCard(
        onTap: () => _onTap(notification),
        padding: const EdgeInsets.all(12),
        // Unread rows get a tinted ground so the eye finds them first.
        borderColor: notification.read
            ? t.outline
            : accent.withValues(alpha: 0.40),
        bright: !notification.read,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.actorName != null)
              PwAvatar(
                name: notification.actorName!,
                color: notification.resolvedAvatarColor,
                size: 40,
              )
            else
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: t.tintIcon),
                ),
                alignment: Alignment.center,
                // An unknown `type` falls back to a generic bell rather than
                // crashing the list.
                child: emoji == null
                    ? Icon(notification.fallbackIcon, size: 20, color: accent)
                    : Text(
                        emoji,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title.trim().isEmpty
                        ? 'Notification'
                        : notification.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          notification.read ? FontWeight.w600 : FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  if (notification.body.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    notification.timeAgo,
                    style: TextStyle(fontSize: 11, color: t.textMuted),
                  ),
                ],
              ),
            ),
            if (!notification.read) ...[
              const SizedBox(width: 8),
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Today" / "Yesterday" / "31 Aug 2026".
  static String _dayLabel(DateTime timestamp) {
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(day).inDays;

    if (difference <= 0) return 'Today';
    if (difference == 1) return 'Yesterday';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }
}
