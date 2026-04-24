// SmartBiz AI — Invoices state management.
import 'package:flutter/material.dart';
import 'models/invoice_models.dart';
import 'data/mock_invoices.dart';

class InvoicesState extends ChangeNotifier {
  final List<Invoice> _invoices = MockInvoices.invoices();
  final List<Customer> _customers = MockInvoices.customers;
  String _search = '';
  InvoiceStatus? _statusFilter;
  int _counter = 6;

  // ── Getters ─────────────────────────────────────────────
  List<Customer> get customers => List.unmodifiable(_customers);

  List<Invoice> get filtered {
    return _invoices.where((inv) {
      if (_statusFilter != null && inv.status != _statusFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!inv.number.toLowerCase().contains(q) &&
            !inv.customer.name.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  InvoiceStatus? get statusFilter => _statusFilter;
  String get search => _search;

  Invoice? getById(String id) {
    try { return _invoices.firstWhere((i) => i.id == id); }
    catch (_) { return null; }
  }

  // ── Actions ─────────────────────────────────────────────
  void setSearch(String q) { _search = q; notifyListeners(); }
  void setStatusFilter(InvoiceStatus? s) {
    _statusFilter = _statusFilter == s ? null : s;
    notifyListeners();
  }

  void markAsPaid(String id) {
    final inv = getById(id);
    if (inv != null) { inv.status = InvoiceStatus.paid; notifyListeners(); }
  }

  void markAsSent(String id) {
    final inv = getById(id);
    if (inv != null && inv.status == InvoiceStatus.draft) { inv.status = InvoiceStatus.sent; notifyListeners(); }
  }

  void createInvoice(Customer customer, List<InvoiceItem> items) {
    final num = 'INV-${_counter.toString().padLeft(3, '0')}';
    _counter++;
    _invoices.add(Invoice(
      id: 'inv_$_counter',
      number: num,
      customer: customer,
      items: items,
      createdAt: DateTime.now(),
      status: InvoiceStatus.draft,
    ));
    notifyListeners();
  }

  void addCustomer(Customer c) {
    _customers.add(c);
    notifyListeners();
  }
}
