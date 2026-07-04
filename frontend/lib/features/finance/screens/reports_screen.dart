// SmartBiz AI — Reports screen (polished MVP).
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

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _dateRange = 2; // 0=7d, 1=30d, 2=6m, 3=1y
  String _category = 'all'; // all, sales, finance, inventory, hr

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FinanceState>();
    final s = state.summary;
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'rpt_title'), style: AppTypography.headingLarge),
                      const SizedBox(height: 4),
                      Text(tr(context, 'rpt_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showExportSheet,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: Text(tr(context, 'rpt_export')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _showPrintDemo,
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: Text(tr(context, 'rpt_print')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Date range chips ───────────────────────
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _RangeChip(label: tr(context, 'rpt_7d'), selected: _dateRange == 0, onTap: () => setState(() => _dateRange = 0)),
                  _RangeChip(label: tr(context, 'rpt_30d'), selected: _dateRange == 1, onTap: () => setState(() => _dateRange = 1)),
                  _RangeChip(label: tr(context, 'rpt_6m'), selected: _dateRange == 2, onTap: () => setState(() => _dateRange = 2)),
                  _RangeChip(label: tr(context, 'rpt_1y'), selected: _dateRange == 3, onTap: () => setState(() => _dateRange = 3)),
                ]),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Report category cards ──────────────────
              LayoutBuilder(builder: (_, constraints) {
                final cols = constraints.maxWidth > 600 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.5,
                  children: [
                    _CategoryCard(
                      id: 'sales', icon: Icons.point_of_sale_outlined, color: AppColors.primary,
                      label: tr(context, 'rpt_cat_sales'), value: '\$${s.totalRevenue.toStringAsFixed(0)}',
                      selected: _category == 'sales', onTap: () => setState(() => _category = _category == 'sales' ? 'all' : 'sales'),
                    ),
                    _CategoryCard(
                      id: 'finance', icon: Icons.account_balance_outlined, color: AppColors.success,
                      label: tr(context, 'rpt_cat_finance'), value: '\$${s.netProfit.toStringAsFixed(0)}',
                      selected: _category == 'finance', onTap: () => setState(() => _category = _category == 'finance' ? 'all' : 'finance'),
                    ),
                    _CategoryCard(
                      id: 'inventory', icon: Icons.warehouse_outlined, color: AppColors.warning,
                      label: tr(context, 'rpt_cat_inventory'), value: tr(context, 'rpt_coming_soon'),
                      selected: _category == 'inventory', onTap: () => setState(() => _category = _category == 'inventory' ? 'all' : 'inventory'),
                    ),
                    _CategoryCard(
                      id: 'hr', icon: Icons.people_outline, color: AppColors.info,
                      label: tr(context, 'rpt_cat_hr'), value: tr(context, 'rpt_coming_soon'),
                      selected: _category == 'hr', onTap: () => setState(() => _category = _category == 'hr' ? 'all' : 'hr'),
                    ),
                  ],
                );
              }),
              const SizedBox(height: AppSpacing.xl),

              // ── Report content by category ─────────────
              if (_category == 'all' || _category == 'sales' || _category == 'finance') ...[
                // Revenue vs Expenses chart
                _ChartCard(
                  title: tr(context, 'fin_rev_vs_exp'),
                  child: _BarChart(
                    revenue: MockFinance.monthlyRevenue,
                    expenses: MockFinance.monthlyExpenses,
                    labels: MockFinance.monthLabels,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

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
              ],

              if (_category == 'inventory') ...[
                _PlaceholderReportCard(
                  icon: Icons.warehouse_outlined,
                  color: AppColors.warning,
                  title: tr(context, 'rpt_inv_title'),
                  items: [
                    tr(context, 'rpt_inv_stock_value'),
                    tr(context, 'rpt_inv_turnover'),
                    tr(context, 'rpt_inv_low_stock'),
                    tr(context, 'rpt_inv_movement'),
                  ],
                ),
              ],

              if (_category == 'hr') ...[
                _PlaceholderReportCard(
                  icon: Icons.people_outline,
                  color: AppColors.info,
                  title: tr(context, 'rpt_hr_title'),
                  items: [
                    tr(context, 'rpt_hr_headcount'),
                    tr(context, 'rpt_hr_roles'),
                    tr(context, 'rpt_hr_dept'),
                    tr(context, 'rpt_hr_activity'),
                  ],
                ),
              ],

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(context, 'rpt_export'), style: AppTypography.headingSmall),
            const SizedBox(height: AppSpacing.lg),
            _ExportOption(icon: Icons.picture_as_pdf, label: 'PDF', onTap: () => _demoExport('PDF')),
            _ExportOption(icon: Icons.table_chart, label: 'CSV', onTap: () => _demoExport('CSV')),
            _ExportOption(icon: Icons.grid_on, label: 'Excel', onTap: () => _demoExport('Excel')),
            const SizedBox(height: AppSpacing.md),
          ]),
        ),
      ),
    );
  }

  void _demoExport(String format) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${tr(context, 'rpt_export_demo')} ($format)'),
      backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showPrintDemo() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context, 'rpt_print_demo')),
      backgroundColor: AppColors.info, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ═══════════════════════════════════════════════════════════
//  Date Range Chip
// ═══════════════════════════════════════════════════════════

class _RangeChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _RangeChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
    child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? AppColors.primary : AppColors.textSecondary)),
  );
}

// ═══════════════════════════════════════════════════════════
//  Report Category Card
// ═══════════════════════════════════════════════════════════

class _CategoryCard extends StatelessWidget {
  final String id;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryCard({required this.id, required this.icon, required this.color, required this.label, required this.value, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? color.withValues(alpha: 0.08) : AppColors.surface,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : AppColors.divider, width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 18, color: color),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTypography.labelMedium),
              const SizedBox(height: 2),
              Text(value, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ]),
          ],
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Placeholder Report Card (inventory / HR)
// ═══════════════════════════════════════════════════════════

class _PlaceholderReportCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<String> items;
  const _PlaceholderReportCard({required this.icon, required this.color, required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTypography.labelLarge),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Text(tr(context, 'rpt_coming_soon'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.warning)),
        ),
      ]),
      const SizedBox(height: AppSpacing.lg),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
            child: Icon(Icons.insert_chart_outlined, size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(item, style: AppTypography.bodyMedium)),
          Icon(Icons.chevron_right, size: 16, color: AppColors.neutral400),
        ]),
      )),
      const SizedBox(height: AppSpacing.sm),
      Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(tr(context, 'rpt_placeholder_hint'), style: AppTypography.caption.copyWith(color: AppColors.textTertiary))),
        ]),
      ),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Export Option
// ═══════════════════════════════════════════════════════════

class _ExportOption extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _ExportOption({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppColors.primary),
    title: Text(label, style: AppTypography.labelMedium),
    trailing: const Icon(Icons.chevron_right, size: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    onTap: onTap,
  );
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
