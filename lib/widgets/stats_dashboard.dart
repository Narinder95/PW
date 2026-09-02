import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../utils/journal_theme.dart';

/// Progress tiles derived from the user's real habits (`GET /api/habits`).
///
/// The old version reported a fixed 15-day streak, a 32-day longest streak,
/// 6 habits and an 87% completion rate regardless of the account. Every value
/// here is computed from [habits]; anything the contract does not expose —
/// a longest-ever streak, for instance — is simply not claimed.
class StatsDashboard extends StatelessWidget {
  final List<Habit> habits;
  final bool loading;

  const StatsDashboard({
    super.key,
    required this.habits,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    final total = habits.length;
    final doneToday = habits.where((habit) => habit.completedToday).length;

    // The server computes `streak` over the full log history; never re-derive
    // it from the 7-day weekData window.
    var bestStreak = 0;
    for (final habit in habits) {
      if (habit.streak > bestStreak) bestStreak = habit.streak;
    }

    // Guarded: a brand-new account has zero habits.
    final percentToday = total == 0 ? 0 : ((doneToday / total) * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Progress',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (loading && habits.isEmpty)
            Text(
              'Loading your habits…',
              style: TextStyle(fontSize: 13, color: t.textMuted),
            )
          else if (total == 0)
            Text(
              'No habits yet — add one on the Journal tab and your stats will '
              'appear here.',
              style: TextStyle(fontSize: 13, height: 1.4, color: t.textMuted),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _StatCard(
                  icon: '🔥',
                  label: 'Best Streak',
                  value: '$bestStreak',
                  unit: bestStreak == 1 ? 'day' : 'days',
                  color: const Color(0xFFFF7043),
                ),
                _StatCard(
                  icon: '✅',
                  label: 'Done Today',
                  value: '$doneToday',
                  unit: 'of $total',
                  color: const Color(0xFF2E7D32),
                ),
                _StatCard(
                  icon: '📋',
                  label: 'Active Habits',
                  value: '$total',
                  unit: total == 1 ? 'habit' : 'habits',
                  color: const Color(0xFF00BCD4),
                ),
                _StatCard(
                  icon: '📈',
                  label: "Today's Rate",
                  value: '$percentToday',
                  unit: '%',
                  color: const Color(0xFF7E57C2),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(color);

    return Container(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.tintBadge),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
        borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: t.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
