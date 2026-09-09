import 'dart:async';

import 'package:flutter/material.dart';

import '../models/habit.dart';
import '../models/habit_catalog.dart';
import '../models/habit_month_progress.dart';
import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';
import '../widgets/friends/state_panels.dart';
import '../widgets/habit_card.dart';
import '../widgets/habit_radial_card.dart';
import '../widgets/inactive_habit_card.dart';
import 'streak_celebration_screen.dart';

/// The Journal tab: the signed-in user's own habits for today.
///
/// Renders the whole of [kHabitCatalog] in a fixed order. A catalogue entry
/// the user tracks draws as a live [HabitCard] with real progress, streak and
/// week dots; one they do not draws as an [InactiveHabitCard] — same geometry,
/// no invented numbers, and a tap starts tracking it for real.
///
/// This is what keeps the page recognisable on a brand-new account without
/// going back to the six fabricated habits it used to hard-code: the
/// catalogue supplies *shape*, `GET /api/habits` supplies all the data.
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  AppServices? _services;
  List<Habit> _habits = const <Habit>[];
  ApiException? _error;
  bool _loading = true;

  /// First-of-month anchor for the radial progress card. Starts on the
  /// current month; the card's own arrows step it forward/back a month at a
  /// time (year never changes directly, only as a side effect of crossing a
  /// year boundary).
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  HabitMonthReport? _monthReport;
  ApiException? _monthError;
  bool _monthLoading = true;

  /// Catalogue keys with a create in flight, so a double-tap cannot create
  /// the same habit twice.
  final Set<String> _activating = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    if (identical(_services, services)) return;
    _services = services;
    _load();
    _loadMonth();
  }

  Future<void> _load() async {
    final services = _services;
    if (services == null) return;
    if (!services.auth.isSignedIn) {
      setState(() {
        _habits = const <Habit>[];
        _loading = false;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final habits = await services.api.getHabits();
      if (!mounted) return;
      setState(() {
        _habits = habits;
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

  Future<void> _loadMonth() async {
    final services = _services;
    if (services == null) return;
    if (!services.auth.isSignedIn) {
      setState(() {
        _monthReport = null;
        _monthLoading = false;
      });
      return;
    }

    setState(() {
      _monthLoading = true;
      _monthError = null;
    });
    try {
      final report = await services.api.getHabitsMonth(month: _selectedMonth);
      if (!mounted) return;
      setState(() {
        _monthReport = report;
        _monthLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _monthError = error;
        _monthLoading = false;
      });
    }
  }

  /// Steps the radial card's month forward or back by [delta] months. The
  /// year is never touched directly — it only moves as a side effect of
  /// `DateTime` rolling over when a month shift crosses a year boundary.
  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + delta);
      // The new month's data hasn't arrived yet — showing the previous
      // month's chart under the new label would misrepresent it.
      _monthReport = null;
    });
    _loadMonth();
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // -------------------------------------------------------------- mutations

  /// `POST /api/habits/:id/log`. The endpoint **sets** the day's progress.
  Future<void> _logHabit(Habit habit, int progress) async {
    final services = _services;
    if (services == null) return;
    try {
      final result = await services.api.logHabit(habit.id, progress: progress);
      if (!mounted) return;
      setState(() {
        _habits = [
          for (final existing in _habits)
            existing.id == result.habit.id ? result.habit : existing,
        ];
      });
      // The server folds a "Steps" log into the walking challenge's own
      // step total (see API_CONTRACT.md), so refresh its cache here too —
      // otherwise the Journey tab would keep showing the pre-log total
      // until its next device sync.
      if (result.habit.name.trim().toLowerCase() == 'steps') {
        unawaited(services.walkingChallenge.refresh());
      }
      if (result.justCompleted) {
        // A streak of 1 is just today; the full-screen celebration is for an
        // actual streak (2+ consecutive days). Below that, the snackbar alone
        // covers "done for today".
        if (result.habit.streak >= 2) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StreakCelebrationScreen(habit: result.habit),
              fullscreenDialog: true,
            ),
          );
        } else {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('${habit.name} done for today 🎉')),
            );
        }
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not log that.');
    }
  }

  Future<void> _createHabit({
    required String name,
    required int target,
    required String unit,
  }) async {
    final services = _services;
    if (services == null) return;
    try {
      final habit = await services.api.createHabit(
        name: name,
        target: target,
        unit: unit.isEmpty ? null : unit,
        icon: '⭐',
      );
      if (!mounted) return;
      setState(() => _habits = <Habit>[..._habits, habit]);
    } on ApiException catch (error) {
      if (!mounted) return;
      showApiErrorSnack(context, error, fallback: 'Could not add that habit.');
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Journal'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: t.textPrimary,
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([_load(), _loadMonth()]),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _buildGreetingPanel(t),
            const SizedBox(height: 20),
            _buildRadialCard(),
            const SizedBox(height: 20),
            ..._buildHabitSection(t),
            const SizedBox(height: 24),
            _buildAddCustomHabitCard(t),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- greeting
  Widget _buildGreetingPanel(JournalTheme t) {
    final user = _services?.auth.user;
    final name = user?.name.trim() ?? '';
    final done = _habits.where((h) => h.completedToday).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline, width: 1),
        boxShadow: t.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? '$_greeting!' : '$_greeting, ${name.split(' ').first}!',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.headline,
          ),
          const SizedBox(height: 6),
          Text(
            _habits.isEmpty
                ? 'Tap any habit below to start tracking it.'
                : '$done of ${_habits.length} '
                    '${_habits.length == 1 ? 'habit' : 'habits'} done today.',
            style: t.subhead,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ radial card
  Widget _buildRadialCard() {
    return HabitRadialCard(
      report: _monthReport,
      loading: _monthLoading,
      error: _monthError,
      onRetry: _loadMonth,
      selectedMonth: _selectedMonth,
      onPrevMonth: () => _shiftMonth(-1),
      onNextMonth: () => _shiftMonth(1),
    );
  }

  // ------------------------------------------------------------ habit list
  //
  // The page always shows the full catalogue. Habits the user tracks render
  // live; the rest render inactive with a "Track" affordance. That way the
  // Journal tab has its familiar shape from the very first launch instead of
  // collapsing to an empty state — without inventing any progress.
  List<Widget> _buildHabitSection(JournalTheme t) {
    final error = _error;
    if (error != null && _habits.isEmpty) {
      return [ErrorPanel(error: error, onRetry: _load)];
    }

    if (_loading && _habits.isEmpty) {
      return const [RowListSkeleton(count: 4)];
    }

    final tracked = <String, Habit>{
      for (final habit in _habits) habit.name.trim().toLowerCase(): habit,
    };

    final cards = <Widget>[];

    // Catalogue order first, so the six familiar habits keep their positions
    // whether or not they are active.
    for (final template in kHabitCatalog) {
      final habit = tracked.remove(template.key);
      cards.add(
        habit != null
            ? HabitCard(
                key: ValueKey<String>(habit.id),
                habit: habit,
                onLog: (progress) => _logHabit(habit, progress),
              )
            : InactiveHabitCard(
                key: ValueKey<String>('template:${template.key}'),
                template: template,
                busy: _activating.contains(template.key),
                onActivate: () => _activateTemplate(template),
              ),
      );
    }

    // Anything the user invented themselves goes after the catalogue.
    for (final habit in tracked.values) {
      cards.add(
        HabitCard(
          key: ValueKey<String>(habit.id),
          habit: habit,
          onLog: (progress) => _logHabit(habit, progress),
        ),
      );
    }

    return [
      for (var i = 0; i < cards.length; i++) ...[
        if (i > 0) const SizedBox(height: 14),
        cards[i],
      ],
    ];
  }

  /// Turns a catalogue entry into a real habit on the server.
  Future<void> _activateTemplate(HabitTemplate template) async {
    final services = _services;
    if (services == null || _activating.contains(template.key)) return;

    setState(() => _activating.add(template.key));
    try {
      final habit = await services.api.createHabit(
        name: template.name,
        target: template.target,
        unit: template.unit,
        icon: template.icon,
        color: template.color,
      );
      if (!mounted) return;
      setState(() {
        _habits = <Habit>[..._habits, habit];
        _activating.remove(template.key);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Now tracking ${template.name}')),
        );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _activating.remove(template.key));
      showApiErrorSnack(
        context,
        error,
        fallback: 'Could not start tracking ${template.name}.',
      );
    }
  }

  // -------------------------------------------------------------- add habit
  Widget _buildAddCustomHabitCard(JournalTheme t) {
    return GestureDetector(
      onTap: _showAddHabitDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: t.surfaceBright,
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
          border: Border.all(color: t.outline, width: 1),
          boxShadow: t.shadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 20, color: t.action),
            const SizedBox(width: 8),
            Text(
              'Add New Habit',
              style: t.habitName.copyWith(
                color: t.action,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddHabitDialog() async {
    final t = JournalTheme.of(context);
    final nameController = TextEditingController();
    final targetController = TextEditingController();
    final unitController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        ),
        title: Text(
          'Add Custom Habit',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDialogField(
                t: t,
                controller: nameController,
                label: 'Name',
                hint: 'Habit name',
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Give the habit a name'
                    : null,
              ),
              const SizedBox(height: 14),
              _buildDialogField(
                t: t,
                controller: targetController,
                label: 'Target',
                hint: 'Daily target',
                keyboardType: TextInputType.number,
                validator: (value) {
                  // The contract requires an integer >= 1.
                  final parsed = int.tryParse((value ?? '').trim());
                  if (parsed == null) return 'Enter a number';
                  if (parsed < 1) return 'Must be at least 1';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              _buildDialogField(
                t: t,
                controller: unitController,
                label: 'Unit',
                hint: 'steps, min, cups…',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: t.textSecondary),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: t.action,
              foregroundColor: t.onAccent(t.action),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(JournalTheme.radiusChip),
              ),
            ),
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    final name = nameController.text.trim();
    final target = int.tryParse(targetController.text.trim()) ?? 1;
    final unit = unitController.text.trim();

    nameController.dispose();
    targetController.dispose();
    unitController.dispose();

    if (submitted != true || !mounted) return;
    await _createHabit(name: name, target: target, unit: unit);
  }

  Widget _buildDialogField({
    required JournalTheme t,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: t.surfaceBright,
        labelStyle: TextStyle(color: t.textSecondary),
        hintStyle: TextStyle(color: t.textMuted),
        errorStyle: TextStyle(color: t.incomplete),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.action, width: 2),
        ),
      ),
    );
  }
}
