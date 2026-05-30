// SmartBiz AI — Organization state management (Phase 16.2).
import 'package:flutter/material.dart';
import 'models/org_models.dart';
import 'models/role_models.dart';

/// Organization structure mode.
enum OrgMode { flat, departments, departmentsTeams }

class OrgState extends ChangeNotifier {
  OrgMode _mode = OrgMode.departmentsTeams;

  final List<Department> _departments = [
    Department(id: 'dept_1', name: 'Management', description: 'Executive leadership and strategy.', managerId: 'emp_1', employeeCount: 1),
    Department(id: 'dept_2', name: 'Finance', description: 'Accounting, billing, and financial planning.', managerId: 'emp_2', employeeCount: 1),
    Department(id: 'dept_3', name: 'Sales', description: 'Customer sales and point-of-sale operations.', managerId: 'emp_3', employeeCount: 2),
    Department(id: 'dept_4', name: 'Operations', description: 'Warehouse, inventory, and logistics.', managerId: 'emp_4', employeeCount: 2),
  ];

  final List<Team> _teams = [
    Team(id: 'team_1', departmentId: 'dept_3', name: 'Retail Sales', description: 'In-store sales team.', leaderId: 'emp_3', memberIds: ['emp_3', 'emp_6']),
    Team(id: 'team_2', departmentId: 'dept_4', name: 'Warehouse Ops', description: 'Stock management team.', leaderId: 'emp_4', memberIds: ['emp_4', 'emp_5']),
  ];

  final Map<String, EmployeeAssignment> _assignments = {
    'emp_1': EmployeeAssignment(employeeId: 'emp_1', departmentId: 'dept_1', primaryRoleId: 'sys_owner'),
    'emp_2': EmployeeAssignment(employeeId: 'emp_2', departmentId: 'dept_2', primaryRoleId: 'sys_accountant', managerId: 'emp_1', extraRoleIds: ['tpl_manager']),
    'emp_3': EmployeeAssignment(employeeId: 'emp_3', departmentId: 'dept_3', teamIds: ['team_1'], primaryRoleId: 'sys_cashier', managerId: 'emp_1'),
    'emp_4': EmployeeAssignment(employeeId: 'emp_4', departmentId: 'dept_4', teamIds: ['team_2'], primaryRoleId: 'sys_warehouse', managerId: 'emp_1'),
    'emp_5': EmployeeAssignment(employeeId: 'emp_5', departmentId: 'dept_4', teamIds: ['team_2'], primaryRoleId: 'sys_employee', managerId: 'emp_4'),
    'emp_6': EmployeeAssignment(employeeId: 'emp_6', departmentId: 'dept_3', teamIds: ['team_1'], primaryRoleId: 'sys_cashier', managerId: 'emp_3'),
  };

  // Name registry for display
  final Map<String, String> _empNames = {
    'emp_1': 'Mohamed Doma', 'emp_2': 'Sara Ahmed', 'emp_3': 'Khalid Omar',
    'emp_4': 'Layla Hassan', 'emp_5': 'Ahmed Ali', 'emp_6': 'Nour Khalil',
  };

  int _deptCounter = 5;
  int _teamCounter = 3;

  // ── Org mode ────────────────────────────────────────────
  OrgMode get mode => _mode;
  bool get teamsEnabled => _mode == OrgMode.departmentsTeams;
  bool get deptsEnabled => _mode != OrgMode.flat;
  void setMode(OrgMode m) { _mode = m; notifyListeners(); }

  // ── Department getters ──────────────────────────────────
  List<Department> get departments => List.unmodifiable(_departments);
  Department? getDept(String id) { try { return _departments.firstWhere((d) => d.id == id); } catch (_) { return null; } }
  int get deptCount => _departments.length;

  // ── Team getters ────────────────────────────────────────
  List<Team> get teams => List.unmodifiable(_teams);
  List<Team> teamsForDept(String deptId) => _teams.where((t) => t.departmentId == deptId).toList();
  Team? getTeam(String id) { try { return _teams.firstWhere((t) => t.id == id); } catch (_) { return null; } }
  int get teamCount => _teams.length;

  // ── Assignment getters ──────────────────────────────────
  EmployeeAssignment? getAssignment(String empId) => _assignments[empId];
  Map<String, EmployeeAssignment> get allAssignments => Map.unmodifiable(_assignments);
  int get managerCount => _assignments.values.where((a) => _assignments.values.any((b) => b.managerId == a.employeeId)).length;
  int get assignedCount => _assignments.values.where((a) => a.departmentId != null).length;
  int get unassignedCount => _empNames.length - assignedCount;
  List<String> get allEmployeeIds => _empNames.keys.toList();
  List<String> employeesInDept(String deptId) => _assignments.entries.where((e) => e.value.departmentId == deptId).map((e) => e.key).toList();

  // ── Name helpers ────────────────────────────────────────
  String empName(String id) => _empNames[id] ?? 'Employee';
  void registerName(String id, String name) { _empNames[id] = name; }

  // ── Org chart ───────────────────────────────────────────
  OrgNode buildOrgTree() {
    final rootId = _assignments.entries.firstWhere((e) => e.value.managerId == null, orElse: () => _assignments.entries.first).key;
    return _buildNode(rootId);
  }

  OrgNode _buildNode(String empId) {
    final a = _assignments[empId];
    final children = _assignments.entries.where((e) => e.value.managerId == empId).map((e) => _buildNode(e.key)).toList();
    final isDeptMgr = _departments.any((d) => d.managerId == empId);
    final isTeamLead = _teams.any((t) => t.leaderId == empId);
    String? badge;
    if (isDeptMgr) badge = 'org_dept_mgr';
    if (isTeamLead) badge = badge != null ? 'org_both_lead' : 'org_team_lead';
    return OrgNode(employeeId: empId, name: empName(empId), role: a?.primaryRoleId ?? 'sys_employee',
      title: _deptTitle(a?.departmentId), badge: badge, children: children);
  }

