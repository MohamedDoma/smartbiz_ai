// SmartBiz AI — Provisioning API models.
//
// Dart models that map to backend /provisioning/* responses.
// All fromJson constructors handle missing/null values safely.

// ═══════════════════════════════════════════════════════════
//  Provisioning Run Status
// ═══════════════════════════════════════════════════════════

/// Enum matching backend ProvisioningRun status constants.
enum ProvisioningRunStatus {
  preview,
  prepared,
  processing,
  foundationApplied,
  applied,
  onboardingComplete,
  rolledBack,
  failed,
  unknown;

  /// Parse a backend status string into the enum.
  static ProvisioningRunStatus fromString(String? value) {
    switch (value) {
      case 'preview':
        return ProvisioningRunStatus.preview;
      case 'prepared':
        return ProvisioningRunStatus.prepared;
      case 'processing':
        return ProvisioningRunStatus.processing;
      case 'foundation_applied':
        return ProvisioningRunStatus.foundationApplied;
      case 'applied':
        return ProvisioningRunStatus.applied;
      case 'onboarding_complete':
        return ProvisioningRunStatus.onboardingComplete;
      case 'rolled_back':
        return ProvisioningRunStatus.rolledBack;
      case 'failed':
        return ProvisioningRunStatus.failed;
      default:
        return ProvisioningRunStatus.unknown;
    }
  }

  /// Whether this status represents a successfully completed onboarding.
  bool get isOnboardingDone =>
      this == ProvisioningRunStatus.applied ||
      this == ProvisioningRunStatus.onboardingComplete;
}

// ═══════════════════════════════════════════════════════════
//  Provisioning Run
// ═══════════════════════════════════════════════════════════

/// A provisioning run as returned by the backend.
class ProvisioningRun {
  final String id;
  final String workspaceId;
  final String? blueprintId;
  final ProvisioningRunStatus status;
  final int version;
  final Map<String, dynamic> config;
  final String? createdAt;
  final String? updatedAt;

  const ProvisioningRun({
    required this.id,
    required this.workspaceId,
    this.blueprintId,
    this.status = ProvisioningRunStatus.unknown,
    this.version = 1,
    this.config = const {},
    this.createdAt,
    this.updatedAt,
  });

  factory ProvisioningRun.fromJson(Map<String, dynamic> json) =>
      ProvisioningRun(
        id: json['id'] as String? ?? '',
        workspaceId: json['workspace_id'] as String? ?? '',
        blueprintId: json['blueprint_id'] as String?,
        status: ProvisioningRunStatus.fromString(json['status'] as String?),
        version: json['version'] as int? ?? 1,
        config: json['config'] is Map
            ? Map<String, dynamic>.from(json['config'] as Map)
            : const {},
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );
}

// ═══════════════════════════════════════════════════════════
//  Preview Result
// ═══════════════════════════════════════════════════════════

/// Operation summary within a preview plan.
class PreviewOperation {
  final String entityType;
  final String action;
  final String? key;
  final String? name;

  const PreviewOperation({
    required this.entityType,
    required this.action,
    this.key,
    this.name,
  });

  factory PreviewOperation.fromJson(Map<String, dynamic> json) =>
      PreviewOperation(
        entityType: json['entity_type'] as String? ?? '',
        action: json['action'] as String? ?? 'create',
        key: json['key'] as String?,
        name: json['name'] as String?,
      );
}

/// Result of POST /api/provisioning/preview.
class PreviewResult {
  final String runId;
  final String status;
  final int version;
  final Map<String, dynamic> plan;
  final List<String> validationErrors;

  const PreviewResult({
    required this.runId,
    required this.status,
    this.version = 1,
    this.plan = const {},
    this.validationErrors = const [],
  });

  bool get isValid => status != 'validation_failed';

