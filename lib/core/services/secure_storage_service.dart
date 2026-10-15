import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static final SecureStorageService _instance =
      SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _keyAccess = 'jwt_access_token';
  static const String _keyRefresh = 'jwt_refresh_token';

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccess, value: token);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: _keyAccess);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefresh, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefresh);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccess);
    await _storage.delete(key: _keyRefresh);
  }
}
