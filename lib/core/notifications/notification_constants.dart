class NotificationConstants {
  // Android Channel Configuration
  static const String channelId = 'grocery_notifications';
  static const String channelName = 'Grocery Notifications';
  static const String channelDescription = 'Notifications for grocery expiry, reminders, and updates';

  // Notification Types
  static const String typeExpiryReminder = 'expiry_reminder';
  static const String typeLowStock = 'low_stock';
  static const String typeShoppingReminder = 'shopping_reminder';
  static const String typeSharedList = 'shared_list';
  static const String typeGroceryUpdated = 'grocery_updated';
  static const String typeGeneral = 'general';

  // Local storage keys
  static const String prefsDeviceIdKey = 'fresh_track_device_id';
  static const String prefsLastFcmTokenKey = 'fresh_track_last_fcm_token';
}