  String? _deptTitle(String? deptId) => deptId == null ? null : getDept(deptId)?.name;

  String roleLabel(String roleId) => switch (roleId) {
    'sys_owner' => 'Owner', 'sys_cashier' => 'Cashier', 'sys_warehouse' => 'Warehouse',
    'sys_accountant' => 'Accountant', 'sys_employee' => 'Employee',
    'tpl_manager' => 'Manager', 'tpl_sales' => 'Sales', 'tpl_hr' => 'HR',
    'tpl_procurement' => 'Procurement', 'tpl_gen_manager' => 'General Manager',
    'tpl_dept_manager' => 'Dept Manager', 'tpl_team_leader' => 'Team Leader',
    'tpl_sales_rep' => 'Sales Rep', 'tpl_hr_mgr' => 'HR Manager',
    'tpl_hr_asst' => 'HR Assistant', 'tpl_wh_mgr' => 'WH Manager',
    'tpl_procurement_off' => 'Procurement', 'tpl_support' => 'Support',
    'tpl_pm' => 'Project Mgr', 'tpl_service' => 'Service',
    'tpl_delivery' => 'Delivery',
    _ => 'Custom',
  };

  // ── Department CRUD ─────────────────────────────────────
  void addDept({required String name, required String description, String? managerId}) {
    _departments.add(Department(id: 'dept_${_deptCounter++}', name: name, description: description, managerId: managerId));
    notifyListeners();
  }

  void editDept(String id, {String? name, String? description}) {
    final d = getDept(id); if (d == null) return;
    if (name != null) d.name = name;
    if (description != null) d.description = description;
    notifyListeners();
  }

  void setDeptManager(String deptId, String? managerId) {
    final d = getDept(deptId); if (d == null) return;
    d.managerId = managerId;
    notifyListeners();
  }

  void deleteDept(String id) {
    _departments.removeWhere((d) => d.id == id);
    _teams.removeWhere((t) => t.departmentId == id);
    for (final a in _assignments.values) { if (a.departmentId == id) a.departmentId = null; }
    notifyListeners();
  }

  // ── Team CRUD ───────────────────────────────────────────
  void addTeam({required String departmentId, required String name, required String description, String? leaderId}) {
    _teams.add(Team(id: 'team_${_teamCounter++}', departmentId: departmentId, name: name, description: description, leaderId: leaderId));
    notifyListeners();
  }

  void editTeam(String id, {String? name, String? description}) {
    final t = getTeam(id); if (t == null) return;
    if (name != null) t.name = name;
    if (description != null) t.description = description;
    notifyListeners();
  }

  void setTeamLeader(String teamId, String? leaderId) {
    final t = getTeam(teamId); if (t == null) return;
    t.leaderId = leaderId;
    notifyListeners();
  }

  void addTeamMember(String teamId, String empId) {
    final t = getTeam(teamId); if (t == null) return;
    if (!t.memberIds.contains(empId)) t.memberIds.add(empId);
    addToTeam(empId, teamId);
    notifyListeners();
  }

  void removeTeamMember(String teamId, String empId) {
    final t = getTeam(teamId); if (t == null) return;
    t.memberIds.remove(empId);
    removeFromTeam(empId, teamId);
    notifyListeners();
  }

  void deleteTeam(String id) {
    _teams.removeWhere((t) => t.id == id);
    for (final a in _assignments.values) { a.teamIds.remove(id); }
    notifyListeners();
  }

  // ── Assignment ──────────────────────────────────────────
  void ensureAssignment(String empId) {
    _assignments.putIfAbsent(empId, () => EmployeeAssignment(employeeId: empId, primaryRoleId: 'sys_employee'));
  }

  void assignDept(String empId, String? deptId) {
    ensureAssignment(empId);
    _assignments[empId]!.departmentId = deptId;
    notifyListeners();
  }

  void assignManager(String empId, String? managerId) {
    ensureAssignment(empId);
    _assignments[empId]!.managerId = managerId;
    notifyListeners();
  }

  void setPrimaryRole(String empId, String roleId) {
    ensureAssignment(empId);
    _assignments[empId]!.primaryRoleId = roleId;
    notifyListeners();
  }

  void toggleExtraRole(String empId, String roleId) {
    ensureAssignment(empId);
    final list = _assignments[empId]!.extraRoleIds;
    if (list.contains(roleId)) { list.remove(roleId); } else { list.add(roleId); }
    notifyListeners();
  }

  void addToTeam(String empId, String teamId) {
    ensureAssignment(empId);
    final list = _assignments[empId]!.teamIds;
    if (!list.contains(teamId)) list.add(teamId);
  }

  void removeFromTeam(String empId, String teamId) {
    _assignments[empId]?.teamIds.remove(teamId);
  }

  // ── Effective permissions calculation ───────────────────
  /// Returns merged permissions from primary + extra roles.
  Map<AppModule, Set<PermAction>> effectivePermissions(String empId, Map<String, CustomRole> rolesMap) {
    final a = _assignments[empId];
    if (a == null) return {};
    final result = <AppModule, Set<PermAction>>{};
    void merge(String roleId) {
      final role = rolesMap[roleId];
      if (role == null) return;
      for (final e in role.permissions.entries) {
        result.putIfAbsent(e.key, () => {});
        result[e.key]!.addAll(e.value.enabled);
      }
    }
    merge(a.primaryRoleId);
    for (final extra in a.extraRoleIds) { merge(extra); }
    return result;
  }
}
