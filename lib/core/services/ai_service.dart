import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../utils/app_logger.dart';

abstract class IAIService {
  /// Predicts shelf life of a grocery item
  Future<Map<String, dynamic>> predictShelfLife(Map<String, dynamic> data);

  /// Fetches natural language AI dashboard insights
  Future<Map<String, dynamic>> fetchAIInsights();
}

class AIServiceImpl implements IAIService {
  final ApiClient _apiClient = ApiClient();

  @override
  Future<Map<String, dynamic>> predictShelfLife(Map<String, dynamic> data) async {
    try {
      final response = await _apiClient.post(
        ApiEndpoints.predictShelfLife,
        data: data,
      );
      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.error('Failed to call remote predictShelfLife, using local fallback estimation', e);
    }
    
    // Fallback to local prediction logic if backend is offline or errors
    return _localPredictionFallback(data);
  }

  @override
  Future<Map<String, dynamic>> fetchAIInsights() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.aiInsights);
      if (response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
    } catch (e) {
      AppLogger.error('Failed to fetch AI Insights', e);
    }
    return {
      'insights': [
        'Could not fetch live insights. Try checking your internet connection.',
        'Store fresh vegetables in high humidity to prevent wilting.',
        'Label food containers with consumption dates to track freshness.'
      ],
      'waste_risk': 0.0,
      'freshness_score': 100,
    };
  }

  Map<String, dynamic> _localPredictionFallback(Map<String, dynamic> data) {
    final String category = (data['category'] ?? 'default').toString().toLowerCase();
    final String name = (data['name'] ?? '').toString().toLowerCase();
    final bool isBeverage = category == 'beverages' || category == 'beverage' ||
        ['carbonated', 'soda', 'coke', 'pepsi', 'sprite', 'fanta', 'drink', 'beverage'].any((k) => name.contains(k));
    final String zone = isBeverage ? 'fridge' : (data['storage_zone'] ?? 'pantry').toString().toLowerCase();
    final double temp = double.tryParse(data['temperature']?.toString() ?? '20.0') ?? 20.0;
    final double humidity = double.tryParse(data['humidity']?.toString() ?? '50.0') ?? 50.0;
    final String ripeness = (data['ripeness'] ?? 'not_applicable').toString().toLowerCase();
    final bool opened = data['is_opened'] == true;
    final int freshness = int.tryParse(data['freshness_score']?.toString() ?? '100') ?? 100;
    final DateTime purchaseDate = DateTime.tryParse(data['purchase_date']?.toString() ?? '') ?? DateTime.now();

    int baseDays = 14;
    switch (category) {
      case 'fruits':
        baseDays = 10;
        break;
      case 'vegetables':
        baseDays = 7;
        break;
      case 'dairy':
        baseDays = 14;
        break;
      case 'meat':
        baseDays = 5;
        break;
      case 'fish':
        baseDays = 3;
        break;
      case 'beverages':
        baseDays = 30;
        break;
      case 'grains':
        baseDays = 180;
        break;
      case 'spices':
        baseDays = 365;
        break;
      case 'bakery':
        baseDays = 4;
        break;
    }

    double estDays = baseDays * (freshness / 100.0);

    // Temp penalties
    if (zone == 'fridge' && temp > 6.0) {
      estDays *= 0.7;
    } else if (zone == 'pantry' && temp > 25.0) {
      estDays *= 0.8;
    }

    // Humidity penalty
    if (zone == 'pantry' && humidity > 70.0) {
      estDays *= 0.9;
    }

    // Opened penalty
    if (opened) {
      estDays *= 0.4;
    }

    // Ripeness penalty
    if (ripeness == 'overripe') {
      estDays *= 0.25;
    } else if (ripeness == 'unripe') {
      estDays *= 1.2;
    }

    final int remainingDays = estDays.clamp(0.5, 365.0).round();
    final predictedExpiry = purchaseDate.add(Duration(days: remainingDays));
    final recommendedConsumption = purchaseDate.add(Duration(days: (remainingDays * 0.8).round()));

    String why = 'Clean, dry storage slows enzymatic spoilage.';
    String how = 'Place in sealed containers or zip bags.';
    if (isBeverage || category == 'beverages') {
      why = 'Chilling preserves carbonation fizz and refreshing flavor.';
      how = 'Store upright on refrigerator shelves (2-5°C). Never freeze cans or glass bottles.';
    } else if (category == 'dairy') {
      why = 'Cold temperature keeps bacteria dormant.';
      how = 'Keep in the main fridge compartments, not the door.';
    } else if (category == 'vegetables' || category == 'fruits') {
      why = 'Slows cellular respiration rates.';
      how = 'Crisper drawers work best for humidity regulation.';
    }

    return {
      'estimated_remaining_days': remainingDays.toDouble(),
      'confidence': opened ? 'Low' : 'High',
      'predicted_expiry': predictedExpiry.toIso8601String().substring(0, 10),
      'recommended_consumption_date': recommendedConsumption.toIso8601String().substring(0, 10),
      'storage_recommendation_why': why,
      'storage_recommendation_how': how,
      'storage_recommendation_shelf_life': 'Est. remaining: $remainingDays days.',
      'ai_explanation': 'Local prediction fallback calculation.',
    };
  }
}
