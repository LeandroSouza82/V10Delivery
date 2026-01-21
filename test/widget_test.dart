// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:v10_delivery/main.dart';

void main() {
  testWidgets('Smoke test - app loads and shows welcome', (WidgetTester tester) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const V10DeliveryApp());

    // Verify that the welcome text with the driver's name is present.
    expect(find.textContaining('Benvindo'), findsOneWidget);
    expect(find.text('Benvindo, LEANDRO'), findsOneWidget);
  });
}
