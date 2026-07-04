// SmartBiz AI — Customers state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/customer_models.dart';
import 'data/mock_customers.dart';

class CustomersState extends ChangeNotifier {
  List<Customer>? _customers;
  List<CustomerActivity>? _activities;

  String _search = '';
  CustomerStatus? _statusFilter;

  List<Customer>? _filteredCache;

  List<Customer> get _data => _customers ??= List.from(mockCustomers);
  List<CustomerActivity> get _actData => _activities ??= List.from(mockActivities);

  // ── Getters ─────────────────────────────────────────────
  List<Customer> get customers {
    if (_filteredCache != null) return _filteredCache!;
    var list = List<Customer>.from(_data);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q) || (c.company?.toLowerCase().contains(q) ?? false) || c.phone.contains(q) || (c.email?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (_statusFilter != null) {
      list = list.where((c) => c.status == _statusFilter).toList();
    }
    _filteredCache = list;
    return _filteredCache!;
  }

  String get search => _search;
  CustomerStatus? get statusFilter => _statusFilter;
  int get totalCustomers => _data.length;
  int get vipCount => _data.where((c) => c.status == CustomerStatus.vip).length;
  double get totalBalance => _data.fold(0, (s, c) => s + c.balance);

  Customer? getById(String id) {
    try { return _data.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }

  List<CustomerActivity> activitiesFor(String customerId) =>
    _actData.where((a) => a.customerId == customerId).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  // ── Actions ─────────────────────────────────────────────
  void _invalidate() { _filteredCache = null; notifyListeners(); }

  void setSearch(String v) { _search = v; _filteredCache = null; notifyListeners(); }
  void setStatusFilter(CustomerStatus? v) { _statusFilter = v; _filteredCache = null; notifyListeners(); }

  void addCustomer({
    required String name, String? company, String? email, required String phone,
    String? address, String? notes, CustomerStatus status = CustomerStatus.active, String langPref = 'en',
  }) {
    _data.insert(0, Customer(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name, company: company, email: email, phone: phone,
      address: address, notes: notes, status: status, preferredLang: langPref,
      lastActivity: DateTime.now(),
    ));
    _invalidate();
  }

  void toggleVip(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = c.status == CustomerStatus.vip ? CustomerStatus.active : CustomerStatus.vip;
    _invalidate();
  }

  void archive(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = CustomerStatus.inactive;
    _invalidate();
  }

  void reactivate(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = CustomerStatus.active;
    _invalidate();
  }

  void updateNotes(String id, String notes) {
    final c = getById(id);
    if (c == null) return;
    c.notes = notes;
    notifyListeners();
  }
}
