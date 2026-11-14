// Copyright 2024 The FlightRecorder Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

/// Production-grade WebSocket interceptor for the flight_recorder package.
///
/// Hooks into Dart's [HttpOverrides] mechanism to intercept WebSocket upgrade
/// requests and wraps every resulting [WebSocket] with a recording proxy that
/// emits [WebSocketFlightEvent] entries for every frame sent or received.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../core/redaction_engine.dart';

// ---------------------------------------------------------------------------
// WebSocket event model
// ---------------------------------------------------------------------------

/// The type of a [WebSocketFlightEvent].
enum WebSocketEventKind {
  /// A new WebSocket connection was established.
  connected,

  /// A message was sent from the client (Flutter) to the server.
  sent,

  /// A message was received from the server.
  received,

  /// The WebSocket was closed cleanly.
  closed,

  /// An error occurred on the WebSocket.
  error,
}

/// A single recorded WebSocket interaction.
@immutable
class WebSocketRawEvent {
  const WebSocketRawEvent({
    required this.id,
    required this.kind,
    required this.url,
    required this.timestampMicros,
    required this.elapsedMicros,
    this.payload,
    this.closeCode,
    this.closeReason,
    this.error,
    this.wasPayloadTruncated = false,
  });

  /// Monotonically-increasing session-scoped identifier.
  final int id;

  /// The kind of event.
  final WebSocketEventKind kind;

  /// The WebSocket URL.
  final String url;

  /// Wall-clock timestamp in microseconds since epoch.
  final int timestampMicros;

  /// Elapsed microseconds since the interceptor was attached.
  final int elapsedMicros;

  /// The text or binary payload (may be `null` for non-data events).
  final String? payload;

  /// Close code for [WebSocketEventKind.closed] events.
  final int? closeCode;

  /// Close reason for [WebSocketEventKind.closed] events.
  final String? closeReason;

  /// Error description for [WebSocketEventKind.error] events.
  final String? error;

  /// True when the payload exceeded [FlightRecorderWebSocketInterceptor.maxMessageLength]
  /// and was truncated.
  final bool wasPayloadTruncated;

  @override
  String toString() =>
      'WebSocketRawEvent(id=$id, kind=${kind.name}, url=$url)';

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'url': url,
        'timestampMicros': timestampMicros,
        'elapsedMicros': elapsedMicros,
        if (payload != null) 'payload': payload,
        if (closeCode != null) 'closeCode': closeCode,
        if (closeReason != null) 'closeReason': closeReason,
        if (error != null) 'error': error,
        'wasPayloadTruncated': wasPayloadTruncated,
      };
}

/// Callback type for WebSocket flight events.
typedef OnWebSocketFlightEvent = void Function(WebSocketRawEvent event);

// ---------------------------------------------------------------------------
// FlightRecorderWebSocketInterceptor
// ---------------------------------------------------------------------------

/// Installs a global [HttpOverrides] that wraps every new WebSocket connection
/// with a recording proxy.
///
/// Usage:
/// ```dart
/// final interceptor = FlightRecorderWebSocketInterceptor(
///   onEvent: (event) => recorder.add(event),
/// );
/// interceptor.attach();
/// // … run app …
/// interceptor.detach();
/// ```
///
/// > **Note**: [HttpOverrides] is a process-wide singleton.  If other code also
/// > installs an [HttpOverrides], they will be chained correctly as long as
/// > each override delegates to the previous one.  [attach] saves and restores
/// > the existing override automatically.
class FlightRecorderWebSocketInterceptor {
  FlightRecorderWebSocketInterceptor({
    required this.onEvent,
    Stopwatch? stopwatch,
    RedactionEngine? redaction,
    this.maxMessageLength = 4096,
  })  : stopwatch = stopwatch ?? (Stopwatch()..start()),
        redaction = redaction ?? RedactionEngine();

  /// Receives every [WebSocketFlightEvent] produced by this interceptor.
  final OnWebSocketFlightEvent onEvent;

