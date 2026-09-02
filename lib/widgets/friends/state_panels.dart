import 'package:flutter/material.dart';

import '../../services/api/api_exception.dart';
import '../../utils/journal_theme.dart';
import '../app_scope.dart';

/// A themed card fill. The Friends widgets used to hard-code
/// `Colors.white.withOpacity(...)`, which is invisible on the light ground —
/// everything now goes through the theme tokens instead.
class PwCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final bool bright;
  final VoidCallback? onTap;

  const PwCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderColor,
    this.bright = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    final content = Container(
      decoration: BoxDecoration(
        color: bright ? t.surfaceBright : t.surface,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: borderColor ?? t.outline, width: 1),
        boxShadow: t.shadow,
      ),
      padding: padding,
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        child: content,
      ),
    );
  }
}

/// Section title, optionally with a trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// One shimmering placeholder block. Used to build skeletons that have the
/// shape of the content they stand in for, rather than a bare spinner.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.circle = false,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final alpha = 0.05 + 0.07 * _controller.value;
        return Container(
          width: widget.circle ? widget.height : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: t.textMuted.withValues(alpha: alpha * (t.isDark ? 3 : 2)),
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius:
                widget.circle ? null : BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Skeleton for a horizontal rail of friend cards.
class FriendRailSkeleton extends StatelessWidget {
  const FriendRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => const SizedBox(
          width: 140,
          child: PwCard(
            padding: EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonBox(height: 64, circle: true),
                SizedBox(height: 12),
                SkeletonBox(width: 60, height: 12),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton for a vertical list of rows.
class RowListSkeleton extends StatelessWidget {
  final int count;

  const RowListSkeleton({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(
        count,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: PwCard(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                SkeletonBox(height: 40, circle: true),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 13),
                      SizedBox(height: 8),
                      SkeletonBox(width: 90, height: 11),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A deliberate empty state: headline, body, optional primary action.
///
/// Used for "No friends yet", which is the state a fresh account lands in —
/// it has to look designed, not broken.
class EmptyStateView extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const EmptyStateView({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
  });

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.action.withValues(alpha: t.isDark ? 0.18 : 0.10),
            ),
            child: Icon(icon, size: 26, color: t.action),
          ),
          const SizedBox(height: 16),
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.45, color: t.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.action,
                  foregroundColor: t.onAccent(t.action),
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(JournalTheme.radiusTile),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error state for a failed load.
///
/// A transport failure gets the panel the spec asks for: the base URL that was
/// actually tried, plus a "Change server" affordance that writes
/// `ApiConfig.baseUrl`. Every other failure gets its `ApiException.message`,
/// which is always human-readable — a raw exception string is never shown.
class ErrorPanel extends StatelessWidget {
  final ApiException error;
  final VoidCallback onRetry;

  const ErrorPanel({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final services = AppScope.of(context);
    final isNetwork = error.isNetwork;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 4),
      child: PwCard(
        borderColor: t.incomplete.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isNetwork ? Icons.cloud_off_outlined : Icons.error_outline,
                  color: t.incomplete,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isNetwork ? "Can't reach the server" : 'Something broke',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              error.message,
              style: TextStyle(fontSize: 14, height: 1.4, color: t.textSecondary),
            ),
            if (isNetwork) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: t.inertCell,
                  borderRadius:
                      BorderRadius.circular(JournalTheme.radiusChip),
                ),
                child: Text(
                  services.baseUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: t.textMuted,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.action,
                    foregroundColor: t.onAccent(t.action),
                    elevation: 0,
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(JournalTheme.radiusTile),
                    ),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
                if (isNetwork) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => showChangeServerDialog(context, onRetry),
                    style: TextButton.styleFrom(
                      foregroundColor: t.textSecondary,
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Change server'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Prompts for a new base URL and persists it via `ApiConfig.setBaseUrl`.
///
/// Exposed as a top-level function so the login screen can offer it too — a
/// developer on a real device whose `localhost` is wrong cannot even sign in
/// otherwise.
Future<void> showChangeServerDialog(
  BuildContext context,
  VoidCallback onChanged,
) async {
  final t = JournalTheme.of(context);
  final services = AppScope.read(context);
  final controller = TextEditingController(text: services.baseUrl);

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: t.background,
      surfaceTintColor: Colors.transparent,
      title: Text(
        'Change server',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The app talks to this base URL. An Android emulator reaches the '
            'host machine at 10.0.2.2.',
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: TextStyle(color: t.textPrimary),
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: 'http://localhost:8080',
              labelStyle: TextStyle(color: t.textSecondary),
              hintStyle: TextStyle(color: t.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          style: TextButton.styleFrom(foregroundColor: t.textSecondary),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: t.action,
            foregroundColor: t.onAccent(t.action),
            elevation: 0,
          ),
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  controller.dispose();
  if (result == null) return;

  await services.client.config.setBaseUrl(result);
  onChanged();
}

/// Turns an [ApiException] into a one-line message fit for a SnackBar.
///
/// Rate-limited nudges get the cooldown spelled out, per the spec. Nothing
/// here ever leaks `toString()` of an exception.
String describeApiError(ApiException error, {String? fallback}) {
  if (error.isRateLimited) {
    final seconds = error.retryAfterSeconds;
    if (seconds != null && seconds > 0) {
      final minutes = (seconds / 60).ceil();
      return 'Already nudged — try again in $minutes min';
    }
    return 'Already nudged — try again shortly';
  }
  if (error.isNetwork) return "Can't reach the server. Check your connection.";
  if (error.message.trim().isEmpty) {
    return fallback ?? 'Something went wrong. Please try again.';
  }
  return error.message;
}

/// Shows [describeApiError] in a SnackBar. Callers must already have checked
/// `mounted`.
void showApiErrorSnack(BuildContext context, ApiException error,
    {String? fallback}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(describeApiError(error, fallback: fallback)),
        duration: const Duration(seconds: 3),
      ),
    );
}
