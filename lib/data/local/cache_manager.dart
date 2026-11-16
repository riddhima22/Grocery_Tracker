import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/grocery_model.dart';
import '../../core/utils/app_logger.dart';

class CacheManager {
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  static const String _keyGroceries = 'cached_groceries_list_v1';
  static const String _keyGroceriesTimestamp = 'cached_groceries_timestamp_v1';
  static const String _keyAIInsights = 'cached_ai_insights_v1';
  static const String _keyAIInsightsTimestamp =
      'cached_ai_insights_timestamp_v1';

  /// Save grocery list to local cache
  Future<void> saveGroceries(List<GroceryModel> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = items.map((item) => item.toJson()).toList();
      await prefs.setString(_keyGroceries, jsonEncode(jsonList));
      await prefs.setInt(
        _keyGroceriesTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.error('Failed to save groceries to cache', e);
    }
  }

  /// Read cached groceries from local cache
  Future<List<GroceryModel>> getCachedGroceries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyGroceries);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .map(
              (item) => GroceryModel.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList();
      }
    } catch (e) {
      AppLogger.error('Failed to read groceries from cache', e);
    }
    return [];
  }

  /// Check if the cached groceries are older than [duration]
  Future<bool> isGroceriesCacheStale({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_keyGroceriesTimestamp);
      if (timestamp == null) return true;
      final cacheAge = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
      return cacheAge > maxAge;
    } catch (_) {
      return true;
    }
  }

  /// Save AI insights to local cache
  Future<void> saveAIInsights(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAIInsights, jsonEncode(data));
      await prefs.setInt(
        _keyAIInsightsTimestamp,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (e) {
      AppLogger.error('Failed to save AI insights to cache', e);
    }
  }

  /// Read cached AI insights from local cache
  Future<Map<String, dynamic>?> getCachedAIInsights() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyAIInsights);
      if (raw != null && raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw));
      }
    } catch (e) {
      AppLogger.error('Failed to read AI insights from cache', e);
    }
    return null;
  }

  /// Clear all cached grocery data (e.g. on logout)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyGroceries);
      await prefs.remove(_keyGroceriesTimestamp);
      await prefs.remove(_keyAIInsights);
      await prefs.remove(_keyAIInsightsTimestamp);
    } catch (e) {
      AppLogger.error('Failed to clear cache', e);
    }
  }
}
