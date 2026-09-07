import 'package:flutter/material.dart';

import '../../models/walking_challenge.dart';
import '../../utils/journal_theme.dart';

/// Shows the current walking-challenge tier, progress toward the next one,
/// today's steps against the target, and a warning banner when the most
/// recent committed day was a near-miss or a demotion.
///
/// Purely a rendering of `WalkingChallenge` — every number on it (level,
/// streak, target, status) comes straight from the server; see that model's
/// doc comment for why this widget must never recompute them.
class WalkingChallengeCard extends StatelessWidget {
  final WalkingChallenge? challenge;
  final bool isLoading;
  final bool permissionDenied;
  final VoidCallback? onConnectHealth;

  const WalkingChallengeCard({
    super.key,
    required this.challenge,
    this.isLoading = false,
    this.permissionDenied = false,
    this.onConnectHealth,
  });

  static const Map<WalkingLevel, Color> _levelColors = <WalkingLevel, Color>{
    WalkingLevel.none: Color(0xFF9CA3AF),
    WalkingLevel.bronze: Color(0xFFCD7F32),
    WalkingLevel.silver: Color(0xFFA8B0BD),
    WalkingLevel.gold: Color(0xFFFFC107),
  };

  static const Map<WalkingLevel, String> _levelEmoji = <WalkingLevel, String>{
    WalkingLevel.none: '👟',
    WalkingLevel.bronze: '🥉',
    WalkingLevel.silver: '🥈',
    WalkingLevel.gold: '🥇',
  };

  static const Map<WalkingLevel, String> _levelLabel = <WalkingLevel, String>{
    WalkingLevel.none: 'No tier yet',
    WalkingLevel.bronze: 'Bronze',
    WalkingLevel.silver: 'Silver',
    WalkingLevel.gold: 'Gold',
  };

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF5F5F7);
    final borderColor =
        isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2);
    final mutedColor = isDarkMode ? Colors.grey[400] : Colors.grey[600];

    final c = challenge;
    final level = c?.level ?? WalkingLevel.none;
    final color = _levelColors[level]!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.4),
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_levelEmoji[level]!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _levelLabel[level]!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    if (c != null)
                      Text(
                        _progressLabel(c),
                        style: TextStyle(fontSize: 11, color: mutedColor),
                      ),
                  ],
                ),
              ),
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (c != null) _TodayProgress(challenge: c, color: color, mutedColor: mutedColor),
          if (permissionDenied) ...[
            const SizedBox(height: 10),
            _ConnectHealthBanner(onTap: onConnectHealth),
          ] else if (c != null && c.hasWarning) ...[
            const SizedBox(height: 10),
            _WarningBanner(challenge: c),
          ],
        ],
      ),
    );
  }

  String _progressLabel(WalkingChallenge c) {
    if (c.level == WalkingLevel.gold) {
      return 'Maintaining gold — ${c.streakDays} day${c.streakDays == 1 ? '' : 's'} strong';
    }
    final next = c.nextLevel;
    if (next == null) return '';
    final remaining = c.daysToNextLevel ?? 0;
    return remaining <= 0
        ? 'About to reach ${_levelLabel[next]}'
        : '${c.streakDays}/3 days to ${_levelLabel[next]}';
  }
}

/// Tiny tappable badge — the compact form of [WalkingChallengeCard] meant to
/// sit as an overlay on the Journey canvas rather than take its own row.
/// Tapping it opens the full card (progress bar, banners) in a bottom sheet.
class WalkingTierBadge extends StatelessWidget {
  final WalkingChallenge? challenge;
  final bool isLoading;
  final bool permissionDenied;
  final VoidCallback? onConnectHealth;

  const WalkingTierBadge({
    super.key,
    required this.challenge,
    this.isLoading = false,
    this.permissionDenied = false,
    this.onConnectHealth,
  });

  @override
  Widget build(BuildContext context) {
    final level = challenge?.level ?? WalkingLevel.none;
    final needsAttention = permissionDenied || (challenge?.hasWarning ?? false);

    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white70),
                ),
              )
            else
              Text(
                WalkingChallengeCard._levelEmoji[level]!,
                style: const TextStyle(fontSize: 16),
              ),
            if (needsAttention)
              const Positioned(
                top: -2,
                right: -2,
                child: _AttentionDot(),
              ),
          ],
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    final t = JournalTheme.of(context);
    showModalBottomSheet<void>(
      context: context,
      // The sheet route itself stays transparent; the real background is the
      // opaque rounded surface below. Without that surface the card's own
      // 40%-alpha tint let the game canvas show straight through, which read
      // as a broken/see-through popup rather than a proper sheet.
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          10,
          16,
          16 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        // MainAxisSize.min plus no isScrollControlled on the sheet itself is
        // what keeps the height to exactly the handle + card: the warning and
        // connect-health banners inside WalkingChallengeCard are already
        // conditional, so the sheet only grows when one is actually shown.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: t.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            WalkingChallengeCard(
              challenge: challenge,
              isLoading: isLoading,
              permissionDenied: permissionDenied,
              onConnectHealth: onConnectHealth,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionDot extends StatelessWidget {
  const _AttentionDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFFEF4444),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _TodayProgress extends StatelessWidget {
  final WalkingChallenge challenge;
  final Color color;
  final Color? mutedColor;

  const _TodayProgress({
    required this.challenge,
    required this.color,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final target = challenge.target;
    final steps = challenge.todaySteps;
    final ratio = target <= 0 ? 0.0 : (steps / target).clamp(0.0, 1.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Today',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mutedColor),
            ),
            Text(
              '$steps / $target steps',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: mutedColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: Colors.grey.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final WalkingChallenge challenge;

  const _WarningBanner({required this.challenge});

  @override
  Widget build(BuildContext context) {
    final demoted = challenge.todayStatus == DayStepStatus.shortfall ||
        (challenge.history.isNotEmpty &&
            challenge.history.last.status == DayStepStatus.shortfall);

    final message = demoted
        ? "You fell short of yesterday's goal by more than 20% — your streak dropped a level."
        : "Close call — you're under this level's goal. One more short day and you'll drop a level.";

    return _Banner(
      icon: demoted ? '⬇️' : '⚠️',
      message: message,
      color: demoted ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
    );
  }
}

class _ConnectHealthBanner extends StatelessWidget {
  final VoidCallback? onTap;

  const _ConnectHealthBanner({this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: const _Banner(
        icon: '❤️',
        message: 'Connect Health to track your steps automatically. Tap to grant access.',
        color: Color(0xFF60A5FA),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final String icon;
  final String message;
  final Color color;

  const _Banner({required this.icon, required this.message, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
