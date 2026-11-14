import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('FlightRecorderDemoApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const FlightRecorderDemoApp());
    expect(find.text('Flight Shop'), findsOneWidget);
    expect(find.text('Flight Recorder Active'), findsOneWidget);
  });
}
