// SmartBiz AI — Provisioning API service.
//
// Remote data-source methods for the provisioning endpoints:
//   POST /provisioning/preview
//   POST /provisioning/apply
//   POST /provisioning/{run}/finalize
//   GET  /provisioning/config
//
// Follows the same patterns as BusinessTemplateService and other
// service classes in core/api.

import 'api_client.dart';
import 'provisioning_models.dart';

class ProvisioningService {
  final ApiClient _client;

  ProvisioningService(this._client);

  // ═══════════════════════════════════════════════════════════
  //  Preview
  // ═══════════════════════════════════════════════════════════

  /// POST /api/provisioning/preview
  ///
  /// Generates a dry-run provisioning plan from the given blueprint.
  /// Returns a [PreviewResult] with the plan operations and validation.
  ///
  /// Throws:
  ///   - [NotFoundException] if blueprint_id is invalid (404)
  ///   - [ValidationException] if blueprint validation fails (422)
  ///   - [ConflictException] on concurrent provisioning conflict (409)
  ///   - [ForbiddenException] if user lacks discovery.manage (403)
  ///   - [AuthException] if unauthenticated (401)
  Future<PreviewResult> preview({required String blueprintId}) async {
    final response = await _client.post('/provisioning/preview', data: {
      'blueprint_id': blueprintId,
    });

    final data = response.data as Map<String, dynamic>;
    final resultJson = data['data'] as Map<String, dynamic>? ?? data;
    return PreviewResult.fromJson(resultJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Apply (core foundation only)
  // ═══════════════════════════════════════════════════════════

  /// POST /api/provisioning/apply
  ///
  /// Applies the blueprint provisioning plan — core entities only
  /// (locations, departments, teams, roles, permissions, module flags).
  /// Returns an [ApplyResult] with the created/adopted entities.
  ///
  /// Throws:
  ///   - [NotFoundException] if blueprint_id is invalid (404)
  ///   - [ValidationException] if blueprint validation fails (422)
  ///   - [ConflictException] on concurrent run or status conflict (409)
  ///   - [ForbiddenException] if user lacks discovery.manage (403)
  ///   - [AuthException] if unauthenticated (401)
  Future<ApplyResult> apply({required String blueprintId}) async {
    final response = await _client.post('/provisioning/apply', data: {
      'blueprint_id': blueprintId,
    });

    final data = response.data as Map<String, dynamic>;
    final resultJson = data['data'] as Map<String, dynamic>? ?? data;
    return ApplyResult.fromJson(resultJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Apply Operational
  // ═══════════════════════════════════════════════════════════

  /// POST /api/provisioning/{runId}/apply-operational
  ///
  /// Applies operational entities (warehouses, pipelines, approvals,
  /// commissions, financial settings) after core foundation is in place.
  /// Idempotent — safe to call multiple times.
  ///
  /// Throws:
  ///   - [NotFoundException] if run is not found (404)
  ///   - [ConflictException] if run is not in 'foundation_applied' status (409)
  ///   - [ForbiddenException] if user lacks discovery.manage (403)
  ///   - [AuthException] if unauthenticated (401)
  Future<ApplyResult> applyOperational({required String runId}) async {
    final response = await _client.post('/provisioning/$runId/apply-operational');

    final data = response.data as Map<String, dynamic>;
    final resultJson = data['data'] as Map<String, dynamic>? ?? data;
    return ApplyResult.fromJson(resultJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Finalize
  // ═══════════════════════════════════════════════════════════

  /// POST /api/provisioning/{runId}/finalize
  ///
  /// Finalizes onboarding by assigning the primary_owner role to the
  /// workspace owner and transitioning the run to 'onboarding_complete'.
  /// Idempotent — safe to call multiple times.
  ///
  /// Throws:
  ///   - [NotFoundException] if run is not found (404)
  ///   - [ConflictException] if run is not in 'applied' status (409)
  ///   - [ValidationException] on missing role/binding (422)
  ///   - [ForbiddenException] if user lacks discovery.manage (403)
  ///   - [AuthException] if unauthenticated (401)
  Future<FinalizeResult> finalize({required String runId}) async {
    final response = await _client.post('/provisioning/$runId/finalize');

    final data = response.data as Map<String, dynamic>;
    final resultJson = data['data'] as Map<String, dynamic>? ?? data;
    return FinalizeResult.fromJson(resultJson);
  }

  // ═══════════════════════════════════════════════════════════
  //  Config / Status Retrieval
  // ═══════════════════════════════════════════════════════════

  /// GET /api/provisioning/config
  ///
  /// Retrieves the active provisioning configuration for the workspace.
  /// Returns null if no configuration has been applied yet.
  ///
  /// The response includes the full run data including status, which
  /// can be used to determine the current provisioning phase.
  Future<ProvisioningRun?> getActiveConfig() async {
    final response = await _client.get('/provisioning/config');

    final data = response.data as Map<String, dynamic>;
    final configJson = data['data'] as Map<String, dynamic>?;
    if (configJson == null) return null;
    return ProvisioningRun.fromJson(configJson);
  }
}
