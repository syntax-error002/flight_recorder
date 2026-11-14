import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/event_models.dart';
import '../core/redaction_engine.dart';

typedef OnHttpFlightEvent = void Function(HttpFlightEvent event);

/// Global HTTP overrides that captures all `dart:io` HttpClient traffic.
class FlightRecorderHttpOverrides extends HttpOverrides {
  final OnHttpFlightEvent onEvent;
  final Stopwatch stopwatch;
  final RedactionEngine redaction;
  final HttpOverrides? delegate;

  FlightRecorderHttpOverrides({
    required this.onEvent,
    required this.stopwatch,
    required this.redaction,
    this.delegate,
  });

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = delegate?.createHttpClient(context) ??
        super.createHttpClient(context);
    return _FlightRecorderHttpClient(client, onEvent, stopwatch, redaction);
  }
}

class _FlightRecorderHttpClient implements HttpClient {
  final HttpClient _inner;
  final OnHttpFlightEvent _onEvent;
  final Stopwatch _stopwatch;
  final RedactionEngine _redaction;

  _FlightRecorderHttpClient(
    this._inner,
    this._onEvent,
    this._stopwatch,
    this._redaction,
  );

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final startMs = _stopwatch.elapsedMilliseconds;
    final request = await _inner.openUrl(method, url);
    return _FlightRecorderHttpClientRequest(
      request,
      method,
      url,
      startMs,
      _onEvent,
      _stopwatch,
      _redaction,
    );
  }

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) {
    return openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  void close({bool force = false}) => _inner.close(force: force);

  // Forward standard HttpClient getters and setters
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? value) => _inner.userAgent = value;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      _inner.authenticateProxy = f;

  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      _inner.badCertificateCallback = callback;

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String? proxyHost, int? proxyPort)? f) =>
      _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
}

class _FlightRecorderHttpClientRequest implements HttpClientRequest {
  final HttpClientRequest _inner;
  final String _method;
  final Uri _url;
  final int _startMs;
  final OnHttpFlightEvent _onEvent;
  final Stopwatch _stopwatch;
  final RedactionEngine _redaction;
  final BytesBuilder _requestBodyBuilder = BytesBuilder();

  _FlightRecorderHttpClientRequest(
    this._inner,
    this._method,
    this._url,
    this._startMs,
    this._onEvent,
    this._stopwatch,
    this._redaction,
  );

  @override
  void add(List<int> data) {
    if (_requestBodyBuilder.length < 32768) {
      _requestBodyBuilder.add(data);
    }
    _inner.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);

  @override
  Future addStream(Stream<List<int>> stream) {
    return _inner.addStream(stream.map((chunk) {
      if (_requestBodyBuilder.length < 32768) {
        _requestBodyBuilder.add(chunk);
      }
      return chunk;
    }));
  }

  @override
  Future flush() => _inner.flush();

  @override
  Future<HttpClientResponse> close() async {
    try {
      final response = await _inner.close();
      final endMs = _stopwatch.elapsedMilliseconds;

      final reqHeaders = <String, String>{};
      _inner.headers.forEach((name, values) {
        reqHeaders[name] = values.join(', ');
      });

      String? reqBodyStr;
      if (_requestBodyBuilder.isNotEmpty) {
        try {
          reqBodyStr = utf8.decode(_requestBodyBuilder.toBytes());
        } catch (_) {
          reqBodyStr = '[Binary Data]';
        }
      }

      return _FlightRecorderHttpClientResponse(
        response,
        _method,
        _url,
        _startMs,
        endMs - _startMs,
        reqHeaders,
        reqBodyStr,
        _onEvent,
        _redaction,
      );
    } catch (e) {
      final endMs = _stopwatch.elapsedMilliseconds;
      _onEvent(HttpFlightEvent(
        timestampMs: _startMs,
        method: _method,
        url: _url.toString(),
        statusCode: 0,
        durationMs: endMs - _startMs,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  // Delegate the rest of HttpClientRequest
  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool value) => _inner.bufferOutput = value;

  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int value) => _inner.contentLength = value;

  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool value) => _inner.followRedirects = value;

  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int value) => _inner.maxRedirects = value;

  @override
  String get method => _inner.method;

  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool value) => _inner.persistentConnection = value;

  @override
  Uri get uri => _inner.uri;

  @override
  Future<HttpClientResponse> get done => _inner.done;

  @override
  void write(Object? obj) {
    final s = obj.toString();
    add(utf8.encode(s));
  }

  @override
  void writeAll(Iterable objects, [String separator = '']) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    add([charCode]);
  }

  @override
  void writeln([Object? obj = '']) {
    write('$obj\n');
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _inner.abort(exception, stackTrace);
  }

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  List<Cookie> get cookies => _inner.cookies;
}

class _FlightRecorderHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final HttpClientResponse _inner;
  final String _method;
  final Uri _url;
  final int _startMs;
  final int _durationMs;
  final Map<String, String> _requestHeaders;
  final String? _requestBody;
  final OnHttpFlightEvent _onEvent;
  final RedactionEngine _redaction;

  final BytesBuilder _responseBodyBuilder = BytesBuilder();
  final StreamController<List<int>> _controller = StreamController<List<int>>();

  _FlightRecorderHttpClientResponse(
    this._inner,
    this._method,
    this._url,
    this._startMs,
    this._durationMs,
    this._requestHeaders,
    this._requestBody,
    this._onEvent,
    this._redaction,
  ) {
    _inner.listen(
      (chunk) {
        if (_responseBodyBuilder.length < 65536) {
          _responseBodyBuilder.add(chunk);
        }
        _controller.add(chunk);
      },
      onError: (e, s) {
        _recordEvent(error: e.toString());
        _controller.addError(e, s);
      },
      onDone: () {
        _recordEvent();
        _controller.close();
      },
      cancelOnError: false,
    );
  }

  void _recordEvent({String? error}) {
    final respHeaders = <String, String>{};
    _inner.headers.forEach((name, values) {
      respHeaders[name] = values.join(', ');
    });

    String? respBodyStr;
    if (_responseBodyBuilder.isNotEmpty) {
      try {
        respBodyStr = utf8.decode(_responseBodyBuilder.toBytes());
      } catch (_) {
        respBodyStr = '[Binary Data]';
      }
    }

    _onEvent(HttpFlightEvent(
      timestampMs: _startMs,
      method: _method,
      url: _url.toString(),
      statusCode: _inner.statusCode,
      durationMs: _durationMs,
      requestHeaders: _redaction.sanitizeHeaders(_requestHeaders),
      requestBody: _redaction.sanitizeJsonPayload(_requestBody),
      responseHeaders: _redaction.sanitizeHeaders(respHeaders),
      responseBody: _redaction.sanitizeJsonPayload(respBodyStr),
      error: error,
    ));
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
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

  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;

  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;

  @override
  int get contentLength => _inner.contentLength;

  @override
  List<Cookie> get cookies => _inner.cookies;

  @override
  Future<Socket> detachSocket() => _inner.detachSocket();

  @override
  HttpHeaders get headers => _inner.headers;

  @override
  bool get isRedirect => _inner.isRedirect;

  @override
  bool get persistentConnection => _inner.persistentConnection;

  @override
  String get reasonPhrase => _inner.reasonPhrase;

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) =>
      _inner.redirect(method, url, followLoops);

  @override
  List<RedirectInfo> get redirects => _inner.redirects;

  @override
  int get statusCode => _inner.statusCode;
}
