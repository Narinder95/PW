import 'package:flutter/material.dart';

import '../models/habit_catalog.dart';
import '../utils/journal_theme.dart';

/// A habit the user is not tracking yet.
///
/// Mirrors [HabitCard]'s geometry — same icon tile, same name/target column,
/// same week-dot row, same bottom rail — so the Journal grid keeps its rhythm
/// whether a habit is taken up or not. What it deliberately does NOT do is
/// invent numbers: the value slot shows a "+" instead of a count, the week
/// dots are all idle, and the rail is empty. An inactive card states that
/// there is no data, rather than faking some.
class InactiveHabitCard extends StatelessWidget {
  final HabitTemplate template;

  /// Starts tracking this habit. Null while a create is already in flight.
  final VoidCallback? onActivate;

  final bool busy;

  const InactiveHabitCard({
    super.key,
    required this.template,
    required this.onActivate,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(template.color);

    // Everything is drawn at reduced emphasis. The accent is still present so
    // the habit stays recognisable, just clearly dormant.
    return Semantics(
      button: true,
      label: '${template.name}, not tracked yet. Tap to start tracking.',
      child: GestureDetector(
        onTap: busy ? null : onActivate,
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
            border: Border.all(
              color: t.outline,
              width: 1,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
            child: Opacity(
              // One opacity over the whole card reads as "dormant" far more
              // clearly than muting each colour individually.
              opacity: busy ? 0.45 : 0.62,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _header(t, accent),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _idleWeekDots(t),
                  ),
                  const SizedBox(height: 14),
                  // The rail slot, empty — keeps the card the same height as
                  // an active one so the list does not jump when you add.
                  Container(height: JournalTheme.progressHeight, color: t.progressTrack),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(JournalTheme t, Color accent) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: t.tintIcon * 0.55),
            borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          ),
          child: Center(
            child: Text(
              template.icon,
              style: const TextStyle(fontSize: JournalTheme.sizeEmoji),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: t.habitName.copyWith(color: t.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  template.blurb,
                  style: t.habitTarget.copyWith(color: t.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Where an active card shows today's count, this shows the way in.
        SizedBox(
          height: 48,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: t.tintBadge),
                      borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 14, color: accent),
                        const SizedBox(width: 4),
                        Text(
                          'Track',
                          style: TextStyle(
                            fontSize: JournalTheme.sizeUnit,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// The same seven-dot row an active card draws, all idle. Day letters roll
  /// with the real date so the row is never wrong, only empty.
  Widget _idleWeekDots(JournalTheme t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List<Widget>.generate(7, (i) {
        final date = today.subtract(Duration(days: 6 - i));
        final isToday = i == 6;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              JournalTheme.weekdayLetter(date),
              style: JournalTheme.dayLetter.copyWith(color: t.textMuted),
            ),
            const SizedBox(height: 6),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.inertCell,
                border: Border.all(
                  color: isToday
                      ? t.textMuted.withValues(alpha: 0.5)
                      : t.outline,
                  width: 1,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
