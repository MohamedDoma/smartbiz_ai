// SmartBiz AI — Organization API service.
// Wraps ApiClient for /departments and /teams endpoints.
import '../../../core/api/api_client.dart';
import '../models/org_models.dart';

class OrgApiService {
  final ApiClient _client;

  OrgApiService(this._client);

  // ── Departments ─────────────────────────────────────────

  Future<List<Department>> listDepartments() async {
    final res = await _client.get('/departments');
    final list = (res.data['data'] as List?) ?? [];
    return list
        .map((e) => Department.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Department> createDepartment({
    required String name,
    String? description,
    String? managerMembershipId,
    int? sortOrder,
  }) async {
    final res = await _client.post(
      '/departments',
      data: {
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (managerMembershipId != null)
          'manager_membership_id': managerMembershipId,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
    );
    return Department.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<Department> updateDepartment(
    String id, {
    String? name,
    String? description,
    bool? isActive,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isActive != null) body['is_active'] = isActive;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final res = await _client.put('/departments/$id', data: body);
    return Department.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDepartment(String id) async {
    await _client.delete('/departments/$id');
  }

  // ── Teams ───────────────────────────────────────────────

  Future<List<Team>> listTeams({String? departmentId}) async {
    final params = <String, dynamic>{};
    if (departmentId != null) params['department_id'] = departmentId;
    final res = await _client.get('/teams', queryParameters: params);
    final list = (res.data['data'] as List?) ?? [];
    return list.map((e) => Team.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Team> createTeam({
    required String name,
    String? departmentId,
    String? description,
    String? managerMembershipId,
    int? sortOrder,
  }) async {
    final res = await _client.post(
      '/teams',
      data: {
        'name': name,
        if (departmentId != null) 'department_id': departmentId,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (managerMembershipId != null)
          'manager_membership_id': managerMembershipId,
        if (sortOrder != null) 'sort_order': sortOrder,
      },
    );
    return Team.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<Team> updateTeam(
    String id, {
    String? name,
    String? departmentId,
    String? description,
    bool? isActive,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (departmentId != null) body['department_id'] = departmentId;
    if (description != null) body['description'] = description;
    if (isActive != null) body['is_active'] = isActive;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final res = await _client.put('/teams/$id', data: body);
    return Team.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> deleteTeam(String id) async {
    await _client.delete('/teams/$id');
  }
}
