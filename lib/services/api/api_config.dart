import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the backend base URL, with a persisted runtime override.
///
/// All builds default to the remote hosted API (Render). QA can override this
/// with a persisted value without a rebuild; it survives a restart via
/// shared_preferences.
class ApiConfig {
  /// shared_preferences key for the override. Namespaced so it cannot collide
  /// with the auth token or any UI preference.
  static const String prefsKey = 'pw.api.baseUrl';

  /// The real, hosted API (Render + Neon Postgres). Used by both release
  /// builds and development builds — no need for a local backend.
  static const String _remoteDefault = 'https://habitpet-api.onrender.com';

  String? _override;

  /// [override] seeds the value without touching shared_preferences, which is
  /// what tests want (no plugin, no async).
  ApiConfig({String? override}) : _override = _normalise(override);

  /// Platform default, ignoring any override.
  /// All builds use the remote hosted API.
  static String get platformDefault => _remoteDefault;

  /// The base URL in force: an explicit override, else [platformDefault].
  /// Never has a trailing slash.
  String get baseUrl => _override ?? platformDefault;

  /// Whether a non-default host is currently in force.
  bool get hasOverride => _override != null;


  /// Loads a persisted override. Safe to call before `runApp` completes; a
  /// missing plugin (unit test, unsupported platform) leaves the default in
  /// place rather than throwing.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _override = _normalise(prefs.getString(prefsKey));
    } on Exception {
      _override = null;
    }
  }

  /// Sets and persists the override. Pass null to clear it and fall back to
  /// [platformDefault].
  Future<void> setBaseUrl(String? value) async {
    _override = _normalise(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_override == null) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, _override!);
      }
    } on Exception {
      // Persisting is best-effort: the in-memory override still applies for
      // this run, which is what a QA session actually needs.
    }
  }

  /// Sets the override for this run only, without persisting.
  void setBaseUrlInMemory(String? value) => _override = _normalise(value);

  /// Builds an absolute [Uri] for [path], appending [query].
  ///
  /// Null query values are dropped (an absent `?before=` is not the same as an
  /// empty one), and non-string values are stringified, so callers can pass
  /// ints and bools directly.
  Uri resolve(String path, [Map<String, dynamic>? query]) {
    final normalisedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl$normalisedPath');

    if (query == null || query.isEmpty) return uri;

    final params = <String, String>{...uri.queryParameters};
    query.forEach((key, value) {
      if (value == null) return;
      params[key] = value is String ? value : '$value';
    });
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  /// Trims whitespace and any trailing slash; empty becomes null so a blank
  /// text field clears the override instead of producing `http:///api/...`.
  static String? _normalise(String? value) {
    if (value == null) return null;
    var trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() => 'ApiConfig($baseUrl${hasOverride ? ' [override]' : ''})';
}
