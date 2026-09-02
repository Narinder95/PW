import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/json.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// Thin JSON transport over `package:http`.
///
/// Owns exactly four concerns and no domain knowledge: bearer-token injection,
/// JSON encode/decode, a request timeout, and the normalisation of every
/// possible failure into an [ApiException]. Endpoint shapes live in `PwApi`.
///
/// The [http.Client] is injectable at construction so every layer above this
/// one can be exercised in a test with `MockClient` and no network.
class ApiClient {
  final ApiConfig config;
  final Duration timeout;

  final http.Client _http;

  /// True when this client created its own [http.Client] and therefore owns
  /// closing it. An injected client belongs to the caller.
  final bool _ownsHttpClient;

  bool _closed = false;

  /// Bearer token. `AuthService` writes it; null means unauthenticated.
  String? authToken;

  /// Invoked whenever any request comes back 401, before the exception is
  /// thrown. `AuthService` uses this to force a sign-out from anywhere in the
  /// app without every call site having to check.
  void Function()? onUnauthorized;

  ApiClient({
    http.Client? httpClient,
    ApiConfig? config,
    this.timeout = const Duration(seconds: 10),
    this.authToken,
    this.onUnauthorized,
  })  : config = config ?? ApiConfig(),
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// The underlying client, so `NotificationService` can open an SSE stream
  /// with `send()` against the same (possibly mocked) transport.
  http.Client get httpClient => _http;

  bool get hasToken => (authToken?.isNotEmpty ?? false);

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('POST', path, body: body, query: query);

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('PATCH', path, body: body, query: query);

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) =>
      _send('DELETE', path, body: body, query: query);

  /// Headers for an authenticated JSON request. Exposed so the SSE stream in
  /// `NotificationService` authenticates identically.
  Map<String, String> buildHeaders({bool json = true}) => <String, String>{
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        if (hasToken) 'Authorization': 'Bearer $authToken',
      };

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    if (_closed) {
      throw ApiException.network('The API client has been closed.');
    }

    final uri = config.resolve(path, query);
    final request = http.Request(method, uri)
      ..headers.addAll(buildHeaders(json: body != null));

    if (body != null) {
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException catch (error) {
      throw ApiException.network(
        'The server took too long to respond.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw ApiException.network(
        "Can't reach the server. Check your connection.",
        cause: error,
      );
    } on http.ClientException catch (error) {
      throw ApiException.network(
        "Can't reach the server. Check your connection.",
        cause: error,
      );
    } on HandshakeException catch (error) {
      throw ApiException.network(
        "Couldn't establish a secure connection.",
        cause: error,
      );
    }

    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    final status = response.statusCode;

    if (status == 401) {
      // Fire before throwing so the sign-out happens even if the caller
      // swallows the exception.
      onUnauthorized?.call();
    }

    if (status < 200 || status >= 300) {
      throw ApiException.fromResponse(
        status,
        response.body,
        headers: response.headers,
      );
    }

    // 204 No Content, and any 2xx with an empty body, are successes with
    // nothing to parse — several contract endpoints (logout, delete, decline)
    // return exactly that.
    if (status == 204 || response.bodyBytes.isEmpty) {
      return const <String, dynamic>{};
    }

    // Decode from bytes, not `response.body`: `http` defaults to latin-1 when
    // the server omits a charset, which mangles the emoji in habit icons.
    final String text;
    try {
      text = utf8.decode(response.bodyBytes, allowMalformed: true);
    } on FormatException catch (error) {
      throw ApiException.malformed(
        'The server sent a response we could not read.',
        statusCode: status,
        cause: error,
      );
    }

    if (text.trim().isEmpty) return const <String, dynamic>{};

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw ApiException.malformed(
        'The server sent an unexpected response.',
        statusCode: status,
        cause: error,
      );
    }

    if (decoded is Map) return asMap(decoded);

    // A bare list or scalar at the top level is off-contract; wrap it rather
    // than throw, so a caller reading a known key just sees it absent.
    return <String, dynamic>{'data': decoded};
  }

  /// Releases the underlying connection pool. Only closes an [http.Client]
  /// this instance created — an injected one is the caller's to close.
  void close() {
    if (_closed) return;
    _closed = true;
    if (_ownsHttpClient) _http.close();
  }
}
