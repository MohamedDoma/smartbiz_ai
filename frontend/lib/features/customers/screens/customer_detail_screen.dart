// SmartBiz AI — Customer detail screen.
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

class CustomerDetailScreen extends StatelessWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomersState>();
    final c = state.getById(customerId);
    final isMobile = Responsive.isMobile(context);

    if (c == null) return Center(child: Text(tr(context, 'cust_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));

    final activities = state.activitiesFor(customerId);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Back + header
          Row(children: [
            IconButton(onPressed: () => context.go('/customers'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            CircleAvatar(radius: 22, backgroundColor: c.status == CustomerStatus.vip ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primarySurface,
              child: Text(c.name[0].toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.status == CustomerStatus.vip ? AppColors.warning : AppColors.primary))),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: AppTypography.headingLarge),
              if (c.company != null) Text(c.company!, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            CustomerStatusBadge(status: c.status),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Stats row
          _StatsRow(customer: c),
          const SizedBox(height: AppSpacing.xl),

          // Contact + Info
          _Section(title: tr(context, 'cust_contact'), children: [
            _InfoRow(icon: Icons.phone, label: tr(context, 'cust_phone'), value: c.phone),
            if (c.email != null) _InfoRow(icon: Icons.email, label: tr(context, 'cust_email'), value: c.email!),
            if (c.address != null) _InfoRow(icon: Icons.location_on, label: tr(context, 'cust_address'), value: c.address!),
            _InfoRow(icon: Icons.language, label: tr(context, 'cust_pref_lang'), value: c.preferredLang == 'ar' ? 'عربي' : 'English'),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Tags
          if (c.tags.isNotEmpty) ...[
            Text(tr(context, 'cust_tags'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 6, runSpacing: 6, children: c.tags.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(t, style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w500)),
            )).toList()),
            const SizedBox(height: AppSpacing.xl),
          ],

          // AI Insights placeholder
          _Section(title: tr(context, 'cust_ai_insights'), children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accent.withValues(alpha: 0.12))),
              child: Row(children: [
                const Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'cust_ai_placeholder'), style: AppTypography.bodySmall.copyWith(color: AppColors.accent))),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Notes
          _Section(title: tr(context, 'cust_notes'), children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(10)),
              child: Text(c.notes ?? tr(context, 'cust_no_notes'), style: AppTypography.bodySmall.copyWith(color: c.notes != null ? AppColors.textPrimary : AppColors.textSecondary)),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Activity timeline
          if (activities.isNotEmpty) ...[
            Text(tr(context, 'cust_activity'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            ...activities.map((a) => ActivityTile(activity: a)),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Actions
          Text(tr(context, 'cust_actions'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _ActionBtn(icon: Icons.receipt_long, label: tr(context, 'cust_create_inv'), color: AppColors.primary, onTap: () => context.go('/invoices/create')),
            _ActionBtn(icon: c.status == CustomerStatus.vip ? Icons.star_outline : Icons.star, label: c.status == CustomerStatus.vip ? tr(context, 'cust_unvip') : tr(context, 'cust_mark_vip'), color: AppColors.warning, onTap: () { state.toggleVip(c.id); _snack(context, tr(context, 'cust_updated')); }),
            if (c.status != CustomerStatus.inactive)
              _ActionBtn(icon: Icons.archive, label: tr(context, 'cust_archive'), color: AppColors.neutral600, onTap: () { state.archive(c.id); _snack(context, tr(context, 'cust_archived')); })
            else
              _ActionBtn(icon: Icons.unarchive, label: tr(context, 'cust_reactivate'), color: AppColors.success, onTap: () { state.reactivate(c.id); _snack(context, tr(context, 'cust_reactivated')); }),
          ]),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  void _snack(BuildContext ctx, String msg) => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
}

class _StatsRow extends StatelessWidget {
  final Customer customer;
  const _StatsRow({required this.customer});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _StatTile(label: tr(context, 'cust_total_invoices'), value: '${customer.totalInvoices}', color: AppColors.primary)),
    const SizedBox(width: AppSpacing.sm),
    Expanded(child: _StatTile(label: tr(context, 'cust_total_spent'), value: '\$${customer.totalSpent.toStringAsFixed(0)}', color: AppColors.success)),
    const SizedBox(width: AppSpacing.sm),
    Expanded(child: _StatTile(label: tr(context, 'cust_balance'), value: '\$${customer.balance.toStringAsFixed(0)}', color: customer.balance > 0 ? AppColors.error : AppColors.success)),
  ]);
}

class _StatTile extends StatelessWidget {
  final String label; final String value; final Color color;
  const _StatTile({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.12))),
    child: Column(children: [
      Text(value, style: AppTypography.headingSmall.copyWith(color: color)),
      Text(label, style: AppTypography.caption),
    ]),
  );
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.md),
    ...children,
  ]);
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      Icon(icon, size: 16, color: AppColors.neutral400),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(width: 100, child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))),
      Expanded(child: Text(value, style: AppTypography.bodyMedium)),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 16, color: color), label: Text(label),
    onPressed: onTap, side: BorderSide(color: color.withValues(alpha: 0.3)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    labelStyle: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500));
}
