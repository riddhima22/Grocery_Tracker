import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grocery_track/core/api/api_client.dart';
import 'package:grocery_track/core/api/token_refresh_manager.dart';
import 'package:grocery_track/core/services/secure_storage_service.dart';

// Test mock adapter to simulate HTTP responses
class MockAdapter implements HttpClientAdapter {
  int refreshCallCount = 0;
  int statusCodeToReturn = 200;
  dynamic responseData;
  DioException? errorToThrow;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.contains('/auth/token/refresh/')) {
      refreshCallCount++;
      if (errorToThrow != null) {
        throw errorToThrow!;
      }
      return ResponseBody.fromString(
        responseData ?? '{"success": true, "data": {"access": "new_access_token_$refreshCallCount", "refresh": "new_refresh_token_$refreshCallCount"}}',
        statusCodeToReturn,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{"success": true}', 200);
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
    test('refreshAccessToken saves new access and rotated refresh token', () async {
      await secureStorage.saveAccessToken('expired_access_1');
      await secureStorage.saveRefreshToken('valid_refresh_1');

      final mockAdapter = MockAdapter();
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

      final mockAdapter = MockAdapter();
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

      final mockAdapter = MockAdapter();
      final testDio = Dio()..httpClientAdapter = mockAdapter;

      // Request that was sent with an older token
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

      final mockAdapter = MockAdapter()
        ..errorToThrow = DioException(
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

      final mockAdapter = MockAdapter()
        ..errorToThrow = DioException(
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
