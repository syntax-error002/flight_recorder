import '../core/event_models.dart';
import '../recorder/recorder_controller.dart';

/// Lightweight, framework-agnostic HTTP/network observer.
///
/// Use this helper to record network calls from Dio, Chopper, package:http, or
/// custom GraphQL clients into the active [FlightRecorder] session without
/// relying on `dart:io.HttpOverrides`.
///
/// ### Dio Example:
/// ```dart
/// class FlightDioInterceptor extends Interceptor {
///   @override
///   void onResponse(Response response, ResponseInterceptorHandler handler) {
///     FlightNetworkObserver.record(
///       method: response.requestOptions.method,
///       url: response.requestOptions.uri.toString(),
///       statusCode: response.statusCode ?? 200,
///       responseBody: response.data?.toString(),
///     );
///     handler.next(response);
///   }
///
///   @override
///   void onError(DioException err, ErrorInterceptorHandler handler) {
///     FlightNetworkObserver.record(
///       method: err.requestOptions.method,
///       url: err.requestOptions.uri.toString(),
///       statusCode: err.response?.statusCode ?? 500,
///       responseBody: err.response?.data?.toString() ?? err.message,
///     );
///     handler.next(err);
///   }
/// }
/// ```
abstract final class FlightNetworkObserver {
  /// Directly records an HTTP request and response into the active flight log.
  static void record({
    required String method,
    required String url,
    required int statusCode,
    int durationMs = 0,
    String? requestBody,
    String? responseBody,
    Map<String, dynamic>? requestHeaders,
    Map<String, dynamic>? responseHeaders,
  }) {
    if (!FlightRecorder.instance.isRecording) return;
    FlightRecorder.instance.recordEvent(
      HttpFlightEvent(
        timestampMs: FlightRecorder.instance.currentTimestampMs,
        method: method,
        url: url,
        statusCode: statusCode,
        durationMs: durationMs,
        requestBody: requestBody,
        responseBody: responseBody,
        requestHeaders:
            requestHeaders?.map((k, v) => MapEntry(k, v.toString())) ??
                const {},
        responseHeaders:
            responseHeaders?.map((k, v) => MapEntry(k, v.toString())) ??
                const {},
      ),
    );
  }
}
