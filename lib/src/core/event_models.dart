/// Base class for all events captured by Flight Recorder.
sealed class FlightEvent {
  /// Milliseconds elapsed since the flight session started.
  final int timestampMs;

  const FlightEvent({required this.timestampMs});

  Map<String, dynamic> toJson();

  static FlightEvent fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'pointer' => PointerFlightEvent.fromJson(json),
      'navigation' => NavigationFlightEvent.fromJson(json),
      'http' => HttpFlightEvent.fromJson(json),
      'lifecycle' => LifecycleFlightEvent.fromJson(json),
      'crash' => CrashFlightEvent.fromJson(json),
      'breadcrumb' => CustomBreadcrumbFlightEvent.fromJson(json),
      'semantic_pointer' => SemanticPointerFlightEvent.fromJson(json),
      'text_input' => TextInputFlightEvent.fromJson(json),
      'platform_channel' => PlatformChannelFlightEvent.fromJson(json),
      'websocket' => WebSocketFlightEvent.fromJson(json),
      'route_stack_snapshot' => RouteStackSnapshotEvent.fromJson(json),
      _ => throw FormatException('Unknown FlightEvent type: $type'),
    };
  }
}

// ---------------------------------------------------------------------------
// Existing event types — kept intact
// ---------------------------------------------------------------------------

/// Pointer interaction (taps, drags, flings, scrolls).
class PointerFlightEvent extends FlightEvent {
  final String action; // 'down', 'move', 'up', 'cancel', 'scroll'
  final double dx;
  final double dy;
  final int pointerId;
  final int buttons;
  final String deviceKind; // 'touch', 'mouse', 'stylus', 'trackpad'
  final double scrollDeltaDx;
  final double scrollDeltaDy;

