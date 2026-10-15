import 'package:flutter/material.dart';
import '../../../data/models/recipe_model.dart';
import '../../../data/repositories/recipe_repository.dart';
import '../../../core/utils/app_logger.dart';

class RecipeProvider extends ChangeNotifier {
  final RecipeRepository _recipeRepository = RecipeRepository();

  List<RecipeModel> _recipes = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _filter = 'all'; // all, veg, non-veg, quick

  List<RecipeModel> get recipes => _filteredRecipes();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get filter => _filter;

  void setFilter(String val) {
    _filter = val;
    notifyListeners();
  }

  Future<void> fetchRecipes() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _recipes = await _recipeRepository.getRecipes();
      _isLoading = false;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      AppLogger.error('Failed to load recipes', e);
    }
    notifyListeners();
  }

  Future<bool> generateNewRecipes({Map<String, dynamic>? preferences}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final newRecipes = await _recipeRepository.generateRecipes(
        preferences: preferences,
      );
      _recipes.insertAll(0, newRecipes);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      AppLogger.error('Failed to generate recipes', e);
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAsCooked(String id) async {
    try {
      await _recipeRepository.markCooked(id);
      return true;
    } catch (e) {
      AppLogger.error('Failed to log recipe cook', e);
      return false;
    }
  }

  List<RecipeModel> _filteredRecipes() {
    if (_filter == 'veg') {
      return _recipes.where((r) => r.dietType.toLowerCase() == 'veg').toList();
    } else if (_filter == 'non-veg') {
      return _recipes
          .where((r) => r.dietType.toLowerCase() == 'non-veg')
          .toList();
    } else if (_filter == 'quick') {
      return _recipes.where((r) => r.prepTimeMins <= 30).toList();
    }
    return _recipes;
  }
}
