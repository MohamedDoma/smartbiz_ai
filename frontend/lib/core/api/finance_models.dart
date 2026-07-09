// SmartBiz AI — Finance API models.

class FinanceAccount {
  final String id;
  final String? workspaceId;
  final String? accountKey;
  final String? code;
  final String name;
  final String type;
  final String normalBalance;
  final bool isSystem;
  final bool isActive;
  final int sortOrder;

  const FinanceAccount({
    required this.id, this.workspaceId, this.accountKey, this.code,
    required this.name, required this.type, required this.normalBalance,
    this.isSystem = false, this.isActive = true, this.sortOrder = 0,
  });

  factory FinanceAccount.fromJson(Map<String, dynamic> j) => FinanceAccount(
    id: j['id'] as String,
    workspaceId: j['workspace_id'] as String?,
    accountKey: j['account_key'] as String?,
    code: j['code'] as String?,
    name: j['name'] as String,
    type: j['type'] as String,
    normalBalance: j['normal_balance'] as String,
    isSystem: j['is_system'] as bool? ?? false,
    isActive: j['is_active'] as bool? ?? true,
    sortOrder: j['sort_order'] as int? ?? 0,
  );
}

class FinanceAccountPayload {
  final String code;
  final String name;
  final String type;
  final String normalBalance;
  final String? accountKey;

  const FinanceAccountPayload({required this.code, required this.name, required this.type, required this.normalBalance, this.accountKey});

  Map<String, dynamic> toJson() => {
    'code': code, 'name': name, 'type': type, 'normal_balance': normalBalance,
    if (accountKey != null) 'account_key': accountKey,
  };
}

class FinanceTransactionLine {
  final String? id;
  final String financeAccountId;
  final String? description;
  final double debitAmount;
  final double creditAmount;
  final Map<String, dynamic>? account;

  const FinanceTransactionLine({
    this.id, required this.financeAccountId, this.description,
    this.debitAmount = 0, this.creditAmount = 0, this.account,
  });

  factory FinanceTransactionLine.fromJson(Map<String, dynamic> j) => FinanceTransactionLine(
    id: j['id'] as String?,
    financeAccountId: j['finance_account_id'] as String,
    description: j['description'] as String?,
    debitAmount: (j['debit_amount'] as num?)?.toDouble() ?? 0,
    creditAmount: (j['credit_amount'] as num?)?.toDouble() ?? 0,
    account: j['account'] as Map<String, dynamic>?,
  );

  Map<String, dynamic> toJson() => {
    'finance_account_id': financeAccountId,
    'debit_amount': debitAmount,
    'credit_amount': creditAmount,
    if (description != null) 'description': description,
  };
}

class FinanceTransaction {
  final String id;
  final String? transactionDate;
  final String? description;
  final String? sourceType;
  final String status;
  final String currency;
  final double totalDebit;
  final double totalCredit;
  final List<FinanceTransactionLine>? lines;
  final String? createdAt;

  const FinanceTransaction({
    required this.id, this.transactionDate, this.description,
    this.sourceType, this.status = 'posted', this.currency = 'LYD',
    this.totalDebit = 0, this.totalCredit = 0, this.lines, this.createdAt,
  });

  factory FinanceTransaction.fromJson(Map<String, dynamic> j) => FinanceTransaction(
    id: j['id'] as String,
    transactionDate: j['transaction_date'] as String?,
    description: j['description'] as String?,
    sourceType: j['source_type'] as String?,
    status: j['status'] as String? ?? 'posted',
    currency: j['currency'] as String? ?? 'LYD',
    totalDebit: (j['total_debit'] as num?)?.toDouble() ?? 0,
    totalCredit: (j['total_credit'] as num?)?.toDouble() ?? 0,
    lines: (j['lines'] as List?)?.map((e) => FinanceTransactionLine.fromJson(e as Map<String, dynamic>)).toList(),
    createdAt: j['created_at'] as String?,
  );
}

class FinanceTransactionPayload {
  final String transactionDate;
  final String? description;
  final String? currency;
  final List<FinanceTransactionLine> lines;

  const FinanceTransactionPayload({required this.transactionDate, this.description, this.currency, required this.lines});

