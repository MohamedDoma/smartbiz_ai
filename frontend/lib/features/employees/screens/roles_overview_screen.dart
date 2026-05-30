// SmartBiz AI — Roles management overview screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../models/role_models.dart';
import '../roles_state.dart';

class RolesOverviewScreen extends StatelessWidget {
  const RolesOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RolesState>();
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.shield, size: 20, color: Colors.white)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'cr_title'), style: AppTypography.headingLarge),
              Text(tr(context, 'cr_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            FilledButton.icon(
              onPressed: () => context.go('/employees/roles/create'),
              icon: const Icon(Icons.add, size: 16),
              label: Text(tr(context, 'cr_create')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // System roles
          _SectionLabel(label: tr(context, 'cr_system_roles'), count: state.systemRoles.length),
          const SizedBox(height: AppSpacing.md),
          ...state.systemRoles.map((r) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _RoleCard(role: r))),
          const SizedBox(height: AppSpacing.xl),

          // Custom roles
          _SectionLabel(label: tr(context, 'cr_custom_roles'), count: state.customRoles.length),
          const SizedBox(height: AppSpacing.md),
          if (state.customRoles.isEmpty)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
              child: Column(children: [
                const Icon(Icons.add_circle_outline, size: 40, color: AppColors.neutral400),
                const SizedBox(height: AppSpacing.md),
                Text(tr(context, 'cr_no_custom'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton(onPressed: () => context.go('/employees/roles/create'), child: Text(tr(context, 'cr_create_first'))),
              ]),
            )
          else
            ...state.customRoles.map((r) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _RoleCard(role: r))),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label; final int count;
  const _SectionLabel({required this.label, required this.count});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: AppTypography.headingSmall),
    const SizedBox(width: AppSpacing.sm),
    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary))),
  ]);
}

class _RoleCard extends StatelessWidget {
  final CustomRole role;
  const _RoleCard({required this.role});

  Color get _accent => switch (role.dashboardType) {
    DashboardType.owner => AppColors.primary,
    DashboardType.cashier => AppColors.success,
    DashboardType.warehouse => AppColors.warning,
    DashboardType.accountant => AppColors.info,
    DashboardType.employee => AppColors.neutral500,
    DashboardType.custom => AppColors.accent,
  };

  @override
  Widget build(BuildContext context) {
    final isSystem = role.type == RoleType.system;
    return InkWell(
      onTap: () => context.go('/employees/roles/${role.id}'),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: _accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(isSystem ? Icons.shield : Icons.tune, size: 18, color: _accent)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role.name, style: AppTypography.labelLarge),
              Text(role.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
            // Type badge
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: (isSystem ? AppColors.info : AppColors.accent).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, isSystem ? 'cr_system' : 'cr_custom'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSystem ? AppColors.info : AppColors.accent))),
          ]),
          const Divider(height: AppSpacing.lg),
          // Stats row
          Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.sm, children: [
            _StatChip(icon: Icons.dashboard_outlined, label: tr(context, dashTypeKey(role.dashboardType)), color: _accent),
            _StatChip(icon: Icons.auto_awesome, label: tr(context, roleAiKey(role.aiAccess)), color: AppColors.accent),
            _StatChip(icon: Icons.extension, label: '${role.enabledModuleCount} ${tr(context, 'cr_modules')}', color: AppColors.primary),
            _StatChip(icon: Icons.people_outline, label: '${role.assignedCount} ${tr(context, 'cr_assigned')}', color: AppColors.info),
          ]),
          const SizedBox(height: AppSpacing.sm),
          // Edit arrow
          Align(alignment: AlignmentDirectional.centerEnd, child: Icon(Icons.chevron_right, size: 18, color: AppColors.neutral400)),
        ]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
  ]);
}
