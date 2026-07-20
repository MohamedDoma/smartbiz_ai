// SmartBiz AI — Employee detail screen (backend-only).
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

class EmployeeDetailScreen extends StatefulWidget {
  final String employeeId;

  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  bool _changingStatus = false;

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
    final employee = state.getById(widget.employeeId);
    final isMobile = Responsive.isMobile(context);

    if (state.loading && !state.initialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (employee == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined,
                size: 44, color: AppColors.neutral400),
            const SizedBox(height: AppSpacing.md),
            Text(
              state.error ?? tr(context, 'emp_not_found'),
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
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
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, employee),
                const SizedBox(height: AppSpacing.xl),
                _Card(
                  children: [
                    _InfoRow(label: tr(context, 'emp_email'), value: employee.email),
                    if (employee.phoneNumber?.isNotEmpty == true)
                      _InfoRow(
                        label: tr(context, 'emp_phone'),
                        value: employee.phoneNumber!,
                      ),
                    if (employee.joinedAt != null)
                      _InfoRow(
                        label: tr(context, 'emp_joined'),
                        value: _formatDate(employee.joinedAt!),
                      ),
                    if (employee.preferredLocale != null)
                      _InfoRow(
                        label: tr(context, 'emp_lang_pref'),
                        value: employee.preferredLocale == 'ar'
                            ? tr(context, 'lang_ar')
                            : tr(context, 'lang_en'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(tr(context, 'emp_role'), style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                _Card(
                  children: [
                    if (employee.roles.isEmpty)
                      Text(
                        tr(context, 'emp_no_roles_assigned'),
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: employee.roles
                            .map(
                              (role) => DynamicRoleBadge(
                                label: role.name ?? role.roleKey ?? '-',
                                primary: role.isPrimary ||
                                    role.roleId == employee.primaryRole?.roleId,
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go('/employees/employee-roles'),
                        icon: const Icon(Icons.shield_outlined, size: 16),
                        label: Text(tr(context, 'emp_change_role')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(tr(context, 'asgn_title'), style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                _Card(
                  children: [
                    _InfoRow(
                      label: tr(context, 'emp_job_title'),
                      value: employee.jobTitle ?? '-',
                    ),
                    _InfoRow(
                      label: tr(context, 'emp_department'),
                      value: employee.department?.name ?? '-',
                    ),
                    _InfoRow(
                      label: tr(context, 'emp_team'),
                      value: employee.team?.name ?? '-',
                    ),
                    _InfoRow(
                      label: tr(context, 'emp_direct_manager'),
                      value: employee.directManager?.fullName ?? '-',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.go(
                          '/employees/${employee.membershipId}/assignment',
                        ),
                        icon: const Icon(Icons.account_tree_outlined, size: 16),
                        label: Text(tr(context, 'emp_edit_assignment')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(tr(context, 'emp_actions'),
                    style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                _Card(
                  children: [
                    if (_changingStatus)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(AppSpacing.md),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (employee.status == 'active')
                      _ActionTile(
                        icon: Icons.block,
                        label: tr(context, 'emp_suspend'),
                        color: AppColors.error,
                        onTap: () => _changeStatus(state, employee, 'suspended'),
                      )
                    else if (employee.status == 'suspended')
                      _ActionTile(
                        icon: Icons.check_circle_outline,
                        label: tr(context, 'emp_reactivate'),
                        color: AppColors.success,
                        onTap: () => _changeStatus(state, employee, 'active'),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, OrgEmployee employee) => Row(
        children: [
          IconButton(
            onPressed: () => context.go('/employees'),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.sm),
          CircleAvatar(
            radius: 23,
            backgroundColor: AppColors.primarySurface,
            child: Text(
              employee.fullName.isNotEmpty
                  ? employee.fullName[0].toUpperCase()
                  : '?',
              style: AppTypography.headingSmall
                  .copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName, style: AppTypography.headingLarge),
                if (employee.jobTitle?.isNotEmpty == true)
                  Text(
                    employee.jobTitle!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          EmployeeStatusBadge(status: employee.status),
        ],
      );

  Future<void> _changeStatus(
    EmployeesState state,
    OrgEmployee employee,
    String status,
  ) async {
    setState(() => _changingStatus = true);
    final error = await state.updateStatus(employee.membershipId, status);
    if (!mounted) return;
    setState(() => _changingStatus = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? tr(context, 'emp_status_updated')),
        backgroundColor: error == null ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _Card extends StatelessWidget {
  final List<Widget> children;

  const _Card({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: AppTypography.labelMedium,
              ),
            ),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(color: color),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: color),
            ],
          ),
        ),
      );
}
