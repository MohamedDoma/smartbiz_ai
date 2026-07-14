// SmartBiz AI — Commission API models.
import 'json_parse_helpers.dart';

// ═══════════════════════════════════════════════════════
//  Commission Plan
// ═══════════════════════════════════════════════════════

class CommissionPlan {
  final String id;
  final String? planKey;
  final String name;
  final String? description;
  final String appliesTo;
  final bool isActive;
  final int sortOrder;
  final int? rulesCount;

  const CommissionPlan({
    required this.id,
    this.planKey,
    required this.name,
    this.description,
    this.appliesTo = 'pipeline_record',
    this.isActive = true,
    this.sortOrder = 0,
    this.rulesCount,
  });

  factory CommissionPlan.fromJson(Map<String, dynamic> j) => CommissionPlan(
        id: j['id'] as String,
        planKey: j['plan_key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        appliesTo: j['applies_to'] as String? ?? 'pipeline_record',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
        rulesCount: j['rules_count'] as int?,
      );
}

/// Payload for creating a commission plan.
class CommissionPlanPayload {
  final String name;
  final String? description;
  final int? sortOrder;

  const CommissionPlanPayload({required this.name, this.description, this.sortOrder});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

/// Payload for updating a commission plan.
/// Supports partial updates — only non-null fields are sent.
class CommissionPlanUpdatePayload {
  final String? name;
  final String? description;
  final bool? isActive;
  final int? sortOrder;

  const CommissionPlanUpdatePayload({this.name, this.description, this.isActive, this.sortOrder});

