import 'package:flutter/widgets.dart';

import '../core/serializer.dart';
import '../interceptors/navigation_observer.dart';
import '../ui/flight_overlay.dart';
import 'flight_config.dart';
import 'recorder_controller.dart';

/// Single-line bootstrap and high-level façade for the Flight Blackbox system.
///
/// ### Quickstart:
/// ```dart
/// void main() => FlightBlackbox.run(app: const MyApp());
/// ```
abstract final class FlightBlackbox {
  /// Initializes the flight recorder and runs [app] wrapped with the diagnostic
  /// overlay in a single call.
  static void run({
    required Widget app,
    FlightConfig? config,
    bool enableOverlay = true,
  }) {
    WidgetsFlutterBinding.ensureInitialized();
    FlightRecorder.instance.start(config: config);
    runApp(
      enableOverlay ? FlightRecorderOverlay(child: app) : app,
    );
  }

  /// Returns the singleton [FlightRecorder] instance.
  static FlightRecorder get instance => FlightRecorder.instance;

  /// Whether the blackbox is actively recording.
  static bool get isRecording => FlightRecorder.instance.isRecording;

  /// Returns the active [FlightRecorderNavigatorObserver] to plug into [MaterialApp.navigatorObservers].
  static FlightRecorderNavigatorObserver get navigatorObserver =>
      FlightRecorder.instance.navigatorObserver;

  /// Captures a custom developer breadcrumb.
  static void breadcrumb(String name, {String category = 'custom'}) =>
      FlightRecorder.instance.addBreadcrumb(name, category: category);

  /// Clears all buffered events in the current session.
  static void clear() => FlightRecorder.instance.clear();

  /// Stops recording.
  static void stop() => FlightRecorder.instance.stop();

  /// Exports the recorded session to disk (.flightlog or .eflightlog) and returns the file path.
  static Future<String> exportSession(
      {String? targetPath, bool compress = true}) async {
    final file = await FlightRecorder.instance.exportSession(
      filePath: targetPath,
      compress: compress,
    );
    return file.path;
  }

  /// Takes an in-memory snapshot of the active flight session.
  static FlightSession snapshot() => FlightRecorder.instance.snapshot();
}
