import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/services/local_storage_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/api/token_refresh_manager.dart';
import '../../../core/utils/app_logger.dart';

enum AuthState { idle, loading, success, error, unverified }

class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository = AuthRepository();
  final LocalStorageService _localStorage = LocalStorageService();

  UserModel? _user;
  bool _isLoading = false;
  String? _errorMessage;
  AuthState _state = AuthState.idle;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AuthState get state => _state;
  bool get isAuthenticated => _user != null;

  void clearErrors() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> checkAuthStatus() async {
    _setState(AuthState.loading);
    try {
      final hasToken = await _authRepository.hasValidToken();
      if (!hasToken) {
        _user = null;
        _setState(AuthState.idle);
        return;
      }

      // Fast path: load cached user profile from local storage immediately
      final cachedUser = await _localStorage.getCachedUser();
      if (cachedUser != null) {
        _user = cachedUser;
        if (!_user!.emailVerified) {
          _setState(AuthState.unverified);
        } else {
          _setState(AuthState.success);
        }
        // Refresh profile in background without blocking splash transition
        _syncProfileInBackground();
        return;
      }

      // Fallback when no cache exists: fetch with timeout
      try {
        _user = await _authRepository.getProfile().timeout(
          const Duration(seconds: 4),
        );
        if (_user != null) {
          await _localStorage.saveCachedUser(_user!);
        }
      } catch (e) {
        AppLogger.warning(
          'Initial profile check failed, attempting token refresh: $e',
        );
        try {
          final newAccess = await TokenRefreshManager()
              .refreshAccessToken()
              .timeout(const Duration(seconds: 4));
          if (newAccess != null) {
            _user = await _authRepository.getProfile().timeout(
              const Duration(seconds: 4),
            );
            if (_user != null) {
              await _localStorage.saveCachedUser(_user!);
            }
          } else {
            _user = null;
            await _authRepository.logout();
            await _localStorage.clearCachedUser();
          }
        } catch (_) {
          _user = null;
        }
      }

      if (_user != null) {
        if (!_user!.emailVerified) {
          _setState(AuthState.unverified);
        } else {
          _setState(AuthState.success);
        }
        return;
      }

      _user = null;
      _setState(AuthState.idle);
    } catch (e) {
      AppLogger.error('Auth state check failed', e);
      _user = null;
      _setState(AuthState.idle);
    }
  }

  void _syncProfileInBackground() {
    _authRepository
        .getProfile()
        .then((profile) async {
          _user = profile;
          await _localStorage.saveCachedUser(profile);
          notifyListeners();
        })
        .catchError((e) {
          AppLogger.debug('Background profile sync skipped/failed: $e');
        });
  }

  Future<bool> login(String email, String password) async {
    _setState(AuthState.loading);
    _errorMessage = null;
    try {
      _user = await _authRepository.login(email: email, password: password);
      if (_user != null) {
        await _localStorage.saveCachedUser(_user!);
      }
      if (_user != null && !_user!.emailVerified) {
        _setState(AuthState.unverified);
        return false;
      }
      _setState(AuthState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<bool> loginWithGoogle({
    required String token,
    String? email,
    String? name,
  }) async {
    _setState(AuthState.loading);
    _errorMessage = null;
    try {
      _user = await _authRepository.loginWithGoogle(
        token: token,
        email: email,
        name: name,
      );
      if (_user != null) {
        await _localStorage.saveCachedUser(_user!);
      }
      _setState(AuthState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<bool> loginWithApple({
    required String token,
    String? email,
    String? name,
  }) async {
    _setState(AuthState.loading);
    _errorMessage = null;
    try {
      _user = await _authRepository.loginWithApple(
        token: token,
        email: email,
        name: name,
      );
      if (_user != null) {
        await _localStorage.saveCachedUser(_user!);
      }
      _setState(AuthState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<bool> register(String email, String password, String name) async {
    _setState(AuthState.loading);
    _errorMessage = null;
    try {
      _user = await _authRepository.register(
        email: email,
        password: password,
        displayName: name,
      );
      if (_user != null) {
        await _localStorage.saveCachedUser(_user!);
      }
      _setState(AuthState.unverified);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<void> logout() async {
    _setState(AuthState.loading);
    try {
      await NotificationService().unregisterFcmToken();
    } catch (_) {}
    try {
      await _authRepository.logout();
    } catch (_) {}
    try {
      await fb_auth.FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    await _localStorage.clearCachedUser();
    _user = null;
    _setState(AuthState.idle);
  }

  Future<bool> verifyEmail() async {
    _setState(AuthState.loading);
    try {
      await _authRepository.verifyEmail();
      if (_user != null) {
        _user = _user!.copyWith(
          dietType: _user!.dietType,
        ); // trigger rebuild state
        // Re-check profile to update values
        _user = await _authRepository.getProfile();
        await _localStorage.saveCachedUser(_user!);
      }
      _setState(AuthState.success);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.unverified);
      return false;
    }
  }

  Future<void> resendVerification() async {
    try {
      await _authRepository.resendVerification();
    } catch (e) {
      AppLogger.error('Resend verification failed', e);
    }
  }

  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    _setState(AuthState.loading);
    try {
      await _authRepository.resetPassword(
        token: token,
        newPassword: newPassword,
      );
      _setState(AuthState.idle);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<bool> requestPasswordReset(String email) async {
    _setState(AuthState.loading);
    try {
      await _authRepository.requestPasswordReset(email);
      _setState(AuthState.idle);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<bool> deleteAccount() async {
    _setState(AuthState.loading);
    try {
      await _authRepository.deleteAccount();
      await _localStorage.clearCachedUser();
      _user = null;
      _setState(AuthState.idle);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      return false;
    }
  }

  Future<void> updatePreferences({
    String? displayName,
    String? dietType,
    String? cuisinePref,
    List<String>? allergies,
    int? householdSize,
    bool? notify3Days,
    bool? notify1Day,
    bool? notifyDailyRecipe,
    String? avatarPath,
  }) async {
    if (_user == null) return;
    _setState(AuthState.loading);
    try {
      final updated = await _authRepository.updateProfile({
        if (displayName != null) 'display_name': displayName,
        if (dietType != null) 'diet_type': dietType,
        if (cuisinePref != null) 'cuisine_pref': cuisinePref,
        if (allergies != null) 'allergies': allergies,
        if (householdSize != null) 'household_size': householdSize,
        if (notify3Days != null) 'notify_3_days': notify3Days,
        if (notify1Day != null) 'notify_1_day': notify1Day,
        if (notifyDailyRecipe != null) 'notify_daily_recipe': notifyDailyRecipe,
      }, avatarPath: avatarPath);
      _user = updated;
      await _localStorage.saveCachedUser(_user!);
      _setState(AuthState.success);
    } catch (e) {
      _errorMessage = e.toString();
      _setState(AuthState.error);
      AppLogger.error('Updating preferences failed', e);
    }
  }

  void _setState(AuthState state) {
    _state = state;
    _isLoading = state == AuthState.loading;
    notifyListeners();
    if (state == AuthState.success) {
      _registerFcmToken();
    }
  }

  void _registerFcmToken() {
    try {
      FirebaseMessaging.instance
          .getToken()
          .then((token) {
            if (token != null && token.isNotEmpty) {
              NotificationService().uploadFcmToken(token);
            }
          })
          .catchError((e) {
            AppLogger.debug('FCM token registration skipped/failed: $e');
          });
    } catch (e) {
      AppLogger.debug('FirebaseMessaging unavailable: $e');
    }
  }
}
