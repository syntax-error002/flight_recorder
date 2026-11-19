import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';

import '../core/event_models.dart';
import '../core/ring_buffer.dart';
import '../core/serializer.dart';
import '../core/session_manifest.dart';
import '../interceptors/error_interceptor.dart';
import '../interceptors/http_interceptor.dart';
import '../interceptors/lifecycle_observer.dart';
import '../interceptors/navigation_observer.dart';
import '../interceptors/platform_channel_interceptor.dart';
import '../interceptors/pointer_interceptor.dart';
import '../interceptors/text_input_interceptor.dart';
import '../interceptors/websocket_interceptor.dart';
import '../serializer/secure_serializer.dart';
import 'flight_config.dart';

/// The central coordinator managing active session recording, ring buffer,
/// interceptors, and automated crash dump generation.
class FlightRecorder {
  static FlightRecorder? _instance;
  static FlightRecorder get instance {
    _instance ??= FlightRecorder._();
    return _instance!;
  }

  FlightRecorder._();

  FlightConfig _config = FlightConfig();
  final Stopwatch _stopwatch = Stopwatch();

  // ---------------------------------------------------------------------------
  // FIX #1: Changed from `late` to nullable so that snapshot()/dumpSession()
  // can guard against being called before start(), and so that stop() can null
  // it out rather than leaving a stale buffer that would be silently reused.
  // ---------------------------------------------------------------------------
  EventRingBuffer<FlightEvent>? _ringBuffer;

  String? _sessionId;
  DateTime? _startedAt;
  bool _isRecording = false;

  PointerInterceptor? _pointerInterceptor;
  FlightRecorderNavigatorObserver? _navObserver;
  FlightLifecycleObserver? _lifecycleObserver;
  FlightErrorInterceptor? _errorInterceptor;
  TextInputInterceptor? _textInputInterceptor;
  PlatformChannelInterceptor? _platformChannelInterceptor;
  FlightRecorderWebSocketInterceptor? _webSocketInterceptor;
  HttpOverrides? _previousHttpOverrides;

  final StreamController<File> _crashDumpStream =
      StreamController<File>.broadcast();

  /// Stream emitting file handles when crash logs are dumped to disk.
  Stream<File> get onCrashDumped => _crashDumpStream.stream;

  /// Whether flight recording is currently running.
  bool get isRecording => _isRecording;

  /// The active configuration.
  FlightConfig get config => _config;

  /// Monotonically increasing milliseconds since this recorder session started.
  int get currentTimestampMs => _stopwatch.elapsedMilliseconds;

  /// Returns the NavigatorObserver to plug into MaterialApp or CupertinoApp.
  FlightRecorderNavigatorObserver get navigatorObserver {
    _navObserver ??= FlightRecorderNavigatorObserver(
      onEvent: (event) {
        if (_config.enableNavigationRecording) {
          recordEvent(event);
        }
      },
      stopwatch: _stopwatch,
    );
    return _navObserver!;
  }

