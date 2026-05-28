// SmartBiz AI — Customers list screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../customers_state.dart';
import '../models/customer_models.dart';
import '../widgets/customer_widgets.dart';

class CustomersListScreen extends StatelessWidget {
  const CustomersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomersState>();
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Expanded(child: Text(tr(context, 'cust_title'), style: AppTypography.headingLarge)),
            FilledButton.icon(
              onPressed: () => context.go('/customers/create'),
              icon: const Icon(Icons.person_add, size: 18),
              label: Text(tr(context, 'cust_add')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),

          // Summary
          Row(children: [
            _StatChip(label: '${state.totalCustomers} ${tr(context, 'cust_total')}', color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            _StatChip(label: '${state.vipCount} VIP', color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            _StatChip(label: '\$${state.totalBalance.toStringAsFixed(0)} ${tr(context, 'cust_outstanding')}', color: AppColors.error),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // Search
          TextField(
            onChanged: state.setSearch,
            decoration: InputDecoration(
              hintText: tr(context, 'cust_search'), prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
              isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Filters
          SingleChildScrollView(scrollDirection: Axis.horizontal,
            child: Row(children: [
              _FilterChip(label: tr(context, 'cust_all'), selected: state.statusFilter == null, onTap: () => state.setStatusFilter(null)),
              _FilterChip(label: tr(context, 'cust_active'), selected: state.statusFilter == CustomerStatus.active, onTap: () => state.setStatusFilter(CustomerStatus.active)),
              _FilterChip(label: tr(context, 'cust_vip'), selected: state.statusFilter == CustomerStatus.vip, onTap: () => state.setStatusFilter(CustomerStatus.vip)),
              _FilterChip(label: tr(context, 'cust_inactive'), selected: state.statusFilter == CustomerStatus.inactive, onTap: () => state.setStatusFilter(CustomerStatus.inactive)),
            ]),
          ),
          const SizedBox(height: AppSpacing.lg),

          // List
          if (state.customers.isEmpty)
            Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(tr(context, 'cust_empty'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary))))
          else
            ...state.customers.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: CustomerCard(customer: c, onTap: () => context.go('/customers/${c.id}')),
            )),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label; final Color color;
  const _StatChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.sm),
    child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.12),
      checkmarkColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300)),
  );
}
