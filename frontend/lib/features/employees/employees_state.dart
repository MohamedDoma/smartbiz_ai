// SmartBiz AI — Employees state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/employee_models.dart';
import 'data/mock_employees.dart';

class EmployeesState extends ChangeNotifier {
  List<Employee>? _employees;
  String _search = '';
  AppRole? _roleFilter;
  EmpStatus? _statusFilter;
  int _counter = 7;

  List<Employee>? _filteredCache;

  List<Employee> get _data => _employees ??= MockEmployees.employees();

  // ── Getters ─────────────────────────────────────────────
  List<Employee> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _data.where((e) {
      if (_roleFilter != null && e.role != _roleFilter) return false;
      if (_statusFilter != null && e.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!e.name.toLowerCase().contains(q) && !e.email.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _filteredCache!;
  }

  int get totalCount => _data.length;
  int get activeCount => _data.where((e) => e.status == EmpStatus.active).length;
  int get invitedCount => _data.where((e) => e.status == EmpStatus.invited).length;

  AppRole? get roleFilter => _roleFilter;
  EmpStatus? get statusFilter => _statusFilter;
  String get search => _search;

  Employee? getById(String id) {
    try { return _data.firstWhere((e) => e.id == id); }
    catch (_) { return null; }
  }

  // ── Filter actions ──────────────────────────────────────
  void _invalidate() { _filteredCache = null; notifyListeners(); }

  void setSearch(String q) { _search = q; _invalidate(); }
  void setRoleFilter(AppRole? r) { _roleFilter = _roleFilter == r ? null : r; _invalidate(); }
  void setStatusFilter(EmpStatus? s) { _statusFilter = _statusFilter == s ? null : s; _invalidate(); }

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
    _data.add(Employee(
      id: 'emp_${_counter++}',
      name: name, email: email, phone: phone,
      role: role, department: department,
      status: EmpStatus.invited,
      aiAccess: aiAccess, langPref: langPref,
    ));
    _invalidate();
  }

  void suspend(String id) {
    final e = getById(id);
    if (e != null && e.status == EmpStatus.active) { e.status = EmpStatus.suspended; _invalidate(); }
  }

  void reactivate(String id) {
    final e = getById(id);
    if (e != null && e.status == EmpStatus.suspended) { e.status = EmpStatus.active; _invalidate(); }
  }

  void changeRole(String id, AppRole newRole) {
    final e = getById(id);
    if (e != null) { e.role = newRole; _invalidate(); }
  }

  void changeAiAccess(String id, AiAccess newAccess) {
    final e = getById(id);
    if (e != null) { e.aiAccess = newAccess; notifyListeners(); }
  }
}
