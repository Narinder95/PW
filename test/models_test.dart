// Model parsing must be TOTAL: a malformed payload degrades to a documented
// fallback and never throws. A single uncaught parse error here would take out
// a whole screen at runtime, so these tests feed the models deliberate garbage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pw/models/app_notification.dart';
import 'package:pw/models/comparison.dart';
import 'package:pw/models/friend.dart';
import 'package:pw/models/friend_activity.dart';
import 'package:pw/models/friend_habit.dart';
import 'package:pw/models/friend_request.dart';
import 'package:pw/models/habit.dart';
import 'package:pw/models/habit_month_progress.dart';
import 'package:pw/models/json.dart';
import 'package:pw/models/match_suggestion.dart';
import 'package:pw/models/nudge.dart';
import 'package:pw/models/user_profile.dart';
import 'package:pw/models/walking_challenge.dart';

/// Payloads that have broken naive `fromJson` implementations before.
const List<Object?> hostileValues = <Object?>[
  null,
  '',
  'not-a-number',
  <String, dynamic>{},
  <dynamic>[],
  true,
  -1,
  0,
  3.7,
  'NaN',
];

void main() {
  group('json coercion helpers', () {
    test('asColor accepts #RRGGBB and #AARRGGBB, falls back on junk', () {
      expect(asColor('#FF0000').toARGB32(), const Color(0xFFFF0000).toARGB32());
      expect(asColor('#2DD4BF').toARGB32(), const Color(0xFF2DD4BF).toARGB32());
      expect(asColor('#802DD4BF').toARGB32(), const Color(0x802DD4BF).toARGB32());
      // Tolerates a missing leading hash.
      expect(asColor('2DD4BF').toARGB32(), const Color(0xFF2DD4BF).toARGB32());

      for (final junk in <Object?>[null, '', 'red', '#GGGGGG', '#12', <int>[], true]) {
        expect(asColor(junk).toARGB32(), kFallbackColor.toARGB32(), reason: 'junk: $junk');
      }

      // A bare int is a legitimate ARGB value, not junk — Flutter's own
      // Color() takes one. It is deliberately NOT sent to the fallback.
      expect(asColor(0xFF2DD4BF).toARGB32(), const Color(0xFF2DD4BF).toARGB32());
      // #RGB shorthand expands.
      expect(asColor('#F00').toARGB32(), const Color(0xFFFF0000).toARGB32());
    });

    test('asInt and asDouble cross-coerce without throwing', () {
      expect(asInt(5), 5);
      expect(asInt(5.9), 5);
      expect(asInt('7'), 7);
      expect(asDouble(1), 1.0);
      expect(asDouble('0.5'), 0.5);

      for (final junk in hostileValues) {
        expect(() => asInt(junk), returnsNormally, reason: 'asInt($junk)');
        expect(() => asDouble(junk), returnsNormally, reason: 'asDouble($junk)');
        expect(asDouble(junk).isNaN, isFalse, reason: 'asDouble($junk) is NaN');
      }
    });

    test('asWeekData always returns exactly 7 booleans', () {
      expect(asWeekData(<bool>[true, false, true]).length, 7);
      expect(asWeekData(List<bool>.filled(20, true)).length, 7);
      expect(asWeekData(null).length, 7);
      expect(asWeekData('nonsense').length, 7);
      expect(asWeekData(<Object?>[1, 0, 'yes', null, true, false, true, true, true]).length, 7);
      // A short list keeps the values it has.
      final padded = asWeekData(<bool>[true, true]);
      expect(padded.length, 7);
      expect(padded.where((b) => b).length, greaterThanOrEqualTo(2));
    });

    test('asDateTime falls back to the epoch, never to now()', () {
      final parsed = asDateTime('2026-08-31T09:14:00.000Z');
      expect(parsed.toUtc().year, 2026);
      for (final junk in <Object?>[null, '', 'yesterday', <int>[], true]) {
        expect(asDateTime(junk), kFallbackDateTime, reason: 'junk: $junk');
      }

      // A number is read as epoch millis rather than discarded — deliberate,
      // so a server that ever switches to numeric timestamps still parses.
      expect(
        asDateTime(1000).toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
    });
  });

  group('Habit', () {
    Map<String, dynamic> habitJson({Object? streak, Object? completedToday}) => {
          'id': 'h_1',
          'name': 'Steps',
          'icon': 'R',
          'color': '#2E7D32',
          'target': 10000,
          'unit': 'steps',
          'progress': 6500,
          'weekData': [true, true, true, true, true, true, true],
          if (streak != null) 'streak': streak,
          if (completedToday != null) 'completedToday': completedToday,
        };

    test('uses the SERVER streak, so a long streak is not capped at 7', () {
      // The regression this guards: deriving streak from the 7-day weekData
      // window renders a 30-day streak as "7".
      final h = Habit.fromJson(habitJson(streak: 30, completedToday: true));
      expect(h.streak, 30);
      expect(h.completedToday, isTrue);
    });

    test('falls back to deriving from weekData when the server sent none', () {
      final h = Habit.fromJson(habitJson());
      expect(h.streak, 7, reason: 'all 7 days complete');

      final local = Habit(
        id: 'local',
        name: 'New',
        icon: 'S',
        color: Colors.purple,
        target: 10,
        unit: 'x',
        progress: 0,
        weekData: List<bool>.filled(7, false),
      );
      expect(local.streak, 0);
      expect(local.completedToday, isFalse);
    });

    test('completionPercentage never divides by zero and stays in [0,1]', () {
      Habit withTarget(int target, int progress) => Habit(
            id: 'x',
            name: 'x',
            icon: 'x',
            color: Colors.red,
            target: target,
            unit: 'x',
            progress: progress,
            weekData: List<bool>.filled(7, false),
          );

      expect(withTarget(0, 5).completionPercentage, 0);
      expect(withTarget(-3, 5).completionPercentage, 0);
      expect(withTarget(10, 100).completionPercentage, 1.0);
      expect(withTarget(10, 5).completionPercentage, 0.5);
      expect(withTarget(10, 5).completionPercentage.isNaN, isFalse);
    });

    test('survives every hostile value in every field', () {
      for (final junk in hostileValues) {
        for (final key in ['id', 'name', 'icon', 'color', 'target', 'unit', 'progress', 'weekData', 'streak']) {
          final payload = habitJson()..[key] = junk;
          expect(() => Habit.fromJson(payload), returnsNormally,
              reason: 'Habit.fromJson with $key = $junk');
        }
      }
      expect(() => Habit.fromJson(const <String, dynamic>{}), returnsNormally);
    });

    test('round-trips through toJson', () {
      final h = Habit.fromJson(habitJson(streak: 12, completedToday: false));
      final back = Habit.fromJson(h.toJson());
      expect(back.streak, 12);
      expect(back.name, 'Steps');
      expect(back.target, 10000);
    });
  });

  group('HabitMonthReport', () {
    Map<String, dynamic> reportJson() => {
          'month': '2026-05',
          'days': 3,
          'habits': [
            {
              'id': 'h_1',
              'name': 'Steps',
              'icon': '👟',
              'color': '#2E7D32',
              'monthData': [true, false, null],
              'progressData': [8342, 0, null],
            },
          ],
        };

    test('parses monthData preserving null as a distinct third state', () {
      final report = HabitMonthReport.fromJson(reportJson());
      expect(report.month, '2026-05');
      expect(report.days, 3);
      expect(report.habits, hasLength(1));

      final habit = report.habits.single;
      expect(habit.name, 'Steps');
      expect(habit.monthData, [true, false, null]);
    });

    test('parses progressData keeping null distinct from a real zero', () {
      final habit = HabitMonthReport.fromJson(reportJson()).habits.single;
      expect(habit.progressData, [8342, 0, null]);
    });

    test('asNullableIntList never collapses null to zero', () {
      expect(asNullableIntList([8342, 0, null, '12']), [8342, 0, null, 12]);
      expect(asNullableIntList(null), isEmpty);
    });

    test('asTriStateList never collapses null to false', () {
      expect(asTriStateList([true, false, null, 1, 0, 'yes']),
          [true, false, null, true, false, true]);
      expect(asTriStateList(null), isEmpty);
      expect(asTriStateList('not a list'), isEmpty);
    });

    test('survives every hostile value in every field', () {
      for (final junk in hostileValues) {
        final payload = reportJson()..['month'] = junk;
        expect(() => HabitMonthReport.fromJson(payload), returnsNormally);

        final habitsPayload = reportJson();
        habitsPayload['habits'] = junk;
        expect(() => HabitMonthReport.fromJson(habitsPayload), returnsNormally);
      }
      expect(() => HabitMonthReport.fromJson(const <String, dynamic>{}), returnsNormally);
      final empty = HabitMonthReport.fromJson(const <String, dynamic>{});
      expect(empty.habits, isEmpty);
      expect(empty.days, 0);
    });
  });

  group('WalkingChallenge', () {
    Map<String, dynamic> challengeJson() => {
          'level': 'bronze',
          'streakDays': 1,
          'target': 10000,
          'nextLevel': 'silver',
          'daysToNextLevel': 2,
          'todaySteps': 6200,
          'todayStatus': 'warning',
          'history': [
            {'date': '2026-08-30', 'steps': 8100, 'target': 8000, 'status': 'met'},
          ],
        };

    test('parses every field, including nested history entries', () {
      final c = WalkingChallenge.fromJson(challengeJson());
      expect(c.level, WalkingLevel.bronze);
      expect(c.streakDays, 1);
      expect(c.target, 10000);
      expect(c.nextLevel, WalkingLevel.silver);
      expect(c.daysToNextLevel, 2);
      expect(c.todaySteps, 6200);
      expect(c.todayStatus, DayStepStatus.warning);
      expect(c.history, hasLength(1));
      expect(c.history.single.status, DayStepStatus.met);
      expect(c.history.single.steps, 8100);
    });

    test('nextLevel/daysToNextLevel are null at gold, not a parse error', () {
      final json = challengeJson()
        ..['level'] = 'gold'
        ..remove('nextLevel')
        ..remove('daysToNextLevel');
      final c = WalkingChallenge.fromJson(json);
      expect(c.level, WalkingLevel.gold);
      expect(c.nextLevel, isNull);
      expect(c.daysToNextLevel, isNull);
    });

    test('an unrecognised level/status degrades rather than throwing', () {
      final json = challengeJson()
        ..['level'] = 'platinum'
        ..['todayStatus'] = 'something_new';
      final c = WalkingChallenge.fromJson(json);
      expect(c.level, WalkingLevel.none);
      expect(c.todayStatus, DayStepStatus.noData);
    });

    test('hasWarning reflects today or the most recent committed day', () {
      const clean = WalkingChallenge(
        todayStatus: DayStepStatus.met,
        history: [
          StepDay(date: '2026-08-30', steps: 9000, target: 8000, status: DayStepStatus.met),
        ],
      );
      expect(clean.hasWarning, isFalse);

      const demoted = WalkingChallenge(
        todayStatus: DayStepStatus.met,
        history: [
          StepDay(date: '2026-08-30', steps: 3000, target: 10000, status: DayStepStatus.shortfall),
        ],
      );
      expect(demoted.hasWarning, isTrue);
    });

    test('survives every hostile value in every field', () {
      for (final junk in hostileValues) {
        for (final key in ['level', 'streakDays', 'target', 'nextLevel', 'daysToNextLevel', 'todaySteps', 'todayStatus', 'history']) {
          final payload = challengeJson()..[key] = junk;
          expect(() => WalkingChallenge.fromJson(payload), returnsNormally,
              reason: 'WalkingChallenge.fromJson with $key = $junk');
        }
      }
      expect(() => WalkingChallenge.fromJson(const <String, dynamic>{}), returnsNormally);
      final empty = WalkingChallenge.fromJson(const <String, dynamic>{});
      expect(empty.level, WalkingLevel.none);
      expect(empty.history, isEmpty);
    });
  });

  group('Friend', () {
    final json = {
      'id': 'u_1',
      'username': 'taylorm',
      'name': 'Taylor',
      'avatarColor': '#FB923C',
      'streakDays': 22,
      'completionPercentage': 0.95,
      'habitsCompleted': 5,
      'habitsTotal': 6,
      'weekData': [true, true, true, true, true, true, false],
      'lastActiveAt': '2026-08-31T08:00:00.000Z',
    };

    test('parses the contract shape', () {
      final f = Friend.fromJson(json);
      expect(f.name, 'Taylor');
      expect(f.streakDays, 22);
      expect(f.completionPercentage, closeTo(0.95, 1e-9));
      expect(f.habitsTotal, 6);
      expect(f.weekData.length, 7);
    });

    test('a friend with no habits parses to a safe zero state', () {
      final empty = Friend.fromJson({
        ...json,
        'habitsCompleted': 0,
        'habitsTotal': 0,
        'completionPercentage': 0,
        'streakDays': 0,
      });
      expect(empty.habitsTotal, 0);
      expect(empty.completionPercentage, 0);
      expect(empty.completionPercentage.isNaN, isFalse);
    });

    test('an int arriving where a double was documented still parses', () {
      final f = Friend.fromJson({...json, 'completionPercentage': 1});
      expect(f.completionPercentage, 1.0);
    });

    test('survives hostile values and an empty map', () {
      for (final junk in hostileValues) {
        for (final key in json.keys) {
          expect(() => Friend.fromJson({...json, key: junk}), returnsNormally,
              reason: 'Friend.fromJson with $key = $junk');
        }
      }
      expect(() => Friend.fromJson(const <String, dynamic>{}), returnsNormally);
    });

    test('an empty name does not break the avatar initial', () {
      final f = Friend.fromJson({...json, 'name': ''});
      // The model keeps it empty; PwAvatar is what renders the fallback. The
      // point here is only that parsing does not throw.
      expect(f.name, '');
    });
  });

  group('AppNotification', () {
    final json = {
      'id': 'nt_1',
      'type': 'nudge',
      'title': 'Alex nudged you',
      'body': 'Alex nudged you to Meditate',
      'actorId': 'u_1',
      'actorName': 'Alex',
      'avatarColor': '#2DD4BF',
      'icon': 'M',
      'color': '#A855F7',
      'refType': 'nudge',
      'refId': 'n_1',
      'read': false,
      'createdAt': '2026-08-31T09:00:00.000Z',
    };

    test('parses every documented type', () {
      const types = [
        'friend_request',
        'friend_request_accepted',
        'nudge',
        'cheer',
        'nudge_accepted',
        'friend_activity',
        'streak_milestone',
        'match_suggestion',
      ];
      for (final t in types) {
        final n = AppNotification.fromJson({...json, 'type': t});
        expect(n.type, isNot(NotificationType.unknown), reason: 'unmapped type: $t');
      }
    });

    test('an UNKNOWN server type falls back instead of throwing', () {
      final n = AppNotification.fromJson({...json, 'type': 'invented_in_v2'});
      expect(n.type, NotificationType.unknown);
      expect(n.title, isNotEmpty);
    });

    test('every nullable field may actually be null', () {
      final sparse = AppNotification.fromJson(const {
        'id': 'nt_2',
        'type': 'streak_milestone',
        'title': 'Nine day streak',
        'body': 'Keep going',
        'actorId': null,
        'actorName': null,
        'avatarColor': null,
        'icon': null,
        'color': null,
        'refType': null,
        'refId': null,
        'read': true,
        'createdAt': '2026-08-31T09:00:00.000Z',
      });
      expect(sparse.actorId, isNull);
      expect(sparse.read, isTrue);
      expect(sparse.refType, RefType.none);
    });

    test('survives hostile values', () {
      for (final junk in hostileValues) {
        for (final key in json.keys) {
          expect(() => AppNotification.fromJson({...json, key: junk}), returnsNormally,
              reason: 'AppNotification.fromJson with $key = $junk');
        }
      }
      expect(() => AppNotification.fromJson(const <String, dynamic>{}), returnsNormally);
    });
  });

  group('the remaining models all survive an empty map and hostile fields', () {
    test('no fromJson throws', () {
      expect(() => Nudge.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => FriendActivity.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => FriendHabit.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => FriendRequest.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => UserRef.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => UserProfile.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => SearchResult.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => MatchSuggestion.fromJson(const <String, dynamic>{}), returnsNormally);
      expect(() => FriendComparison.fromJson(const <String, dynamic>{}), returnsNormally);

      for (final junk in hostileValues) {
        final m = <String, dynamic>{
          'id': junk,
          'name': junk,
          'type': junk,
          'status': junk,
          'relationship': junk,
          'winner': junk,
          'verdict': junk,
          'habits': junk,
          'sharedHabits': junk,
          'matchScore': junk,
          'user': junk,
          'fromUser': junk,
          'toUser': junk,
          'me': junk,
          'friend': junk,
        };
        expect(() => Nudge.fromJson(m), returnsNormally, reason: 'Nudge with $junk');
        expect(() => FriendRequest.fromJson(m), returnsNormally, reason: 'FriendRequest with $junk');
        expect(() => SearchResult.fromJson(m), returnsNormally, reason: 'SearchResult with $junk');
        expect(() => MatchSuggestion.fromJson(m), returnsNormally, reason: 'MatchSuggestion with $junk');
        expect(() => FriendComparison.fromJson(m), returnsNormally, reason: 'FriendComparison with $junk');
        expect(() => FriendHabit.fromJson(m), returnsNormally, reason: 'FriendHabit with $junk');
      }
    });

    test('unknown enum spellings fall back rather than throwing', () {
      expect(
        SearchResult.fromJson(const {'id': 'u', 'relationship': 'invented'}).relationship,
        isNotNull,
      );
      expect(
        FriendHabit.fromJson(const {'id': 'h', 'status': 'invented'}).status,
        isNotNull,
      );
      expect(Nudge.fromJson(const {'id': 'n', 'type': 'invented'}).type, isNotNull);
    });

    test('FriendHabit.percentage guards a zero target', () {
      final h = FriendHabit.fromJson(const {
        'id': 'h',
        'name': 'Broken',
        'progress': 5,
        'target': 0,
      });
      expect(h.percentage, 0);
      expect(h.percentage.isNaN, isFalse);
    });
  });

  group('timeAgo', () {
    test('renders recent and old timestamps without throwing', () {
      DateTime ago(Duration d) => DateTime.now().subtract(d);
      final cases = <Duration>[
        Duration.zero,
        const Duration(seconds: 30),
        const Duration(minutes: 1),
        const Duration(minutes: 45),
        const Duration(hours: 1),
        const Duration(hours: 20),
        const Duration(days: 1),
        const Duration(days: 6),
        const Duration(days: 30),
        const Duration(days: 900),
      ];
      for (final d in cases) {
        final a = FriendActivity.fromJson({
          'id': 'a',
          'friendName': 'X',
          'createdAt': ago(d).toUtc().toIso8601String(),
        });
        expect(a.timeAgo, isNotEmpty, reason: 'timeAgo empty for $d');
      }
    });

    test('a future timestamp does not produce a negative string', () {
      final a = FriendActivity.fromJson({
        'id': 'a',
        'friendName': 'X',
        'createdAt': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String(),
      });
      expect(a.timeAgo, isNotEmpty);
      expect(a.timeAgo.contains('-'), isFalse, reason: 'got: ${a.timeAgo}');
    });
  });
}