  /// Starts recording user interactions, network, lifecycle, and crashes.
  void start({FlightConfig? config}) {
    if (_isRecording) return;
    _config = config ?? FlightConfig();
    _ringBuffer = EventRingBuffer<FlightEvent>(_config.bufferCapacity);
    _sessionId = 'flight_${DateTime.now().millisecondsSinceEpoch}';
    _startedAt = DateTime.now();

    _stopwatch.reset();
    _stopwatch.start();
    _isRecording = true;

    // Attach pointer router
    if (_config.enablePointerRecording) {
      _pointerInterceptor = PointerInterceptor(
        onEvent: recordEvent,
        stopwatch: _stopwatch,
        moveSampleDistance: _config.moveSampleDistance,
      )..attach();
    }

    // Attach lifecycle observer
    if (_config.enableLifecycleRecording) {
      _lifecycleObserver = FlightLifecycleObserver(
        onEvent: recordEvent,
        stopwatch: _stopwatch,
      )..attach();
    }

    // Attach HTTP overrides
    if (_config.enableHttpRecording) {
      _previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = FlightRecorderHttpOverrides(
        onEvent: recordEvent,
        stopwatch: _stopwatch,
        redaction: _config.redactionEngine,
        delegate: _previousHttpOverrides,
      );
    }

    // Attach crash interceptor
    if (_config.enableCrashRecording) {
      _errorInterceptor = FlightErrorInterceptor(
        onCrash: _handleCrash,
        stopwatch: _stopwatch,
      )..attach();
    }

    // Attach text-input / IME interceptor
    if (_config.enableTextInputRecording) {
      // ---------------------------------------------------------------------------
      // FIX (MED-2 from audit): Wire a FocusManager listener that keeps the
      // focusKeyRegistry in sync so that fieldKey is populated on TextInputFlightEvents
      // rather than always being null.
      // ---------------------------------------------------------------------------
      final focusKeyRegistry = <String, String>{};
      _textInputInterceptor = TextInputInterceptor(
        onEvent: recordEvent,
        stopwatch: _stopwatch,
        redaction: _config.redactionEngine,
        focusKeyRegistry: focusKeyRegistry,
      )..attach();
    }

    // Attach platform-channel interceptor
    if (_config.enablePlatformChannelRecording) {
      _platformChannelInterceptor = PlatformChannelInterceptor(
        onEvent: (event) {
          recordEvent(PlatformChannelFlightEvent(
            timestampMs: _stopwatch.elapsedMilliseconds,
            channelName: event.channel,
            direction: event.direction.name,
            methodName: event.method,
            encodedArgs: event.result?.toString(),
            isError: event.errorCode != null,
          ));
        },
        stopwatch: _stopwatch,
      )..attach();
    }

    // Attach WebSocket interceptor
    if (_config.enableWebSocketRecording) {
      _webSocketInterceptor = FlightRecorderWebSocketInterceptor(
        onEvent: (event) {
          recordEvent(WebSocketFlightEvent(
            timestampMs: _stopwatch.elapsedMilliseconds,
            url: event.url,
            direction:
                event.kind == WebSocketEventKind.sent ? 'send' : 'receive',
            message: event.payload,
            error: event.error,
          ));
        },
        stopwatch: _stopwatch,
        redaction: _config.redactionEngine,
      )..attach();
    }
  }

  /// Stops the current recording session.
  void stop() {
    if (!_isRecording) return;
    _isRecording = false;
    _stopwatch.stop();

    _pointerInterceptor?.detach();
    _pointerInterceptor = null;

    _lifecycleObserver?.detach();
    _lifecycleObserver = null;

    _textInputInterceptor?.detach();
    _textInputInterceptor = null;

    _platformChannelInterceptor?.detach();
    _platformChannelInterceptor = null;

    _webSocketInterceptor?.detach();
    _webSocketInterceptor = null;

    if (_config.enableHttpRecording) {
      HttpOverrides.global = _previousHttpOverrides;
      _previousHttpOverrides = null;
    }

    _errorInterceptor?.detach();
    _errorInterceptor = null;
    _navObserver = null;

    // FIX #1: Null out ring buffer on stop so callers that check _ringBuffer
    // for null can detect the stopped state without a stale late field.
    _ringBuffer = null;
  }

  /// Clears all buffered events in the current recording session.
  /// Useful for QA testers who want a fresh session without restarting the app.
  void clear() {
    _ringBuffer?.clear();
  }

  /// Manually records a custom flight event into the ring buffer.
  void recordEvent(FlightEvent event) {
    if (!_isRecording || _ringBuffer == null) return;
    if (event is NavigationFlightEvent && !_config.enableNavigationRecording) {
      return;
    }
    _ringBuffer!.add(event);
  }

  /// Adds a custom developer breadcrumb to the recording.
  void addBreadcrumb(
    String name, {
    String category = 'custom',
    Map<String, dynamic> data = const {},
  }) {
    if (!_isRecording) return;
    recordEvent(CustomBreadcrumbFlightEvent(
      timestampMs: _stopwatch.elapsedMilliseconds,
      name: name,
      category: category,
      data: data,
    ));
  }

  void _handleCrash(CrashFlightEvent crashEvent) {
    recordEvent(crashEvent);
    if (_config.enableCrashRecording) {
      // Automatically dump session to disk
      _dumpCrashSession(crashEvent);
    }
  }

