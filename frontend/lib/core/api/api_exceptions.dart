// SmartBiz AI — API exception types.
//
// Typed exceptions for API error handling. Screens and services catch
// these instead of raw Dio errors.

/// Base API exception.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// 401 — token expired, invalid, or missing.
class AuthException extends ApiException {
  const AuthException([super.message = 'Unauthenticated.'])
      : super(statusCode: 401);
}

/// 422 — validation failed, with per-field error messages.
class ValidationException extends ApiException {
  /// Per-field error messages from backend.
  /// Example: `{'email': ['The email field is required.']}`
  final Map<String, List<String>> errors;

  const ValidationException({
    String message = 'Validation failed.',
    this.errors = const {},
  }) : super(message, statusCode: 422);

  /// Flat list of all error messages.
  List<String> get allMessages =>
      errors.values.expand((msgs) => msgs).toList();

  /// First error message, useful for SnackBar display.
  String? get firstMessage {
    for (final msgs in errors.values) {
      if (msgs.isNotEmpty) return msgs.first;
    }
    return null;
  }

  @override
  String toString() => 'ValidationException: $message — $errors';
}

/// Network unreachable, timeout, DNS failure, etc.
class NetworkException extends ApiException {
  const NetworkException([super.message = 'Network error. Check your connection.']);
}
