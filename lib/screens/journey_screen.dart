import 'dart:async';

import 'package:flutter/material.dart';
import '../models/habit.dart';
import '../models/habit_catalog.dart';
import '../services/api/api_exception.dart';
import '../widgets/activity_input_card.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/state_panels.dart';
import '../widgets/journey/journey_canvas.dart';

/// The five [kHabitCatalog] entries the Journey tab's "LOG TODAY" panel
/// offers, in display order. `Steps` is deliberately excluded: it already has
/// its own logging surface on the Journal tab, and it drives the walking
/// challenge above rather than being just another habit tile.
const List<String> _kJourneyPanelKeys = <String>[
  'water',
  'exercise',
  'sleep',
  'meditation',
  'reading',
];

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({Key? key}) : super(key: key);

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final scrollController = ScrollController();
  final GlobalKey<JourneyCanvasState> _journeyCanvasKey = GlobalKey();

  /// The signed-in user's real habits — the same `GET /api/habits` data the
  /// Journal tab shows, so logging Water/Exercise/Sleep/Meditate/Read here
  /// updates the very same habit and reads back identically on Journal.
  List<Habit> _habits = const <Habit>[];
  bool _habitsLoading = true;

  /// Catalogue keys with a log request in flight, so a double-tap on one
  /// tile can't fire twice, without blocking the other tiles.
  final Set<String> _loggingKeys = <String>{};
  DateTime? _lastSaveTime;

  AppServices? _services;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _loadHabits();

    if (!_bootstrapped && services.auth.isSignedIn) {
      _bootstrapped = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => services.walkingChallenge.syncFromDevice());
    }
  }

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHabits() async {
    final services = _services;
    if (services == null) return;
    if (!services.auth.isSignedIn) {
      setState(() {
        _habits = const <Habit>[];
        _habitsLoading = false;
      });
      return;
    }

    setState(() => _habitsLoading = true);
    try {
      final habits = await services.api.getHabits();
      if (!mounted) return;
      setState(() {
        _habits = habits;
        _habitsLoading = false;
      });
    } on ApiException catch (_) {
      // The panel just falls back to zeros; the canvas above already has its
      // own error handling for the walking challenge, and duplicating a
      // second error banner here would be noise.
      if (!mounted) return;
      setState(() => _habitsLoading = false);
    }
  }

  Habit? _habitFor(String key) {
    for (final habit in _habits) {
      if (habit.name.trim().toLowerCase() == key) return habit;
    }
    return null;
  }

  int _valueFor(String key) => _habitFor(key)?.progress ?? 0;

  /// `POST /api/habits` (if not yet tracked) then `POST /api/habits/:id/log`.
  /// Mirrors `JournalScreen._activateTemplate` + `_logHabit` so a habit
  /// logged from here is the exact same server record Journal shows.
  Future<void> _logActivity(HabitTemplate template, int progress) async {
    final services = _services;
    // Guards against a tap racing the initial `GET /api/habits`: without
    // this, a tap before `_habits` has loaded could create a duplicate
    // habit because `_habitFor` would find nothing yet to attach the log to.
    if (services == null || _habitsLoading || _loggingKeys.contains(template.key)) {
      return;
    }

    setState(() => _loggingKeys.add(template.key));
    try {
      var habit = _habitFor(template.key);
      habit ??= await services.api.createHabit(
        name: template.name,
        target: template.target,
        unit: template.unit,
        icon: template.icon,
        color: template.color,
      );
      final result = await services.api.logHabit(habit.id, progress: progress);
      if (!mounted) return;
      setState(() {
        final exists = _habits.any((h) => h.id == result.habit.id);
        _habits = exists
            ? [
                for (final existing in _habits)
                  existing.id == result.habit.id ? result.habit : existing,
              ]
            : [..._habits, result.habit];
        _loggingKeys.remove(template.key);
        _lastSaveTime = DateTime.now();
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _loggingKeys.remove(template.key));
      showApiErrorSnack(context, error, fallback: 'Could not log that.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journey'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: services.walkingChallenge,
          builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final screenHeight = constraints.maxHeight;
            final topSectionHeight = screenHeight * 0.6;
            final bottomSectionHeight = screenHeight * 0.4;
            final challenge = services.walkingChallenge.challenge;

            return Column(
              children: [
                // TOP 60% - 2D Game Canvas, with the walking-challenge tier
                // shown as a tiny badge overlaying the canvas rather than a
                // row of its own.
                SizedBox(
                  height: topSectionHeight,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: JourneyCanvas(
                      key: _journeyCanvasKey,
                      stepsToday: challenge?.todaySteps ?? 0,
                      waterIntake: _valueFor('water'),
                      exerciseMinutes: _valueFor('exercise'),
                      sleepHours: _valueFor('sleep'),
                      challenge: challenge,
                      challengeLoading: services.walkingChallenge.isLoading,
                      challengePermissionDenied:
                          services.walkingChallenge.permissionDenied,
                      petStepBank: services.petStepBank,
                      onConnectHealth: () =>
                          services.walkingChallenge.syncFromDevice(),
                      onActivityLogged: (steps) {
                        // Optional: trigger celebration animation
                      },
                    ),
                  ),
                ),

                // BOTTOM 40% - Activity Input Section
                SizedBox(
                  height: bottomSectionHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border(
                        top: BorderSide(
                          color: Colors.grey[300] ?? Colors.grey,
                          width: 1,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'LOG TODAY',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              Text(
                                '${_kJourneyPanelKeys.map(_valueFor).fold<int>(0, (a, b) => a + b)} logged',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                ActivityInputCard(
                                  icon: '💧',
                                  label: 'Water',
                                  unit: 'L',
                                  value: _valueFor('water'),
                                  onChanged: (value) {
                                    final previousValue = _valueFor('water');
                                    unawaited(_logActivity(templateFor('water')!, value));

                                    if (value > previousValue) {
                                      _journeyCanvasKey.currentState
                                          ?.startDrinkingWater();
                                    }
                                  },
                                  presets: const [100, 200],
                                  color: const Color(0xFF2DD4BF),
                                ),
                                const SizedBox(width: 10),
                                ActivityInputCard(
                                  icon: '💪',
                                  label: 'Exercise',
                                  unit: 'min',
                                  value: _valueFor('exercise'),
                                  onChanged: (value) {
                                    final previousValue = _valueFor('exercise');
                                    unawaited(_logActivity(templateFor('exercise')!, value));

                                    if (value > previousValue) {
                                      _journeyCanvasKey.currentState
                                          ?.startExercise();
                                    }
                                  },
                                  presets: const [15, 30],
                                  color: const Color(0xFFFB7185),
                                ),
                                const SizedBox(width: 10),
                                ActivityInputCard(
                                  icon: '😴',
                                  label: 'Sleep',
                                  unit: 'h',
                                  value: _valueFor('sleep'),
                                  onChanged: (value) {
                                    unawaited(_logActivity(templateFor('sleep')!, value));
                                  },
                                  presets: const [1, 2],
                                  color: const Color(0xFFA78BFA),
                                ),
                                const SizedBox(width: 10),
                                ActivityInputCard(
                                  icon: '🧘',
                                  label: 'Meditate',
                                  unit: 'min',
                                  value: _valueFor('meditation'),
                                  onChanged: (value) {
                                    final previousValue = _valueFor('meditation');
                                    unawaited(_logActivity(templateFor('meditation')!, value));

                                    if (value > previousValue) {
                                      _journeyCanvasKey.currentState
                                          ?.startMeditation();
                                    }
                                  },
                                  presets: const [5, 10],
                                  color: const Color(0xFF20B2AA),
                                ),
                                const SizedBox(width: 10),
                                ActivityInputCard(
                                  icon: '📖',
                                  label: 'Read',
                                  unit: 'min',
                                  value: _valueFor('reading'),
                                  onChanged: (value) {
                                    final previousValue = _valueFor('reading');
                                    unawaited(_logActivity(templateFor('reading')!, value));

                                    if (value > previousValue) {
                                      _journeyCanvasKey.currentState
                                          ?.startReading();
                                    }
                                  },
                                  presets: const [15, 30],
                                  color: const Color(0xFFFBBF24),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _lastSaveTime != null
                                    ? '✅ Saved'
                                    : '📝 Log activities below',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                              ),
                              if (_loggingKeys.isNotEmpty)
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                      Colors.green[600],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          ),
        ),
      ),
    );
  }
}
