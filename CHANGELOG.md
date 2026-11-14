# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 0.1.0

### Features
* **Zero-Allocation Ring Buffer:** $O(1)$ pre-allocated circular buffer (`EventRingBuffer`) for high-frequency gesture, navigation, network, and lifecycle events without GC overhead.
* **Deterministic Test Synthesizer:** Pure-Dart CLI (`dart run flight_recorder:synthesize`) converting `.flightlog` recordings into reproducible `testWidgets` Dart test scripts.
* **Semantic Hit-Test Resolution:** Walk render tree to resolve `find.byKey`, `find.text`, `find.byType`, and `SemanticsNode.label` instead of brittle screen coordinates.
* **Keyboard & IME Recording:** Intercept `flutter/textinput` channel with real-time PII redaction and `tester.enterText` synthesis.
* **Platform Channel Replay Binding:** Automatically stub `MethodChannel` invocations via `PlatformChannelReplayBinding.installAll` to eliminate `MissingPluginException` in headless test environments.
* **Pure-Dart Authenticated Encryption:** AES-256 / ChaCha20 quarter-round cipher + HMAC-SHA256 authenticated encryption (`.eflightlog`) with PBKDF2 key derivation.
* **WebSocket Interceptor & Replay:** Full bidirectional WebSocket tracking and in-process mock server (`FlightWebSocketReplayServer`).
* **Dependency Injection Scaffolding:** `TestHarnessBuilder` generating `test/flight_harness.dart` with auto-detection for Riverpod, GetIt, Bloc, and Provider.
* **Diagnostic Floating Overlay:** Draggable staging/dogfood pill (`FlightRecorderOverlay`) with real-time event inspector, export, and clipboard test synthesis.
* **Dual Replay Harness:** Standalone `FlightReplayServer` with `HttpOverrides` for deterministic network fixture replay.
