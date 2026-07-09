// SmartBiz AI — Finance Accounts screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../finance_state.dart';

class FinanceAccountsScreen extends StatefulWidget {
  const FinanceAccountsScreen({super.key});
  @override
  State<FinanceAccountsScreen> createState() => _FinanceAccountsScreenState();
}

class _FinanceAccountsScreenState extends State<FinanceAccountsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceState>().loadAccounts();
    });
  }

  Color _typeColor(String type) => switch (type) {
    'asset' => Colors.blue,
    'liability' => Colors.orange,
    'equity' => Colors.purple,
    'income' => Colors.green,
    'expense' => Colors.red,
    _ => Colors.grey,
  };

  String _typeLabel(BuildContext ctx, String type) => switch (type) {
    'asset' => tr(ctx, 'fin_asset'),
    'liability' => tr(ctx, 'fin_liability'),
    'equity' => tr(ctx, 'fin_equity'),
    'income' => tr(ctx, 'fin_income'),
    'expense' => tr(ctx, 'fin_expense_type'),
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fin_accounts'))),
      body: Consumer<FinanceState>(builder: (ctx, state, _) {
        if (state.loading && state.accounts.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.accounts.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.account_balance, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'fin_bootstrap'), style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => state.bootstrap(),
                child: Text(tr(context, 'fin_bootstrap')),
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.accounts.length,
          itemBuilder: (ctx, i) {
            final a = state.accounts[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _typeColor(a.type).withValues(alpha: 0.15),
                  child: Text(a.code ?? '?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _typeColor(a.type))),
                ),
                title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _typeColor(a.type).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(_typeLabel(context, a.type), style: TextStyle(fontSize: 10, color: _typeColor(a.type), fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Text('${tr(context, 'fin_normal_balance')}: ${a.normalBalance == 'debit' ? tr(context, 'fin_debit') : tr(context, 'fin_credit')}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  if (a.isSystem) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(tr(context, 'fin_system_account'), style: const TextStyle(fontSize: 9, color: Colors.blue)),
                    ),
                  ],
                ]),
              ),
            );
          },
        );
      }),
    );
  }
}
