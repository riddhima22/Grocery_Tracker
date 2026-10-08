import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../firebase_options.dart';
import '../utils/app_logger.dart';

/// Top-level background message handler required by Firebase Messaging.
/// Must be annotated with @pragma('vm:entry-point') to prevent tree-shaking.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Ensure Firebase is initialized in background isolate if not already
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    AppLogger.info(
      'FCM Background message received: ID=${message.messageId}, '
      'Title=${message.notification?.title ?? message.data['title']}, '
      'Type=${message.data['type']}',
    );
  } catch (e, stack) {
    AppLogger.error('Error in firebaseMessagingBackgroundHandler', e, stack);
  }
}
