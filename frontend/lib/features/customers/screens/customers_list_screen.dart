// SmartBiz AI — Customers list screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/pages/widgets/generic_page_state.dart';
import '../customers_state.dart';
import '../models/customer_models.dart';
import '../widgets/customer_widgets.dart';

class CustomersListScreen extends StatelessWidget {
  const CustomersListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomersState>();
    final isMobile = Responsive.isMobile(context);
    final items = state.customers;

    return Column(
      children: [
        // Pinned header
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(bottom: BorderSide(color: AppColors.divider)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              Row(children: [
                _StatChip(label: '${state.totalCustomers} ${tr(context, 'cust_total')}', color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                _StatChip(label: '${state.vipCount} VIP', color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                _StatChip(label: '\$${state.totalBalance.toStringAsFixed(0)} ${tr(context, 'cust_outstanding')}', color: AppColors.error),
              ]),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                onChanged: state.setSearch,
                decoration: InputDecoration(
                  hintText: tr(context, 'cust_search'), prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
                  isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SingleChildScrollView(scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip(label: tr(context, 'cust_all'), selected: state.statusFilter == null, onTap: () => state.setStatusFilter(null)),
                  _FilterChip(label: tr(context, 'cust_active'), selected: state.statusFilter == CustomerStatus.active, onTap: () => state.setStatusFilter(CustomerStatus.active)),
                  _FilterChip(label: tr(context, 'cust_vip'), selected: state.statusFilter == CustomerStatus.vip, onTap: () => state.setStatusFilter(CustomerStatus.vip)),
                  _FilterChip(label: tr(context, 'cust_inactive'), selected: state.statusFilter == CustomerStatus.inactive, onTap: () => state.setStatusFilter(CustomerStatus.inactive)),
                ]),
              ),
            ]),
          )),
        ),

        // Virtualized list
        Expanded(
          child: items.isEmpty
              ? GenericPageState.empty(
                  title: tr(context, 'cust_empty'),
                  message: tr(context, 'cust_empty_hint'),
                  icon: Icons.people_outline,
                  actionLabel: tr(context, 'cust_add'),
                  onAction: () => context.go('/customers/create'),
                )
              : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView.separated(
                    padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => CustomerCard(customer: items[i], onTap: () => context.go('/customers/${items[i].id}')),
                  ),
                )),
        ),
      ],
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
