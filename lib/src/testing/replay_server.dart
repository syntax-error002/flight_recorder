import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A deterministic HTTP replay server used during widget tests.
/// Matches requests against recorded session fixtures and returns responses.
class FlightReplayServer extends HttpOverrides {
  final List<ReplayFixture> fixtures;
  final bool failOnUnmatched;

  FlightReplayServer({
    required this.fixtures,
    this.failOnUnmatched = false,
  });

  /// Installs this replay server as the active HttpOverrides.
  void install() {
    HttpOverrides.global = this;
  }

  /// Restores HttpOverrides.global.
  void uninstall() {
    if (HttpOverrides.current == this) {
      HttpOverrides.global = null;
    }
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _ReplayHttpClient(this);
  }
}

class ReplayFixture {
  final String method;
  final String urlPattern;
  final int statusCode;
  final String responseBody;
  final Map<String, String> responseHeaders;

  const ReplayFixture({
    required this.method,
    required this.urlPattern,
    this.statusCode = 200,
    this.responseBody = '',
    this.responseHeaders = const {'content-type': 'application/json'},
  });

  bool matches(String reqMethod, String reqUrl) {
    if (method.toUpperCase() != reqMethod.toUpperCase()) return false;
    if (urlPattern == reqUrl) return true;
    if (reqUrl.contains(urlPattern)) return true;
    return false;
  }
}

/// Compatibility alias for [ReplayFixture].
typedef FlightFixture = ReplayFixture;

class _ReplayHttpClient implements HttpClient {
  final FlightReplayServer _server;

  _ReplayHttpClient(this._server);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _ReplayHttpClientRequest(_server, method, url);
  }

  @override
  Future<HttpClientRequest> open(
          String method, String host, int port, String path) =>
      openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));

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
  void close({bool force = false}) {}

  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  void addCredentials(
      Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set authenticate(
      Future<bool> Function(Uri url, String scheme, String? realm)? f) {}
  @override
  set authenticateProxy(
      Future<bool> Function(
              String host, int port, String scheme, String? realm)?
          f) {}
  @override
  set badCertificateCallback(
      bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  set connectionFactory(
      Future<ConnectionTask<Socket>> Function(
              Uri url, String? proxyHost, int? proxyPort)?
          f) {}
  @override
  set findProxy(String Function(Uri url)? f) {}
  @override
  set keyLog(Function(String line)? callback) {}
}

class _ReplayHttpClientRequest implements HttpClientRequest {
  final FlightReplayServer _server;
  final String _method;
  final Uri _url;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  _ReplayHttpClientRequest(this._server, this._method, this._url);

  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) async => stream.drain();

  @override
  Future flush() async {}

  @override
  Future<HttpClientResponse> close() async {
    final urlStr = _url.toString();
    final fixture = _server.fixtures.firstWhere(
      (f) => f.matches(_method, urlStr),
      orElse: () {
        if (_server.failOnUnmatched) {
          throw StateError('No replay fixture for $_method $urlStr');
        }
        return ReplayFixture(
          method: _method,
          urlPattern: urlStr,
          statusCode: 200,
          responseBody: '{}',
        );
      },
    );

    return _ReplayHttpClientResponse(fixture);
  }

  @override
  bool bufferOutput = false;
  @override
  int contentLength = -1;
  @override
  Encoding encoding = utf8;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  String get method => _method;
  @override
  bool persistentConnection = false;
  @override
  Uri get uri => _url;
  @override
  Future<HttpClientResponse> get done => close();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => [];
  @override
  void write(Object? obj) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? obj = '']) {}
}

class _ReplayHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final ReplayFixture _fixture;
  late final List<int> _bytes;

  _ReplayHttpClientResponse(this._fixture) {
    _bytes = utf8.encode(_fixture.responseBody);
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  int get statusCode => _fixture.statusCode;
  @override
  int get contentLength => _bytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpHeaders get headers => _MockHttpHeaders(_fixture.responseHeaders);
  @override
  String get reasonPhrase => 'OK';
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => [];
  @override
  Future<Socket> detachSocket() => throw UnsupportedError('Replay only');
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) =>
      throw UnsupportedError('Replay only');
  @override
  List<RedirectInfo> get redirects => [];
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  _MockHttpHeaders([Map<String, String>? initial]) {
    if (initial != null) {
      initial.forEach((k, v) => _headers[k.toLowerCase()] = [v]);
    }
  }

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];
  @override
  String? value(String name) => _headers[name.toLowerCase()]?.firstOrNull;
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  void remove(String name, Object value) => _headers.remove(name.toLowerCase());
  @override
  void removeAll(String name) => _headers.remove(name.toLowerCase());
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _headers.forEach(action);
  @override
  void noFolding(String name) {}
  @override
  void clear() => _headers.clear();

  @override
  bool chunkedTransferEncoding = false;
  @override
  int contentLength = -1;
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  String? host;
  @override
  DateTime? ifModifiedSince;
  @override
  bool persistentConnection = false;
  @override
  int? port;
}
