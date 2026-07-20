// SmartBiz AI — Employees state (backend-only).
import 'package:flutter/foundation.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/org_models.dart';
import '../../core/api/org_service.dart';

class EmployeesState extends ChangeNotifier {
  final OrgService _service;

  EmployeesState(this._service);

  List<OrgEmployee> _employees = const [];
  bool _loading = false;
  bool _initialized = false;
  String? _error;
  String _search = '';
  String? _roleKeyFilter;
  String? _statusFilter;

  List<OrgEmployee> get employees => List.unmodifiable(_employees);
  bool get loading => _loading;
  bool get initialized => _initialized;
  String? get error => _error;
  String get search => _search;
  String? get roleKeyFilter => _roleKeyFilter;
  String? get statusFilter => _statusFilter;

  List<OrgEmployee> get filtered {
    final query = _search.trim().toLowerCase();
    final result = _employees.where((employee) {
      if (_statusFilter != null && employee.status != _statusFilter) {
        return false;
      }
      if (_roleKeyFilter != null &&
          !employee.roles.any((role) => role.roleKey == _roleKeyFilter)) {
        return false;
      }
      if (query.isNotEmpty &&
          !employee.fullName.toLowerCase().contains(query) &&
          !employee.email.toLowerCase().contains(query) &&
          !(employee.jobTitle ?? '').toLowerCase().contains(query)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return result;
  }

  List<OrgRoleRef> get availableRoles {
    final byId = <String, OrgRoleRef>{};
    for (final employee in _employees) {
      for (final role in employee.roles) {
        byId[role.roleId] = role;
      }
    }
    final roles = byId.values.toList()
      ..sort((a, b) => (a.name ?? a.roleKey ?? '')
          .toLowerCase()
          .compareTo((b.name ?? b.roleKey ?? '').toLowerCase()));
    return roles;
  }

  int get totalCount => _employees.length;
  int get activeCount => _employees.where((e) => e.status == 'active').length;
  int get suspendedCount =>
      _employees.where((e) => e.status == 'suspended').length;

  OrgEmployee? getById(String membershipId) {
    try {
      return _employees.firstWhere((e) => e.membershipId == membershipId);
    } catch (_) {
      return null;
    }
  }

  Future<void> load({bool force = false}) async {
    if (_loading || (_initialized && !force)) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _employees = await _service.listEmployees();
      _initialized = true;
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(force: true);

  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  void setRoleFilter(String? roleKey) {
    _roleKeyFilter = _roleKeyFilter == roleKey ? null : roleKey;
    notifyListeners();
  }

  void setStatusFilter(String? status) {
    _statusFilter = _statusFilter == status ? null : status;
    notifyListeners();
  }

  void clearFilters() {
    _roleKeyFilter = null;
    _statusFilter = null;
    notifyListeners();
  }

  Future<String?> updateStatus(String membershipId, String status) async {
    try {
      final updated = await _service.updateEmployeeStatus(membershipId, status);
      _replace(updated);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  void syncEmployee(OrgEmployee employee) => _replace(employee);

  void _replace(OrgEmployee employee) {
    _employees = _employees
        .map((item) => item.membershipId == employee.membershipId ? employee : item)
        .toList();
    notifyListeners();
  }
}
