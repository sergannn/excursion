// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:booking_app/src/app.dart';

void main() {
  testWidgets('Login screen is shown by default', (WidgetTester tester) async {
    await BookingAppBootstrap.ensureInitialized();
    await tester.pumpWidget(const BookingApp());
    await tester.pumpAndSettle();

    expect(find.text('Вход в систему'), findsOneWidget);
  });
}
