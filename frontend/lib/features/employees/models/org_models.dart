// SmartBiz AI — Organization structure models.
import 'role_models.dart';

/// A department in the organization.
class Department {
  final String id;
  String name;
  String description;
  String? managerId;
  int employeeCount;

  Department({
    required this.id,
    required this.name,
    required this.description,
    this.managerId,
    this.employeeCount = 0,
  });
}

/// A team within a department.
class Team {
  final String id;
  String departmentId;
  String name;
  String description;
  String? leaderId;
  List<String> memberIds;

  Team({
    required this.id,
    required this.departmentId,
    required this.name,
    required this.description,
    this.leaderId,
    List<String>? memberIds,
  }) : memberIds = memberIds ?? [];

  int get memberCount => memberIds.length;
}

/// Employee's role assignment with hybrid support.
class EmployeeAssignment {
  final String employeeId;
  String? departmentId;
  List<String> teamIds;
  String? managerId;
  String primaryRoleId;
  List<String> extraRoleIds;
  Set<_ExtraPerm> extraPermissions;

  EmployeeAssignment({
    required this.employeeId,
    this.departmentId,
    List<String>? teamIds,
    this.managerId,
    required this.primaryRoleId,
    List<String>? extraRoleIds,
    Set<_ExtraPerm>? extraPermissions,
  }) : teamIds = teamIds ?? [],
       extraRoleIds = extraRoleIds ?? [],
       extraPermissions = extraPermissions ?? {};

  bool get hasExtraRoles => extraRoleIds.isNotEmpty;
  bool get hasExtraPerms => extraPermissions.isNotEmpty;
  int get totalRoleCount => 1 + extraRoleIds.length;
}

/// A single extra permission override.
class _ExtraPerm {
  final AppModule module;
  final PermAction action;
  const _ExtraPerm(this.module, this.action);

  @override
  bool operator ==(Object other) => other is _ExtraPerm && other.module == module && other.action == action;

  @override
  int get hashCode => module.hashCode ^ action.hashCode;
}

/// Node in the org chart tree.
class OrgNode {
  final String employeeId;
  final String name;
  final String role;
  final String? title;
  final String? badge; // 'org_dept_mgr', 'org_team_lead', 'org_both_lead'
  final List<OrgNode> children;

  const OrgNode({
    required this.employeeId,
    required this.name,
    required this.role,
    this.title,
    this.badge,
    this.children = const [],
  });
}
