import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/habit_month_progress.dart';
import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import 'friends/state_panels.dart';

/// Fraction of the hub radius each month arrow sits from the hub's centre.
/// Shared by the widget's tap hit-test and the painter's chevron drawing so
/// the tappable area always lines up with what's actually on screen.
const double _hubArrowOffsetFraction = 0.72;

/// The Journal tab's hero card: a 270° radial fan where each ring is one
/// habit and each wedge along the ring is one day of the month, filled green
/// if that habit was completed that day and red if it was missed.
///
/// Habit 1 is the outermost ring, stacking inward; the open top-left quadrant
/// (the 90° the fan doesn't use) carries a numbered legend with a connector
/// line running from each habit's name to where its ring begins. The centre
/// hub mirrors the month/year, and the outer rim is numbered day 1 through
/// the last day of the month, sweeping clockwise from the top.
class HabitRadialCard extends StatelessWidget {
  final HabitMonthReport? report;
  final bool loading;
  final ApiException? error;
  final VoidCallback? onRetry;

  /// First-of-month anchor for the currently displayed month.
  final DateTime selectedMonth;

  /// Steps the displayed month back/forward one at a time. The card itself
  /// disables the forward arrow (drawn dim, not tappable) once
  /// [selectedMonth] is the current month — there is nothing to show beyond
  /// today, so [onNextMonth] is simply not invoked past that point.
  final VoidCallback? onPrevMonth;
  final VoidCallback? onNextMonth;

  const HabitRadialCard({
    super.key,
    required this.report,
    required this.loading,
    required this.error,
    required this.selectedMonth,
    this.onRetry,
    this.onPrevMonth,
    this.onNextMonth,
  });

