import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/habit.dart';
import '../services/animation/sprite_atlas.dart';
import '../services/animation/sprite_library.dart';
import '../services/animation/streak_celebration_picker.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';

/// Full-screen celebration shown when logging a habit extends an existing
/// streak (2+ consecutive days — see `_logHabit` in `JournalScreen`, the only
/// caller). Plays one streak-clip once, in round-robin order across whichever
/// `streak_N` art has actually been built, then returns the user to Journey.
class StreakCelebrationScreen extends StatefulWidget {
  final Habit habit;

  const StreakCelebrationScreen({super.key, required this.habit});

  @override
  State<StreakCelebrationScreen> createState() => _StreakCelebrationScreenState();
}

class _StreakCelebrationScreenState extends State<StreakCelebrationScreen>
    with SingleTickerProviderStateMixin {
  SpriteAtlas? _atlas;
  Ticker? _ticker;
  Duration _lastTick = Duration.zero;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await StreakCelebrationPicker().next();
    if (name == null || !mounted) return;
    final atlas = await SpriteLibrary.instance.load(name);
    if (!mounted || atlas == null) return;
    setState(() => _atlas = atlas);
    _ticker = createTicker(_onTick)..start();
  }

  /// Plays through once and holds the last frame — same clamp-not-loop rule
  /// the Journey pet's activity clips use.
  void _onTick(Duration elapsed) {
    final atlas = _atlas;
    if (atlas == null) return;
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final next = (_elapsed + dt).clamp(0.0, atlas.duration);
    if (next != _elapsed) setState(() => _elapsed = next);
    if (_elapsed >= atlas.duration) _ticker?.stop();
  }

  int get _frame {
    final atlas = _atlas;
    if (atlas == null) return 0;
    return (_elapsed * atlas.fps).floor().clamp(0, atlas.frameCount - 1);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);
    final habit = widget.habit;
    final accent = t.accent(habit.color);
    final atlas = _atlas;

    // Read once during build rather than inside the pop callback below: by
    // the time a pop callback fires the route is already being torn down, and
    // an InheritedWidget lookup at that point is a real source of framework
    // assertion failures (an Element still registered as a dependent of an
    // InheritedElement that has since unmounted).
    final tabNotifier = AppScope.of(context).tab;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) tabNotifier.value = kJourneyTab;
      },
      child: Scaffold(
        backgroundColor: t.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              children: [
                Text(habit.icon, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(
                  habit.name.toUpperCase(),
                  style: t.subhead.copyWith(letterSpacing: 1.2),
                ),
                const SizedBox(height: 12),
                Text(
                  '${habit.streak}',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    color: accent,
                  ),
                ),
                Text(
                  habit.streak == 1 ? 'day streak' : 'day streak 🔥',
                  style: t.headline.copyWith(fontSize: 20),
                ),
                Expanded(
                  child: Center(
                    child: atlas == null
                        ? SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accent,
                            ),
                          )
                        : CustomPaint(
                            painter: _StreakFramePainter(atlas: atlas, frame: _frame),
                            size: Size.infinite,
                          ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: t.onAccent(accent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
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

class _StreakFramePainter extends CustomPainter {
  final SpriteAtlas atlas;
  final int frame;

  _StreakFramePainter({required this.atlas, required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final aspect = atlas.sourceWidth / atlas.sourceHeight;
    var w = size.width;
    var h = w / aspect;
    if (h > size.height) {
      h = size.height;
      w = h * aspect;
    }
    final rect = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: w,
      height: h,
    );
    atlas.drawFrame(canvas, frame, rect, Paint());
  }

  @override
  bool shouldRepaint(covariant _StreakFramePainter oldDelegate) =>
      oldDelegate.frame != frame || !identical(oldDelegate.atlas, atlas);
}
