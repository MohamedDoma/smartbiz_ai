// SmartBiz AI — Org structure state management.
import 'package:flutter/foundation.dart';
import '../../core/api/org_models.dart';
import '../../core/api/org_service.dart';

class OrgStructureState extends ChangeNotifier {
  final OrgService _service;
  OrgStructureState(this._service);

  List<OrgDepartment> _departments = [];
  List<OrgTeam> _teams = [];
  List<OrgEmployee> _employees = [];
  bool _loading = false;
  String? _error;

  List<OrgDepartment> get departments => _departments;
  List<OrgTeam> get teams => _teams;
  List<OrgEmployee> get employees => _employees;
  bool get loading => _loading;
  String? get error => _error;

  // ── Load all ───────────────────────────────────────────────

  Future<void> loadAll() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _service.listDepartments(),
        _service.listTeams(),
        _service.listEmployees(),
      ]);
      _departments = results[0] as List<OrgDepartment>;
      _teams = results[1] as List<OrgTeam>;
      _employees = results[2] as List<OrgEmployee>;
    } catch (e) {
      _error = e.toString();
    }
    _loading = false;
    notifyListeners();
  }

  // ── Departments ────────────────────────────────────────────

  Future<OrgDepartment?> createDepartment(DepartmentPayload payload) async {
    try {
      final dept = await _service.createDepartment(payload);
      _departments = [..._departments, dept];
      notifyListeners();
      return dept;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteDepartment(String id) async {
    try {
      await _service.deleteDepartment(id);
      _departments = _departments.where((d) => d.id != id).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ── Teams ──────────────────────────────────────────────────

  Future<OrgTeam?> createTeam(TeamPayload payload) async {
    try {
      final team = await _service.createTeam(payload);
      _teams = [..._teams, team];
      notifyListeners();
      return team;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> deleteTeam(String id) async {
    try {
      await _service.deleteTeam(id);
      _teams = _teams.where((t) => t.id != id).toList();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  // ── Employee Assignment ────────────────────────────────────

  Future<OrgEmployee?> assignEmployee(
    String membershipId,
    EmployeeAssignmentPayload payload,
  ) async {
    try {
      final updated = await _service.updateEmployeeAssignment(membershipId, payload);
      _employees = _employees.map((e) => e.membershipId == membershipId ? updated : e).toList();
      notifyListeners();
      return updated;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
}
