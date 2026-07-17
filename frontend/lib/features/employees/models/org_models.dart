// SmartBiz AI — Organization structure models (backend-backed).
// Matches the JSON shape from DepartmentController and TeamController.

/// A department from the backend.
class Department {
  final String id;
  final String workspaceId;
  final String? departmentKey;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final DeptManager? manager;
  final int memberCount;
  final int teamCount;

  const Department({
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

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    workspaceId: json['workspace_id'] as String? ?? '',
    departmentKey: json['department_key'] as String?,
    name: json['name'] as String,
    description: json['description'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: json['sort_order'] as int? ?? 0,
    manager: json['manager'] != null
        ? DeptManager.fromJson(json['manager'] as Map<String, dynamic>)
        : null,
    memberCount: json['member_count'] as int? ?? 0,
    teamCount: json['team_count'] as int? ?? 0,
  );
}

class DeptManager {
  final String membershipId;
  final String fullName;
  final String email;

  const DeptManager({
    required this.membershipId,
    required this.fullName,
    required this.email,
  });

  factory DeptManager.fromJson(Map<String, dynamic> json) => DeptManager(
    membershipId: json['membership_id'] as String,
    fullName: json['full_name'] as String,
    email: json['email'] as String? ?? '',
  );
}

/// A team from the backend.
class Team {
  final String id;
  final String workspaceId;
  final String? departmentId;
  final TeamDepartment? department;
  final String? teamKey;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final DeptManager? manager;
  final int memberCount;

  const Team({
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

  factory Team.fromJson(Map<String, dynamic> json) => Team(
    id: json['id'] as String,
    workspaceId: json['workspace_id'] as String? ?? '',
    departmentId: json['department_id'] as String?,
    department: json['department'] != null
        ? TeamDepartment.fromJson(json['department'] as Map<String, dynamic>)
        : null,
    teamKey: json['team_key'] as String?,
    name: json['name'] as String,
    description: json['description'] as String?,
    isActive: json['is_active'] as bool? ?? true,
    sortOrder: json['sort_order'] as int? ?? 0,
    manager: json['manager'] != null
        ? DeptManager.fromJson(json['manager'] as Map<String, dynamic>)
        : null,
    memberCount: json['member_count'] as int? ?? 0,
  );
}

class TeamDepartment {
  final String id;
  final String name;

  const TeamDepartment({required this.id, required this.name});

  factory TeamDepartment.fromJson(Map<String, dynamic> json) =>
      TeamDepartment(id: json['id'] as String, name: json['name'] as String);
}
