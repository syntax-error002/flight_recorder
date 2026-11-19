import 'package:flutter/widgets.dart';
import '../core/event_models.dart';

typedef OnNavigationFlightEvent = void Function(NavigationFlightEvent event);

/// A [NavigatorObserver] that records route transitions into Flight Recorder.
class FlightRecorderNavigatorObserver extends NavigatorObserver {
  final OnNavigationFlightEvent onEvent;
  final Stopwatch stopwatch;

  FlightRecorderNavigatorObserver({
    required this.onEvent,
    required this.stopwatch,
  });

  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return '<none>';
    return route.settings.name ?? route.runtimeType.toString();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    onEvent(NavigationFlightEvent(
      timestampMs: stopwatch.elapsedMilliseconds,
      action: 'push',
      routeName: _getRouteName(route),
      previousRouteName:
          previousRoute != null ? _getRouteName(previousRoute) : null,
    ));
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    onEvent(NavigationFlightEvent(
      timestampMs: stopwatch.elapsedMilliseconds,
      action: 'pop',
      routeName: _getRouteName(route),
      previousRouteName:
          previousRoute != null ? _getRouteName(previousRoute) : null,
    ));
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    onEvent(NavigationFlightEvent(
      timestampMs: stopwatch.elapsedMilliseconds,
      action: 'replace',
      routeName: _getRouteName(newRoute),
      previousRouteName: oldRoute != null ? _getRouteName(oldRoute) : null,
    ));
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    onEvent(NavigationFlightEvent(
      timestampMs: stopwatch.elapsedMilliseconds,
      action: 'remove',
      routeName: _getRouteName(route),
      previousRouteName:
          previousRoute != null ? _getRouteName(previousRoute) : null,
    ));
  }
}
