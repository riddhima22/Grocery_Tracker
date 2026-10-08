import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_track/core/widgets/confirm_dialog.dart';
import 'package:grocery_track/config/app_theme.dart';

void main() {
  group('Delete Confirmation Dialog Tests', () {
    testWidgets('shows confirmation dialog with title, message, and Cancel/Delete buttons', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConfirmDialog.show(
                    context: context,
                    title: 'Delete Confirmation',
                    content: 'Are you sure you want to delete this item? This action cannot be undone.',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Tap button to show dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify Title and Content
      expect(find.text('Delete Confirmation'), findsOneWidget);
      expect(
        find.text('Are you sure you want to delete this item? This action cannot be undone.'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Verify dialog dismissed and result is false
      expect(find.text('Delete Confirmation'), findsNothing);
      expect(result, isFalse);
    });

    testWidgets('returns true only when user confirms by tapping Delete', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await ConfirmDialog.show(
                    context: context,
                    title: 'Delete Confirmation',
                    content: 'Are you sure you want to delete this item? This action cannot be undone.',
                    confirmLabel: 'Delete',
                    cancelLabel: 'Cancel',
                    isDestructive: true,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap Delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Verify dialog dismissed and result is true
      expect(find.text('Delete Confirmation'), findsNothing);
      expect(result, isTrue);
    });
  });
}
