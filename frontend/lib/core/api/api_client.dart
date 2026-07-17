// SmartBiz AI — API Client.
//
// Central Dio-based HTTP client for all backend communication.
//
// Features:
//   - Auto-attaches auth token from secure storage
//   - Auto-attaches X-Workspace-Id header when set
//   - Converts Dio errors into typed ApiExceptions
//   - Configurable base URL via ApiConfig
//
// Usage:
//   final client = ApiClient();
//   final response = await client.get('/products');

import 'package:dio/dio.dart';
import 'api_config.dart';
import 'api_exceptions.dart';
import 'token_storage.dart';

class ApiClient {
  late final Dio _dio;

  /// Optional callback to get the active workspace ID.
  /// Set this after AppState is wired (Step 40+).
  String? Function()? workspaceIdProvider;

  /// Callback invoked on 401 responses.
  /// Set this to trigger sign-out / redirect (Step 40+).
  void Function()? onAuthError;

  ApiClient({this.workspaceIdProvider, this.onAuthError}) {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  // ═══════════════════════════════════════════════════════════
  //  Workspace ID Management
  // ═══════════════════════════════════════════════════════════

  String? _workspaceId;

  /// Set the active workspace ID for all subsequent requests.
  void setWorkspaceId(String? workspaceId) {
    _workspaceId = workspaceId;
  }

  /// Current workspace ID (from explicit set or provider callback).
  String? get _effectiveWorkspaceId =>
      _workspaceId ?? workspaceIdProvider?.call();

  // ═══════════════════════════════════════════════════════════
  //  HTTP Methods
  // ═══════════════════════════════════════════════════════════

  /// GET request.
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// POST request.
  Future<Response<dynamic>> post(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.post(path, data: data);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// PUT request.
  Future<Response<dynamic>> put(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.put(path, data: data);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  /// DELETE request.
  Future<Response<dynamic>> delete(
    String path, {
    Object? data,
  }) async {
    try {
      return await _dio.delete(path, data: data);
    } on DioException catch (e) {
      throw _mapException(e);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Interceptors
  // ═══════════════════════════════════════════════════════════

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Attach auth token if available.
    final token = await TokenStorage.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    // Attach workspace ID if available.
    final wsId = _effectiveWorkspaceId;
    if (wsId != null && wsId.isNotEmpty) {
      options.headers['X-Workspace-Id'] = wsId;
    }

    handler.next(options);
  }

  void _onError(DioException error, ErrorInterceptorHandler handler) {
    // Notify listener on 401 (token expired / invalid).
    if (error.response?.statusCode == 401) {
      onAuthError?.call();
    }
    handler.next(error);
  }

  // ═══════════════════════════════════════════════════════════
  //  Error Mapping
  // ═══════════════════════════════════════════════════════════

  ApiException _mapException(DioException e) {
    final response = e.response;

    // No response at all — network issue.
    if (response == null) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return const NetworkException('Request timed out.');
      }
      return const NetworkException();
    }

    final statusCode = response.statusCode ?? 0;
    final data = response.data;
    final message = data is Map ? (data['message'] as String? ?? 'Error') : 'Error';

    // 401 — Unauthenticated
    if (statusCode == 401) {
      return AuthException(message);
    }

    // 403 — Forbidden
    if (statusCode == 403) {
      return ForbiddenException(message);
    }

    // 404 — Not Found
    if (statusCode == 404) {
      final errorCode = data is Map ? data['error'] as String? : null;
      return NotFoundException(message: message, errorCode: errorCode);
    }

    // 422 — Validation
    if (statusCode == 422) {
      final rawErrors = data is Map ? data['errors'] : null;
      final errors = <String, List<String>>{};
      if (rawErrors is Map) {
        for (final entry in rawErrors.entries) {
          final key = entry.key.toString();
          final value = entry.value;
          if (value is List) {
            errors[key] = value.map((v) => v.toString()).toList();
          }
        }
      }
      return ValidationException(message: message, errors: errors);
    }

    // 409 — Conflict (duplicate contact, open deal, etc.)
    if (statusCode == 409) {
      final errorCode = data is Map ? data['error_code'] as String? : null;
      final existing = data is Map && data['existing'] is Map
          ? Map<String, dynamic>.from(data['existing'] as Map)
          : null;
      return ConflictException(
        message: message,
        errorCode: errorCode,
        existing: existing,
      );
    }

    // Everything else
    return ApiException(message, statusCode: statusCode);
  }
}
