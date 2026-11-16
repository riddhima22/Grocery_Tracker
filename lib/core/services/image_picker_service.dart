import 'package:image_picker/image_picker.dart';
import 'permission_service.dart';
import '../utils/app_logger.dart';

class ImagePickerService {
  static final ImagePickerService _instance = ImagePickerService._internal();
  factory ImagePickerService() => _instance;
  ImagePickerService._internal();

  final ImagePicker _picker = ImagePicker();
  final PermissionService _permissionService = PermissionService();

  Future<XFile?> capturePhoto() async {
    final hasPermission = await _permissionService.requestCameraPermission();
    if (!hasPermission) {
      AppLogger.warning('Camera permission was denied by user.');
      return null;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (file != null) {
        final bytes = await file.length();
        AppLogger.info(
          'Captured photo: ${file.name} (${(bytes / 1024).toStringAsFixed(1)} KB)',
        );
      }
      return file;
    } catch (e, stack) {
      AppLogger.error('Failed to capture photo', e, stack);
      return null;
    }
  }

  Future<XFile?> selectImageFromGallery() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (file != null) {
        final bytes = await file.length();
        AppLogger.info(
          'Selected gallery image: ${file.name} (${(bytes / 1024).toStringAsFixed(1)} KB)',
        );
      }
      return file;
    } catch (e, stack) {
      AppLogger.error('Failed to pick gallery image', e, stack);
      return null;
    }
  }

  Future<List<XFile>> selectMultipleImagesFromGallery() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      for (final file in images) {
        final bytes = await file.length();
        AppLogger.info(
          'Selected multi-image: ${file.name} (${(bytes / 1024).toStringAsFixed(1)} KB)',
        );
      }
      return images;
    } catch (e, stack) {
      AppLogger.error('Failed to pick multi-images from gallery', e, stack);
      return [];
    }
  }
}
