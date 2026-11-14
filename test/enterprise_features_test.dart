import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_recorder/flight_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 1 & 2: Semantic Hit-Test & Robust Finder Synthesis', () {
    testWidgets('SemanticResolver resolves key and text from widget tree', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('checkout_submit_btn'),
                onPressed: () {},
                child: const Text('Pay \$49.99 Now'),
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byKey(const Key('checkout_submit_btn'));
      final centerOffset = tester.getCenter(buttonFinder);

      final identity = SemanticResolver.resolve(centerOffset, null);
      expect(identity, isNotNull);
      expect(identity!.key, 'checkout_submit_btn');
      expect(identity.text, 'Pay \$49.99 Now');
      expect(identity.isResolvable, isTrue);

      final event = SemanticPointerFlightEvent(
        timestampMs: 100,
        action: 'down',
        dx: centerOffset.dx,
        dy: centerOffset.dy,
        resolvedKey: identity.key,
        resolvedText: identity.text,
        resolvedType: identity.widgetType,
      );

      expect(event.toFinderExpression(), "find.byKey(const Key('checkout_submit_btn'))");
    });
  });

  group('Issue 3: Test Harness & DI Scaffolding Generator', () {
    test('TestHarnessBuilder auto-detects Riverpod and generates harness', () {
      const pubspec = '''
name: my_app
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
''';

      final detected = TestHarnessBuilder.detectFramework(pubspec);
      expect(detected, DiFramework.riverpod);

      final harnessCode = TestHarnessBuilder.generateHarness(
        framework: detected,
        appWidgetConstructor: 'const MyApp()',
        detectedChannels: ['plugins.flutter.io/shared_preferences', 'flutter_secure_storage'],
        detectedHttpHosts: ['api.myapp.com'],
      );

      expect(harnessCode.contains('ProviderScope'), isTrue);
      expect(harnessCode.contains('plugins.flutter.io/shared_preferences'), isTrue);
      expect(harnessCode.contains('flutter_secure_storage'), isTrue);
      expect(harnessCode.contains('FlightReplayServer'), isTrue);
    });

    test('TestHarnessBuilder detects Bloc from pubspec', () {
      const pubspec = 'dependencies:\n  flutter_bloc: ^8.1.3\n';
      expect(TestHarnessBuilder.detectFramework(pubspec), DiFramework.bloc);
    });
  });

  group('Issue 4: Platform Channel Interception & Replay Binding', () {
    test('PlatformChannelReplayBinding stubs native channels avoiding MissingPluginException', () async {
      const channelName = 'com.myapp.secure_vault';
      const methodName = 'getAuthToken';

      PlatformChannelReplayBinding.stubChannel(
        channelName,
        methodName,
        'mock_jwt_token_123',
      );

      const channel = MethodChannel(channelName);
      final result = await channel.invokeMethod<String>(methodName);

      expect(result, 'mock_jwt_token_123');

      PlatformChannelReplayBinding.uninstallAll([channelName]);
    });
  });

  group('Issue 5: Keyboard & Text Input (IME) Event Tracking', () {
    test('TextInputFlightEvent stores and serializes redacted text inputs', () {
      const event = TextInputFlightEvent(
        timestampMs: 350,
        action: 'updateValue',
        fieldKey: 'email_input',
        fieldType: 'TextField',
        redactedText: '[EMAIL_REDACTED]',
        selectionBase: 16,
        selectionExtent: 16,
        inputAction: 'done',
      );

      expect(event.fieldKey, 'email_input');
      expect(event.text, '[EMAIL_REDACTED]');

      final json = event.toJson();
      final restored = TextInputFlightEvent.fromJson(json);

      expect(restored.fieldKey, 'email_input');
      expect(restored.text, '[EMAIL_REDACTED]');
      expect(restored.inputAction, 'done');
    });
  });

  group('Issue 6: Security, Encryption & .eflightlog Format', () {
    test('CryptoEngine encrypts and decrypts with authenticated HMAC', () {
      final key = CryptoEngine.generateRandomKey();
      final crypto = CryptoEngine.withKey(key);

      final originalData = Uint8List.fromList(utf8.encode('Sensitive Flight Session Data with Passwords'));
      final encrypted = crypto.encrypt(originalData);

      expect(encrypted.length > originalData.length, isTrue);

      final decrypted = crypto.decrypt(encrypted);
      expect(utf8.decode(decrypted), 'Sensitive Flight Session Data with Passwords');
    });

    test('SecureFlightSerializer writes and auto-detects .eflightlog files', () async {
      final key = CryptoEngine.generateRandomKey();
      final crypto = CryptoEngine.withKey(key);
      final secureSerializer = SecureFlightSerializer(crypto: crypto);

      final manifest = SessionManifest(
        sessionId: 'encrypted_session_42',
        startedAt: DateTime.utc(2026, 11, 14, 12, 0),
        platform: 'android',
        initialWidth: 412.0,
        initialHeight: 915.0,
        initialDevicePixelRatio: 2.625,
      );

      final session = FlightSession(
        manifest: manifest,
        events: [
          const CustomBreadcrumbFlightEvent(timestampMs: 50, name: 'Secret Action'),
        ],
      );

      final tempFile = File('${Directory.systemTemp.path}/test_secure_session.eflightlog');
      await secureSerializer.writeEncryptedToFile(session, tempFile.path);

      expect(await tempFile.exists(), isTrue);

      // Read back with auto-detection
      final restored = await SecureFlightSerializer.readAutoDetect(tempFile.path, crypto: crypto);
      expect(restored.manifest.sessionId, 'encrypted_session_42');
      expect(restored.events.first.toJson()['name'], 'Secret Action');

      await tempFile.delete();
    });
  });

  group('Issue 7: WebSocket Replay Harness', () {
    test('FlightWebSocketReplayServer manages fixtures', () {
      const fixture = WebSocketReplayFixture(
        urlPattern: 'wss://api.example.com/feed',
        serverMessages: ['{"type": "price_update", "price": 105.2}'],
      );

      final server = FlightWebSocketReplayServer(fixtures: [fixture]);
      server.install();
      expect(FlightWebSocketReplayServer.current, isNotNull);
      server.uninstall();
      expect(FlightWebSocketReplayServer.current, isNull);
    });
  });

  group('Deep Navigation & Route Stack Snapshot', () {
    test('RouteStackSnapshotEvent serializes and restores deep routes', () {
      const snapshot = RouteStackSnapshotEvent(
        timestampMs: 10,
        routeStack: ['/', '/home', '/settings', '/security', '/change-password'],
      );

      final json = snapshot.toJson();
      final restored = RouteStackSnapshotEvent.fromJson(json);

      expect(restored.stack.length, 5);
      expect(restored.stack.last, '/change-password');
    });
  });
}