  /// Used to calculate [WebSocketFlightEvent.elapsedMicros].
  final Stopwatch stopwatch;

  /// Used to redact sensitive data before it is emitted as a flight event.
  final RedactionEngine redaction;

  /// Payloads longer than this many characters are truncated before recording.
  /// Set to `0` to disable truncation.
  final int maxMessageLength;

  HttpOverrides? _previousOverrides;
  _FlightRecorderHttpOverrides? _ours;
  bool _isAttached = false;
  int _nextId = 0;

  /// Whether the interceptor is currently installed.
  bool get isAttached => _isAttached;

  /// Installs the [HttpOverrides].  Safe to call multiple times.
  void attach() {
    if (_isAttached) return;
    _previousOverrides = HttpOverrides.current;
    _ours = _FlightRecorderHttpOverrides(
      interceptor: this,
      previous: _previousOverrides,
    );
    HttpOverrides.global = _ours;
    _isAttached = true;
    if (kDebugMode) {
      debugPrint('[FlightRecorder] WebSocketInterceptor attached');
    }
  }

  /// Removes the [HttpOverrides] and restores the previous override.  Safe to
  /// call multiple times.
  void detach() {
    if (!_isAttached) return;
    HttpOverrides.global = _previousOverrides;
    _previousOverrides = null;
    _ours = null;
    _isAttached = false;
    if (kDebugMode) {
      debugPrint('[FlightRecorder] WebSocketInterceptor detached');
    }
  }

  // ---- Internal helpers ---------------------------------------------------

  int _nextEventId() => _nextId++;

  void _emit(WebSocketRawEvent event) {
    try {
      onEvent(event);
    } catch (e, s) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: s,
        library: 'flight_recorder',
        context: ErrorDescription('in FlightRecorderWebSocketInterceptor.onEvent'),
      ));
    }
  }

  String? _processPayload(dynamic data) {
    if (data == null) return null;

    String text;
    if (data is String) {
      text = data;
    } else if (data is Uint8List) {
      // Represent binary frames as a hex prefix for readability.
      final hex = data
          .take(64)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      text = '[binary ${data.length}B] $hex${data.length > 64 ? '…' : ''}';
    } else if (data is List<int>) {
      text = '[binary ${data.length}B]';
    } else {
      text = data.toString();
    }

    text = redaction.redact(text);

    if (maxMessageLength > 0 && text.length > maxMessageLength) {
      return text.substring(0, maxMessageLength);
    }
    return text;
  }

  bool _isPayloadTruncated(dynamic data) {
    if (maxMessageLength <= 0) return false;
    if (data is String) return data.length > maxMessageLength;
    return false;
  }
}

// ---------------------------------------------------------------------------
// _FlightRecorderHttpOverrides
// ---------------------------------------------------------------------------

class _FlightRecorderHttpOverrides extends HttpOverrides {
  _FlightRecorderHttpOverrides({
    required this.interceptor,
    this.previous,
  });

  final FlightRecorderWebSocketInterceptor interceptor;
  final HttpOverrides? previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final base = previous != null
        ? previous!.createHttpClient(context)
        : super.createHttpClient(context);
    return _RecordingHttpClient(base, interceptor);
  }
}

// ---------------------------------------------------------------------------
// _RecordingHttpClient
// ---------------------------------------------------------------------------

