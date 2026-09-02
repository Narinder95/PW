import 'dart:convert';

import '../../models/json.dart';

/// Every failure the API layer can produce, normalised to one type.
///
/// The contract's error envelope is
/// `{"error": {"code": ..., "message": ..., "field": ...}}`, but the client
/// also has to survive responses that are *not* that: an HTML 502 page from a
/// proxy, an empty body, a truncated JSON document. [ApiException.fromResponse]
/// is total — it always produces an exception rather than throwing a second,
/// less useful one out of the parser.
class ApiException implements Exception {
  /// Machine-readable code. Contract codes are `validation_error`,
  /// `unauthorized`, `forbidden`, `not_found`, `conflict`, `rate_limited` and
  /// `internal`. The client adds [codeNetwork] and [codeMalformed].
  final String code;

  /// Human-readable text. Safe to show in a snackbar.
  final String message;

  /// HTTP status, or null for a transport failure that never got one.
  final int? statusCode;

  /// Which input field failed, on a `validation_error`.
  final String? field;

  /// Seconds to wait, on a `rate_limited` nudge cooldown.
  final int? retryAfterSeconds;

  /// The underlying error (SocketException, FormatException, ...), for logs.
  final Object? cause;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.field,
    this.retryAfterSeconds,
    this.cause,
  });

  /// No usable connection: DNS failure, refused socket, timeout, aborted
  /// request. Client-side only — the server never sends this code.
  static const String codeNetwork = 'network';

  /// A 2xx response whose body could not be understood.
  static const String codeMalformed = 'malformed_response';

  factory ApiException.network(String message, {Object? cause}) =>
      ApiException(code: codeNetwork, message: message, cause: cause);

  factory ApiException.malformed(String message, {int? statusCode, Object? cause}) =>
      ApiException(
        code: codeMalformed,
        message: message,
        statusCode: statusCode,
        cause: cause,
      );

  /// Builds an exception from a non-2xx HTTP response.
  ///
  /// [headers] is consulted for `Retry-After` when the body omits
  /// `retryAfterSeconds`, since a reverse proxy may be the one rate-limiting.
  factory ApiException.fromResponse(
    int statusCode,
    String body, {
    Map<String, String>? headers,
  }) {
    Map<String, dynamic> error = const <String, dynamic>{};

    if (body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final envelope = asMap(decoded);
          // Accept both `{"error": {...}}` and a bare `{code, message}`, so a
          // slightly-off backend still yields a typed error.
          error = envelope['error'] is Map
              ? asMap(envelope['error'])
              : envelope;
        }
      } on FormatException {
        // Not JSON at all — an HTML error page or a truncated body. Fall
        // through to the status-derived defaults below.
        error = const <String, dynamic>{};
      }
    }

    final code = asStringOrNull(error['code']) ?? _codeForStatus(statusCode);
    final message = asStringOrNull(error['message']) ??
        _messageForStatus(statusCode, body);

    return ApiException(
      code: code,
      message: message,
      statusCode: statusCode,
      field: asStringOrNull(error['field']),
      retryAfterSeconds: asIntOrNull(error['retryAfterSeconds']) ??
          asIntOrNull(headers?['retry-after']),
    );
  }

  static String _codeForStatus(int status) {
    switch (status) {
      case 400:
        return 'validation_error';
      case 401:
        return 'unauthorized';
      case 403:
        return 'forbidden';
      case 404:
        return 'not_found';
      case 409:
        return 'conflict';
      case 429:
        return 'rate_limited';
      default:
        return status >= 500 ? 'internal' : 'http_$status';
    }
  }

  static String _messageForStatus(int status, String body) {
    switch (status) {
      case 400:
        return 'That request was not valid.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return "You don't have access to that.";
      case 404:
        return 'That could not be found.';
      case 409:
        return 'That conflicts with something that already exists.';
      case 429:
        return 'Too many requests. Please wait a moment.';
    }
    if (status >= 500) return 'The server had a problem. Please try again.';
    // Last resort: a short slice of the body beats an empty message when
    // debugging an unexpected status, but never a whole HTML page.
    final snippet = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (snippet.isEmpty) return 'Request failed ($status).';
    return snippet.length > 120
        ? '${snippet.substring(0, 120)}...'
        : snippet;
  }

  /// No/expired token, or bad credentials on login. Triggers a forced
  /// sign-out everywhere except the login screen itself.
  bool get isUnauthorized => statusCode == 401 || code == 'unauthorized';

  /// Authenticated but not allowed — e.g. viewing a non-friend's habits.
  bool get isForbidden => statusCode == 403 || code == 'forbidden';

  bool get isNotFound => statusCode == 404 || code == 'not_found';

  /// Duplicate: username taken, already friends, request already exists.
  bool get isConflict => statusCode == 409 || code == 'conflict';

  /// Nudge cooldown. See [retryAfterSeconds].
  bool get isRateLimited => statusCode == 429 || code == 'rate_limited';

  bool get isValidationError =>
      statusCode == 400 || code == 'validation_error';

  /// Transport failure — worth offering a "Retry" button for.
  bool get isNetwork => code == codeNetwork;

  /// 5xx.
  bool get isServerError => (statusCode ?? 0) >= 500;

  /// True when retrying unchanged could plausibly succeed.
  bool get isRetryable => isNetwork || isServerError || isRateLimited;

  @override
  String toString() =>
      'ApiException($code${statusCode == null ? '' : ' $statusCode'}: '
      '$message${field == null ? '' : ' [$field]'})';
}
