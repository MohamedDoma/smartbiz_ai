// SmartBiz AI — Billing & Subscription screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../settings_state.dart';
import '../models/settings_models.dart';

class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context, 'fb_billing_coming')),
      backgroundColor: AppColors.info,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showPlanDialog(BuildContext context, PlanFeatures plan, bool isCurrent) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, plan.nameKey)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, plan.priceKey), style: AppTypography.headingSmall.copyWith(color: AppColors.primary)),
        const SizedBox(height: AppSpacing.sm),
        Text('${plan.employees} ${tr(context, 'bill_employees')} · ${plan.aiCredits} ${tr(context, 'bill_ai_credits')}', style: AppTypography.bodySmall),
        const SizedBox(height: AppSpacing.md),
        if (isCurrent)
          Container(padding: const EdgeInsets.all(AppSpacing.sm), decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.check_circle, size: 16, color: AppColors.success), const SizedBox(width: 6),
              Text(tr(context, 'fb_current_plan'), style: AppTypography.caption.copyWith(color: AppColors.success))]))
        else
          Container(padding: const EdgeInsets.all(AppSpacing.sm), decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.info_outline, size: 16, color: AppColors.info), const SizedBox(width: 6),
              Expanded(child: Text(tr(context, 'fb_billing_coming'), style: AppTypography.caption.copyWith(color: AppColors.info)))])),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'inv_cancel')))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsState>();
    final sub = state.subscription;
    final isMobile = Responsive.isMobile(context);
    final planName = switch (sub.plan) { PlanType.starter => 'plan_starter', PlanType.growth => 'plan_growth', PlanType.business => 'plan_business', PlanType.enterprise => 'plan_enterprise' };

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'set_billing'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Current plan card
          Container(padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(tr(context, planName), style: AppTypography.headingSmall.copyWith(color: Colors.white)),
                if (sub.isTrial) ...[const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text(tr(context, 'bill_trial'), style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)))],
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text('${tr(context, 'bill_renews')}: ${sub.renewalDate.day}/${sub.renewalDate.month}/${sub.renewalDate.year}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
              const SizedBox(height: AppSpacing.md),
              Row(children: [
                _MiniStat(label: tr(context, 'bill_employees'), value: '${sub.activeEmployees}/${sub.employeeLimit}', color: Colors.white),
                const SizedBox(width: AppSpacing.xl),
                _MiniStat(label: tr(context, 'bill_ai_credits'), value: '${sub.aiCreditsRemaining}', color: sub.isAiLow ? AppColors.warning : Colors.white),
              ]),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Quick actions — all show feedback
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _ActionChip(icon: Icons.upgrade, label: tr(context, 'bill_upgrade'), color: AppColors.primary, onTap: () => _showComingSoon(context)),
            _ActionChip(icon: Icons.add_circle_outline, label: tr(context, 'bill_buy_credits'), color: AppColors.accent, onTap: () => _showComingSoon(context)),
            _ActionChip(icon: Icons.history, label: tr(context, 'bill_history'), color: AppColors.neutral600, onTap: () => _showComingSoon(context)),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Plans
          Text(tr(context, 'bill_plans'), style: AppTypography.headingSmall),
          const SizedBox(height: AppSpacing.md),
          ...SettingsState.plans.map((p) => _PlanCard(plan: p, current: sub.plan == p.type, onTap: () => _showPlanDialog(context, p, sub.plan == p.type))),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label; final String value; final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
    Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
  ]);
}

class _ActionChip extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionChip({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 16, color: color), label: Text(label),
    onPressed: onTap, side: BorderSide(color: color.withValues(alpha: 0.3)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    labelStyle: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500));
}

class _PlanCard extends StatelessWidget {
  final PlanFeatures plan; final bool current; final VoidCallback onTap;
  const _PlanCard({required this.plan, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: plan.recommended ? AppColors.primary : AppColors.divider, width: plan.recommended ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr(context, plan.nameKey), style: AppTypography.labelLarge)),
            if (plan.recommended) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, 'bill_recommended'), style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600))),
            if (current) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, 'bill_current'), style: const TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 4),
          Text(tr(context, plan.priceKey), style: AppTypography.headingSmall.copyWith(color: AppColors.primary)),
          const SizedBox(height: AppSpacing.sm),
          Text('${plan.employees} ${tr(context, 'bill_employees')} · ${plan.aiCredits} ${tr(context, 'bill_ai_credits')}', style: AppTypography.caption),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 6, runSpacing: 4, children: plan.featureKeys.map((k) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(6)),
            child: Text(tr(context, k), style: const TextStyle(fontSize: 10, color: AppColors.neutral600)),
          )).toList()),
        ]),
      ),
    );
  }
}