  Map<String, dynamic> toJson() => {
    'transaction_date': transactionDate,
    if (description != null) 'description': description,
    if (currency != null) 'currency': currency,
    'lines': lines.map((l) => l.toJson()).toList(),
  };
}

class FinanceExpense {
  final String id;
  final String? expenseDate;
  final String? category;
  final String description;
  final double amount;
  final String currency;
  final String? paymentMethod;
  final String? financeTransactionId;
  final String status;

  const FinanceExpense({
    required this.id, this.expenseDate, this.category,
    required this.description, required this.amount, this.currency = 'LYD',
    this.paymentMethod, this.financeTransactionId, this.status = 'posted',
  });

  factory FinanceExpense.fromJson(Map<String, dynamic> j) => FinanceExpense(
    id: j['id'] as String,
    expenseDate: j['expense_date'] as String?,
    category: j['category'] as String?,
    description: j['description'] as String,
    amount: (j['amount'] as num?)?.toDouble() ?? 0,
    currency: j['currency'] as String? ?? 'LYD',
    paymentMethod: j['payment_method'] as String?,
    financeTransactionId: j['finance_transaction_id'] as String?,
    status: j['status'] as String? ?? 'posted',
  );
}

class FinanceExpensePayload {
  final String expenseDate;
  final String? category;
  final String description;
  final double amount;
  final String? currency;
  final String? paymentMethod;

  const FinanceExpensePayload({required this.expenseDate, this.category, required this.description, required this.amount, this.currency, this.paymentMethod});

  Map<String, dynamic> toJson() => {
    'expense_date': expenseDate, 'description': description, 'amount': amount,
    if (category != null) 'category': category,
    if (currency != null) 'currency': currency,
    if (paymentMethod != null) 'payment_method': paymentMethod,
  };
}

class FinanceSummary {
  final String income;
  final String expenses;
  final String netProfit;
  final String cashBalance;
  final String accountsReceivable;
  final String commissionPayable;

  const FinanceSummary({this.income = '0.00', this.expenses = '0.00', this.netProfit = '0.00', this.cashBalance = '0.00', this.accountsReceivable = '0.00', this.commissionPayable = '0.00'});

  factory FinanceSummary.fromJson(Map<String, dynamic> j) => FinanceSummary(
    income: j['income'] as String? ?? '0.00',
    expenses: j['expenses'] as String? ?? '0.00',
    netProfit: j['net_profit'] as String? ?? '0.00',
    cashBalance: j['cash_balance'] as String? ?? '0.00',
    accountsReceivable: j['accounts_receivable'] as String? ?? '0.00',
    commissionPayable: j['commission_payable'] as String? ?? '0.00',
  );
}

class ProfitLossSummary {
  final String? from;
  final String? to;
  final String income;
  final String expenses;
  final String netProfit;
  final List<Map<String, dynamic>> details;

  const ProfitLossSummary({this.from, this.to, this.income = '0.00', this.expenses = '0.00', this.netProfit = '0.00', this.details = const []});

  factory ProfitLossSummary.fromJson(Map<String, dynamic> j) => ProfitLossSummary(
    from: j['from'] as String?,
    to: j['to'] as String?,
    income: j['income'] as String? ?? '0.00',
    expenses: j['expenses'] as String? ?? '0.00',
    netProfit: j['net_profit'] as String? ?? '0.00',
    details: (j['details'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
  );
}

class AccountBalance {
  final String id;
  final String? code;
  final String name;
  final String type;
  final String normalBalance;
  final String totalDebit;
  final String totalCredit;
  final double balance;

  const AccountBalance({required this.id, this.code, required this.name, required this.type, required this.normalBalance, this.totalDebit = '0.00', this.totalCredit = '0.00', this.balance = 0});

  factory AccountBalance.fromJson(Map<String, dynamic> j) => AccountBalance(
    id: j['id'] as String,
    code: j['code'] as String?,
    name: j['name'] as String,
    type: j['type'] as String,
    normalBalance: j['normal_balance'] as String,
    totalDebit: j['total_debit'] as String? ?? '0.00',
    totalCredit: j['total_credit'] as String? ?? '0.00',
    balance: (j['balance'] as num?)?.toDouble() ?? 0,
  );
}
