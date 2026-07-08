// SmartBiz AI — Org structure API models.

/// Department model from backend.
class OrgDepartment {
  final String id;
  final String workspaceId;
  final String? departmentKey;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final OrgManagerRef? manager;
  final int memberCount;
  final int teamCount;

  const OrgDepartment({
    required this.id,
    required this.workspaceId,
    this.departmentKey,
    required this.name,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
    this.manager,
    this.memberCount = 0,
    this.teamCount = 0,
  });

  factory OrgDepartment.fromJson(Map<String, dynamic> json) => OrgDepartment(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        departmentKey: json['department_key'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
        manager: json['manager'] != null
            ? OrgManagerRef.fromJson(json['manager'] as Map<String, dynamic>)
            : null,
        memberCount: json['member_count'] as int? ?? 0,
        teamCount: json['team_count'] as int? ?? 0,
      );
}

/// Department create/update payload.
class DepartmentPayload {
  final String name;
  final String? description;
  final String? managerMembershipId;
  final int? sortOrder;

  const DepartmentPayload({
    required this.name,
    this.description,
    this.managerMembershipId,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (managerMembershipId != null) 'manager_membership_id': managerMembershipId,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

/// Team model from backend.
class OrgTeam {
  final String id;
  final String workspaceId;
  final String? departmentId;
  final OrgNameRef? department;
  final String? teamKey;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final OrgManagerRef? manager;
  final int memberCount;

  const OrgTeam({
    required this.id,
    required this.workspaceId,
    this.departmentId,
    this.department,
    this.teamKey,
    required this.name,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
    this.manager,
    this.memberCount = 0,
  });

  factory OrgTeam.fromJson(Map<String, dynamic> json) => OrgTeam(
        id: json['id'] as String,
        workspaceId: json['workspace_id'] as String,
        departmentId: json['department_id'] as String?,
        department: json['department'] != null
            ? OrgNameRef.fromJson(json['department'] as Map<String, dynamic>)
            : null,
        teamKey: json['team_key'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
        manager: json['manager'] != null
            ? OrgManagerRef.fromJson(json['manager'] as Map<String, dynamic>)
            : null,
        memberCount: json['member_count'] as int? ?? 0,
      );
}

/// Team create/update payload.
class TeamPayload {
  final String name;
  final String? departmentId;
  final String? description;
  final String? managerMembershipId;
  final int? sortOrder;

  const TeamPayload({
    required this.name,
    this.departmentId,
    this.description,
    this.managerMembershipId,
    this.sortOrder,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (departmentId != null) 'department_id': departmentId,
        if (description != null) 'description': description,
        if (managerMembershipId != null) 'manager_membership_id': managerMembershipId,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
}

/// Employee with org info (extends role data from Step 50.5).
class OrgEmployee {
  final String membershipId;
  final String userId;
  final String fullName;
  final String email;
  final String? phoneNumber;
  final String status;
  final String? jobTitle;
  final OrgNameRef? department;
  final OrgNameRef? team;
  final OrgManagerRef? directManager;
  final List<OrgRoleRef> roles;
  final OrgRoleRef? primaryRole;

  const OrgEmployee({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.email,
    this.phoneNumber,
    this.status = 'active',
    this.jobTitle,
    this.department,
    this.team,
    this.directManager,
    this.roles = const [],
    this.primaryRole,
  });

  factory OrgEmployee.fromJson(Map<String, dynamic> json) => OrgEmployee(
        membershipId: json['membership_id'] as String,
        userId: json['user_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phoneNumber: json['phone_number'] as String?,
        status: json['status'] as String? ?? 'active',
        jobTitle: json['job_title'] as String?,
        department: json['department'] != null
            ? OrgNameRef.fromJson(json['department'] as Map<String, dynamic>)
            : null,
        team: json['team'] != null
            ? OrgNameRef.fromJson(json['team'] as Map<String, dynamic>)
            : null,
        directManager: json['direct_manager'] != null
            ? OrgManagerRef.fromJson(json['direct_manager'] as Map<String, dynamic>)
            : null,
        roles: (json['roles'] as List<dynamic>?)
                ?.map((r) => OrgRoleRef.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        primaryRole: json['primary_role'] != null
            ? OrgRoleRef.fromJson(json['primary_role'] as Map<String, dynamic>)
            : null,
      );
}

/// Employee assignment payload.
class EmployeeAssignmentPayload {
  final String? departmentId;
  final String? teamId;
  final String? directManagerMembershipId;
  final String? jobTitle;

  const EmployeeAssignmentPayload({
    this.departmentId,
    this.teamId,
    this.directManagerMembershipId,
    this.jobTitle,
  });

  Map<String, dynamic> toJson() => {
        'department_id': departmentId,
        'team_id': teamId,
        'direct_manager_membership_id': directManagerMembershipId,
        'job_title': jobTitle,
      };
}

// ── Shared ref types ─────────────────────────────────────────

class OrgNameRef {
  final String id;
  final String name;
  const OrgNameRef({required this.id, required this.name});
  factory OrgNameRef.fromJson(Map<String, dynamic> json) => OrgNameRef(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
      );
}

class OrgManagerRef {
  final String membershipId;
  final String fullName;
  final String email;
  const OrgManagerRef({required this.membershipId, required this.fullName, required this.email});
  factory OrgManagerRef.fromJson(Map<String, dynamic> json) => OrgManagerRef(
        membershipId: json['membership_id'] as String,
        fullName: json['full_name'] as String? ?? '',
        email: json['email'] as String? ?? '',
      );
}

class OrgRoleRef {
  final String roleId;
  final String? roleKey;
  final String? name;
  final bool isPrimary;
  const OrgRoleRef({required this.roleId, this.roleKey, this.name, this.isPrimary = false});
  factory OrgRoleRef.fromJson(Map<String, dynamic> json) => OrgRoleRef(
        roleId: json['role_id'] as String,
        roleKey: json['role_key'] as String?,
        name: json['name'] as String?,
        isPrimary: json['is_primary'] as bool? ?? false,
      );
}
