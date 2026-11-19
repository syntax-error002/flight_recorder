import 'package:flutter/foundation.dart';
import '../core/event_models.dart';

typedef OnCrashFlightEvent = void Function(CrashFlightEvent event);
typedef PlatformErrorCallback = bool Function(
    Object exception, StackTrace stackTrace);

/// Intercepts framework-level Flutter errors and root platform dispatch errors.
class FlightErrorInterceptor {
  final OnCrashFlightEvent onCrash;
  final Stopwatch stopwatch;

  FlutterExceptionHandler? _originalFlutterOnError;
  PlatformErrorCallback? _originalPlatformOnError;
  bool _isAttached = false;

  FlightErrorInterceptor({
    required this.onCrash,
    required this.stopwatch,
  });

  void attach() {
    if (_isAttached) return;

    _originalFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final nowMs = stopwatch.elapsedMilliseconds;
      final event = CrashFlightEvent(
        timestampMs: nowMs,
        exception: details.exceptionAsString(),
        stackTrace: details.stack?.toString() ?? StackTrace.current.toString(),
        errorDetails: details.context?.toDescription(),
      );

      onCrash(event);

      // Chain original handler
      _originalFlutterOnError?.call(details);
    };

    _originalPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final nowMs = stopwatch.elapsedMilliseconds;
      final event = CrashFlightEvent(
        timestampMs: nowMs,
        exception: error.toString(),
        stackTrace: stack.toString(),
      );

      onCrash(event);

      return _originalPlatformOnError?.call(error, stack) ?? false;
    };

    _isAttached = true;
  }

  void detach() {
    if (!_isAttached) return;
    FlutterError.onError = _originalFlutterOnError;
    PlatformDispatcher.instance.onError = _originalPlatformOnError;
    _isAttached = false;
  }
}
