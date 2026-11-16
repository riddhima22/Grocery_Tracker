import 'dart:async';
import 'package:dio/dio.dart';
import '../services/secure_storage_service.dart';
import 'api_endpoints.dart';
import '../utils/app_logger.dart';

class RefreshTokenException implements Exception {
  final bool isSessionExpired;
  final String message;

  RefreshTokenException(this.message, {this.isSessionExpired = false});

  @override
  String toString() => message;
}

class TokenRefreshManager {
  static final TokenRefreshManager _instance = TokenRefreshManager._internal();
  factory TokenRefreshManager() => _instance;
  TokenRefreshManager._internal();

  final SecureStorageService _secureStorage = SecureStorageService();
  bool _isRefreshing = false;
  Completer<String?>? _refreshCompleter;

  bool get isRefreshing => _isRefreshing;

  /// Waits for an active in-flight refresh operation without starting another one.
  Future<String?> waitForRefresh() {
    if (_isRefreshing && _refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    return Future.value(null);
  }

  /// Centralized JWT access token refresh with concurrency locking,
  /// token reuse detection, and refresh token rotation persistence.
  Future<String?> refreshAccessToken({String? failedToken, Dio? dioClient}) async {
    // 1. If another concurrent request already refreshed the token in storage,
    // reuse the new token immediately without hitting the backend again!
    if (failedToken != null && failedToken.isNotEmpty) {
      final currentStoredToken = await _secureStorage.getAccessToken();
      if (currentStoredToken != null &&
          currentStoredToken.isNotEmpty &&
          currentStoredToken != failedToken) {
        AppLogger.info(
          'Access token was already refreshed by a concurrent request; reusing updated token.',
        );
        return currentStoredToken;
      }
    }

    // 2. If a refresh is currently in progress, await the shared Completer
    if (_isRefreshing && _refreshCompleter != null) {
      AppLogger.info(
        'Token refresh is already in progress, awaiting shared result...',
      );
      return _refreshCompleter!.future;
    }

    _isRefreshing = true;
    final completer = Completer<String?>();
    // Prevent unhandled zone exception if completer completes with error before/without secondary listeners
    completer.future.catchError((_) => null);
    _refreshCompleter = completer;

    try {
      AppLogger.info('Centralized JWT refresh started.');
      final refreshToken = await _secureStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        AppLogger.warning('No refresh token found in storage. Centralized JWT refresh failed.');
        final err = RefreshTokenException(
          'No refresh token found in storage.',
          isSessionExpired: true,
        );
        if (!completer.isCompleted) completer.completeError(err);
        throw err;
      }

      // Perform request using a clean, isolated Dio instance to prevent interceptor recursion
      final freshDio = dioClient ??
          Dio(
            BaseOptions(
              baseUrl: ApiEndpoints.baseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
            ),
          );

      final response = await freshDio.post(
        ApiEndpoints.refresh,
        data: {'refresh': refreshToken},
      );

      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> dataMap;
        if (response.data is Map<String, dynamic> &&
            response.data['success'] == true &&
            response.data['data'] != null &&
            response.data['data'] is Map<String, dynamic>) {
          dataMap = response.data['data'] as Map<String, dynamic>;
        } else if (response.data is Map<String, dynamic>) {
          dataMap = response.data as Map<String, dynamic>;
        } else {
          throw RefreshTokenException('Invalid token refresh response format.');
        }

        final newAccess = (dataMap['access'] ??
            (response.data is Map ? response.data['access'] : null)) as String?;
        final newRefresh = (dataMap['refresh'] ??
            (response.data is Map ? response.data['refresh'] : null)) as String?;

        if (newAccess == null || newAccess.isEmpty) {
          throw RefreshTokenException(
            'Access token not found in token refresh response.',
          );
        }

        await _secureStorage.saveTokens(
          access: newAccess,
          refresh: (newRefresh != null && newRefresh.isNotEmpty) ? newRefresh : null,
        );
        if (newRefresh != null && newRefresh.isNotEmpty) {
          AppLogger.info('Rotated refresh token saved to secure storage.');
        }

        AppLogger.info(
          'Centralized JWT refresh succeeded. New access token and rotated refresh token secured.',
        );
        if (!completer.isCompleted) completer.complete(newAccess);
        return newAccess;
      } else {
        final err = RefreshTokenException(
          'Token refresh returned unexpected HTTP status: ${response.statusCode}',
        );
        if (!completer.isCompleted) completer.completeError(err);
        throw err;
      }
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;
      final errorData = dioErr.response?.data;
      final errorStr = errorData?.toString().toLowerCase() ?? '';

      // Check if refresh token is genuinely invalid, expired, or blacklisted (HTTP 401 or 400)
      final isBlacklistedOrInvalid =
          statusCode == 401 ||
          statusCode == 403 ||
          (statusCode == 400 &&
              (errorStr.contains('token_not_valid') ||
                  errorStr.contains('blacklisted') ||
                  errorStr.contains('expired') ||
                  errorStr.contains('invalid')));

      if (isBlacklistedOrInvalid) {
        AppLogger.warning(
          'Refresh token was rejected by server (HTTP $statusCode). Centralized JWT refresh failed.',
        );
        final err = RefreshTokenException(
          'Refresh token is invalid, expired, or blacklisted.',
          isSessionExpired: true,
        );
        if (!completer.isCompleted) completer.completeError(err);
        throw err;
      }

      AppLogger.warning(
        'Centralized JWT refresh encountered transient network/server error: ${dioErr.type} ${dioErr.message}',
      );
      final err = RefreshTokenException(
        'Transient network error during token refresh: ${dioErr.message}',
        isSessionExpired: false,
      );
      if (!completer.isCompleted) completer.completeError(err);
      throw err;
    } catch (e, stack) {
      AppLogger.error('Centralized JWT refresh unexpected error', e, stack);
      if (e is RefreshTokenException) {
        if (!completer.isCompleted) completer.completeError(e);
        rethrow;
      }
      final err = RefreshTokenException(
        'Token refresh failed unexpectedly: $e',
        isSessionExpired: false,
      );
      if (!completer.isCompleted) completer.completeError(err);
      throw err;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}
