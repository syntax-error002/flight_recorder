import 'package:flutter/widgets.dart';
import '../core/event_models.dart';

typedef OnLifecycleFlightEvent = void Function(LifecycleFlightEvent event);

/// Listens to app lifecycle states and window metric changes.
class FlightLifecycleObserver with WidgetsBindingObserver {
  final OnLifecycleFlightEvent onEvent;
  final Stopwatch stopwatch;
  bool _isAttached = false;

  FlightLifecycleObserver({
    required this.onEvent,
    required this.stopwatch,
  });

  void attach() {
    if (_isAttached) return;
    WidgetsBinding.instance.addObserver(this);
    _isAttached = true;
  }

  void detach() {
    if (!_isAttached) return;
    WidgetsBinding.instance.removeObserver(this);
    _isAttached = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onEvent(LifecycleFlightEvent(
      timestampMs: stopwatch.elapsedMilliseconds,
      state: state.name,
    ));
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null) {
      final physicalSize = view.physicalSize;
      final dpr = view.devicePixelRatio;
      final logicalWidth = physicalSize.width / dpr;
      final logicalHeight = physicalSize.height / dpr;

      onEvent(LifecycleFlightEvent(
        timestampMs: stopwatch.elapsedMilliseconds,
        state: 'metricsChanged',
        width: logicalWidth,
        height: logicalHeight,
        devicePixelRatio: dpr,
      ));
    }
  }
}
