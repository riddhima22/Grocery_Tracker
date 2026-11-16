class AppConfig {
  static const String defaultBaseUrl =
      'https://grocery-tracker-backend-rcwl.onrender.com/api/v1';

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );
}
