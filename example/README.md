# Flight Recorder Showcase Example

A complete e-commerce application demonstrating `flight_recorder` in action.

## Features Demonstrated

- **Gesture Recording:** Captures pointer down, move, and up events with sub-pixel noise throttling.
- **Semantic Resolution:** Identifies buttons and fields by Key and Text content.
- **IME & Keyboard Input:** Intercepts typed input in search and promo code fields with automatic PII masking.
- **Network Interception:** Captures HTTP requests and responses to `https://httpbin.org/get`.
- **Navigation Tracking:** Tracks route pushes and pops between the Product Catalog and Cart screens.
- **Simulated Crash:** Triggers an intentional unhandled `StateError` to showcase automatic crash dump generation.
- **Flight Diagnostic Pill:** Draggable floating action button providing instant session log export and clipboard test synthesis.

## Running the Example

```bash
flutter run -d windows
# or
flutter run -d chrome
# or
flutter run
```

## Reproducing a Session

1. Tap items to add them to the cart.
2. Tap "Test HTTP Call" or "Simulate Crash".
3. Tap the red floating diagnostic pill.
4. Click **"Copy Dart Test"** or **"Export .flightlog"**.
5. Run the CLI tool against the exported log:
   ```bash
   dart run flight_recorder:synthesize -i my_session.flightlog -o test/repros/crash_test.dart
   ```
6. Run the generated test:
   ```bash
   flutter test test/repros/crash_test.dart
   ```
