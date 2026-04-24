// SmartBiz AI — Finance state management.
import 'package:flutter/material.dart';
import 'models/finance_models.dart';
import 'data/mock_finance.dart';

class FinanceState extends ChangeNotifier {
  final List<Expense> _expenses = MockFinance.expenses();
  final List<Transaction> _transactions = MockFinance.transactions();
  FinanceSummary _summary = MockFinance.summary;
  ExpenseCategory? _categoryFilter;
  int _counter = 8;

  // ── Getters ─────────────────────────────────────────────
  FinanceSummary get summary => _summary;
  List<Transaction> get transactions => List.unmodifiable(_transactions);

  List<Expense> get filteredExpenses {
    if (_categoryFilter == null) return List.unmodifiable(_expenses);
    return _expenses.where((e) => e.category == _categoryFilter).toList();
  }

  ExpenseCategory? get categoryFilter => _categoryFilter;
  double get totalExpenses => _expenses.fold(0.0, (s, e) => s + e.amount);

  // ── Filter ──────────────────────────────────────────────
  void setCategoryFilter(ExpenseCategory? c) {
    _categoryFilter = _categoryFilter == c ? null : c;
    notifyListeners();
  }

  // ── Actions ─────────────────────────────────────────────
  void addExpense({required String title, required double amount, required ExpenseCategory category}) {
    _expenses.insert(0, Expense(
      id: 'e${_counter++}',
      title: title,
      amount: amount,
      category: category,
      date: DateTime.now(),
    ));
    _transactions.insert(0, Transaction(
      id: 't${_counter++}',
      type: TxnType.expenseAdded,
      description: title,
      amount: amount,
      date: DateTime.now(),
    ));
    _summary = FinanceSummary(
      totalRevenue: _summary.totalRevenue,
      totalExpenses: _summary.totalExpenses + amount,
      outstanding: _summary.outstanding,
      cashBalance: _summary.cashBalance - amount,
    );
    notifyListeners();
  }

  void recordPayment({required String invoiceNumber, required String customerName, required double amount}) {
    _transactions.insert(0, Transaction(
      id: 't${_counter++}',
      type: TxnType.invoicePaid,
      description: '$invoiceNumber — $customerName',
      amount: amount,
      date: DateTime.now(),
    ));
    _summary = FinanceSummary(
      totalRevenue: _summary.totalRevenue + amount,
      totalExpenses: _summary.totalExpenses,
      outstanding: (_summary.outstanding - amount).clamp(0, double.infinity),
      cashBalance: _summary.cashBalance + amount,
    );
    notifyListeners();
  }
}
