import '../../config/app_config.dart';

class ApiEndpoints {
  static const String baseUrl = AppConfig.baseUrl;

  // Health check & warm-up
  static const String health = '/health/';

  // Authentication
  static const String register = '/auth/register/';
  static const String login = '/auth/login/';
  static const String refresh = '/auth/token/refresh/';
  static const String logout = '/auth/logout/';
  static const String me = '/auth/me/';
  static const String forgotPassword = '/auth/forgot-password/';
  static const String resetPassword = '/auth/reset-password/';
  static const String verifyEmail = '/auth/verify-email/';
  static const String resendVerification = '/auth/resend-verification/';
  static const String googleLogin = '/auth/google/';
  static const String appleLogin = '/auth/apple/';

  // Groceries
  static const String groceries = '/groceries/';
  static String groceryDetail(String id) => '/groceries/$id/';
  static String adjustQuantity(String id) => '/groceries/$id/adjust-quantity/';
  static String consume(String id) => '/groceries/$id/consume/';
  static String waste(String id) => '/groceries/$id/waste/';
  static const String useFirst = '/groceries/use-first/';
  static const String stats = '/groceries/stats/';
  static const String zones = '/groceries/zones/';
  static const String predictShelfLife = '/groceries/predict-shelf-life/';
  static const String aiInsights = '/groceries/ai-insights/';

  // Scans
  static const String scans = '/scans/';
  static const String scanSessions = '/scans/sessions/';
  static String scanDetail(String id) => '/scans/sessions/$id/';
  static String scanCandidates(String id) => '/scans/sessions/$id/candidates/';
  static String scanCandidateDetail(String sessionId, String candidateId) =>
      '/scans/sessions/$sessionId/candidates/$candidateId/';
  static String retryImage(String id) => '/scans/sessions/$id/retry-image/';
  static String mergeCandidates(String id) =>
      '/scans/sessions/$id/merge-candidates/';
  static String confirmScan(String id) => '/scans/sessions/$id/confirm/';

  // Recipes
  static const String recipes = '/recipes/';
  static const String generateRecipes = '/recipes/generate/';
  static String recipeDetail(String id) => '/recipes/$id/';
  static String markCooked(String id) => '/recipes/$id/mark-cooked/';

  // Grocery List
  static const String currentGroceryList = '/grocery-lists/current/';
  static const String generateGroceryList = '/grocery-lists/generate/';
  static String groceryListDetail(String id) => '/grocery-lists/$id/';
  static String groceryListItems(String id) => '/grocery-lists/$id/items/';
  static String groceryListItemDetail(String listId, String itemId) =>
      '/grocery-lists/$listId/items/$itemId/';
  static String itemFeedback(String listId, String itemId) =>
      '/grocery-lists/$listId/items/$itemId/feedback/';
  static String markPurchased(String listId, String itemId) =>
      '/grocery-lists/$listId/items/$itemId/mark-purchased/';

  // Profile
  static const String profile = '/profile/';
  static const String deleteAccount = '/profile/account/';

  // Notifications
  static const String deviceToken = '/notifications/device-token/';
  static const String notificationPreferences = '/notifications/preferences/';

  // Meals
  static const String meals = '/meals/';
  static String mealDetail(String id) => '/meals/$id/';
  static String confirmMealDeduction(String id) =>
      '/meals/$id/confirm-deduction/';
}
