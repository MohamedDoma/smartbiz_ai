// SmartBiz AI — Invoice detail screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../invoices_state.dart';
import '../models/invoice_models.dart';
import '../widgets/invoice_widgets.dart';

class InvoiceDetailScreen extends StatelessWidget {
  final String invoiceId;
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InvoicesState>();
    final invoice = state.getById(invoiceId);
    final isMobile = Responsive.isMobile(context);

    if (invoice == null) {
      return Center(child: Text(tr(context, 'inv_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with back button
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/invoices'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(invoice.number, style: AppTypography.headingLarge),
                        Text(invoice.customer.name, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  InvoiceStatusBadge(status: invoice.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Invoice card
              Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer details
                    Text(tr(context, 'inv_customer'), style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.person, size: 18, color: AppColors.primary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(invoice.customer.name, style: AppTypography.labelMedium),
                              if (invoice.customer.email != null)
                                Text(invoice.customer.email!, style: AppTypography.caption),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),

                    // Items header
                    Text(tr(context, 'inv_items'), style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.md),

                    // Items table
                    ...invoice.items.asMap().entries.map((e) => _DetailItemRow(item: e.value, index: e.key)),

                    const Divider(height: AppSpacing.xl),

                    // Totals
                    InvoiceTotals(invoice: invoice),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Actions
              if (isMobile)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildActions(context, invoice, state),
                )
              else
                Row(children: _buildActions(context, invoice, state).map((w) => Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: w,
                ))).toList()),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, Invoice invoice, InvoicesState state) {
    return [
      if (invoice.status == InvoiceStatus.draft)
        FilledButton.icon(
          onPressed: () => state.markAsSent(invoice.id),
          icon: const Icon(Icons.send, size: 16),
          label: Text(tr(context, 'inv_send')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.info,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      if (invoice.status != InvoiceStatus.paid)
        FilledButton.icon(
          onPressed: () => state.markAsPaid(invoice.id),
          icon: const Icon(Icons.check_circle, size: 16),
          label: Text(tr(context, 'inv_mark_paid')),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.print, size: 16),
        label: Text(tr(context, 'inv_print')),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    ];
  }
}

class _DetailItemRow extends StatelessWidget {
  final InvoiceItem item;
  final int index;
  const _DetailItemRow({required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text('${index + 1}', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600))),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(item.productName, style: AppTypography.bodyMedium)),
          SizedBox(width: 50, child: Text('×${item.quantity}', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center)),
          SizedBox(width: 70, child: Text('\$${item.unitPrice.toStringAsFixed(2)}', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.end)),
          SizedBox(width: 80, child: Text('\$${item.total.toStringAsFixed(2)}', style: AppTypography.labelMedium, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
