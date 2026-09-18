// Covers the two release-readiness fixes to the walking challenge:
//   1. A manually-logged Steps habit reflects in `challenge.todaySteps`
//      immediately, ahead of the server round trip.
//   2. Live device-step ticks update the cache instantly, but only hit
//      `POST /api/steps/sync` on a debounce or a large step jump — not once
//      per tick.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:pw/services/api/api_client.dart';
import 'package:pw/services/api/api_config.dart';
import 'package:pw/services/api/pw_api.dart';
import 'package:pw/services/step_source.dart';
import 'package:pw/services/walking_challenge_service.dart';

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.Response> Function(http.BaseRequest request) handler;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final res = await handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
      request: request,
    );
  }

  bool get hasSyncRequest => requests.any((r) => r.url.path == '/api/steps/sync');
}

http.Response _json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _challengeJson({required int todaySteps}) => {
      'challenge': {
        'level': 'none',
        'streakDays': 0,
        'target': 8000,
        'todaySteps': todaySteps,
        'todayStatus': 'no_data',
        'history': <dynamic>[],
      },
    };

/// A [StepSource] whose live stream is driven manually by the test via
/// [emit], standing in for the platform pedometer sensor.
class _FakeLiveStepSource extends StepSource {
  final _controller = StreamController<int>.broadcast();

  @override
  Future<bool> requestAuthorization() async => true;

  @override
  Future<Map<String, int>> readDailySteps({int days = 8}) async =>
      const <String, int>{};

  @override
  Stream<int> liveTodaySteps() => _controller.stream;

  void emit(int steps) => _controller.add(steps);

  Future<void> close() => _controller.close();
}

void main() {
  group('applyManualSteps', () {
    test('is a no-op until something has been loaded into challenge',
        () async {
      final client = _RecordingClient((_) async => _json(_challengeJson(todaySteps: 0)));
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api);

      await service.applyManualSteps(500);

      expect(service.challenge, isNull);
      expect(client.requests, isEmpty);
    });

    test('bumps todaySteps instantly, then reconciles with the server',
        () async {
      var serverTodaySteps = 3000;
      Completer<void>? gate;
      final client = _RecordingClient((_) async {
        if (gate != null) await gate.future;
        return _json(_challengeJson(todaySteps: serverTodaySteps));
      });
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api);

      await service.refresh();
      expect(service.challenge?.todaySteps, 3000);

      serverTodaySteps = 3500;
      gate = Completer<void>();

      // Not awaited yet: an async function body runs synchronously up to its
      // first `await`, so the optimistic bump below is already visible
      // before the (gated) reconciliation request has even been sent.
      final pending = service.applyManualSteps(3400);
      expect(service.challenge?.todaySteps, 3400);

      gate.complete();
      await pending;
      expect(service.challenge?.todaySteps, 3500);
    });

    test('never regresses the displayed total below a higher server value',
        () async {
      final client = _RecordingClient((_) async => _json(_challengeJson(todaySteps: 5000)));
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api);
      await service.refresh();
      expect(service.challenge?.todaySteps, 5000);

      // A manual log lower than what's already on screen must not visibly
      // regress the count, even for the instant before reconciliation.
      await service.applyManualSteps(1200);
      expect(service.challenge?.todaySteps, 5000);
    });
  });

  group('live tracking', () {
    late _FakeLiveStepSource stepSource;

    setUp(() => stepSource = _FakeLiveStepSource());
    tearDown(() => stepSource.close());

    test('a tick updates the cache immediately without hitting the API',
        () async {
      final client = _RecordingClient((_) async => _json(_challengeJson(todaySteps: 0)));
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api, stepSource: stepSource);

      service.startLiveTracking();
      stepSource.emit(42);
      await Future<void>.delayed(Duration.zero);

      expect(service.challenge?.todaySteps, 42);
      expect(client.requests, isEmpty);
    });

    test('a jump past the step floor syncs immediately, bypassing the debounce',
        () async {
      final client = _RecordingClient((_) async => _json(_challengeJson(todaySteps: 150)));
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api, stepSource: stepSource);

      service.startLiveTracking();
      stepSource.emit(150); // >= the 100-step immediate-sync floor
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(service.challenge?.todaySteps, 150);
      expect(client.hasSyncRequest, isTrue);
    });

    test('stopLiveTracking flushes a small pending delta rather than losing it',
        () async {
      final client = _RecordingClient((_) async => _json(_challengeJson(todaySteps: 30)));
      final api = PwApi(ApiClient(
        httpClient: client,
        config: ApiConfig(override: 'http://test.local'),
      ));
      final service = WalkingChallengeService(api: api, stepSource: stepSource);

      service.startLiveTracking();
      stepSource.emit(30); // below the immediate-sync floor
      await Future<void>.delayed(Duration.zero);
      expect(client.requests, isEmpty,
          reason: 'a small delta should sit behind the debounce, not sync yet');

      await service.stopLiveTracking();

      expect(client.hasSyncRequest, isTrue);
    });
  });
}
