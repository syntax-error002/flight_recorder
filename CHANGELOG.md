# Changelog

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 0.3.0

### Added
* `FlightBlackbox.run(app: ...)` helper to initialize error handling, observers, interceptors, and the diagnostic overlay in a single call.
* `FlightNetworkObserver.record(...)` for recording requests from manual HTTP clients (Dio, Chopper, http) without requiring `HttpOverrides`.
* WebSocket interceptor support enabled by default in `FlightConfig`.
* Automatic `tester.takeException()` handling in synthesized tests to capture and report app crashes during replay.

### Fixed
* Fixed widget resolution failing or misidentifying elements in deep widget trees by increasing `SemanticResolver` traversal depth to 512 and adding bounding-box branch pruning.
* Fixed keystroke recording by migrating from binary messenger overrides to Flutter's `TextInputControl` API (`TextInput.setInputControl`).
* Fixed synthesized tests failing on forms with multiple unkeyed fields by disambiguating `TextField` finders via labels, hints, or index.
* Fixed framework internal keys (`LabeledGlobalKey`, private keys) taking precedence over actual UI elements in candidate scoring.
* Fixed test runner timeouts caused by `pumpAndSettle()` waiting on continuous animations (shimmers, spinners) by generating a bounded `_safeSettle` helper.
* Fixed PII redaction bypassing mixed-case headers and uppercase JSON payload keys.
* Fixed `WidgetIdentity.isResolvable` treating generic widget types (like `Container`) as unique finders.
* Fixed generated test harnesses emitting empty HTTP stubs instead of real recorded fixtures.

### Changed
* Improved `FlightRecorderOverlay` dragging and layout to respect screen bounds and safe areas.
* Excluded interactions with the diagnostic overlay itself from being recorded into user session logs.

## 0.2.0

### Features & Improvements
* **Modal Barrier & Occlusion Hit-Testing:** Added visual paint-order `visitIndex` tracking and `ModalBarrier` hit-detection in `SemanticResolver`. Eliminates false positive hits on occluded background widgets when modal bottom sheets, alert dialogs, or overlay routes are open.
* **Atomic Tap & Navigation Lookahead:** Implemented `_findMatchingUpIndex` in `FlightSynthesizer` to automatically couple taps with interleaved route transitions and breadcrumbs, eliminating gesture fragmentation and ensuring route animations settle cleanly.
* **Intelligent Off-Screen Lazy List Scrolling:** Generated `testWidgets` tests automatically scroll lazy list items (`ListView.builder`, `SliverList`) into view via `scrollUntilVisible` targeting the topmost active scrollable before tapping.
* **Auto-Import & Test Harness CLI:** Added `-I` / `--import` flag to `bin/synthesize.dart` with automatic detection of host project `package:<name>/main.dart` from `pubspec.yaml`.
* **API Ergonomics:** Added `FlightRecorder.instance.dumpSession()` alias for `snapshot()`.

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
