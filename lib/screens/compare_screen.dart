import 'package:flutter/material.dart';

import '../models/comparison.dart';
import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/pw_avatar.dart';
import '../widgets/friends/state_panels.dart';

/// Head-to-head against one friend (`GET /api/friends/:id/compare`).
///
/// Never cached — a stale head-to-head is worse than a spinner, which is why
/// `FriendsRepository.compareWith` does not cache either.
class CompareScreen extends StatefulWidget {
  final String friendId;
  final String friendName;

  const CompareScreen({
    super.key,
    required this.friendId,
    this.friendName = '',
  });

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  AppServices? _services;
  FriendComparison? _comparison;
  ApiException? _error;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _load();
  }

  Future<void> _load() async {
    final services = _services;
    if (services == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final comparison = await services.friends.compareWith(widget.friendId);
      if (!mounted) return;
      setState(() {
        _comparison = comparison;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        title: Text(
          widget.friendName.trim().isEmpty
              ? 'Compare'
              : 'You vs ${widget.friendName}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
      ),
      body: _buildBody(t),
    );
  }

  Widget _buildBody(JournalTheme t) {
    final error = _error;
    if (error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [ErrorPanel(error: error, onRetry: _load)],
      );
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: RowListSkeleton(count: 4),
      );
    }

    final comparison = _comparison;
    if (comparison == null) {
      return const EmptyStateView(
        icon: Icons.compare_arrows_rounded,
        headline: 'Nothing to compare',
        body: 'Try again in a moment.',
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        children: [
          _buildScoreboard(t, comparison),
          const SizedBox(height: 24),
          if (!comparison.hasSharedHabits)
            const EmptyStateView(
              icon: Icons.join_inner_outlined,
              headline: 'No shared habits',
              body: 'No habits in common yet — add one they track to compare.',
            )
          else ...[
            SectionHeader(
              title: '${comparison.sharedHabitCount} shared '
                  '${comparison.sharedHabitCount == 1 ? 'habit' : 'habits'}',
            ),
            const SizedBox(height: 12),
            for (final habit in comparison.habits) ...[
              _buildHabitRow(t, comparison, habit),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ scoreboard

  Widget _buildScoreboard(JournalTheme t, FriendComparison comparison) {
    return PwCard(
      bright: true,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildSide(
                  t,
                  comparison.me,
                  label: 'You',
                  ahead: comparison.verdict == Verdict.meAhead,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'vs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: _buildSide(
                  t,
                  comparison.friend,
                  label: comparison.friend.name,
                  ahead: comparison.verdict == Verdict.friendAhead,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: t.action.withValues(alpha: t.isDark ? 0.20 : 0.10),
              borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
            ),
            child: Text(
              // The model already renders "You're ahead" / "X is ahead" /
              // "Dead even" using the friend's real name.
              comparison.hasSharedHabits
                  ? (comparison.isTie ? 'Dead even' : comparison.verdictLabel)
                  : comparison.verdictLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.action,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSide(
    JournalTheme t,
    ComparisonSide side, {
    required String label,
    required bool ahead,
  }) {
    final accent = t.accent(side.avatarColor);

    return Column(
      children: [
        PwAvatar(name: side.name, color: side.avatarColor, size: 52),
        const SizedBox(height: 8),
        Text(
          label.trim().isEmpty ? 'Friend' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${side.score}',
          style: TextStyle(
            fontSize: 28,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: ahead ? accent : t.textSecondary,
          ),
        ),
        Text(
          side.score == 1 ? 'win' : 'wins',
          style: TextStyle(fontSize: 11, color: t.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          '${side.streakDays} day streak',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: t.textMuted),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- habit rows

  Widget _buildHabitRow(
    JournalTheme t,
    FriendComparison comparison,
    HabitComparison habit,
  ) {
    final accent = t.accent(habit.color);
    final meColor = t.accent(comparison.me.avatarColor);
    final friendColor = t.accent(comparison.friend.avatarColor);

    return PwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
                  color: accent.withValues(alpha: t.tintIcon),
                ),
                alignment: Alignment.center,
                child: Text(
                  habit.icon.trim().isEmpty ? '•' : habit.icon,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  habit.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              if (habit.winner == Winner.tie)
                PwChip(label: 'Tie', color: habit.color)
              else
                PwChip(
                  label: habit.iWon ? 'You win' : 'They win',
                  color: habit.iWon
                      ? comparison.me.avatarColor
                      : comparison.friend.avatarColor,
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Two-sided bar: me growing leftward, the friend growing rightward.
          Row(
            children: [
              Expanded(
                child: _buildHalfBar(
                  t,
                  ratio: habit.myRatio,
                  color: meColor,
                  dimmed: habit.friendWon,
                  alignEnd: true,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildHalfBar(
                  t,
                  ratio: habit.friendRatio,
                  color: friendColor,
                  dimmed: habit.iWon,
                  alignEnd: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _label(habit.myProgress, habit.myTarget, habit.unit),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: habit.iWon ? FontWeight.w700 : FontWeight.w400,
                    color: habit.iWon ? meColor : t.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _label(habit.friendProgress, habit.friendTarget, habit.unit),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        habit.friendWon ? FontWeight.w700 : FontWeight.w400,
                    color: habit.friendWon ? friendColor : t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHalfBar(
    JournalTheme t, {
    required double ratio,
    required Color color,
    required bool dimmed,
    required bool alignEnd,
  }) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: t.progressTrack,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          // Model getters already clamp to [0,1] and guard a zero target.
          widthFactor: ratio,
          child: Container(
            decoration: BoxDecoration(
              color: dimmed ? color.withValues(alpha: 0.45) : color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
      ),
    );
  }

  static String _label(int progress, int target, String unit) {
    final suffix = unit.trim().isEmpty ? '' : ' $unit';
    return '${JournalTheme.formatCount(progress)}/'
        '${JournalTheme.formatCount(target)}$suffix';
  }
}
