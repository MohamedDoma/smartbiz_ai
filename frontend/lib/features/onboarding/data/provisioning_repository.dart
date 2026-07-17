// SmartBiz AI — Provisioning Repository.
//
// Wraps ProvisioningService (remote data-source) with domain-level error
// handling, logging, and result types. This is the interface consumed by
// BLoCs/state — never the raw service directly.

import '../../../core/api/api_exceptions.dart';
import '../../../core/api/provisioning_models.dart';
import '../../../core/api/provisioning_service.dart';

// ═══════════════════════════════════════════════════════════
//  Result Types
// ═══════════════════════════════════════════════════════════

/// Sealed-style result for provisioning operations.
///
/// Callers switch on [isSuccess] or [errorType] to handle outcomes
/// without catching exceptions in the UI layer.
class ProvisioningResult<T> {
  final T? data;
  final ProvisioningError? error;

  const ProvisioningResult._({this.data, this.error});

  factory ProvisioningResult.success(T data) =>
      ProvisioningResult._(data: data);

  factory ProvisioningResult.failure(ProvisioningError error) =>
      ProvisioningResult._(error: error);

  bool get isSuccess => data != null && error == null;
  bool get isFailure => !isSuccess;

  /// Convenience: the error type for switch/if matching.
  ProvisioningErrorType get errorType {
    if (error == null) return ProvisioningErrorType.none;
    switch (error!.statusCode) {
      case 401:
        return ProvisioningErrorType.unauthorized;
      case 403:
        return ProvisioningErrorType.forbidden;
      case 404:
        return ProvisioningErrorType.notFound;
      case 409:
        return ProvisioningErrorType.conflict;
      case 422:
        return ProvisioningErrorType.validation;
      default:
        if (error!.statusCode >= 500) {
          return ProvisioningErrorType.server;
        }
        return ProvisioningErrorType.network;
    }
  }
}

enum ProvisioningErrorType {
  none,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  validation,
  server,
  network,
}

// ═══════════════════════════════════════════════════════════
//  Repository
// ═══════════════════════════════════════════════════════════

class ProvisioningRepository {
  final ProvisioningService _service;

  ProvisioningRepository(this._service);

  /// Preview a blueprint provisioning plan.
  Future<ProvisioningResult<PreviewResult>> preview({
    required String blueprintId,
  }) async {
    try {
      final result = await _service.preview(blueprintId: blueprintId);
      return ProvisioningResult.success(result);
    } on ApiException catch (e) {
      return ProvisioningResult.failure(
        _mapApiException(e),
      );
    } catch (e) {
      return ProvisioningResult.failure(
        ProvisioningError(
          message: e.toString(),
          statusCode: 0,
        ),
      );
    }
  }

  /// Apply the provisioning plan (core foundation entities).
  Future<ProvisioningResult<ApplyResult>> apply({
    required String blueprintId,
  }) async {
    try {
      final result = await _service.apply(blueprintId: blueprintId);
      return ProvisioningResult.success(result);
    } on ApiException catch (e) {
      return ProvisioningResult.failure(
        _mapApiException(e),
      );
    } catch (e) {
      return ProvisioningResult.failure(
        ProvisioningError(
          message: e.toString(),
          statusCode: 0,
        ),
      );
    }
  }

  /// Apply operational entities (warehouses, pipelines, approvals, etc.).
  Future<ProvisioningResult<ApplyResult>> applyOperational({
    required String runId,
  }) async {
    try {
      final result = await _service.applyOperational(runId: runId);
      return ProvisioningResult.success(result);
    } on ApiException catch (e) {
      return ProvisioningResult.failure(
        _mapApiException(e),
      );
    } catch (e) {
      return ProvisioningResult.failure(
        ProvisioningError(
          message: e.toString(),
          statusCode: 0,
        ),
      );
    }
  }

  /// Finalize onboarding for a provisioning run.
  Future<ProvisioningResult<FinalizeResult>> finalize({
    required String runId,
  }) async {
    try {
      final result = await _service.finalize(runId: runId);
      return ProvisioningResult.success(result);
    } on ApiException catch (e) {
      return ProvisioningResult.failure(
        _mapApiException(e),
      );
    } catch (e) {
      return ProvisioningResult.failure(
        ProvisioningError(
          message: e.toString(),
          statusCode: 0,
        ),
      );
    }
  }

  /// Get the active provisioning config/status for the workspace.
  Future<ProvisioningResult<ProvisioningRun?>> getActiveConfig() async {
    try {
      final result = await _service.getActiveConfig();
      return ProvisioningResult.success(result);
    } on ApiException catch (e) {
      return ProvisioningResult.failure(
        _mapApiException(e),
      );
    } catch (e) {
      return ProvisioningResult.failure(
        ProvisioningError(
          message: e.toString(),
          statusCode: 0,
        ),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Error Mapping
  // ═══════════════════════════════════════════════════════════

  ProvisioningError _mapApiException(ApiException e) {
    String? errorCode;

    if (e is ConflictException) {
      errorCode = e.errorCode;
    } else if (e is NotFoundException) {
      errorCode = e.errorCode;
    }

    return ProvisioningError(
      message: e.message,
      errorCode: errorCode,
      statusCode: e.statusCode ?? 0,
    );
  }
}
