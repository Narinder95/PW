import 'package:flutter/material.dart';

/// A habit the app *offers*, distinct from a habit the user actually tracks.
///
/// These are templates, not data: nothing here is ever presented as the user's
/// progress. The Journal tab renders the full catalogue so the page has shape
/// from the very first launch — entries the user has taken up render live,
/// the rest render inactive with a "start tracking" affordance.
@immutable
class HabitTemplate {
  final String name;
  final String icon;
  final Color color;
  final int target;
  final String unit;

  /// One line explaining the habit, shown on the inactive card in place of
  /// the progress numbers it has no right to invent.
  final String blurb;

  const HabitTemplate({
    required this.name,
    required this.icon,
    required this.color,
    required this.target,
    required this.unit,
    required this.blurb,
  });

  /// Case- and whitespace-insensitive key, used to match a template against
  /// the user's real habits (which are matched the same way server-side).
  String get key => name.trim().toLowerCase();
}

/// The six habits the Journal tab has always shown.
///
/// Colours and targets are the originals, so a user who had them before sees
/// exactly what they saw before.
const List<HabitTemplate> kHabitCatalog = <HabitTemplate>[
  HabitTemplate(
    name: 'Steps',
    icon: '👟',
    color: Color(0xFF2E7D32),
    target: 10000,
    unit: 'steps',
    blurb: 'Track your daily movement',
  ),
  HabitTemplate(
    name: 'Water',
    icon: '💧',
    color: Color(0xFF0097A7),
    target: 8,
    unit: 'cups',
    blurb: 'Stay hydrated through the day',
  ),
  HabitTemplate(
    name: 'Exercise',
    icon: '💪',
    color: Color(0xFFFF7043),
    target: 30,
    unit: 'min',
    blurb: 'Get your body moving',
  ),
  HabitTemplate(
    name: 'Sleep',
    icon: '😴',
    color: Color(0xFF7E57C2),
    target: 8,
    unit: 'hours',
    blurb: 'Rest is part of the work',
  ),
  HabitTemplate(
    name: 'Meditation',
    icon: '🧘',
    color: Color(0xFF26A69A),
    target: 10,
    unit: 'min',
    blurb: 'A few quiet minutes',
  ),
  HabitTemplate(
    name: 'Reading',
    icon: '📚',
    color: Color(0xFFFFA726),
    target: 20,
    unit: 'min',
    blurb: 'Feed your head',
  ),
];

/// Template for [name], or null if it is a custom habit the user invented.
HabitTemplate? templateFor(String name) {
  final key = name.trim().toLowerCase();
  for (final template in kHabitCatalog) {
    if (template.key == key) return template;
  }
  return null;
}
