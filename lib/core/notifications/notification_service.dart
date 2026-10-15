import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../utils/app_logger.dart';
import 'notification_constants.dart';
import 'notification_handler.dart';
import 'notification_router.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _cachedDeviceId;

  /// Initializes push notification channels, permissions, foreground listeners,
  /// background handlers, and cold-start tap receivers.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      tz.initializeTimeZones();

      // 1. Android Notification Channel (High Importance / Heads-up)
      const AndroidNotificationChannel androidChannel =
          AndroidNotificationChannel(
            NotificationConstants.channelId,
            NotificationConstants.channelName,
            description: NotificationConstants.channelDescription,
            importance: Importance.high,
            playSound: true,
          );

      // 2. Initialize Local Notifications Plugin
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          AppLogger.info(
            'Local notification clicked with payload: ${response.payload}',
          );
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final Map<String, dynamic> data = jsonDecode(response.payload!);
              NotificationRouter.handleNotificationTap(data);
            } catch (e) {
              AppLogger.error('Failed to parse notification payload JSON', e);
            }
          }
        },
      );

      // 3. Register notification channel on Android
      final androidImplementation = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(androidChannel);
      }

      // 4. Request Permissions
      await _requestPermissions(androidImplementation);

      // 5. Register Background Message Handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // 6. Setup Foreground Message Handling
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        AppLogger.info(
          'Foreground FCM push received: ${message.notification?.title ?? message.data['title']}',
        );
        _showForegroundNotification(message);
      });

      // 7. Setup Background Notification Tap Handling (App resumed from background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        AppLogger.info(
          'Push notification clicked in background: ${message.data}',
        );
        NotificationRouter.handleNotificationTap(message.data);
      });

      // 8. Handle Terminated App Notification Tap (Cold Start)
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        AppLogger.info(
          'Terminated app launched from notification: ${initialMessage.data}',
        );
        NotificationRouter.handleNotificationTap(initialMessage.data);
      } else {
        NotificationRouter.processPendingNotification();
      }

      // 9. Manage and Sync FCM Token
      await _initFcmTokenSync();

      _initialized = true;
      AppLogger.info('NotificationService initialized successfully.');
    } catch (e, stack) {
      AppLogger.error('Failed to initialize NotificationService', e, stack);
    }
  }

  /// Request permissions on Android 13+ (POST_NOTIFICATIONS) and iOS
  Future<void> _requestPermissions(
    AndroidFlutterLocalNotificationsPlugin? androidImplementation,
  ) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final granted = await androidImplementation
            ?.requestNotificationsPermission();
        AppLogger.info('Android notification permission granted: $granted');
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final settings = await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        AppLogger.info(
          'iOS notification permission status: ${settings.authorizationStatus}',
        );
      }
    } catch (e) {
      AppLogger.warning('Notification permission request skipped/failed: $e');
    }
  }

  /// Retrieves or generates a persistent device ID for multi-device sync
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(NotificationConstants.prefsDeviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await prefs.setString(NotificationConstants.prefsDeviceIdKey, deviceId);
    }
    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Fetch token, setup refresh stream, and upload to backend
  Future<void> _initFcmTokenSync() async {
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        AppLogger.info(
          'FCM Token generated: ${token.substring(0, token.length > 15 ? 15 : token.length)}...',
        );
        await uploadFcmToken(token);
      }

      _fcm.onTokenRefresh.listen((newToken) async {
        AppLogger.info(
          'FCM Token refreshed: ${newToken.substring(0, newToken.length > 15 ? 15 : newToken.length)}...',
        );
        await uploadFcmToken(newToken);
      });
    } catch (e) {
      AppLogger.warning('FCM token retrieval skipped/failed: $e');
    }
  }

  /// Registers/updates FCM token on backend API with platform and device_id
  Future<void> uploadFcmToken(String token) async {
    try {
      final deviceId = await getDeviceId();
      final platform = defaultTargetPlatform.name.toLowerCase();

      await ApiClient().post(
        ApiEndpoints.deviceToken,
        data: {'token': token, 'platform': platform, 'device_id': deviceId},
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(NotificationConstants.prefsLastFcmTokenKey, token);
      AppLogger.info('FCM token uploaded to backend successfully.');
    } catch (e) {
      // Don't throw if user is offline or not logged in yet
      AppLogger.debug('FCM token upload skipped/deferred: $e');
    }
  }

  /// De-registers FCM device token on backend when user logs out
  Future<void> unregisterFcmToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastToken = prefs.getString(
        NotificationConstants.prefsLastFcmTokenKey,
      );
      final deviceId = await getDeviceId();

      if (lastToken != null && lastToken.isNotEmpty) {
        await ApiClient().delete(
          ApiEndpoints.deviceToken,
          data: {'token': lastToken, 'device_id': deviceId},
        );
        await prefs.remove(NotificationConstants.prefsLastFcmTokenKey);
        AppLogger.info('FCM device token unlinked from backend on logout.');
      }
    } catch (e) {
      AppLogger.debug('Unregistering FCM token skipped/failed on logout: $e');
    }
  }

  /// Displays foreground notifications using flutter_local_notifications
  void _showForegroundNotification(RemoteMessage message) {
    try {
      final title =
          message.notification?.title ??
          message.data['title'] ??
          'FreshTrack Alert';
      final body = message.notification?.body ?? message.data['body'] ?? '';

      final notificationId = message.messageId.hashCode != 0
          ? message.messageId.hashCode
          : DateTime.now().millisecondsSinceEpoch % 100000;

      final payloadString = jsonEncode(message.data);

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            NotificationConstants.channelId,
            NotificationConstants.channelName,
            channelDescription: NotificationConstants.channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      _localNotifications.show(
        notificationId,
        title,
        body,
        details,
        payload: payloadString,
      );
    } catch (e, stack) {
      AppLogger.error('Failed to show foreground notification', e, stack);
    }
  }

  // ==========================================
  // Scheduled Local Notifications (Offline/Device Fallback)
  // ==========================================

  Future<void> scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final tz.TZDateTime tzDate = tz.TZDateTime.from(scheduledDate, tz.local);
    if (tzDate.isBefore(DateTime.now())) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          NotificationConstants.channelId,
          NotificationConstants.channelName,
          channelDescription: NotificationConstants.channelDescription,
          importance: Importance.max,
          priority: Priority.high,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      tzDate,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  Future<void> scheduleExpiryAlertsForItems(List<dynamic> items) async {
    await cancelAllNotifications();
    int id = 1;
    for (var item in items) {
      if (item.expiryDate == null) continue;

      final expiry = item.expiryDate!;
      final itemId = item.id.toString();

      // 1. One day prior alert (at 9:00 AM)
      final oneDayBefore = expiry.subtract(const Duration(days: 1));
      final scheduledOneDay = DateTime(
        oneDayBefore.year,
        oneDayBefore.month,
        oneDayBefore.day,
        9,
        0,
      );
      await scheduleLocalNotification(
        id: id++,
        title: 'Expiry Tomorrow: ${item.name}',
        body:
            '${item.name} will expire tomorrow. Use it soon to prevent waste!',
        scheduledDate: scheduledOneDay,
        payload: jsonEncode({
          'type': NotificationConstants.typeExpiryReminder,
          'grocery_id': itemId,
        }),
      );

      // 2. Expiry day alert (at 9:00 AM)
      final scheduledExpiry = DateTime(
        expiry.year,
        expiry.month,
        expiry.day,
        9,
        0,
      );
      await scheduleLocalNotification(
        id: id++,
        title: 'Expired Today: ${item.name}',
        body: '${item.name} is expiring today. Mark as consumed or wasted.',
        scheduledDate: scheduledExpiry,
        payload: jsonEncode({
          'type': NotificationConstants.typeExpiryReminder,
          'grocery_id': itemId,
        }),
      );
    }
  }
}
