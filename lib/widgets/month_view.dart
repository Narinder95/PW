import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../utils/journal_theme.dart';

class MonthView extends StatefulWidget {
  final Habit habit;

  const MonthView({Key? key, required this.habit}) : super(key: key);

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  late DateTime currentMonth;

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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    currentMonth = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + delta);
    });
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
        _buildMonthGrid(t),
      ],
    );
  }

  // --------------------------------------------------------------- month nav
  Widget _buildMonthNav(JournalTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildNavButton(t, Icons.chevron_left_rounded, () => _shiftMonth(-1)),
        Text(
          '${_monthNames[currentMonth.month - 1]} ${currentMonth.year}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        _buildNavButton(t, Icons.chevron_right_rounded, () => _shiftMonth(1)),
      ],
    );
  }

  Widget _buildNavButton(JournalTheme t, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 20, color: t.textSecondary),
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
    final daysInMonth = _daysIn(currentMonth);
    // DateTime.weekday is 1 = Monday .. 7 = Sunday, matching the Monday-first
    // header above.
    final leading = DateTime(currentMonth.year, currentMonth.month, 1).weekday - 1;
    final daysInPrevMonth = _daysIn(DateTime(currentMonth.year, currentMonth.month - 1));

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

  /// A cell with no state to report: an adjacent month, or a day that hasn't
  /// happened yet.
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
    final accent = t.accent(widget.habit.color);
    final date = DateTime(currentMonth.year, currentMonth.month, day);
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

    if (_completedOn(date)) {
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

  // -------------------------------------------------------------------- data
  int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

  /// Completion for a past day.
  ///
  /// The last 7 days come from the habit's real `weekData`; anything older is
  /// still placeholder until history is persisted.
  bool _completedOn(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysAgo = today.difference(date).inDays;
    final count = widget.habit.weekData.length;

    if (daysAgo >= 0 && daysAgo < count) {
      return widget.habit.weekData[count - 1 - daysAgo];
    }

    // TODO: Replace with persisted history once a data layer exists.
    return date.day % 3 != 0;
  }
}
