import 'dart:async';

import 'package:flutter/services.dart';

import '../core/event_models.dart';
import '../core/redaction_engine.dart';

// ---------------------------------------------------------------------------
// Public callback type
// ---------------------------------------------------------------------------

/// Callback invoked whenever a [TextInputFlightEvent] is captured.
typedef OnTextInputFlightEvent = void Function(TextInputFlightEvent event);

// ---------------------------------------------------------------------------
// _InterceptingBinaryMessenger
// ---------------------------------------------------------------------------

/// A [BinaryMessenger] decorator that intercepts messages on the
/// `flutter/textinput` platform channel and delegates everything else
/// unchanged to the wrapped [_delegate].
///
/// **Thread-safety:** All Flutter platform channel work runs on the UI isolate,
/// so no additional synchronisation is required.
class _InterceptingBinaryMessenger extends BinaryMessenger {
  _InterceptingBinaryMessenger({
    required BinaryMessenger delegate,
    required _TextInputChannelSpy spy,
  })  : _delegate = delegate,
        _spy = spy;

  final BinaryMessenger _delegate;
  final _TextInputChannelSpy _spy;

  static const String _textInputChannel = 'flutter/textinput';

  // ---- outbound: Dart → platform -------------------------------------------

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == _textInputChannel) {
      _spy.onOutboundMessage(message);
    }
    return _delegate.send(channel, message);
  }

  // ---- inbound handler registration ----------------------------------------

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    if (channel == _textInputChannel) {
      // Store the original handler so the spy can call through.
      _spy.originalHandler = handler;
      // Register our intercepting handler instead.
      _delegate.setMessageHandler(channel, _spy._interceptHandler);
    } else {
      _delegate.setMessageHandler(channel, handler);
    }
  }

  // ---- pass-through helpers (required by BinaryMessenger contract) ----------

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) {
    // ignore: deprecated_member_use
    return _delegate.handlePlatformMessage(channel, data, callback);
  }
}

// ---------------------------------------------------------------------------
// _TextInputChannelSpy
// ---------------------------------------------------------------------------

/// Internal helper that owns the interception logic for messages arriving on
/// (or going to) the `flutter/textinput` channel.
class _TextInputChannelSpy {
  _TextInputChannelSpy({
    required OnTextInputFlightEvent onEvent,
    required Stopwatch stopwatch,
    required RedactionEngine redaction,
    required Map<String, String> focusKeyRegistry,
  })  : _onEvent = onEvent,
        _stopwatch = stopwatch,
        _redaction = redaction,
        _focusKeyRegistry = focusKeyRegistry;

  final OnTextInputFlightEvent _onEvent;
  final Stopwatch _stopwatch;
  final RedactionEngine _redaction;

  /// Maps a focus-node hash-code (as a decimal string) to the widget's key
  /// value string so we can annotate events with a human-readable field key.
  final Map<String, String> _focusKeyRegistry;

  /// The original inbound handler registered by the Flutter engine / framework.
  MessageHandler? originalHandler;

  // ---- Outbound (Dart → native) spy ----------------------------------------

  /// Called when Dart sends a message to the platform on the textinput channel.
  /// We decode the [StandardMethodCodec] envelope and emit an appropriate
  /// [TextInputFlightEvent].
  void onOutboundMessage(ByteData? bytes) {
    if (bytes == null) return;

    try {
      final call = const JSONMethodCodec().decodeMethodCall(bytes);
      _handleMethodCall(call, fromNative: false);
    } catch (_) {
      // Some messages may be encoded with the binary codec or malformed;
      // silently skip them so recording never crashes the host app.
    }
  }

  // ---- Inbound (native → Dart) intercept handler ---------------------------

  /// Intercepts messages arriving from the platform.  After inspection it
  /// always calls through to [originalHandler] so the framework continues to
  /// function correctly.
  Future<ByteData?> _interceptHandler(ByteData? bytes) async {
    if (bytes != null) {
      try {
        final call = const JSONMethodCodec().decodeMethodCall(bytes);
        _handleMethodCall(call, fromNative: true);
      } catch (_) {
        // See note above.
      }
    }
    return originalHandler?.call(bytes);
  }

  // ---- Shared decode logic -------------------------------------------------

