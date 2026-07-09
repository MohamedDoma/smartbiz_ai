// SmartBiz AI — Finance Dashboard screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../finance_state.dart';

class FinanceDashboardScreen extends StatefulWidget {
  const FinanceDashboardScreen({super.key});
  @override
  State<FinanceDashboardScreen> createState() => _FinanceDashboardScreenState();
}

class _FinanceDashboardScreenState extends State<FinanceDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<FinanceState>();
      s.loadSummary();
      s.loadAccounts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'fin_summary'))),
      body: Consumer<FinanceState>(builder: (ctx, state, _) {
        final summary = state.summary;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Quick actions
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                icon: const Icon(Icons.build_outlined, size: 18),
                label: Text(tr(context, 'fin_bootstrap')),
                onPressed: () async {
                  await state.bootstrap();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr(context, 'fin_saved'))),
                    );
                    state.loadSummary();
                  }
                },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: Text(tr(context, 'fin_create_expense')),
                onPressed: () => Navigator.of(context).pushNamed('/finance/expenses'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long, size: 18),
                label: Text(tr(context, 'fin_transactions')),
                onPressed: () => Navigator.of(context).pushNamed('/finance/transactions'),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_balance_outlined, size: 18),
                label: Text(tr(context, 'fin_accounts')),
                onPressed: () => Navigator.of(context).pushNamed('/finance/accounts'),
              ),
            ]),
            const SizedBox(height: 20),

            if (summary == null && state.loading)
              const Center(child: CircularProgressIndicator())
            else if (summary != null) ...[
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 3 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _SummaryCard(label: tr(context, 'fin_income'), value: summary.income, icon: Icons.trending_up, color: Colors.green),
                  _SummaryCard(label: tr(context, 'fin_expenses_label'), value: summary.expenses, icon: Icons.trending_down, color: Colors.red),
                  _SummaryCard(label: tr(context, 'fin_net_profit'), value: summary.netProfit, icon: Icons.bar_chart, color: cs.primary),
                  _SummaryCard(label: tr(context, 'fin_cash_balance'), value: summary.cashBalance, icon: Icons.account_balance_wallet, color: Colors.teal),
                  _SummaryCard(label: tr(context, 'fin_receivable'), value: summary.accountsReceivable, icon: Icons.people, color: Colors.orange),
                  _SummaryCard(label: tr(context, 'fin_commission_payable'), value: summary.commissionPayable, icon: Icons.payments, color: Colors.purple),
                ],
              ),
            ] else
              Center(child: Text(tr(context, 'fin_bootstrap'), style: TextStyle(color: Colors.grey[500]))),
          ]),
        );
      }),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ]),
      ),
    );
  }
}
