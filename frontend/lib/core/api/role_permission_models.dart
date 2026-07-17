// SmartBiz AI — Role & permission API models (real backend).

/// A single permission item from the catalog.
class PermissionItem {
  final String key;
  final String label;
  final String description;

  /// Whether this permission is eligible as a workflow approver key.
  /// Only permissions flagged `usable_as_approver: true` in the backend
  /// catalog should appear in the approval-step permission selector.
  final bool usableAsApprover;

  /// Optional locale-specific labels returned by the backend catalog
  /// for permissions that appear in user-facing workflow UIs.
  final String? labelEn;
  final String? labelAr;

  const PermissionItem({
    required this.key,
    required this.label,
    this.description = '',
    this.usableAsApprover = false,
    this.labelEn,
    this.labelAr,
  });

  factory PermissionItem.fromJson(Map<String, dynamic> json) => PermissionItem(
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
        usableAsApprover: json['usable_as_approver'] as bool? ?? false,
        labelEn: json['label_en'] as String?,
        labelAr: json['label_ar'] as String?,
      );

  /// Returns the best label for the given language code ('en' or 'ar'),
  /// falling back to the default [label] field.
  String localizedLabel(String langCode) {
    if (langCode == 'ar') return labelAr ?? label;
    if (langCode == 'en') return labelEn ?? label;
    return label;
  }
}

/// A category group of permissions.
class PermissionCategory {
  final String category;
  final String label;
  final String? labelEn;
  final String? labelAr;
  final List<PermissionItem> permissions;

  const PermissionCategory({required this.category, required this.label, this.labelEn, this.labelAr, required this.permissions});

  factory PermissionCategory.fromJson(Map<String, dynamic> json) => PermissionCategory(
        category: json['category'] as String? ?? '',
        label: json['label'] as String? ?? '',
        labelEn: json['label_en'] as String?,
        labelAr: json['label_ar'] as String?,
        permissions: (json['permissions'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(PermissionItem.fromJson)
            .toList(),
      );

  /// Returns the best label for the given language code ('en' or 'ar'),
  /// falling back to the default [label] field.
  String localizedLabel(String langCode) {
    if (langCode == 'ar') return labelAr ?? label;
    if (langCode == 'en') return labelEn ?? label;
    return label;
  }
}

/// A workspace role (from GET /api/workspace-roles).
class WorkspaceRole {
  final String id;
  final String roleKey;
  final String name;
  final String? description;
  final List<String> permissions;
  final int hierarchyLevel;
  final bool isSystem;
  final bool isDefault;
  final bool isDeletable;
  final bool isActive;
  final int sortOrder;
  final int assignedCount;

  const WorkspaceRole({
    required this.id,
    required this.roleKey,
    required this.name,
    this.description,
    this.permissions = const [],
    this.hierarchyLevel = 99,
    this.isSystem = false,
    this.isDefault = false,
    this.isDeletable = true,
    this.isActive = true,
    this.sortOrder = 0,
    this.assignedCount = 0,
  });

  factory WorkspaceRole.fromJson(Map<String, dynamic> json) => WorkspaceRole(
        id: json['id'] as String? ?? '',
        roleKey: json['role_key'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        permissions: (json['permissions'] as List<dynamic>? ?? []).cast<String>(),
        hierarchyLevel: json['hierarchy_level'] as int? ?? 99,
        isSystem: json['is_system'] as bool? ?? false,
        isDefault: json['is_default'] as bool? ?? false,
        isDeletable: json['is_deletable'] as bool? ?? true,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
        assignedCount: json['assigned_count'] as int? ?? 0,
      );

  /// Whether this role is a protected system role that cannot be modified
  /// or deactivated. Uses backend flags (is_system + not deletable) rather
  /// than checking the role_key string.
  bool get isProtected => isSystem && !isDeletable;
}

/// Payload for creating/updating a workspace role.
class WorkspaceRolePayload {
  final String name;
  final String? roleKey;
  final String? description;
  final List<String> permissions;
  final int? sortOrder;
  final bool? isActive;

  const WorkspaceRolePayload({
    required this.name,
    this.roleKey,
    this.description,
    this.permissions = const [],
    this.sortOrder,
    this.isActive,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (roleKey != null) 'role_key': roleKey,
        if (description != null) 'description': description,
        'permissions': permissions,
        if (sortOrder != null) 'sort_order': sortOrder,
        if (isActive != null) 'is_active': isActive,
      };
}

/// A member summary from /api/workspace-employees.
class WorkspaceEmployeeMember {
  final String membershipId;
  final String userId;
  final String? fullName;
  final String? email;
  final String status;
  final String? joinedAt;
  final MemberRoleSummary? primaryRole;
  final List<MemberRoleSummary> roles;

  const WorkspaceEmployeeMember({
    required this.membershipId,
    required this.userId,
    this.fullName,
    this.email,
    this.status = 'active',
    this.joinedAt,
    this.primaryRole,
    this.roles = const [],
  });

  factory WorkspaceEmployeeMember.fromJson(Map<String, dynamic> json) {
    final pr = json['primary_role'] as Map<String, dynamic>?;
    final rolesList = (json['roles'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(MemberRoleSummary.fromJson)
        .toList();
    return WorkspaceEmployeeMember(
      membershipId: json['membership_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      status: json['status'] as String? ?? 'active',
      joinedAt: json['joined_at'] as String?,
      primaryRole: pr != null ? MemberRoleSummary.fromJson(pr) : null,
      roles: rolesList,
    );
  }
}

class MemberRoleSummary {
  final String roleId;
  final String? roleKey;
  final String? name;
  final bool isPrimary;

  const MemberRoleSummary({required this.roleId, this.roleKey, this.name, this.isPrimary = false});

  factory MemberRoleSummary.fromJson(Map<String, dynamic> json) => MemberRoleSummary(
        roleId: json['role_id'] as String? ?? '',
        roleKey: json['role_key'] as String?,
        name: json['name'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}

/// Payload for updating employee roles.
class EmployeeRolesPayload {
  final List<String> roleIds;
  final String? primaryRoleId;

  const EmployeeRolesPayload({required this.roleIds, this.primaryRoleId});

  Map<String, dynamic> toJson() => {
        'role_ids': roleIds,
        if (primaryRoleId != null) 'primary_role_id': primaryRoleId,
      };
}