  const PointerFlightEvent({
    required super.timestampMs,
    required this.action,
    required this.dx,
    required this.dy,
    this.pointerId = 0,
    this.buttons = 1,
    this.deviceKind = 'touch',
    this.scrollDeltaDx = 0.0,
    this.scrollDeltaDy = 0.0,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'pointer',
        'timestampMs': timestampMs,
        'action': action,
        'dx': dx,
        'dy': dy,
        'pointerId': pointerId,
        'buttons': buttons,
        'deviceKind': deviceKind,
        'scrollDeltaDx': scrollDeltaDx,
        'scrollDeltaDy': scrollDeltaDy,
      };

  factory PointerFlightEvent.fromJson(Map<String, dynamic> json) {
    return PointerFlightEvent(
      timestampMs: json['timestampMs'] as int,
      action: json['action'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      pointerId: json['pointerId'] as int? ?? 0,
      buttons: json['buttons'] as int? ?? 1,
      deviceKind: json['deviceKind'] as String? ?? 'touch',
      scrollDeltaDx: (json['scrollDeltaDx'] as num?)?.toDouble() ?? 0.0,
      scrollDeltaDy: (json['scrollDeltaDy'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Route transitions (screen push, pop, replace).
class NavigationFlightEvent extends FlightEvent {
  final String action; // 'push', 'pop', 'replace', 'remove'
  final String routeName;
  final String? previousRouteName;

  const NavigationFlightEvent({
    required super.timestampMs,
    required this.action,
    required this.routeName,
    this.previousRouteName,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'navigation',
        'timestampMs': timestampMs,
        'action': action,
        'routeName': routeName,
        'previousRouteName': previousRouteName,
      };

  factory NavigationFlightEvent.fromJson(Map<String, dynamic> json) {
    return NavigationFlightEvent(
      timestampMs: json['timestampMs'] as int,
      action: json['action'] as String,
      routeName: json['routeName'] as String,
      previousRouteName: json['previousRouteName'] as String?,
    );
  }
}

/// Network requests and responses captured by HttpOverrides or Dio.
class HttpFlightEvent extends FlightEvent {
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final Map<String, String> responseHeaders;
  final String? responseBody;
  final String? error;

  const HttpFlightEvent({
    required super.timestampMs,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    this.requestHeaders = const {},
    this.requestBody,
    this.responseHeaders = const {},
    this.responseBody,
    this.error,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'http',
        'timestampMs': timestampMs,
        'method': method,
        'url': url,
        'statusCode': statusCode,
        'durationMs': durationMs,
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'error': error,
      };

  factory HttpFlightEvent.fromJson(Map<String, dynamic> json) {
    return HttpFlightEvent(
      timestampMs: json['timestampMs'] as int,
      method: json['method'] as String,
      url: json['url'] as String,
      statusCode: json['statusCode'] as int,
      durationMs: json['durationMs'] as int,
      requestHeaders: (json['requestHeaders'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      requestBody: json['requestBody'] as String?,
      responseHeaders: (json['responseHeaders'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v.toString()),
          ) ??
          {},
      responseBody: json['responseBody'] as String?,
      error: json['error'] as String?,
    );
  }
}

/// App lifecycle and viewport changes.
class LifecycleFlightEvent extends FlightEvent {
  final String state; // 'resumed', 'inactive', 'paused', 'detached', 'metricsChanged'
  final double? width;
  final double? height;
  final double? devicePixelRatio;

  const LifecycleFlightEvent({
    required super.timestampMs,
    required this.state,
    this.width,
    this.height,
    this.devicePixelRatio,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'lifecycle',
        'timestampMs': timestampMs,
        'state': state,
        'width': width,
        'height': height,
        'devicePixelRatio': devicePixelRatio,
      };

  factory LifecycleFlightEvent.fromJson(Map<String, dynamic> json) {
    return LifecycleFlightEvent(
      timestampMs: json['timestampMs'] as int,
      state: json['state'] as String,
      width: (json['width'] as num?)?.toDouble(),
      height: (json['height'] as num?)?.toDouble(),
      devicePixelRatio: (json['devicePixelRatio'] as num?)?.toDouble(),
    );
  }
}

/// Unhandled crash or intercepted exception.
class CrashFlightEvent extends FlightEvent {
  final String exception;
  final String stackTrace;
  final String? errorDetails;

  const CrashFlightEvent({
    required super.timestampMs,
    required this.exception,
    required this.stackTrace,
    this.errorDetails,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'crash',
        'timestampMs': timestampMs,
        'exception': exception,
        'stackTrace': stackTrace,
        'errorDetails': errorDetails,
      };

  factory CrashFlightEvent.fromJson(Map<String, dynamic> json) {
    return CrashFlightEvent(
      timestampMs: json['timestampMs'] as int,
      exception: json['exception'] as String,
      stackTrace: json['stackTrace'] as String,
      errorDetails: json['errorDetails'] as String?,
    );
  }
}

/// Custom breadcrumb or state transition event.
class CustomBreadcrumbFlightEvent extends FlightEvent {
  final String name;
  final String category;
  final Map<String, dynamic> data;

  const CustomBreadcrumbFlightEvent({
    required super.timestampMs,
    required this.name,
    this.category = 'default',
    this.data = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'breadcrumb',
        'timestampMs': timestampMs,
        'name': name,
        'category': category,
        'data': data,
      };

  factory CustomBreadcrumbFlightEvent.fromJson(Map<String, dynamic> json) {
    return CustomBreadcrumbFlightEvent(
      timestampMs: json['timestampMs'] as int,
      name: json['name'] as String,
      category: json['category'] as String? ?? 'default',
      data: (json['data'] as Map<String, dynamic>?) ?? {},
    );
  }
}

// ---------------------------------------------------------------------------
// New event types
// ---------------------------------------------------------------------------

/// Pointer event enriched with semantic widget-identity information resolved at
/// record time via a hit-test so that the test synthesizer can generate robust
/// widget-finder expressions (by key, type, text, tooltip, or semantic label)
/// instead of relying solely on raw coordinates.
///
/// [action]           – One of: 'down', 'move', 'up', 'cancel', 'scroll'.
/// [dx] / [dy]        – Screen-space position in logical pixels.
/// [pointerId]        – Device pointer ID (useful for multi-touch sessions).
/// [buttons]          – Bitmask matching Flutter's [PointerEvent.buttons].
/// [deviceKind]       – 'touch', 'mouse', 'stylus', or 'trackpad'.
/// [scrollDeltaDx] / [scrollDeltaDy] – Non-zero for scroll events.
/// [resolvedKey]      – Value of the first ancestor Widget.key (ValueKey /
///                      ObjectKey) found during hit-test, e.g. 'submit_btn'.
/// [resolvedType]     – Runtime type name of the hit widget, e.g. 'ElevatedButton'.
/// [resolvedText]     – Text content found inside the hit widget subtree.
/// [resolvedTooltip]  – Tooltip string registered on the hit widget.
/// [resolvedSemLabel] – Accessibility semantics label (SemanticsNode.label).
class SemanticPointerFlightEvent extends PointerFlightEvent {
  // Semantic resolution fields – populated at record time via hit-test.
  final String? resolvedKey;
  final String? resolvedType;
  final String? resolvedText;
  final String? resolvedTooltip;
  final String? resolvedSemLabel;

  String? get resolvedWidgetType => resolvedType;

  bool get hasSemantic =>
      resolvedKey != null ||
      resolvedText != null ||
      resolvedTooltip != null ||
      resolvedSemLabel != null ||
      resolvedType != null;

  String toFinderExpression([double? fallbackDx, double? fallbackDy]) {
    if (resolvedKey != null) {
      return "find.byKey(const Key('${_esc(resolvedKey!)}'))";
    }
    if (resolvedText != null) {
      return "find.text('${_esc(resolvedText!)}')";
    }
    if (resolvedTooltip != null) {
      return "find.byTooltip('${_esc(resolvedTooltip!)}')";
    }
    if (resolvedSemLabel != null) {
      return "find.bySemanticsLabel('${_esc(resolvedSemLabel!)}')";
    }
    if (resolvedType != null) {
      return 'find.byType($resolvedType)';
    }
    final x = (fallbackDx ?? dx).toStringAsFixed(1);
    final y = (fallbackDy ?? dy).toStringAsFixed(1);
    return 'const Offset($x, $y)';
  }

  static String _esc(String s) => s.replaceAll("'", r"\'");

  const SemanticPointerFlightEvent({
    required super.timestampMs,
    required super.action,
    required super.dx,
    required super.dy,
    super.pointerId = 0,
    super.buttons = 1,
    super.deviceKind = 'touch',
    super.scrollDeltaDx = 0.0,
    super.scrollDeltaDy = 0.0,
    this.resolvedKey,
    this.resolvedType,
    this.resolvedText,
    this.resolvedTooltip,
    this.resolvedSemLabel,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'semantic_pointer',
        'timestampMs': timestampMs,
        'action': action,
        'dx': dx,
        'dy': dy,
        'pointerId': pointerId,
        'buttons': buttons,
        'deviceKind': deviceKind,
        'scrollDeltaDx': scrollDeltaDx,
        'scrollDeltaDy': scrollDeltaDy,
        'resolvedKey': resolvedKey,
        'resolvedType': resolvedType,
        'resolvedText': resolvedText,
        'resolvedTooltip': resolvedTooltip,
        'resolvedSemLabel': resolvedSemLabel,
      };

  factory SemanticPointerFlightEvent.fromJson(Map<String, dynamic> json) {
    return SemanticPointerFlightEvent(
      timestampMs: json['timestampMs'] as int,
      action: json['action'] as String,
      dx: (json['dx'] as num).toDouble(),
      dy: (json['dy'] as num).toDouble(),
      pointerId: json['pointerId'] as int? ?? 0,
      buttons: json['buttons'] as int? ?? 1,
      deviceKind: json['deviceKind'] as String? ?? 'touch',
      scrollDeltaDx: (json['scrollDeltaDx'] as num?)?.toDouble() ?? 0.0,
      scrollDeltaDy: (json['scrollDeltaDy'] as num?)?.toDouble() ?? 0.0,
      resolvedKey: json['resolvedKey'] as String?,
      resolvedType: json['resolvedType'] as String?,
      resolvedText: json['resolvedText'] as String?,
      resolvedTooltip: json['resolvedTooltip'] as String?,
      resolvedSemLabel: json['resolvedSemLabel'] as String?,
    );
  }
}

/// Keyboard / IME event captured by intercepting the `flutter/textinput`
/// platform channel.  PII is redacted before the event is stored; raw text is
/// never persisted.
///
/// [action]        – One of: 'updateValue', 'performAction', 'setClient',
///                   'clearClient'.
/// [fieldKey]      – Widget key of the focused TextField, if resolved via the
///                   [TextInputInterceptor]'s focus-to-key registry.
/// [fieldType]     – Runtime type of the focused input widget (e.g. 'TextField',
///                   'TextFormField', 'CupertinoTextField').
/// [redactedText]  – The typed text after all [RedactionEngine] rules have been
///                   applied; never the raw value.
/// [selectionBase] – Caret / selection start index (from TextEditingValue).
/// [selectionExtent] – Caret / selection end index.
/// [inputAction]   – The [TextInputAction] label: 'done', 'next', 'send',
///                   'go', 'search', etc.
class TextInputFlightEvent extends FlightEvent {
  final String action;
  final String? fieldKey;
  final String? fieldType;
  final String? redactedText;
  final int? selectionBase;
  final int? selectionExtent;
  final String? inputAction;

  String get text => redactedText ?? '';
  String? get fieldWidgetType => fieldType;

  const TextInputFlightEvent({
    required super.timestampMs,
    required this.action,
    this.fieldKey,
    this.fieldType,
    this.redactedText,
    this.selectionBase,
    this.selectionExtent,
    this.inputAction,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'text_input',
        'timestampMs': timestampMs,
        'action': action,
        'fieldKey': fieldKey,
        'fieldType': fieldType,
        'redactedText': redactedText,
        'selectionBase': selectionBase,
        'selectionExtent': selectionExtent,
        'inputAction': inputAction,
      };

  factory TextInputFlightEvent.fromJson(Map<String, dynamic> json) {
    return TextInputFlightEvent(
      timestampMs: json['timestampMs'] as int,
      action: json['action'] as String,
      fieldKey: json['fieldKey'] as String?,
      fieldType: json['fieldType'] as String?,
      redactedText: json['redactedText'] as String?,
      selectionBase: json['selectionBase'] as int?,
      selectionExtent: json['selectionExtent'] as int?,
      inputAction: json['inputAction'] as String?,
    );
  }
}

/// A MethodChannel or EventChannel call captured at the
/// [BinaryMessenger] level.  Binary payloads are base64-encoded and truncated
/// to 16 KB so that large binary blobs (images, fonts) do not bloat the flight
/// recording.
///
/// [channelName]  – e.g. 'plugins.flutter.io/camera'.
/// [direction]    – 'toNative' (Dart → platform) or 'fromNative'
///                  (platform → Dart reply / EventChannel message).
/// [methodName]   – Method name decoded from the standard MethodCodec, if
///                  available; `null` for EventChannel streams.
/// [encodedArgs]  – base64url-encoded, truncated binary payload.  Consumers
///                  should treat this as an opaque diagnostic blob.
/// [isError]      – `true` when the platform replied with a PlatformException
///                  or the EventChannel emitted an error event.
class PlatformChannelFlightEvent extends FlightEvent {
  final String channelName;
  final String direction;
  final String? methodName;
  final String? encodedArgs;
  final bool isError;

  String get channel => channelName;
  String? get method => methodName;
  String? get resultJson => encodedArgs;
  String? get argumentsJson => encodedArgs;

  const PlatformChannelFlightEvent({
    required super.timestampMs,
    required this.channelName,
    required this.direction,
    this.methodName,
    this.encodedArgs,
    this.isError = false,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'platform_channel',
        'timestampMs': timestampMs,
        'channelName': channelName,
        'direction': direction,
        'methodName': methodName,
        'encodedArgs': encodedArgs,
        'isError': isError,
      };

  factory PlatformChannelFlightEvent.fromJson(Map<String, dynamic> json) {
    return PlatformChannelFlightEvent(
      timestampMs: json['timestampMs'] as int,
      channelName: json['channelName'] as String,
      direction: json['direction'] as String,
      methodName: json['methodName'] as String?,
      encodedArgs: json['encodedArgs'] as String?,
      isError: json['isError'] as bool? ?? false,
    );
  }
}

/// A WebSocket lifecycle or message event captured by wrapping the
/// WebSocket client used by the application.
///
/// [url]       – The WebSocket endpoint URL.
/// [direction] – One of: 'connected', 'disconnected', 'sent', 'received',
///               'error'.
/// [message]   – UTF-8 text message, truncated and PII-redacted.  `null` for
///               lifecycle events ('connected', 'disconnected') or binary
///               frames when [isBinary] is `true`.
/// [isBinary]  – `true` for binary (Uint8List) frames.
/// [error]     – Error description when [direction] is 'error'.
class WebSocketFlightEvent extends FlightEvent {
  final String url;
  final String direction;
  final String? message;
  final bool isBinary;
  final String? error;

  String? get payload => message;

  const WebSocketFlightEvent({
    required super.timestampMs,
    required this.url,
    required this.direction,
    this.message,
    this.isBinary = false,
    this.error,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'websocket',
        'timestampMs': timestampMs,
        'url': url,
        'direction': direction,
        'message': message,
        'isBinary': isBinary,
        'error': error,
      };

  factory WebSocketFlightEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketFlightEvent(
      timestampMs: json['timestampMs'] as int,
      url: json['url'] as String,
      direction: json['direction'] as String,
      message: json['message'] as String?,
      isBinary: json['isBinary'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }
}

/// A snapshot of the full navigation route stack captured at session start (or
/// whenever a recording resumes mid-session).  The synthesizer uses this to
/// emit the correct sequence of [Navigator.pushNamed] calls so that the
/// replayed test starts on the right screen even for deeply-nested routes.
///
/// [routeStack]      – Ordered list of route names from root to top, e.g.
///                     `['/', '/home', '/product/42', '/checkout']`.
/// [routeArguments]  – A JSON-safe map keyed by route name containing the
///                     route's constructor arguments at the time the snapshot
///                     was taken.  Values must be JSON-encodable primitives or
///                     collections thereof.
class RouteStackSnapshotEvent extends FlightEvent {
  final List<String> routeStack;
  final Map<String, dynamic> routeArguments;

  List<String> get stack => routeStack;

  const RouteStackSnapshotEvent({
    required super.timestampMs,
    required this.routeStack,
    this.routeArguments = const {},
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'route_stack_snapshot',
        'timestampMs': timestampMs,
        'routeStack': routeStack,
        'routeArguments': routeArguments,
      };

  factory RouteStackSnapshotEvent.fromJson(Map<String, dynamic> json) {
    return RouteStackSnapshotEvent(
      timestampMs: json['timestampMs'] as int,
      routeStack: (json['routeStack'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      routeArguments:
          (json['routeArguments'] as Map<String, dynamic>?) ?? const {},
    );
  }
}