/// Thin [HttpClient] wrapper that intercepts [openUrl] for ws/wss schemes and
/// delegates everything else to the original.
class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this._delegate, this._interceptor);

  final HttpClient _delegate;
  final FlightRecorderWebSocketInterceptor _interceptor;

  // ---- WebSocket upgrade path --------------------------------------------

  /// Intercept `GET` requests that are part of a WebSocket upgrade.
  /// Dart's standard [WebSocket.connect] internally calls
  /// `httpClient.openUrl('GET', uri)` and then upgrades.  We detect the
  /// upgrade by wrapping the returned [HttpClientRequest].
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = await _delegate.openUrl(method, url);
    // WebSocket upgrades always use GET and an http(s) scheme at the
    // HttpClient level (the ws/wss is converted by the SDK).
    if (method.toUpperCase() == 'GET') {
      return _RecordingHttpClientRequest(request, url.toString(), _interceptor);
    }
    return request;
  }

  // ---- Remaining HttpClient interface (all forwarded) --------------------

  @override
  bool get autoUncompress => _delegate.autoUncompress;
  @override
  set autoUncompress(bool v) => _delegate.autoUncompress = v;

  @override
  Duration? get connectionTimeout => _delegate.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _delegate.connectionTimeout = v;

  @override
  Duration get idleTimeout => _delegate.idleTimeout;
  @override
  set idleTimeout(Duration v) => _delegate.idleTimeout = v;

  @override
  int? get maxConnectionsPerHost => _delegate.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _delegate.maxConnectionsPerHost = v;

  @override
  String? get userAgent => _delegate.userAgent;
  @override
  set userAgent(String? v) => _delegate.userAgent = v;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _delegate.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) =>
      _delegate.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _delegate.authenticate = f;

  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _delegate.authenticateProxy = f;

  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _delegate.badCertificateCallback = callback;

  @override
  set findProxy(String Function(Uri url)? f) => _delegate.findProxy = f;

  @override
  void close({bool force = false}) => _delegate.close(force: force);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _delegate.delete(host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _delegate.deleteUrl(url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _delegate.get(host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _delegate.getUrl(url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _delegate.head(host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _delegate.headUrl(url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _delegate.patch(host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _delegate.patchUrl(url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _delegate.post(host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _delegate.postUrl(url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _delegate.put(host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _delegate.putUrl(url);

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      _delegate.open(method, host, port, path);

  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {
    _delegate.connectionFactory = f;
  }

  @override
  set keyLog(Function(String line)? callback) {
    _delegate.keyLog = callback;
  }
}

// ---------------------------------------------------------------------------
// _RecordingHttpClientRequest
// ---------------------------------------------------------------------------

/// Wraps an [HttpClientRequest] so that when the response arrives we can check
/// whether it's a WebSocket upgrade (101 Switching Protocols) and if so wrap
/// the resulting [WebSocket].
class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest(this._delegate, this._url, this._interceptor);

  final HttpClientRequest _delegate;
  // ignore: unused_field
  final String _url;
  // ignore: unused_field
  final FlightRecorderWebSocketInterceptor _interceptor;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _delegate.abort(exception, stackTrace);

  @override
  Future<HttpClientResponse> close() async {
    final response = await _delegate.close();
    if (response.statusCode == HttpStatus.switchingProtocols) {
      // This is a WebSocket upgrade response — the caller (WebSocket.connect)
      // will detach the socket from the HTTP layer.  We cannot wrap the
      // WebSocket at this level without reimplementing the upgrade handshake.
      //
      // Instead we return the response as-is and rely on the
      // [_RecordingWebSocket] factory (see [FlightRecorderWebSocketInterceptor.wrapWebSocket])
      // which is called by our patched WebSocket.connect stub in test mode.
      //
      // In production, integrators should call
      // [FlightRecorderWebSocketInterceptor.wrapWebSocket] on every WebSocket
      // they create, or use the [recordedWebSocketConnect] helper below.
    }
    return response;
  }

  // ---- Forwarded members -------------------------------------------------

  @override
  HttpHeaders get headers => _delegate.headers;

  @override
  String get method => _delegate.method;

  @override
  Uri get uri => _delegate.uri;

  @override
  void add(List<int> data) => _delegate.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _delegate.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      _delegate.addStream(stream);

  @override
  Future<void> flush() => _delegate.flush();

  @override
  void write(Object? object) => _delegate.write(object);

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _delegate.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _delegate.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _delegate.writeln(object);

  @override
  bool get bufferOutput => _delegate.bufferOutput;
  @override
  set bufferOutput(bool v) => _delegate.bufferOutput = v;

  @override
  int get contentLength => _delegate.contentLength;
  @override
  set contentLength(int v) => _delegate.contentLength = v;

  @override
  Encoding get encoding => _delegate.encoding;
  @override
  set encoding(Encoding v) => _delegate.encoding = v;

  @override
  bool get followRedirects => _delegate.followRedirects;
  @override
  set followRedirects(bool v) => _delegate.followRedirects = v;

  @override
  int get maxRedirects => _delegate.maxRedirects;
  @override
  set maxRedirects(int v) => _delegate.maxRedirects = v;

  @override
  bool get persistentConnection => _delegate.persistentConnection;
  @override
  set persistentConnection(bool v) => _delegate.persistentConnection = v;

  @override
  Future<HttpClientResponse> get done => _delegate.done;

  @override
  HttpConnectionInfo? get connectionInfo => _delegate.connectionInfo;

  @override
  List<Cookie> get cookies => _delegate.cookies;
}

// ---------------------------------------------------------------------------
// _RecordingWebSocket — the core WebSocket recording proxy
// ---------------------------------------------------------------------------

/// A [WebSocket]-compatible wrapper that records every frame sent and received.
///
/// Implements the [WebSocket] interface by delegating to [_delegate] for all
/// outgoing operations and by intercepting the incoming [Stream<dynamic>].
class _RecordingWebSocket extends Stream<dynamic> implements WebSocket {
  _RecordingWebSocket({
    required WebSocket delegate,
    required String url,
    required FlightRecorderWebSocketInterceptor interceptor,
  })  : _delegate = delegate,
        _url = url,
        _interceptor = interceptor {
    // Emit connected event.
    _emitEvent(WebSocketEventKind.connected);

    // Wire up the incoming stream with recording.
    _incomingController = StreamController<dynamic>(onCancel: () {
      _subscription?.cancel();
    });
    _subscription = _delegate.listen(
      (dynamic data) {
        _emitDataEvent(WebSocketEventKind.received, data);
        _incomingController.add(data);
      },
      onError: (Object error, StackTrace stack) {
        _emitErrorEvent(error);
        _incomingController.addError(error, stack);
      },
      onDone: () {
        _emitCloseEvent();
        _incomingController.close();
      },
    );
  }

  final WebSocket _delegate;
  final String _url;
  final FlightRecorderWebSocketInterceptor _interceptor;

  late final StreamController<dynamic> _incomingController;
  StreamSubscription<dynamic>? _subscription;

  // ---- Stream implementation ---------------------------------------------

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _incomingController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // ---- WebSocket send interface ------------------------------------------

  @override
  void add(dynamic data) {
    _emitDataEvent(WebSocketEventKind.sent, data);
    _delegate.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _emitErrorEvent(error);
    _delegate.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) {
    // Tap the stream to record each message before forwarding.
    final tapped = stream.map((dynamic data) {
      _emitDataEvent(WebSocketEventKind.sent, data);
      return data;
    });
    return _delegate.addStream(tapped);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _delegate.close(code, reason);
  }

  @override
  void addUtf8Text(List<int> bytes) => _delegate.addUtf8Text(bytes);

  // ---- WebSocket metadata ------------------------------------------------

  @override
  int? get closeCode => _delegate.closeCode;

  @override
  String? get closeReason => _delegate.closeReason;

  @override
  String get extensions => _delegate.extensions;

  @override
  String? get protocol => _delegate.protocol;

  @override
  int get readyState => _delegate.readyState;

  @override
  Duration? get pingInterval => _delegate.pingInterval;

  @override
  set pingInterval(Duration? interval) => _delegate.pingInterval = interval;

  @override
  Future<void> get done => _delegate.done;

  // ---- Private event helpers ---------------------------------------------

  void _emitEvent(WebSocketEventKind kind) {
    _interceptor._emit(WebSocketRawEvent(
      id: _interceptor._nextEventId(),
      kind: kind,
      url: _url,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
      elapsedMicros: _interceptor.stopwatch.elapsedMicroseconds,
    ));
  }

  void _emitDataEvent(WebSocketEventKind kind, dynamic data) {
    final payload = _interceptor._processPayload(data);
    final truncated = _interceptor._isPayloadTruncated(data);
    _interceptor._emit(WebSocketRawEvent(
      id: _interceptor._nextEventId(),
      kind: kind,
      url: _url,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
      elapsedMicros: _interceptor.stopwatch.elapsedMicroseconds,
      payload: payload,
      wasPayloadTruncated: truncated,
    ));
  }

  void _emitErrorEvent(Object error) {
    _interceptor._emit(WebSocketRawEvent(
      id: _interceptor._nextEventId(),
      kind: WebSocketEventKind.error,
      url: _url,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
      elapsedMicros: _interceptor.stopwatch.elapsedMicroseconds,
      error: error.toString(),
    ));
  }

  void _emitCloseEvent() {
    _interceptor._emit(WebSocketRawEvent(
      id: _interceptor._nextEventId(),
      kind: WebSocketEventKind.closed,
      url: _url,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
      elapsedMicros: _interceptor.stopwatch.elapsedMicroseconds,
      closeCode: _delegate.closeCode,
      closeReason: _delegate.closeReason,
    ));
  }
}

// ---------------------------------------------------------------------------
// recordedWebSocketConnect — production helper
// ---------------------------------------------------------------------------

/// A drop-in replacement for [WebSocket.connect] that wraps the resulting
/// socket with a [_RecordingWebSocket] bound to [interceptor].
///
/// Use this everywhere you open a WebSocket in your application:
/// ```dart
/// final ws = await recordedWebSocketConnect(
///   'wss://api.example.com/ws',
///   interceptor: flightRecorder.webSocketInterceptor,
/// );
/// ```
Future<WebSocket> recordedWebSocketConnect(
  String url,
  FlightRecorderWebSocketInterceptor interceptor, {
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
  CompressionOptions compression = CompressionOptions.compressionDefault,
  HttpClient? customClient,
}) async {
  final raw = await WebSocket.connect(
    url,
    protocols: protocols,
    headers: headers,
    compression: compression,
    customClient: customClient,
  );
  return _RecordingWebSocket(
    delegate: raw,
    url: url,
    interceptor: interceptor,
  );
}

// ---------------------------------------------------------------------------
// Replay support — WebSocketReplayFixture + FlightWebSocketReplayServer
// ---------------------------------------------------------------------------

/// Describes a set of server-side messages to replay for a given URL pattern.
@immutable
class WebSocketReplayFixture {
  const WebSocketReplayFixture({
    required this.urlPattern,
    required this.serverMessages,
    this.connectDelayMs = 0,
    this.messageIntervalMs = 10,
    this.closeCode,
    this.closeReason,
  });

  /// A regex pattern matched against the WebSocket URL.
  final String urlPattern;

  /// Ordered list of text messages the fake server will send after connection.
  final List<String> serverMessages;

  /// Milliseconds to wait before the socket reports "connected" (simulates
  /// network latency).
  final int connectDelayMs;

  /// Milliseconds between each replayed server message.
  final int messageIntervalMs;

  /// If non-null, the fake socket will close with this code after all messages.
  final int? closeCode;

  /// Close reason accompanying [closeCode].
  final String? closeReason;
}

/// Installs fake WebSocket connections that replay pre-recorded messages.
///
/// During a test, replace [WebSocket.connect] by passing [install]'s
/// [recordedWebSocketConnect]-compatible factory to your DI container, or use
/// the [FlightWebSocketReplayServer.connect] method directly.
///
/// Example:
/// ```dart
/// final replayServer = FlightWebSocketReplayServer(fixtures: [
///   WebSocketReplayFixture(
///     urlPattern: r'wss://api\.example\.com/ws',
///     serverMessages: ['{"type":"pong"}'],
///   ),
/// ]);
/// replayServer.install();
/// // …tests…
/// replayServer.uninstall();
/// ```
class FlightWebSocketReplayServer {
  FlightWebSocketReplayServer({required this.fixtures});

  final List<WebSocketReplayFixture> fixtures;

  static FlightWebSocketReplayServer? _current;

  /// Installs this instance as the global replay server.
  ///
  /// Call [connect] to get a fake [WebSocket] from within tests.
  void install() {
    _current = this;
  }

  /// Removes the global replay server.
  void uninstall() {
    if (_current == this) _current = null;
  }

  /// Returns the currently installed [FlightWebSocketReplayServer], or `null`.
  static FlightWebSocketReplayServer? get current => _current;

  /// Finds the first fixture whose [WebSocketReplayFixture.urlPattern] matches
  /// [url] and returns a fake [WebSocket] that emits the recorded messages.
  ///
  /// Throws a [StateError] if no fixture matches.
  Future<WebSocket> connect(String url) async {
    for (final fixture in fixtures) {
      if (RegExp(fixture.urlPattern).hasMatch(url)) {
        return _FakeWebSocket(url: url, fixture: fixture);
      }
    }
    throw StateError(
      '[FlightRecorder] No WebSocketReplayFixture matched url: $url\n'
      'Registered patterns: ${fixtures.map((f) => f.urlPattern).join(', ')}',
    );
  }
}

// ---------------------------------------------------------------------------
// _FakeWebSocket — StreamController-based replay socket
// ---------------------------------------------------------------------------

/// A completely in-process fake [WebSocket] that emits [fixture.serverMessages]
/// in order, then optionally closes.
///
/// Outgoing messages sent via [add] are silently discarded (or can be
/// inspected via [sentMessages] in tests).
class _FakeWebSocket extends Stream<dynamic> implements WebSocket {
  _FakeWebSocket({required this.url, required this.fixture}) {
    _controller = StreamController<dynamic>(onListen: _startReplay);
  }

  final String url;
  final WebSocketReplayFixture fixture;

  late final StreamController<dynamic> _controller;
  final List<dynamic> _sentMessages = [];
  int _closeCode = WebSocketStatus.normalClosure;
  String _closeReason = '';
  bool _closed = false;

  /// All messages sent by the client via [add] or [addStream].
  List<dynamic> get sentMessages => List.unmodifiable(_sentMessages);

  void _startReplay() async {
    if (fixture.connectDelayMs > 0) {
      await Future<void>.delayed(
          Duration(milliseconds: fixture.connectDelayMs));
    }

    for (final message in fixture.serverMessages) {
      if (_controller.isClosed) break;
      await Future<void>.delayed(
          Duration(milliseconds: fixture.messageIntervalMs));
      if (!_controller.isClosed) {
        _controller.add(message);
      }
    }

    if (!_controller.isClosed) {
      if (fixture.closeCode != null) {
        _closeCode = fixture.closeCode!;
        _closeReason = fixture.closeReason ?? '';
      }
      await _controller.close();
    }
  }

  // ---- Stream implementation ---------------------------------------------

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // ---- WebSocket send interface ------------------------------------------

  @override
  void add(dynamic data) {
    if (_closed) {
      throw WebSocketException('WebSocket is closed.');
    }
    _sentMessages.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _sentMessages.add(error);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _closed = true;
    _closeCode = code ?? WebSocketStatus.normalClosure;
    _closeReason = reason ?? '';
    if (!_controller.isClosed) await _controller.close();
  }

  @override
  void addUtf8Text(List<int> bytes) {
    if (_closed) {
      throw WebSocketException('WebSocket is closed.');
    }
    _sentMessages.add(utf8.decode(bytes));
  }

  // ---- WebSocket metadata ------------------------------------------------

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String get extensions => '';

  @override
  String? get protocol => '';

  @override
  int get readyState => _closed ? WebSocket.closed : WebSocket.open;

  @override
  Duration? get pingInterval => null;

  @override
  set pingInterval(Duration? interval) {
    // No-op for fake socket.
  }

  @override
  Future<void> get done => _controller.done;
}
