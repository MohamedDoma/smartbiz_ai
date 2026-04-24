// SmartBiz AI — Mock finance data.
import '../models/finance_models.dart';

class MockFinance {
  MockFinance._();

  static List<Expense> expenses() => [
    Expense(id: 'e1', title: 'Office Rent', amount: 3500, category: ExpenseCategory.rent, date: DateTime.now().subtract(const Duration(days: 1))),
    Expense(id: 'e2', title: 'Employee Salaries', amount: 12000, category: ExpenseCategory.salaries, date: DateTime.now().subtract(const Duration(days: 2))),
    Expense(id: 'e3', title: 'Electricity Bill', amount: 450, category: ExpenseCategory.utilities, date: DateTime.now().subtract(const Duration(days: 3))),
    Expense(id: 'e4', title: 'Internet Service', amount: 180, category: ExpenseCategory.utilities, date: DateTime.now().subtract(const Duration(days: 5))),
    Expense(id: 'e5', title: 'Office Supplies', amount: 320, category: ExpenseCategory.supplies, date: DateTime.now().subtract(const Duration(days: 6))),
    Expense(id: 'e6', title: 'Facebook Ads', amount: 750, category: ExpenseCategory.marketing, date: DateTime.now().subtract(const Duration(days: 7))),
    Expense(id: 'e7', title: 'Cleaning Service', amount: 200, category: ExpenseCategory.other, date: DateTime.now().subtract(const Duration(days: 10))),
  ];

  static List<Transaction> transactions() => [
    Transaction(id: 't1', type: TxnType.invoicePaid, description: 'INV-001 — Ahmed Trading Co.', amount: 385.10, date: DateTime.now().subtract(const Duration(hours: 4))),
    Transaction(id: 't2', type: TxnType.expenseAdded, description: 'Office Rent', amount: 3500, date: DateTime.now().subtract(const Duration(days: 1))),
    Transaction(id: 't3', type: TxnType.paymentReceived, description: 'Partial — Sara Group', amount: 200, date: DateTime.now().subtract(const Duration(days: 2))),
    Transaction(id: 't4', type: TxnType.expenseAdded, description: 'Employee Salaries', amount: 12000, date: DateTime.now().subtract(const Duration(days: 2))),
    Transaction(id: 't5', type: TxnType.invoicePaid, description: 'INV-005 — Omar Supplies', amount: 461, date: DateTime.now().subtract(const Duration(days: 3))),
    Transaction(id: 't6', type: TxnType.expenseAdded, description: 'Electricity Bill', amount: 450, date: DateTime.now().subtract(const Duration(days: 3))),
    Transaction(id: 't7', type: TxnType.paymentReceived, description: 'Advance — Khalid Enterprises', amount: 500, date: DateTime.now().subtract(const Duration(days: 4))),
  ];

  static const FinanceSummary summary = FinanceSummary(
    totalRevenue: 28450,
    totalExpenses: 17400,
    outstanding: 4250,
    cashBalance: 15300,
  );

  /// Monthly breakdown for charts (last 6 months).
  static const List<double> monthlyRevenue = [22000, 24500, 21800, 26200, 27100, 28450];
  static const List<double> monthlyExpenses = [15000, 16200, 14800, 17000, 16500, 17400];
  static const List<String> monthLabels = ['Nov', 'Dec', 'Jan', 'Feb', 'Mar', 'Apr'];
}
