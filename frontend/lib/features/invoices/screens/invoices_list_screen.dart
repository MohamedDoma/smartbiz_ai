// SmartBiz AI — Invoices list screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/pages/widgets/generic_page_state.dart';
import '../invoices_state.dart';
import '../models/invoice_models.dart';
import '../widgets/invoice_widgets.dart';

class InvoicesListScreen extends StatelessWidget {
  const InvoicesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InvoicesState>();
    final isMobile = Responsive.isMobile(context);
    final invoices = state.filtered;

    return LayoutBuilder(builder: (context, constraints) {
      return Column(
        children: [
          // Header + search + filters
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(tr(context, 'inv_title'), style: AppTypography.headingLarge)),
                    FilledButton.icon(
                      onPressed: () => context.go('/invoices/create'),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr(context, 'inv_create')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Search
                TextField(
                  onChanged: state.setSearch,
                  textDirection: Directionality.of(context),
                  decoration: InputDecoration(
                    hintText: tr(context, 'inv_search'),
                    hintTextDirection: Directionality.of(context),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // Status filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _StatusChip(label: tr(context, 'inv_all'), selected: state.statusFilter == null, onTap: () => state.setStatusFilter(null)),
                      ...InvoiceStatus.values.map((s) {
                        final key = switch (s) {
                          InvoiceStatus.draft => 'inv_status_draft',
                          InvoiceStatus.sent => 'inv_status_sent',
                          InvoiceStatus.paid => 'inv_status_paid',
                          InvoiceStatus.overdue => 'inv_status_overdue',
                        };
                        return _StatusChip(label: tr(context, key), selected: state.statusFilter == s, onTap: () => state.setStatusFilter(s));
                      }),
                    ],
                  ),
                ),
              ],
            ),
            )),
          ),

          // Invoice list
          Expanded(
            child: invoices.isEmpty
                ? GenericPageState.empty(
                    title: tr(context, 'inv_empty'),
                    message: tr(context, 'inv_empty_hint'),
                    icon: Icons.receipt_long,
                    actionLabel: tr(context, 'inv_create'),
                    onAction: () => context.go('/invoices/create'),
                  )
                : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView.separated(
                      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
                      itemCount: invoices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => _InvoiceRow(invoice: invoices[index]),
                    ),
                  )),
          ),
        ],
      );
    });
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _StatusChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primarySurface,
        checkmarkColor: AppColors.primary,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary),
      ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final Invoice invoice;
  const _InvoiceRow({required this.invoice});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/invoices/${invoice.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // Invoice icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.number, style: AppTypography.labelLarge),
                  const SizedBox(height: 2),
                  Text(invoice.customer.name, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  if (invoice.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${tr(context, 'inv_due')}: ${invoice.dueDate!.day}/${invoice.dueDate!.month}/${invoice.dueDate!.year}',
                        style: AppTypography.caption.copyWith(
                          color: invoice.status == InvoiceStatus.overdue ? AppColors.error : AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Amount + status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${invoice.total.toStringAsFixed(2)}', style: AppTypography.labelLarge),
                const SizedBox(height: 4),
                InvoiceStatusBadge(status: invoice.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
