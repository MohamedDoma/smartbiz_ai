// SmartBiz AI — Employees list screen (backend-only).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/api/org_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../employees_state.dart';
import '../widgets/employee_widgets.dart';

class EmployeesListScreen extends StatefulWidget {
  const EmployeesListScreen({super.key});

  @override
  State<EmployeesListScreen> createState() => _EmployeesListScreenState();
}

class _EmployeesListScreenState extends State<EmployeesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EmployeesState>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<EmployeesState>();
    final isMobile = Responsive.isMobile(context);
    final employees = state.filtered;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(context, 'emp_title'),
                            style: AppTypography.headingLarge),
                        Text(
                          '${state.activeCount} ${tr(context, 'emp_status_active')} · '
                          '${state.suspendedCount} ${tr(context, 'emp_status_suspended')}',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (!isMobile) ...[
                    OutlinedButton.icon(
                      onPressed: () => context.go('/employees/roles'),
                      icon: const Icon(Icons.shield_outlined, size: 16),
                      label: Text(tr(context, 'rpm_title')),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/employees/organization'),
                      icon: const Icon(Icons.account_tree_outlined, size: 16),
                      label: Text(tr(context, 'org_title')),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  FilledButton.icon(
                    onPressed: () => context.go('/employees/invite'),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: Text(tr(context, 'emp_invite')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                onChanged: state.setSearch,
                decoration: InputDecoration(
                  hintText: tr(context, 'emp_search'),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: state.loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          onPressed: state.refresh,
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: tr(context, 'inv_all'),
                      selected: state.roleKeyFilter == null &&
                          state.statusFilter == null,
                      onTap: state.clearFilters,
                    ),
                    _FilterChip(
                      label: tr(context, 'emp_status_active'),
                      selected: state.statusFilter == 'active',
                      onTap: () => state.setStatusFilter('active'),
                    ),
                    _FilterChip(
                      label: tr(context, 'emp_status_suspended'),
                      selected: state.statusFilter == 'suspended',
                      onTap: () => state.setStatusFilter('suspended'),
                    ),
                    Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: AppColors.divider,
                    ),
                    ...state.availableRoles.map(
                      (role) => _FilterChip(
                        label: role.name ?? role.roleKey ?? '-',
                        selected: state.roleKeyFilter == role.roleKey,
                        onTap: () => state.setRoleFilter(role.roleKey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _body(context, state, employees, isMobile)),
      ],
    );
  }

  Widget _body(
    BuildContext context,
    EmployeesState state,
    List<OrgEmployee> employees,
    bool isMobile,
  ) {
    if (state.loading && !state.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && !state.initialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(state.error!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: state.refresh,
              icon: const Icon(Icons.refresh),
              label: Text(tr(context, 'retry')),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: state.refresh,
      child: employees.isEmpty
          ? ListView(
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * .2),
                const Icon(Icons.people_outline,
                    size: 48, color: AppColors.neutral300),
                const SizedBox(height: AppSpacing.md),
                Text(
                  tr(context, 'emp_empty'),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            )
          : ListView.separated(
              padding: EdgeInsets.all(
                  isMobile ? AppSpacing.md : AppSpacing.base),
              itemCount: employees.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (_, index) =>
                  _EmployeeRow(employee: employees[index]),
            ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: AppColors.primarySurface,
          checkmarkColor: AppColors.primary,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.neutral300,
          ),
        ),
      );
}

class _EmployeeRow extends StatelessWidget {
  final OrgEmployee employee;

  const _EmployeeRow({required this.employee});

  @override
  Widget build(BuildContext context) {
    final primaryRole = employee.primaryRole;
    final orgParts = [
      if (employee.jobTitle?.isNotEmpty == true) employee.jobTitle!,
      if (employee.department != null) employee.department!.name,
      if (employee.team != null) employee.team!.name,
    ];

    return InkWell(
      onTap: () => context.go('/employees/${employee.membershipId}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primarySurface,
              child: Text(
                employee.fullName.isNotEmpty
                    ? employee.fullName[0].toUpperCase()
                    : '?',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName, style: AppTypography.labelLarge),
                  Text(
                    employee.email,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (orgParts.isNotEmpty)
                    Text(
                      orgParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textTertiary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (primaryRole != null)
                  DynamicRoleBadge(
                    label: primaryRole.name ?? primaryRole.roleKey ?? '-',
                    primary: true,
                  ),
                const SizedBox(height: 5),
                EmployeeStatusBadge(status: employee.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
