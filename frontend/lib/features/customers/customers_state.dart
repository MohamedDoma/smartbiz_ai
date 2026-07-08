// SmartBiz AI — Customers state management (real API).
//
// Replaces mock data with real backend CRUD via ContactService.
// Keeps existing UI contract: customers, search, statusFilter, totalCustomers, etc.

import 'package:flutter/material.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/contact_models.dart';
import '../../core/api/contact_service.dart';
import 'models/customer_models.dart';

class CustomersState extends ChangeNotifier {
  final ContactService _service;

  CustomersState(this._service);

  // ── Core state ──────────────────────────────────────────
  List<Customer> _customers = [];
  bool _loading = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String? _error;
  String _search = '';
  CustomerStatus? _statusFilter;

  // ── Cached views ────────────────────────────────────────
  List<Customer>? _filteredCache;

  // ── Getters ─────────────────────────────────────────────
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  String get search => _search;
  CustomerStatus? get statusFilter => _statusFilter;
  int get totalCustomers => _customers.length;
  int get vipCount => _customers.where((c) => c.status == CustomerStatus.vip).length;
  double get totalBalance => _customers.fold(0, (s, c) => s + c.balance);

  List<Customer> get customers {
    if (_filteredCache != null) return _filteredCache!;
    var list = List<Customer>.from(_customers);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) =>
        c.name.toLowerCase().contains(q) ||
        (c.company?.toLowerCase().contains(q) ?? false) ||
        c.phone.contains(q) ||
        (c.email?.toLowerCase().contains(q) ?? false)
      ).toList();
    }
    if (_statusFilter != null) {
      list = list.where((c) => c.status == _statusFilter).toList();
    }
    _filteredCache = list;
    return _filteredCache!;
  }

  Customer? getById(String id) {
    try {
      return _customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Activities are not yet available from backend — return empty list.
  List<CustomerActivity> activitiesFor(String customerId) => [];

  // ── Invalidation ────────────────────────────────────────
  void _invalidate() {
    _filteredCache = null;
    notifyListeners();
  }

  // ── Search / Filter ─────────────────────────────────────
  void setSearch(String v) {
    _search = v;
    _filteredCache = null;
    notifyListeners();
  }

  void setStatusFilter(CustomerStatus? v) {
    _statusFilter = v;
    _filteredCache = null;
    notifyListeners();
  }

  // ── Load contacts from backend ──────────────────────────
  Future<void> loadCustomers({bool refresh = false}) async {
    if (_loading) return;

    if (refresh) {
      _currentPage = 1;
      _hasMore = false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.listContacts(
        page: _currentPage,
        perPage: 50,
      );

      if (refresh || _currentPage == 1) {
        _customers = result.data.map(_mapApiContact).toList();
      } else {
        _customers.addAll(result.data.map(_mapApiContact));
      }

      _hasMore = result.hasMore;
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  /// Load next page if available.
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    _currentPage++;
    await loadCustomers();
  }

  // ── Create contact ─────────────────────────────────────
  Future<void> addCustomer({
    required String name,
    String? company,
    String? email,
    required String phone,
    String? address,
    String? notes,
    String? taxNumber,
    CustomerStatus status = CustomerStatus.active,
    String langPref = 'en',
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = ContactPayload(
        name: name,
        type: 'customer',
        phone: phone.isNotEmpty ? phone : null,
        email: email,
        address: address,
        taxNumber: taxNumber,
      );
      final created = await _service.createContact(payload);
      _customers.insert(0, _mapApiContact(created));
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Update contact ─────────────────────────────────────
  Future<void> updateCustomer({
    required String id,
    required String name,
    String? phone,
    String? email,
    String? address,
    String? taxNumber,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = ContactPayload(
        name: name,
        type: 'customer',
        phone: phone,
        email: email,
        address: address,
        taxNumber: taxNumber,
      );
      final updated = await _service.updateContact(id, payload);
      final idx = _customers.indexWhere((c) => c.id == id);
      if (idx >= 0) _customers[idx] = _mapApiContact(updated);
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Delete contact ─────────────────────────────────────
  Future<void> deleteCustomer(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deleteContact(id);
      _customers.removeWhere((c) => c.id == id);
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Map backend model to UI model ──────────────────────
  static Customer _mapApiContact(ApiContact api) => Customer(
        id: api.id,
        name: api.name,
        phone: api.phone ?? '',
        email: api.email,
        address: api.address,
        balance: api.balance,
      );

  // ── Error formatting ───────────────────────────────────
  String _friendlyError(dynamic e) {
    if (e is ValidationException) {
      final msgs = e.errors.values.expand((v) => v).toList();
      return msgs.isNotEmpty ? msgs.first : e.message;
    }
    if (e is AuthException) return 'Session expired. Please login again.';
    if (e is NetworkException) return 'Network error. Check your connection.';
    if (e is ApiException) return e.message;
    return 'Something went wrong.';
  }
}
