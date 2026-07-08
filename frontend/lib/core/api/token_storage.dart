// SmartBiz AI — Secure token storage.
//
// Wraps flutter_secure_storage for reading, writing, and clearing
// the Sanctum API token. No logging of token values.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  TokenStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _tokenKey = 'smartbiz_auth_token';

  /// Read the stored auth token. Returns null if not set.
  static Future<String?> readToken() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  /// Write a new auth token to secure storage.
  static Future<void> writeToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  /// Clear the stored auth token (logout / session expiry).
  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
  }
}