  static const List<String> _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return selectedMonth.year == now.year && selectedMonth.month == now.month;
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline, width: 1),
        boxShadow: t.shadow,
      ),
      child: _buildBody(t),
    );
  }

  // -------------------------------------------------------------------- body
  Widget _buildBody(JournalTheme t) {
    final err = error;
    if (err != null && report == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ErrorPanel(error: err, onRetry: onRetry ?? () {}),
      );
    }

    if (loading && report == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SkeletonBox(width: 220, height: 140, radius: 70)),
      );
    }

    final habits = report?.habits ?? const <HabitMonthProgress>[];
    if (habits.isEmpty) {
      return const EmptyStateView(
        icon: Icons.donut_large_rounded,
        headline: 'Nothing to chart yet',
        body: 'Track a habit below to see your month build up here.',
        padding: EdgeInsets.symmetric(vertical: 20),
      );
    }

    final days = report!.days;
    final todayDay = _isCurrentMonth ? DateTime.now().day : null;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => _handleHubTap(details.localPosition, side),
                child: CustomPaint(
                  painter: _RadialHabitPainter(
                    habits: habits,
                    days: days,
                    todayDay: todayDay,
                    theme: t,
                    monthAbbrev: _monthAbbrev[selectedMonth.month - 1],
                    year: '${selectedMonth.year}',
                    isCurrentMonth: _isCurrentMonth,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildColorKey(t),
      ],
    );
  }

  /// Hit-tests a tap against the hub's two month arrows. The geometry here
  /// must match `_RadialHabitPainter.paint`'s hub sizing exactly, or the
  /// tappable area drifts from what's actually drawn.
  void _handleHubTap(Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    const labelMargin = 15.0;
    final outerR = side / 2 - labelMargin;
    final innerR = math.max(40.0, outerR * 0.3);
    final hubR = innerR - 6;
    if (hubR <= 10) return;

    const hitRadius = 22.0;
    final arrowOffset = hubR * _hubArrowOffsetFraction;
    final leftCentre = Offset(center.dx - arrowOffset, center.dy);
    final rightCentre = Offset(center.dx + arrowOffset, center.dy);

    if ((local - leftCentre).distance <= hitRadius) {
      onPrevMonth?.call();
    } else if ((local - rightCentre).distance <= hitRadius && !_isCurrentMonth) {
      onNextMonth?.call();
    }
  }

  // ---------------------------------------------------------------- legend
  Widget _buildColorKey(JournalTheme t) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _colorKeyItem(t, t.complete, 'Done'),
        const SizedBox(width: 16),
        _colorKeyItem(t, t.incomplete, 'Missed'),
        const SizedBox(width: 16),
        _colorKeyItem(t, t.inertCell, 'Upcoming', outlined: true),
      ],
    );
  }

  Widget _colorKeyItem(JournalTheme t, Color color, String label, {bool outlined = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: outlined ? Border.all(color: t.outline) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: t.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Draws the 270° concentric-ring fan, its embedded habit legend, the day
/// rim, and the centre hub.
///
/// Geometry: the painted square is split so the ring system (a 270° sweep
/// starting at 12 o'clock and running clockwise to 9 o'clock) occupies the
/// bottom-right three-quarters, leaving the top-left quarter empty for the
/// legend. Angles follow the "0°=12 o'clock, clockwise" convention (matching
/// how people read a clock face) rather than Flutter's raw "0 rad=3 o'clock"
/// one; [_toRadians] does the one-line conversion between them.
class _RadialHabitPainter extends CustomPainter {
  final List<HabitMonthProgress> habits;
  final int days;
  final int? todayDay;
  final JournalTheme theme;
  final String monthAbbrev;
  final String year;
  final bool isCurrentMonth;

  _RadialHabitPainter({
    required this.habits,
    required this.days,
    required this.todayDay,
    required this.theme,
    required this.monthAbbrev,
    required this.year,
    required this.isCurrentMonth,
  });

  static const double _totalSweepDeg = 270;
  static const double _gapDeg = 0.5;

  /// Flutter's `drawArc` measures radians from 3 o'clock, clockwise-positive
  /// — exactly a -90° rotation of the "0°=12 o'clock" convention used
  /// throughout this painter.
  static double _toRadians(double clockDeg) => (clockDeg - 90) * math.pi / 180;

  static Offset _polar(Offset center, double radius, double clockDeg) {
    final rad = _toRadians(clockDeg);
    return center + Offset(radius * math.cos(rad), radius * math.sin(rad));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (habits.isEmpty || days <= 0) return;

    final side = math.min(size.width, size.height);
    final center = Offset(side / 2, side / 2);
    const labelMargin = 15.0;
    final outerR = side / 2 - labelMargin;
    final innerR = math.max(40.0, outerR * 0.3);
    final ringThickness = (outerR - innerR) / habits.length;
    if (ringThickness <= 0) return;

    final angleStep = _totalSweepDeg / days;
    final dayGap = math.min(_gapDeg, angleStep * 0.25);

    // Ring 0 (habit 1) is outermost, stacking inward.
    for (var r = 0; r < habits.length; r++) {
      final habit = habits[r];
      final ringOuter = outerR - r * ringThickness;
      final strokeWidth = math.max(1.0, ringThickness - 1.5);
      final midR = ringOuter - ringThickness / 2;

      for (var day = 1; day <= days; day++) {
        final idx = day - 1;
        final state = idx < habit.monthData.length ? habit.monthData[idx] : null;
        final color = state == true
            ? theme.complete
            : state == false
                ? theme.incomplete
                : theme.inertCell;

        final startDeg = (day - 1) * angleStep + dayGap / 2;
        final endDeg = day * angleStep - dayGap / 2;

        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: midR),
          _toRadians(startDeg),
          _toRadians(endDeg) - _toRadians(startDeg),
          false,
          paint,
        );
      }
    }

    _drawLegend(canvas, center, outerR, ringThickness);
    _drawDayRim(canvas, center, outerR, angleStep);
    _drawHub(canvas, center, innerR);
  }

  void _drawLegend(Canvas canvas, Offset center, double outerR, double ringThickness) {
    final boundaryX = center.dx * 0.56;
    final linePaint = Paint()
      ..color = theme.outline
      ..strokeWidth = 1;
    final dotPaint = Paint()..color = theme.textMuted;

    for (var r = 0; r < habits.length; r++) {
      final ringOuter = outerR - r * ringThickness;
      final midR = ringOuter - ringThickness / 2;
      final y = center.dy - midR;
      if (y < 2) continue;

      canvas.drawLine(Offset(boundaryX + 5, y), Offset(center.dx, y), linePaint);
      canvas.drawCircle(Offset(center.dx, y), 2, dotPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${r + 1}. ${habits[r].name.toUpperCase()}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            fontFamily: 'monospace',
            color: theme.textSecondary,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(10, boundaryX - 4));
      tp.paint(canvas, Offset(boundaryX - tp.width, y - tp.height / 2));
    }
  }

  void _drawDayRim(Canvas canvas, Offset center, double outerR, double angleStep) {
    final labelRadius = outerR + 9;
    for (var day = 1; day <= days; day++) {
      final mid = (day - 1) * angleStep + angleStep / 2;
      final pos = _polar(center, labelRadius, mid);
      final isToday = todayDay == day;

      final tp = TextPainter(
        text: TextSpan(
          text: '$day',
          style: TextStyle(
            fontSize: isToday ? 8.5 : 7.5,
            fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            color: isToday ? theme.action : theme.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawHub(Canvas canvas, Offset center, double innerR) {
    final hubR = innerR - 6;
    if (hubR <= 10) return;

    canvas.drawCircle(center, hubR, Paint()..color = theme.background);
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = theme.outline,
    );

    // Month + year centred as a block now that the "MONTH / YEAR" caption
    // above them is gone — dash sits on the hub's vertical centre, the month
    // above it and the year below, so the pair reads as one balanced unit.
    _paintCentered(canvas, center, hubR * -0.28, monthAbbrev, 13, FontWeight.w800, theme.action, 1.0);

    final dashY = center.dy + hubR * 0.02;
    _drawDashedLine(canvas, Offset(center.dx - hubR * 0.45, dashY), Offset(center.dx + hubR * 0.45, dashY), theme.action);

    _paintCentered(canvas, center, hubR * 0.32, year, 12, FontWeight.w800, theme.textPrimary, 1.2);

    final arrowOffset = hubR * _hubArrowOffsetFraction;
    _drawMonthArrow(canvas, Offset(center.dx - arrowOffset, center.dy), pointRight: false, enabled: true);
    _drawMonthArrow(
      canvas,
      Offset(center.dx + arrowOffset, center.dy),
      pointRight: true,
      enabled: !isCurrentMonth,
    );
  }

  /// A small chevron for stepping the displayed month back/forward. Purely
  /// decorative here — [HabitRadialCard._handleHubTap] does the actual
  /// hit-testing, at the same [_hubArrowOffsetFraction] offset.
  void _drawMonthArrow(Canvas canvas, Offset center, {required bool pointRight, required bool enabled}) {
    const armLength = 7.0;
    final paint = Paint()
      ..color = enabled ? theme.textSecondary : theme.textMuted.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final dir = pointRight ? 1.0 : -1.0;
    final tip = Offset(center.dx + dir * armLength * 0.6, center.dy);
    final topBack = Offset(center.dx - dir * armLength * 0.6, center.dy - armLength);
    final bottomBack = Offset(center.dx - dir * armLength * 0.6, center.dy + armLength);

    canvas.drawLine(topBack, tip, paint);
    canvas.drawLine(tip, bottomBack, paint);
  }

  void _paintCentered(Canvas canvas, Offset center, double dy, String text, double fontSize,
      FontWeight weight, Color color, double letterSpacing) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy + dy - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Color color) {
    const dashWidth = 2.5;
    const dashSpace = 2.0;
    final total = (end - start).distance;
    final direction = (end - start) / total;
    final paint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;

    var travelled = 0.0;
    while (travelled < total) {
      final segEnd = math.min(travelled + dashWidth, total);
      canvas.drawLine(start + direction * travelled, start + direction * segEnd, paint);
      travelled += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _RadialHabitPainter oldDelegate) =>
      !identical(oldDelegate.habits, habits) ||
      oldDelegate.days != days ||
      oldDelegate.todayDay != todayDay ||
      oldDelegate.theme.isDark != theme.isDark ||
      oldDelegate.monthAbbrev != monthAbbrev ||
      oldDelegate.year != year ||
      oldDelegate.isCurrentMonth != isCurrentMonth;
}
