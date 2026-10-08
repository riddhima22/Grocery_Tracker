import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_endpoints.dart';
import 'api_error_mapper.dart';
import 'token_refresh_manager.dart';
import '../services/secure_storage_service.dart';
import '../utils/app_logger.dart';
import '../../config/app_navigation.dart';
import '../../config/app_routes.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio _dio;
  final SecureStorageService _secureStorage = SecureStorageService();

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 90),
        receiveTimeout: const Duration(seconds: 90),
        sendTimeout: const Duration(seconds: 60),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.addAll([
      _authInterceptor(),
      _logInterceptor(),
    ]);
  }

  /// Asynchronously pre-warms the backend (e.g. waking it from Render free-tier sleep)
  /// without blocking the UI.
  Future<void> warmUp() async {
    try {
      await _dio.get(
        ApiEndpoints.health,
        options: Options(validateStatus: (status) => status != null && status < 500),
      );
    } catch (_) {
      // Best effort background wakeup ping
    }
  }

  static bool _isPublicEndpoint(String path) {
    final publicEndpoints = [
      ApiEndpoints.health,
      ApiEndpoints.login,
      ApiEndpoints.register,
      ApiEndpoints.refresh,
      ApiEndpoints.googleLogin,
      ApiEndpoints.appleLogin,
      ApiEndpoints.forgotPassword,
      ApiEndpoints.resetPassword,
    ];
    return publicEndpoints.any((endpoint) => path.contains(endpoint));
  }

  Interceptor _authInterceptor() => InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Do NOT attach Authorization header to unauthenticated/public auth endpoints
          if (!_isPublicEndpoint(options.path)) {
            final token = await _secureStorage.getAccessToken();
            if (token != null && !options.headers.containsKey('Authorization')) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }
          handler.next(options);
        },
        onError: (err, handler) async {
          final options = err.requestOptions;
          final path = options.path;

          // 1. Cold start / server timeout auto-retry (e.g. Render waking up)
          final isTimeoutOrNetworkError =
              err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.connectionError ||
              (err.response?.statusCode != null &&
                  [502, 503, 504].contains(err.response!.statusCode));

          if (isTimeoutOrNetworkError && options.extra['isColdStartRetry'] != true) {
            options.extra['isColdStartRetry'] = true;
            AppLogger.warning(
              'Server latency or cold start on $path (${err.type}). Retrying request in 2s...',
            );
            await Future.delayed(const Duration(seconds: 2));
            try {
              final response = await _dio.fetch(options);
              return handler.resolve(response);
            } catch (retryErr) {
              if (retryErr is DioException) {
                return handler.next(retryErr);
              }
            }
          }

          // 2. Token refresh on 401
          if (err.response?.statusCode == 401 &&
              !_isPublicEndpoint(path) &&
              options.extra['isRetry'] != true) {
            AppLogger.warning('Received 401 Unauthorized on $path. Attempting token refresh...');
            options.extra['isRetry'] = true;
            
            try {
              final newAccessToken = await TokenRefreshManager().refreshAccessToken();
              if (newAccessToken != null) {
                // Update Authorization header with the new token
                options.headers['Authorization'] = 'Bearer $newAccessToken';
                // Clone and retry request
                final response = await _dio.fetch(options);
                return handler.resolve(response);
              }
            } on RefreshTokenException catch (refreshErr) {
              if (refreshErr.isSessionExpired) {
                // Only kick user to login if refresh token is genuinely expired or invalid
                AppLogger.error('Session expired permanently. Redirecting to Login screen...');
                await _secureStorage.clearTokens();
                AppNavigation.toAndRemoveUntil(AppRoutes.login);
                return handler.next(err);
              } else {
                // Transient error: do NOT kick user to login screen!
                AppLogger.warning('Token refresh failed due to network/server timeout. User session preserved.');
                return handler.next(err);
              }
            } catch (e) {
              AppLogger.error('Token refresh retry encountered unexpected error', e);
              return handler.next(err);
            }
          }
          handler.next(err);
        },
      );

  Interceptor _logInterceptor() {
    if (kReleaseMode) {
      // In production release mode, disable all payload/header logging
      return LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: false,
      );
    }

    return LogInterceptor(
      requestHeader: false,
      requestBody: true,
      responseHeader: false,
      responseBody: false,
      logPrint: (obj) {
        String msg = obj.toString();
        // Redact authorization headers
        msg = msg.replaceAll(RegExp(r'Bearer\s+[a-zA-Z0-9_\-\.]+'), 'Bearer [REDACTED]');
        // Redact passwords, tokens, and credentials in json payloads
        msg = msg.replaceAll(
          RegExp(r'"(password|token|refresh|access|id_token|secret)":\s*"[^"]*"', caseSensitive: false),
          r'"$1": "[REDACTED]"',
        );
        AppLogger.debug(msg);
      },
    );
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters, Options? options}) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters, Options? options}) async {
    try {
      return await _dio.post(path, data: data, queryParameters: queryParameters, options: options);
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> put(String path, {dynamic data, Options? options}) async {
    try {
      return await _dio.put(path, data: data, options: options);
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> patch(String path, {dynamic data, Options? options}) async {
    try {
      return await _dio.patch(path, data: data, options: options);
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> delete(String path, {dynamic data, Options? options}) async {
    try {
      return await _dio.delete(path, data: data, options: options);
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }
}
