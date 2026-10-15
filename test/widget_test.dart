import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_track/core/widgets/app_button.dart';

void main() {
  testWidgets('AppButton renders text and triggers callback', (
    WidgetTester tester,
  ) async {
    bool pressed = false;

    // Build the widget
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppButton(
            text: 'Submit Order',
            onPressed: () {
              pressed = true;
            },
          ),
        ),
      ),
    );

    // Verify button text is present
    expect(find.text('Submit Order'), findsOneWidget);
    expect(pressed, isFalse);

    // Tap the button
    await tester.tap(find.text('Submit Order'));
    await tester.pump();

    // Verify callback was triggered
    expect(pressed, isTrue);
  });

  testWidgets('AppButton shows loader when isLoading is true', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppButton(text: 'Loading Item', isLoading: true)),
      ),
    );

    // Verify loader is visible, text is not (since loader replaces text child structure or wraps it)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
