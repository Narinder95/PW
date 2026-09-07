import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../utils/journal_theme.dart';

/// A calendar grid for one month of a habit's completion history.
///
/// Purely presentational: the caller owns which month is selected and fetches
/// its data (`GET /api/habits/month`), passing the result in as
/// [monthCompletion]. There is no synthetic fallback for a day the server
/// didn't report on — it renders as "no data", the same as a day before the
/// habit existed.
class MonthView extends StatelessWidget {
  final Habit habit;

  /// First-of-month anchor for the month being displayed.
  final DateTime month;

  /// `true` (target met), `false` (missed), or `null` (no data) per day of
  /// [month], oldest first. Null while the month's data hasn't loaded yet.
  final List<bool?>? monthCompletion;

  final bool loading;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;

  const MonthView({
    super.key,
    required this.habit,
    required this.month,
    required this.monthCompletion,
    required this.loading,
    required this.onPrevMonth,
    required this.onNextMonth,
  });

  static const List<String> _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  bool get _canGoToNextMonth {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    return month.isBefore(currentMonth);
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMonthNav(t),
        const SizedBox(height: 10),
        _buildWeekdayHeader(t),
        const SizedBox(height: 6),
        if (loading && monthCompletion == null)
          const _MonthGridSkeleton()
        else
          _buildMonthGrid(t),
      ],
    );
  }

  // --------------------------------------------------------------- month nav
  Widget _buildMonthNav(JournalTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildNavButton(t, Icons.chevron_left_rounded, onPrevMonth),
        Text(
          '${_monthNames[month.month - 1]} ${month.year}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        _buildNavButton(
          t,
          Icons.chevron_right_rounded,
          _canGoToNextMonth ? onNextMonth : null,
        ),
      ],
    );
  }

  Widget _buildNavButton(JournalTheme t, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? t.textMuted.withValues(alpha: 0.3) : t.textSecondary,
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader(JournalTheme t) {
    return Row(
      children: _weekdayLetters
          .map(
            (letter) => Expanded(
              child: Center(
                child: Text(
                  letter,
                  style: JournalTheme.dayLetter.copyWith(color: t.textMuted),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // -------------------------------------------------------------------- grid
  Widget _buildMonthGrid(JournalTheme t) {
    final daysInMonth = _daysIn(month);
    // DateTime.weekday is 1 = Monday .. 7 = Sunday, matching the Monday-first
    // header above.
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInPrevMonth = _daysIn(DateTime(month.year, month.month - 1));

    // Pad the tail so the final week is a complete row.
    final used = leading + daysInMonth;
    final totalCells = ((used + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        mainAxisExtent: 32,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        if (index < leading) {
          // Trailing days of the previous month.
          return _buildInertCell(t, daysInPrevMonth - leading + index + 1);
        }
        if (index >= leading + daysInMonth) {
          // Leading days of the next month.
          return _buildInertCell(t, index - leading - daysInMonth + 1);
        }

        final day = index - leading + 1;
        return _buildDayCell(t, day);
      },
    );
  }

  /// A cell with no state to report: an adjacent month, a day that hasn't
  /// happened yet, or one the server has no record for.
  Widget _buildInertCell(JournalTheme t, int day) {
    return Container(
      decoration: BoxDecoration(
        color: t.inertCell,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCell),
      ),
      child: Center(
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: JournalTheme.sizeUnit,
            color: t.textMuted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildDayCell(JournalTheme t, int day) {
    final accent = t.accent(habit.color);
    final date = DateTime(month.year, month.month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Today gets a ring rather than a verdict — the day isn't over.
    if (date == today) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(JournalTheme.radiusCell),
          border: Border.all(color: accent, width: 2),
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: JournalTheme.sizeUnit,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        ),
      );
    }

    // Days that haven't happened yet carry no state.
    if (date.isAfter(today)) {
      return _buildInertCell(t, day);
    }

    final completion = monthCompletion;
    final state = (completion != null && day - 1 < completion.length)
        ? completion[day - 1]
        : null;

    if (state == true) {
      final ink = t.onAccent(accent);
      return Container(
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(JournalTheme.radiusCell),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: JournalTheme.sizeUnit,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            Positioned(
              bottom: 4,
              child: Container(
                width: 3,
                height: 3,
                decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      );
    }

    if (state == false) {
      return Container(
        decoration: BoxDecoration(
          color: t.incomplete.withValues(alpha: t.tintMissedCell),
          borderRadius: BorderRadius.circular(JournalTheme.radiusCell),
        ),
        child: Center(
          child: Text(
            '$day',
            style: TextStyle(
              fontSize: JournalTheme.sizeUnit,
              color: t.incomplete,
            ),
          ),
        ),
      );
    }

    // state == null: no data for a day that already happened — the server
    // has no record (before the habit existed, or the month hasn't loaded).
    return _buildInertCell(t, day);
  }

  int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;
}

class _MonthGridSkeleton extends StatelessWidget {
  const _MonthGridSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        mainAxisExtent: 32,
      ),
      itemCount: 35,
      itemBuilder: (context, index) => Container(
        decoration: BoxDecoration(
          color: t.inertCell,
          borderRadius: BorderRadius.circular(JournalTheme.radiusCell),
        ),
      ),
    );
  }
}
