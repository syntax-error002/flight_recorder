import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/event_models.dart';
import '../core/redaction_engine.dart';
import '../core/semantic_resolver.dart';

// ---------------------------------------------------------------------------
// Public callback type
// ---------------------------------------------------------------------------

/// Callback invoked whenever a [TextInputFlightEvent] is captured.
typedef OnTextInputFlightEvent = void Function(TextInputFlightEvent event);

// ---------------------------------------------------------------------------
// _FlightRecordingControl
// ---------------------------------------------------------------------------

class _FlightRecordingControl with TextInputControl {
  final TextInputInterceptor interceptor;
  _FlightRecordingControl(this.interceptor);

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    interceptor._handleClientAttached(client, configuration);
  }

  @override
  void setEditingState(TextEditingValue value) {
    interceptor._handleEditingState(value);
  }

  @override
  void detach(TextInputClient client) {
    interceptor._handleClientDetached(client);
  }
}

// ---------------------------------------------------------------------------
// TextInputInterceptor — public API
// ---------------------------------------------------------------------------

/// Intercepts keyboard / IME events by plugging into Flutter's native
/// [TextInputControl] mechanism.
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
/// Raw text is *never* stored. Every text value passes through [redaction]
/// before being assigned to [TextInputFlightEvent.redactedText].
///
/// ## Focus registry
///
/// [focusKeyRegistry] maps a focus-node hash-code (as a decimal string) to
/// the widget's key string. Callers should populate this map from a
/// [FocusManager.instance] listener or from the [TextInputInterceptor]'s host
/// widget. When no matching entry is found the [TextInputFlightEvent.fieldKey]
/// is resolved semantically via label or widget keys.
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
  }) {
    _control = _FlightRecordingControl(this);
  }

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
  late final _FlightRecordingControl _control;
  String? _activeFieldKey;
  String? _activeFieldType;

  // ---- TextInputControl handlers -------------------------------------------

  void _handleClientAttached(
      TextInputClient client, TextInputConfiguration configuration) {
    final int ts = stopwatch.elapsedMilliseconds;
    String? resolvedKey;
    try {
      final focus = FocusManager.instance.primaryFocus;
      final ctx = focus?.context;
      ctx?.visitAncestorElements((a) {
        final w = a.widget;
        if (w is TextField) {
          final cleanKey = SemanticResolver.extractKey(w.key);
          if (cleanKey != null) {
            resolvedKey = cleanKey;
          } else if (w.decoration?.labelText?.isNotEmpty == true) {
            resolvedKey = 'label:${w.decoration!.labelText}';
          } else if (w.decoration?.hintText?.isNotEmpty == true) {
            resolvedKey = 'label:${w.decoration!.hintText}';
          }
          return false;
        }
        return true;
      });
    } catch (_) {}

    _activeFieldKey = resolvedKey;
    _activeFieldType = configuration.inputType.toString();

    onEvent(TextInputFlightEvent(
      timestampMs: ts,
      action: 'setClient',
      fieldKey: _activeFieldKey,
      fieldType: _activeFieldType,
      inputAction: configuration.inputAction.name,
    ));
  }

  void _handleEditingState(TextEditingValue value) {
    final int ts = stopwatch.elapsedMilliseconds;
    final redacted = redaction.sanitizeString(value.text);
    onEvent(TextInputFlightEvent(
      timestampMs: ts,
      action: 'updateValue',
      fieldKey: _activeFieldKey,
      fieldType: _activeFieldType,
      redactedText: redacted,
      selectionBase: value.selection.baseOffset,
      selectionExtent: value.selection.extentOffset,
    ));
  }

  void _handleClientDetached(TextInputClient client) {
    final int ts = stopwatch.elapsedMilliseconds;
    onEvent(TextInputFlightEvent(
      timestampMs: ts,
      action: 'clearClient',
      fieldKey: _activeFieldKey,
    ));
    _activeFieldKey = null;
    _activeFieldType = null;
  }

  // ---- Lifecycle -----------------------------------------------------------

  /// Attaches the interceptor to Flutter's text input control mechanism.
  void attach() {
    if (_attached) return;

    try {
      TextInput.setInputControl(_control);
    } catch (_) {}

    try {
      FocusManager.instance.addListener(_handleFocusChange);
    } catch (_) {}

    _attached = true;
  }

  /// Restores the original text input control.
  void detach() {
    if (!_attached) return;

    try {
      TextInput.restorePlatformInputControl();
    } catch (_) {}

    try {
      FocusManager.instance.removeListener(_handleFocusChange);
    } catch (_) {}

    _attached = false;
  }

  void _handleFocusChange() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return;
    final context = focus.context;
    if (context == null) return;
    try {
      final identity = SemanticResolver.resolve(Offset.zero, context);
      final key = identity?.key;
      if (key != null) {
        focusKeyRegistry[focus.hashCode.toString()] = key;
      }
    } catch (_) {}
  }
}
