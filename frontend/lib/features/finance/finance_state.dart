// SmartBiz AI — Finance state management.
import 'package:flutter/foundation.dart';
import '../../core/api/finance_models.dart';
import '../../core/api/finance_service.dart';

class FinanceState extends ChangeNotifier {
  final FinanceService _svc;
  FinanceState(this._svc);

  List<FinanceAccount> _accounts = [];
  List<FinanceTransaction> _transactions = [];
  List<FinanceExpense> _expenses = [];
  FinanceSummary? _summary;
  ProfitLossSummary? _profitLoss;
  List<AccountBalance> _balances = [];
  bool _loading = false;
  String? _error;

  List<FinanceAccount> get accounts => _accounts;
  List<FinanceTransaction> get transactions => _transactions;
  List<FinanceExpense> get expenses => _expenses;
  FinanceSummary? get summary => _summary;
  ProfitLossSummary? get profitLoss => _profitLoss;
  List<AccountBalance> get balances => _balances;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> bootstrap() async {
    _loading = true; _error = null; notifyListeners();
    try {
      await _svc.bootstrapFinance();
      await loadAccounts();
    } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<void> loadAccounts() async {
    _loading = true; _error = null; notifyListeners();
    try { _accounts = await _svc.listAccounts(); } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<void> loadTransactions() async {
    _loading = true; _error = null; notifyListeners();
    try { _transactions = await _svc.listTransactions(); } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<void> loadExpenses() async {
    _loading = true; _error = null; notifyListeners();
    try { _expenses = await _svc.listExpenses(); } catch (e) { _error = e.toString(); }
    _loading = false; notifyListeners();
  }

  Future<FinanceExpense?> createExpense(FinanceExpensePayload p) async {
    try {
      final exp = await _svc.createExpense(p);
      _expenses = [exp, ..._expenses];
      notifyListeners();
      return exp;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<FinanceTransaction?> createTransaction(FinanceTransactionPayload p) async {
    try {
      final txn = await _svc.createTransaction(p);
      _transactions = [txn, ..._transactions];
      notifyListeners();
      return txn;
    } catch (e) { _error = e.toString(); notifyListeners(); return null; }
  }

  Future<void> voidTransaction(String id) async {
    try {
      await _svc.voidTransaction(id);
      await loadTransactions();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> voidExpense(String id) async {
    try {
      await _svc.voidExpense(id);
      await loadExpenses();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> postCommissionEntry(String id) async {
    try {
      await _svc.postCommissionEntry(id);
      notifyListeners();
    } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> loadSummary() async {
    try { _summary = await _svc.getSummary(); notifyListeners(); } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> loadProfitLoss({String? from, String? to}) async {
    try { _profitLoss = await _svc.getProfitLoss(from: from, to: to); notifyListeners(); } catch (e) { _error = e.toString(); notifyListeners(); }
  }

  Future<void> loadBalances() async {
    try { _balances = await _svc.getAccountBalances(); notifyListeners(); } catch (e) { _error = e.toString(); notifyListeners(); }
  }
}
