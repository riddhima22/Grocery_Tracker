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
        connectTimeout: const Duration(seconds: 45),
        receiveTimeout: const Duration(seconds: 45),
        sendTimeout: const Duration(seconds: 45),
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

  static bool _isLoggingOut = false;

  /// Prevents multiple simultaneous logout and navigation operations
  static Future<void> _handlePermanentSessionExpiry() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    try {
      AppLogger.error(
        'Session expired permanently. Clearing credentials and redirecting to Login screen...',
      );
      await SecureStorageService().clearTokens();
      AppNavigation.toAndRemoveUntil(AppRoutes.login);
    } finally {
      // Release lock after navigation delay
      Future.delayed(const Duration(seconds: 3), () {
        _isLoggingOut = false;
      });
    }
  }

  /// Recreates a FormData object with clean unfinalized streams for retry
  static FormData _recreateFormData(FormData original) {
    final fresh = FormData();
    fresh.fields.addAll(original.fields);
    for (final file in original.files) {
      try {
        fresh.files.add(MapEntry(file.key, file.value.clone()));
      } catch (_) {
        fresh.files.add(file);
      }
    }
    return fresh;
  }

  /// Cleans Content-Type and Content-Length headers and options so Dio regenerates
  /// fresh boundaries and content lengths for retried requests.
  static void _prepareOptionsForRetry(RequestOptions options) {
    if (options.data is FormData) {
      options.data = _recreateFormData(options.data as FormData);
      options.contentType = null;
      options.headers.remove(Headers.contentTypeHeader);
      options.headers.remove('content-type');
      options.headers.remove('Content-Type');
      options.headers.remove(Headers.contentLengthHeader);
      options.headers.remove('content-length');
      options.headers.remove('Content-Length');
    }
  }

  Interceptor _authInterceptor() => InterceptorsWrapper(
    onRequest: (options, handler) async {
      // Do NOT attach Authorization header to unauthenticated/public auth endpoints
      if (!_isPublicEndpoint(options.path)) {
        // If a centralized token refresh is currently running, wait for it to complete
        // so this request departs with the fresh access token rather than a doomed expired one.
        if (TokenRefreshManager().isRefreshing) {
          AppLogger.info(
            'Request to ${options.path} paused awaiting active token refresh...',
          );
          await TokenRefreshManager().waitForRefresh();
        }

        final token = await _secureStorage.getAccessToken();
        if (token != null) {
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
          _prepareOptionsForRetry(options);
          final response = await _dio.fetch(options);
          return handler.resolve(response);
        } catch (retryErr) {
          if (retryErr is DioException) {
            return handler.next(retryErr);
          }
        }
      }

      // 2. Token refresh and original request retry on HTTP 401
      if (err.response?.statusCode == 401 &&
          !_isPublicEndpoint(path) &&
          options.extra['isRetry'] != true) {
        options.extra['isRetry'] = true;
        AppLogger.warning(
          'Access token expired on ${options.method} $path (HTTP 401). Initiating token refresh...',
        );

        final authHeader = options.headers['Authorization'] as String?;
        final failedToken = authHeader?.replaceFirst('Bearer ', '').trim();

        try {
          final newAccessToken = await TokenRefreshManager()
              .refreshAccessToken(failedToken: failedToken);
          if (newAccessToken != null) {
            // Update Authorization header with the newly minted access token
            options.headers['Authorization'] = 'Bearer $newAccessToken';

            // Clean headers and prepare fresh unfinalized streams for multipart uploads
            _prepareOptionsForRetry(options);

            AppLogger.info(
              'Retrying original request: ${options.method} $path with refreshed token...',
            );
            final response = await _dio.fetch(options);
            AppLogger.info(
              'Original request retry succeeded: ${options.method} $path (HTTP ${response.statusCode}).',
            );
            return handler.resolve(response);
          }
        } on RefreshTokenException catch (refreshErr) {
          if (refreshErr.isSessionExpired) {
            AppLogger.error(
              'Session expired permanently on $path. Refresh token rejected (${refreshErr.message}).',
            );
            await _handlePermanentSessionExpiry();
            return handler.next(err);
          } else {
            // Transient error (timeout / 5xx): do NOT kick user to login screen
            AppLogger.warning(
              'Token refresh encountered transient error: ${refreshErr.message}. Session preserved.',
            );
            return handler.next(err);
          }
        } on DioException catch (retryDioErr) {
          AppLogger.error(
            'Original request retry failed: ${options.method} $path (HTTP ${retryDioErr.response?.statusCode ?? 'NO_STATUS'}).',
          );
          return handler.next(retryDioErr);
        } catch (retryOtherErr, stack) {
          AppLogger.error(
            'Original request retry failed unexpectedly: ${options.method} $path',
            retryOtherErr,
            stack,
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

  /// Exposes log sanitization for verification and testing
  static dynamic sanitizeLogData(dynamic data) => _sanitizeLogData(data);

  static dynamic _sanitizeLogData(dynamic data) {
    if (data == null) return 'null';
    if (data is FormData) {
      final fields = data.fields.map((f) {
        final keyLower = f.key.toLowerCase();
        if (keyLower.contains('password') ||
            keyLower.contains('token') ||
            keyLower.contains('secret') ||
            keyLower.contains('credential') ||
            keyLower.contains('authorization')) {
          return '${f.key}: [REDACTED]';
        }
        return '${f.key}: ${f.value}';
      }).toList();
      final files = data.files
          .map((f) => '${f.key}: File(${f.value.filename}, ${f.value.length}b)')
          .toList();
      return 'FormData(fields: $fields, files: $files)';
    }

    if (data is Map) {
      final sanitized = <String, dynamic>{};
      for (final entry in data.entries) {
        final keyLower = entry.key.toString().toLowerCase();
        if (keyLower.contains('password') ||
            keyLower.contains('token') ||
            keyLower.contains('refresh') ||
            keyLower.contains('access') ||
            keyLower.contains('secret') ||
            keyLower.contains('credential') ||
            keyLower.contains('authorization')) {
          sanitized[entry.key.toString()] = '[REDACTED]';
        } else if (entry.value is Map || entry.value is List) {
          sanitized[entry.key.toString()] = _sanitizeLogData(entry.value);
        } else {
          sanitized[entry.key.toString()] = entry.value;
        }
      }
      return sanitized;
    }

    if (data is List) {
      return data.map((item) => _sanitizeLogData(item)).toList();
    }

    String str = data.toString();
    // Redact Bearer tokens in headers or text
    str = str.replaceAll(
      RegExp(r'Bearer\s+[a-zA-Z0-9_\-\.]+'),
      'Bearer [REDACTED]',
    );
    // Redact passwords, tokens, credentials in JSON or Dart toString formats
    str = str.replaceAll(
      RegExp(
        r'("?(?:password|token|refresh|access|id_token|secret)"?\s*[:=]\s*)"?[^",}\s]+"?',
        caseSensitive: false,
      ),
      r'$1"[REDACTED]"',
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
