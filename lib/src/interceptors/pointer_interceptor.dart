import 'package:flutter/gestures.dart';
import '../core/event_models.dart';
import '../core/semantic_resolver.dart';
import '../ui/flight_overlay.dart';

typedef OnPointerFlightEvent = void Function(PointerFlightEvent event);

/// Intercepts all global pointer events at the Flutter engine level.
/// Uses [GestureBinding.instance.pointerRouter] without requiring wrapping widgets.
class PointerInterceptor {
  final OnPointerFlightEvent onEvent;
  final Stopwatch stopwatch;
  final double moveSampleDistance; // Minimum logical pixels move to record

  bool _isAttached = false;
  Offset? _lastRecordedOffset;
  WidgetIdentity? _lastRecordedIdentity;
  int _lastMoveTimeMs = 0;

  PointerInterceptor({
    required this.onEvent,
    required this.stopwatch,
    this.moveSampleDistance = 2.0,
  });

  /// Starts listening to global pointer events.
  void attach() {
    if (_isAttached) return;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointerEvent);
    _isAttached = true;
  }

  /// Stops listening to global pointer events.
  void detach() {
    if (!_isAttached) return;
    GestureBinding.instance.pointerRouter
        .removeGlobalRoute(_handlePointerEvent);
    _isAttached = false;
    _lastRecordedOffset = null;
  }

  void _handlePointerEvent(PointerEvent event) {
    // Drop touches hitting the diagnostic overlay itself to avoid self-recording
    if (FlightRecorderOverlay.isOverlayPoint(event.position)) {
      return;
    }

    final nowMs = stopwatch.elapsedMilliseconds;

    if (event is PointerDownEvent) {
      _lastRecordedOffset = event.position;
      try {
        _lastRecordedIdentity = SemanticResolver.resolve(event.position, null);
      } catch (_) {
        _lastRecordedIdentity = null;
      }

      if (_lastRecordedIdentity != null &&
          _lastRecordedIdentity!.isResolvable) {
        onEvent(SemanticPointerFlightEvent(
          timestampMs: nowMs,
          action: 'down',
          dx: event.position.dx,
          dy: event.position.dy,
          pointerId: event.pointer,
          buttons: event.buttons,
          deviceKind: event.kind.name,
          resolvedKey: _lastRecordedIdentity!.key,
          resolvedType: _lastRecordedIdentity!.widgetType,
          resolvedText: _lastRecordedIdentity!.text,
          resolvedTooltip: _lastRecordedIdentity!.tooltip,
          resolvedSemLabel: _lastRecordedIdentity!.semanticLabel,
        ));
      } else {
        onEvent(PointerFlightEvent(
          timestampMs: nowMs,
          action: 'down',
          dx: event.position.dx,
          dy: event.position.dy,
          pointerId: event.pointer,
          buttons: event.buttons,
          deviceKind: event.kind.name,
        ));
      }
    } else if (event is PointerMoveEvent) {
      // Throttle rapid sub-pixel moves to preserve ring-buffer efficiency
      final lastPos = _lastRecordedOffset;
      final timeSinceLastMove = nowMs - _lastMoveTimeMs;

      if (lastPos != null) {
        final distanceSquared = (event.position - lastPos).distanceSquared;
        if (distanceSquared < (moveSampleDistance * moveSampleDistance) &&
            timeSinceLastMove < 32) {
          return; // Skip negligible sub-frame jitter
        }
      }

      _lastRecordedOffset = event.position;
      _lastMoveTimeMs = nowMs;

      onEvent(PointerFlightEvent(
        timestampMs: nowMs,
        action: 'move',
        dx: event.position.dx,
        dy: event.position.dy,
        pointerId: event.pointer,
        buttons: event.buttons,
        deviceKind: event.kind.name,
      ));
    } else if (event is PointerUpEvent) {
      final identity = _lastRecordedIdentity;
      _lastRecordedOffset = null;
      _lastRecordedIdentity = null;

      if (identity != null && identity.isResolvable) {
        onEvent(SemanticPointerFlightEvent(
          timestampMs: nowMs,
          action: 'up',
          dx: event.position.dx,
          dy: event.position.dy,
          pointerId: event.pointer,
          buttons: event.buttons,
          deviceKind: event.kind.name,
          resolvedKey: identity.key,
          resolvedType: identity.widgetType,
          resolvedText: identity.text,
          resolvedTooltip: identity.tooltip,
          resolvedSemLabel: identity.semanticLabel,
        ));
      } else {
        onEvent(PointerFlightEvent(
          timestampMs: nowMs,
          action: 'up',
          dx: event.position.dx,
          dy: event.position.dy,
          pointerId: event.pointer,
          buttons: event.buttons,
          deviceKind: event.kind.name,
        ));
      }
    } else if (event is PointerCancelEvent) {
      _lastRecordedOffset = null;
      onEvent(PointerFlightEvent(
        timestampMs: nowMs,
        action: 'cancel',
        dx: event.position.dx,
        dy: event.position.dy,
        pointerId: event.pointer,
        buttons: event.buttons,
        deviceKind: event.kind.name,
      ));
    } else if (event is PointerScrollEvent) {
      onEvent(PointerFlightEvent(
        timestampMs: nowMs,
        action: 'scroll',
        dx: event.position.dx,
        dy: event.position.dy,
        pointerId: event.pointer,
        buttons: event.buttons,
        deviceKind: event.kind.name,
        scrollDeltaDx: event.scrollDelta.dx,
        scrollDeltaDy: event.scrollDelta.dy,
      ));
    }
  }
}
