// lib/src/synthesis/test_harness_builder.dart
//
// Generates a `test/flight_harness.dart` file tailored to the developer's
// dependency-injection framework.
//
// Supported frameworks:
//   • Riverpod  (flutter_riverpod / riverpod)
//   • GetIt     (get_it / injectable)
//   • Bloc      (flutter_bloc / bloc)
//   • Provider  (provider)
//   • None      (bare WidgetTester, no DI wrapper)
//
// Generated harness capabilities:
//   1. Installs a [FlightReplayServer] for every detected HTTP host.
//   2. Stubs every detected platform channel with setMockMethodCallHandler.
//   3. Provides setUpAll / tearDownAll scaffolding.
//   4. Provides a `pumpApp(WidgetTester tester)` convenience helper.
//
// All output is returned as a Dart source string; nothing is written to disk
// by this class — that is the caller's responsibility (e.g. write to
// `test/flight_harness.dart`).

// ignore_for_file: constant_identifier_names

/// The DI framework in use in the host application.
enum DiFramework {
  /// `flutter_riverpod` / `riverpod`.
  riverpod,

  /// `get_it` / `injectable`.
  getIt,

  /// `flutter_bloc` / `bloc`.
  bloc,

  /// `provider`.
  provider,

  /// No recognised DI framework; plain widget pump.
  none,
}

// ---------------------------------------------------------------------------
// TestHarnessBuilder
// ---------------------------------------------------------------------------

/// Generates Flutter integration-test harness source files that replay
/// recorded HTTP traffic and platform-channel calls captured by
/// `flight_recorder`.
abstract final class TestHarnessBuilder {
  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Generates a complete `test/flight_harness.dart` file as a Dart source
  /// string.
  ///
  /// Parameters
  /// ----------
  /// [framework]              – DI framework to scaffold around.
  /// [appWidgetConstructor]   – The Dart expression used to construct the root
  ///                            app widget, e.g. `'const MyApp()'`.
  /// [detectedChannels]       – Platform channel names recorded during a
  ///                            session (from `PlatformChannelFlightEvents`).
  /// [detectedHttpHosts]      – HTTP host names recorded during a session
  ///                            (from `HttpFlightEvents`), e.g.
  ///                            `['api.example.com', 'cdn.example.com']`.
  static String generateHarness({
    required DiFramework framework,
    required String appWidgetConstructor,
    required List<String> detectedChannels,
    required List<String> detectedHttpHosts,
  }) {
    final _HarnessWriter writer = _HarnessWriter(
      framework: framework,
      appWidgetConstructor: appWidgetConstructor,
      channels: List.unmodifiable(detectedChannels),
      hosts: List.unmodifiable(detectedHttpHosts),
    );
    return writer.build();
  }

  /// Tries to detect which DI framework is in use by scanning [pubspecContent]
  /// for well-known package names in the `dependencies` or
  /// `dev_dependencies` blocks.
  ///
  /// The heuristic is intentionally simple: it looks for the package name as
  /// a word inside the YAML text.  This avoids pulling in a full YAML parser.
  static DiFramework detectFramework(String pubspecContent) {
    // Ordered by specificity – riverpod before provider so we don't
    // misidentify a riverpod project as a bare-provider one.
    const Map<DiFramework, List<String>> markers = {
      DiFramework.riverpod: ['flutter_riverpod', 'riverpod', 'hooks_riverpod'],
      DiFramework.getIt: ['get_it', 'injectable'],
      DiFramework.bloc: ['flutter_bloc', 'bloc'],
      DiFramework.provider: ['provider'],
    };

    for (final entry in markers.entries) {
      for (final keyword in entry.value) {
        // Match the package name followed by a colon (YAML key) or as a
        // standalone word to avoid partial matches.
        final RegExp pattern =
            RegExp(r'\b' + RegExp.escape(keyword) + r'\b');
        if (pattern.hasMatch(pubspecContent)) {
          return entry.key;
        }
      }
    }
    return DiFramework.none;
  }

