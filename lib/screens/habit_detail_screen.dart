import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_month_progress.dart';
import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/state_panels.dart';
import '../widgets/month_view.dart';

/// Full-page stats view for one habit, reached by tapping its [HabitCard].
///
/// Replaces the old inline "expand for a calendar" affordance: this page adds
/// real completion-rate stats (last 7 days, and the browsable month) on top
/// of the calendar, and moves the "Log Activity" action here too, since the
/// card itself no longer opens a sheet on tap.
class HabitDetailScreen extends StatefulWidget {
  final Habit habit;

  /// Same contract as [HabitCard.onLog]: sets the day's progress. Null hides
  /// the Log Activity button entirely (mirrors the old card's behaviour).
  final Future<void> Function(int progress)? onLog;

  const HabitDetailScreen({super.key, required this.habit, this.onLog});

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  AppServices? _services;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  HabitMonthReport? _report;
  ApiException? _error;
  bool _loading = true;

  Habit get habit => widget.habit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _loadMonth();
  }

  Future<void> _loadMonth() async {
    final services = _services;
    if (services == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await services.api.getHabitsMonth(month: _selectedMonth);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
      // The new month's data hasn't arrived yet — showing the previous
      // month's grid under the new header would misrepresent it.
      _report = null;
    });
    _loadMonth();
  }

  HabitMonthProgress? get _monthProgress {
    final report = _report;
    if (report == null) return null;
    for (final entry in report.habits) {
      if (entry.id == habit.id) return entry;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(habit.color);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(habit.name),
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            _buildHeaderCard(t, accent),
            const SizedBox(height: 16),
            if (widget.onLog != null) ...[
              _buildLogButton(t, accent),
              const SizedBox(height: 20),
            ],
            _buildChartCard(t, accent),
            const SizedBox(height: 20),
            _buildCalendarCard(t),
            const SizedBox(height: 28),
            _buildBackButton(t),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ header
  Widget _buildHeaderCard(JournalTheme t, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline, width: 1),
        boxShadow: t.shadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TODAY'S LOG",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      JournalTheme.formatCount(habit.progress),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.0,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '/ ${JournalTheme.formatCount(habit.target)} ${habit.unit}',
                      style: t.subhead,
                    ),
                  ],
                ),
                if (habit.streak > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: t.tintBadge),
                      borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
                    ),
                    child: Text(
                      '🔥 ${habit.streak} DAY STREAK',
                      style: TextStyle(
                        fontSize: JournalTheme.sizeUnit,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- log button
  Widget _buildLogButton(JournalTheme t, Color accent) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _showLogSheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: t.onAccent(accent),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          ),
        ),
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text('Log Activity', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _showLogSheet() async {
    final t = JournalTheme.of(context);
    final accent = t.accent(habit.color);
    final progressController = TextEditingController(text: '${habit.progress}');

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: t.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: progressController,
                autofocus: true,
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
                    borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                    borderSide: BorderSide(color: t.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                    borderSide: BorderSide(color: t.outline),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: t.onAccent(accent),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                    ),
                  ),
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
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
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final parsed = int.tryParse(progressController.text.trim()) ?? habit.progress;
    progressController.dispose();
    if (confirmed != true || !mounted) return;

    await widget.onLog?.call(parsed < 0 ? 0 : parsed);
    // The habit list this page was pushed from now has the fresh value; this
    // page's own `habit` copy is a snapshot and won't update in place, so
    // returning to it is simpler and more honest than showing stale numbers.
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------ chart
  Widget _buildChartCard(JournalTheme t, Color accent) {
    final error = _error;
    if (error != null && _report == null) {
      // The calendar card below already renders this same error with a
      // retry — no need to show it twice.
      return const SizedBox.shrink();
    }

    final progressData = _monthProgress?.progressData;
    final ready = _monthProgress != null;

    if (_loading && !ready) {
      return const SkeletonBox(width: double.infinity, height: 160);
    }

    final values = (progressData ?? const <int?>[])
        .whereType<int>()
        .toList(growable: false);
    final average = values.isEmpty
        ? null
        : values.reduce((a, b) => a + b) / values.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DAILY PROGRESS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: t.textMuted,
                ),
              ),
              Text(
                average == null
                    ? 'No data yet'
                    : 'Avg ${JournalTheme.formatCount(average.round())} ${habit.unit}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            width: double.infinity,
            child: values.isEmpty
                ? Center(
                    child: Text(
                      'Log a few days to see the trend',
                      style: TextStyle(fontSize: 12, color: t.textMuted),
                    ),
                  )
                : CustomPaint(
                    painter: _ProgressChartPainter(
                      month: _selectedMonth,
                      progressData: progressData ?? const <int?>[],
                      target: habit.target,
                      accent: accent,
                      theme: t,
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- calendar
  Widget _buildCalendarCard(JournalTheme t) {
    final error = _error;
    if (error != null && _report == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surfaceBright,
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
          border: Border.all(color: t.outline, width: 1),
        ),
        child: ErrorPanel(error: error, onRetry: _loadMonth),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline, width: 1),
      ),
      child: MonthView(
        habit: habit,
        month: _selectedMonth,
        monthCompletion: _monthProgress?.monthData,
        loading: _loading,
        onPrevMonth: () => _shiftMonth(-1),
        onNextMonth: () => _shiftMonth(1),
      ),
    );
  }

  // ------------------------------------------------------------------- back
  Widget _buildBackButton(JournalTheme t) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textSecondary,
          side: BorderSide(color: t.outline),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Back', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Bar chart of one month's raw logged values, with a dashed target line.
