// SmartBiz AI — Role & permission management state (real backend).
import 'package:flutter/material.dart';
import '../../core/api/role_permission_models.dart';
import '../../core/api/role_permission_service.dart';

class RolePermissionState extends ChangeNotifier {
  final RolePermissionService _service;

  RolePermissionState(this._service);

  // ── Permission Catalog ──────────────────────────────────────
  List<PermissionCategory> _catalog = [];
  bool _catalogLoading = false;
  String? _catalogError;

  List<PermissionCategory> get catalog => _catalog;
  bool get catalogLoading => _catalogLoading;
  String? get catalogError => _catalogError;

  Future<void> loadCatalog() async {
    if (_catalog.isNotEmpty) return; // Cache
    _catalogLoading = true;
    _catalogError = null;
    notifyListeners();
    try {
      _catalog = await _service.listPermissionCatalog();
    } catch (e) {
      _catalogError = e.toString();
    }
    _catalogLoading = false;
    notifyListeners();
  }

  // ── Workspace Roles ─────────────────────────────────────────
  List<WorkspaceRole> _roles = [];
  bool _rolesLoading = false;
  String? _rolesError;

  List<WorkspaceRole> get roles => _roles;
  List<WorkspaceRole> get activeRoles => _roles.where((r) => r.isActive).toList();
  List<WorkspaceRole> get nonOwnerRoles => activeRoles.where((r) => !r.isOwner).toList();
  bool get rolesLoading => _rolesLoading;
  String? get rolesError => _rolesError;

  Future<void> loadRoles() async {
    _rolesLoading = true;
    _rolesError = null;
    notifyListeners();
    try {
      _roles = await _service.listWorkspaceRoles();
    } catch (e) {
      _rolesError = e.toString();
    }
    _rolesLoading = false;
    notifyListeners();
  }

  Future<WorkspaceRole?> createRole(WorkspaceRolePayload payload) async {
    try {
      final role = await _service.createRole(payload);
      _roles = [..._roles, role];
      notifyListeners();
      return role;
    } catch (e) {
      rethrow;
    }
  }

  Future<WorkspaceRole?> updateRole(String roleId, WorkspaceRolePayload payload) async {
    try {
      final role = await _service.updateRole(roleId, payload);
      _roles = _roles.map((r) => r.id == roleId ? role : r).toList();
      notifyListeners();
      return role;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deactivateRole(String roleId) async {
    await _service.deactivateRole(roleId);
    _roles = _roles.map((r) => r.id == roleId
        ? WorkspaceRole(
            id: r.id,
            roleKey: r.roleKey,
            name: r.name,
            description: r.description,
            permissions: r.permissions,
            hierarchyLevel: r.hierarchyLevel,
            isSystem: r.isSystem,
            isDefault: r.isDefault,
            isDeletable: r.isDeletable,
            isActive: false,
            sortOrder: r.sortOrder,
            assignedCount: r.assignedCount,
          )
        : r).toList();
    notifyListeners();
  }

  // ── Workspace Employees ─────────────────────────────────────
  List<WorkspaceEmployeeMember> _employees = [];
  bool _employeesLoading = false;
  String? _employeesError;

  List<WorkspaceEmployeeMember> get employees => _employees;
  bool get employeesLoading => _employeesLoading;
  String? get employeesError => _employeesError;

  Future<void> loadEmployees() async {
    _employeesLoading = true;
    _employeesError = null;
    notifyListeners();
    try {
      _employees = await _service.listWorkspaceEmployees();
    } catch (e) {
      _employeesError = e.toString();
    }
    _employeesLoading = false;
    notifyListeners();
  }

  Future<WorkspaceEmployeeMember?> updateEmployeeRoles(
    String membershipId,
    EmployeeRolesPayload payload,
  ) async {
    try {
      final updated = await _service.updateEmployeeRoles(membershipId, payload);
      _employees = _employees.map((e) => e.membershipId == membershipId ? updated : e).toList();
      notifyListeners();
      return updated;
    } catch (e) {
      rethrow;
    }
  }
}
