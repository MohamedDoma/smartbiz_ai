// SmartBiz AI — Employee organization assignment editor (real backend).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/api/org_models.dart';
import '../../../core/api/org_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/responsive.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../employees_state.dart';

class EmployeeAssignmentScreen extends StatefulWidget {
  final String employeeId;

  const EmployeeAssignmentScreen({super.key, required this.employeeId});

  @override
  State<EmployeeAssignmentScreen> createState() =>
      _EmployeeAssignmentScreenState();
}

class _EmployeeAssignmentScreenState extends State<EmployeeAssignmentScreen> {
  static const _none = '__none__';

  final _jobTitleController = TextEditingController();
  late final OrgService _service;

  List<OrgDepartment> _departments = const [];
  List<OrgTeam> _teams = const [];
  List<OrgEmployee> _employees = const [];
  OrgEmployee? _employee;
  String? _departmentId;
  String? _teamId;
  String? _managerId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = OrgService(context.read<AppState>().apiClient);
    _load();
  }

  @override
  void dispose() {
    _jobTitleController.dispose();
    super.dispose();
  }

  List<OrgTeam> get _availableTeams => _departmentId == null
      ? _teams
      : _teams.where((team) => team.departmentId == _departmentId).toList();

  List<OrgEmployee> get _availableManagers => _employees
      .where((employee) =>
          employee.membershipId != widget.employeeId &&
          employee.status == 'active')
      .toList()
    ..sort((a, b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.listDepartments(),
        _service.listTeams(),
        _service.listEmployees(),
      ]);
      final employees = results[2] as List<OrgEmployee>;
      final matches =
          employees.where((item) => item.membershipId == widget.employeeId);
      final employee = matches.isEmpty ? null : matches.first;

      if (!mounted) return;
      if (employee == null) {
        setState(() {
          _loading = false;
          _error = tr(context, 'emp_not_found');
        });
        return;
      }

      final departments = results[0] as List<OrgDepartment>;
      final teams = results[1] as List<OrgTeam>;
      var departmentId = employee.department?.id;
      if (departmentId != null &&
          !departments.any((item) => item.id == departmentId)) {
        departmentId = null;
      }
      var teamId = employee.team?.id;
      if (teamId != null &&
          !teams.any((item) =>
              item.id == teamId &&
              (departmentId == null || item.departmentId == departmentId))) {
        teamId = null;
      }
      var managerId = employee.directManager?.membershipId;
      if (managerId != null &&
          !employees.any((item) =>
              item.membershipId == managerId && item.status == 'active')) {
        managerId = null;
      }

      setState(() {
        _departments = departments;
        _teams = teams;
        _employees = employees;
        _employee = employee;
        _departmentId = departmentId;
        _teamId = teamId;
        _managerId = managerId;
        _jobTitleController.text = employee.jobTitle ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final updated = await _service.updateEmployeeAssignment(
        widget.employeeId,
        EmployeeAssignmentPayload(
          departmentId: _departmentId,
          teamId: _teamId,
          directManagerMembershipId: _managerId,
          jobTitle: _jobTitleController.text.trim(),
        ),
      );
      if (!mounted) return;

      context.read<EmployeesState>().syncEmployee(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(context, 'asgn_saved')),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      context.go('/employees/${updated.membershipId}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  String _friendlyError(Object error) {
    if (error is ValidationException) {
      final messages = error.errors.values.expand((items) => items).toList();
      return messages.isNotEmpty ? messages.first : error.message;
    }
    if (error is ApiException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/employees/${widget.employeeId}'),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        tr(context, 'emp_edit_assignment'),
                        style: AppTypography.headingLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!, onRetry: _loading ? null : _load),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xxl),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_employee != null)
                  _buildForm(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_employee!.fullName, style: AppTypography.headingSmall),
            Text(
              _employee!.email,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            TextFormField(
              controller: _jobTitleController,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_job_title'),
                prefixIcon: const Icon(Icons.work_outline),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _departmentId ?? _none,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_department'),
                prefixIcon: const Icon(Icons.account_tree_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                DropdownMenuItem(
                  value: _none,
                  child: Text(tr(context, 'asgn_none')),
                ),
                ..._departments.map(
                  (department) => DropdownMenuItem(
                    value: department.id,
                    child: Text(department.name),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        _departmentId = value == _none ? null : value;
                        if (_departmentId == null) {
                          _teamId = null;
                        } else if (_teamId != null &&
                            !_availableTeams
                                .any((team) => team.id == _teamId)) {
                          _teamId = null;
                        }
                      }),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _teamId ?? _none,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_team'),
                prefixIcon: const Icon(Icons.groups_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                DropdownMenuItem(
                  value: _none,
                  child: Text(tr(context, 'asgn_none')),
                ),
                ..._availableTeams.map(
                  (team) => DropdownMenuItem(
                    value: team.id,
                    child: Text(team.name),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                        _teamId = value == _none ? null : value;
                        if (_teamId != null) {
                          final team = _teams.firstWhere(
                            (item) => item.id == _teamId,
                          );
                          _departmentId = team.departmentId ?? _departmentId;
                        }
                      }),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _managerId ?? _none,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: tr(context, 'emp_direct_manager'),
                prefixIcon: const Icon(Icons.supervisor_account_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                DropdownMenuItem(
                  value: _none,
                  child: Text(tr(context, 'asgn_none')),
                ),
                ..._availableManagers.map(
                  (manager) => DropdownMenuItem(
                    value: manager.membershipId,
                    child: Text(manager.fullName),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(
                        () => _managerId = value == _none ? null : value,
                      ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => context.go('/employees/${widget.employeeId}'),
                    child: Text(tr(context, 'cancel')),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(tr(context, 'save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _ErrorBanner({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  onRetry?.call();
                },
                child: Text(tr(context, 'retry')),
              ),
          ],
        ),
      );
}