///
/// A day with no log row draws no bar at all — a `0`-height bar would read as
/// "logged zero", which is a different fact from "never logged". A day after
/// today is skipped the same way, since it has no data by definition.
class _ProgressChartPainter extends CustomPainter {
  final DateTime month;
  final List<int?> progressData;
  final int target;
  final Color accent;
  final JournalTheme theme;

  _ProgressChartPainter({
    required this.month,
    required this.progressData,
    required this.target,
    required this.accent,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progressData.isEmpty) return;

    const labelSpace = 16.0;
    final chartHeight = size.height - labelSpace;
    if (chartHeight <= 0) return;

    final loggedValues = progressData.whereType<int>();
    final maxLogged = loggedValues.isEmpty
        ? 0
        : loggedValues.reduce((a, b) => a > b ? a : b);
    // Headroom above the tallest bar/target line so nothing touches the top
    // edge; guards target == 0 and an all-empty month the same way.
    final scale = math.max(target, maxLogged) * 1.15;
    final maxValue = scale <= 0 ? 1.0 : scale;

    final days = progressData.length;
    const gapFraction = 0.25;
    final slot = size.width / days;
    final barWidth = slot * (1 - gapFraction);

    final metPaint = Paint()..color = accent;
    final shortPaint = Paint()..color = accent.withValues(alpha: 0.4);
    final noDataPaint = Paint()..color = theme.textMuted.withValues(alpha: 0.25);

    for (var i = 0; i < days; i++) {
      final value = progressData[i];
      final x = i * slot + (slot - barWidth) / 2;

      if (value == null) {
        // A faint baseline tick, not a bar — there is nothing to plot.
        canvas.drawRect(
          Rect.fromLTWH(x, chartHeight - 2, barWidth, 2),
          noDataPaint,
        );
        continue;
      }

      final barHeight = math.max(2.0, chartHeight * (value / maxValue).clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromLTWH(x, chartHeight - barHeight, barWidth, barHeight),
        value >= target ? metPaint : shortPaint,
      );
    }

    _drawTargetLine(canvas, size.width, chartHeight, target / maxValue);
    _drawDayLabels(canvas, size.width, chartHeight, days);
  }

  void _drawTargetLine(Canvas canvas, double width, double chartHeight, double fraction) {
    if (fraction <= 0 || fraction >= 1) return;
    final y = chartHeight * (1 - fraction);
    final paint = Paint()
      ..color = theme.textSecondary.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dash, width), y), paint);
      x += dash + gap;
    }
  }

  void _drawDayLabels(Canvas canvas, double width, double chartHeight, int days) {
    final labelDays = <int>{1, (days / 2).round(), days};
    for (final day in labelDays) {
      if (day < 1 || day > days) continue;
      final x = (day - 1 + 0.5) * (width / days);
      final tp = TextPainter(
        text: TextSpan(
          text: '$day',
          style: TextStyle(fontSize: 9, color: theme.textMuted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, chartHeight + 3));
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressChartPainter oldDelegate) =>
      !identical(oldDelegate.progressData, progressData) ||
      oldDelegate.target != target ||
      oldDelegate.accent != accent ||
      oldDelegate.theme.isDark != theme.isDark;
}
