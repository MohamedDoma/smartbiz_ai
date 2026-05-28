// SmartBiz AI — Customer reusable widgets.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/customer_models.dart';

class CustomerStatusBadge extends StatelessWidget {
  final CustomerStatus status;
  const CustomerStatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
    CustomerStatus.active => AppColors.success,
    CustomerStatus.inactive => AppColors.neutral400,
    CustomerStatus.vip => AppColors.warning,
  };

  String get _key => switch (status) {
    CustomerStatus.active => 'cust_active',
    CustomerStatus.inactive => 'cust_inactive',
    CustomerStatus.vip => 'cust_vip',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (status == CustomerStatus.vip) ...[const Icon(Icons.star, size: 10, color: AppColors.warning), const SizedBox(width: 2)],
      Text(tr(context, _key), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _color)),
    ]),
  );
}

class BalanceChip extends StatelessWidget {
  final double balance;
  const BalanceChip({super.key, required this.balance});
  @override
  Widget build(BuildContext context) {
    final hasBalance = balance > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (hasBalance ? AppColors.error : AppColors.success).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Text(hasBalance ? '\$${balance.toStringAsFixed(0)}' : tr(context, 'cust_paid'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: hasBalance ? AppColors.error : AppColors.success)),
    );
  }
}

class CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  const CustomerCard({super.key, required this.customer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
        child: Row(children: [
          CircleAvatar(radius: 20, backgroundColor: customer.status == CustomerStatus.vip ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primarySurface,
            child: Text(customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: customer.status == CustomerStatus.vip ? AppColors.warning : AppColors.primary))),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.name, style: AppTypography.labelLarge),
            if (customer.company != null) Text(customer.company!, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            Text(customer.phone, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            CustomerStatusBadge(status: customer.status),
            const SizedBox(height: 4),
            BalanceChip(balance: customer.balance),
          ]),
        ]),
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  final CustomerActivity activity;
  const ActivityTile({super.key, required this.activity});

  IconData get _icon => switch (activity.iconName) {
    'receipt' => Icons.receipt_long,
    'payment' => Icons.payment,
    'task_alt' => Icons.task_alt,
    'auto_awesome' => Icons.auto_awesome,
    _ => Icons.circle,
  };

  Color get _color => switch (activity.iconName) {
    'receipt' => AppColors.primary,
    'payment' => AppColors.success,
    'task_alt' => AppColors.info,
    'auto_awesome' => AppColors.warning,
    _ => AppColors.neutral500,
  };

  @override
  Widget build(BuildContext context) {
    final diff = DateTime.now().difference(activity.timestamp);
    final ago = diff.inDays > 0 ? '${diff.inDays}d' : diff.inHours > 0 ? '${diff.inHours}h' : '${diff.inMinutes}m';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(children: [
        Container(width: 28, height: 28, decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Icon(_icon, size: 14, color: _color)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, activity.titleKey), style: AppTypography.labelSmall),
          Text(tr(context, activity.descKey), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ])),
        Text(ago, style: AppTypography.caption),
      ]),
    );
  }
}
