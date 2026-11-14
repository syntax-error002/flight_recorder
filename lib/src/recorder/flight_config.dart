import 'dart:io';
import '../core/crypto_engine.dart';
import '../core/redaction_engine.dart';

/// Configuration options for Flight Recorder.
class FlightConfig {
  /// Maximum number of events kept in the in-memory ring buffer.
  final int bufferCapacity;

  /// Minimum logical distance (pixels) between move events to throttle noise.
  final double moveSampleDistance;

  /// Whether to capture touch and pointer events globally.
  final bool enablePointerRecording;

  /// Whether to capture route navigation transitions.
  final bool enableNavigationRecording;

  /// Whether to capture app lifecycle and viewport metrics.
  final bool enableLifecycleRecording;

  /// Whether to capture HTTP requests via HttpOverrides.
  final bool enableHttpRecording;

  /// Whether to capture unhandled crashes and auto-export session.
  final bool enableCrashRecording;

  /// Whether to capture keyboard and text input events.
  final bool enableTextInputRecording;

  /// Whether to capture platform channel calls and responses.
  final bool enablePlatformChannelRecording;

  /// Optional cryptographic engine for encrypting session logs to `.eflightlog`.
  final CryptoEngine? cryptoEngine;

  /// Directory where crash .flightlog files will be automatically written.
  final Directory? dumpDirectory;

  /// The redaction engine for scrubbing sensitive data.
  final RedactionEngine redactionEngine;

  FlightConfig({
    this.bufferCapacity = 2000,
    this.moveSampleDistance = 2.0,
    this.enablePointerRecording = true,
    this.enableNavigationRecording = true,
    this.enableLifecycleRecording = true,
    this.enableHttpRecording = true,
    this.enableCrashRecording = true,
    this.enableTextInputRecording = true,
    this.enablePlatformChannelRecording = true,
    this.cryptoEngine,
    this.dumpDirectory,
    RedactionEngine? redactionEngine,
  }) : redactionEngine = redactionEngine ?? RedactionEngine();
}