  factory PreviewResult.fromJson(Map<String, dynamic> json) {
    final errors = json['validation_errors'] as List<dynamic>? ?? [];
    return PreviewResult(
      runId: json['run_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      plan: json['plan'] is Map
          ? Map<String, dynamic>.from(json['plan'] as Map)
          : const {},
      validationErrors: errors.map((e) => e.toString()).toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Apply Result
// ═══════════════════════════════════════════════════════════

/// Entity created during provisioning apply.
class ProvisionedEntity {
  final String entityType;
  final String entityId;
  final String? key;
  final String? name;
  final String action;

  const ProvisionedEntity({
    required this.entityType,
    required this.entityId,
    this.key,
    this.name,
    this.action = 'created',
  });

  factory ProvisionedEntity.fromJson(Map<String, dynamic> json) =>
      ProvisionedEntity(
        entityType: json['entity_type'] as String? ?? '',
        entityId: json['entity_id'] as String? ?? '',
        key: json['key'] as String?,
        name: json['name'] as String?,
        action: json['action'] as String? ?? 'created',
      );
}

/// Result of POST /api/provisioning/apply.
///
/// Covers both core and operational apply — the response shapes are
/// identical; the backend combines both phases in a single call.
class ApplyResult {
  final String runId;
  final String status;
  final String workspaceId;
  final int entitiesCreated;
  final int entitiesAdopted;
  final List<ProvisionedEntity> entities;
  final bool alreadyApplied;
  final String? activeRunId;
  final String? message;

  const ApplyResult({
    required this.runId,
    required this.status,
    this.workspaceId = '',
    this.entitiesCreated = 0,
    this.entitiesAdopted = 0,
    this.entities = const [],
    this.alreadyApplied = false,
    this.activeRunId,
    this.message,
  });

  factory ApplyResult.fromJson(Map<String, dynamic> json) {
    final entityList = json['entities'] as List<dynamic>? ?? [];
    return ApplyResult(
      runId: json['run_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      entitiesCreated: json['entities_created'] as int? ?? 0,
      entitiesAdopted: json['entities_adopted'] as int? ?? 0,
      entities: entityList
          .whereType<Map<String, dynamic>>()
          .map(ProvisionedEntity.fromJson)
          .toList(),
      alreadyApplied: json['already_applied'] as bool? ?? false,
      activeRunId: json['active_run'] is Map
          ? (json['active_run'] as Map)['run_id'] as String?
          : json['active_run_id'] as String?,
      message: json['message'] as String?,
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Finalize Result
// ═══════════════════════════════════════════════════════════

/// Primary owner role info from finalization.
class FinalizeOwnerRole {
  final String key;
  final String id;
  final String? name;

  const FinalizeOwnerRole({
    required this.key,
    required this.id,
    this.name,
  });

  factory FinalizeOwnerRole.fromJson(Map<String, dynamic> json) =>
      FinalizeOwnerRole(
        key: json['key'] as String? ?? '',
        id: json['id'] as String? ?? '',
        name: json['name'] as String?,
      );
}

/// Owner membership info from finalization.
class FinalizeOwnerMembership {
  final String id;
  final String userId;

  const FinalizeOwnerMembership({
    required this.id,
    required this.userId,
  });

  factory FinalizeOwnerMembership.fromJson(Map<String, dynamic> json) =>
      FinalizeOwnerMembership(
        id: json['id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
      );
}

/// Result of POST /api/provisioning/{run}/finalize.
class FinalizeResult {
  final String runId;
  final String status;
  final String workspaceId;
  final FinalizeOwnerRole? primaryOwnerRole;
  final FinalizeOwnerMembership? ownerMembership;
  final bool roleAssigned;
  final bool onboardingCompleted;
  final bool alreadyFinalized;

  const FinalizeResult({
    required this.runId,
    required this.status,
    this.workspaceId = '',
    this.primaryOwnerRole,
    this.ownerMembership,
    this.roleAssigned = false,
    this.onboardingCompleted = false,
    this.alreadyFinalized = false,
  });

  factory FinalizeResult.fromJson(Map<String, dynamic> json) {
    final roleJson = json['primary_owner_role'] as Map<String, dynamic>?;
    final membershipJson = json['owner_membership'] as Map<String, dynamic>?;
    return FinalizeResult(
      runId: json['run_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      workspaceId: json['workspace_id'] as String? ?? '',
      primaryOwnerRole:
          roleJson != null ? FinalizeOwnerRole.fromJson(roleJson) : null,
      ownerMembership: membershipJson != null
          ? FinalizeOwnerMembership.fromJson(membershipJson)
          : null,
      roleAssigned: json['role_assigned'] as bool? ?? false,
      onboardingCompleted: json['onboarding_completed'] as bool? ?? false,
      alreadyFinalized: json['already_finalized'] as bool? ?? false,
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Structured Provisioning Error
// ═══════════════════════════════════════════════════════════

/// Parsed provisioning error from backend JSON error responses.
///
/// Backend provisioning errors always include:
///   - `message`: human-readable description
///   - `error`: stable error code string
///
/// The [errorCode] maps to:
///   - `run_not_found` (404)
///   - `invalid_status_transition` (409)
///   - `missing_primary_owner_role` (422)
///   - `missing_role_binding` (422)
///   - `missing_bound_entity` (409)
///   - `no_active_membership` (422)
///   - `blueprint_not_found` (404)
///   - `concurrent_run` (409)
///   - `internal_error` (500)
class ProvisioningError {
  final String message;
  final String? errorCode;
  final int statusCode;

  const ProvisioningError({
    required this.message,
    this.errorCode,
    this.statusCode = 0,
  });

  factory ProvisioningError.fromJson(Map<String, dynamic> json,
      {int statusCode = 0}) {
    return ProvisioningError(
      message: json['message'] as String? ?? 'Unknown error',
      errorCode: json['error'] as String? ?? json['error_code'] as String?,
      statusCode: statusCode,
    );
  }

  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isValidation => statusCode == 422;
  bool get isForbidden => statusCode == 403;
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ProvisioningError($statusCode/$errorCode): $message';
}
