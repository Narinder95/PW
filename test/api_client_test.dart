// The transport layer's job is to turn every possible server reply — including
// the ones that are not JSON at all — into a typed ApiException the UI can
// branch on, and to never let a raw exception reach a screen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:pw/services/api/api_client.dart';
import 'package:pw/services/api/api_config.dart';
import 'package:pw/services/api/api_exception.dart';

/// An http.Client that returns whatever the test tells it to.
class FakeClient extends http.BaseClient {
  FakeClient(this.handler);

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
}

ApiClient clientReturning(
  Future<http.Response> Function(http.BaseRequest) handler, {
  String? token,
  void Function()? onUnauthorized,
}) =>
    ApiClient(
      httpClient: FakeClient(handler),
      config: ApiConfig(override: 'http://test.local'),
      authToken: token,
      onUnauthorized: onUnauthorized,
    );

http.Response json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('happy path', () {
    test('decodes a JSON object', () async {
      final api = clientReturning((_) async => json({'ok': true}, 200));
      final res = await api.get('/api/health');
      expect(res, isA<Map<String, dynamic>>());
      expect((res as Map)['ok'], isTrue);
    });

    test('sends the bearer token when there is one, and omits it when not',
        () async {
      final withToken = FakeClient((_) async => json({}, 200));
      await ApiClient(
        httpClient: withToken,
        config: ApiConfig(override: 'http://test.local'),
        authToken: 'tok-123',
      ).get('/api/me');
      expect(withToken.requests.single.headers['Authorization'], 'Bearer tok-123');

      final without = FakeClient((_) async => json({}, 200));
      await ApiClient(
        httpClient: without,
        config: ApiConfig(override: 'http://test.local'),
      ).get('/api/health');
      expect(without.requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('a 204 with an empty body is not a parse error', () async {
      final api = clientReturning((_) async => http.Response('', 204));
      await expectLater(api.post('/api/notifications/x/read'), completes);
    });

    test('builds the URL from the configured base', () async {
      final fake = FakeClient((_) async => json({}, 200));
      await ApiClient(
        httpClient: fake,
        config: ApiConfig(override: 'http://staging.example:9000'),
      ).get('/api/friends');
      expect(fake.requests.single.url.toString(), 'http://staging.example:9000/api/friends');
    });
  });

  group('error envelope mapping', () {
    Future<ApiException> capture(Future<void> Function() action) async {
      try {
        await action();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('maps the documented codes onto the typed checks', () async {
      final cases = <int, String>{
        400: 'validation_error',
        401: 'unauthorized',
        403: 'forbidden',
        404: 'not_found',
        409: 'conflict',
        429: 'rate_limited',
        500: 'internal',
      };

      for (final entry in cases.entries) {
        final api = clientReturning(
          (_) async => json({
            'error': {'code': entry.value, 'message': 'nope'}
          }, entry.key),
        );
        final e = await capture(() => api.get('/api/x'));
        expect(e.code, entry.value, reason: 'status ${entry.key}');
        expect(e.statusCode, entry.key);
      }
    });

    test('the typed predicates match the codes', () async {
      Future<ApiException> forStatus(int status, String code) async {
        final api = clientReturning(
          (_) async => json({
            'error': {'code': code, 'message': 'x'}
          }, status),
        );
        return capture(() => api.get('/api/x'));
      }

      expect((await forStatus(401, 'unauthorized')).isUnauthorized, isTrue);
      expect((await forStatus(403, 'forbidden')).isForbidden, isTrue);
      expect((await forStatus(404, 'not_found')).isNotFound, isTrue);
      expect((await forStatus(409, 'conflict')).isConflict, isTrue);
      expect((await forStatus(429, 'rate_limited')).isRateLimited, isTrue);
    });

    test('carries `field` on a validation error', () async {
      final api = clientReturning(
        (_) async => json({
          'error': {'code': 'validation_error', 'message': 'too short', 'field': 'password'}
        }, 400),
      );
      final e = await capture(() => api.post('/api/auth/register'));
      expect(e.field, 'password');
      expect(e.message, 'too short');
    });

    test('carries retryAfterSeconds on a nudge cooldown', () async {
      final api = clientReturning(
        (_) async => json({
          'error': {
            'code': 'rate_limited',
            'message': 'slow down',
            'retryAfterSeconds': 1800,
          }
        }, 429),
      );
      final e = await capture(() => api.post('/api/nudges'));
      expect(e.isRateLimited, isTrue);
      expect(e.retryAfterSeconds, 1800);
    });

    test('a 401 fires the onUnauthorized hook so the app can sign out', () async {
      var fired = 0;
      final api = clientReturning(
        (_) async => json({
          'error': {'code': 'unauthorized', 'message': 'nope'}
        }, 401),
        token: 'stale',
        onUnauthorized: () => fired++,
      );
      await capture(() => api.get('/api/me'));
      expect(fired, 1);
    });
  });

  group('replies that are not the envelope at all', () {
    Future<ApiException> capture(Future<void> Function() action) async {
      try {
        await action();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('an HTML error page still yields a typed exception', () async {
      final api = clientReturning(
        (_) async => http.Response(
          '<!doctype html><h1>502 Bad Gateway</h1>',
          502,
          headers: {'content-type': 'text/html'},
        ),
      );
      final e = await capture(() => api.get('/api/friends'));
      expect(e, isA<ApiException>());
      expect(e.statusCode, 502);
      expect(e.message, isNotEmpty);
      // Never leak raw markup into something a user might see.
      expect(e.message.contains('<'), isFalse, reason: 'got: ${e.message}');
    });

    test('an empty error body still yields a typed exception', () async {
      final api = clientReturning((_) async => http.Response('', 500));
      final e = await capture(() => api.get('/api/friends'));
      expect(e.statusCode, 500);
      expect(e.message, isNotEmpty);
    });

    test('malformed JSON in a 200 is a malformed_response, not a crash', () async {
      final api = clientReturning(
        (_) async => http.Response('{"friends": [', 200,
            headers: {'content-type': 'application/json'}),
      );
      final e = await capture(() => api.get('/api/friends'));
      expect(e.code, ApiException.codeMalformed);
    });

    test('an error envelope missing its code still maps by status', () async {
      final api = clientReturning(
        (_) async => json({'error': {'message': 'something'}}, 403),
      );
      final e = await capture(() => api.get('/api/friends/x'));
      expect(e.statusCode, 403);
      expect(e.isForbidden, isTrue);
    });
  });

  group('transport failures become code=network', () {
    Future<ApiException> capture(Future<void> Function() action) async {
      try {
        await action();
      } on ApiException catch (e) {
        return e;
      }
      fail('expected an ApiException');
    }

    test('a refused socket', () async {
      final api = clientReturning(
        (_) async => throw const SocketException('Connection refused'),
      );
      final e = await capture(() => api.get('/api/health'));
      expect(e.code, ApiException.codeNetwork);
      expect(e.isNetwork, isTrue);
      expect(e.statusCode, isNull);
    });

    test('an http.ClientException', () async {
      final api = clientReturning((_) async => throw http.ClientException('boom'));
      final e = await capture(() => api.get('/api/health'));
      expect(e.isNetwork, isTrue);
    });

    test('a timeout', () async {
      final api = ApiClient(
        httpClient: FakeClient((_) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return json({}, 200);
        }),
        config: ApiConfig(override: 'http://test.local'),
        timeout: const Duration(milliseconds: 50),
      );
      final e = await capture(() => api.get('/api/health'));
      expect(e.isNetwork, isTrue);
    });

    test('a network failure is never reported as unauthorized', () async {
      var signedOut = 0;
      final api = clientReturning(
        (_) async => throw const SocketException('down'),
        onUnauthorized: () => signedOut++,
      );
      await capture(() => api.get('/api/me'));
      expect(signedOut, 0, reason: 'a flaky network must not sign the user out');
    });
  });

  group('ApiConfig', () {
    test('strips trailing slashes and treats blank as no override', () {
      expect(ApiConfig(override: 'http://x:8080/').baseUrl, 'http://x:8080');
      expect(ApiConfig(override: 'http://x:8080///').baseUrl, 'http://x:8080');
      expect(ApiConfig(override: '   ').hasOverride, isFalse);
      expect(ApiConfig(override: null).hasOverride, isFalse);
    });

    test('resolve drops null query values and stringifies the rest', () {
      final c = ApiConfig(override: 'http://x:8080');
      expect(c.resolve('/api/activity').toString(), 'http://x:8080/api/activity');
      final uri = c.resolve('/api/activity', {'limit': 20, 'before': null, 'unreadOnly': true});
      expect(uri.queryParameters['limit'], '20');
      expect(uri.queryParameters['unreadOnly'], 'true');
      expect(uri.queryParameters.containsKey('before'), isFalse);
    });

    test('a leading slash is optional', () {
      final c = ApiConfig(override: 'http://x:8080');
      expect(c.resolve('api/me').toString(), 'http://x:8080/api/me');
    });
  });
}
