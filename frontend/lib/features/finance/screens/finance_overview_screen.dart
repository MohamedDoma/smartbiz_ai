// SmartBiz AI — Finance overview screen (Accounting).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../finance_state.dart';
import '../models/finance_models.dart';

class FinanceOverviewScreen extends StatelessWidget {
  const FinanceOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FinanceState>();
    final s = state.summary;
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.success, AppColors.primary]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.account_balance, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'fin_title'), style: AppTypography.headingLarge),
                      Text(tr(context, 'fin_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Metrics grid
              _MetricsGrid(summary: s, isMobile: isMobile),
              const SizedBox(height: AppSpacing.xl),

              // Quick actions
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(icon: Icons.receipt_long, label: tr(context, 'fin_view_expenses'), color: AppColors.error, onTap: () => context.go('/accounting/expenses')),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _QuickAction(icon: Icons.bar_chart, label: tr(context, 'fin_view_reports'), color: AppColors.info, onTap: () => context.go('/reports')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Transactions timeline
              Text(tr(context, 'fin_recent_txn'), style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.md),
              ...state.transactions.take(6).map((t) => _TransactionRow(txn: t)),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Metrics Grid
// ═══════════════════════════════════════════════════════════
class _MetricsGrid extends StatelessWidget {
  final FinanceSummary summary;
  final bool isMobile;
  const _MetricsGrid({required this.summary, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricCard(label: tr(context, 'fin_revenue'), value: '\$${_fmt(summary.totalRevenue)}', icon: Icons.trending_up, color: AppColors.success),
      _MetricCard(label: tr(context, 'fin_expenses'), value: '\$${_fmt(summary.totalExpenses)}', icon: Icons.trending_down, color: AppColors.error),
      _MetricCard(label: tr(context, 'fin_profit'), value: '\$${_fmt(summary.netProfit)}', icon: Icons.show_chart, color: AppColors.primary, sub: '${summary.profitMargin.toStringAsFixed(1)}%'),
      _MetricCard(label: tr(context, 'fin_outstanding'), value: '\$${_fmt(summary.outstanding)}', icon: Icons.schedule, color: AppColors.warning),
      _MetricCard(label: tr(context, 'fin_cash'), value: '\$${_fmt(summary.cashBalance)}', icon: Icons.account_balance_wallet, color: AppColors.info),
    ];

    if (isMobile) {
      return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: c)).toList());
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: cards.map((c) => SizedBox(width: 170, child: c)).toList(),
    );
  }

  String _fmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toStringAsFixed(0);
}

class _MetricCard extends StatelessWidget {
  final String label; final String value; final IconData icon; final Color color; final String? sub;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color, this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: AppTypography.headingSmall),
              Row(children: [
                Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                if (sub != null) ...[const SizedBox(width: 4), Text(sub!, style: AppTypography.caption.copyWith(color: color, fontWeight: FontWeight.w600))],
              ]),
            ]),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.labelMedium)),
          Icon(Icons.chevron_right, size: 18, color: color),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Transaction Row
// ═══════════════════════════════════════════════════════════
class _TransactionRow extends StatelessWidget {
  final Transaction txn;
  const _TransactionRow({required this.txn});

  IconData get _icon => switch (txn.type) {
    TxnType.invoicePaid => Icons.check_circle,
    TxnType.expenseAdded => Icons.arrow_downward,
    TxnType.paymentReceived => Icons.arrow_upward,
  };
  Color get _color => switch (txn.type) {
    TxnType.invoicePaid => AppColors.success,
    TxnType.expenseAdded => AppColors.error,
    TxnType.paymentReceived => AppColors.info,
  };
  String get _sign => txn.type == TxnType.expenseAdded ? '-' : '+';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(_icon, size: 16, color: _color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(txn.description, style: AppTypography.bodySmall, overflow: TextOverflow.ellipsis)),
          Text('$_sign\$${txn.amount.toStringAsFixed(2)}', style: AppTypography.labelMedium.copyWith(color: _color)),
        ],
      ),
    );
  }
}
