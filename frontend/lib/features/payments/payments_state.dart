// SmartBiz AI — Payments state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/payment_models.dart';
import 'data/mock_payments.dart';

class PaymentsState extends ChangeNotifier {
  List<Payment>? _payments;
  String _search = '';
  PaymentStatus? _statusFilter;
  List<Payment>? _filteredCache;

  List<Payment> get _data => _payments ??= MockPayments.payments();

  // ── Getters ─────────────────────────────────────────────
  List<Payment> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _data.where((p) {
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

  PaymentStatus? get statusFilter => _statusFilter;
  String get search => _search;

  double get totalReceived => _data
      .where((p) => p.status == PaymentStatus.completed)
      .fold(0.0, (s, p) => s + p.amount);

  double get totalPending => _data
      .where((p) => p.status == PaymentStatus.pending)
      .fold(0.0, (s, p) => s + p.amount);

  double get totalFailed => _data
      .where((p) => p.status == PaymentStatus.failed)
      .fold(0.0, (s, p) => s + p.amount);

  int get completedCount => _data.where((p) => p.status == PaymentStatus.completed).length;
  int get pendingCount => _data.where((p) => p.status == PaymentStatus.pending).length;

  // ── Actions ─────────────────────────────────────────────
  void _invalidate() { _filteredCache = null; notifyListeners(); }

  void setSearch(String q) { _search = q; _invalidate(); }
  void setStatusFilter(PaymentStatus? s) {
    _statusFilter = _statusFilter == s ? null : s;
    _invalidate();
  }
}
