import 'package:flutter/material.dart';

/// Defensive JSON coercion helpers shared by every model in `lib/models`.
///
/// The rule for this layer: **a malformed payload must never throw.** The
/// backend is built in parallel against `docs/API_CONTRACT.md`; if a field
/// arrives null, missing, as an `int` where a `double` was documented, as a
/// `String` where a number was documented, or as an enum spelling nobody has
/// seen before, the client degrades to a documented fallback instead of
/// blowing up a whole screen. Everything in here is total.

/// Colour returned when a colour string is missing or unparseable.
///
/// Neutral grey: it never impersonates one of the six habit accents, so a
/// garbage colour is visually obvious in QA without being an error state.
const Color kFallbackColor = Color(0xFF9E9E9E);

/// Timestamp returned by [asDateTime] when the value is missing or garbage.
///
/// The Unix epoch rather than `DateTime.now()`: `now()` would make a broken
/// row look freshly created and would make the value non-deterministic across
/// two reads of the same payload.
final DateTime kFallbackDateTime =
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Reads `json[key]` from anything map-shaped, tolerating a null container.
Object? pick(Map<String, dynamic>? json, String key) =>
    json == null ? null : json[key];

/// Coerces [value] to a `Map<String, dynamic>`; `{}` for anything else.
Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), v));
  }
  return const <String, dynamic>{};
}

/// Coerces [value] to a nullable map. Distinguishes "absent" from "empty",
/// which matters for optional envelope members such as `activity` on a log.
Map<String, dynamic>? asMapOrNull(Object? value) {
  if (value == null) return null;
  if (value is Map) return asMap(value);
  return null;
}

/// Coerces [value] to a list of maps, dropping any element that is not
/// map-shaped rather than failing the whole list.
List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is Map) out.add(asMap(item));
  }
  return out;
}

/// Maps a JSON list into models via [build], skipping non-map elements.
List<T> asModelList<T>(
  Object? value,
  T Function(Map<String, dynamic>) build,
) =>
    asMapList(value).map(build).toList(growable: false);

/// Coerces [value] to a `String`. Numbers and bools are stringified so an id
/// that arrives numeric (the contract says ids are opaque strings, but a
/// backend may still emit `1`) does not become an empty id.
String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return fallback;
}

/// As [asString] but preserves a genuinely absent value as `null`.
String? asStringOrNull(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  return null;
}

/// Coerces [value] to an `int`, accepting `double` (truncated) and numeric
/// strings. Non-finite doubles fall back rather than throwing on `toInt()`.
int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : fallback;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
    final asNum = double.tryParse(value.trim());
    if (asNum != null && asNum.isFinite) return asNum.toInt();
  }
  return fallback;
}

/// As [asInt] but preserves absent/unparseable as `null`.
int? asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is double) return value.isFinite ? value.toInt() : null;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// Coerces [value] to a `double`, accepting `int` and numeric strings.
/// NaN and infinity are rejected: they propagate into layout constraints and
/// crash the render tree far away from the parse site.
double asDouble(Object? value, [double fallback = 0]) {
  if (value is double) return value.isFinite ? value : fallback;
  if (value is int) return value.toDouble();
  if (value is num) {
    final d = value.toDouble();
    return d.isFinite ? d : fallback;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim());
    if (parsed != null && parsed.isFinite) return parsed;
  }
  return fallback;
}

/// [asDouble] clamped into `[0, 1]`. For ratio fields such as
/// `completionPercentage`, which the contract documents as a double in [0,1]
/// but which a buggy server could send as `95` (meaning 95%).
double asRatio(Object? value, [double fallback = 0]) {
  final raw = asDouble(value, fallback);
  return raw.clamp(0.0, 1.0).toDouble();
}

/// Coerces [value] to a `bool`, accepting 0/1 and "true"/"false"/"yes"/"no".
bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'y':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'n':
        return false;
    }
  }
  return fallback;
}

/// Parses an ISO-8601 timestamp. Also accepts epoch milliseconds as a number,
/// which is what a hand-rolled serialiser tends to emit by accident.
DateTime asDateTime(Object? value, {DateTime? fallback}) =>
    asDateTimeOrNull(value) ?? fallback ?? kFallbackDateTime;

/// As [asDateTime] but returns `null` for a documented-nullable timestamp
/// (`acceptedAt`, `respondedAt`, `lastActiveAt`).
DateTime? asDateTimeOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true)
        .toLocal();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return DateTime.tryParse(trimmed)?.toLocal();
  }
  return null;
}

/// Formats a `DateTime` back to the contract's ISO-8601 UTC form.
String? isoOrNull(DateTime? value) => value?.toUtc().toIso8601String();

/// Renders a date at day granularity (`YYYY-MM-DD`) for `?date=` parameters.
String asDateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$month-$day';
}

/// Parses a colour string.
///
/// Accepts `#RRGGBB`, `#AARRGGBB`, the same two without the leading `#`, the
/// 3-digit `#RGB` shorthand, and a raw ARGB int. Anything else — an empty
/// string, `"red"`, a truncated hex, a list — yields [kFallbackColor] (or an
/// explicit [fallback]). Never throws.
Color asColor(Object? value, [Color fallback = kFallbackColor]) {
  if (value is Color) return value;
  if (value is int) return Color(value);
  if (value is! String) return fallback;

  var hex = value.trim();
  if (hex.isEmpty) return fallback;
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.startsWith('0x') || hex.startsWith('0X')) hex = hex.substring(2);

  // #RGB shorthand -> #RRGGBB
  if (hex.length == 3) {
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return fallback;

  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}

