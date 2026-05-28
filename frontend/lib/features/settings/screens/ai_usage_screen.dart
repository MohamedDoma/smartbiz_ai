// SmartBiz AI — AI usage / credits screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../settings_state.dart';

class AiUsageScreen extends StatelessWidget {
  const AiUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SettingsState>();
    final sub = state.subscription;
    final pct = sub.aiUsagePercent;
    final barColor = sub.isAiLow ? AppColors.error : AppColors.accent;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/settings'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'set_ai_usage'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Usage gauge
          Container(padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
            child: Column(children: [
              Row(children: [
                Expanded(child: Text(tr(context, 'ai_credits_remaining'), style: AppTypography.labelLarge)),
                Text('${sub.aiCreditsRemaining}', style: AppTypography.headingSmall.copyWith(color: barColor)),
                Text(' / ${sub.aiCreditsTotal}', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: AppSpacing.md),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: pct, backgroundColor: AppColors.neutral100, color: barColor, minHeight: 12)),
              const SizedBox(height: AppSpacing.sm),
              if (sub.isAiLow)
                Row(children: [
                  const Icon(Icons.warning_amber, size: 14, color: AppColors.error),
                  const SizedBox(width: 4),
                  Expanded(child: Text(tr(context, 'ai_low_warning'), style: AppTypography.caption.copyWith(color: AppColors.error))),
                ]),
            ]),
          ),
          const SizedBox(height: AppSpacing.md),

          // Buy credits action
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(tr(context, 'fb_billing_coming')),
                backgroundColor: AppColors.info,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ));
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: Text(tr(context, 'bill_buy_credits')),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.accent, side: const BorderSide(color: AppColors.accent), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(height: AppSpacing.xl),

          // Stats row
          Row(children: [
            Expanded(child: _StatCard(label: tr(context, 'ai_used_month'), value: '${sub.aiCreditsUsed}', color: AppColors.accent)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _StatCard(label: tr(context, 'ai_estimated'), value: '~${(sub.aiCreditsUsed * 1.3).toInt()}', color: AppColors.warning)),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Top modules
          Text(tr(context, 'ai_top_modules'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.md),
          _ModuleBar(label: tr(context, 'nav_ai_chat'), value: 0.45, credits: 1540, color: AppColors.primary),
          _ModuleBar(label: tr(context, 'nav_advisor'), value: 0.25, credits: 855, color: AppColors.accent),
          _ModuleBar(label: tr(context, 'nav_sales'), value: 0.18, credits: 615, color: AppColors.success),
          _ModuleBar(label: tr(context, 'nav_reports'), value: 0.12, credits: 410, color: AppColors.info),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label; final String value; final Color color;
  const _StatCard({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(value, style: AppTypography.headingSmall.copyWith(color: color)),
      Text(label, style: AppTypography.caption),
    ]),
  );
}

class _ModuleBar extends StatelessWidget {
  final String label; final double value; final int credits; final Color color;
  const _ModuleBar({required this.label, required this.value, required this.credits, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: AppTypography.bodySmall)),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value, backgroundColor: AppColors.neutral100, color: color, minHeight: 10))),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(width: 50, child: Text('$credits', style: AppTypography.labelSmall, textAlign: TextAlign.end)),
    ]),
  );
}
