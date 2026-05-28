// SmartBiz AI — Reusable dashboard widgets.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/dashboard_models.dart';

// ═══════════════════════════════════════════════════════════
//  Icon + Color Mapping
// ═══════════════════════════════════════════════════════════
IconData mapIcon(String name) => switch (name) {
  'point_of_sale' => Icons.point_of_sale,
  'trending_up' => Icons.trending_up,
  'trending_down' => Icons.trending_down,
  'receipt_long' => Icons.receipt_long,
  'receipt' => Icons.receipt,
  'inventory_2' => Icons.inventory_2,
  'people' => Icons.people,
  'auto_awesome' => Icons.auto_awesome,
  'warning' => Icons.warning_amber,
  'payment' => Icons.payment,
  'bolt' => Icons.bolt,
  'bar_chart' => Icons.bar_chart,
  'add_box' => Icons.add_box_outlined,
  'person_add' => Icons.person_add_outlined,
  'lightbulb' => Icons.lightbulb_outlined,
  'warehouse' => Icons.warehouse,
  'account_balance' => Icons.account_balance,
  'task_alt' => Icons.task_alt,
  _ => Icons.circle,
};

Color mapColor(String name) => switch (name) {
  'primary' => AppColors.primary,
  'accent' => AppColors.accent,
  'success' => AppColors.success,
  'warning' => AppColors.warning,
  'error' => AppColors.error,
  'info' => AppColors.info,
  _ => AppColors.neutral500,
};

// ═══════════════════════════════════════════════════════════
//  MetricCard
// ═══════════════════════════════════════════════════════════
class MetricCardWidget extends StatelessWidget {
  final DashboardMetric metric;
  const MetricCardWidget({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final color = mapColor(metric.colorName);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(mapIcon(metric.iconName), size: 18, color: color),
              ),
              const Spacer(),
              if (metric.trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (metric.trendUp ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(metric.trendUp ? Icons.arrow_upward : Icons.arrow_downward, size: 10,
                          color: metric.trendUp ? AppColors.success : AppColors.error),
                      const SizedBox(width: 2),
                      Text(metric.trend!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: metric.trendUp ? AppColors.success : AppColors.error)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(metric.value, style: AppTypography.headingLarge.copyWith(fontSize: 22)),
          const SizedBox(height: 2),
          Text(tr(context, metric.labelKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  RecommendationCard
// ═══════════════════════════════════════════════════════════
class RecommendationCardWidget extends StatelessWidget {
  final DashboardRecommendation rec;
  const RecommendationCardWidget({super.key, required this.rec});

  Color get _impactColor => switch (rec.impact) {
    RecommendationImpact.high => AppColors.error,
    RecommendationImpact.medium => AppColors.warning,
    RecommendationImpact.low => AppColors.info,
  };

  String _impactKey() => switch (rec.impact) {
    RecommendationImpact.high => 'dash_impact_high',
    RecommendationImpact.medium => 'dash_impact_medium',
    RecommendationImpact.low => 'dash_impact_low',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(mapIcon(rec.iconName), size: 16, color: _impactColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(tr(context, rec.titleKey), style: AppTypography.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(tr(context, _impactKey()), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _impactColor)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(tr(context, rec.descriptionKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _RecAction(label: tr(context, 'dash_rec_review'), primary: true),
              const SizedBox(width: AppSpacing.sm),
              _RecAction(label: tr(context, 'dash_rec_dismiss')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecAction extends StatelessWidget {
  final String label;
  final bool primary;
  const _RecAction({required this.label, this.primary = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: AppColors.neutral300),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: primary ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  QuickActionCard
// ═══════════════════════════════════════════════════════════
class QuickActionCardWidget extends StatelessWidget {
  final DashboardQuickAction action;
  const QuickActionCardWidget({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(action.route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
              child: Icon(mapIcon(action.iconName), size: 20, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(tr(context, action.labelKey), style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary),
                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  ActivityItem
// ═══════════════════════════════════════════════════════════
class ActivityItemWidget extends StatelessWidget {
  final DashboardActivity activity;
  const ActivityItemWidget({super.key, required this.activity});

  @override
  Widget build(BuildContext context) {
    final color = mapColor(activity.colorName);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(mapIcon(activity.iconName), size: 14, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(tr(context, activity.titleKey), style: AppTypography.bodyMedium, overflow: TextOverflow.ellipsis)),
          Text(tr(context, activity.timeKey), style: AppTypography.caption),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  OpsSnapshotCard
// ═══════════════════════════════════════════════════════════
class OpsSnapshotCard extends StatelessWidget {
  final OpsSnapshotItem item;
  const OpsSnapshotCard({super.key, required this.item});

  Color get _statusColor => switch (item.statusKey) {
    'good' => AppColors.success,
    'warning' => AppColors.warning,
    'alert' => AppColors.error,
    _ => AppColors.neutral500,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(mapIcon(item.iconName), size: 18, color: _statusColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, item.labelKey), style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary)),
                Text(item.value, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: _statusColor, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SectionHeader
// ═══════════════════════════════════════════════════════════
class DashboardSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;
  final Widget? trailing;
  const DashboardSectionHeader({super.key, required this.icon, required this.title, this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: iconColor ?? AppColors.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTypography.headingSmall)),
        if (trailing != null) trailing!,
      ],
    );
  }
}