  /// Returns the import lines required at the top of the generated harness.
  static List<String> harnessImports(DiFramework framework) {
    return _frameworkImports(framework);
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static List<String> _frameworkImports(DiFramework framework) {
    final List<String> base = [
      "import 'package:flutter/material.dart';",
      "import 'package:flutter_test/flutter_test.dart';",
      "import 'package:flight_recorder/flight_recorder.dart';",
    ];

    switch (framework) {
      case DiFramework.riverpod:
        base.add(
            "import 'package:flutter_riverpod/flutter_riverpod.dart';");
      case DiFramework.getIt:
        base.add("import 'package:get_it/get_it.dart';");
      case DiFramework.bloc:
        base.add("import 'package:flutter_bloc/flutter_bloc.dart';");
      case DiFramework.provider:
        base.add("import 'package:provider/provider.dart';");
      case DiFramework.none:
        break;
    }

    return base;
  }
}

// ---------------------------------------------------------------------------
// _HarnessWriter  (internal)
// ---------------------------------------------------------------------------

/// Internal builder that assembles the generated harness source string.
final class _HarnessWriter {
  final DiFramework framework;
  final String appWidgetConstructor;
  final List<String> channels;
  final List<String> hosts;

  const _HarnessWriter({
    required this.framework,
    required this.appWidgetConstructor,
    required this.channels,
    required this.hosts,
  });

  // -------------------------------------------------------------------------
  // Top-level build method
  // -------------------------------------------------------------------------

  String build() {
    final StringBuffer buf = StringBuffer();

    _writeFileHeader(buf);
    _writeImports(buf);
    buf.writeln();
    _writeFixtures(buf);
    buf.writeln();
    _writeChannelStubs(buf);
    buf.writeln();
    _writeSetUpTearDown(buf);
    buf.writeln();
    _writePumpApp(buf);

    return buf.toString();
  }

  // -------------------------------------------------------------------------
  // Sections
  // -------------------------------------------------------------------------

  void _writeFileHeader(StringBuffer buf) {
    buf.writeln(
        '// AUTO-GENERATED BY FLIGHT RECORDER — EDIT AS NEEDED');
    buf.writeln('// Generated at: ${DateTime.now().toUtc().toIso8601String()}');
    buf.writeln('// DI framework: ${framework.name}');
    buf.writeln('// Detected HTTP hosts: ${hosts.isEmpty ? 'none' : hosts.join(', ')}');
    buf.writeln(
        '// Detected platform channels: ${channels.isEmpty ? 'none' : channels.join(', ')}');
    buf.writeln('//');
    buf.writeln('// ignore_for_file: type=lint, unused_element');
    buf.writeln();

    if (framework == DiFramework.getIt) {
      // GetIt overrides require `// @dart=2.12` compatibility note
      buf.writeln('// ignore_for_file: implementation_imports');
      buf.writeln();
    }
  }

  void _writeImports(StringBuffer buf) {
    for (final String imp
        in TestHarnessBuilder._frameworkImports(framework)) {
      buf.writeln(imp);
    }
  }

  /// Emits the `_fixtures` list from recorded HTTP hosts.
  void _writeFixtures(StringBuffer buf) {
    buf.writeln('// ─── Recorded HTTP fixtures ──────────────────────────────');
    if (hosts.isEmpty) {
      buf.writeln('// No HTTP hosts were recorded in this session.');
      buf.writeln('const List<ReplayFixture> _fixtures = [];');
      return;
    }

    buf.writeln('//');
    buf.writeln('// Each ReplayFixture below corresponds to a recorded host.');
    buf.writeln('// Replace the placeholder responses with real recordings');
    buf.writeln('// exported from the FlightRecorder dashboard.');
    buf.writeln('//');
    buf.writeln('final List<ReplayFixture> _fixtures = [');
    for (final String host in hosts) {
      buf.writeln('  // Fixtures for host: $host');
      buf.writeln('  // TODO: populate from exported .flightlog recordings.');
      buf.writeln('  ReplayFixture(');
      buf.writeln("    method: 'GET',");
      buf.writeln("    urlPattern: 'https://$host',");
      buf.writeln("    statusCode: 200,");
      buf.writeln("    responseBody: '{}',");
      buf.writeln('  ),');
    }
    buf.writeln('];');
  }

