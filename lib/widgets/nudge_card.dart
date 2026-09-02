import 'package:flutter/material.dart';

import '../models/nudge.dart';
import '../utils/journal_theme.dart';
import 'friends/pw_avatar.dart';
import 'friends/state_panels.dart';

/// A received nudge or cheer, with the Accept action.
///
/// `cheer` and `nudge` read differently — "X cheered you on Steps" vs
/// "X nudged you to Meditate" — and the optional free-text message is shown
/// when the sender wrote one.
class NudgeCard extends StatelessWidget {
  final Nudge nudge;
  final VoidCallback onAccept;

  const NudgeCard({
    super.key,
    required this.nudge,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(nudge.habitColor);
    final from = nudge.fromUserName.trim().isEmpty
        ? 'A friend'
        : nudge.fromUserName;
    final message = nudge.message?.trim();

    return PwCard(
      borderColor: accent.withValues(alpha: 0.35),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: t.tintIcon),
            ),
            alignment: Alignment.center,
            child: Icon(
              nudge.isCheer
                  ? Icons.celebration_outlined
                  : Icons.waving_hand_outlined,
              color: accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: from,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text: nudge.isCheer
                            ? ' cheered you on '
                            : ' nudged you to ',
                      ),
                      TextSpan(
                        text: nudge.habitName.trim().isEmpty
                            ? 'a habit'
                            : nudge.habitName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, height: 1.35, color: t.textPrimary),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '"$message"',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: t.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  nudge.timeAgo,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: onAccept,
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: t.onAccent(accent),
              elevation: 0,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Row for a friend request awaiting a decision, with Accept / Decline.
class FriendRequestTile extends StatelessWidget {
  final String name;
  final String handle;
  final Color avatarColor;
  final String subtitle;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  /// Shown instead of the buttons while an action is in flight.
  final bool busy;

  const FriendRequestTile({
    super.key,
    required this.name,
    required this.handle,
    required this.avatarColor,
    this.subtitle = '',
    this.onAccept,
    this.onDecline,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return PwCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          PwAvatar(name: name, color: avatarColor, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.trim().isEmpty ? 'Unknown' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                if (handle.isNotEmpty)
                  Text(
                    handle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textSecondary),
                  ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.textMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            if (onDecline != null)
              IconButton(
                onPressed: onDecline,
                tooltip: 'Decline',
                iconSize: 22,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
                icon: Icon(Icons.close_rounded, color: t.textMuted),
              ),
            if (onAccept != null)
              ElevatedButton(
                onPressed: onAccept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.action,
                  foregroundColor: t.onAccent(t.action),
                  elevation: 0,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text(
                  'Accept',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
