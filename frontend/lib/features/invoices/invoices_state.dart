// SmartBiz AI — Invoices state management (real API).
//
// Replaces mock data with real backend CRUD via InvoiceService.
// Keeps existing UI contract: filtered, statusFilter, getById, etc.

import 'package:flutter/material.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/invoice_models.dart';
import '../../core/api/invoice_service.dart';
import 'models/invoice_models.dart';

class InvoicesState extends ChangeNotifier {
  final InvoiceService _service;

  InvoicesState(this._service);

  // ── Core state ──────────────────────────────────────────
  List<Invoice> _invoices = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  InvoiceStatus? _statusFilter;

  // Cached filtered list
  List<Invoice>? _filteredCache;

  // ── Getters ─────────────────────────────────────────────
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  InvoiceStatus? get statusFilter => _statusFilter;

  List<Invoice> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _invoices.where((inv) {
      if (_statusFilter != null && inv.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!inv.number.toLowerCase().contains(q) &&
            !inv.customer.name.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _filteredCache!;
  }

  Invoice? getById(String id) {
    try {
      return _invoices.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

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

  void setStatusFilter(InvoiceStatus? s) {
    _statusFilter = _statusFilter == s ? null : s;
    _invalidate();
  }

  // ── Load invoices from backend ──────────────────────────
  Future<void> loadInvoices({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.listInvoices(perPage: 50);
      _invoices = result.data.map(_mapApiInvoice).toList();
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ── Create invoice ─────────────────────────────────────
  Future<void> createInvoice(InvoicePayload payload) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final created = await _service.createInvoice(payload);
      _invoices.insert(0, _mapApiInvoice(created));
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Mark as paid (backend update) ──────────────────────
  Future<void> markAsPaid(String id) async {
    try {
      final updated =
          await _service.updateInvoice(id, {'payment_status': 'paid'});
      final idx = _invoices.indexWhere((i) => i.id == id);
      if (idx >= 0) _invoices[idx] = _mapApiInvoice(updated);
      _invalidate();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ── Map backend model to UI model ──────────────────────
  static Invoice _mapApiInvoice(ApiInvoice api) {
    final items = api.items
        .map((i) => InvoiceItem(
              productName: i.productNameSnapshot ?? 'Item',
              quantity: i.quantity.round(),
              unitPrice: i.unitPrice,
            ))
        .toList();

    // Map payment_status to UI enum
    final status = switch (api.paymentStatus) {
      'paid' => InvoiceStatus.paid,
      'partial' => InvoiceStatus.sent,
      'overdue' => InvoiceStatus.overdue,
      'refunded' => InvoiceStatus.overdue,
      _ => InvoiceStatus.draft,
    };

    return Invoice(
      id: api.id,
      number: api.invoiceNumber ?? 'INV-${api.id.substring(0, 6).toUpperCase()}',
      customer: Customer(
        id: api.contactId ?? '',
        name: api.contactName ?? 'Unknown',
        email: api.contactEmail,
      ),
      items: items,
      createdAt: api.createdAt != null
          ? DateTime.tryParse(api.createdAt!) ?? DateTime.now()
          : DateTime.now(),
      dueDate: api.dueDate != null ? DateTime.tryParse(api.dueDate!) : null,
      status: status,
      taxRate: api.totalAmount > 0 ? api.taxAmount / api.totalAmount : 0,
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
