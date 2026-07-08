// SmartBiz AI — API base URL configuration.
//
// Uses compile-time environment for flexibility:
//   flutter run --dart-define=API_BASE_URL=https://api.smartbiz.ai
//
// Defaults to local Docker backend for development.

class ApiConfig {
  ApiConfig._();

  /// Base URL for all API requests.
  ///
  /// Override at build time:
  /// ```
  /// flutter run --dart-define=API_BASE_URL=https://api.smartbiz.ai
  /// ```
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080/api',
  );

  /// Default request timeout.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Default response timeout.
  static const Duration receiveTimeout = Duration(seconds: 30);
}
