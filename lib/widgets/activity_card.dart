import 'package:flutter/material.dart';

import '../models/friend_activity.dart';
import '../utils/journal_theme.dart';
import 'friends/pw_avatar.dart';
import 'friends/state_panels.dart';

/// One row of the friends activity feed.
///
/// The completion blurb is server-rendered ("30/30 pages"), so the row reads
/// "Taylor Mills completed 30/30 pages of Read".
class ActivityCard extends StatelessWidget {
  final FriendActivity activity;
  final VoidCallback? onTap;

  const ActivityCard({
    super.key,
    required this.activity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final habitAccent = t.accent(activity.habitColor);
    final name = activity.friendName.trim().isEmpty
        ? 'Someone'
        : activity.friendName;

    return PwCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Guarded avatar — the old version did `friendName[0]`.
          PwAvatar(
            name: activity.friendName,
            color: activity.avatarColor,
            size: 40,
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
                        text: name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' completed '),
                      TextSpan(
                        text: activity.completion,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: habitAccent,
                        ),
                      ),
                      if (activity.habitName.trim().isNotEmpty)
                        TextSpan(text: ' of ${activity.habitName}'),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  activity.timeAgo,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: habitAccent.withValues(alpha: t.tintIcon),
            ),
            alignment: Alignment.center,
            child: Text(
              activity.habitIcon.trim().isEmpty ? '•' : activity.habitIcon,
              maxLines: 1,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: habitAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
