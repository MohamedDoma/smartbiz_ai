// SmartBiz AI — Roles & permissions overview screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../models/employee_models.dart';
import '../widgets/employee_widgets.dart';

class RolesOverviewScreen extends StatelessWidget {
  const RolesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: AppSpacing.sm),
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.shield, size: 20, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(context, 'roles_title'), style: AppTypography.headingLarge),
                Text(tr(context, 'roles_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ])),
            ]),
            const SizedBox(height: AppSpacing.xl),
            ...RoleDefinitions.all.map((rd) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _RoleCard(rd: rd),
            )),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final RoleDefinition rd;
  const _RoleCard({required this.rd});

  Color get _accent => switch (rd.role) {
    AppRole.owner => AppColors.primary,
    AppRole.cashier => AppColors.info,
    AppRole.warehouse => AppColors.warning,
    AppRole.accountant => AppColors.success,
    AppRole.employee => AppColors.neutral500,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: _accent.withValues(alpha: 0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.shield_outlined, size: 18, color: _accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, rd.nameKey), style: AppTypography.labelLarge),
            Text(tr(context, rd.descKey), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ])),
          AiAccessBadge(access: rd.recommendedAi),
        ]),
        const Divider(height: AppSpacing.xl),

        // Modules
        Text(tr(context, 'emp_modules'), style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: 6, runSpacing: 6, children: rd.moduleKeys.map((k) => _Chip(label: tr(context, k), color: _accent)).toList()),
        const SizedBox(height: AppSpacing.md),

        // Permissions
        Text(tr(context, 'emp_perms_list'), style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: 6, runSpacing: 6, children: rd.permissionKeys.map((k) => _Chip(label: tr(context, k), color: AppColors.accent)).toList()),
        const SizedBox(height: AppSpacing.md),

        // Dashboard
        Row(children: [
          const Icon(Icons.dashboard_outlined, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text('${tr(context, 'roles_dashboard')}: ${tr(context, rd.dashboardKey)}', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
  );
}