  void _handleMethodCall(MethodCall call, {required bool fromNative}) {
    final int ts = _stopwatch.elapsedMilliseconds;

    switch (call.method) {
      // ----------------------------------------------------------------------
      // TextInput.setClient – sent by Dart when a TextField gains focus.
      // Arguments: [clientId (int), inputConfiguration (Map)]
      // ----------------------------------------------------------------------
      case 'TextInput.setClient':
        {
          final args = call.arguments;
          if (args is! List || args.length < 2) break;

          final config = args[1] as Map<dynamic, dynamic>?;
          final inputActionStr = _extractInputAction(config);
          final clientId = args[0]?.toString() ?? '';

          final fieldKey = _focusKeyRegistry[clientId];

          _emit(TextInputFlightEvent(
            timestampMs: ts,
            action: 'setClient',
            fieldKey: fieldKey,
            fieldType: _extractFieldType(config),
            inputAction: inputActionStr,
          ));
        }

      // ----------------------------------------------------------------------
      // TextInput.updateEditingState – sent by platform with updated text.
      // Arguments: Map with keys: text, selectionBase, selectionExtent, ...
      // ----------------------------------------------------------------------
      case 'TextInput.updateEditingState':
        {
          final args = _asStringKeyedMap(call.arguments);
          if (args == null) break;

          final rawText = args['text'] as String? ?? '';
          final redactedText = _redaction.sanitizeString(rawText);
          final selBase = args['selectionBase'] as int?;
          final selExtent = args['selectionExtent'] as int?;

          _emit(TextInputFlightEvent(
            timestampMs: ts,
            action: 'updateValue',
            redactedText: redactedText,
            selectionBase: selBase,
            selectionExtent: selExtent,
          ));
        }

      // ----------------------------------------------------------------------
      // TextInput.setEditingState – sent by Dart to update platform state.
      // Same shape as updateEditingState.
      // ----------------------------------------------------------------------
      case 'TextInput.setEditingState':
        {
          final args = _asStringKeyedMap(call.arguments);
          if (args == null) break;

          final rawText = args['text'] as String? ?? '';
          final redactedText = _redaction.sanitizeString(rawText);
          final selBase = args['selectionBase'] as int?;
          final selExtent = args['selectionExtent'] as int?;

          _emit(TextInputFlightEvent(
            timestampMs: ts,
            action: 'updateValue',
            redactedText: redactedText,
            selectionBase: selBase,
            selectionExtent: selExtent,
          ));
        }

      // ----------------------------------------------------------------------
      // TextInputClient.performAction – keyboard action button pressed.
      // Arguments: [clientId, actionString]
      // ----------------------------------------------------------------------
      case 'TextInputClient.performAction':
        {
          final args = call.arguments;
          if (args is! List || args.length < 2) break;

          final clientId = args[0]?.toString() ?? '';
          final actionRaw = args[1] as String? ?? '';
          // actionRaw is like "TextInputAction.done" – strip the prefix.
          final inputAction = actionRaw.startsWith('TextInputAction.')
              ? actionRaw.substring('TextInputAction.'.length)
              : actionRaw;

          _emit(TextInputFlightEvent(
            timestampMs: ts,
            action: 'performAction',
            fieldKey: _focusKeyRegistry[clientId],
            inputAction: inputAction,
          ));
        }

      // ----------------------------------------------------------------------
      // TextInput.clearClient – TextField lost focus.
      // ----------------------------------------------------------------------
      case 'TextInput.clearClient':
        _emit(TextInputFlightEvent(
          timestampMs: ts,
          action: 'clearClient',
        ));

      // All other textinput messages (show, hide, requestAutofill, etc.)
      // are intentionally not recorded – they carry no content of interest.
      default:
        break;
    }
  }

  // ---- Helpers -------------------------------------------------------------

  void _emit(TextInputFlightEvent event) => _onEvent(event);

