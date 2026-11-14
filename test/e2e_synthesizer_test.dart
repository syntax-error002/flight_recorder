import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_flight_recorder/flutter_flight_recorder.dart';

void main() {
  test('Synthesizes valid Dart test file from session', () async {
    final manifest = SessionManifest(
      sessionId: 'e2e_session_1',
      startedAt: DateTime.utc(2026, 11, 14, 18, 0, 0),
      platform: 'windows',
      initialWidth: 400.0,
      initialHeight: 800.0,
      initialDevicePixelRatio: 1.0,
    );

    final events = <FlightEvent>[
      const HttpFlightEvent(
        timestampMs: 50,
        method: 'GET',
        url: 'https://api.flightrecorder.dev/status',
        statusCode: 200,
        durationMs: 30,
        responseBody: '{"status": "flight_ready"}',
      ),
      const PointerFlightEvent(
        timestampMs: 120,
        action: 'down',
        dx: 200.0,
        dy: 400.0,
      ),
      const PointerFlightEvent(
        timestampMs: 180,
        action: 'up',
        dx: 200.0,
        dy: 400.0,
      ),
      const CustomBreadcrumbFlightEvent(
        timestampMs: 220,
        name: 'Check Completed',
        category: 'e2e',
      ),
    ];

    final session = FlightSession(manifest: manifest, events: events);

    final generatedCode = FlightSynthesizer.synthesize(
      session: session,
      testDescription: 'E2E Generated Reproduction Test',
      appWidgetConstructor: '''
Directionality(
  textDirection: TextDirection.ltr,
  child: Material(
    child: Center(
      child: ElevatedButton(
        onPressed: () {},
        child: const Text('Target Button'),
      ),
    ),
  ),
)
''',
    );

    final generatedFile = File('test/generated_e2e_repro_test.dart');
    generatedFile.writeAsStringSync(generatedCode, flush: true);

    expect(generatedFile.existsSync(), isTrue);
    expect(generatedFile.lengthSync() > 100, isTrue);

    // Save sample flightlog for CLI and developer manual testing
    final fixtureFile = File('test/fixtures/sample.flightlog');
    await fixtureFile.parent.create(recursive: true);
    await FlightSerializer.writeToFile(session, fixtureFile.path);
    expect(fixtureFile.existsSync(), isTrue);
  });
}
