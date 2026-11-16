import 'dart:io';
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
    _dio.interceptors.addAll([_authInterceptor(), _logInterceptor()]);
  }

  /// Asynchronously pre-warms the backend (e.g. waking it from Render free-tier sleep)
  /// without blocking the UI.
  Future<void> warmUp() async {
    try {
      await _dio.get(
        ApiEndpoints.health,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
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

  static bool _isCertificateOrHandshakeError(DioException err) {
    final rawError = err.error;
    if (rawError is HandshakeException ||
        rawError is TlsException ||
        rawError is CertificateException) {
      return true;
    }
    final errorStr = '${err.message} ${err.error}'.toLowerCase();
    return errorStr.contains('certificate_verify_failed') ||
        errorStr.contains('handshake error') ||
        errorStr.contains('handshakeexception') ||
        errorStr.contains('cert_authority_invalid') ||
        errorStr.contains('self signed certificate') ||
        errorStr.contains('tlsexception') ||
        errorStr.contains('certificateexception');
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
      // Do NOT retry certificate / TLS verification failures
      final isCertError = _isCertificateOrHandshakeError(err);
      final isTimeoutOrNetworkError =
          !isCertError &&
          (err.type == DioExceptionType.receiveTimeout ||
              err.type == DioExceptionType.connectionTimeout ||
              err.type == DioExceptionType.connectionError ||
              (err.response?.statusCode != null &&
                  [502, 503, 504].contains(err.response!.statusCode)));

      if (isTimeoutOrNetworkError &&
          options.extra['isColdStartRetry'] != true) {
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
        AppLogger.warning(
          'Received 401 Unauthorized on $path. Attempting token refresh...',
        );
        options.extra['isRetry'] = true;

        try {
          final newAccessToken = await TokenRefreshManager()
              .refreshAccessToken();
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
            AppLogger.error(
              'Session expired permanently. Redirecting to Login screen...',
            );
            await _secureStorage.clearTokens();
            AppNavigation.toAndRemoveUntil(AppRoutes.login);
            return handler.next(err);
          } else {
            // Transient error: do NOT kick user to login screen!
            AppLogger.warning(
              'Token refresh failed due to network/server timeout. User session preserved.',
            );
            return handler.next(err);
          }
        } catch (e) {
          AppLogger.error(
            'Token refresh retry encountered unexpected error',
            e,
          );
          return handler.next(err);
        }
      }
      handler.next(err);
    },
  );

  Interceptor _logInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) {
        if (!kReleaseMode) {
          final method = options.method.toUpperCase();
          final uri = options.uri.toString();
          final qParams = options.queryParameters.isNotEmpty
              ? options.queryParameters
              : null;
          final sanitizedBody = _sanitizeLogData(options.data);
          AppLogger.debug(
            '--> $method $uri${qParams != null ? '\nQuery: $qParams' : ''}\nBody: $sanitizedBody',
          );
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (!kReleaseMode) {
          final method = response.requestOptions.method.toUpperCase();
          final uri = response.requestOptions.uri.toString();
          final status = response.statusCode;
          final sanitizedBody = _sanitizeLogData(response.data);
          AppLogger.debug(
            '<-- $status $method $uri\nResponse Body: $sanitizedBody',
          );
        }
        handler.next(response);
      },
      onError: (err, handler) {
        final options = err.requestOptions;
        final method = options.method.toUpperCase();
        final uri = options.uri.toString();
        final status = err.response?.statusCode ?? 'NO_STATUS';
        final errType = err.type;
        final qParams = options.queryParameters.isNotEmpty
            ? options.queryParameters
            : null;
        final sanitizedReqBody = _sanitizeLogData(options.data);
        final sanitizedRespBody = _sanitizeLogData(err.response?.data);

        AppLogger.error(
          '[HTTP Error] $method $uri | Status: $status | Type: $errType'
          '${qParams != null ? '\nQuery: $qParams' : ''}\n'
          'Request Body: $sanitizedReqBody\n'
          'Response Body: $sanitizedRespBody',
          err.error,
        );
        handler.next(err);
      },
    );
  }

  static dynamic _sanitizeLogData(dynamic data) {
    if (data == null) return 'null';
    if (data is FormData) {
      final fields = data.fields.map((f) {
        final keyLower = f.key.toLowerCase();
        if (keyLower.contains('password') ||
            keyLower.contains('token') ||
            keyLower.contains('secret')) {
          return '${f.key}: [REDACTED]';
        }
        return '${f.key}: ${f.value}';
      }).toList();
      final files = data.files
          .map((f) => '${f.key}: File(${f.value.filename}, ${f.value.length}b)')
          .toList();
      return 'FormData(fields: $fields, files: $files)';
    }
    String str = data.toString();
    // Redact Bearer tokens
    str = str.replaceAll(
      RegExp(r'Bearer\s+[a-zA-Z0-9_\-\.]+'),
      'Bearer [REDACTED]',
    );
    // Redact passwords, tokens, credentials
    str = str.replaceAll(
      RegExp(
        r'"(password|token|refresh|access|id_token|secret)":\s*"[^"]*"',
        caseSensitive: false,
      ),
      r'"$1": "[REDACTED]"',
    );
    // Truncate large HTML error payloads cleanly to prevent log bloat
    if (str.length > 500 &&
        (str.contains('<html') ||
            str.contains('<!doctype') ||
            str.contains('<head'))) {
      return '${str.substring(0, 300)}... [HTML Truncated]';
    }
    return str;
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> put(
    String path, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> patch(
    String path, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.patch(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }

  Future<Response> delete(
    String path, {
    dynamic data,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        options: options,
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw ApiErrorMapper.map(e);
    }
  }
}
