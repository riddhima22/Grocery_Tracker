import 'dart:async';
import 'package:dio/dio.dart';
import '../services/secure_storage_service.dart';
import 'api_endpoints.dart';
import '../utils/app_logger.dart';

class TokenRefreshManager {
  static final TokenRefreshManager _instance = TokenRefreshManager._internal();
  factory TokenRefreshManager() => _instance;
  TokenRefreshManager._internal();

  final SecureStorageService _secureStorage = SecureStorageService();
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  Future<String?> refreshAccessToken([Dio? dioClient]) async {
    if (_isRefreshing && _refreshCompleter != null) {
      AppLogger.info('Token refresh is already in progress, awaiting result...');
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    final completer = Completer<String?>();
    _refreshCompleter = completer;

    try {
      AppLogger.info('Starting token refresh request...');
      final refreshToken = await _secureStorage.getRefreshToken();
      if (refreshToken == null) {
        AppLogger.warning('No refresh token found in storage.');
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }

      // Perform request using a clean Dio instance to avoid interceptor recursion
      final freshDio = Dio(BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

      final response = await freshDio.post(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> dataMap;
        if (response.data is Map<String, dynamic> && response.data['success'] == true && response.data['data'] != null) {
          dataMap = response.data['data'] as Map<String, dynamic>;
        } else if (response.data is Map<String, dynamic>) {
          dataMap = response.data as Map<String, dynamic>;
        } else {
          throw Exception('Invalid token refresh response type');
        }

        final newAccess = dataMap['access'] as String?;
        final newRefresh = dataMap['refresh'] as String?; // Optional depending on settings rotation
        
        if (newAccess == null) {
          throw Exception('Access token not found in refresh response');
        }

        await _secureStorage.saveAccessToken(newAccess);
        if (newRefresh != null) {
          await _secureStorage.saveRefreshToken(newRefresh);
        }
        
        AppLogger.info('Token refresh completed successfully.');
        if (!completer.isCompleted) completer.complete(newAccess);
        return newAccess;
      } else {
        AppLogger.warning('Token refresh returned invalid status: ${response.statusCode}');
        if (!completer.isCompleted) completer.complete(null);
        return null;
      }
    } catch (e, stack) {
      AppLogger.error('Token refresh failed', e, stack);
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}

