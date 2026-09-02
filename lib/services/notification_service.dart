import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_notification.dart';
import '../models/json.dart';
import 'api/api_client.dart';
import 'api/api_exception.dart';
import 'api/pw_api.dart';

/// How the service is currently receiving notifications.
enum LiveStatus {
  /// Nothing running — before [NotificationService.start] or after
  /// [NotificationService.stop].
  idle,

  /// SSE handshake in flight.
  connecting,

  /// SSE connected; `event: ready` received.
  live,

  /// SSE unavailable; polling `unread-count` instead, retrying SSE in the
  /// background.
  polling,
}

/// The client half of the notification system.
///
/// Holds the notification list and unread count, mutates them optimistically
/// with rollback, and keeps them live over SSE with a polling fallback.
///
/// Safe to `dispose()` at any point: every timer and subscription is cancelled
/// and `notifyListeners()` is never called afterwards.
class NotificationService extends ChangeNotifier {
  final PwApi api;
  final ApiClient client;

  /// Poll interval used while SSE is unavailable.
  final Duration pollInterval;

  /// First reconnect delay. Doubles per attempt up to [maxBackoff].
  final Duration initialBackoff;

  /// Ceiling for the reconnect delay.
  final Duration maxBackoff;

  /// How many notifications to fetch per [refresh].
  final int pageLimit;

  List<AppNotification> _notifications = const <AppNotification>[];
  int _unreadCount = 0;
  bool _loading = false;
  ApiException? _lastError;
  LiveStatus _liveStatus = LiveStatus.idle;

  StreamSubscription<String>? _sseSub;
  http.Client? _sseClient;
  Timer? _pollTimer;
  Timer? _retryTimer;
  int _retryAttempt = 0;
  bool _streamWanted = false;
  bool _disposed = false;

  /// Newly-arrived notifications, for a transient in-app banner. Broadcast so
  /// a banner host and an analytics listener can both subscribe.
  final StreamController<AppNotification> _incoming =
      StreamController<AppNotification>.broadcast();

  /// Buffer for partially-received SSE text. The transport splits on
  /// arbitrary byte boundaries, so a frame can straddle two chunks.
  final StringBuffer _sseBuffer = StringBuffer();