/// As [asColor] but keeps a documented-nullable colour null.
Color? asColorOrNull(Object? value) {
  if (value == null) return null;
  if (value is String && value.trim().isEmpty) return null;
  // Sentinel round-trip: if parsing degraded to the fallback and the input was
  // not literally the fallback, treat it as absent rather than as grey.
  final probe = asColor(value, const Color(0x00000001));
  return probe == const Color(0x00000001) ? null : probe;
}

/// Serialises a [Color] to the contract's `#RRGGBB` form (alpha dropped, since
/// the contract only ever carries opaque avatar/habit colours).
String colorToHex(Color color) {
  final argb = color.toARGB32();
  final rgb = (argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${rgb.toUpperCase()}';
}

/// Coerces [value] to a `List<String>`, stringifying scalar elements and
/// dropping anything that cannot be represented.
List<String> asStringList(Object? value) {
  if (value is! List) return const <String>[];
  final out = <String>[];
  for (final item in value) {
    if (item == null) continue;
    if (item is String) {
      out.add(item);
    } else if (item is num || item is bool) {
      out.add(item.toString());
    }
  }
  return List<String>.unmodifiable(out);
}

/// Number of days the week strip renders. The contract guarantees length 7,
/// oldest first, index 6 = today — but the client must survive a server that
/// forgets.
const int kWeekLength = 7;

/// Coerces [value] to exactly [kWeekLength] booleans.
///
/// Short lists are **left-padded** with `false` and long lists are trimmed
/// from the front, because index 6 must stay "today": dropping from the tail
/// would silently relabel every day in the strip.
List<bool> asWeekData(Object? value) {
  if (value is! List || value.isEmpty) {
    return List<bool>.filled(kWeekLength, false, growable: false);
  }
  final parsed = value.map<bool>(asBool).toList();
  if (parsed.length == kWeekLength) {
    return List<bool>.unmodifiable(parsed);
  }
  if (parsed.length > kWeekLength) {
    return List<bool>.unmodifiable(
      parsed.sublist(parsed.length - kWeekLength),
    );
  }
  return List<bool>.unmodifiable(<bool>[
    ...List<bool>.filled(kWeekLength - parsed.length, false),
    ...parsed,
  ]);
}

/// Coerces [value] to a `List<bool?>`, preserving explicit nulls — used for
/// tri-state day data (complete / missed / no-data) where collapsing null to
/// `false` would draw a habit as missed on a day it didn't exist yet.
/// Non-null, non-bool elements degrade to `false` rather than being dropped,
/// which would shift every later day's index.
List<bool?> asTriStateList(Object? value) {
  if (value is! List) return const <bool?>[];
  return List<bool?>.unmodifiable(
    value.map<bool?>((e) => e == null ? null : asBool(e)),
  );
}

/// Coerces [value] to a `List<int?>`, preserving explicit nulls — used for
/// `progressData`, where `null` means "no log row" and must stay distinct
/// from a real `0` (the user logged zero that day).
List<int?> asNullableIntList(Object? value) {
  if (value is! List) return const <int?>[];
  return List<int?>.unmodifiable(
    value.map<int?>((e) => e == null ? null : asInt(e)),
  );
}

/// Renders a date at month granularity (`YYYY-MM`) for `?month=` parameters.
String asYearMonth(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

/// Resolves an enum from its wire spelling via [table], falling back to
/// [fallback] for null, a non-string, or an unrecognised value.
///
/// Matching is case-insensitive and tolerates `camelCase` where the contract
/// uses `snake_case` (and vice versa), so `requestSent` and `request_sent`
/// both resolve.
T asEnum<T>(Object? value, Map<String, T> table, T fallback) {
  if (value is T) return value;
  final raw = asStringOrNull(value);
  if (raw == null) return fallback;

  final direct = table[raw];
  if (direct != null) return direct;

  final needle = _enumKey(raw);
  for (final entry in table.entries) {
    if (_enumKey(entry.key) == needle) return entry.value;
  }
  return fallback;
}

String _enumKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Drops null values so a PATCH body carries only the fields being changed.
/// The contract's PATCH endpoints treat an absent key as "leave alone", which
/// is not the same as an explicit null.
Map<String, dynamic> compactJson(Map<String, dynamic> source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    if (value != null) out[key] = value;
  });
  return out;
}

/// Relative-time label shared by every model that shows "x ago".
///
/// Kept in one place so the Nudge card and the Activity card can never drift
/// apart. A future timestamp (clock skew between device and server) reads as
/// "now" rather than as a negative duration.
String relativeTimeLabel(DateTime timestamp, {String justNow = 'now'}) {
  final diff = DateTime.now().difference(timestamp);
  if (diff.isNegative || diff.inMinutes < 1) return justNow;
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min${diff.inMinutes > 1 ? 's' : ''} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
  final weeks = diff.inDays ~/ 7;
  return '$weeks week${weeks > 1 ? 's' : ''} ago';
}
