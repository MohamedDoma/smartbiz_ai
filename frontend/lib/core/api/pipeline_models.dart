// SmartBiz AI — Pipeline & Custom Field API models.

// ═══════════════════════════════════════════════════════
//  Pipeline
// ═══════════════════════════════════════════════════════

class Pipeline {
  final String id;
  final String workspaceId;
  final String? pipelineKey;
  final String name;
  final String? description;
  final String entityType;
  final bool isActive;
  final int sortOrder;
  final int? stagesCount;
  final int? recordsCount;
  final List<PipelineStage>? stages;
  final List<CustomField>? customFields;

  const Pipeline({
    required this.id,
    required this.workspaceId,
    this.pipelineKey,
    required this.name,
    this.description,
    this.entityType = 'generic',
    this.isActive = true,
    this.sortOrder = 0,
    this.stagesCount,
    this.recordsCount,
    this.stages,
    this.customFields,
  });

  factory Pipeline.fromJson(Map<String, dynamic> j) => Pipeline(
        id: j['id'] as String,
        workspaceId: j['workspace_id'] as String,
        pipelineKey: j['pipeline_key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        entityType: j['entity_type'] as String? ?? 'generic',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
        stagesCount: j['stages_count'] as int?,
        recordsCount: j['records_count'] as int?,
        stages: (j['stages'] as List?)?.map((e) => PipelineStage.fromJson(e as Map<String, dynamic>)).toList(),
        customFields: (j['custom_fields'] as List?)?.map((e) => CustomField.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class PipelinePayload {
  final String name;
  final String? description;
  final String? entityType;
  final int? sortOrder;

  const PipelinePayload({required this.name, this.description, this.entityType, this.sortOrder});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (entityType != null) 'entity_type': entityType,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Pipeline Stage
// ═══════════════════════════════════════════════════════

class PipelineStage {
  final String id;
  final String pipelineId;
  final String? stageKey;
  final String name;
  final String? description;
  final String statusType;
  final int sortOrder;
  final bool isActive;
  final int? recordsCount;

  const PipelineStage({
    required this.id,
    required this.pipelineId,
    this.stageKey,
    required this.name,
    this.description,
    this.statusType = 'open',
    this.sortOrder = 0,
    this.isActive = true,
    this.recordsCount,
  });

  factory PipelineStage.fromJson(Map<String, dynamic> j) => PipelineStage(
        id: j['id'] as String,
        pipelineId: j['pipeline_id'] as String? ?? '',
        stageKey: j['stage_key'] as String?,
        name: j['name'] as String,
        description: j['description'] as String?,
        statusType: j['status_type'] as String? ?? 'open',
        sortOrder: j['sort_order'] as int? ?? 0,
        isActive: j['is_active'] as bool? ?? true,
        recordsCount: j['records_count'] as int?,
      );
}

class PipelineStagePayload {
  final String name;
  final String? description;
  final String? statusType;
  final int? sortOrder;

  const PipelineStagePayload({required this.name, this.description, this.statusType, this.sortOrder});

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (statusType != null) 'status_type': statusType,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Pipeline Record
// ═══════════════════════════════════════════════════════

class PipelineRecord {
  final String id;
  final String pipelineId;
  final String stageId;
  final PipelineRecordRef? pipeline;
  final PipelineRecordStageRef? stage;
  final String title;
  final String? description;
  final PipelineRecordRef? contact;
  final PipelineRecordAssignee? assignedTo;
  final double? valueAmount;
  final String? currency;
  final String status;
  final String? expectedCloseDate;
  final String? closedAt;
  final Map<String, PipelineRecordCustomValue>? customValues;
  final String? createdAt;

  const PipelineRecord({
    required this.id,
    required this.pipelineId,
    required this.stageId,
    this.pipeline,
    this.stage,
    required this.title,
    this.description,
    this.contact,
    this.assignedTo,
    this.valueAmount,
    this.currency,
    this.status = 'open',
    this.expectedCloseDate,
    this.closedAt,
    this.customValues,
    this.createdAt,
  });

  factory PipelineRecord.fromJson(Map<String, dynamic> j) {
    Map<String, PipelineRecordCustomValue>? cv;
    if (j['custom_values'] != null && j['custom_values'] is Map) {
      cv = {};
      (j['custom_values'] as Map<String, dynamic>).forEach((k, v) {
        cv![k] = PipelineRecordCustomValue.fromJson(v as Map<String, dynamic>);
      });
    }
    return PipelineRecord(
      id: j['id'] as String,
      pipelineId: j['pipeline_id'] as String,
      stageId: j['stage_id'] as String,
      pipeline: j['pipeline'] != null ? PipelineRecordRef.fromJson(j['pipeline'] as Map<String, dynamic>) : null,
      stage: j['stage'] != null ? PipelineRecordStageRef.fromJson(j['stage'] as Map<String, dynamic>) : null,
      title: j['title'] as String,
      description: j['description'] as String?,
      contact: j['contact'] != null ? PipelineRecordRef.fromJson(j['contact'] as Map<String, dynamic>) : null,
      assignedTo: j['assigned_to'] != null ? PipelineRecordAssignee.fromJson(j['assigned_to'] as Map<String, dynamic>) : null,
      valueAmount: _parseDouble(j['value_amount']),
      currency: j['currency'] as String?,
      status: j['status'] as String? ?? 'open',
      expectedCloseDate: j['expected_close_date'] as String?,
      closedAt: j['closed_at'] as String?,
      customValues: cv,
      createdAt: j['created_at'] as String?,
    );
  }
}

class PipelineRecordPayload {
  final String pipelineId;
  final String stageId;
  final String title;
  final String? description;
  final String? contactId;
  final String? assignedMembershipId;
  final double? valueAmount;
  final String? currency;
  final String? expectedCloseDate;
  final Map<String, dynamic>? customValues;

  const PipelineRecordPayload({
    required this.pipelineId,
    required this.stageId,
    required this.title,
    this.description,
    this.contactId,
    this.assignedMembershipId,
    this.valueAmount,
    this.currency,
    this.expectedCloseDate,
    this.customValues,
  });

  Map<String, dynamic> toJson() => {
        'pipeline_id': pipelineId,
        'stage_id': stageId,
        'title': title,
        if (description != null) 'description': description,
        if (contactId != null) 'contact_id': contactId,
        if (assignedMembershipId != null) 'assigned_membership_id': assignedMembershipId,
        if (valueAmount != null) 'value_amount': valueAmount,
        if (currency != null) 'currency': currency,
        if (expectedCloseDate != null) 'expected_close_date': expectedCloseDate,
        if (customValues != null) 'custom_values': customValues,
      };
}

class PipelineMovePayload {
  final String stageId;
  const PipelineMovePayload({required this.stageId});
  Map<String, dynamic> toJson() => {'stage_id': stageId};
}

// ═══════════════════════════════════════════════════════
//  Custom Field
// ═══════════════════════════════════════════════════════

class CustomField {
  final String id;
  final String workspaceId;
  final String? pipelineId;
  final String? fieldKey;
  final String label;
  final String fieldType;
  final List<String>? options;
  final bool isRequired;
  final String appliesTo;
  final bool isActive;
  final int sortOrder;

  const CustomField({
    required this.id,
    this.workspaceId = '',
    this.pipelineId,
    this.fieldKey,
    required this.label,
    required this.fieldType,
    this.options,
    this.isRequired = false,
    this.appliesTo = 'pipeline_record',
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(
        id: j['id'] as String,
        workspaceId: j['workspace_id'] as String? ?? '',
        pipelineId: j['pipeline_id'] as String?,
        fieldKey: j['field_key'] as String?,
        label: j['label'] as String,
        fieldType: j['field_type'] as String,
        options: (j['options'] as List?)?.map((e) => e.toString()).toList(),
        isRequired: j['is_required'] as bool? ?? false,
        appliesTo: j['applies_to'] as String? ?? 'pipeline_record',
        isActive: j['is_active'] as bool? ?? true,
        sortOrder: j['sort_order'] as int? ?? 0,
      );
}

class CustomFieldPayload {
  final String? pipelineId;
  final String label;
  final String? fieldKey;
  final String fieldType;
  final List<String>? options;
  final bool? isRequired;
  final int? sortOrder;

  const CustomFieldPayload({
    this.pipelineId,
    required this.label,
    this.fieldKey,
    required this.fieldType,
    this.options,
    this.isRequired,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'field_type': fieldType,
        if (pipelineId != null) 'pipeline_id': pipelineId,
        if (fieldKey != null) 'field_key': fieldKey,
        if (options != null) 'options': options,
        if (isRequired != null) 'is_required': isRequired,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

// ═══════════════════════════════════════════════════════
//  Shared refs
// ═══════════════════════════════════════════════════════

class PipelineRecordRef {
  final String id;
  final String name;
  const PipelineRecordRef({required this.id, required this.name});
  factory PipelineRecordRef.fromJson(Map<String, dynamic> j) =>
      PipelineRecordRef(id: j['id'] as String, name: j['name'] as String? ?? '');
}

class PipelineRecordStageRef {
  final String id;
  final String name;
  final String statusType;
  const PipelineRecordStageRef({required this.id, required this.name, required this.statusType});
  factory PipelineRecordStageRef.fromJson(Map<String, dynamic> j) => PipelineRecordStageRef(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        statusType: j['status_type'] as String? ?? 'open',
      );
}

class PipelineRecordAssignee {
  final String membershipId;
  final String fullName;
  const PipelineRecordAssignee({required this.membershipId, required this.fullName});
  factory PipelineRecordAssignee.fromJson(Map<String, dynamic> j) => PipelineRecordAssignee(
        membershipId: j['membership_id'] as String,
        fullName: j['full_name'] as String? ?? '',
      );
}

class PipelineRecordCustomValue {
  final String? fieldKey;
  final String? label;
  final String? fieldType;
  final dynamic value;
  const PipelineRecordCustomValue({this.fieldKey, this.label, this.fieldType, this.value});
  factory PipelineRecordCustomValue.fromJson(Map<String, dynamic> j) => PipelineRecordCustomValue(
        fieldKey: j['field_key'] as String?,
        label: j['label'] as String?,
        fieldType: j['field_type'] as String?,
        value: j['value'],
      );
}

// ═══════════════════════════════════════════════════════
//  Assignable Member (for assignment selector)
// ═══════════════════════════════════════════════════════

class AssignableMember {
  final String membershipId;
  final String fullName;
  final String? roleName;
  final String? roleKey;
  final String? department;
  final String? team;

  const AssignableMember({
    required this.membershipId,
    required this.fullName,
    this.roleName,
    this.roleKey,
    this.department,
    this.team,
  });

  factory AssignableMember.fromJson(Map<String, dynamic> j) => AssignableMember(
        membershipId: j['membership_id'] as String,
        fullName: j['full_name'] as String? ?? '',
        roleName: j['role_name'] as String?,
        roleKey: j['role_key'] as String?,
        department: j['department'] as String?,
        team: j['team'] as String?,
      );
}

/// Parse a value that may arrive as a [num] or a [String] (e.g. PostgreSQL
/// decimal columns serialised by Laravel). Returns null for null/empty/invalid.
double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }
  return null;
}

const kFieldTypes = ['text', 'textarea', 'number', 'date', 'boolean', 'select', 'multi_select', 'currency'];
