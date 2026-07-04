// SmartBiz AI — Finance state management.
// Performance: lazy mock data + cached filtered expenses.
import 'package:flutter/material.dart';
import 'models/finance_models.dart';
import 'data/mock_finance.dart';

class FinanceState extends ChangeNotifier {
  List<Expense>? _expenses;
  List<Transaction>? _transactions;
  FinanceSummary? _summary;
  ExpenseCategory? _categoryFilter;
  int _counter = 8;

  List<Expense>? _filteredCache;

  List<Expense> get _expData => _expenses ??= MockFinance.expenses();
  List<Transaction> get _txData => _transactions ??= MockFinance.transactions();

  // ── Getters ─────────────────────────────────────────────
  FinanceSummary get summary => _summary ??= MockFinance.summary;
  List<Transaction> get transactions => List.unmodifiable(_txData);

  List<Expense> get filteredExpenses {
    if (_filteredCache != null) return _filteredCache!;
    if (_categoryFilter == null) {
      _filteredCache = List.unmodifiable(_expData);
    } else {
      _filteredCache = _expData.where((e) => e.category == _categoryFilter).toList();
    }
    return _filteredCache!;
  }

  ExpenseCategory? get categoryFilter => _categoryFilter;
  double get totalExpenses => _expData.fold(0.0, (s, e) => s + e.amount);

  // ── Filter ──────────────────────────────────────────────
  void setCategoryFilter(ExpenseCategory? c) {
    _categoryFilter = _categoryFilter == c ? null : c;
    _filteredCache = null;
    notifyListeners();
  }

  // ── Actions ─────────────────────────────────────────────
  void addExpense({required String title, required double amount, required ExpenseCategory category}) {
    _expData.insert(0, Expense(
      id: 'e${_counter++}',
      title: title,
      amount: amount,
      category: category,
      date: DateTime.now(),
    ));
    _txData.insert(0, Transaction(
      id: 't${_counter++}',
      type: TxnType.expenseAdded,
      description: title,
      amount: amount,
      date: DateTime.now(),
    ));
    final s = summary;
    _summary = FinanceSummary(
      totalRevenue: s.totalRevenue,
      totalExpenses: s.totalExpenses + amount,
      outstanding: s.outstanding,
      cashBalance: s.cashBalance - amount,
    );
    _filteredCache = null;
    notifyListeners();
  }

  void recordPayment({required String invoiceNumber, required String customerName, required double amount}) {
    _txData.insert(0, Transaction(
      id: 't${_counter++}',
      type: TxnType.invoicePaid,
      description: '$invoiceNumber — $customerName',
      amount: amount,
      date: DateTime.now(),
    ));
    final s = summary;
    _summary = FinanceSummary(
      totalRevenue: s.totalRevenue + amount,
      totalExpenses: s.totalExpenses,
      outstanding: (s.outstanding - amount).clamp(0, double.infinity),
      cashBalance: s.cashBalance + amount,
    );
    notifyListeners();
  }
}
