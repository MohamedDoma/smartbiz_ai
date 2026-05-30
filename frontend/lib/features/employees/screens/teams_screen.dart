// SmartBiz AI — Teams management screen (Phase 16.2).
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

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrgState>();
    final isMobile = Responsive.isMobile(context);

    if (!state.teamsEnabled) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
          child: Column(children: [
            const SizedBox(height: AppSpacing.xxl),
            const Icon(Icons.groups_outlined, size: 56, color: AppColors.neutral300),
            const SizedBox(height: AppSpacing.md),
            Text(tr(context, 'org_teams_disabled'), style: AppTypography.headingSmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Text(tr(context, 'org_teams_disabled_hint'), style: AppTypography.bodySmall.copyWith(color: AppColors.neutral400), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(onPressed: () => context.go('/employees/organization'), icon: const Icon(Icons.settings, size: 16), label: Text(tr(context, 'org_change_mode')),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
        )),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/employees/organization'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'org_teams'), style: AppTypography.headingLarge)),
            FilledButton.icon(onPressed: () => _showCreateDialog(context, state),
              icon: const Icon(Icons.add, size: 16), label: Text(tr(context, 'org_add_team')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
          ]),
          const SizedBox(height: AppSpacing.xl),
          if (state.teams.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
              child: Column(children: [
                const Icon(Icons.groups_outlined, size: 48, color: AppColors.neutral300),
                const SizedBox(height: AppSpacing.md),
                Text(tr(context, 'org_no_teams'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ]))
          else
            ...state.departments.map((dept) {
              final deptTeams = state.teamsForDept(dept.id);
              if (deptTeams.isEmpty) return const SizedBox.shrink();
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.business, size: 14, color: AppColors.textSecondary), const SizedBox(width: 4),
                  Text(dept.name, style: AppTypography.labelMedium.copyWith(color: AppColors.textSecondary)),
                ]),
                const SizedBox(height: AppSpacing.sm),
                ...deptTeams.map((t) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: _TeamCard(team: t, dept: dept, state: state))),
                const SizedBox(height: AppSpacing.md),
              ]);
            }),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  void _showCreateDialog(BuildContext context, OrgState state) {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    String? selectedDept = state.departments.isNotEmpty ? state.departments.first.id : null;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_add_team')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: selectedDept,
          decoration: InputDecoration(labelText: tr(context, 'org_department'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true),
          items: state.departments.map((d) => DropdownMenuItem(value: d.id, child: Text(d.name))).toList(),
          onChanged: (v) => setD(() => selectedDept = v)),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'org_team_name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: descC, maxLines: 2, decoration: InputDecoration(labelText: tr(context, 'cr_description'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          if (nameC.text.trim().isEmpty || selectedDept == null) return;
          state.addTeam(departmentId: selectedDept!, name: nameC.text.trim(), description: descC.text.trim());
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_team_created')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.accent), child: Text(tr(context, 'perm_create'))),
      ],
    )));
  }
}

class _TeamCard extends StatelessWidget {
  final Team team; final Department dept; final OrgState state;
  const _TeamCard({required this.team, required this.dept, required this.state});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.accent.withValues(alpha: 0.15))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.groups, size: 18, color: AppColors.accent)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(team.name, style: AppTypography.labelLarge),
          Text(team.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ])),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          onSelected: (action) => _handleAction(context, action),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_edit_team'))])),
            PopupMenuItem(value: 'leader', child: Row(children: [const Icon(Icons.star, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_assign_leader'))])),
            PopupMenuItem(value: 'members', child: Row(children: [const Icon(Icons.group_add, size: 16), const SizedBox(width: 8), Text(tr(context, 'org_manage_members'))])),
            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: AppColors.error), const SizedBox(width: 8), Text(tr(context, 'cr_delete'), style: TextStyle(color: AppColors.error))])),
          ],
        ),
      ]),
      const Divider(height: AppSpacing.lg),
      Row(children: [
        _ChipInfo(icon: Icons.people, label: '${team.memberCount} ${tr(context, 'org_members')}', color: AppColors.info),
        const SizedBox(width: AppSpacing.sm),
        if (team.leaderId != null)
          _ChipInfo(icon: Icons.star, label: state.empName(team.leaderId!), color: AppColors.warning)
        else
          _ChipInfo(icon: Icons.person_off, label: tr(context, 'org_no_leader'), color: AppColors.neutral400),
      ]),
      // Member list
      if (team.memberIds.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: 6, runSpacing: 4, children: team.memberIds.map((id) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 8, backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: Text(state.empName(id).isNotEmpty ? state.empName(id)[0] : '?', style: const TextStyle(fontSize: 7, color: AppColors.primary))),
            const SizedBox(width: 4),
            Text(state.empName(id), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        )).toList()),
      ],
    ]),
  );

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit': _showEditDialog(context);
      case 'leader': _showLeaderDialog(context);
      case 'members': _showMembersDialog(context);
      case 'delete': _confirmDelete(context);
    }
  }

  void _showEditDialog(BuildContext context) {
    final nameC = TextEditingController(text: team.name);
    final descC = TextEditingController(text: team.description);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_edit_team')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'org_team_name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: descC, maxLines: 2, decoration: InputDecoration(labelText: tr(context, 'cr_description'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          state.editTeam(team.id, name: nameC.text.trim(), description: descC.text.trim());
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_team_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.accent), child: Text(tr(context, 'cr_save_changes'))),
      ],
    ));
  }

  void _showLeaderDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_assign_leader')),
      content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(tr(context, 'asgn_none')), leading: const Icon(Icons.clear), selected: team.leaderId == null,
          onTap: () { state.setTeamLeader(team.id, null); Navigator.pop(ctx); }),
        ...state.allEmployeeIds.map((id) => ListTile(
          title: Text(state.empName(id)), leading: const Icon(Icons.person), selected: team.leaderId == id,
          onTap: () {
            state.setTeamLeader(team.id, id);
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_leader_assigned')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
          },
        )),
      ])),
    ));
  }

  void _showMembersDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'org_manage_members')),
      content: SizedBox(width: 300, child: Column(mainAxisSize: MainAxisSize.min, children: state.allEmployeeIds.map((id) {
        final isMember = team.memberIds.contains(id);
        return CheckboxListTile(value: isMember, title: Text(state.empName(id), style: AppTypography.labelMedium),
          onChanged: (_) { setD(() { if (isMember) { state.removeTeamMember(team.id, id); } else { state.addTeamMember(team.id, id); } }); });
      }).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'ux_close')))],
    )));
  }

  void _confirmDelete(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(tr(context, 'cr_delete_title')),
      content: Text('${tr(context, 'cr_delete_confirm')} "${team.name}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          state.deleteTeam(team.id); Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'org_team_deleted')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
        }, style: FilledButton.styleFrom(backgroundColor: AppColors.error), child: Text(tr(context, 'cr_delete'))),
      ],
    ));
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _ChipInfo({required this.icon, required this.label, required this.color});
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
