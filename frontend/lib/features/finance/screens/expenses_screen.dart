// SmartBiz AI — Expenses list/add screen.
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

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<FinanceState>();
    final isMobile = Responsive.isMobile(context);
    final expenses = state.filteredExpenses;

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/accounting'), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(tr(context, 'fin_expenses'), style: AppTypography.headingLarge)),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context, state),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr(context, 'fin_add_expense')),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Category filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _CatChip(label: tr(context, 'inv_all'), selected: state.categoryFilter == null, onTap: () => state.setCategoryFilter(null)),
                    ...ExpenseCategory.values.map((c) {
                      final key = _catKey(c);
                      return _CatChip(label: tr(context, key), selected: state.categoryFilter == c, onTap: () => state.setCategoryFilter(c));
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: expenses.isEmpty
              ? Center(child: Text(tr(context, 'fin_no_expenses'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)))
              : ListView.separated(
                  padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
                  itemCount: expenses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _ExpenseRow(expense: expenses[i]),
                ),
        ),
      ],
    );
  }

  String _catKey(ExpenseCategory c) => switch (c) {
    ExpenseCategory.rent => 'fin_cat_rent',
    ExpenseCategory.salaries => 'fin_cat_sal',
    ExpenseCategory.utilities => 'fin_cat_util',
    ExpenseCategory.supplies => 'fin_cat_sup',
    ExpenseCategory.marketing => 'fin_cat_mkt',
    ExpenseCategory.other => 'fin_cat_other',
  };

  void _showAddDialog(BuildContext context, FinanceState state) {
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    ExpenseCategory cat = ExpenseCategory.other;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr(context, 'fin_add_expense')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                textDirection: Directionality.of(context),
                decoration: InputDecoration(labelText: tr(context, 'fin_exp_title'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: amountC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tr(context, 'fin_exp_amount'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ExpenseCategory>(
                value: cat,
                decoration: InputDecoration(labelText: tr(context, 'fin_exp_category'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                items: ExpenseCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(tr(context, _catKey(c))))).toList(),
                onChanged: (v) => setState(() => cat = v ?? cat),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'inv_cancel'))),
            FilledButton(
              onPressed: () {
                if (titleC.text.isNotEmpty && amountC.text.isNotEmpty) {
                  state.addExpense(title: titleC.text, amount: double.tryParse(amountC.text) ?? 0, category: cat);
                  Navigator.pop(ctx);
                }
              },
              child: Text(tr(context, 'prod_save')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _CatChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
    child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), selectedColor: AppColors.primarySurface, checkmarkColor: AppColors.primary,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary)),
  );
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  const _ExpenseRow({required this.expense});

  IconData get _icon => switch (expense.category) {
    ExpenseCategory.rent => Icons.home,
    ExpenseCategory.salaries => Icons.people,
    ExpenseCategory.utilities => Icons.bolt,
    ExpenseCategory.supplies => Icons.shopping_bag,
    ExpenseCategory.marketing => Icons.campaign,
    ExpenseCategory.other => Icons.more_horiz,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(_icon, size: 18, color: AppColors.error),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expense.title, style: AppTypography.labelMedium),
              Text('${expense.date.day}/${expense.date.month}/${expense.date.year}', style: AppTypography.caption),
            ]),
          ),
          Text('-\$${expense.amount.toStringAsFixed(2)}', style: AppTypography.labelLarge.copyWith(color: AppColors.error)),
        ],
      ),
    );
  }
}
