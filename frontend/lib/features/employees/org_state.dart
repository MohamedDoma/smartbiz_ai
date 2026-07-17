// SmartBiz AI — Organization state management (backend-backed).
// Loads departments and teams from the real API.
// All mutations go through the backend; local state is refreshed from the response.
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/api_exceptions.dart';
import 'models/org_models.dart';
import 'data/org_api_service.dart';

/// Organization structure mode.
enum OrgMode { flat, departments, departmentsTeams }

class OrgState extends ChangeNotifier {
  OrgMode _mode = OrgMode.departmentsTeams;

  List<Department> _departments = [];
  List<Team> _teams = [];

  bool _loading = false;
  bool _initialized = false;
  String? _error;

  late OrgApiService _api;
  bool _apiReady = false;

  // ── Initialization ──────────────────────────────────────

  /// Wire the API client. Must be called before any API operations.
  void setApiClient(ApiClient client) {
    _api = OrgApiService(client);
    _apiReady = true;
  }

  /// Load departments and teams from the backend.
  Future<void> loadAll() async {
    if (!_apiReady) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _api.listDepartments(),
        _api.listTeams(),
      ]);
      _departments = results[0] as List<Department>;
      _teams = results[1] as List<Team>;
      _initialized = true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Getters ─────────────────────────────────────────────

  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;

  OrgMode get mode => _mode;
  bool get teamsEnabled => _mode == OrgMode.departmentsTeams;
  bool get deptsEnabled => _mode != OrgMode.flat;

  void setMode(OrgMode m) {
    _mode = m;
    notifyListeners();
  }

  List<Department> get departments => List.unmodifiable(_departments);
  int get deptCount => _departments.length;

  Department? getDept(String id) {
    try {
      return _departments.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Team> get teams => List.unmodifiable(_teams);
  int get teamCount => _teams.length;

  List<Team> teamsForDept(String deptId) =>
      _teams.where((t) => t.departmentId == deptId).toList();

  Team? getTeam(String id) {
    try {
      return _teams.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Department CRUD ─────────────────────────────────────

  /// Create a department via the backend. Returns the error message, or null.
  Future<String?> addDept({required String name, String? description}) async {
    if (!_apiReady) return 'API not initialized';
    try {
      final dept = await _api.createDepartment(
        name: name,
        description: description,
      );
      _departments = [..._departments, dept];
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Edit a department via the backend. Returns the error message, or null.
  Future<String?> editDept(
    String id, {
    String? name,
    String? description,
  }) async {
    if (!_apiReady) return 'API not initialized';
    try {
      final updated = await _api.updateDepartment(
        id,
        name: name,
        description: description,
      );
      _departments = _departments.map((d) => d.id == id ? updated : d).toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete (deactivate) a department via the backend.
  Future<String?> deleteDept(String id) async {
    if (!_apiReady) return 'API not initialized';
    try {
      await _api.deleteDepartment(id);
      _departments = _departments.where((d) => d.id != id).toList();
      _teams = _teams.where((t) => t.departmentId != id).toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Team CRUD ───────────────────────────────────────────

  Future<String?> addTeam({
    required String name,
    required String departmentId,
    String? description,
  }) async {
    if (!_apiReady) return 'API not initialized';
    try {
      final team = await _api.createTeam(
        name: name,
        departmentId: departmentId,
        description: description,
      );
      _teams = [..._teams, team];
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> editTeam(
    String id, {
    String? name,
    String? description,
  }) async {
    if (!_apiReady) return 'API not initialized';
    try {
      final updated = await _api.updateTeam(
        id,
        name: name,
        description: description,
      );
      _teams = _teams.map((t) => t.id == id ? updated : t).toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deleteTeam(String id) async {
    if (!_apiReady) return 'API not initialized';
    try {
      await _api.deleteTeam(id);
      _teams = _teams.where((t) => t.id != id).toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }
}