  NotificationService({
    required this.api,
    required this.client,
    this.pollInterval = const Duration(seconds: 20),
    this.initialBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 60),
    this.pageLimit = 30,
  });

  // ------------------------------------------------------------------ state

  /// Newest first, matching the server's order.
  List<AppNotification> get notifications =>
      List<AppNotification>.unmodifiable(_notifications);

  /// The caller's total unread count — not just what is loaded.
  int get unreadCount => _unreadCount;

  bool get hasUnread => _unreadCount > 0;

  bool get isLoading => _loading;

  /// Last failure, for an error state. Cleared by a successful [refresh].
  ApiException? get lastError => _lastError;

  LiveStatus get liveStatus => _liveStatus;

  bool get isLive => _liveStatus == LiveStatus.live;

  /// True when there is nothing to show and nothing in flight — the cue for
  /// an empty state rather than a spinner.
  bool get isEmpty => _notifications.isEmpty && !_loading;

  /// Newly-arrived notifications, for a banner.
  Stream<AppNotification> get onNotification => _incoming.stream;

  // ------------------------------------------------------------------ loads

  /// Fetches the newest page and the authoritative unread count.
  Future<void> refresh() async {
    if (_disposed) return;
    _loading = true;
    _notify();

    try {
      final page = await api.getNotifications(limit: pageLimit);
      if (_disposed) return;
      _notifications = List<AppNotification>.unmodifiable(page.notifications);
      _unreadCount = page.unreadCount;
      _lastError = null;
    } on ApiException catch (error) {
      if (_disposed) return;
      _lastError = error;
    } finally {
      if (!_disposed) {
        _loading = false;
        _notify();
      }
    }
  }

  /// Refreshes just the badge. Cheap enough for an app-resume hook.
  Future<void> refreshUnreadCount() async {
    if (_disposed) return;
    try {
      final count = await api.getUnreadCount();
      if (_disposed || count == _unreadCount) return;
      _unreadCount = count;
      _notify();
    } on ApiException catch (error) {
      if (!_disposed) _lastError = error;
    }
  }

  // -------------------------------------------------------------- mutations

  /// Marks one notification read.
  ///
  /// Applied locally first so the row responds instantly, and rolled back to
  /// the exact prior list if the server rejects it.
  Future<bool> markRead(String id) async {
    if (_disposed) return false;

    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return false;
    if (_notifications[index].read) return true;

    final previousList = _notifications;
    final previousCount = _unreadCount;

    final updated = List<AppNotification>.of(_notifications);
    updated[index] = updated[index].copyWith(read: true);
    _notifications = List<AppNotification>.unmodifiable(updated);
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    _notify();

    try {
      await api.markNotificationRead(id);
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      // A 404 means it is already gone server-side; keeping the optimistic
      // state is more correct than restoring a row that no longer exists.
      if (error.isNotFound) return false;
      _notifications = previousList;
      _unreadCount = previousCount;
      _lastError = error;
      _notify();
      return false;
    }
  }

  /// Marks everything read. Optimistic, with full rollback.
  Future<bool> markAllRead() async {
    if (_disposed) return false;
    if (_unreadCount == 0 && !_notifications.any((n) => !n.read)) return true;

    final previousList = _notifications;
    final previousCount = _unreadCount;

    _notifications = List<AppNotification>.unmodifiable(
      _notifications.map((n) => n.read ? n : n.copyWith(read: true)),
    );
    _unreadCount = 0;
    _notify();

    try {
      await api.markAllNotificationsRead();
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      _notifications = previousList;
      _unreadCount = previousCount;
      _lastError = error;
      _notify();
      return false;
    }
  }

  /// Deletes one notification. Optimistic, restoring it at its original index
  /// on failure so a swipe-to-delete that fails does not also reorder the list.
  Future<bool> delete(String id) async {
    if (_disposed) return false;

    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return false;

    final previousList = _notifications;
    final previousCount = _unreadCount;
    final removed = _notifications[index];

    final updated = List<AppNotification>.of(_notifications)..removeAt(index);
    _notifications = List<AppNotification>.unmodifiable(updated);
    if (!removed.read) {
      _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    }
    _notify();

    try {
      await api.deleteNotification(id);
      return true;
    } on ApiException catch (error) {
      if (_disposed) return false;
      // Already deleted server-side: the optimistic removal was right.
      if (error.isNotFound) return true;
      _notifications = previousList;
      _unreadCount = previousCount;
      _lastError = error;
      _notify();
      return false;
    }
  }

  // ----------------------------------------------------------- live delivery

  /// Loads the first page and opens the live stream.
  ///
  /// Call after sign-in. Repeat calls while already running are no-ops.
  Future<void> start() async {
    if (_disposed || _streamWanted) return;
    _streamWanted = true;
    await refresh();
    if (_disposed || !_streamWanted) return;
    unawaited(_openStream());
  }

  /// Tears down live delivery but keeps the loaded list. Call on sign-out.
  Future<void> stop() async {
    _streamWanted = false;
    _retryAttempt = 0;
    _cancelTimers();
    await _closeStream();
    if (!_disposed) {
      _setLiveStatus(LiveStatus.idle);
    }
  }

  Future<void> _openStream() async {
    if (_disposed || !_streamWanted) return;
    if (!client.hasToken) {
      // Nothing to authenticate with; polling would 401 just as hard.
      _startPolling();
      return;
    }

    _setLiveStatus(LiveStatus.connecting);
    await _closeStream();
    _sseBuffer.clear();

    // A dedicated client: an SSE connection is held open indefinitely, and
    // closing it to reconnect must not tear down in-flight ordinary requests.
    final sseClient = http.Client();
    _sseClient = sseClient;

    try {
      final request = http.Request('GET', api.notificationStreamUri())
        ..headers.addAll(<String, String>{
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          if (client.hasToken) 'Authorization': 'Bearer ${client.authToken}',
        })
        // Without this, a proxy may buffer the whole response and nothing is
        // delivered until the connection closes.
        ..persistentConnection = true;

      // Only the handshake gets a timeout. The stream itself must be allowed
      // to idle — the server's 25s `ping` is what proves it is still alive.
      final response = await sseClient
          .send(request)
          .timeout(const Duration(seconds: 15));

      if (_disposed || !_streamWanted) {
        sseClient.close();
        return;
      }

      if (response.statusCode == 401) {
        // Let AuthService's forced sign-out handle it; do not retry a stream
        // that will keep 401ing.
        client.onUnauthorized?.call();
        _setLiveStatus(LiveStatus.idle);
        sseClient.close();
        return;
      }

      if (response.statusCode != 200) {
        throw ApiException.fromResponse(response.statusCode, '');
      }

      _sseSub = response.stream
          .transform(utf8.decoder)
          .listen(
            _onSseChunk,
            onError: (Object error) => _onStreamFailure(error),
            onDone: () => _onStreamFailure(
              // A clean close is still a disconnect; reconnect the same way.
              ApiException.network('The notification stream closed.'),
            ),
            cancelOnError: true,
          );

      _retryAttempt = 0;
      _stopPolling();
      _setLiveStatus(LiveStatus.live);
    } on Exception catch (error) {
      sseClient.close();
      if (identical(_sseClient, sseClient)) _sseClient = null;
      _onStreamFailure(error);
    }
  }

  /// Parses the SSE line protocol incrementally.
  ///
  /// Frames are `event:`/`data:` lines terminated by a blank line, and a chunk
  /// boundary can fall anywhere — including mid-line — so the tail of each
  /// chunk is held back until a newline arrives.
  void _onSseChunk(String chunk) {
    if (_disposed) return;

    _sseBuffer.write(chunk);
    final text = _sseBuffer.toString();

    // Keep everything after the last newline: it may be a partial line.
    final lastNewline = text.lastIndexOf('\n');
    if (lastNewline < 0) return;

    final complete = text.substring(0, lastNewline + 1);
    final remainder = text.substring(lastNewline + 1);
    _sseBuffer
      ..clear()
      ..write(remainder);

    for (final line in const LineSplitter().convert(complete)) {
      _onSseLine(line);
    }
  }

  String? _pendingEvent;
  final StringBuffer _pendingData = StringBuffer();

  void _onSseLine(String rawLine) {
    // Tolerate CRLF as well as LF.
    final line = rawLine.endsWith('\r')
        ? rawLine.substring(0, rawLine.length - 1)
        : rawLine;

    if (line.isEmpty) {
      _dispatchFrame();
      return;
    }

    // Comment / heartbeat line.
    if (line.startsWith(':')) return;

    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    // One optional leading space after the colon, per the SSE spec.
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _pendingEvent = value;
        break;
      case 'data':
        // Multi-line data fields are joined with newlines, per the spec.
        if (_pendingData.isNotEmpty) _pendingData.write('\n');
        _pendingData.write(value);
        break;
      case 'id':
      case 'retry':
        // Not used: the server does not replay by Last-Event-ID, and the
        // reconnect delay is the client's own backoff.
        break;
    }
  }

  void _dispatchFrame() {
    final event = _pendingEvent;
    final data = _pendingData.toString();
    _pendingEvent = null;
    _pendingData.clear();

    if (event == null && data.isEmpty) return;

    switch (event) {
      case 'ready':
        _retryAttempt = 0;
        _setLiveStatus(LiveStatus.live);
        break;
      case 'ping':
        // Liveness only. Nothing to do — receiving it is the point.
        break;
      case 'notification':
        _handleIncoming(data);
        break;
      default:
        // An event type this client does not know. Ignored, never fatal.
        break;
    }
  }

  void _handleIncoming(String data) {
    if (data.trim().isEmpty) return;

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      json = asMap(decoded);
    } on FormatException {
      // A malformed frame must not kill a live connection that is otherwise
      // delivering fine.
      return;
    }

    final notification = AppNotification.fromJson(json);
    if (notification.id.isEmpty) return;

    // The same notification can arrive twice — a reconnect that overlaps a
    // refresh, say. De-duplicate on id rather than showing it twice.
    if (_notifications.any((n) => n.id == notification.id)) return;

    _notifications = List<AppNotification>.unmodifiable(
      <AppNotification>[notification, ..._notifications],
    );
    if (!notification.read) _unreadCount++;
    _notify();

    if (!_incoming.isClosed) _incoming.add(notification);
  }

  void _onStreamFailure(Object error) {
    if (_disposed || !_streamWanted) return;

    unawaited(_closeStream());

    // Cover the gap with polling so the badge keeps moving while SSE is down.
    _startPolling();
    _scheduleReconnect();
  }

  /// Exponential backoff: 2s, 4s, 8s, 16s, 32s, then capped at 60s.
  void _scheduleReconnect() {
    if (_disposed || !_streamWanted) return;
    _retryTimer?.cancel();

    final multiplier = 1 << _retryAttempt.clamp(0, 20);
    var delayMs = initialBackoff.inMilliseconds * multiplier;
    if (delayMs > maxBackoff.inMilliseconds || delayMs <= 0) {
      delayMs = maxBackoff.inMilliseconds;
    }
    _retryAttempt++;

    _retryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_disposed || !_streamWanted) return;
      unawaited(_openStream());
    });
  }

  void _startPolling() {
    if (_disposed || !_streamWanted) return;
    _setLiveStatus(LiveStatus.polling);
    if (_pollTimer != null) return;

    // Poll immediately so the badge is not stale for a whole interval.
    unawaited(refreshUnreadCount());
    _pollTimer = Timer.periodic(pollInterval, (_) {
      if (_disposed || !_streamWanted) return;
      unawaited(refreshUnreadCount());
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _cancelTimers() {
    _stopPolling();
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _closeStream() async {
    final sub = _sseSub;
    _sseSub = null;
    // Detach the handlers first: cancelling can itself surface an onDone that
    // would otherwise schedule another reconnect.
    sub?.onError(null);
    sub?.onDone(null);
    await sub?.cancel();

    _sseClient?.close();
    _sseClient = null;

    _sseBuffer.clear();
    _pendingEvent = null;
    _pendingData.clear();
  }

  void _setLiveStatus(LiveStatus status) {
    if (_disposed || _liveStatus == status) return;
    _liveStatus = status;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Cancels every timer and subscription, closes the stream and the incoming
  /// controller. Safe at any point, including mid-reconnect and mid-request:
  /// the `_disposed` guard makes every in-flight continuation a no-op, so
  /// `notifyListeners()` is never called after this returns.
  @override
  void dispose() {
    _disposed = true;
    _streamWanted = false;
    _cancelTimers();
    // Cannot await in dispose(); the guard above already makes the service
    // inert, and closing the http.Client aborts the socket.
    unawaited(_closeStream());
    unawaited(_incoming.close());
    super.dispose();
  }
}
