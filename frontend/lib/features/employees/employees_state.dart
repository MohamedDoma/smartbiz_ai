// SmartBiz AI — Employees state management.
import 'package:flutter/material.dart';
import 'models/employee_models.dart';
import 'data/mock_employees.dart';

class EmployeesState extends ChangeNotifier {
  final List<Employee> _employees = MockEmployees.employees();
  String _search = '';
  AppRole? _roleFilter;
  EmpStatus? _statusFilter;
  int _counter = 7;

  // ── Getters ─────────────────────────────────────────────
  List<Employee> get filtered {
    return _employees.where((e) {
      if (_roleFilter != null && e.role != _roleFilter) return false;
      if (_statusFilter != null && e.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!e.name.toLowerCase().contains(q) && !e.email.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  int get totalCount => _employees.length;
  int get activeCount => _employees.where((e) => e.status == EmpStatus.active).length;
  int get invitedCount => _employees.where((e) => e.status == EmpStatus.invited).length;

  AppRole? get roleFilter => _roleFilter;
  EmpStatus? get statusFilter => _statusFilter;
  String get search => _search;

  Employee? getById(String id) {
    try { return _employees.firstWhere((e) => e.id == id); }
    catch (_) { return null; }
  }

  // ── Filter actions ──────────────────────────────────────
  void setSearch(String q) { _search = q; notifyListeners(); }
  void setRoleFilter(AppRole? r) { _roleFilter = _roleFilter == r ? null : r; notifyListeners(); }
  void setStatusFilter(EmpStatus? s) { _statusFilter = _statusFilter == s ? null : s; notifyListeners(); }

  // ── Employee actions ────────────────────────────────────
  void inviteEmployee({
    required String name,
    required String email,
    String? phone,
    required AppRole role,
    String? department,
    required AiAccess aiAccess,
    required String langPref,
  }) {
    _employees.add(Employee(
      id: 'emp_${_counter++}',
      name: name, email: email, phone: phone,
      role: role, department: department,
      status: EmpStatus.invited,
      aiAccess: aiAccess, langPref: langPref,
    ));
    notifyListeners();
  }

  void suspend(String id) {
    final e = getById(id);
    if (e != null && e.status == EmpStatus.active) { e.status = EmpStatus.suspended; notifyListeners(); }
  }

  void reactivate(String id) {
    final e = getById(id);
    if (e != null && e.status == EmpStatus.suspended) { e.status = EmpStatus.active; notifyListeners(); }
  }

  void changeRole(String id, AppRole newRole) {
    final e = getById(id);
    if (e != null) { e.role = newRole; notifyListeners(); }
  }

  void changeAiAccess(String id, AiAccess newAccess) {
    final e = getById(id);
    if (e != null) { e.aiAccess = newAccess; notifyListeners(); }
  }
}
