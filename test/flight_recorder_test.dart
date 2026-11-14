import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flight_blackbox/flight_blackbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EventRingBuffer Tests', () {
    test('Capacity and FIFO wraparound work with zero allocations', () {
      final buffer = EventRingBuffer<int>(3);
      expect(buffer.isEmpty, isTrue);
      expect(buffer.isFull, isFalse);

      buffer.add(1);
      buffer.add(2);
      expect(buffer.length, 2);
      expect(buffer.toList(), [1, 2]);

      buffer.add(3);
      expect(buffer.isFull, isTrue);
      expect(buffer.toList(), [1, 2, 3]);

      // Overwrite oldest (1 is dropped, 4 is added)
      buffer.add(4);
      expect(buffer.length, 3);
      expect(buffer.toList(), [2, 3, 4]);

      // Overwrite another (2 is dropped, 5 is added)
      buffer.add(5);
      expect(buffer.toList(), [3, 4, 5]);

      // Clear
      buffer.clear();
      expect(buffer.isEmpty, isTrue);
      expect(buffer.length, 0);
    });

    test('Ring buffer iterator handles empty and full buffers', () {
      final buffer = EventRingBuffer<String>(2);
      buffer.addAll(['a', 'b']);
      final results = <String>[];
      for (final item in buffer) {
        results.add(item);
      }
      expect(results, ['a', 'b']);
    });
  });

  group('RedactionEngine Tests', () {
    final engine = RedactionEngine();

    test('Redacts emails and credit cards from strings', () {
      final text = 'Contact user at john.doe@example.com with card 4111 2222 3333 4444';
      final sanitized = engine.sanitizeString(text);
      expect(sanitized.contains('john.doe@example.com'), isFalse);
      expect(sanitized.contains('[EMAIL_REDACTED]'), isTrue);
      expect(sanitized.contains('4111 2222 3333 4444'), isFalse);
      expect(sanitized.contains('[CARD_REDACTED]'), isTrue);
    });

    test('Redacts authorization and cookie headers', () {
      final headers = {
        'Authorization': 'Bearer eyJhbGciOi...',
        'Cookie': 'sessionId=abc123xyz',
        'Content-Type': 'application/json',
      };
      final sanitized = engine.sanitizeHeaders(headers);
      expect(sanitized['Authorization'], '[REDACTED]');
      expect(sanitized['Cookie'], '[REDACTED]');
      expect(sanitized['Content-Type'], 'application/json');
    });

    test('Redacts sensitive keys in JSON payloads recursively', () {
      final payload = jsonEncode({
        'user': 'alex',
        'password': 'SuperSecretPassword!123',
        'auth': {
          'access_token': 'secret_token_value',
          'profile': {'email': 'test@corp.com'},
        },
      });

      final sanitized = engine.sanitizeJsonPayload(payload)!;
      final decoded = jsonDecode(sanitized) as Map<String, dynamic>;

      expect(decoded['password'], '[REDACTED]');
      expect((decoded['auth'] as Map)['access_token'], '[REDACTED]');
      expect(
        ((decoded['auth'] as Map)['profile'] as Map)['email'],
        '[EMAIL_REDACTED]',
      );
      expect(decoded['user'], 'alex');
    });
  });

  group('Serialization and Compression Tests', () {
    test('Serializes and deserializes FlightSession with GZIP compression', () async {
      final manifest = SessionManifest(
        sessionId: 'test_session_1',
        startedAt: DateTime.utc(2026, 11, 14, 12, 0, 0),
        platform: 'windows',
        initialWidth: 412.0,
        initialHeight: 915.0,
        initialDevicePixelRatio: 2.625,
      );

      final events = <FlightEvent>[
        const PointerFlightEvent(
          timestampMs: 150,
          action: 'down',
          dx: 100.5,
          dy: 200.0,
        ),
        const PointerFlightEvent(
          timestampMs: 200,
          action: 'up',
          dx: 100.5,
          dy: 200.0,
        ),
        const NavigationFlightEvent(
          timestampMs: 250,
          action: 'push',
          routeName: '/checkout',
        ),
        const HttpFlightEvent(
          timestampMs: 300,
          method: 'GET',
          url: 'https://api.example.com/items',
          statusCode: 200,
          durationMs: 45,
          responseBody: '{"items": [1, 2, 3]}',
        ),
        const CrashFlightEvent(
          timestampMs: 800,
          exception: 'StateError: Invalid checkout state',
          stackTrace: 'trace...',
        ),
      ];

      final session = FlightSession(manifest: manifest, events: events);

      // Binary compressed format
      final compressedBytes = FlightSerializer.toCompressedBytes(session);
      expect(compressedBytes.isNotEmpty, isTrue);

      final restoredSession = FlightSerializer.fromBytes(compressedBytes);
      expect(restoredSession.manifest.sessionId, 'test_session_1');
      expect(restoredSession.events.length, 5);

      final pDown = restoredSession.events[0] as PointerFlightEvent;
      expect(pDown.action, 'down');
      expect(pDown.dx, 100.5);

      final nav = restoredSession.events[2] as NavigationFlightEvent;
      expect(nav.routeName, '/checkout');

      final http = restoredSession.events[3] as HttpFlightEvent;
      expect(http.method, 'GET');
      expect(http.statusCode, 200);

      final crash = restoredSession.events[4] as CrashFlightEvent;
      expect(crash.exception, 'StateError: Invalid checkout state');
    });
  });

  group('FlightSynthesizer TestWidgets Code Generation', () {
    test('Synthesizes valid, runnable testWidgets Dart code', () {
      final manifest = SessionManifest(
        sessionId: 'crash_session_99',
        startedAt: DateTime.utc(2026, 11, 14, 15, 30),
        platform: 'android',
        initialWidth: 400.0,
        initialHeight: 800.0,
        initialDevicePixelRatio: 2.0,
      );

      final events = <FlightEvent>[
        const HttpFlightEvent(
          timestampMs: 50,
          method: 'POST',
          url: 'https://api.myapp.com/login',
          statusCode: 200,
          durationMs: 80,
          responseBody: '{"token": "auth_ok"}',
        ),
        const PointerFlightEvent(
          timestampMs: 120,
          action: 'down',
          dx: 150.0,
          dy: 300.0,
        ),
        const PointerFlightEvent(
          timestampMs: 180,
          action: 'up',
          dx: 150.0,
          dy: 300.0,
        ),
        const CrashFlightEvent(
          timestampMs: 250,
          exception: 'NullPointerException at login_screen.dart:42',
          stackTrace: 'stack...',
        ),
      ];

      final session = FlightSession(manifest: manifest, events: events);
      final code = FlightSynthesizer.synthesize(
        session: session,
        testDescription: 'Reproduce Login Crash',
        appWidgetConstructor: 'const Placeholder()',
      );

      expect(code.contains("testWidgets('Reproduce Login Crash'"), isTrue);
      expect(code.contains('FlightReplayServer'), isTrue);
      expect(code.contains('tester.tapAt(const Offset(150.0, 300.0))'), isTrue);
      expect(code.contains('tester.view.physicalSize = const Size(800.0, 1600.0)'), isTrue);
      expect(code.contains('NullPointerException at login_screen.dart:42'), isTrue);
    });
  });

  group('FlightReplayServer Deterministic HTTP Replay', () {
    test('Intercepts and returns recorded fixtures', () async {
      final fixtures = [
        const ReplayFixture(
          method: 'GET',
          urlPattern: 'https://myapi.com/user/profile',
          statusCode: 200,
          responseBody: '{"name": "Alice"}',
        ),
      ];

      final replayServer = FlightReplayServer(fixtures: fixtures);
      replayServer.install();

      try {
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse('https://myapi.com/user/profile'));
        final response = await request.close();
        final body = await utf8.decodeStream(response);

        expect(response.statusCode, 200);
        expect(body, '{"name": "Alice"}');
        client.close();
      } finally {
        replayServer.uninstall();
      }
    });
  });

  group('FlightRecorder Controller & Interceptors Integration', () {
    testWidgets('Records pointer events and breadcrumbs during widget interactions', (tester) async {
      final recorder = FlightRecorder.instance;
      recorder.start(config: FlightConfig(bufferCapacity: 50));

      try {
        recorder.addBreadcrumb('App Launched', category: 'lifecycle');

        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  recorder.addBreadcrumb('Button Tapped');
                },
                child: const Text('Tap Me'),
              ),
            ),
          ),
        );

        // Tap the button using tester
        await tester.tap(find.text('Tap Me'));
        await tester.pump();

        final events = recorder.getRecentEvents();
        expect(events.isNotEmpty, isTrue);

        final breadcrumbEvents = events.whereType<CustomBreadcrumbFlightEvent>().toList();
        expect(breadcrumbEvents.any((b) => b.name == 'App Launched'), isTrue);
        expect(breadcrumbEvents.any((b) => b.name == 'Button Tapped'), isTrue);

        final pointerEvents = events.whereType<PointerFlightEvent>().toList();
        expect(pointerEvents.isNotEmpty, isTrue);
        expect(pointerEvents.any((p) => p.action == 'down'), isTrue);
        expect(pointerEvents.any((p) => p.action == 'up'), isTrue);
      } finally {
        recorder.stop();
      }
    });
  });
}
