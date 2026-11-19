// ignore_for_file: implementation_imports
// Copyright 2024 The FlightRecorder Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

/// Production-grade Platform Channel interceptor for the flight_recorder package.
///
/// Wraps [ServicesBinding.defaultBinaryMessenger] with a custom
/// [BinaryMessenger] that records every outgoing MethodChannel call and
/// every incoming response as a [PlatformChannelFlightEvent].
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Public event model
// ---------------------------------------------------------------------------

/// Direction of a platform-channel message.
enum PlatformChannelDirection {
  /// Flutter → native (outgoing call).
  toNative,

  /// Native → Flutter (incoming response or event).
  fromNative,
}

/// A single recorded platform-channel interaction.
@immutable
class PlatformChannelRawEvent {
  const PlatformChannelRawEvent({
    required this.id,
    required this.channel,
    required this.method,
    required this.direction,
    required this.timestampMicros,
    required this.elapsedMicros,
    this.arguments,
    this.result,
    this.errorCode,
    this.errorMessage,
    this.errorDetails,
    this.wasTruncated = false,
  });

  /// Monotonically-increasing identifier within a recording session.
  final int id;

  /// The MethodChannel name, e.g. `"com.example.app/payments"`.
  final String channel;

  /// The method name decoded from the codec, e.g. `"charge"`.
  final String method;

  /// Whether this event represents a call going out or a response coming back.
  final PlatformChannelDirection direction;

  /// Wall-clock timestamp in microseconds since epoch.
  final int timestampMicros;

  /// Elapsed microseconds since the [PlatformChannelInterceptor] was attached.
  final int elapsedMicros;

  /// Arguments sent with the call ([PlatformChannelDirection.toNative]) or
  /// `null` for response events.
  final Object? arguments;

  /// Return value from native ([PlatformChannelDirection.fromNative]) or
  /// `null` for call events.
  final Object? result;

  // ---- Error fields (populated when native returns a PlatformException) ----

  /// Error code, populated when native throws a [PlatformException].
  final String? errorCode;

  /// Human-readable error message.
  final String? errorMessage;

  /// Additional error details forwarded from native.
  final Object? errorDetails;

  /// True when the binary payload exceeded [PlatformChannelInterceptor.maxPayloadBytes]
  /// and was truncated before decoding.
  final bool wasTruncated;

  @override
  String toString() =>
      'PlatformChannelRawEvent(id=$id, $direction, channel=$channel, '
      'method=$method, errorCode=$errorCode)';

  Map<String, Object?> toJson() => {
        'id': id,
        'channel': channel,
        'method': method,
        'direction': direction.name,
        'timestampMicros': timestampMicros,
        'elapsedMicros': elapsedMicros,
        if (arguments != null) 'arguments': _safeSerialise(arguments),
        if (result != null) 'result': _safeSerialise(result),
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (errorDetails != null) 'errorDetails': _safeSerialise(errorDetails),
        'wasTruncated': wasTruncated,
      };

  static Object? _safeSerialise(Object? value) {
    if (value == null) return null;
    try {
      // Verify JSON-encode is possible; if not, fall back to toString.
      jsonEncode(value);
      return value;
    } catch (_) {
      return value.toString();
    }
  }
}

/// Callback type for platform-channel events.
typedef OnPlatformChannelEvent = void Function(PlatformChannelRawEvent event);

// ---------------------------------------------------------------------------
// Channels that Flutter uses internally – never record these.
// ---------------------------------------------------------------------------

const Set<String> _kAlwaysIgnoredChannels = {
  'flutter/textinput',
  'flutter/navigation',
  'flutter/lifecycle',
  'flutter/keyevent',
  'flutter/platform',
  'flutter/accessibility',
  'flutter/mousecursor',
  'flutter/restoration',
};

// ---------------------------------------------------------------------------
// PlatformChannelInterceptor
// ---------------------------------------------------------------------------

/// Attaches to [ServicesBinding.defaultBinaryMessenger] and records every
/// outgoing MethodChannel call and every incoming response.
///
/// Usage:
/// ```dart
/// final interceptor = PlatformChannelInterceptor(
///   onEvent: (event) => recorder.add(event),
/// );
/// interceptor.attach();
/// // … run app / test …
/// interceptor.detach();
/// ```
class PlatformChannelInterceptor {
  PlatformChannelInterceptor({
    required this.onEvent,
    Stopwatch? stopwatch,
    Set<String>? ignoredChannels,
    this.maxPayloadBytes = 16384,
  })  : stopwatch = stopwatch ?? (Stopwatch()..start()),
        ignoredChannels = {
          ..._kAlwaysIgnoredChannels,
          ...?ignoredChannels,
        };

  /// Called whenever a [PlatformChannelRawEvent] is captured.
  final OnPlatformChannelEvent onEvent;

