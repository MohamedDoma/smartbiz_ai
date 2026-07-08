// SmartBiz AI — Auth Service.
//
// Handles login, logout, registration, and session restore via the backend API.
// Uses ApiClient for HTTP and TokenStorage for secure persistence.

import 'api_client.dart';
import 'api_exceptions.dart';
import 'auth_models.dart';
import 'token_storage.dart';

class AuthService {
  final ApiClient _client;

  AuthService(this._client);

  /// Login with email + password.
  ///
  /// On success: stores token, returns full AuthSession.
  /// On failure: throws AuthException, ValidationException, or NetworkException.
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    final data = response.data as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);

    // Store the token securely.
    final token = session.token;
    if (token != null && token.isNotEmpty) {
      await TokenStorage.writeToken(token);
    }

    return session;
  }

  /// Restore session from stored token.
  ///
  /// Calls GET /auth/me with the stored Bearer token.
  /// Returns null if no token is stored.
  /// Throws on network/server errors.
  Future<AuthSession?> me() async {
    final token = await TokenStorage.readToken();
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _client.get('/auth/me');
      final data = response.data as Map<String, dynamic>;
      return AuthSession.fromJson(data);
    } on AuthException {
      // Token expired or invalid — clear it.
      await TokenStorage.clearToken();
      return null;
    }
  }

  /// Logout — revoke server token + clear local storage.
  ///
  /// Always clears local token even if the API call fails
  /// (e.g., network error, already expired).
  Future<void> logout() async {
    try {
      await _client.post('/auth/logout');
    } on ApiException {
      // Ignore — we clear locally regardless.
    } finally {
      await TokenStorage.clearToken();
    }
  }

  /// Register a new business owner with their workspace.
  ///
  /// On success: stores token, returns full AuthSession.
  /// On failure: throws ValidationException, NetworkException, or ApiException.
  Future<AuthSession> registerBusinessOwner({
    required String fullName,
    required String email,
    required String phoneNumber,
    required String password,
    required String passwordConfirmation,
    required String workspaceName,
    String? businessType,
    String? businessSize,
    String? preferredLocale,
  }) async {
    final response = await _client.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'phone_number': phoneNumber,
      'password': password,
      'password_confirmation': passwordConfirmation,
      'workspace_name': workspaceName,
      'business_name': workspaceName, // backend accepts either
      if (businessType != null) 'business_type': businessType,
      if (businessSize != null) 'business_size': businessSize,
      if (preferredLocale != null) 'preferred_locale': preferredLocale,
    });

    final data = response.data as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);

    // Store the token securely.
    final token = session.token;
    if (token != null && token.isNotEmpty) {
      await TokenStorage.writeToken(token);
    }

    return session;
  }
}
