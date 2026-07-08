// SmartBiz AI — Ownership API models.

class OwnershipAssignment {
  final String id;
  final String entityType;
  final String entityId;
  final String ownerMembershipId;
  final Map<String, dynamic>? owner;
  final Map<String, dynamic>? team;
  final Map<String, dynamic>? department;
  final String source;
  final String status;
  final String? assignedAt;
  final String? notes;

  const OwnershipAssignment({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.ownerMembershipId,
    this.owner,
    this.team,
    this.department,
    this.source = 'manual',
    this.status = 'active',
    this.assignedAt,
    this.notes,
  });

  factory OwnershipAssignment.fromJson(Map<String, dynamic> j) => OwnershipAssignment(
        id: j['id'] as String,
        entityType: j['entity_type'] as String,
        entityId: j['entity_id'] as String,
        ownerMembershipId: j['owner_membership_id'] as String,
        owner: j['owner'] as Map<String, dynamic>?,
        team: j['team'] as Map<String, dynamic>?,
        department: j['department'] as Map<String, dynamic>?,
        source: j['source'] as String? ?? 'manual',
        status: j['status'] as String? ?? 'active',
        assignedAt: j['assigned_at'] as String?,
        notes: j['notes'] as String?,
      );
}

class OwnershipAssignmentPayload {
  final String entityType;
  final String entityId;
  final String ownerMembershipId;
  final String? source;
  final String? notes;

  const OwnershipAssignmentPayload({
    required this.entityType,
    required this.entityId,
    required this.ownerMembershipId,
    this.source,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'entity_type': entityType,
        'entity_id': entityId,
        'owner_membership_id': ownerMembershipId,
        if (source != null) 'source': source,
        if (notes != null) 'notes': notes,
      };
}

class OwnershipTransferPayload {
  final String toMembershipId;
  final String? reason;

  const OwnershipTransferPayload({required this.toMembershipId, this.reason});

  Map<String, dynamic> toJson() => {
        'to_membership_id': toMembershipId,
        if (reason != null) 'reason': reason,
      };
}

class OwnershipResolveResult {
  final String source;
  final Map<String, dynamic>? owner;
  final String? assignmentId;

  const OwnershipResolveResult({required this.source, this.owner, this.assignmentId});

  factory OwnershipResolveResult.fromJson(Map<String, dynamic> j) => OwnershipResolveResult(
        source: j['source'] as String,
        owner: j['owner'] as Map<String, dynamic>?,
        assignmentId: j['assignment_id'] as String?,
      );
}

const kEntityTypes = ['contact', 'pipeline_record'];
const kOwnershipSources = ['manual', 'created_by', 'assigned_employee', 'transfer', 'import'];