  /// Emits the `_setupChannelStubs()` function.
  void _writeChannelStubs(StringBuffer buf) {
    buf.writeln('// ─── Platform channel stubs ───────────────────────────────');
    buf.writeln('void _setupChannelStubs() {');

    if (channels.isEmpty) {
      buf.writeln(
          '  // No platform channels were recorded in this session.');
    } else {
      for (final String ch in channels) {
        final String handlerBody = _defaultChannelHandler(ch);
        buf.writeln(
            '  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger');
        buf.writeln('      .setMockMethodCallHandler(');
        buf.writeln("        const MethodChannel('$ch'),");
        buf.writeln('        (MethodCall call) async {');
        buf.writeln('          // Channel: $ch');
        for (final String line in handlerBody.split('\n')) {
          buf.writeln('          $line');
        }
        buf.writeln('        },');
        buf.writeln('      );');
        buf.writeln();
      }
    }

    buf.writeln('}');
  }

  /// Emits `setUpAll` / `tearDownAll` with [FlightReplayServer] lifecycle.
  void _writeSetUpTearDown(StringBuffer buf) {
    buf.writeln('// ─── Test lifecycle ───────────────────────────────────────');
    buf.writeln('late FlightReplayServer _replayServer;');
    buf.writeln();
    buf.writeln('void flightSetUpAll() {');
    buf.writeln('  setUpAll(() {');
    buf.writeln(
        '    _replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('    _replayServer.install();');
    buf.writeln('    _setupChannelStubs();');
    buf.writeln('  });');
    buf.writeln();
    buf.writeln('  tearDownAll(() {');
    buf.writeln('    _replayServer.uninstall();');
    buf.writeln('  });');
    buf.writeln('}');
  }

  /// Emits the `pumpApp` convenience helper, adapted to the DI framework.
  void _writePumpApp(StringBuffer buf) {
    buf.writeln('// ─── Widget pump helper ───────────────────────────────────');

    switch (framework) {
      case DiFramework.riverpod:
        _writePumpAppRiverpod(buf);
      case DiFramework.getIt:
        _writePumpAppGetIt(buf);
      case DiFramework.bloc:
        _writePumpAppBloc(buf);
      case DiFramework.provider:
        _writePumpAppProvider(buf);
      case DiFramework.none:
        _writePumpAppNone(buf);
    }
  }

  // ── DI-specific pumpApp implementations ───────────────────────────────────

  void _writePumpAppRiverpod(StringBuffer buf) {
    buf.writeln(
        '/// Pumps [$appWidgetConstructor] inside a [ProviderScope].');
    buf.writeln('///');
    buf.writeln(
        '/// Supply [overrides] to inject test-specific provider values.');
    buf.writeln('Future<void> pumpApp(');
    buf.writeln('  WidgetTester tester, {');
    buf.writeln('  List<Override> overrides = const [],');
    buf.writeln('}) async {');
    buf.writeln(
        '  final replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('  replayServer.install();');
    buf.writeln('  addTearDown(replayServer.uninstall);');
    buf.writeln('  _setupChannelStubs();');
    buf.writeln('  await tester.pumpWidget(');
    buf.writeln('    ProviderScope(');
    buf.writeln('      overrides: overrides,');
    buf.writeln('      child: $appWidgetConstructor,');
    buf.writeln('    ),');
    buf.writeln('  );');
    buf.writeln('  await tester.pumpAndSettle();');
    buf.writeln('}');
  }

  void _writePumpAppGetIt(StringBuffer buf) {
    buf.writeln(
        '/// Pumps [$appWidgetConstructor] after re-initialising GetIt.');
    buf.writeln('///');
    buf.writeln(
        '/// [configure] allows overriding registrations for the test.');
    buf.writeln('Future<void> pumpApp(');
    buf.writeln('  WidgetTester tester, {');
    buf.writeln(
        '  void Function(GetIt getIt)? configure,');
    buf.writeln('}) async {');
    buf.writeln(
        '  final replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('  replayServer.install();');
    buf.writeln('  addTearDown(replayServer.uninstall);');
    buf.writeln('  _setupChannelStubs();');
    buf.writeln();
    buf.writeln('  final GetIt sl = GetIt.instance;');
    buf.writeln('  await sl.reset();');
    buf.writeln('  // TODO: call your DI setup function here, e.g.:');
    buf.writeln('  // setupLocator();');
    buf.writeln('  configure?.call(sl);');
    buf.writeln();
    buf.writeln('  await tester.pumpWidget($appWidgetConstructor);');
    buf.writeln('  await tester.pumpAndSettle();');
    buf.writeln('}');
  }

  void _writePumpAppBloc(StringBuffer buf) {
    buf.writeln(
        '/// Pumps [$appWidgetConstructor] with optional BLoC [providers].');
    buf.writeln('Future<void> pumpApp(');
    buf.writeln('  WidgetTester tester, {');
    buf.writeln('  List<BlocProvider> providers = const [],');
    buf.writeln('}) async {');
    buf.writeln(
        '  final replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('  replayServer.install();');
    buf.writeln('  addTearDown(replayServer.uninstall);');
    buf.writeln('  _setupChannelStubs();');
    buf.writeln();
    buf.writeln('  final Widget child = providers.isEmpty');
    buf.writeln('      ? $appWidgetConstructor');
    buf.writeln('      : MultiBlocProvider(');
    buf.writeln('          providers: providers,');
    buf.writeln('          child: $appWidgetConstructor,');
    buf.writeln('        );');
    buf.writeln();
    buf.writeln('  await tester.pumpWidget(child);');
    buf.writeln('  await tester.pumpAndSettle();');
    buf.writeln('}');
  }

  void _writePumpAppProvider(StringBuffer buf) {
    buf.writeln(
        '/// Pumps [$appWidgetConstructor] with optional ChangeNotifier [providers].');
    buf.writeln('Future<void> pumpApp(');
    buf.writeln('  WidgetTester tester, {');
    buf.writeln('  List<SingleChildWidget> providers = const [],');
    buf.writeln('}) async {');
    buf.writeln(
        '  final replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('  replayServer.install();');
    buf.writeln('  addTearDown(replayServer.uninstall);');
    buf.writeln('  _setupChannelStubs();');
    buf.writeln();
    buf.writeln('  final Widget child = providers.isEmpty');
    buf.writeln('      ? $appWidgetConstructor');
    buf.writeln('      : MultiProvider(');
    buf.writeln('          providers: providers,');
    buf.writeln('          child: $appWidgetConstructor,');
    buf.writeln('        );');
    buf.writeln();
    buf.writeln('  await tester.pumpWidget(child);');
    buf.writeln('  await tester.pumpAndSettle();');
    buf.writeln('}');
  }

  void _writePumpAppNone(StringBuffer buf) {
    buf.writeln(
        '/// Pumps [$appWidgetConstructor] with no DI wrapper.');
    buf.writeln('Future<void> pumpApp(WidgetTester tester) async {');
    buf.writeln(
        '  final replayServer = FlightReplayServer(fixtures: _fixtures);');
    buf.writeln('  replayServer.install();');
    buf.writeln('  addTearDown(replayServer.uninstall);');
    buf.writeln('  _setupChannelStubs();');
    buf.writeln('  await tester.pumpWidget($appWidgetConstructor);');
    buf.writeln('  await tester.pumpAndSettle();');
    buf.writeln('}');
  }

  // ── Channel handler heuristics ────────────────────────────────────────────

  /// Returns a default stub handler body (the lines inside the `async {…}`)
  /// for well-known channel names.
  static String _defaultChannelHandler(String channel) {
    // Exact-match for the most common plugins
    const Map<String, String> knownHandlers = {
      'plugins.flutter.io/shared_preferences':
          "return <String, Object>{};",
      'plugins.flutter.io/shared_preferences_android':
          "return <String, Object>{};",
      'plugins.flutter.io/shared_preferences_foundation':
          "return <String, Object>{};",
      'flutter_secure_storage':
          "return switch (call.method) {\n"
          "  'read' => null,\n"
          "  'readAll' => <String, String>{},\n"
          "  'containsKey' => false,\n"
          "  _ => null,\n"
          "};",
      'plugins.flutter.io/path_provider':
          "return '/tmp/flight_test';",
      'plugins.flutter.io/path_provider_foundation':
          "return '/tmp/flight_test';",
      'plugins.flutter.io/connectivity':
          "return 'wifi';",
      'dev.fluttercommunity.plus/connectivity':
          "return 'wifi';",
      'com.baseflow.permissionhandler/permissions':
          "return <int, int>{};",
      'plugins.flutter.io/firebase_messaging':
          "return null;",
      'com.google.firebase.cloud_firestore':
          "return null;",
    };

    if (knownHandlers.containsKey(channel)) {
      return knownHandlers[channel]!;
    }

    // Fallback: return null for unrecognised channels
    return "// TODO: implement stub for '$channel'\n"
        "return null;";
  }
}
