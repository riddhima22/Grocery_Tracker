import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_endpoints.dart';
import '../../../core/services/secure_storage_service.dart';
import '../model/user_model.dart';

class AuthRepository {
  final ApiClient _apiClient = ApiClient();
  final SecureStorageService _secureStorage = SecureStorageService();

  /// Helper to safely process auth responses (JWT tokens + user data)
  /// Supports both nested structure ({data: {user: {}, tokens: {access, refresh}}})
  /// and flat structure ({access, refresh, user: {}}).
  Future<UserModel> _processAuthResponse(dynamic responseData) async {
    final Map<String, dynamic> map;
    if (responseData is Map<String, dynamic> &&
        responseData['success'] == true &&
        responseData['data'] != null) {
      map = responseData['data'] as Map<String, dynamic>;
    } else if (responseData is Map<String, dynamic>) {
      map = responseData;
    } else {
      throw Exception('Invalid authentication response from server');
    }

    String? access;
    String? refresh;

    if (map['tokens'] is Map<String, dynamic>) {
      final tokensMap = map['tokens'] as Map<String, dynamic>;
      access = tokensMap['access'] as String?;
      refresh = tokensMap['refresh'] as String?;
    }

    access ??= map['access'] as String?;
    refresh ??= map['refresh'] as String?;

    if (access != null) {
      await _secureStorage.saveAccessToken(access);
    }
    if (refresh != null) {
      await _secureStorage.saveRefreshToken(refresh);
    }

    if (map['user'] is Map<String, dynamic>) {
      return UserModel.fromJson(map['user'] as Map<String, dynamic>);
    } else {
      return await getProfile();
    }
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.register,
      data: {
        'email': email,
        'password': password,
        'display_name': displayName,
      },
    );

    return await _processAuthResponse(response.data);
  }

  Future<UserModel> login({
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.login,
      data: {
        'email': email,
        'password': password,
      },
    );

    return await _processAuthResponse(response.data);
  }

  Future<UserModel> getProfile() async {
    final response = await _apiClient.get(ApiEndpoints.me);
    return UserModel.fromJson(response.data['data'] ?? response.data);
  }

  Future<UserModel> updateProfile(Map<String, dynamic> data, {String? avatarPath}) async {
    dynamic requestData;
    Options? options;

    if (avatarPath != null) {
      final multipartFile = await MultipartFile.fromFile(
        avatarPath,
        filename: avatarPath.split('/').last,
      );
      final map = Map<String, dynamic>.from(data);
      map['avatar'] = multipartFile;
      requestData = FormData.fromMap(map);
      options = Options(contentType: 'multipart/form-data');
    } else {
      requestData = data;
    }

    final response = await _apiClient.patch(
      ApiEndpoints.me,
      data: requestData,
      options: options,
    );
    final responseData = response.data['data'] ?? response.data;
    return UserModel.fromJson(responseData);
  }

  Future<void> requestPasswordReset(String email) async {
    await _apiClient.post(ApiEndpoints.forgotPassword, data: {'email': email});
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _apiClient.post(ApiEndpoints.resetPassword, data: {
      'token': token,
      'password': newPassword,
    });
  }

  Future<void> verifyEmail({String? token}) async {
    final data = token != null && token.isNotEmpty ? {'token': token} : null;
    await _apiClient.post(ApiEndpoints.verifyEmail, data: data);
  }

  Future<void> resendVerification() async {
    await _apiClient.post(ApiEndpoints.resendVerification);
  }

  Future<void> logout() async {
    try {
      final refresh = await _secureStorage.getRefreshToken();
      if (refresh != null) {
        await _apiClient.post(ApiEndpoints.logout, data: {'refresh': refresh});
      }
    } catch (_) {}
    await _secureStorage.clearTokens();
  }

  Future<void> deleteAccount() async {
    await _apiClient.delete(ApiEndpoints.deleteAccount);
    await _secureStorage.clearTokens();
  }

  Future<bool> hasValidToken() async {
    final token = await _secureStorage.getAccessToken();
    final refresh = await _secureStorage.getRefreshToken();
    return token != null || refresh != null;
  }

  Future<UserModel> loginWithGoogle({required String token, String? email, String? name}) async {
    final response = await _apiClient.post(
      ApiEndpoints.googleLogin,
      data: {
        'token': token,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
      },
    );

    return await _processAuthResponse(response.data);
  }

  Future<UserModel> loginWithApple({required String token, String? email, String? name}) async {
    final response = await _apiClient.post(
      ApiEndpoints.appleLogin,
      data: {
        'token': token,
        if (email != null) 'email': email,
        if (name != null) 'name': name,
      },
    );

    return await _processAuthResponse(response.data);
  }
}
