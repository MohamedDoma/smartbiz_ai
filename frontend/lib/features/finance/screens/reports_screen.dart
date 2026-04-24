// SmartBiz AI — Financial reports screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../finance_state.dart';
import '../models/finance_models.dart';
import '../data/mock_finance.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

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
              Text(tr(context, 'fin_reports_title'), style: AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.sm),
              Text(tr(context, 'fin_reports_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.xl),

              // Revenue vs Expenses chart
              _ChartCard(
                title: tr(context, 'fin_rev_vs_exp'),
                child: _BarChart(
                  revenue: MockFinance.monthlyRevenue,
                  expenses: MockFinance.monthlyExpenses,
                  labels: MockFinance.monthLabels,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Summary cards
              if (isMobile)
                Column(children: [
                  _SummaryTile(label: tr(context, 'fin_revenue'), value: '\$${s.totalRevenue.toStringAsFixed(0)}', color: AppColors.success, icon: Icons.trending_up),
                  const SizedBox(height: AppSpacing.sm),
                  _SummaryTile(label: tr(context, 'fin_expenses'), value: '\$${s.totalExpenses.toStringAsFixed(0)}', color: AppColors.error, icon: Icons.trending_down),
                  const SizedBox(height: AppSpacing.sm),
                  _SummaryTile(label: tr(context, 'fin_profit'), value: '\$${s.netProfit.toStringAsFixed(0)}', color: AppColors.primary, icon: Icons.show_chart),
                ])
              else
                Row(children: [
                  Expanded(child: _SummaryTile(label: tr(context, 'fin_revenue'), value: '\$${s.totalRevenue.toStringAsFixed(0)}', color: AppColors.success, icon: Icons.trending_up)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _SummaryTile(label: tr(context, 'fin_expenses'), value: '\$${s.totalExpenses.toStringAsFixed(0)}', color: AppColors.error, icon: Icons.trending_down)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _SummaryTile(label: tr(context, 'fin_profit'), value: '\$${s.netProfit.toStringAsFixed(0)}', color: AppColors.primary, icon: Icons.show_chart)),
                ]),
              const SizedBox(height: AppSpacing.xl),

              // Expense breakdown
              _ChartCard(
                title: tr(context, 'fin_exp_breakdown'),
                child: _ExpenseBreakdown(state: state),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Chart Card wrapper
// ═══════════════════════════════════════════════════════════
class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.lg),
        child,
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Simple Bar Chart (pure Flutter, no dependencies)
// ═══════════════════════════════════════════════════════════
class _BarChart extends StatelessWidget {
  final List<double> revenue;
  final List<double> expenses;
  final List<String> labels;
  const _BarChart({required this.revenue, required this.expenses, required this.labels});

  @override
  Widget build(BuildContext context) {
    final maxVal = [...revenue, ...expenses].reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(labels.length, (i) {
          final rH = maxVal > 0 ? (revenue[i] / maxVal * 140) : 0.0;
          final eH = maxVal > 0 ? (expenses[i] / maxVal * 140) : 0.0;
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(width: 12, height: rH, decoration: BoxDecoration(color: AppColors.success, borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
                    const SizedBox(width: 2),
                    Container(width: 12, height: eH, decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.5), borderRadius: const BorderRadius.vertical(top: Radius.circular(3)))),
                  ],
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: AppTypography.caption.copyWith(fontSize: 10)),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Summary Tile
// ═══════════════════════════════════════════════════════════
class _SummaryTile extends StatelessWidget {
  final String label; final String value; final Color color; final IconData icon;
  const _SummaryTile({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: AppTypography.headingSmall.copyWith(color: color)),
          Text(label, style: AppTypography.caption),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Expense Breakdown (horizontal bars)
// ═══════════════════════════════════════════════════════════
class _ExpenseBreakdown extends StatelessWidget {
  final FinanceState state;
  const _ExpenseBreakdown({required this.state});

  @override
  Widget build(BuildContext context) {
    final categories = <String, double>{};
    for (final e in state.filteredExpenses) {
      final key = switch (e.category) {
        ExpenseCategory.rent => tr(context, 'fin_cat_rent'),
        ExpenseCategory.salaries => tr(context, 'fin_cat_sal'),
        ExpenseCategory.utilities => tr(context, 'fin_cat_util'),
        ExpenseCategory.supplies => tr(context, 'fin_cat_sup'),
        ExpenseCategory.marketing => tr(context, 'fin_cat_mkt'),
        ExpenseCategory.other => tr(context, 'fin_cat_other'),
      };
      categories[key] = (categories[key] ?? 0) + e.amount;
    }
    final max = categories.values.isEmpty ? 1.0 : categories.values.reduce((a, b) => a > b ? a : b);
    final colors = [AppColors.primary, AppColors.error, AppColors.warning, AppColors.info, AppColors.success, AppColors.accent];

    return Column(
      children: categories.entries.toList().asMap().entries.map((entry) {
        final e = entry.value;
        final c = colors[entry.key % colors.length];
        final pct = e.value / max;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            SizedBox(width: 100, child: Text(e.key, style: AppTypography.bodySmall)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: pct, backgroundColor: AppColors.neutral100, color: c, minHeight: 10),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(width: 70, child: Text('\$${e.value.toStringAsFixed(0)}', style: AppTypography.labelSmall, textAlign: TextAlign.end)),
          ]),
        );
      }).toList(),
    );
  }
}
