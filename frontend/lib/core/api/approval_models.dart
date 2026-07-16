// SmartBiz AI — Approval Engine API models.

// ── Safe-cast helpers ────────────────────────────────────

/// Safely extract a [Map<String, dynamic>] from a JSON value that may be
/// a Map, an empty List (PHP's default `[]`), or null.
Map<String, dynamic>? _safeMap(dynamic v) {
  if (v == null) return null;
  if (v is Map) return Map<String, dynamic>.from(v);
  // Backend returns [] for empty JSON objects — treat as null.
  if (v is List && v.isEmpty) return null;
  return null;
}

/// Safely cast a dynamic value to [Map<String, dynamic>] via Map.from().
/// Returns null for non-Map values.
Map<String, dynamic>? _castMap(dynamic v) {
  if (v == null) return null;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

// ═══════════════════════════════════════════════════════
//  Approval Workflow
// ═══════════════════════════════════════════════════════

class ApprovalWorkflow {
  final String id;
  final String workflowKey;
  final String name;
  final String? description;
  final String entityType;
  final Map<String, dynamic>? triggerConditions;
  final bool isActive;
  final int sortOrder;
  final String? createdBy;
  final List<ApprovalWorkflowStep> steps;
  final String? createdAt;
  final String? updatedAt;

  const ApprovalWorkflow({
    required this.id,
    required this.workflowKey,
    required this.name,
    this.description,
    required this.entityType,
    this.triggerConditions,
    this.isActive = true,
    this.sortOrder = 0,
    this.createdBy,
    this.steps = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory ApprovalWorkflow.fromJson(Map<String, dynamic> j) => ApprovalWorkflow(
    id: j['id'] as String,
    workflowKey: j['workflow_key'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    entityType: j['entity_type'] as String,
    triggerConditions: _safeMap(j['trigger_conditions']),
    isActive: j['is_active'] as bool? ?? true,
    sortOrder: j['sort_order'] as int? ?? 0,
    createdBy: j['created_by'] as String?,
    steps:
        (j['steps'] as List?)
            ?.whereType<Map>()
            .map(
              (e) =>
                  ApprovalWorkflowStep.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList() ??
        [],
    createdAt: j['created_at'] as String?,
    updatedAt: j['updated_at'] as String?,
  );
}

// ═══════════════════════════════════════════════════════
//  Approval Workflow Step
// ═══════════════════════════════════════════════════════

class ApprovalWorkflowStep {
  final String id;
  final String workflowId;
  final String name;
  final int stepOrder;
  final String approverType;
  final String? approverPermissionKey;
  final String? approverMembershipId;
  final Map<String, dynamic>? conditions;
  final bool allowSelfApproval;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  const ApprovalWorkflowStep({
    required this.id,
    required this.workflowId,
    required this.name,
    required this.stepOrder,
    required this.approverType,
    this.approverPermissionKey,
    this.approverMembershipId,
    this.conditions,
    this.allowSelfApproval = false,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory ApprovalWorkflowStep.fromJson(Map<String, dynamic> j) =>
      ApprovalWorkflowStep(
        id: j['id'] as String,
        workflowId: j['workflow_id'] as String,
        name: j['name'] as String,
        stepOrder: j['step_order'] as int? ?? 1,
        approverType: j['approver_type'] as String,
        approverPermissionKey: j['approver_permission_key'] as String?,
        approverMembershipId: j['approver_membership_id'] as String?,
        conditions: _safeMap(j['conditions']),
        allowSelfApproval: j['allow_self_approval'] as bool? ?? false,
        isActive: j['is_active'] as bool? ?? true,
        createdAt: j['created_at'] as String?,
        updatedAt: j['updated_at'] as String?,
      );
}

// ═══════════════════════════════════════════════════════
//  Approval Request
// ═══════════════════════════════════════════════════════

class ApprovalRequest {
  final String id;
  final String? workflowId;
  final Map<String, dynamic>? workflow;
  final String entityType;
  final String entityId;
  final String? subjectDisplayName;
  final String requesterMembershipId;
  final Map<String, dynamic>? requester;
  final String status;
  final int currentStepOrder;
  final String? finalNotes;
  final String? resolvedAt;
  final String? createdAt;
  final String? updatedAt;
  final int? stepsCount;
  final int? completedSteps;
  final int? rejectedAtStep;
  final Map<String, dynamic>? entitySnapshot;
  final Map<String, dynamic>? metadata;
  final List<ApprovalRequestStepDetail> steps;
  final List<ApprovalDecisionDetail> decisions;

  // Server-authoritative capability flags.
  // These are the ONLY source of truth for UI action visibility.
  final bool canView;
  final bool canDecide;
  final bool canCancel;

  const ApprovalRequest({
    required this.id,
    this.workflowId,
    this.workflow,
    required this.entityType,
    required this.entityId,
    this.subjectDisplayName,
    required this.requesterMembershipId,
    this.requester,
    this.status = 'pending',
    this.currentStepOrder = 1,
    this.finalNotes,
    this.resolvedAt,
    this.createdAt,
    this.updatedAt,
    this.stepsCount,
    this.completedSteps,
    this.rejectedAtStep,
    this.entitySnapshot,
    this.metadata,
    this.steps = const [],
    this.decisions = const [],
    this.canView = false,
    this.canDecide = false,
    this.canCancel = false,
  });

  factory ApprovalRequest.fromJson(Map<String, dynamic> j) => ApprovalRequest(
    id: j['id'] as String,
    workflowId: j['workflow_id'] as String?,
    workflow: _castMap(j['workflow']),
    entityType: j['entity_type'] as String,
    entityId: j['entity_id'] as String,
    subjectDisplayName: j['subject_display_name'] as String?,
    requesterMembershipId: j['requester_membership_id'] as String,
    requester: _castMap(j['requester']),
    status: j['status'] as String? ?? 'pending',
    currentStepOrder: j['current_step_order'] as int? ?? 1,
    finalNotes: j['final_notes'] as String?,
    resolvedAt: j['resolved_at'] as String?,
    createdAt: j['created_at'] as String?,
    updatedAt: j['updated_at'] as String?,
    stepsCount: j['steps_count'] as int?,
    completedSteps: j['completed_steps'] as int?,
    rejectedAtStep: j['rejected_at_step'] as int?,
    entitySnapshot: _castMap(j['entity_snapshot']),
    metadata: _safeMap(j['metadata']),
    steps:
        (j['steps'] as List?)
            ?.whereType<Map>()
            .map(
              (e) => ApprovalRequestStepDetail.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList() ??
        [],
    decisions:
        (j['decisions'] as List?)
            ?.whereType<Map>()
            .map(
              (e) =>
                  ApprovalDecisionDetail.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList() ??
        [],
    canView: j['can_view'] as bool? ?? false,
    canDecide: j['can_decide'] as bool? ?? false,
    canCancel: j['can_cancel'] as bool? ?? false,
  );

  /// Human-readable requester name.
  String get requesterName => requester?['full_name'] as String? ?? 'Unknown';

  /// Human-readable workflow name.
  String get workflowName => workflow?['name'] as String? ?? 'Unknown Workflow';

  /// Readable subject title with cascading fallback:
  /// 1. Backend-resolved subject_display_name (e.g., pipeline record title)
  /// 2. entity_snapshot title or name
  /// 3. null (caller should provide a localized entity label or shortened UUID)
  String? get displayTitle =>
      subjectDisplayName ??
      entitySnapshot?['title'] as String? ??
      entitySnapshot?['name'] as String?;

  /// Progress as 0.0–1.0.
  /// For rejected requests, shows progress up to the rejection point.
  double get progress {
    final total = stepsCount ?? steps.length;
    if (total <= 0) return 0;
    if (status == 'approved') return 1.0;
    final done = completedSteps ?? 0;
    return (done / total).clamp(0.0, 1.0);
  }

  /// Human-readable progress label.
  /// e.g. "1/2" for pending, "Rejected at step 1" for rejected.
  String get progressLabel {
    final total = stepsCount ?? steps.length;
    if (status == 'rejected' && rejectedAtStep != null) {
      return 'Rejected at step $rejectedAtStep/$total';
    }
    if (status == 'approved') {
      return '$total/$total';
    }
    return '${completedSteps ?? 0}/$total';
  }
}

// ═══════════════════════════════════════════════════════
//  Approval Request Step Detail (from show endpoint)
// ═══════════════════════════════════════════════════════

class ApprovalRequestStepDetail {
  final String id;
  final String? workflowStepId;
  final String? stepName;
  final int stepOrder;
  final String? approverType;
  final String? approverPermissionKey;
  final String status;
  final Map<String, dynamic>? decidedBy;
  final String? decisionNotes;
  final String? decidedAt;

  const ApprovalRequestStepDetail({
    required this.id,
    this.workflowStepId,
    this.stepName,
    required this.stepOrder,
    this.approverType,
    this.approverPermissionKey,
    this.status = 'pending',
    this.decidedBy,
    this.decisionNotes,
    this.decidedAt,
  });

  factory ApprovalRequestStepDetail.fromJson(Map<String, dynamic> j) =>
      ApprovalRequestStepDetail(
        id: j['id'] as String,
        workflowStepId: j['workflow_step_id'] as String?,
        stepName: j['step_name'] as String?,
        stepOrder: j['step_order'] as int? ?? 1,
        approverType: j['approver_type'] as String?,
        approverPermissionKey: j['approver_permission_key'] as String?,
        status: j['status'] as String? ?? 'pending',
        decidedBy: _castMap(j['decided_by']),
        decisionNotes: j['decision_notes'] as String?,
        decidedAt: j['decided_at'] as String?,
      );

  String get decidedByName => decidedBy?['full_name'] as String? ?? 'N/A';
}

// ═══════════════════════════════════════════════════════
//  Approval Decision Detail (audit trail)
// ═══════════════════════════════════════════════════════

class ApprovalDecisionDetail {
  final String id;
  final String? stepId;
  final Map<String, dynamic>? actor;
  final String decision;
  final String? notes;
  final Map<String, dynamic>? actorSnapshot;
  final String? createdAt;

  const ApprovalDecisionDetail({
    required this.id,
    this.stepId,
    this.actor,
    required this.decision,
    this.notes,
    this.actorSnapshot,
    this.createdAt,
  });

  factory ApprovalDecisionDetail.fromJson(Map<String, dynamic> j) =>
      ApprovalDecisionDetail(
        id: j['id'] as String,
        stepId: j['step_id'] as String?,
        actor: _castMap(j['actor']),
        decision: j['decision'] as String,
        notes: j['notes'] as String?,
        actorSnapshot: _castMap(j['actor_snapshot']),
        createdAt: j['created_at'] as String?,
      );

  String get actorName => actor?['full_name'] as String? ?? 'System';
}

// ═══════════════════════════════════════════════════════
//  Payloads
// ═══════════════════════════════════════════════════════

/// Payload for submitting a new approval request.
class ApprovalRequestPayload {
  final String entityType;
  final String entityId;
  final Map<String, dynamic>? entitySnapshot;
  final Map<String, dynamic>? metadata;

  const ApprovalRequestPayload({
    required this.entityType,
    required this.entityId,
    this.entitySnapshot,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'entity_type': entityType,
    'entity_id': entityId,
    if (entitySnapshot != null) 'entity_snapshot': entitySnapshot,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Payload for making a decision on an approval step.
class ApprovalDecisionPayload {
  final String decision; // 'approved' | 'rejected'
  final String? notes;

  const ApprovalDecisionPayload({required this.decision, this.notes});

  Map<String, dynamic> toJson() => {
    'decision': decision,
    if (notes != null) 'notes': notes,
  };
}

/// Payload for creating a new workflow.
class ApprovalWorkflowPayload {
  final String? workflowKey;
  final String name;
  final String? description;
  final String entityType;
  final Map<String, dynamic>? triggerConditions;
  final List<ApprovalWorkflowStepPayload>? steps;

  const ApprovalWorkflowPayload({
    this.workflowKey,
    required this.name,
    this.description,
    required this.entityType,
    this.triggerConditions,
    this.steps,
  });

  Map<String, dynamic> toJson() => {
    if (workflowKey != null && workflowKey!.isNotEmpty)
      'workflow_key': workflowKey,
    'name': name,
    if (description != null) 'description': description,
    'entity_type': entityType,
    if (triggerConditions != null) 'trigger_conditions': triggerConditions,
    if (steps != null) 'steps': steps!.map((s) => s.toJson()).toList(),
  };
}

/// Payload for a workflow step in the create-workflow request.
class ApprovalWorkflowStepPayload {
  final String name;
  final String approverType;
  final String? approverPermissionKey;
  final String? approverMembershipId;
  final bool? allowSelfApproval;
  final Map<String, dynamic>? conditions;

  const ApprovalWorkflowStepPayload({
    required this.name,
    required this.approverType,
    this.approverPermissionKey,
    this.approverMembershipId,
    this.allowSelfApproval,
    this.conditions,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'approver_type': approverType,
    if (approverPermissionKey != null)
      'approver_permission_key': approverPermissionKey,
    if (approverMembershipId != null)
      'approver_membership_id': approverMembershipId,
    if (allowSelfApproval != null) 'allow_self_approval': allowSelfApproval,
    if (conditions != null) 'conditions': conditions,
  };
}

/// Payload for updating a workflow definition.
class ApprovalWorkflowUpdatePayload {
  final String? name;
  final String? description;
  final Map<String, dynamic>? triggerConditions;
  final bool? isActive;
  final int? sortOrder;

  const ApprovalWorkflowUpdatePayload({
    this.name,
    this.description,
    this.triggerConditions,
    this.isActive,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
    if (triggerConditions != null) 'trigger_conditions': triggerConditions,
    if (isActive != null) 'is_active': isActive,
    if (sortOrder != null) 'sort_order': sortOrder,
  };
}

// ═══════════════════════════════════════════════════════
//  Constants
// ═══════════════════════════════════════════════════════

const kApprovalStatuses = ['pending', 'approved', 'rejected', 'cancelled'];
const kApproverTypes = [
  'permission',
  'requester_manager',
  'specific_membership',
];
