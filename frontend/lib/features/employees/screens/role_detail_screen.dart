// SmartBiz AI — Role detail + permission editor screen.
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

class RoleDetailScreen extends StatelessWidget {
  final String roleId;
  const RoleDetailScreen({super.key, required this.roleId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RolesState>();
    final role = state.getById(roleId);
    final isMobile = Responsive.isMobile(context);

    if (role == null) {
      return Center(child: Text(tr(context, 'cr_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));
    }

    final isSystem = role.type == RoleType.system;
    final accent = switch (role.dashboardTemplate.colorName) {
      'primary' => AppColors.primary,
      'success' => AppColors.success,
      'warning' => AppColors.warning,
      'info' => AppColors.info,
      'accent' => AppColors.accent,
      _ => AppColors.neutral500,
    };

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            IconButton(onPressed: () => context.go('/employees/roles'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Container(width: 40, height: 40, decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(isSystem ? Icons.shield : Icons.tune, size: 20, color: accent)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(role.name, style: AppTypography.headingLarge),
              Text(role.description, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: (isSystem ? AppColors.info : AppColors.accent).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(tr(context, isSystem ? 'cr_system' : 'cr_custom'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isSystem ? AppColors.info : AppColors.accent))),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Info card
          _InfoCard(role: role, accent: accent),
          const SizedBox(height: AppSpacing.xl),

          // System role warning
          if (isSystem) ...[
            Container(width: double.infinity, padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.warning.withValues(alpha: 0.2))),
              child: Row(children: [
                const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'cr_system_readonly'), style: AppTypography.bodySmall.copyWith(color: AppColors.warning))),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Permission matrix — ExpansionTile for performance
          Text(tr(context, 'cr_permissions'), style: AppTypography.headingSmall),
          const SizedBox(height: AppSpacing.sm),
          Text('${role.totalPermissions} ${tr(context, 'cr_perms_active')} · ${role.enabledModuleCount} ${tr(context, 'cr_modules')}', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          ...AppModule.values.map((m) {
            final perms = role.permissions[m]!;
            return _DetailModuleExpansion(
              module: m, perms: perms, isSystem: isSystem,
              onToggle: isSystem ? null : (a) { state.togglePermission(roleId, m, a); },
              onSelectAll: isSystem ? null : () { state.selectAllModule(roleId, m); },
              onClear: isSystem ? null : () { state.clearModule(roleId, m); },
            );
          }),
          const SizedBox(height: AppSpacing.xl),

          // Actions
          if (!isSystem) ...[
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _confirmDelete(context, state, role),
                icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                label: Text(tr(context, 'cr_delete'), style: const TextStyle(color: AppColors.error)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.error), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cr_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
                },
                icon: const Icon(Icons.check, size: 16), label: Text(tr(context, 'cr_save_changes')),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ]),
          ] else
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () {
                final copy = role.deepCopy(id: '', name: '${role.name} (Copy)', type: RoleType.custom);
                context.read<RolesState>().addRole(copy);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cr_duplicated')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              },
              icon: const Icon(Icons.copy, size: 16), label: Text(tr(context, 'cr_duplicate')),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  void _confirmDelete(BuildContext context, RolesState state, CustomRole role) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'cr_delete_title')),
      content: Text('${tr(context, 'cr_delete_confirm')} "${role.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () { state.deleteRole(role.id); Navigator.pop(ctx); context.go('/employees/roles');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cr_deleted')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: Text(tr(context, 'cr_delete'))),
      ],
    ));
  }
}

class _InfoCard extends StatelessWidget {
  final CustomRole role; final Color accent;
  const _InfoCard({required this.role, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Row(label: tr(context, 'cr_dashboard_type'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(tr(context, role.dashboardTemplate.labelKey), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent)))),
      _Row(label: tr(context, 'cr_ai_access'), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Text(tr(context, roleAiKey(role.aiAccess)), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)))),
      _Row(label: tr(context, 'cr_modules'), value: '${role.enabledModuleCount}'),
      _Row(label: tr(context, 'cr_total_perms'), value: '${role.totalPermissions}'),
      _Row(label: tr(context, 'cr_assigned'), value: '${role.assignedCount}'),
    ]),
  );
}

class _Row extends StatelessWidget {
  final String label; final String? value; final Widget? child;
  const _Row({required this.label, this.value, this.child});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary))),
      if (value != null) Text(value!, style: AppTypography.labelMedium),
      if (child != null) child!,
    ]),
  );
}

class _DetailModuleExpansion extends StatelessWidget {
  final AppModule module;
  final ModulePermissions perms;
  final bool isSystem;
  final void Function(PermAction)? onToggle;
  final VoidCallback? onSelectAll;
  final VoidCallback? onClear;
  const _DetailModuleExpansion({required this.module, required this.perms, required this.isSystem, this.onToggle, this.onSelectAll, this.onClear});

  IconData get _icon => switch (module.iconName) {
    'dashboard_outlined' => Icons.dashboard_outlined,
    'auto_awesome' => Icons.auto_awesome,
    'lightbulb' => Icons.lightbulb_outlined,
    'people' => Icons.people,
    'receipt_long' => Icons.receipt_long,
    'inventory_2' => Icons.inventory_2,
    'warehouse' => Icons.warehouse,
    'account_balance' => Icons.account_balance,
    'bar_chart' => Icons.bar_chart,
    'badge' => Icons.badge,
    'shield' => Icons.shield,
    'settings' => Icons.settings,
    'credit_card' => Icons.credit_card,
    _ => Icons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final hasAny = perms.hasAny;
    final enabledCount = perms.enabled.length;
    final totalCount = module.applicableActions.length;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: hasAny ? AppColors.primarySurface.withValues(alpha: 0.3) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasAny ? AppColors.primary.withValues(alpha: 0.2) : AppColors.divider),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
          leading: Icon(_icon, size: 18, color: hasAny ? AppColors.primary : AppColors.neutral500),
          title: Row(children: [
            Expanded(child: Text(tr(context, module.labelKey), style: AppTypography.labelLarge.copyWith(color: hasAny ? AppColors.primary : AppColors.textPrimary))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: (hasAny ? AppColors.primary : AppColors.neutral500).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
              child: Text('$enabledCount/$totalCount', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: hasAny ? AppColors.primary : AppColors.neutral500)),
            ),
          ]),
          children: [
            if (!isSystem)
              Align(alignment: AlignmentDirectional.centerEnd, child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: perms.hasAll
                    ? InkWell(onTap: onClear, child: Text(tr(context, 'cr_clear'), style: AppTypography.caption.copyWith(color: AppColors.error)))
                    : InkWell(onTap: onSelectAll, child: Text(tr(context, 'cr_all'), style: AppTypography.caption.copyWith(color: AppColors.primary))),
              )),
            Wrap(spacing: 6, runSpacing: 6, children: module.applicableActions.map((a) {
              final on = perms.enabled.contains(a);
              return FilterChip(
                label: Text(tr(context, permActionKey(a))),
                selected: on,
                onSelected: isSystem ? null : (_) => onToggle?.call(a),
                selectedColor: AppColors.primary.withValues(alpha: 0.12),
                checkmarkColor: AppColors.primary,
                disabledColor: on ? AppColors.primary.withValues(alpha: 0.06) : null,
                side: BorderSide(color: on ? AppColors.primary : AppColors.neutral300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: on ? AppColors.primary : AppColors.textSecondary),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }
}
