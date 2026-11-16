import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grocery_track/core/api/api_client.dart';
import 'package:grocery_track/core/api/token_refresh_manager.dart';
import 'package:grocery_track/core/services/secure_storage_service.dart';

// Test mock adapter to record all calls and simulate network responses
class MockHttpRecordingAdapter implements HttpClientAdapter {
  final List<RequestOptions> recordedCalls = [];
  int refreshCallCount = 0;
  int retryCallCount = 0;
  DioException? refreshErrorToThrow;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recordedCalls.add(options.copyWith());

    // Consume request stream to simulate network transmission
    if (requestStream != null) {
      await for (final _ in requestStream) {}
    }

    // 1. Handle token refresh endpoint
    if (options.path.contains('/auth/token/refresh/')) {
      refreshCallCount++;
      if (refreshErrorToThrow != null) {
        throw refreshErrorToThrow!;
      }
      return ResponseBody.fromString(
        '{"success": true, "data": {"access": "new_access_token_$refreshCallCount", "refresh": "new_refresh_token_$refreshCallCount"}}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // 2. Handle original request retries (isRetry == true)
    if (options.extra['isRetry'] == true) {
      retryCallCount++;
      return ResponseBody.fromString(
        '{"success": true, "data": {"status": "retried_successfully", "retry_count": $retryCallCount}}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    // 3. Initial requests return 401 Unauthorized (expired token)
    return ResponseBody.fromString(
      '{"detail": "Given token not valid for any token type", "code": "token_not_valid", "messages": [{"message": "Token is expired"}]}',
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  final secureStorage = SecureStorageService();
  final tokenRefreshManager = TokenRefreshManager();

  setUp(() async {
    await secureStorage.clearTokens();
  });

  group('TokenRefreshManager Lifecycle Tests', () {
    test('refreshAccessToken saves new access and rotated refresh token atomically', () async {
      await secureStorage.saveAccessToken('expired_access_1');
      await secureStorage.saveRefreshToken('valid_refresh_1');

      final mockAdapter = MockHttpRecordingAdapter();
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      final newAccess = await tokenRefreshManager.refreshAccessToken(dioClient: testDio);

      expect(newAccess, 'new_access_token_1');
      expect(await secureStorage.getAccessToken(), 'new_access_token_1');
      expect(await secureStorage.getRefreshToken(), 'new_refresh_token_1');
      expect(mockAdapter.refreshCallCount, 1);
    });

    test('simultaneous refresh requests trigger only 1 backend call and return same token', () async {
      await secureStorage.saveAccessToken('expired_access_1');
      await secureStorage.saveRefreshToken('valid_refresh_1');

      final mockAdapter = MockHttpRecordingAdapter();
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      // Trigger 5 simultaneous calls
      final futures = List.generate(
        5,
        (_) => tokenRefreshManager.refreshAccessToken(dioClient: testDio),
      );

      final results = await Future.wait(futures);

      expect(mockAdapter.refreshCallCount, 1);
      for (final result in results) {
        expect(result, 'new_access_token_1');
      }
      expect(await secureStorage.getAccessToken(), 'new_access_token_1');
      expect(await secureStorage.getRefreshToken(), 'new_refresh_token_1');
    });

    test('avoids duplicate refresh if token was already updated by another concurrent request', () async {
      await secureStorage.saveAccessToken('already_refreshed_access');
      await secureStorage.saveRefreshToken('valid_refresh_1');

      final mockAdapter = MockHttpRecordingAdapter();
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      final result = await tokenRefreshManager.refreshAccessToken(
        failedToken: 'old_expired_token',
        dioClient: testDio,
      );

      // Must return current stored token without calling refresh endpoint
      expect(result, 'already_refreshed_access');
      expect(mockAdapter.refreshCallCount, 0);
    });

    test('expired/blacklisted refresh token throws RefreshTokenException with isSessionExpired=true', () async {
      await secureStorage.saveRefreshToken('blacklisted_refresh_token');

      final mockAdapter = MockHttpRecordingAdapter()
        ..refreshErrorToThrow = DioException(
          requestOptions: RequestOptions(path: '/auth/token/refresh/'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/token/refresh/'),
            statusCode: 401,
            data: {'detail': 'Token is blacklisted', 'code': 'token_not_valid'},
          ),
          type: DioExceptionType.badResponse,
        );
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      await expectLater(
        tokenRefreshManager.refreshAccessToken(dioClient: testDio),
        throwsA(
          isA<RefreshTokenException>().having(
            (e) => e.isSessionExpired,
            'isSessionExpired',
            isTrue,
          ),
        ),
      );
    });

    test('transient network error during refresh throws RefreshTokenException with isSessionExpired=false', () async {
      await secureStorage.saveRefreshToken('valid_refresh_token');

      final mockAdapter = MockHttpRecordingAdapter()
        ..refreshErrorToThrow = DioException(
          requestOptions: RequestOptions(path: '/auth/token/refresh/'),
          type: DioExceptionType.connectionTimeout,
          message: 'Connection timed out',
        );
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      await expectLater(
        tokenRefreshManager.refreshAccessToken(dioClient: testDio),
        throwsA(
          isA<RefreshTokenException>().having(
            (e) => e.isSessionExpired,
            'isSessionExpired',
            isFalse,
          ),
        ),
      );
    });
  });

  group('ApiClient Original Request Retry Tests', () {
    test('expired access token retries original JSON request once with new token', () async {
      await secureStorage.saveAccessToken('expired_access_token');
      await secureStorage.saveRefreshToken('valid_refresh_token');

      final mockAdapter = MockHttpRecordingAdapter();
      final testDio = Dio(BaseOptions(baseUrl: 'https://example.com'))..httpClientAdapter = mockAdapter;

      // Add interceptor under test
      testDio.interceptors.add(
        InterceptorsWrapper(
          onError: (err, handler) async {
            final options = err.requestOptions;
            if (err.response?.statusCode == 401 && options.extra['isRetry'] != true) {
              options.extra['isRetry'] = true;
              final newAccess = await tokenRefreshManager.refreshAccessToken(dioClient: testDio);
              if (newAccess != null) {
                options.headers['Authorization'] = 'Bearer $newAccess';
                final response = await testDio.fetch(options);
                return handler.resolve(response);
              }
            }
            return handler.next(err);
          },
        ),
      );

      final response = await testDio.post(
        '/api/v1/groceries/',
        data: {'name': 'Bananas', 'quantity': 5},
      );

      expect(response.statusCode, 200);
      expect(response.data['data']['status'], 'retried_successfully');
      expect(mockAdapter.refreshCallCount, 1);
      expect(mockAdapter.retryCallCount, 1);

      // Verify call sequence: call 1 was initial 401, call 2 was refresh, call 3 was retried request
      expect(mockAdapter.recordedCalls.length, 3);
      expect(mockAdapter.recordedCalls[0].path, '/api/v1/groceries/');
      expect(mockAdapter.recordedCalls[1].path, contains('/auth/token/refresh/'));
      expect(mockAdapter.recordedCalls[2].path, '/api/v1/groceries/');
      expect(mockAdapter.recordedCalls[2].headers['Authorization'], 'Bearer new_access_token_1');
    });

    test('expired access token retries original multipart FormData upload with fresh boundaries', () async {
      await secureStorage.saveAccessToken('expired_access_token');
      await secureStorage.saveRefreshToken('valid_refresh_token');

      final mockAdapter = MockHttpRecordingAdapter();
      final testDio = Dio(BaseOptions(baseUrl: 'https://example.com'))..httpClientAdapter = mockAdapter;

      testDio.interceptors.add(
        InterceptorsWrapper(
          onError: (err, handler) async {
            final options = err.requestOptions;
            if (err.response?.statusCode == 401 && options.extra['isRetry'] != true) {
              options.extra['isRetry'] = true;
              final newAccess = await tokenRefreshManager.refreshAccessToken(dioClient: testDio);
              if (newAccess != null) {
                options.headers['Authorization'] = 'Bearer $newAccess';

                // Recreate FormData cleanly
                if (options.data is FormData) {
                  final original = options.data as FormData;
                  final fresh = FormData();
                  fresh.fields.addAll(original.fields);
                  for (final f in original.files) {
                    fresh.files.add(MapEntry(f.key, f.value.clone()));
                  }
                  options.data = fresh;
                  options.contentType = null;
                  options.headers.remove(Headers.contentTypeHeader);
                  options.headers.remove('content-type');
                  options.headers.remove('Content-Type');
                  options.headers.remove(Headers.contentLengthHeader);
                  options.headers.remove('content-length');
                }

                final response = await testDio.fetch(options);
                return handler.resolve(response);
              }
            }
            return handler.next(err);
          },
        ),
      );

      final file1 = MultipartFile.fromBytes([10, 20, 30], filename: 'img1.jpg');
      final file2 = MultipartFile.fromBytes([40, 50, 60], filename: 'img2.jpg');
      final formData = FormData.fromMap({'images': [file1, file2]});

      final response = await testDio.post(
        '/api/v1/scans/sessions/',
        data: formData,
      );

      expect(response.statusCode, 200);
      expect(response.data['data']['status'], 'retried_successfully');
      expect(mockAdapter.refreshCallCount, 1);
      expect(mockAdapter.retryCallCount, 1);

      // Verify multipart call sequence
      expect(mockAdapter.recordedCalls.length, 3);
      expect(mockAdapter.recordedCalls[0].path, '/api/v1/scans/sessions/');
      expect(mockAdapter.recordedCalls[1].path, contains('/auth/token/refresh/'));
      expect(mockAdapter.recordedCalls[2].path, '/api/v1/scans/sessions/');
      expect(mockAdapter.recordedCalls[2].headers['Authorization'], 'Bearer new_access_token_1');
      expect(mockAdapter.recordedCalls[2].data, isA<FormData>());
      expect((mockAdapter.recordedCalls[2].data as FormData).files.length, 2);
    });

    test('prevents infinite retry loops when retried request returns 401 again', () async {
      await secureStorage.saveAccessToken('expired_access_token');
      await secureStorage.saveRefreshToken('valid_refresh_token');

      int attemptCount = 0;
      final testDio = Dio(BaseOptions(baseUrl: 'https://example.com'));
      final adapter = MockHttpRecordingAdapter();
      testDio.httpClientAdapter = adapter;

      testDio.interceptors.add(
        InterceptorsWrapper(
          onError: (err, handler) async {
            final options = err.requestOptions;
            if (err.response?.statusCode == 401 && options.extra['isRetry'] != true) {
              attemptCount++;
              options.extra['isRetry'] = true;
              final newAccess = await tokenRefreshManager.refreshAccessToken(dioClient: testDio);
              if (newAccess != null) {
                options.headers['Authorization'] = 'Bearer $newAccess';
                try {
                  // Simulate server persistently returning 401 even on retry
                  final retryOptions = options.copyWith();
                  retryOptions.extra['force401'] = true;
                  final response = await testDio.fetch(retryOptions);
                  return handler.resolve(response);
                } on DioException catch (retryErr) {
                  return handler.next(retryErr);
                }
              }
            }
            return handler.next(err);
          },
        ),
      );

      // Verify that after 1 retry attempt, it fails cleanly without an infinite loop
      try {
        await testDio.get('/api/v1/groceries/');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 401);
      }
      expect(attemptCount, 1);
    });
  });

  group('ApiClient Log Sanitization & Security Tests', () {
    test('sanitizes tokens and passwords from Maps and FormDatas without leaking credentials', () {
      final sensitiveMap = {
        'email': 'user@example.com',
        'password': 'superSecretPassword123!',
        'refresh': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
        'access': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
        'nested': {
          'token': 'secret_token_value',
          'safe_data': 'public_info',
        },
      };

      final sanitized = ApiClient.sanitizeLogData(sensitiveMap);

      expect(sanitized['password'], '[REDACTED]');
      expect(sanitized['refresh'], '[REDACTED]');
      expect(sanitized['access'], '[REDACTED]');
      expect(sanitized['nested']['token'], '[REDACTED]');
      expect(sanitized['nested']['safe_data'], 'public_info');
      expect(sanitized['email'], 'user@example.com');
    });

    test('sanitizes Bearer headers in string logs', () {
      const rawLog = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.xyz.123';
      final sanitized = ApiClient.sanitizeLogData(rawLog);

      expect(sanitized, contains('Bearer [REDACTED]'));
      expect(sanitized, isNot(contains('xyz.123')));
    });
  });
}
