// SmartBiz AI — Super Admin placeholder screen.
// Reusable placeholder for sub-routes not yet fully implemented.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';

class SuperAdminPlaceholderScreen extends StatelessWidget {
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final Color color;
  final List<SaPlaceholderItem> items;

  const SuperAdminPlaceholderScreen({
    super.key,
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.color,
    required this.items,
  });

  // ── Factory constructors for each route ──────────────────

  factory SuperAdminPlaceholderScreen.tenants() => const SuperAdminPlaceholderScreen(
    titleKey: 'sa_tenants_title', subtitleKey: 'sa_tenants_subtitle',
    icon: Icons.business_outlined, color: AppColors.primary,
    items: [
      SaPlaceholderItem(Icons.list, 'sa_ph_tenant_list'),
      SaPlaceholderItem(Icons.person_add, 'sa_ph_tenant_create'),
      SaPlaceholderItem(Icons.block, 'sa_ph_tenant_suspend'),
      SaPlaceholderItem(Icons.settings, 'sa_ph_tenant_config'),
    ],
  );

  factory SuperAdminPlaceholderScreen.plans() => const SuperAdminPlaceholderScreen(
    titleKey: 'sa_plans_title', subtitleKey: 'sa_plans_subtitle',
    icon: Icons.card_membership_outlined, color: AppColors.success,
    items: [
      SaPlaceholderItem(Icons.view_list, 'sa_ph_plan_list'),
      SaPlaceholderItem(Icons.add_circle, 'sa_ph_plan_create'),
      SaPlaceholderItem(Icons.tune, 'sa_ph_plan_limits'),
      SaPlaceholderItem(Icons.attach_money, 'sa_ph_plan_pricing'),
    ],
  );

  factory SuperAdminPlaceholderScreen.modules() => const SuperAdminPlaceholderScreen(
    titleKey: 'sa_modules_title', subtitleKey: 'sa_modules_subtitle',
    icon: Icons.extension_outlined, color: AppColors.accent,
    items: [
      SaPlaceholderItem(Icons.grid_view, 'sa_ph_mod_registry'),
      SaPlaceholderItem(Icons.toggle_on, 'sa_ph_mod_toggle'),
      SaPlaceholderItem(Icons.flag, 'sa_ph_mod_feature'),
      SaPlaceholderItem(Icons.route, 'sa_ph_mod_deps'),
    ],
  );

  factory SuperAdminPlaceholderScreen.usage() => const SuperAdminPlaceholderScreen(
    titleKey: 'sa_usage_title', subtitleKey: 'sa_usage_subtitle',
    icon: Icons.auto_awesome_outlined, color: AppColors.warning,
    items: [
      SaPlaceholderItem(Icons.bar_chart, 'sa_ph_ai_overview'),
      SaPlaceholderItem(Icons.people, 'sa_ph_ai_per_tenant'),
      SaPlaceholderItem(Icons.speed, 'sa_ph_ai_rate'),
      SaPlaceholderItem(Icons.savings, 'sa_ph_ai_cost'),
    ],
  );

  factory SuperAdminPlaceholderScreen.health() => const SuperAdminPlaceholderScreen(
    titleKey: 'sa_health_title', subtitleKey: 'sa_health_subtitle',
    icon: Icons.monitor_heart_outlined, color: AppColors.info,
    items: [
      SaPlaceholderItem(Icons.dns, 'sa_ph_sys_services'),
      SaPlaceholderItem(Icons.storage, 'sa_ph_sys_db'),
      SaPlaceholderItem(Icons.memory, 'sa_ph_sys_resources'),
      SaPlaceholderItem(Icons.error_outline, 'sa_ph_sys_errors'),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 22, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, titleKey), style: AppTypography.headingLarge),
                  const SizedBox(height: 2),
                  Text(tr(context, subtitleKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ])),
              ]),
              const SizedBox(height: AppSpacing.xl),

              // Feature list
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
                    Row(children: [
                      Text(tr(context, 'sa_ph_features'), style: AppTypography.labelLarge),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tr(context, 'sa_ph_planned'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.lg),
                    ...items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(children: [
                        Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                          child: Icon(item.icon, size: 15, color: color),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(tr(context, item.labelKey), style: AppTypography.bodyMedium)),
                        Icon(Icons.chevron_right, size: 16, color: AppColors.neutral400),
                      ]),
                    )),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Info hint
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.neutral100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(tr(context, 'sa_ph_hint'), style: AppTypography.caption.copyWith(color: AppColors.textTertiary))),
                ]),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class SaPlaceholderItem {
  final IconData icon;
  final String labelKey;
  const SaPlaceholderItem(this.icon, this.labelKey);
}
