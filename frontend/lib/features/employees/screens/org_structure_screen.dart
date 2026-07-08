// SmartBiz AI — Org Structure screen.
// Shows departments, teams, and employees with org assignment.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/org_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../org_structure_state.dart';

class OrgStructureScreen extends StatefulWidget {
  const OrgStructureScreen({super.key});
  @override
  State<OrgStructureScreen> createState() => _OrgStructureScreenState();
}

class _OrgStructureScreenState extends State<OrgStructureScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OrgStructureState>().loadAll();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'org_structure')),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: tr(context, 'org_departments')),
            Tab(text: tr(context, 'org_teams')),
            Tab(text: tr(context, 'org_employees')),
          ],
        ),
      ),
      body: Consumer<OrgStructureState>(
        builder: (context, state, _) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null) {
            return Center(child: Text(state.error!, style: TextStyle(color: AppColors.error)));
          }
          return TabBarView(
            controller: _tabCtrl,
            children: [
              _DepartmentsTab(departments: state.departments),
              _TeamsTab(teams: state.teams),
              _EmployeesTab(employees: state.employees, departments: state.departments, teams: state.teams),
            ],
          );
        },
      ),
    );
  }
}

// ── Departments Tab ─────────────────────────────────────────

class _DepartmentsTab extends StatelessWidget {
  final List<OrgDepartment> departments;
  const _DepartmentsTab({required this.departments});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: departments.isEmpty
          ? Center(child: Text(tr(context, 'org_no_departments')))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: departments.length,
              itemBuilder: (ctx, i) {
                final d = departments[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: d.isActive ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                      child: Icon(Icons.business, color: d.isActive ? AppColors.primary : Colors.grey),
                    ),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${d.memberCount} ${tr(context, 'org_employees')} · ${d.teamCount} ${tr(context, 'org_teams')}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    trailing: d.manager != null
                        ? Chip(label: Text(d.manager!.fullName, style: const TextStyle(fontSize: 12)))
                        : null,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateDeptDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateDeptDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'org_create_department')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: tr(context, 'org_department_name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(labelText: tr(context, 'description')),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final state = context.read<OrgStructureState>();
              await state.createDepartment(DepartmentPayload(
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr(context, 'create')),
          ),
        ],
      ),
    );
  }
}

// ── Teams Tab ────────────────────────────────────────────────

class _TeamsTab extends StatelessWidget {
  final List<OrgTeam> teams;
  const _TeamsTab({required this.teams});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: teams.isEmpty
          ? Center(child: Text(tr(context, 'org_no_teams')))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: teams.length,
              itemBuilder: (ctx, i) {
                final t = teams[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                      child: const Icon(Icons.groups, color: AppColors.accent),
                    ),
                    title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      t.department != null ? t.department!.name : tr(context, 'org_no_department'),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                    trailing: Text('${t.memberCount}', style: TextStyle(color: Colors.grey[500])),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateTeamDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateTeamDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final state = context.read<OrgStructureState>();
    String? selectedDeptId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(tr(context, 'org_create_team')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(labelText: tr(context, 'org_team_name')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedDeptId,
                decoration: InputDecoration(labelText: tr(context, 'org_select_department')),
                items: [
                  DropdownMenuItem<String>(value: null, child: Text(tr(context, 'org_no_department'))),
                  ...state.departments.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
                ],
                onChanged: (v) => setDialogState(() => selectedDeptId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await state.createTeam(TeamPayload(
                  name: nameCtrl.text.trim(),
                  departmentId: selectedDeptId,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'create')),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Employees Tab ────────────────────────────────────────────

class _EmployeesTab extends StatelessWidget {
  final List<OrgEmployee> employees;
  final List<OrgDepartment> departments;
  final List<OrgTeam> teams;
  const _EmployeesTab({required this.employees, required this.departments, required this.teams});

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return Center(child: Text(tr(context, 'employees_empty')));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: employees.length,
      itemBuilder: (ctx, i) {
        final e = employees[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              child: Text(
                e.fullName.isNotEmpty ? e.fullName[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ),
            title: Text(e.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (e.jobTitle != null) Text(e.jobTitle!, style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                Row(children: [
                  if (e.department != null) ...[
                    Icon(Icons.business, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(e.department!.name, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    const SizedBox(width: 8),
                  ],
                  if (e.team != null) ...[
                    Icon(Icons.groups, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(e.team!.name, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ]),
                if (e.primaryRole != null)
                  Chip(
                    label: Text(e.primaryRole!.name ?? e.primaryRole!.roleKey ?? '', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            isThreeLine: true,
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: tr(context, 'org_assign_employee'),
              onPressed: () => _showAssignDialog(context, e),
            ),
          ),
        );
      },
    );
  }

  void _showAssignDialog(BuildContext context, OrgEmployee emp) {
    final jobCtrl = TextEditingController(text: emp.jobTitle ?? '');
    String? deptId = emp.department?.id;
    String? teamId = emp.team?.id;
    String? managerId = emp.directManager?.membershipId;
    final state = context.read<OrgStructureState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${tr(context, 'org_assign_employee')}: ${emp.fullName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: jobCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'org_job_title')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: deptId,
                  decoration: InputDecoration(labelText: tr(context, 'org_select_department')),
                  items: [
                    DropdownMenuItem<String>(value: null, child: Text(tr(context, 'org_no_department'))),
                    ...departments.where((d) => d.isActive).map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))),
                  ],
                  onChanged: (v) => setDialogState(() { deptId = v; teamId = null; }),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: teamId,
                  decoration: InputDecoration(labelText: tr(context, 'org_select_team')),
                  items: [
                    DropdownMenuItem<String>(value: null, child: Text(tr(context, 'org_no_team'))),
                    ...teams
                        .where((t) => t.isActive && (deptId == null || t.departmentId == deptId))
                        .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name))),
                  ],
                  onChanged: (v) => setDialogState(() => teamId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: managerId,
                  decoration: InputDecoration(labelText: tr(context, 'org_select_manager')),
                  items: [
                    DropdownMenuItem<String>(value: null, child: Text(tr(context, 'org_no_manager'))),
                    ...state.employees
                        .where((m) => m.membershipId != emp.membershipId && m.status == 'active')
                        .map((m) => DropdownMenuItem(value: m.membershipId, child: Text(m.fullName))),
                  ],
                  onChanged: (v) => setDialogState(() => managerId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                await state.assignEmployee(
                  emp.membershipId,
                  EmployeeAssignmentPayload(
                    departmentId: deptId,
                    teamId: teamId,
                    directManagerMembershipId: managerId,
                    jobTitle: jobCtrl.text.trim().isEmpty ? null : jobCtrl.text.trim(),
                  ),
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }
}
