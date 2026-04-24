// SmartBiz AI — Invoices shared widgets.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/invoice_models.dart';

// ═══════════════════════════════════════════════════════════
//  Status Badge
// ═══════════════════════════════════════════════════════════
class InvoiceStatusBadge extends StatelessWidget {
  final InvoiceStatus status;
  const InvoiceStatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
    InvoiceStatus.draft => AppColors.neutral500,
    InvoiceStatus.sent => AppColors.info,
    InvoiceStatus.paid => AppColors.success,
    InvoiceStatus.overdue => AppColors.error,
  };

  String _key() => switch (status) {
    InvoiceStatus.draft => 'inv_status_draft',
    InvoiceStatus.sent => 'inv_status_sent',
    InvoiceStatus.paid => 'inv_status_paid',
    InvoiceStatus.overdue => 'inv_status_overdue',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(tr(context, _key()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color)),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Totals Section
// ═══════════════════════════════════════════════════════════
class InvoiceTotals extends StatelessWidget {
  final Invoice invoice;
  const InvoiceTotals({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Row(label: tr(context, 'inv_subtotal'), value: '\$${invoice.subtotal.toStringAsFixed(2)}'),
        _Row(label: '${tr(context, 'inv_tax')} (${(invoice.taxRate * 100).toStringAsFixed(0)}%)', value: '\$${invoice.tax.toStringAsFixed(2)}'),
        const Divider(height: AppSpacing.lg),
        _Row(label: tr(context, 'inv_total'), value: '\$${invoice.total.toStringAsFixed(2)}', bold: true),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _Row({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? AppTypography.headingSmall : AppTypography.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style.copyWith(color: bold ? AppColors.textPrimary : AppColors.textSecondary)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