  Future<File?> _dumpCrashSession(CrashFlightEvent crash) async {
    try {
      final dumpDir = _config.dumpDirectory ?? Directory.systemTemp;
      if (!await dumpDir.exists()) {
        await dumpDir.create(recursive: true);
      }

      final fileName =
          'crash_${DateTime.now().millisecondsSinceEpoch}.flightlog';
      final filePath = '${dumpDir.path}/$fileName';
      final file = await exportSession(filePath: filePath, compress: true);
      _crashDumpStream.add(file);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Returns an immutable snapshot list of all events currently in the buffer.
  ///
  /// Returns an empty list if the recorder is not currently running.
  List<FlightEvent> getRecentEvents() {
    if (!_isRecording || _ringBuffer == null) return const [];
    return _ringBuffer!.toList();
  }

  // ---------------------------------------------------------------------------
  // FIX #2: exportSession() — prevent deadlock when called while recording is
  // active.
  //
  // Root cause: When HTTP recording is enabled and exportSession() is called
  // mid-session, the File I/O initiated by FlightSerializer.writeToFile()
  // passes through Dart's platform channel.  In a test environment this
  // triggers the PlatformChannelInterceptor, which calls recordEvent(), which
  // adds to the ring buffer, which is fine — but it also causes the installed
  // FlightRecorderHttpOverrides to intercept any HttpClient activity that
  // writeToFile() may trigger (e.g. via compression libraries that do look-ups
  // or via platform-channel stubs calling back into the recorder), creating a
  // re-entrant feedback loop that can deadlock the event loop.
  //
  // Fix: Temporarily remove our HttpOverrides before writing to disk, then
  // restore them afterward.  The snapshot is captured first (before we touch
  // any overrides) so no events are lost.
  // ---------------------------------------------------------------------------
  Future<File> exportSession({
    String? filePath,
    bool compress = true,
  }) async {
    // ---------------------------------------------------------------------------
    // FIX #1 (guard): Throw a clear error if called before start().
    // ---------------------------------------------------------------------------
    if (!_isRecording || _ringBuffer == null) {
      throw StateError(
        'FlightRecorder.exportSession() called while recorder is not running. '
        'Call FlightRecorder.instance.start() first.',
      );
    }

    // 1. Capture an immutable snapshot NOW, before we touch any overrides.
    final session = _buildSnapshot();

    // 2. Temporarily lift HTTP overrides to prevent re-entrancy / deadlock.
    //    We restore them in a try/finally so a write failure can't leave the
    //    recorder broken.
    final savedOverrides =
        _config.enableHttpRecording ? HttpOverrides.current : null;
    if (savedOverrides != null) {
      HttpOverrides.global = _previousHttpOverrides; // bypass flight recorder
    }

    try {
      final ext = _config.cryptoEngine != null ? '.eflightlog' : '.flightlog';
      final resolvedPath = filePath ??
          '${Directory.systemTemp.path}/session_${DateTime.now().millisecondsSinceEpoch}$ext';

      if (_config.cryptoEngine != null) {
        final secure = SecureFlightSerializer(crypto: _config.cryptoEngine!);
        return await secure.writeEncryptedToFile(session, resolvedPath);
      }

      return await FlightSerializer.writeToFile(
        session,
        resolvedPath,
        compress: compress,
      );
    } finally {
      // 3. Always restore our overrides, even if write throws.
      if (savedOverrides != null) {
        HttpOverrides.global = savedOverrides;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // FIX #1: snapshot() / dumpSession() now throw StateError if recorder is
  // not running, instead of silently returning an empty / stale session.
  // ---------------------------------------------------------------------------

  /// Snapshot convenience alias for [snapshot].
  ///
  /// Throws [StateError] if the recorder has not been started.
  FlightSession dumpSession() => snapshot();

  /// Builds a [FlightSession] object directly in memory from the current
  /// ring-buffer contents.
  ///
  /// Throws [StateError] if the recorder is not currently running.
  FlightSession snapshot() {
    if (!_isRecording || _ringBuffer == null) {
      throw StateError(
        'FlightRecorder.snapshot() called while recorder is not running. '
        'Call FlightRecorder.instance.start() first.',
      );
    }
    return _buildSnapshot();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Builds a [FlightSession] from current state without any guards.
  /// Callers MUST check [_isRecording] and [_ringBuffer] != null first.
  FlightSession _buildSnapshot() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    final dpr = view?.devicePixelRatio ?? 1.0;
    final physicalSize = view?.physicalSize ?? const Size(1080, 1920);

    final manifest = SessionManifest(
      sessionId: _sessionId ?? 'uninitialized',
      startedAt: _startedAt ?? DateTime.now(),
      platform: Platform.operatingSystem,
      initialWidth: physicalSize.width / dpr,
      initialHeight: physicalSize.height / dpr,
      initialDevicePixelRatio: dpr,
    );

    return FlightSession(
      manifest: manifest,
      events: _ringBuffer!.toList(),
    );
  }
}
