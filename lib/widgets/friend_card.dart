import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../utils/journal_theme.dart';
import 'friends/pw_avatar.dart';
import 'friends/state_panels.dart';

/// One friend in the horizontal rail on the Friends tab.
///
/// Rewritten off the theme tokens: the old version filled the card with
/// `Colors.white.withOpacity(0.08)`, which is invisible against the light
/// ground, and indexed `friend.name[0]`, which range-errors on an empty name.
class FriendCard extends StatelessWidget {
  final Friend friend;
  final VoidCallback onTap;

  const FriendCard({
    super.key,
    required this.friend,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(friend.avatarColor);

    return SizedBox(
      width: 140,
      child: PwCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        borderColor: accent.withValues(alpha: t.isDark ? 0.28 : 0.22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PwAvatar(
              // `completionPercentage` is parsed clamped to [0,1] by the model.
              name: friend.name,
              color: friend.avatarColor,
              size: 52,
              ringValue: friend.completionPercentage,
              ringWidth: 4,
            ),
            const SizedBox(height: 10),
            if (friend.streakDays > 0)
              StreakBadge(days: friend.streakDays, color: friend.avatarColor)
            else
              // devong: streak 0. A dash keeps the card the same height as its
              // neighbours instead of collapsing the layout.
              Text(
                'No streak yet',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
            const SizedBox(height: 10),
            Text(
              friend.name.trim().isEmpty ? 'Unknown' : friend.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              // habitsTotal is legitimately 0 for a friend with no habits.
              // Rendered as text, never divided — the ring above already used
              // the server's own ratio.
              friend.habitsTotal <= 0
                  ? 'No habits yet'
                  : '${friend.habitsCompleted}/${friend.habitsTotal} habits',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: t.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
