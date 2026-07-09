// SmartBiz AI — Finance API service.
import '../api/api_client.dart';
import '../api/finance_models.dart';

class FinanceService {
  final ApiClient _c;
  FinanceService(this._c);

  Future<List<FinanceAccount>> listAccounts() async {
    final r = await _c.get('/finance/accounts');
    return (r.data['data'] as List).map((e) => FinanceAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> bootstrapFinance() async => await _c.post('/finance/bootstrap');

  Future<FinanceAccount> createAccount(FinanceAccountPayload p) async {
    final r = await _c.post('/finance/accounts', data: p.toJson());
    return FinanceAccount.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceAccount> updateAccount(String id, Map<String, dynamic> data) async {
    final r = await _c.put('/finance/accounts/$id', data: data);
    return FinanceAccount.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<FinanceTransaction>> listTransactions() async {
    final r = await _c.get('/finance/transactions');
    return (r.data['data'] as List).map((e) => FinanceTransaction.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FinanceTransaction> getTransaction(String id) async {
    final r = await _c.get('/finance/transactions/$id');
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceTransaction> createTransaction(FinanceTransactionPayload p) async {
    final r = await _c.post('/finance/transactions', data: p.toJson());
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceTransaction> voidTransaction(String id) async {
    final r = await _c.post('/finance/transactions/$id/void');
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<FinanceExpense>> listExpenses() async {
    final r = await _c.get('/finance/expenses');
    return (r.data['data'] as List).map((e) => FinanceExpense.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FinanceExpense> createExpense(FinanceExpensePayload p) async {
    final r = await _c.post('/finance/expenses', data: p.toJson());
    return FinanceExpense.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceExpense> voidExpense(String id) async {
    final r = await _c.post('/finance/expenses/$id/void');
    return FinanceExpense.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceTransaction> postCommissionEntry(String id) async {
    final r = await _c.post('/commission-entries/$id/post-to-finance');
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceTransaction> postInvoice(String id) async {
    final r = await _c.post('/invoices/$id/post-to-finance');
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceTransaction> postPayment(String id) async {
    final r = await _c.post('/payments/$id/post-to-finance');
    return FinanceTransaction.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<FinanceSummary> getSummary() async {
    final r = await _c.get('/finance/summary');
    return FinanceSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<ProfitLossSummary> getProfitLoss({String? from, String? to}) async {
    final params = <String, dynamic>{};
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final r = await _c.get('/finance/profit-loss', queryParameters: params);
    return ProfitLossSummary.fromJson(r.data['data'] as Map<String, dynamic>);
  }

  Future<List<AccountBalance>> getAccountBalances() async {
    final r = await _c.get('/finance/account-balances');
    return (r.data['data'] as List).map((e) => AccountBalance.fromJson(e as Map<String, dynamic>)).toList();
  }
}
