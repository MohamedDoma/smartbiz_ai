// SmartBiz AI — Finance Transactions screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../finance_state.dart';

class FinanceTransactionsScreen extends StatefulWidget {
  const FinanceTransactionsScreen({super.key});
  @override
  State<FinanceTransactionsScreen> createState() => _FinanceTransactionsScreenState();
}

class _FinanceTransactionsScreenState extends State<FinanceTransactionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceState>().loadTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fin_transactions'))),
      body: Consumer<FinanceState>(builder: (ctx, state, _) {
        if (state.loading && state.transactions.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.transactions.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'fin_no_data'), style: TextStyle(color: Colors.grey[600])),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.transactions.length,
          itemBuilder: (ctx, i) {
            final t = state.transactions[i];
            final isVoid = t.status == 'void';
            return Card(
              child: ListTile(
                leading: Icon(
                  isVoid ? Icons.cancel : Icons.check_circle,
                  color: isVoid ? Colors.red : Colors.green,
                ),
                title: Text(
                  t.description ?? tr(context, 'fin_transaction'),
                  style: TextStyle(fontWeight: FontWeight.w600, decoration: isVoid ? TextDecoration.lineThrough : null),
                ),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr(context, 'fin_date')}: ${t.transactionDate?.split('T').first ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Row(children: [
                    Text('${tr(context, 'fin_total_debit')}: ${t.totalDebit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    const SizedBox(width: 12),
                    Text('${tr(context, 'fin_total_credit')}: ${t.totalCredit.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11, color: Colors.green)),
                  ]),
                  if (t.sourceType != null)
                    Text('${tr(context, 'rpt_data_source')}: ${t.sourceType}', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                ]),
                trailing: isVoid
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(tr(context, 'fin_void_txn'), style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.block, color: Colors.red, size: 20),
                        tooltip: tr(context, 'fin_void_txn'),
                        onPressed: () => state.voidTransaction(t.id),
                      ),
              ),
            );
          },
        );
      }),
    );
  }
}
