// SmartBiz AI — Org structure API service.
import '../api/api_client.dart';
import '../api/org_models.dart';

class OrgService {
  final ApiClient _client;
  OrgService(this._client);

  // ── Departments ──────────────────────────────────────────

  Future<List<OrgDepartment>> listDepartments() async {
    final response = await _client.get('/departments');
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => OrgDepartment.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrgDepartment> createDepartment(DepartmentPayload payload) async {
    final response = await _client.post('/departments', data: payload.toJson());
    return OrgDepartment.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<OrgDepartment> updateDepartment(String id, DepartmentPayload payload) async {
    final response = await _client.put('/departments/$id', data: payload.toJson());
    return OrgDepartment.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDepartment(String id) async {
    await _client.delete('/departments/$id');
  }

  // ── Teams ────────────────────────────────────────────────

  Future<List<OrgTeam>> listTeams({String? departmentId}) async {
    final params = <String, dynamic>{};
    if (departmentId != null) params['department_id'] = departmentId;
    final response = await _client.get('/teams', queryParameters: params);
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => OrgTeam.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<OrgTeam> createTeam(TeamPayload payload) async {
    final response = await _client.post('/teams', data: payload.toJson());
    return OrgTeam.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<OrgTeam> updateTeam(String id, TeamPayload payload) async {
    final response = await _client.put('/teams/$id', data: payload.toJson());
    return OrgTeam.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteTeam(String id) async {
    await _client.delete('/teams/$id');
  }

  // ── Employees ────────────────────────────────────────────

  Future<List<OrgEmployee>> listEmployees() async {
    final response = await _client.get('/workspace-employees');
    final list = response.data['data'] as List<dynamic>;
    return list.map((e) => OrgEmployee.fromJson(e as Map<String, dynamic>)).toList();
  }


  Future<OrgEmployee> updateEmployeeStatus(
    String membershipId,
    String status,
  ) async {
    final response = await _client.put(
      '/workspace-employees/$membershipId/status',
      data: {'status': status},
    );
    return OrgEmployee.fromJson(response.data['data'] as Map<String, dynamic>);
  }

  Future<OrgEmployee> updateEmployeeAssignment(
    String membershipId,
    EmployeeAssignmentPayload payload,
  ) async {
    final response = await _client.put(
      '/workspace-employees/$membershipId/assignment',
      data: payload.toJson(),
    );
    return OrgEmployee.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}
