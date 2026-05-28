// SmartBiz AI — Customers state management.
import 'package:flutter/material.dart';
import 'models/customer_models.dart';
import 'data/mock_customers.dart';

class CustomersState extends ChangeNotifier {
  final List<Customer> _customers = List.from(mockCustomers);
  final List<CustomerActivity> _activities = List.from(mockActivities);

  String _search = '';
  CustomerStatus? _statusFilter;

  // ── Getters ─────────────────────────────────────────────
  List<Customer> get customers {
    var list = List<Customer>.from(_customers);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) => c.name.toLowerCase().contains(q) || (c.company?.toLowerCase().contains(q) ?? false) || c.phone.contains(q) || (c.email?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (_statusFilter != null) {
      list = list.where((c) => c.status == _statusFilter).toList();
    }
    return list;
  }

  String get search => _search;
  CustomerStatus? get statusFilter => _statusFilter;
  int get totalCustomers => _customers.length;
  int get vipCount => _customers.where((c) => c.status == CustomerStatus.vip).length;
  double get totalBalance => _customers.fold(0, (s, c) => s + c.balance);

  Customer? getById(String id) {
    try { return _customers.firstWhere((c) => c.id == id); } catch (_) { return null; }
  }

  List<CustomerActivity> activitiesFor(String customerId) =>
    _activities.where((a) => a.customerId == customerId).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  // ── Actions ─────────────────────────────────────────────
  void setSearch(String v) { _search = v; notifyListeners(); }
  void setStatusFilter(CustomerStatus? v) { _statusFilter = v; notifyListeners(); }

  void addCustomer({
    required String name, String? company, String? email, required String phone,
    String? address, String? notes, CustomerStatus status = CustomerStatus.active, String langPref = 'en',
  }) {
    _customers.insert(0, Customer(
      id: 'c${DateTime.now().millisecondsSinceEpoch}',
      name: name, company: company, email: email, phone: phone,
      address: address, notes: notes, status: status, preferredLang: langPref,
      lastActivity: DateTime.now(),
    ));
    notifyListeners();
  }

  void toggleVip(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = c.status == CustomerStatus.vip ? CustomerStatus.active : CustomerStatus.vip;
    notifyListeners();
  }

  void archive(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = CustomerStatus.inactive;
    notifyListeners();
  }

  void reactivate(String id) {
    final c = getById(id);
    if (c == null) return;
    c.status = CustomerStatus.active;
    notifyListeners();
  }

  void updateNotes(String id, String notes) {
    final c = getById(id);
    if (c == null) return;
    c.notes = notes;
    notifyListeners();
  }
}
