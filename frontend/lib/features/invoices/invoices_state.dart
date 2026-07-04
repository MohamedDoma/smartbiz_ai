// SmartBiz AI — Invoices state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/invoice_models.dart';
import 'data/mock_invoices.dart';

class InvoicesState extends ChangeNotifier {
  List<Invoice>? _invoices;
  List<Customer>? _customers;
  String _search = '';
  InvoiceStatus? _statusFilter;
  int _counter = 6;

  // Cached filtered list — invalidated on data/filter change
  List<Invoice>? _filteredCache;

  List<Invoice> get _data => _invoices ??= MockInvoices.invoices();
  List<Customer> get _custData => _customers ??= MockInvoices.customers;

  // ── Getters ─────────────────────────────────────────────
  List<Customer> get customers => List.unmodifiable(_custData);

  List<Invoice> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _data.where((inv) {
      if (_statusFilter != null && inv.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!inv.number.toLowerCase().contains(q) &&
            !inv.customer.name.toLowerCase().contains(q)) { return false; }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _filteredCache!;
  }

  InvoiceStatus? get statusFilter => _statusFilter;
  String get search => _search;

  Invoice? getById(String id) {
    try { return _data.firstWhere((i) => i.id == id); }
    catch (_) { return null; }
  }

  // ── Actions ─────────────────────────────────────────────
  void _invalidate() { _filteredCache = null; notifyListeners(); }

  void setSearch(String q) { _search = q; _invalidate(); }
  void setStatusFilter(InvoiceStatus? s) {
    _statusFilter = _statusFilter == s ? null : s;
    _invalidate();
  }

  void markAsPaid(String id) {
    final inv = getById(id);
    if (inv != null) { inv.status = InvoiceStatus.paid; _invalidate(); }
  }

  void markAsSent(String id) {
    final inv = getById(id);
    if (inv != null && inv.status == InvoiceStatus.draft) { inv.status = InvoiceStatus.sent; _invalidate(); }
  }

  void createInvoice(Customer customer, List<InvoiceItem> items) {
    final num = 'INV-${_counter.toString().padLeft(3, '0')}';
    _counter++;
    _data.add(Invoice(
      id: 'inv_$_counter',
      number: num,
      customer: customer,
      items: items,
      createdAt: DateTime.now(),
      status: InvoiceStatus.draft,
    ));
    _invalidate();
  }

  void addCustomer(Customer c) {
    _custData.add(c);
    notifyListeners();
  }
}
