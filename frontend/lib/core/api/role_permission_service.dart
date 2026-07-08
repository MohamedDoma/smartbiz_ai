// SmartBiz AI — Role & permission API service (real backend).
import 'api_client.dart';
import 'role_permission_models.dart';

class RolePermissionService {
  final ApiClient _client;

  RolePermissionService(this._client);

  // ── Permission Catalog ──────────────────────────────────────

  Future<List<PermissionCategory>> listPermissionCatalog() async {
    final response = await _client.get('/permission-catalog');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(PermissionCategory.fromJson).toList();
  }

  // ── Workspace Roles ─────────────────────────────────────────

  Future<List<WorkspaceRole>> listWorkspaceRoles() async {
    final response = await _client.get('/workspace-roles');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(WorkspaceRole.fromJson).toList();
  }

  Future<WorkspaceRole> createRole(WorkspaceRolePayload payload) async {
    final response = await _client.post('/workspace-roles', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return WorkspaceRole.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<WorkspaceRole> updateRole(String roleId, WorkspaceRolePayload payload) async {
    final response = await _client.put('/workspace-roles/$roleId', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return WorkspaceRole.fromJson(data['data'] as Map<String, dynamic>);
  }

  Future<void> deactivateRole(String roleId) async {
    await _client.post('/workspace-roles/$roleId/deactivate');
  }

  // ── Workspace Employees ─────────────────────────────────────

  Future<List<WorkspaceEmployeeMember>> listWorkspaceEmployees() async {
    final response = await _client.get('/workspace-employees');
    final data = response.data as Map<String, dynamic>;
    final list = data['data'] as List<dynamic>? ?? [];
    return list.whereType<Map<String, dynamic>>().map(WorkspaceEmployeeMember.fromJson).toList();
  }

  Future<WorkspaceEmployeeMember> updateEmployeeRoles(
    String membershipId,
    EmployeeRolesPayload payload,
  ) async {
    final response = await _client.put('/workspace-employees/$membershipId/roles', data: payload.toJson());
    final data = response.data as Map<String, dynamic>;
    return WorkspaceEmployeeMember.fromJson(data['data'] as Map<String, dynamic>);
  }
}
