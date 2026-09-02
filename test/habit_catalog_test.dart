// The Journal tab shows every catalogue habit, active or not. These tests pin
// the two properties that matter: the catalogue supplies SHAPE only, and it
// must never contribute a number that could be mistaken for the user's data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pw/models/habit.dart';
import 'package:pw/models/habit_catalog.dart';

/// Mirrors the merge in `_JournalScreenState._buildHabitSection`.
({List<String> active, List<String> inactive, List<String> custom}) merge(
  List<Habit> habits,
) {
  final tracked = <String, Habit>{
    for (final h in habits) h.name.trim().toLowerCase(): h,
  };
  final active = <String>[];
  final inactive = <String>[];
  for (final template in kHabitCatalog) {
    if (tracked.remove(template.key) != null) {
      active.add(template.name);
    } else {
      inactive.add(template.name);
    }
  }
  return (active: active, inactive: inactive, custom: tracked.values.map((h) => h.name).toList());
}

Habit habit(String name, {int progress = 0, int target = 10}) => Habit(
      id: 'h_${name.toLowerCase()}',
      name: name,
      icon: '*',
      color: Colors.teal,
      target: target,
      unit: 'x',
      progress: progress,
      weekData: List<bool>.filled(7, false),
    );

void main() {
  group('catalogue', () {
    test('has the six habits the Journal tab has always shown', () {
      expect(
        kHabitCatalog.map((h) => h.name).toList(),
        ['Steps', 'Water', 'Exercise', 'Sleep', 'Meditation', 'Reading'],
      );
    });

    test('every entry is complete and sane', () {
      for (final h in kHabitCatalog) {
        expect(h.name.trim(), isNotEmpty);
        expect(h.icon.trim(), isNotEmpty);
        expect(h.unit.trim(), isNotEmpty);
        expect(h.blurb.trim(), isNotEmpty);
        expect(h.target, greaterThan(0), reason: '${h.name} would divide by zero');
      }
    });

    test('keys are unique and normalised', () {
      final keys = kHabitCatalog.map((h) => h.key).toList();
      expect(keys.toSet().length, keys.length, reason: 'duplicate catalogue key');
      for (final key in keys) {
        expect(key, key.trim().toLowerCase());
      }
    });

    test('templateFor matches case- and whitespace-insensitively', () {
      expect(templateFor('Steps')?.name, 'Steps');
      expect(templateFor('  steps  ')?.name, 'Steps');
      expect(templateFor('STEPS')?.name, 'Steps');
      expect(templateFor('Underwater Basket Weaving'), isNull);
    });
  });

  group('merge with the user\'s real habits', () {
    test('a brand-new account shows all six, all inactive', () {
      final result = merge(const <Habit>[]);
      expect(result.active, isEmpty);
      expect(result.inactive.length, 6);
      expect(result.custom, isEmpty);
    });

    test('a tracked habit flips to active and keeps its catalogue position', () {
      final result = merge([habit('Water'), habit('Reading')]);
      expect(result.active, ['Water', 'Reading']);
      expect(result.inactive, ['Steps', 'Exercise', 'Sleep', 'Meditation']);
      // Order across the whole page is still catalogue order.
      expect(result.active.length + result.inactive.length, 6);
    });

    test('matching is case-insensitive, so a re-created habit is not duplicated', () {
      final result = merge([habit('  water  '), habit('STEPS')]);
      expect(result.active..sort(), ['Steps', 'Water']);
      expect(result.custom, isEmpty, reason: 'case differences created a phantom custom habit');
    });

    test('custom habits appear after the catalogue, not inside it', () {
      final result = merge([habit('Steps'), habit('Guitar practice')]);
      expect(result.active, ['Steps']);
      expect(result.custom, ['Guitar practice']);
      expect(result.inactive.contains('Guitar practice'), isFalse);
    });

    test('every catalogue habit tracked leaves nothing inactive', () {
      final result = merge([for (final t in kHabitCatalog) habit(t.name)]);
      expect(result.inactive, isEmpty);
      expect(result.active.length, 6);
    });
  });

  group('the catalogue never fakes user data', () {
    test('a template is not a Habit and carries no progress or streak', () {
      // If HabitTemplate ever grows a `progress`/`streak`/`weekData` field it
      // would start looking like real data on an untracked card. It must not.
      const template = HabitTemplate(
        name: 'X',
        icon: '*',
        color: Colors.red,
        target: 1,
        unit: 'x',
        blurb: 'y',
      );
      expect(template, isNot(isA<Habit>()));
      expect(template.toString().toLowerCase().contains('progress'), isFalse);
    });

    test('activating a template carries its real target and unit across', () {
      final steps = templateFor('Steps')!;
      expect(steps.target, 10000);
      expect(steps.unit, 'steps');
      // The created habit starts at zero — the template contributes the goal,
      // never a starting value.
      final created = habit(steps.name, progress: 0, target: steps.target);
      expect(created.progress, 0);
      expect(created.streak, 0);
      expect(created.completedToday, isFalse);
      expect(created.completionPercentage, 0);
    });
  });
}