  Map<String, dynamic> toJson() => {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (isActive != null) 'is_active': isActive,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Commission Rule
// ═══════════════════════════════════════════════════════

class CommissionRule {
  final String id;
  final String commissionPlanId;
  final Map<String, dynamic>? plan;
  final String? pipelineId;
  final Map<String, dynamic>? pipeline;
  final String? stageId;
  final Map<String, dynamic>? stage;
  final String? roleId;
  final String? departmentId;
  final String? teamId;
  final String targetType;
  final String calculationType;
  final double? percentageRate;
  final double? fixedAmount;
  final String? currency;
  final double? minRecordValue;
  final double? maxRecordValue;
  final String triggerStatus;
  final bool isActive;
  final int sortOrder;

  const CommissionRule({
    required this.id,
    required this.commissionPlanId,
    this.plan,
    this.pipelineId,
    this.pipeline,
    this.stageId,
    this.stage,
    this.roleId,
    this.departmentId,
    this.teamId,
    this.targetType = 'assigned_employee',
    this.calculationType = 'percentage',
    this.percentageRate,
    this.fixedAmount,
    this.currency,
    this.minRecordValue,
    this.maxRecordValue,
    this.triggerStatus = 'won',
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CommissionRule.fromJson(Map<String, dynamic> j) => CommissionRule(
        id: j['id'] as String,
        commissionPlanId: j['commission_plan_id'] as String,
        plan: j['plan'] as Map<String, dynamic>?,
        pipelineId: j['pipeline_id'] as String?,
        pipeline: j['pipeline'] as Map<String, dynamic>?,
        stageId: j['stage_id'] as String?,
        stage: j['stage'] as Map<String, dynamic>?,
        roleId: j['role_id'] as String?,
        departmentId: j['department_id'] as String?,
        teamId: j['team_id'] as String?,
        targetType: j['target_type'] as String? ?? 'assigned_employee',
        calculationType: j['calculation_type'] as String? ?? 'percentage',
        percentageRate: parseJsonDouble(j['percentage_rate']),
        fixedAmount: parseJsonDouble(j['fixed_amount']),
        currency: j['currency'] as String?,
        minRecordValue: parseJsonDouble(j['min_record_value']),
        maxRecordValue: parseJsonDouble(j['max_record_value']),
        triggerStatus: j['trigger_status'] as String? ?? 'won',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

/// Payload for creating a commission rule.
class CommissionRulePayload {
  final String commissionPlanId;
  final String? pipelineId;
  final String? stageId;
  final String? roleId;
  final String? departmentId;
  final String? teamId;
  final String? targetType;
  final String? calculationType;
  final double? percentageRate;
  final double? fixedAmount;
  final String? currency;
  final double? minRecordValue;
  final double? maxRecordValue;

  const CommissionRulePayload({
    required this.commissionPlanId,
    this.pipelineId,
    this.stageId,
    this.roleId,
    this.departmentId,
    this.teamId,
    this.targetType,
    this.calculationType,
    this.percentageRate,
    this.fixedAmount,
    this.currency,
    this.minRecordValue,
    this.maxRecordValue,
  });

  Map<String, dynamic> toJson() => {
        'commission_plan_id': commissionPlanId,
        if (pipelineId != null) 'pipeline_id': pipelineId,
        if (stageId != null) 'stage_id': stageId,
        if (roleId != null) 'role_id': roleId,
        if (departmentId != null) 'department_id': departmentId,
        if (teamId != null) 'team_id': teamId,
        if (targetType != null) 'target_type': targetType,
        if (calculationType != null) 'calculation_type': calculationType,
        if (percentageRate != null) 'percentage_rate': percentageRate,
        if (fixedAmount != null) 'fixed_amount': fixedAmount,
        if (currency != null) 'currency': currency,
        if (minRecordValue != null) 'min_record_value': minRecordValue,
        if (maxRecordValue != null) 'max_record_value': maxRecordValue,
      };
}

/// Payload for updating a commission rule.
/// Supports partial updates — only non-null fields are sent.
class CommissionRuleUpdatePayload {
  final String? pipelineId;
  final String? stageId;
  final String? targetType;
  final String? calculationType;
  final double? percentageRate;
  final double? fixedAmount;
  final String? currency;
  final double? minRecordValue;
  final double? maxRecordValue;
  final bool? isActive;

  const CommissionRuleUpdatePayload({
    this.pipelineId,
    this.stageId,
    this.targetType,
    this.calculationType,
    this.percentageRate,
    this.fixedAmount,
    this.currency,
    this.minRecordValue,
    this.maxRecordValue,
    this.isActive,
  });

  Map<String, dynamic> toJson() => {
        if (pipelineId != null) 'pipeline_id': pipelineId,
        if (stageId != null) 'stage_id': stageId,
        if (targetType != null) 'target_type': targetType,
        if (calculationType != null) 'calculation_type': calculationType,
        if (percentageRate != null) 'percentage_rate': percentageRate,
        if (fixedAmount != null) 'fixed_amount': fixedAmount,
        if (currency != null) 'currency': currency,
        if (minRecordValue != null) 'min_record_value': minRecordValue,
        if (maxRecordValue != null) 'max_record_value': maxRecordValue,
        if (isActive != null) 'is_active': isActive,
      };
}

// ═══════════════════════════════════════════════════════
//  Commission Entry
// ═══════════════════════════════════════════════════════

class CommissionEntry {
  final String id;
  final String? commissionPlanId;
  final Map<String, dynamic>? plan;
  final String? commissionRuleId;
  final String pipelineRecordId;
  final Map<String, dynamic>? record;
  final String recipientMembershipId;
  final Map<String, dynamic>? recipient;
  final String? sourceMembershipId;
  final Map<String, dynamic>? source;
  final double baseAmount;
  final double commissionAmount;
  final String currency;
  final String calculationType;
  final double? percentageRate;
  final double? fixedAmount;
  final String status;
  final String? calculatedAt;
  final String? approvedAt;
  final String? paidAt;
  final String? notes;

  const CommissionEntry({
    required this.id,
    this.commissionPlanId,
    this.plan,
    this.commissionRuleId,
    required this.pipelineRecordId,
    this.record,
    required this.recipientMembershipId,
    this.recipient,
    this.sourceMembershipId,
    this.source,
    required this.baseAmount,
    required this.commissionAmount,
    this.currency = 'LYD',
    this.calculationType = 'percentage',
    this.percentageRate,
    this.fixedAmount,
    this.status = 'pending',
    this.calculatedAt,
    this.approvedAt,
    this.paidAt,
    this.notes,
  });

  factory CommissionEntry.fromJson(Map<String, dynamic> j) => CommissionEntry(
        id: j['id'] as String,
        commissionPlanId: j['commission_plan_id'] as String?,
        plan: j['plan'] as Map<String, dynamic>?,
        commissionRuleId: j['commission_rule_id'] as String?,
        pipelineRecordId: j['pipeline_record_id'] as String,
        record: j['record'] as Map<String, dynamic>?,
        recipientMembershipId: j['recipient_membership_id'] as String,
        recipient: j['recipient'] as Map<String, dynamic>?,
        sourceMembershipId: j['source_membership_id'] as String?,
        source: j['source'] as Map<String, dynamic>?,
        baseAmount: parseJsonDoubleOr(j['base_amount']),
        commissionAmount: parseJsonDoubleOr(j['commission_amount']),
        currency: j['currency'] as String? ?? 'LYD',
        calculationType: j['calculation_type'] as String? ?? 'percentage',
        percentageRate: parseJsonDouble(j['percentage_rate']),
        fixedAmount: parseJsonDouble(j['fixed_amount']),
        status: j['status'] as String? ?? 'pending',
        calculatedAt: j['calculated_at'] as String?,
        approvedAt: j['approved_at'] as String?,
        paidAt: j['paid_at'] as String?,
        notes: j['notes'] as String?,
      );
}

class CommissionCalculationResult {
  final int createdCount;
  final List<CommissionEntry> entries;

  const CommissionCalculationResult({this.createdCount = 0, this.entries = const []});

  factory CommissionCalculationResult.fromJson(Map<String, dynamic> j) => CommissionCalculationResult(
        createdCount: j['created_count'] as int? ?? 0,
        entries: (j['entries'] as List?)?.map((e) => CommissionEntry.fromJson(e as Map<String, dynamic>)).toList() ?? [],
      );
}

const kTargetTypes = ['assigned_employee', 'direct_manager', 'team_manager', 'department_manager'];
const kCalculationTypes = ['percentage', 'fixed_amount'];
const kEntryStatuses = ['pending', 'approved', 'paid', 'cancelled'];

// ═══════════════════════════════════════════════════════
//  Commission Settings Options (permission-safe)
// ═══════════════════════════════════════════════════════

/// A single eligible stage returned by the settings options endpoint.
class CommissionStageOption {
  final String id;
  final String name;
  final String statusType;

  const CommissionStageOption({required this.id, required this.name, required this.statusType});

  factory CommissionStageOption.fromJson(Map<String, dynamic> j) => CommissionStageOption(
        id: j['id'] as String,
        name: j['name'] as String,
        statusType: j['status_type'] as String? ?? 'won',
      );
}

/// A pipeline with its eligible stages, returned by the settings options endpoint.
class CommissionPipelineOption {
  final String id;
  final String name;
  final String entityType;
  final List<CommissionStageOption> stages;

  const CommissionPipelineOption({
    required this.id,
    required this.name,
    required this.entityType,
    required this.stages,
  });

  factory CommissionPipelineOption.fromJson(Map<String, dynamic> j) => CommissionPipelineOption(
        id: j['id'] as String,
        name: j['name'] as String,
        entityType: j['entity_type'] as String? ?? 'deal',
        stages: (j['stages'] as List?)
                ?.map((e) => CommissionStageOption.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Top-level response from GET /commission-settings/options.
class CommissionSettingsOptions {
  final List<CommissionPipelineOption> pipelines;

  const CommissionSettingsOptions({required this.pipelines});

  factory CommissionSettingsOptions.fromJson(Map<String, dynamic> j) => CommissionSettingsOptions(
        pipelines: (j['pipelines'] as List?)
                ?.map((e) => CommissionPipelineOption.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
