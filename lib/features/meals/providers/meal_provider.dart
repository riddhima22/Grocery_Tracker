import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/models/meal_log_model.dart';
import '../../../data/repositories/meal_repository.dart';
import '../../../core/utils/app_logger.dart';

enum MealUIState { idle, analyzing, review, success, error }

class MealProvider extends ChangeNotifier {
  final MealRepository _mealRepository = MealRepository();

  MealUIState _uiState = MealUIState.idle;
  String? _errorMessage;
  MealLogModel? _currentMealLog;
  List<MealLogModel> _recentMeals = [];

  // Editable candidate deduction map: candidate_id -> {confirmed: bool, quantity: double}
  final Map<String, Map<String, dynamic>> _deductionEdits = {};

  MealUIState get uiState => _uiState;
  String? get errorMessage => _errorMessage;
  MealLogModel? get currentMealLog => _currentMealLog;
  List<MealLogModel> get recentMeals => _recentMeals;
  Map<String, Map<String, dynamic>> get deductionEdits => _deductionEdits;

  Future<void> logMeal({XFile? image, String? description}) async {
    _uiState = MealUIState.analyzing;
    _errorMessage = null;
    notifyListeners();

    try {
      final mealLog = await _mealRepository.createMealLog(
        image: image,
        description: description,
      );
      _currentMealLog = mealLog;
      _initEdits(mealLog);
      _uiState = MealUIState.review;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _uiState = MealUIState.error;
      notifyListeners();
    }
  }

  void _initEdits(MealLogModel mealLog) {
    _deductionEdits.clear();
    for (var c in mealLog.candidates) {
      _deductionEdits[c.id] = {
        'confirmed': c.confirmed,
        'quantity': c.deductQuantity,
      };
    }
  }

  void updateCandidateConfirmation(String candidateId, bool confirmed) {
    if (_deductionEdits.containsKey(candidateId)) {
      _deductionEdits[candidateId]!['confirmed'] = confirmed;
      notifyListeners();
    }
  }

  void updateCandidateQuantity(String candidateId, double quantity) {
    if (_deductionEdits.containsKey(candidateId)) {
      _deductionEdits[candidateId]!['quantity'] = quantity;
      notifyListeners();
    }
  }

  Future<bool> confirmDeduction() async {
    if (_currentMealLog == null) return false;

    _uiState = MealUIState.analyzing;
    notifyListeners();

    try {
      final List<Map<String, dynamic>> payload = [];
      _deductionEdits.forEach((candId, data) {
        payload.add({
          'candidate_id': candId,
          'confirmed': data['confirmed'],
          'quantity': data['quantity'],
        });
      });

      final updated = await _mealRepository.confirmDeduction(
        _currentMealLog!.id,
        payload,
      );
      _currentMealLog = updated;
      _uiState = MealUIState.success;
      await fetchRecentMeals();
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _uiState = MealUIState.review;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchRecentMeals() async {
    try {
      _recentMeals = await _mealRepository.getMealLogs();
      notifyListeners();
    } catch (e) {
      AppLogger.error('Failed to fetch meal logs', e);
    }
  }

  void reset() {
    _uiState = MealUIState.idle;
    _currentMealLog = null;
    _errorMessage = null;
    _deductionEdits.clear();
    notifyListeners();
  }
}