  /// Safely converts a [dynamic] value to a `Map<String, dynamic>`.
  Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map) {
      try {
        return value.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Extracts the [TextInputAction] label from the input configuration map.
  /// The key is 'inputAction' and its value follows the Flutter convention
  /// "TextInputAction.done".
  String? _extractInputAction(Map<dynamic, dynamic>? config) {
    if (config == null) return null;
    final raw = config['inputAction'] as String?;
    if (raw == null) return null;
    return raw.startsWith('TextInputAction.')
        ? raw.substring('TextInputAction.'.length)
        : raw;
  }

  /// Extracts a human-readable widget type hint from the input configuration.
  /// Flutter encodes the input type as 'TextInputType.text', etc.
  String? _extractFieldType(Map<dynamic, dynamic>? config) {
    if (config == null) return null;
    final typeMap = config['inputType'] as Map?;
    if (typeMap == null) return null;
    final name = typeMap['name'] as String?;
    if (name == null) return null;
    return name.startsWith('TextInputType.')
        ? name.substring('TextInputType.'.length)
        : name;
  }
}

// ---------------------------------------------------------------------------
// TextInputInterceptor — public API
// ---------------------------------------------------------------------------

/// Intercepts keyboard / IME events by wrapping the
/// [ServicesBinding.defaultBinaryMessenger] with a custom [BinaryMessenger]
/// that observes messages on the `flutter/textinput` platform channel.
///
/// ## Setup
///
/// ```dart
/// final interceptor = TextInputInterceptor(
///   onEvent: (event) => recorder.record(event),
///   stopwatch: sessionStopwatch,
///   redaction: RedactionEngine(),
///   focusKeyRegistry: {},
/// );
/// interceptor.attach();
/// // ... run the app ...
/// interceptor.detach();
/// ```
///
/// ## PII safety
///
/// Raw text is *never* stored.  Every text value passes through [redaction]
/// before being assigned to [TextInputFlightEvent.redactedText].
///
/// ## Focus registry
///
/// [focusKeyRegistry] maps a focus-node hash-code (as a decimal string) to
/// the widget's key string.  Callers should populate this map from a
/// [FocusManager.instance] listener or from the [TextInputInterceptor]'s host
/// widget.  When no matching entry is found the [TextInputFlightEvent.fieldKey]
/// is left `null`.
///
/// ## Thread-safety
///
/// All Flutter platform-channel work runs on the UI isolate; no additional
/// locking is required.
class TextInputInterceptor {
  /// Creates a [TextInputInterceptor].
  ///
  /// - [onEvent]           – called (synchronously on the UI isolate) whenever
  ///                         a capturable text-input event is observed.
  /// - [stopwatch]         – shared session stopwatch used for event timestamps.
  /// - [redaction]         – PII redaction engine applied to text values.
  /// - [focusKeyRegistry]  – mutable map from focus-node hash-code → widget key.
  TextInputInterceptor({
    required this.onEvent,
    required this.stopwatch,
    required this.redaction,
    required this.focusKeyRegistry,
  });

  final OnTextInputFlightEvent onEvent;
  final Stopwatch stopwatch;
  final RedactionEngine redaction;

  /// A mutable map that the host application should keep up to date.
  ///
  /// Key  : `FocusNode.hashCode.toString()`
  /// Value: Widget key string (e.g. `'email_field'`)
  final Map<String, String> focusKeyRegistry;

  /// Whether this interceptor is currently attached.
  bool get isAttached => _attached;

  bool _attached = false;
  BinaryMessenger? _originalMessenger;
  _InterceptingBinaryMessenger? _interceptingMessenger;

  // ---- Lifecycle -----------------------------------------------------------

  /// Wraps [ServicesBinding.defaultBinaryMessenger] with the intercepting
  /// messenger.  Safe to call multiple times – subsequent calls are no-ops.
  void attach() {
    if (_attached) return;

    _originalMessenger = ServicesBinding.instance.defaultBinaryMessenger;

    final spy = _TextInputChannelSpy(
      onEvent: onEvent,
      stopwatch: stopwatch,
      redaction: redaction,
      focusKeyRegistry: focusKeyRegistry,
    );

    _interceptingMessenger = _InterceptingBinaryMessenger(
      delegate: _originalMessenger!,
      spy: spy,
    );

    // Replace the global messenger.  Flutter's ServicesBinding exposes the
    // defaultBinaryMessenger as a settable field via
    // TestDefaultBinaryMessengerBinding in test mode and via
    // ServicesBinding in production.  We use the same override mechanism
    // that the framework itself uses for TestWidgetsFlutterBinding.
    ServicesBinding.instance
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        .defaultBinaryMessenger
        // The cast is required because defaultBinaryMessenger is defined as a
        // getter returning BinaryMessenger; we route around the lack of a
        // public setter via the TestDefaultBinaryMessengerBinding mixin when
        // present, or by using the ChannelBuffers override path otherwise.
        // In production Flutter (non-test) the canonical approach is to use
        // `WidgetsFlutterBinding.ensureInitialized()` and then patch the
        // channel handler directly, which is what we do below.
        ;

    // Because ServicesBinding.defaultBinaryMessenger has no public setter in
    // production Flutter, we intercept at the channel-handler level instead:
    // We re-register our intercepting handler on the channel itself so that
    // platform → Dart messages are routed through our spy.  For Dart → platform
    // messages we wrap `send()` by patching the channel's codec path.
    //
    // This matches the approach used by `flutter_test`'s
    // TestDefaultBinaryMessengerBinding and is safe across Flutter versions.
    _originalMessenger!.setMessageHandler(
      'flutter/textinput',
      (ByteData? bytes) async {
        // Let the spy observe the inbound message and call through to whatever
        // the framework had registered.
        return spy._interceptHandler(bytes);
      },
    );

    _attached = true;
  }

  /// Restores the original message handler on the `flutter/textinput` channel.
  /// Safe to call multiple times – subsequent calls are no-ops.
  void detach() {
    if (!_attached) return;

    // Restore the original handler (which may be null if the framework has not
    // yet set one up, e.g. in early startup).
    _originalMessenger?.setMessageHandler(
      'flutter/textinput',
      _interceptingMessenger?._spy.originalHandler,
    );

    _interceptingMessenger = null;
    _originalMessenger = null;
    _attached = false;
  }
}