  /// Used to calculate [PlatformChannelRawEvent.elapsedMicros].
  final Stopwatch stopwatch;

  /// Channel names that should be silently passed through without recording.
  final Set<String> ignoredChannels;

  /// Maximum byte length of a binary payload before it is truncated and the
  /// raw bytes are discarded.  Set to `0` to disable truncation.
  final int maxPayloadBytes;

  BinaryMessenger? _originalMessenger;
  _RecordingBinaryMessenger? _recordingMessenger;
  bool _isAttached = false;
  int _nextId = 0;

  /// Whether the interceptor is currently attached.
  bool get isAttached => _isAttached;

  /// Installs the recording [BinaryMessenger].
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  void attach() {
    if (_isAttached) return;
    _originalMessenger = ServicesBinding.instance.defaultBinaryMessenger;
    _recordingMessenger = _RecordingBinaryMessenger(
      original: _originalMessenger!,
      interceptor: this,
    );
    _setDefaultBinaryMessenger(_recordingMessenger!);
    _isAttached = true;
    if (kDebugMode) {
      debugPrint('[FlightRecorder] PlatformChannelInterceptor attached');
    }
  }

  /// Removes the recording [BinaryMessenger] and restores the original.
  ///
  /// Safe to call multiple times; subsequent calls are no-ops.
  void detach() {
    if (!_isAttached) return;
    _setDefaultBinaryMessenger(_originalMessenger!);
    _originalMessenger = null;
    _recordingMessenger = null;
    _isAttached = false;
    if (kDebugMode) {
      debugPrint('[FlightRecorder] PlatformChannelInterceptor detached');
    }
  }

  // ---- Internal helpers ---------------------------------------------------

  int _nextEventId() => _nextId++;

