// SmartBiz AI — Finance Expenses screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/finance_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../finance_state.dart';

class FinanceExpensesScreen extends StatefulWidget {
  const FinanceExpensesScreen({super.key});
  @override
  State<FinanceExpensesScreen> createState() => _FinanceExpensesScreenState();
}

class _FinanceExpensesScreenState extends State<FinanceExpensesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FinanceState>().loadExpenses();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'fin_expenses_label')),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _showCreateDialog(context)),
        ],
      ),
      body: Consumer<FinanceState>(builder: (ctx, state, _) {
        if (state.loading && state.expenses.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.expenses.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.money_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'fin_no_data'), style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr(context, 'fin_create_expense')),
                onPressed: () => _showCreateDialog(context),
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.expenses.length,
          itemBuilder: (ctx, i) {
            final e = state.expenses[i];
            final isVoid = e.status == 'void';
            return Card(
              child: ListTile(
                leading: Icon(Icons.receipt, color: isVoid ? Colors.grey : Colors.red),
                title: Text(e.description, style: TextStyle(fontWeight: FontWeight.w600, decoration: isVoid ? TextDecoration.lineThrough : null)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e.amount.toStringAsFixed(2)} ${e.currency}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Row(children: [
                    if (e.category != null) Text('${e.category} · ', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    Text(e.expenseDate?.split('T').first ?? '', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    if (e.paymentMethod != null) Text(' · ${e.paymentMethod}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ]),
                ]),
                trailing: isVoid
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text(tr(context, 'fin_void_txn'), style: const TextStyle(fontSize: 10, color: Colors.red)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.block, color: Colors.red, size: 20),
                        tooltip: tr(context, 'fin_void_txn'),
                        onPressed: () => state.voidExpense(e.id),
                      ),
              ),
            );
          },
        );
      }),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final state = context.read<FinanceState>();
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final catCtrl = TextEditingController();
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          title: Text(tr(context, 'fin_create_expense')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: descCtrl, decoration: InputDecoration(labelText: tr(context, 'rpt_description')), autofocus: true),
                const SizedBox(height: 8),
                TextField(controller: amountCtrl, decoration: InputDecoration(labelText: tr(context, 'fin_amount')), keyboardType: TextInputType.number),
                const SizedBox(height: 8),
                TextField(controller: catCtrl, decoration: InputDecoration(labelText: tr(context, 'fin_category'))),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: tr(context, 'fin_payment_method')),
                  initialValue: paymentMethod,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  ],
                  onChanged: (v) => setDlg(() => paymentMethod = v ?? 'cash'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text.trim());
                if (descCtrl.text.trim().isEmpty || amount == null || amount <= 0) return;
                await state.createExpense(FinanceExpensePayload(
                  expenseDate: DateTime.now().toIso8601String().split('T').first,
                  description: descCtrl.text.trim(),
                  amount: amount,
                  category: catCtrl.text.trim().isEmpty ? null : catCtrl.text.trim(),
                  paymentMethod: paymentMethod,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'create')),
            ),
          ],
        );
      }),
    );
  }
}
