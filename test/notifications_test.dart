import 'package:flutter_test/flutter_test.dart';
import 'package:grocery_track/core/notifications/notification_constants.dart';
import 'package:grocery_track/core/notifications/notification_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationConstants Tests', () {
    test('verifies channel ID and notification types', () {
      expect(NotificationConstants.channelId, 'grocery_notifications');
      expect(NotificationConstants.channelName, 'Grocery Notifications');
      expect(NotificationConstants.typeExpiryReminder, 'expiry_reminder');
      expect(NotificationConstants.typeLowStock, 'low_stock');
      expect(NotificationConstants.typeShoppingReminder, 'shopping_reminder');
      expect(NotificationConstants.typeSharedList, 'shared_list');
      expect(NotificationConstants.typeGroceryUpdated, 'grocery_updated');
      expect(NotificationConstants.typeGeneral, 'general');
    });
  });

  group('NotificationRouter Tests', () {
    test(
      'handles empty or null notification payload gracefully without crashing',
      () {
        expect(
          () => NotificationRouter.handleNotificationTap(null),
          returnsNormally,
        );
        expect(
          () => NotificationRouter.handleNotificationTap({}),
          returnsNormally,
        );
      },
    );

    test('queues pending notification when navigator is not mounted', () {
      final payload = {
        'type': NotificationConstants.typeExpiryReminder,
        'grocery_id': 'item_123',
      };
      // Navigator state is null in this headless unit test environment
      NotificationRouter.handleNotificationTap(payload);
      // Ensure processing pending doesn't throw
      expect(
        () => NotificationRouter.processPendingNotification(),
        returnsNormally,
      );
    });

    test('parses shopping reminder payload safely', () {
      final payload = {
        'type': NotificationConstants.typeShoppingReminder,
        'list_id': 'list_999',
      };
      expect(
        () => NotificationRouter.handleNotificationTap(payload),
        returnsNormally,
      );
    });

    test('parses low stock payload safely', () {
      final payload = {
        'type': NotificationConstants.typeLowStock,
        'grocery_id': 'item_456',
      };
      expect(
        () => NotificationRouter.handleNotificationTap(payload),
        returnsNormally,
      );
    });

    test('parses shared list payload safely', () {
      final payload = {
        'type': NotificationConstants.typeSharedList,
        'list_id': 'list_shared_1',
      };
      expect(
        () => NotificationRouter.handleNotificationTap(payload),
        returnsNormally,
      );
    });
  });
}
