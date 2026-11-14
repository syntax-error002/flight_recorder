/// Pure Dart core of Flight Blackbox.
/// Safe to run in pure Dart CLI environments without Flutter engine / dart:ui dependencies.
library;

export 'src/core/crypto_engine.dart';
export 'src/core/event_models.dart';
export 'src/core/redaction_engine.dart';
export 'src/core/ring_buffer.dart';
export 'src/core/serializer.dart';
export 'src/core/session_manifest.dart';
export 'src/serializer/secure_serializer.dart';
export 'src/synthesis/test_harness_builder.dart';
export 'src/synthesis/test_synthesizer.dart';
export 'src/testing/replay_server.dart';
