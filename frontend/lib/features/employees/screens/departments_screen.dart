// SmartBiz AI — Departments management screen (Phase 16.2).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../org_state.dart';
import '../models/org_models.dart';

class DepartmentsScreen extends StatelessWidget {
  const DepartmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrgState>();
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/employees/organization'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'org_departments'), style: AppTypography.headingLarge)),
            FilledButton.icon(onPressed: () => _showCreateDialog(context, state),
              icon: const Icon(Icons.add, size: 16), label: Text(tr(context, 'org_add_dept')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
          const SizedBox(height: AppSpacing.xl),
          if (state.departments.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
              child: Column(children: [
                const Icon(Icons.business_outlined, size: 48, color: AppColors.neutral300),
                const SizedBox(height: AppSpacing.md),
                Text(tr(context, 'org_no_depts'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ]))
          else
            ...state.departments.map((d) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _DeptCard(dept: d, teams: state.teamsForDept(d.id), state: state, empCount: state.employeesInDept(d.id).length))),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  void _showCreateDialog(BuildContext context, OrgState state) {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_add_dept')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'org_dept_name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: descC, maxLines: 2, decoration: InputDecoration(labelText: tr(context, 'cr_description'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          if (nameC.text.trim().isEmpty) return;
          state.addDept(name: nameC.text.trim(), description: descC.text.trim());
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_dept_created')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.primary), child: Text(tr(context, 'perm_create'))),
      ],
    ));
  }
}

class _DeptCard extends StatelessWidget {
  final Department dept; final List<Team> teams; final OrgState state; final int empCount;
  const _DeptCard({required this.dept, required this.teams, required this.state, required this.empCount});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.business, size: 18, color: AppColors.primary)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dept.name, style: AppTypography.labelLarge),
          Text(dept.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ])),
        // Actions menu
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_edit_dept'))])),
            PopupMenuItem(value: 'manager', child: Row(children: [const Icon(Icons.supervisor_account, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_assign_mgr'))])),
            PopupMenuItem(value: 'employees', child: Row(children: [const Icon(Icons.people, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_view_emps'))])),
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: AppColors.error), const SizedBox(width: 8), Text(tr(context, 'cr_delete'), style: TextStyle(color: AppColors.error))])),
          ],
        ),
      ]),
      const Divider(height: AppSpacing.lg),
      // Stats row
      Row(children: [
        _InfoChip(icon: Icons.groups, label: '${teams.length} ${tr(context, 'org_teams')}', color: AppColors.accent),
        const SizedBox(width: AppSpacing.sm),
        _InfoChip(icon: Icons.people, label: '$empCount ${tr(context, 'org_members')}', color: AppColors.info),
        const SizedBox(width: AppSpacing.sm),
        if (dept.managerId != null)
          _InfoChip(icon: Icons.supervisor_account, label: state.empName(dept.managerId!), color: AppColors.success)
        else
          _InfoChip(icon: Icons.person_off, label: tr(context, 'org_no_manager'), color: AppColors.warning),
      ]),
      // Team subtree
      if (teams.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        ...teams.map((t) => Padding(padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            const SizedBox(width: AppSpacing.xl),
            Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.neutral400), const SizedBox(width: 4),
            Icon(Icons.groups_2, size: 14, color: AppColors.accent), const SizedBox(width: 4),
            Text(t.name, style: AppTypography.bodySmall),
            Text(' (${t.memberCount})', style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          ]),
        )),
      ],
    ]),
  );

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit': _showEditDialog(context);
      case 'manager': _showManagerDialog(context);
      case 'employees': _showEmployeesDialog(context);
      case 'delete': _confirmDelete(context);
    }
  }

  void _showEditDialog(BuildContext context) {
    final nameC = TextEditingController(text: dept.name);
    final descC = TextEditingController(text: dept.description);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_edit_dept')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'org_dept_name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: descC, maxLines: 2, decoration: InputDecoration(labelText: tr(context, 'cr_description'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          state.editDept(dept.id, name: nameC.text.trim(), description: descC.text.trim());
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_dept_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.primary), child: Text(tr(context, 'cr_save_changes'))),
      ],
    ));
  }

  void _showManagerDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_assign_mgr')),
      content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(tr(context, 'asgn_none')), leading: const Icon(Icons.clear), selected: dept.managerId == null,
          onTap: () { state.setDeptManager(dept.id, null); Navigator.pop(ctx); }),
        ...state.allEmployeeIds.map((id) => ListTile(
          title: Text(state.empName(id)), leading: const Icon(Icons.person),
          selected: dept.managerId == id,
          onTap: () {
            state.setDeptManager(dept.id, id);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_mgr_assigned')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
          },
        )),
      ])),
    ));
  }

  void _showEmployeesDialog(BuildContext context) {
    final empIds = state.employeesInDept(dept.id);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('${dept.name} — ${tr(context, 'org_members')}'),
      content: SizedBox(width: 300, child: empIds.isEmpty
        ? Text(tr(context, 'asgn_none'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))
        : Column(mainAxisSize: MainAxisSize.min, children: empIds.map((id) => ListTile(
            leading: CircleAvatar(radius: 14, backgroundColor: AppColors.primarySurface,
              child: Text(state.empName(id).isNotEmpty ? state.empName(id)[0] : '?', style: const TextStyle(fontSize: 11, color: AppColors.primary))),
            title: Text(state.empName(id), style: AppTypography.labelMedium),
            subtitle: Text(state.roleLabel(state.getAssignment(id)?.primaryRoleId ?? ''), style: AppTypography.caption),
          )).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'ux_close')))],
    ));
  }

  void _confirmDelete(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'cr_delete_title')),
      content: Text('${tr(context, 'cr_delete_confirm')} "${dept.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          state.deleteDept(dept.id); Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_dept_deleted')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: Text(tr(context, 'cr_delete'))),
      ],
    ));
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color), const SizedBox(width: 4),
      Flexible(child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color), overflow: TextOverflow.ellipsis)),
    ]),
  );
}
