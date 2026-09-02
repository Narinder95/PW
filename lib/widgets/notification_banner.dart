import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../utils/journal_theme.dart';
import 'app_scope.dart';
import 'friends/pw_avatar.dart';

/// Shows a transient banner whenever `NotificationService` delivers a new
/// notification, on whichever screen happens to be visible.
///
/// It renders into the root navigator's [Overlay] rather than into the widget
/// tree, so it floats above pushed routes and costs the layout nothing. Tapping
/// it routes through [AppServices.openRef] — the same function a tapped push
/// uses.
class NotificationBannerHost extends StatefulWidget {
  final AppServices services;
  final Widget child;

  const NotificationBannerHost({
    super.key,
    required this.services,
    required this.child,
  });

  @override
  State<NotificationBannerHost> createState() => _NotificationBannerHostState();
}

class _NotificationBannerHostState extends State<NotificationBannerHost> {
  StreamSubscription<AppNotification>? _subscription;
  OverlayEntry? _entry;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NotificationBannerHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.services, widget.services)) _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription =
        widget.services.notifications.onNotification.listen(_show);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _timer?.cancel();
    _removeEntry();
    super.dispose();
  }

  void _show(AppNotification notification) {
    final overlay = widget.services.navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    _removeEntry();
    final entry = OverlayEntry(
      builder: (context) => _Banner(
        notification: notification,
        onDismiss: _removeEntry,
        onTap: () {
          _removeEntry();
          widget.services.openRef(
            refType: notification.refType,
            refId: notification.refId,
            actorId: notification.actorId,
          );
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);

    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 4), _removeEntry);
  }

  void _removeEntry() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Banner extends StatefulWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _Banner({
    required this.notification,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final notification = widget.notification;
    final accent = t.accent(notification.resolvedColor);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -1),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: ValueKey<String>('banner-${notification.id}'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius:
                      BorderRadius.circular(JournalTheme.radiusCard),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.isDark
                          ? const Color(0xFF23261F)
                          : Colors.white,
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusCard),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: t.isDark ? 0.45 : 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (notification.actorName != null)
                          PwAvatar(
                            name: notification.actorName!,
                            color: notification.resolvedAvatarColor,
                            size: 36,
                          )
                        else
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: t.tintIcon),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              notification.fallbackIcon,
                              size: 18,
                              color: accent,
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notification.title.trim().isEmpty
                                    ? 'Notification'
                                    : notification.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                              if (notification.body.trim().isNotEmpty)
                                Text(
                                  notification.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: t.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onDismiss,
                          tooltip: 'Dismiss',
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          icon: Icon(Icons.close, size: 18, color: t.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