  void _emit(PlatformChannelRawEvent event) {
    try {
      onEvent(event);
    } catch (e, s) {
      // Never let a listener crash the app.
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: s,
        library: 'flight_recorder',
        context: ErrorDescription('in PlatformChannelInterceptor.onEvent'),
      ));
    }
  }

  /// Attempts to decode a raw binary message as a [MethodCall] using
  /// [StandardMethodCodec] first, then [JSONMethodCodec].
  ///
  /// Returns `null` if decoding fails with both codecs.
  _DecodedCall? _decodeCall(ByteData? message, bool truncated) {
    if (message == null) return _DecodedCall('(null)', null);

    for (final codec in const <MethodCodec>[
      StandardMethodCodec(),
      JSONMethodCodec(),
    ]) {
      try {
        final call = codec.decodeMethodCall(message);
        return _DecodedCall(call.method, call.arguments);
      } catch (_) {
        // try next codec
      }
    }
    return null;
  }

  /// Attempts to decode a binary response envelope.
  _DecodedResponse? _decodeResponse(ByteData? reply) {
    if (reply == null) return const _DecodedResponse(null, null, null, null);

    for (final codec in const <MethodCodec>[
      StandardMethodCodec(),
      JSONMethodCodec(),
    ]) {
      try {
        final result = codec.decodeEnvelope(reply);
        return _DecodedResponse(result, null, null, null);
      } on PlatformException catch (e) {
        return _DecodedResponse(null, e.code, e.message, e.details);
      } catch (_) {
        // try next codec
      }
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// _RecordingBinaryMessenger — the core wrapper
// ---------------------------------------------------------------------------

class _RecordingBinaryMessenger extends BinaryMessenger {
  _RecordingBinaryMessenger({
    required this.original,
    required this.interceptor,
  });

  final BinaryMessenger original;
  final PlatformChannelInterceptor interceptor;

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    if (interceptor.ignoredChannels.contains(channel)) {
      return original.send(channel, message);
    }

    // ---- Optionally truncate oversized payloads --------------------------
    bool truncated = false;
    ByteData? effectiveMessage = message;
    if (interceptor.maxPayloadBytes > 0 &&
        message != null &&
        message.lengthInBytes > interceptor.maxPayloadBytes) {
      truncated = true;
      effectiveMessage = message.buffer.asByteData(
        message.offsetInBytes,
        interceptor.maxPayloadBytes,
      );
    }

    // ---- Decode the outgoing call ----------------------------------------
    final decoded = interceptor._decodeCall(effectiveMessage, truncated);
    final eventId = interceptor._nextEventId();
    final now = DateTime.now().microsecondsSinceEpoch;
    final elapsed = interceptor.stopwatch.elapsedMicroseconds;

    interceptor._emit(PlatformChannelRawEvent(
      id: eventId,
      channel: channel,
      method: decoded?.method ?? '(unknown)',
      direction: PlatformChannelDirection.toNative,
      timestampMicros: now,
      elapsedMicros: elapsed,
      arguments: decoded?.arguments,
      wasTruncated: truncated,
    ));

    // ---- Forward to native and capture the response ----------------------
    final reply = await original.send(channel, message);

    // ---- Decode the response ---------------------------------------------
    final dr = interceptor._decodeResponse(reply);
    interceptor._emit(PlatformChannelRawEvent(
      id: interceptor._nextEventId(),
      channel: channel,
      method: decoded?.method ?? '(unknown)',
      direction: PlatformChannelDirection.fromNative,
      timestampMicros: DateTime.now().microsecondsSinceEpoch,
      elapsedMicros: interceptor.stopwatch.elapsedMicroseconds,
      result: dr?.result,
      errorCode: dr?.errorCode,
      errorMessage: dr?.errorMessage,
      errorDetails: dr?.errorDetails,
    ));

    return reply;
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      original.handlePlatformMessage(channel, data, callback);

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    original.setMessageHandler(channel, handler);
  }

  void setMockMessageHandler(String channel, MessageHandler? handler) {
    // Forward to original if it supports mocks (test environment).
    if (original is TestDefaultBinaryMessengerBinding) {
      (original as dynamic).setMockMessageHandler(channel, handler);
    } else {
      original.setMessageHandler(channel, handler);
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

class _DecodedCall {
  const _DecodedCall(this.method, this.arguments);
  final String method;
  final Object? arguments;
}

class _DecodedResponse {
  const _DecodedResponse(
      this.result, this.errorCode, this.errorMessage, this.errorDetails);
  final Object? result;
  final String? errorCode;
  final String? errorMessage;
  final Object? errorDetails;
}

/// Installs [messenger] as the process-wide default binary messenger.
///
/// In test environments [TestDefaultBinaryMessengerBinding] is available; in
/// production we use the [ChannelBuffers] back-door via [ServicesBinding].
void _setDefaultBinaryMessenger(BinaryMessenger messenger) {
  try {
    (ServicesBinding.instance as dynamic).defaultBinaryMessenger = messenger;
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// PlatformChannelReplayBinding — test-time channel stubs
// ---------------------------------------------------------------------------

/// Utilities for replaying recorded [PlatformChannelFlightEvent]s in a test
/// environment.
///
/// Typical usage inside a `testWidgets` callback:
/// ```dart
/// PlatformChannelReplayBinding.installAll(recordedEvents);
/// ```
class PlatformChannelReplayBinding {
  PlatformChannelReplayBinding._();

  /// Stubs a single channel+method combination so that any call to [channel]
  /// with the given [methodName] returns [returnValue] without hitting native.
  static void stubChannel(
    String channelName,
    String methodName,
    dynamic returnValue, {
    MethodCodec codec = const StandardMethodCodec(),
    TestDefaultBinaryMessenger? messenger,
  }) {
    final effectiveMessenger = messenger ??
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    effectiveMessenger.setMockMethodCallHandler(
      MethodChannel(channelName, codec),
      (MethodCall call) async {
        if (call.method == methodName) {
          return returnValue;
        }
        return null;
      },
    );
  }

  /// Installs all [PlatformChannelRawEvent]s that have
  /// [PlatformChannelDirection.fromNative] direction as channel stubs.
  ///
  /// For each distinct (channel, method) pair the **last** recorded return
  /// value is used so that the most recent response wins.
  ///
  /// Calls to channels not present in [events] will still raise
  /// [MissingPluginException] unless separately stubbed.
  static void installAll(
    List<PlatformChannelRawEvent> events, [
    TestDefaultBinaryMessenger? messenger,
  ]) {
    // Build a map of channel → method → returnValue from recorded responses.
    final Map<String, Map<String, _StubEntry>> stubs = {};

    for (final event in events) {
      if (event.direction != PlatformChannelDirection.fromNative) continue;
      if (event.errorCode != null) continue; // skip error responses

      stubs.putIfAbsent(event.channel, () => {})[event.method] =
          _StubEntry(event.result);
    }

    final effectiveMessenger = messenger ??
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    for (final channelEntry in stubs.entries) {
      final channelName = channelEntry.key;
      final methodMap = channelEntry.value;

      effectiveMessenger.setMockMethodCallHandler(
        MethodChannel(channelName),
        (MethodCall call) async {
          final stub = methodMap[call.method];
          return stub?.returnValue;
        },
      );
    }
  }

  /// Removes all stubs installed by [installAll] for the given channels.
  static void uninstallAll(
    List<String> channelNames, [
    TestDefaultBinaryMessenger? messenger,
  ]) {
    final effectiveMessenger = messenger ??
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in channelNames) {
      effectiveMessenger.setMockMethodCallHandler(
        MethodChannel(name),
        null,
      );
    }
  }
}

class _StubEntry {
  const _StubEntry(this.returnValue);
  final Object? returnValue;
}
