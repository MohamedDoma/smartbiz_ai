// SmartBiz AI — Payments state management (real API).
//
// Replaces mock data with real backend CRUD via PaymentService.
// Keeps existing UI contract: filtered, statusFilter, totalReceived, etc.

import 'package:flutter/material.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/payment_models.dart';
import '../../core/api/payment_service.dart';
import 'models/payment_models.dart';

class PaymentsState extends ChangeNotifier {
  final PaymentService _service;

  PaymentsState(this._service);

  // ── Core state ──────────────────────────────────────────
  List<Payment> _payments = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  PaymentStatus? _statusFilter;

  // Cached filtered list
  List<Payment>? _filteredCache;

  // ── Getters ─────────────────────────────────────────────
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  PaymentStatus? get statusFilter => _statusFilter;

  List<Payment> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _payments.where((p) {
      if (_statusFilter != null && p.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!p.referenceNumber.toLowerCase().contains(q) &&
            !p.customerName.toLowerCase().contains(q) &&
            !(p.invoiceNumber?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return _filteredCache!;
  }

  double get totalReceived => _payments
      .where((p) => p.status == PaymentStatus.completed)
      .fold(0.0, (s, p) => s + p.amount);

  double get totalPending => _payments
      .where((p) => p.status == PaymentStatus.pending)
      .fold(0.0, (s, p) => s + p.amount);

  double get totalFailed => _payments
      .where((p) => p.status == PaymentStatus.failed)
      .fold(0.0, (s, p) => s + p.amount);

  int get completedCount =>
      _payments.where((p) => p.status == PaymentStatus.completed).length;
  int get pendingCount =>
      _payments.where((p) => p.status == PaymentStatus.pending).length;

  // ── Invalidation ────────────────────────────────────────
  void _invalidate() {
    _filteredCache = null;
    notifyListeners();
  }

  // ── Search / Filter ─────────────────────────────────────
  void setSearch(String q) {
    _search = q;
    _invalidate();
  }

  void setStatusFilter(PaymentStatus? s) {
    _statusFilter = _statusFilter == s ? null : s;
    _invalidate();
  }

  // ── Load payments from backend ──────────────────────────
  Future<void> loadPayments({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.listPayments(perPage: 50);
      _payments = result.data.map(_mapApiPayment).toList();
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ── Create payment ─────────────────────────────────────
  Future<void> recordPayment(PaymentPayload payload) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final created = await _service.createPayment(payload);
      _payments.insert(0, _mapApiPayment(created));
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
  static Payment _mapApiPayment(ApiPayment api) {
    final method = switch (api.paymentMethod) {
      'cash' => PaymentMethod.cash,
      'credit_card' => PaymentMethod.card,
      'bank_transfer' => PaymentMethod.transfer,
      'check' => PaymentMethod.transfer,
      'mobile_payment' => PaymentMethod.online,
      _ => PaymentMethod.cash,
    };

    final status = switch (api.status) {
      'completed' => PaymentStatus.completed,
      'pending' => PaymentStatus.pending,
      'failed' => PaymentStatus.failed,
      'reversed' => PaymentStatus.refunded,
      _ => PaymentStatus.completed,
    };

    return Payment(
      id: api.id,
      referenceNumber: api.referenceNumber ?? api.paymentNumber ?? api.id.substring(0, 8),
      invoiceNumber: api.invoiceId,
      customerName: '',
      amount: api.amount,
      method: method,
      status: status,
      date: api.paymentDate != null
          ? DateTime.tryParse(api.paymentDate!) ?? DateTime.now()
          : DateTime.now(),
    );
  }

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
