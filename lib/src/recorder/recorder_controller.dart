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
  late EventRingBuffer<FlightEvent> _ringBuffer;

  String? _sessionId;
  DateTime? _startedAt;
  bool _isRecording = false;

  PointerInterceptor? _pointerInterceptor;
  FlightRecorderNavigatorObserver? _navObserver;
  FlightLifecycleObserver? _lifecycleObserver;
  FlightErrorInterceptor? _errorInterceptor;
  TextInputInterceptor? _textInputInterceptor;
  PlatformChannelInterceptor? _platformChannelInterceptor;
  HttpOverrides? _previousHttpOverrides;

  final StreamController<File> _crashDumpStream = StreamController<File>.broadcast();

  /// Stream emitting file handles when crash logs are dumped to disk.
  Stream<File> get onCrashDumped => _crashDumpStream.stream;

  /// Whether flight recording is currently running.
  bool get isRecording => _isRecording;

  /// The active configuration.
  FlightConfig get config => _config;

  /// Returns the NavigatorObserver to plug into MaterialApp or CupertinoApp.
  FlightRecorderNavigatorObserver get navigatorObserver {
    _navObserver ??= FlightRecorderNavigatorObserver(
      onEvent: recordEvent,
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
      _textInputInterceptor = TextInputInterceptor(
        onEvent: recordEvent,
        stopwatch: _stopwatch,
        redaction: _config.redactionEngine,
        focusKeyRegistry: {},
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

    if (_config.enableHttpRecording) {
      HttpOverrides.global = _previousHttpOverrides;
    }

    _errorInterceptor?.detach();
    _errorInterceptor = null;
  }

  /// Manually records a custom flight event into the ring buffer.
  void recordEvent(FlightEvent event) {
    if (!_isRecording) return;
    _ringBuffer.add(event);
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

      final fileName = 'crash_${DateTime.now().millisecondsSinceEpoch}.flightlog';
      final filePath = '${dumpDir.path}/$fileName';
      final file = await exportSession(filePath: filePath, compress: true);
      _crashDumpStream.add(file);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Returns an immutable snapshot list of all events currently in the buffer.
  List<FlightEvent> getRecentEvents() {
    if (!_isRecording) return [];
    return _ringBuffer.toList();
  }

  /// Exports the recorded session snapshot to a file or in-memory [FlightSession].
  Future<File> exportSession({
    String? filePath,
    bool compress = true,
  }) async {
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

    final session = FlightSession(
      manifest: manifest,
      events: _ringBuffer.toList(),
    );

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
  }

  /// Snapshot convenience alias for [snapshot].
  FlightSession dumpSession() => snapshot();

  /// Builds a [FlightSession] object directly in memory.
  FlightSession snapshot() {
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
      events: _ringBuffer.toList(),
    );
  }
}
