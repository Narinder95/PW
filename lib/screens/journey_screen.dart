import 'package:flutter/material.dart';
import '../widgets/activity_input_card.dart';
import '../widgets/app_scope.dart';
import '../widgets/journey/journey_canvas.dart';

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({Key? key}) : super(key: key);

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  final Map<String, int> activityValues = {
    'water': 0,
    'exercise': 0,
    'sleep': 0,
    'meditation': 0,
    'reading': 0,
  };

  final scrollController = ScrollController();
  final GlobalKey<JourneyCanvasState> _journeyCanvasKey = GlobalKey();
  bool _isSaving = false;
  DateTime? _lastSaveTime;

  AppServices? _services;
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;

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

  Future<void> _autoSaveActivity(String type) async {
    if (_isSaving) return;

    _isSaving = true;
    _lastSaveTime = DateTime.now();

    try {
      // TODO: Send to backend/Firebase
      // await FirebaseService.saveActivity(type, activityValues[type]!);
    } catch (e) {
      // Silently fail
    } finally {
      _isSaving = false;
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
                      waterIntake: activityValues['water']!,
                      exerciseMinutes: activityValues['exercise']!,
                      sleepHours: activityValues['sleep']!,
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
                                '${activityValues.values.reduce((a, b) => a + b)} logged',
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
                                  value: activityValues['water']!,
                                  onChanged: (value) {
                                    final previousValue = activityValues['water']!;
                                    setState(() {
                                      activityValues['water'] = value;
                                    });
                                    _autoSaveActivity('water');

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
                                  value: activityValues['exercise']!,
                                  onChanged: (value) {
                                    final previousValue = activityValues['exercise']!;
                                    setState(() {
                                      activityValues['exercise'] = value;
                                    });
                                    _autoSaveActivity('exercise');

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
                                  value: activityValues['sleep']!,
                                  onChanged: (value) {
                                    setState(() {
                                      activityValues['sleep'] = value;
                                    });
                                    _autoSaveActivity('sleep');
                                  },
                                  presets: const [1, 2],
                                  color: const Color(0xFFA78BFA),
                                ),
                                const SizedBox(width: 10),
                                ActivityInputCard(
                                  icon: '🧘',
                                  label: 'Meditate',
                                  unit: 'min',
                                  value: activityValues['meditation']!,
                                  onChanged: (value) {
                                    final previousValue = activityValues['meditation']!;
                                    setState(() {
                                      activityValues['meditation'] = value;
                                    });
                                    _autoSaveActivity('meditation');

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
                                  value: activityValues['reading']!,
                                  onChanged: (value) {
                                    final previousValue = activityValues['reading']!;
                                    setState(() {
                                      activityValues['reading'] = value;
                                    });
                                    _autoSaveActivity('reading');

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
                                    ? '✅ Auto-saving'
                                    : '📝 Log activities below',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                              ),
                              if (_isSaving)
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
