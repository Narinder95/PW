import 'package:flutter/material.dart';

import '../models/friend.dart';
import '../models/friend_habit.dart';
import '../models/nudge.dart';
import '../services/api/api_exception.dart';
import '../services/api/pw_api.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/pw_avatar.dart';
import '../widgets/friends/state_panels.dart';
import 'compare_screen.dart';

/// A friend's day, loaded from `GET /api/friends/:id`.
///
/// Everything here is server data: the habit list, the completed/total count
/// and the week strip. The previous version hard-coded Steps/Hydration/Workout,
/// a `totalHabits = 6`, and a fixed `M T W T F S S` row.
class FriendDetailScreen extends StatefulWidget {
  final String friendId;

  /// The summary already in hand, when the screen was opened from the rail.
  /// Lets the header paint immediately instead of flashing a skeleton.
  final Friend? initialFriend;

  const FriendDetailScreen({
    super.key,
    required this.friendId,
    this.initialFriend,
  });

  @override
  State<FriendDetailScreen> createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  AppServices? _services;
  FriendDetail? _detail;
  ApiException? _error;
  bool _loading = true;

  /// Habit ids with a nudge/cheer in flight.
  final Set<String> _busyHabits = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _load();
  }

  Future<void> _load({bool force = false}) async {
    final services = _services;
    if (services == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail =
          await services.friends.loadFriendDetail(widget.friendId, force: force);
      if (!mounted) return;
      setState(() {
        _detail = detail;
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

  /// The best friend record available: the freshly loaded one, else the
  /// summary the caller handed in, else the repository's cached copy.
  Friend? get _friend =>
      _detail?.friend ??
      widget.initialFriend ??
      _services?.friends.friendById(widget.friendId);

  // -------------------------------------------------------------- mutations

  Future<void> _sendNudge(FriendHabit habit) async {
    final services = _services;
    final friend = _friend;
    if (services == null || friend == null) return;

    setState(() => _busyHabits.add(habit.id));
    final isCheer = habit.isCompleted;
    try {
      await services.friends.sendNudge(
        toUserId: friend.id,
        habitId: habit.id,
        habitName: habit.name,
        habitIcon: habit.icon,
        habitColor: habit.color,
        type: isCheer ? NudgeType.cheer : NudgeType.nudge,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isCheer
                  ? 'Cheered ${friend.name} on ${habit.name}'
                  : 'Nudged ${friend.name} to ${habit.name}',
            ),
          ),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      // `describeApiError` turns a 429 into
      // "Already nudged — try again in N min" using retryAfterSeconds.
      showApiErrorSnack(context, error, fallback: 'Could not send that.');
    } finally {
      if (mounted) setState(() => _busyHabits.remove(habit.id));
    }
  }

  Future<void> _confirmRemove() async {
    final services = _services;
    final friend = _friend;
    if (services == null || friend == null) return;
    final t = JournalTheme.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Remove ${friend.name}?',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        content: Text(
          "You'll both stop seeing each other's habits and activity.",
          style: TextStyle(color: t.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.incomplete,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await services.friends.removeFriend(friend.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not remove.');
    }
  }

  void _openCompare() {
    final friend = _friend;
    if (friend == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CompareScreen(
          friendId: friend.id,
          friendName: friend.name,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final friend = _friend;

    return Scaffold(
      backgroundColor: t.background,
      // A normal AppBar back button. The old floating FAB overlapped content
      // and was non-standard.
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        title: Text(
          friend?.name.trim().isNotEmpty == true ? friend!.name : 'Friend',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        actions: [
          if (friend != null)
            PopupMenuButton<String>(
              tooltip: 'More',
              color: t.background,
              onSelected: (value) {
                if (value == 'remove') _confirmRemove();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'remove',
                  child: Text(
                    'Remove friend',
                    style: TextStyle(color: t.incomplete),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(t, friend),
    );
  }

  Widget _buildBody(JournalTheme t, Friend? friend) {
    final error = _error;
    if (error != null && _detail == null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          if (error.isForbidden)
            const EmptyStateView(
              icon: Icons.lock_outline,
              headline: 'Not visible',
              body: "You can only see the habits of people you're friends with.",
            )
          else
            ErrorPanel(error: error, onRetry: () => _load(force: true)),
        ],
      );
    }

    if (friend == null && _loading) return _buildSkeleton();
    if (friend == null) {
      return const EmptyStateView(
        icon: Icons.person_off_outlined,
        headline: 'Friend not found',
        body: 'This account may have been removed.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _buildHeader(t, friend),
          const SizedBox(height: 28),
          _buildTodaysProgress(t, friend),
          const SizedBox(height: 28),
          _buildWeeklyMomentum(t, friend),
          const SizedBox(height: 28),
          _buildTodaysHabits(t, friend),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeader(JournalTheme t, Friend friend) {
    final accent = t.accent(friend.avatarColor);

    return Column(
      children: [
        PwAvatar(
          name: friend.name,
          color: friend.avatarColor,
          size: 96,
          ringValue: friend.completionPercentage,
          ringWidth: 5,
        ),
        const SizedBox(height: 16),
        Text(
          friend.name.trim().isEmpty ? 'Unknown' : friend.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        if (friend.username.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '@${friend.username}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: t.textSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (friend.streakDays > 0)
              StreakBadge(days: friend.streakDays, color: friend.avatarColor)
            else
              PwChip(label: 'No streak yet', color: friend.avatarColor),
            PwChip(
              label: friend.habitsTotal <= 0
                  ? 'No habits'
                  : '${friend.habitsCompleted}/${friend.habitsTotal} habits',
              color: friend.avatarColor,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openCompare,
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
              ),
            ),
            icon: const Icon(Icons.compare_arrows_rounded, size: 20),
            label: const Text(
              'Compare',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- progress

  Widget _buildTodaysProgress(JournalTheme t, Friend friend) {
    final accent = t.accent(friend.avatarColor);
    // `habitsRatio` guards habitsTotal == 0 on the model. devong lands here.
    final ratio = friend.habitsRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Today's Progress",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
            Text(
              friend.habitsTotal <= 0
                  ? 'No habits'
                  : '${friend.habitsCompleted}/${friend.habitsTotal} habits',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PwCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: t.progressTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                friend.habitsTotal <= 0
                    ? "${friend.name} hasn't set up any habits yet."
                    : '${(ratio * 100).round()}% of today done',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: t.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ week strip

  Widget _buildWeeklyMomentum(JournalTheme t, Friend friend) {
    final accent = t.accent(friend.avatarColor);
    final week = friend.weekData;
    final count = week.length;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Momentum',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        PwCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List<Widget>.generate(count, (index) {
              // weekData is oldest-first with index 6 = today, so the labels
              // roll with the real dates rather than a fixed Mon-Sun week.
              final date = today.subtract(Duration(days: count - 1 - index));
              final completed = week[index];
              final isToday = index == count - 1;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    JournalTheme.weekdayLetter(date),
                    style: JournalTheme.dayLetter.copyWith(
                      color: isToday ? t.textPrimary : t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: completed
                          ? accent.withValues(alpha: t.tintDotFill)
                          : t.inertCell,
                      border: Border.all(
                        color: isToday
                            ? accent.withValues(alpha: t.tintRing)
                            : t.outline,
                        width: isToday ? 2 : 1,
                      ),
                    ),
                    child: completed
                        ? Icon(Icons.check_rounded, size: 17, color: accent)
                        : null,
                  ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ habit list

  Widget _buildTodaysHabits(JournalTheme t, Friend friend) {
    final habits = _detail?.habits ?? const <FriendHabit>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's Habits",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading && habits.isEmpty)
          const RowListSkeleton(count: 3)
        else if (habits.isEmpty)
          EmptyStateView(
            icon: Icons.checklist_outlined,
            headline: 'Nothing tracked yet',
            body: "${friend.name} hasn't set up any habits yet.",
            padding: const EdgeInsets.symmetric(vertical: 24),
          )
        else
          for (final habit in habits) ...[
            _buildHabitTile(t, friend, habit),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  Widget _buildHabitTile(JournalTheme t, Friend friend, FriendHabit habit) {
    final accent = t.accent(habit.color);
    final busy = _busyHabits.contains(habit.id);
    final isCheer = habit.isCompleted;

    return PwCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                  color: accent.withValues(alpha: t.tintIcon),
                ),
                alignment: Alignment.center,
                child: Text(
                  habit.icon.trim().isEmpty ? '•' : habit.icon,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 18,
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
                      habit.name.trim().isEmpty ? 'Habit' : habit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      // Model-rendered: "1300 / 2000 mL".
                      habit.progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : OutlinedButton(
                        onPressed: () => _sendNudge(habit),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accent,
                          side: BorderSide(
                            color: accent.withValues(alpha: 0.6),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(
                          isCheer ? 'Cheer' : 'Nudge',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              // `percentage` guards target <= 0 on the model.
              value: habit.percentage,
              minHeight: 6,
              backgroundColor: t.progressTrack,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: const [
        Center(child: SkeletonBox(height: 96, circle: true)),
        SizedBox(height: 16),
        Center(child: SkeletonBox(width: 160, height: 22)),
        SizedBox(height: 10),
        Center(child: SkeletonBox(width: 100, height: 13)),
        SizedBox(height: 32),
        RowListSkeleton(count: 3),
      ],
    );
  }
}
