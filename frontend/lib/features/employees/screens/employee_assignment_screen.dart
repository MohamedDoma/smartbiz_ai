// SmartBiz AI — Employee assignment editor screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../org_state.dart';
import '../roles_state.dart';
import '../models/role_models.dart';

class EmployeeAssignmentScreen extends StatelessWidget {
  final String employeeId;
  const EmployeeAssignmentScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context) {
    final orgState = context.watch<OrgState>();
    final rolesState = context.watch<RolesState>();
    final isMobile = Responsive.isMobile(context);
    final a = orgState.getAssignment(employeeId);
    final name = orgState.empName(employeeId);

    // Build roles map for effective permissions
    final rolesMap = <String, CustomRole>{};
    for (final r in rolesState.allRoles) { rolesMap[r.id] = r; }

    final effective = orgState.effectivePermissions(employeeId, rolesMap);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            IconButton(onPressed: () => context.go('/employees/$employeeId'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            CircleAvatar(radius: 18, backgroundColor: AppColors.primarySurface,
              child: Text(name.isNotEmpty ? name[0] : '?', style: AppTypography.labelLarge.copyWith(color: AppColors.primary))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: AppTypography.headingMedium),
              Text(tr(context, 'asgn_title'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ── Department ──────────────────────────────────
          if (orgState.deptsEnabled) ...[
            _SectionLabel(label: tr(context, 'org_department')),
            const SizedBox(height: AppSpacing.sm),
            _DropdownCard<String?>(
              value: a?.departmentId,
              items: [DropdownMenuItem<String?>(value: null, child: Text(tr(context, 'asgn_none'))),
                ...orgState.departments.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name)))],
              onChanged: (v) => orgState.assignDept(employeeId, v),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Team ────────────────────────────────────────
          if (orgState.teamsEnabled) ...[
            _SectionLabel(label: tr(context, 'org_teams')),
            const SizedBox(height: AppSpacing.sm),
            if (orgState.teams.isEmpty)
              Text(tr(context, 'org_no_teams'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))
            else
              Wrap(spacing: 6, runSpacing: 6, children: orgState.teams.map((t) {
                final isMember = a?.teamIds.contains(t.id) ?? false;
                return FilterChip(label: Text(t.name), selected: isMember,
                  onSelected: (_) => isMember ? orgState.removeFromTeam(employeeId, t.id) : orgState.addToTeam(employeeId, t.id),
                  selectedColor: AppColors.accent.withValues(alpha: 0.15), checkmarkColor: AppColors.accent,
                  side: BorderSide(color: isMember ? AppColors.accent : AppColors.neutral300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)));
              }).toList()),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Manager ─────────────────────────────────────
          _SectionLabel(label: tr(context, 'asgn_manager')),
          const SizedBox(height: AppSpacing.sm),
          _DropdownCard<String?>(
            value: a?.managerId,
            items: [DropdownMenuItem<String?>(value: null, child: Text(tr(context, 'asgn_none'))),
              ...orgState.allEmployeeIds.where((id) => id != employeeId).map((id) =>
                DropdownMenuItem<String?>(value: id, child: Text(orgState.empName(id))))],
            onChanged: (v) => orgState.assignManager(employeeId, v),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Primary Role ────────────────────────────────
          _SectionLabel(label: tr(context, 'asgn_primary_role')),
          const SizedBox(height: AppSpacing.sm),
          _DropdownCard<String>(
            value: a?.primaryRoleId ?? 'sys_employee',
            items: RoleTemplates.allSelectableRoles().where((r) => r.id != 'sys_owner').map((r) =>
              DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
            onChanged: (v) { if (v != null) orgState.setPrimaryRole(employeeId, v); },
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Extra Roles ─────────────────────────────────
          _SectionLabel(label: tr(context, 'asgn_extra_roles')),
          Text(tr(context, 'asgn_extra_hint'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: 6, runSpacing: 6, children: RoleTemplates.allSelectableRoles()
              .where((r) => r.id != 'sys_owner' && r.id != (a?.primaryRoleId ?? ''))
              .map((r) {
            final isExtra = a?.extraRoleIds.contains(r.id) ?? false;
            return FilterChip(label: Text(r.name), selected: isExtra,
              onSelected: (_) => orgState.toggleExtraRole(employeeId, r.id),
              selectedColor: AppColors.primary.withValues(alpha: 0.12), checkmarkColor: AppColors.primary,
              side: BorderSide(color: isExtra ? AppColors.primary : AppColors.neutral300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isExtra ? AppColors.primary : AppColors.textSecondary));
          }).toList()),
          const SizedBox(height: AppSpacing.xl),

          // ── Effective Permissions ───────────────────────
          _SectionLabel(label: tr(context, 'asgn_effective')),
          Text(tr(context, 'asgn_eff_hint'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          if (effective.isEmpty)
            Text(tr(context, 'asgn_no_perms'), style: AppTypography.bodySmall.copyWith(color: AppColors.neutral400))
          else
            ...AppModule.values.where((m) => effective[m]?.isNotEmpty ?? false).map((m) {
              final perms = effective[m]!;
              final hasDangerous = perms.any((p) => p == PermAction.delete || p == PermAction.manage);
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: hasDangerous ? AppColors.error.withValues(alpha: 0.03) : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hasDangerous ? AppColors.error.withValues(alpha: 0.2) : AppColors.divider),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                    title: Row(children: [
                      Text(tr(context, m.labelKey), style: AppTypography.labelMedium),
                      if (hasDangerous) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: (hasDangerous ? AppColors.error : AppColors.primary).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                        child: Text('${perms.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: hasDangerous ? AppColors.error : AppColors.primary)),
                      ),
                    ]),
                    children: [
                      Wrap(spacing: 4, runSpacing: 4, children: perms.map((p) {
                        final isDangerous = p == PermAction.delete || p == PermAction.manage;
                        final color = isDangerous ? AppColors.error : AppColors.primary;
                        return Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                          child: Text(tr(context, permActionKey(p)), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)));
                      }).toList()),
                    ],
                  ),
                ),
              );
            }),
          const SizedBox(height: AppSpacing.xl),

          // Save button
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'asgn_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
              context.go('/employees/$employeeId');
            },
            icon: const Icon(Icons.check, size: 16), label: Text(tr(context, 'cr_save_changes')),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label, style: AppTypography.labelLarge);
}

class _DropdownCard<T> extends StatelessWidget {
  final T value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _DropdownCard({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.surface, border: Border.all(color: AppColors.neutral300), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: value, isExpanded: true, items: items, onChanged: onChanged)),
  );
}
