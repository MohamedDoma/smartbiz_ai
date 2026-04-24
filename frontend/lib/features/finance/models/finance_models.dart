// SmartBiz AI — Finance data models.

/// Expense category.
enum ExpenseCategory { rent, salaries, utilities, supplies, marketing, other }

/// A single expense entry.
class Expense {
  final String id;
  final String title;
  final double amount;
  final ExpenseCategory category;
  final DateTime date;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
  });
}

/// Transaction type.
enum TxnType { invoicePaid, expenseAdded, paymentReceived }

/// A single transaction in the timeline.
class Transaction {
  final String id;
  final TxnType type;
  final String description;
  final double amount;
  final DateTime date;

  const Transaction({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.date,
  });
}

/// Aggregated financial summary.
class FinanceSummary {
  final double totalRevenue;
  final double totalExpenses;
  final double outstanding;
  final double cashBalance;

  const FinanceSummary({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.outstanding,
    required this.cashBalance,
  });

  double get netProfit => totalRevenue - totalExpenses;
  double get profitMargin => totalRevenue > 0 ? (netProfit / totalRevenue * 100) : 0;
}
