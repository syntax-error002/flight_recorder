import 'dart:io';
import 'package:args/args.dart';
import 'package:flight_recorder/flight_recorder_core.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'input',
      abbr: 'i',
      help: 'Path to the .flightlog or .eflightlog recording file',
      mandatory: true,
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Path where the generated Dart test file will be written',
      defaultsTo: 'test/repro_test.dart',
    )
    ..addOption(
      'widget',
      abbr: 'w',
      help: 'Constructor for the root widget to pump in the test',
      defaultsTo: 'const Placeholder()',
    )
    ..addOption(
      'description',
      abbr: 'd',
      help: 'Description title for the testWidgets block',
      defaultsTo: 'Reproduced Flight Session Test',
    )
    ..addOption(
      'key',
      abbr: 'k',
      help: 'Decryption passphrase for encrypted .eflightlog files',
    )
    ..addOption(
      'harness',
      abbr: 'H',
      help: 'Generate a DI test harness scaffold (provider, riverpod, bloc, get_it)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Display usage help',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      stdout.writeln('Flight Recorder Test Synthesizer');
      stdout.writeln(parser.usage);
      exit(0);
    }

    final inputPath = results['input'] as String;
    final outputPath = results['output'] as String;
    final widgetConstructor = results['widget'] as String;
    final description = results['description'] as String;
    final key = results['key'] as String?;
    final harness = results['harness'] as String?;

    final inputFile = File(inputPath);
    if (!await inputFile.exists()) {
      stderr.writeln('Error: Input file does not exist: $inputPath');
      exit(1);
    }

    stdout.writeln('Reading flightlog: $inputPath...');
    final FlightSession session;
    final inputBytes = await inputFile.readAsBytes();
    if (SecureFlightSerializer.hasEflightMagic(inputBytes)) {
      if (key == null || key.isEmpty) {
        stderr.writeln(
            'Error: File is encrypted (.eflightlog). Please supply --key <passphrase>.');
        exit(1);
      }
      final crypto = CryptoEngine.withPassphrase(key);
      session = await SecureFlightSerializer(crypto: crypto)
          .readEncryptedFromFile(inputPath);
    } else {
      session = await FlightSerializer.readFromFile(inputPath);
    }

    stdout.writeln(
      'Session Loaded: ${session.manifest.sessionId} (${session.events.length} events)',
    );

    stdout.writeln('Synthesizing Dart testWidgets code...');
    final testCode = FlightSynthesizer.synthesize(
      session: session,
      testDescription: description,
      appWidgetConstructor: widgetConstructor,
    );

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    await outputFile.writeAsString(testCode, flush: true);

    stdout.writeln('SUCCESS! Generated test written to: $outputPath');

    if (harness != null) {
      DiFramework framework = DiFramework.none;
      final lower = harness.toLowerCase();
      if (lower == 'riverpod') {
        framework = DiFramework.riverpod;
      } else if (lower == 'bloc') {
        framework = DiFramework.bloc;
      } else if (lower == 'get_it' || lower == 'getit') {
        framework = DiFramework.getIt;
      } else if (lower == 'provider') {
        framework = DiFramework.provider;
      } else {
        final pubspecFile = File('pubspec.yaml');
        if (await pubspecFile.exists()) {
          final content = await pubspecFile.readAsString();
          framework = TestHarnessBuilder.detectFramework(content);
        }
      }

      final detectedChannels = session.events
          .whereType<PlatformChannelFlightEvent>()
          .map((e) => e.channel)
          .toSet()
          .toList();
      final detectedHttpHosts = session.events
          .whereType<HttpFlightEvent>()
          .map((e) => Uri.tryParse(e.url)?.host ?? '')
          .where((h) => h.isNotEmpty)
          .toSet()
          .toList();

      final harnessCode = TestHarnessBuilder.generateHarness(
        framework: framework,
        appWidgetConstructor: widgetConstructor,
        detectedChannels: detectedChannels,
        detectedHttpHosts: detectedHttpHosts,
      );
      final harnessFile = File('test/flight_harness.dart');
      await harnessFile.parent.create(recursive: true);
      await harnessFile.writeAsString(harnessCode, flush: true);
      stdout.writeln(
          'SUCCESS! Test harness scaffold written to: test/flight_harness.dart');
    }

    stdout.writeln('Run locally with: flutter test $outputPath');
  } catch (e) {
    stderr.writeln('Synthesis Failed: $e');
    stdout.writeln(parser.usage);
    exit(1);
  }
}
