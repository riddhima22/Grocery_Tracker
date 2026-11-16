import 'package:flutter/material.dart';
import '../../../core/services/local_storage_service.dart';

class OnboardingProvider extends ChangeNotifier {
  final LocalStorageService _localStorage = LocalStorageService();
  bool _onboardingComplete = false;

  bool get onboardingComplete => _onboardingComplete;

  Future<void> checkOnboardingStatus() async {
    _onboardingComplete = await _localStorage.isOnboardingComplete();
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await _localStorage.setOnboardingComplete(true);
    _onboardingComplete = true;
    notifyListeners();
  }
}
