import 'package:dio/dio.dart';
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
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 45),
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

  static bool _isPublicEndpoint(String path) {
    final publicEndpoints = [
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
          final path = err.requestOptions.path;
          // Only trigger token refresh on authenticated endpoints (not public login/register)
          if (err.response?.statusCode == 401 &&
              !_isPublicEndpoint(path) &&
              err.requestOptions.extra['isRetry'] != true) {
            AppLogger.warning('Received 401 Unauthorized on $path. Attempting token refresh...');
            err.requestOptions.extra['isRetry'] = true;
            
            try {
              final newAccessToken = await TokenRefreshManager().refreshAccessToken();
              if (newAccessToken != null) {
                // Update Authorization header with the new token
                err.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
                // Clone and retry request
                final response = await _dio.fetch(err.requestOptions);
                return handler.resolve(response);
              }
            } catch (e) {
              AppLogger.error('Token refresh retry failed', e);
            }

            // If refresh fails or returns null, clear state and kick user to login
            AppLogger.error('Token refresh failed. Redirecting to Login screen...');
            await _secureStorage.clearTokens();
            AppNavigation.toAndRemoveUntil(AppRoutes.login);
          }
          handler.next(err);
        },
      );

  Interceptor _logInterceptor() => LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        logPrint: (obj) => AppLogger.debug(obj.toString()),
      );

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
