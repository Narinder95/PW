import 'package:flutter/material.dart';

import '../../utils/journal_theme.dart';

/// Initial-in-a-circle avatar, the only avatar the product has (the contract's
/// "Non-goals" rule out image avatars).
///
/// [name] is allowed to be empty — that is exactly the case the old
/// `FriendCard`/`ActivityCard` crashed on with `name[0]` — and renders as `?`.
class PwAvatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  /// Optional 0..1 completion ring drawn around the circle.
  final double? ringValue;

  /// Ring thickness. Ignored when [ringValue] is null.
  final double ringWidth;

  const PwAvatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 40,
    this.ringValue,
    this.ringWidth = 4,
  });

  /// First letter, or `?` for an empty/whitespace name. Never indexes into an
  /// empty string.
  static String initialOf(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(color);
    final ring = ringValue;

    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: t.tintIcon),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        initialOf(name),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );

    if (ring == null) return circle;

    final outer = size + ringWidth * 4;
    return SizedBox(
      width: outer,
      height: outer,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: outer,
            height: outer,
            child: CircularProgressIndicator(
              // Already clamped by the caller's model getters, clamped again
              // here so a rogue value can never produce a NaN sweep.
              value: ring.clamp(0.0, 1.0),
              strokeWidth: ringWidth,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              backgroundColor: t.progressTrack,
            ),
          ),
          circle,
        ],
      ),
    );
  }
}

/// A 0-100 match score drawn as a ring with the number inside.
class ScoreRing extends StatelessWidget {
  final int score;
  final Color color;
  final double size;

  const ScoreRing({
    super.key,
    required this.score,
    required this.color,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(color);
    final clamped = score.clamp(0, 100);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: clamped / 100,
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
              backgroundColor: t.progressTrack,
            ),
          ),
          Text(
            '$clamped',
            style: TextStyle(
              fontSize: size * 0.32,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill used for shared-habit chips and status labels.
class PwChip extends StatelessWidget {
  final String label;
  final Color color;

  const PwChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.tintBadge),
        borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: accent,
        ),
      ),
    );
  }
}

/// Streak badge: `🔥 22`. Rendered only when the streak is above zero, which
/// is `devong`'s case.
class StreakBadge extends StatelessWidget {
  final int days;
  final Color color;

  const StreakBadge({super.key, required this.days, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final accent = t.accent(color);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: t.tintBadge),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(width: 3),
          const Text('🔥', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
