import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import '../core/event_models.dart';

/// Helper utility for feeding recorded pointer events into Flutter's [WidgetTester].
class FlightPointerInjector {
  /// Injects a recorded [PointerFlightEvent] directly into the test binding.
  static Future<void> inject(WidgetTester tester, PointerFlightEvent event) async {
    final position = Offset(event.dx, event.dy);
    final pointer = event.pointerId;

    switch (event.action) {
      case 'down':
        await tester.sendEventToBinding(PointerDownEvent(
          pointer: pointer,
          position: position,
          buttons: event.buttons,
          kind: _mapDeviceKind(event.deviceKind),
        ));
        break;
      case 'move':
        await tester.sendEventToBinding(PointerMoveEvent(
          pointer: pointer,
          position: position,
          buttons: event.buttons,
          kind: _mapDeviceKind(event.deviceKind),
        ));
        break;
      case 'up':
        await tester.sendEventToBinding(PointerUpEvent(
          pointer: pointer,
          position: position,
          kind: _mapDeviceKind(event.deviceKind),
        ));
        break;
      case 'cancel':
        await tester.sendEventToBinding(PointerCancelEvent(
          pointer: pointer,
          position: position,
        ));
        break;
      case 'scroll':
        await tester.sendEventToBinding(PointerScrollEvent(
          device: pointer,
          position: position,
          scrollDelta: Offset(event.scrollDeltaDx, event.scrollDeltaDy),
          kind: _mapDeviceKind(event.deviceKind),
        ));
        break;
    }
  }

  static PointerDeviceKind _mapDeviceKind(String kind) {
    return switch (kind) {
      'mouse' => PointerDeviceKind.mouse,
      'stylus' => PointerDeviceKind.stylus,
      'trackpad' => PointerDeviceKind.trackpad,
      _ => PointerDeviceKind.touch,
    };
  }
}
