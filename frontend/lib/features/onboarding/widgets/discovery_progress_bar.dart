// SmartBiz AI — Discovery progress bar widget.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/onboarding_models.dart';

class DiscoveryProgressBar extends StatelessWidget {
  final DiscoveryProgress progress;

  const DiscoveryProgressBar({super.key, required this.progress});

  static const _categoryKeys = <DiscoveryCategory, String>{
    DiscoveryCategory.companyBasics: 'cat_company_basics',
    DiscoveryCategory.businessType: 'cat_business_type',
    DiscoveryCategory.operations: 'cat_operations',
    DiscoveryCategory.teamRoles: 'cat_team_roles',
    DiscoveryCategory.productsServices: 'cat_products_services',
    DiscoveryCategory.financeWorkflows: 'cat_finance_workflows',
  };

  @override
  Widget build(BuildContext context) {
    final percent = progress.completionPercent;
    final completed = progress.completedCount;
    final total = progress.categories.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress header
          Row(
            children: [
              const Icon(Icons.explore, size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(tr(context, 'onboard_progress'), style: AppTypography.labelSmall),
              const Spacer(),
              Text('$completed / $total', style: AppTypography.labelSmall.copyWith(color: AppColors.accent)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 4,
              backgroundColor: AppColors.neutral100,
              valueColor: AlwaysStoppedAnimation<Color>(
                percent >= 1.0 ? AppColors.success : AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),

          // Category chips
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _categoryKeys.entries.map((entry) {
                final done = progress.categories[entry.key] ?? false;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
                  child: Chip(
                    label: Text(
                      tr(context, entry.value),
                      style: TextStyle(
                        fontSize: 10,
                        color: done ? Colors.white : AppColors.neutral500,
                        fontWeight: done ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    backgroundColor: done ? AppColors.success : AppColors.neutral100,
                    side: BorderSide.none,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
