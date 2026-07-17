// SmartBiz AI — Employee Role Assignment screen (real backend).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/role_permission_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../role_permission_state.dart';

class EmployeeRolesScreen extends StatefulWidget {
  const EmployeeRolesScreen({super.key});

  @override
  State<EmployeeRolesScreen> createState() => _EmployeeRolesScreenState();
}

class _EmployeeRolesScreenState extends State<EmployeeRolesScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<RolePermissionState>();
    state.loadEmployees();
    state.loadRoles();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RolePermissionState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.info, AppColors.primary]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.people, size: 20, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'emr_title'), style: AppTypography.headingLarge),
                  Text(tr(context, 'emr_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            if (state.employeesLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.employeesError != null)
              _ErrorBox(message: state.employeesError!, onRetry: () => state.loadEmployees())
            else if (state.employees.isEmpty)
              Center(child: Text(tr(context, 'emr_no_employees'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)))
            else
              ...state.employees.map((emp) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _EmployeeCard(
                  employee: emp,
                  availableRoles: state.nonOwnerRoles,
                  onEditRoles: () => _showRoleEditor(context, emp, state),
                ),
              )),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }

  Future<void> _showRoleEditor(BuildContext context, WorkspaceEmployeeMember emp, RolePermissionState state) async {
    final selectedRoleIds = <String>{...emp.roles.map((r) => r.roleId)};
    String primaryId = emp.primaryRole?.roleId ?? (selectedRoleIds.isNotEmpty ? selectedRoleIds.first : '');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final availableRoles = state.nonOwnerRoles;
          return AlertDialog(
            title: Text('${tr(context, 'emr_edit_roles')} — ${emp.fullName ?? emp.email ?? ''}'),
            content: SizedBox(
              width: 400,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr(context, 'emr_select_roles'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 350),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableRoles.length,
                    itemBuilder: (_, i) {
                      final role = availableRoles[i];
                      final isSelected = selectedRoleIds.contains(role.id);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            selectedRoleIds.add(role.id);
                            if (selectedRoleIds.length == 1) primaryId = role.id;
                          } else {
                            selectedRoleIds.remove(role.id);
                            if (primaryId == role.id && selectedRoleIds.isNotEmpty) {
                              primaryId = selectedRoleIds.first;
                            }
                          }
                        }),
                        title: Text(role.name, style: AppTypography.labelMedium),
                        subtitle: Text(role.roleKey, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                        secondary: isSelected && selectedRoleIds.length > 1
                            ? IconButton(
                                icon: Icon(primaryId == role.id ? Icons.star : Icons.star_border,
                                    color: primaryId == role.id ? AppColors.warning : AppColors.neutral400, size: 20),
                                tooltip: tr(context, 'emr_set_primary'),
                                onPressed: () => setDialogState(() => primaryId = role.id),
                              )
                            : null,
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
                if (selectedRoleIds.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(tr(context, 'rpm_select_at_least_one'), style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
              FilledButton(
                onPressed: selectedRoleIds.isEmpty
                    ? null
                    : () async {
                        try {
                          final messenger = ScaffoldMessenger.of(context);
                          final successMsg = tr(context, 'emr_roles_updated');
                          await state.updateEmployeeRoles(
                            emp.membershipId,
                            EmployeeRolesPayload(
                              roleIds: selectedRoleIds.toList(),
                              primaryRoleId: primaryId,
                            ),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(successMsg)),
                            );
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
                            );
                          }
                        }
                      },
                child: Text(tr(context, 'save')),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final WorkspaceEmployeeMember employee;
  final List<WorkspaceRole> availableRoles;
  final VoidCallback onEditRoles;

  const _EmployeeCard({required this.employee, required this.availableRoles, required this.onEditRoles});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(
              (employee.fullName ?? employee.email ?? '?')[0].toUpperCase(),
              style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(employee.fullName ?? '', style: AppTypography.labelLarge),
            Text(employee.email ?? '', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ])),
          // Edit roles button (but not for owner)
          if (!employee.roles.any((r) => r.roleKey == 'owner'))
            TextButton.icon(
              onPressed: onEditRoles,
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: Text(tr(context, 'emr_edit_roles'), style: const TextStyle(fontSize: 12)),
            ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        // Role chips
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          ...employee.roles.map((r) => Chip(
            label: Text(r.name ?? r.roleKey ?? '', style: const TextStyle(fontSize: 11)),
            avatar: r.isPrimary ? const Icon(Icons.star, size: 14, color: AppColors.warning) : null,
            backgroundColor: r.isPrimary ? AppColors.warning.withValues(alpha: 0.1) : AppColors.primarySurface,
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          )),
        ]),
      ]),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withValues(alpha: 0.2))),
    child: Column(children: [
      Text(message, style: AppTypography.bodySmall.copyWith(color: AppColors.error)),
      const SizedBox(height: AppSpacing.sm),
      TextButton(onPressed: onRetry, child: Text(tr(context, 'retry'))),
    ]),
  );
}
