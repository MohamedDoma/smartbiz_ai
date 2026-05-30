// SmartBiz AI — Employee detail screen (Phase 16.2).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../employees_state.dart';
import '../org_state.dart';
import '../roles_state.dart';
import '../models/employee_models.dart';
import '../widgets/employee_widgets.dart';

class EmployeeDetailScreen extends StatelessWidget {
  final String employeeId;
  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context) {
    final empState = context.watch<EmployeesState>();
    final orgState = context.watch<OrgState>();
    final emp = empState.getById(employeeId);
    final isMobile = Responsive.isMobile(context);

    if (emp == null) {
      return Center(child: Text(tr(context, 'emp_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));
    }

    final a = orgState.getAssignment(employeeId);
    final roleDef = RoleDefinitions.forRole(emp.role);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: AppSpacing.sm),
              CircleAvatar(radius: 22, backgroundColor: AppColors.primarySurface,
                child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?', style: AppTypography.headingSmall.copyWith(color: AppColors.primary))),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(emp.name, style: AppTypography.headingLarge),
                Text(emp.email, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ])),
              EmpStatusBadge(status: emp.status),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // Info card
            _Card(children: [
              _InfoRow(label: tr(context, 'emp_role'), trailing: RoleBadge(role: emp.role)),
              _InfoRow(label: tr(context, 'emp_ai_access'), trailing: AiAccessBadge(access: emp.aiAccess)),
              if (emp.department != null) _InfoRow(label: tr(context, 'emp_department'), value: emp.department!),
              if (emp.phone != null) _InfoRow(label: tr(context, 'emp_phone'), value: emp.phone!),
              _InfoRow(label: tr(context, 'emp_lang_pref'), value: emp.langPref == 'ar' ? tr(context, 'lang_ar') : tr(context, 'lang_en')),
              if (emp.lastActive != null) _InfoRow(label: tr(context, 'emp_last_active'), value: _fmtAgo(context, emp.lastActive!)),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // Organization assignment card
            Text(tr(context, 'asgn_title'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Card(children: [
              if (a != null) ...[
                if (a.departmentId != null)
                  _InfoRow(label: tr(context, 'org_department'), value: orgState.getDept(a.departmentId!)?.name ?? '—'),
                if (a.teamIds.isNotEmpty)
                  _InfoRow(label: tr(context, 'org_teams'), value: a.teamIds.map((id) => orgState.getTeam(id)?.name ?? id).join(', ')),
                if (a.managerId != null)
                  _InfoRow(label: tr(context, 'asgn_manager'), value: orgState.empName(a.managerId!)),
                _InfoRow(label: tr(context, 'asgn_primary_role'), value: orgState.roleLabel(a.primaryRoleId)),
                if (a.hasExtraRoles) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(tr(context, 'asgn_extra_roles'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                    const Spacer(),
                    Wrap(spacing: 4, children: a.extraRoleIds.map((id) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                      child: Text(orgState.roleLabel(id), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.accent)),
                    )).toList()),
                  ]),
                ],
              ] else
                Text(tr(context, 'asgn_not_assigned'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () => context.go('/employees/$employeeId/assignment'),
                icon: const Icon(Icons.edit, size: 14),
                label: Text(tr(context, 'asgn_edit')),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // Permissions summary
            Text(tr(context, 'emp_permissions'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Card(children: [
              Text(tr(context, roleDef.descKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.md),
              Text(tr(context, 'emp_modules'), style: AppTypography.labelMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: roleDef.moduleKeys.map((k) => _PermChip(label: tr(context, k), color: AppColors.primary)).toList()),
              const SizedBox(height: AppSpacing.md),
              Text(tr(context, 'emp_perms_list'), style: AppTypography.labelMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(spacing: 6, runSpacing: 6, children: roleDef.permissionKeys.map((k) => _PermChip(label: tr(context, k), color: AppColors.accent)).toList()),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // Actions
            _Card(children: [
              Text(tr(context, 'emp_actions'), style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.md),
              if (emp.status == EmpStatus.active)
                _ActionTile(icon: Icons.block, label: tr(context, 'emp_suspend'), color: AppColors.error, onTap: () => empState.suspend(emp.id)),
              if (emp.status == EmpStatus.suspended)
                _ActionTile(icon: Icons.check_circle, label: tr(context, 'emp_reactivate'), color: AppColors.success, onTap: () => empState.reactivate(emp.id)),
              if (emp.status == EmpStatus.invited)
                _ActionTile(icon: Icons.send, label: tr(context, 'emp_resend'), color: AppColors.info, onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'ux_invite_resent')), backgroundColor: AppColors.info, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
              _ActionTile(icon: Icons.swap_horiz, label: tr(context, 'emp_change_role'), color: AppColors.primary, onTap: () => _showRoleDialog(context, empState, emp)),
              _ActionTile(icon: Icons.auto_awesome, label: tr(context, 'emp_change_ai'), color: AppColors.accent, onTap: () => _showAiDialog(context, empState, emp)),
            ]),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }

  String _fmtAgo(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${tr(context, 'ux_min_ago')}';
    if (diff.inHours < 24) return '${diff.inHours} ${tr(context, 'ux_hr_ago')}';
    return '${diff.inDays} ${tr(context, 'ux_day_ago')}';
  }

  void _showRoleDialog(BuildContext context, EmployeesState state, Employee emp) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr(context, 'emp_change_role')),
      content: Column(mainAxisSize: MainAxisSize.min, children: AppRole.values.where((r) => r != AppRole.owner).map((r) {
        final key = switch (r) { AppRole.owner => 'role_owner', AppRole.cashier => 'role_cashier', AppRole.warehouse => 'role_warehouse', AppRole.accountant => 'role_accountant', AppRole.employee => 'role_employee' };
        return RadioListTile<AppRole>(value: r, groupValue: emp.role, title: Text(tr(context, key)),
          onChanged: (v) { if (v != null) { state.changeRole(emp.id, v); Navigator.pop(ctx); } });
      }).toList()),
    ));
  }

  void _showAiDialog(BuildContext context, EmployeesState state, Employee emp) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(tr(context, 'emp_change_ai')),
      content: Column(mainAxisSize: MainAxisSize.min, children: AiAccess.values.map((a) {
        final key = switch (a) { AiAccess.full => 'ai_full', AiAccess.limited => 'ai_limited', AiAccess.none => 'ai_none' };
        return RadioListTile<AiAccess>(value: a, groupValue: emp.aiAccess, title: Text(tr(context, key)),
          onChanged: (v) { if (v != null) { state.changeAiAccess(emp.id, v); Navigator.pop(ctx); } });
      }).toList()),
    ));
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

class _InfoRow extends StatelessWidget {
  final String label; final String? value; final Widget? trailing;
  const _InfoRow({required this.label, this.value, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary))),
      if (value != null) Text(value!, style: AppTypography.labelMedium),
      if (trailing != null) trailing!,
    ]),
  );
}

class _PermChip extends StatelessWidget {
  final String label; final Color color;
  const _PermChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color)),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(10),
      child: Container(padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(children: [
          Icon(icon, size: 18, color: color), const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.labelMedium.copyWith(color: color))),
          Icon(Icons.chevron_right, size: 18, color: color),
        ]),
      ),
    ),
  );
}
