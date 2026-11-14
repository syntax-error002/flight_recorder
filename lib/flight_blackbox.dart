/// Flight Blackbox: Deterministic in-app event-sourcing ring buffer
/// and crash-to-testWidgets synthesizer for Flutter.
library;

export 'src/core/crypto_engine.dart';
export 'src/core/event_models.dart';
export 'src/core/redaction_engine.dart';
export 'src/core/ring_buffer.dart';
export 'src/core/semantic_resolver.dart';
export 'src/core/serializer.dart';
export 'src/core/session_manifest.dart';

export 'src/interceptors/error_interceptor.dart';
export 'src/interceptors/http_interceptor.dart';
export 'src/interceptors/lifecycle_observer.dart';
export 'src/interceptors/navigation_observer.dart';
export 'src/interceptors/platform_channel_interceptor.dart';
export 'src/interceptors/pointer_interceptor.dart';
export 'src/interceptors/text_input_interceptor.dart';
export 'src/interceptors/websocket_interceptor.dart';

export 'src/recorder/flight_config.dart';
export 'src/recorder/recorder_controller.dart';

export 'src/serializer/secure_serializer.dart';

export 'src/synthesis/test_harness_builder.dart';
export 'src/synthesis/test_synthesizer.dart';

export 'src/testing/pointer_replay.dart';
export 'src/testing/replay_server.dart';

export 'src/ui/flight_overlay.dart';
