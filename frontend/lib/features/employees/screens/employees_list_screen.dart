// SmartBiz AI — Employees list screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../employees_state.dart';
import '../models/employee_models.dart';
import '../widgets/employee_widgets.dart';

class EmployeesListScreen extends StatelessWidget {
  const EmployeesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmployeesState>();
    final isMobile = Responsive.isMobile(context);
    final employees = state.filtered;

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(context, 'emp_title'), style: AppTypography.headingLarge),
                      Text('${state.activeCount} ${tr(context, 'emp_status_active')} · ${state.invitedCount} ${tr(context, 'emp_status_invited')}',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/employees/roles'),
                    icon: const Icon(Icons.shield_outlined, size: 16),
                    label: Text(tr(context, 'emp_roles')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/employees/role-management'),
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                    label: Text(tr(context, 'rpm_title')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/employees/employee-roles'),
                    icon: const Icon(Icons.group_outlined, size: 16),
                    label: Text(tr(context, 'emr_title')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/employees/organization'),
                    icon: const Icon(Icons.account_tree_outlined, size: 16),
                    label: Text(tr(context, 'org_title')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => context.go('/employees/invite'),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: Text(tr(context, 'emp_invite')),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Search
              TextField(
                onChanged: state.setSearch,
                textDirection: Directionality.of(context),
                decoration: InputDecoration(
                  hintText: tr(context, 'emp_search'),
                  hintTextDirection: Directionality.of(context),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Filters
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _Chip(label: tr(context, 'inv_all'), selected: state.roleFilter == null && state.statusFilter == null, onTap: () { state.setRoleFilter(null); state.setStatusFilter(null); }),
                  ...EmpStatus.values.map((s) {
                    final key = switch (s) { EmpStatus.active => 'emp_status_active', EmpStatus.invited => 'emp_status_invited', EmpStatus.suspended => 'emp_status_suspended' };
                    return _Chip(label: tr(context, key), selected: state.statusFilter == s, onTap: () => state.setStatusFilter(s));
                  }),
                  Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppColors.divider),
                  ...AppRole.values.map((r) {
                    final key = switch (r) { AppRole.owner => 'role_owner', AppRole.cashier => 'role_cashier', AppRole.warehouse => 'role_warehouse', AppRole.accountant => 'role_accountant', AppRole.employee => 'role_employee' };
                    return _Chip(label: tr(context, key), selected: state.roleFilter == r, onTap: () => state.setRoleFilter(r));
                  }),
                ]),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: employees.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 48, color: AppColors.neutral300),
                  const SizedBox(height: AppSpacing.md),
                  Text(tr(context, 'emp_empty'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ]))
              : ListView.separated(
                  padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
                  itemCount: employees.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _EmployeeRow(employee: employees[i]),
                ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
    child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap(),
      selectedColor: AppColors.primarySurface, checkmarkColor: AppColors.primary,
      side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary)),
  );
}

class _EmployeeRow extends StatelessWidget {
  final Employee employee;
  const _EmployeeRow({required this.employee});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/employees/${employee.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20, backgroundColor: AppColors.primarySurface,
              child: Text(employee.name.isNotEmpty ? employee.name[0].toUpperCase() : '?',
                  style: AppTypography.labelLarge.copyWith(color: AppColors.primary)),
            ),
            const SizedBox(width: AppSpacing.md),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(employee.name, style: AppTypography.labelLarge),
              const SizedBox(height: 2),
              Text(employee.email, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            // Badges
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                RoleBadge(role: employee.role),
                const SizedBox(width: 6),
                AiAccessBadge(access: employee.aiAccess),
              ]),
              const SizedBox(height: 4),
              EmpStatusBadge(status: employee.status),
            ]),
          ],
        ),
      ),
    );
  }
}
