import 'package:permission_handler/permission_handler.dart';
import '../utils/app_logger.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) return true;

    final result = await Permission.camera.request();
    AppLogger.info('Camera permission request result: $result');
    return result.isGranted;
  }

  Future<bool> requestPhotosPermission() async {
    final status = await Permission.photos.status;
    if (status.isGranted) return true;

    final result = await Permission.photos.request();
    AppLogger.info('Photos permission request result: $result');
    return result.isGranted;
  }

  Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    final result = await Permission.notification.request();
    AppLogger.info('Notification permission request result: $result');
    return result.isGranted;
  }
}
