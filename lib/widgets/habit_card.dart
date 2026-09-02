import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../utils/journal_theme.dart';
import 'month_view.dart';

class HabitCard extends StatefulWidget {
  final Habit habit;

  /// Called with the day's new total when the user logs progress.
  ///
  /// `POST /api/habits/:id/log` **sets** the day's progress rather than
  /// incrementing it, so this is an absolute value. Null leaves the sheet's
  /// log affordance out entirely.
  final Future<void> Function(int progress)? onLog;

  const HabitCard({super.key, required this.habit, this.onLog});

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> {
  bool isExpanded = false;

  Habit get habit => widget.habit;

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(habit.color);

    return GestureDetector(
      onTap: () => _showHabitDetailModal(context),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
          border: Border.all(color: t.outline, width: 1),
          boxShadow: t.shadow,
        ),
        // Clipped so the progress rail bleeds into the bottom corners.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildHeader(t, accent),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildWeekDots(t, accent),
              ),
              const SizedBox(height: 14),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                  child: MonthView(habit: habit),
                ),
              _buildProgressRail(t, accent),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ header
  Widget _buildHeader(JournalTheme t, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Accent-tinted icon tile
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: t.tintIcon),
            borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          ),
          child: Center(
            child: Text(
              habit.icon,
              style: const TextStyle(fontSize: JournalTheme.sizeEmoji),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Name + target
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.name,
                  style: t.habitName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '/ ${JournalTheme.formatCount(habit.target)} ${habit.unit}',
                  style: t.habitTarget,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Chevron + value + streak
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => setState(() => isExpanded = !isExpanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 2),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 24,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ),
            Text(
              JournalTheme.formatCount(habit.progress),
              style: t.habitValue(accent),
            ),
            if (habit.streak > 0) ...[
              const SizedBox(height: 4),
              _buildStreakChip(t, accent),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStreakChip(JournalTheme t, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.tintBadge),
        borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
      ),
      child: Text(
        '🔥 ${habit.streak} DAY STREAK',
        style: TextStyle(
          fontSize: JournalTheme.sizeUnit,
          height: 14 / JournalTheme.sizeUnit,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: accent,
        ),
      ),
    );
  }

  // --------------------------------------------------------------- week dots
  //
  // `weekData` is the last 7 days ending today, so index 6 is today and the
  // labels roll with the date rather than sitting on a fixed Mon-Sun week.
  // This keeps Habit.streak / completedToday reading the same data they always
  // have.
  Widget _buildWeekDots(JournalTheme t, Color accent) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final count = habit.weekData.length;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(count, (i) {
        final date = today.subtract(Duration(days: count - 1 - i));
        final completed = habit.weekData[i];
        final isToday = i == count - 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(t, accent, completed: completed, isToday: isToday),
            const SizedBox(height: 5),
            Text(
              JournalTheme.weekdayLetter(date),
              style: JournalTheme.dayLetter.copyWith(
                color: completed
                    ? t.textSecondary
                    : isToday
                        ? t.textPrimary
                        : t.textMuted.withValues(alpha: 0.7),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildDot(
    JournalTheme t,
    Color accent, {
    required bool completed,
    required bool isToday,
  }) {
    // Done: filled accent with a contrasting pip.
    if (completed) {
      final fill = accent.withValues(alpha: t.tintDotFill);
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              // The pip sits on a tint over the card, not on solid accent, so
              // it follows the ground rather than the fill.
              color: t.isDark ? t.textPrimary : Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    // Today, still open: accent ring around a soft pip.
    if (isToday) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: accent.withValues(alpha: t.tintRing),
            width: 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: t.tintDotFill),
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
    }

    // Missed: hollow, barely-there.
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.tintDotIdle),
        shape: BoxShape.circle,
        border: Border.all(
          color: accent.withValues(alpha: t.tintDotBorder),
          width: 1,
        ),
      ),
    );
  }

  // ----------------------------------------------------------- progress rail
  Widget _buildProgressRail(JournalTheme t, Color accent) {
    return Container(
      height: JournalTheme.progressHeight,
      width: double.infinity,
      color: t.progressTrack,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          // completionPercentage is already clamped to 0..1 on the model.
          widthFactor: habit.completionPercentage,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(color: accent),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- sheet
  void _showHabitDetailModal(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(habit.color);
    final onLog = widget.onLog;
    final progressController =
        TextEditingController(text: '${habit.progress}');

    showModalBottomSheet(
      context: context,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: t.tintIcon),
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusTile),
                    ),
                    child: Center(
                      child: Text(
                        habit.icon,
                        style:
                            const TextStyle(fontSize: JournalTheme.sizeEmoji),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(habit.name, style: t.headline),
                        const SizedBox(height: 2),
                        Text(
                          '${JournalTheme.formatCount(habit.progress)} of '
                          '${JournalTheme.formatCount(habit.target)} ${habit.unit}',
                          style: t.subhead,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (onLog != null) ...[
                TextField(
                  controller: progressController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: t.textPrimary),
                  decoration: InputDecoration(
                    labelText: "Today's total",
                    suffixText: habit.unit,
                    labelStyle: TextStyle(color: t.textSecondary),
                    suffixStyle: TextStyle(color: t.textMuted),
                    filled: true,
                    fillColor: t.surfaceBright,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusTile),
                      borderSide: BorderSide(color: t.outline),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusTile),
                      borderSide: BorderSide(color: t.outline),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: t.onAccent(accent),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusTile),
                    ),
                  ),
                  onPressed: onLog == null
                      ? () => Navigator.pop(context)
                      : () {
                          // The endpoint sets the day's total, so a negative
                          // or unparseable entry falls back to no change.
                          final parsed = int.tryParse(
                                progressController.text.trim(),
                              ) ??
                              habit.progress;
                          Navigator.pop(context);
                          onLog(parsed < 0 ? 0 : parsed);
                        },
                  child: const Text(
                    'Log Activity',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: t.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(progressController.dispose);
  }
}
