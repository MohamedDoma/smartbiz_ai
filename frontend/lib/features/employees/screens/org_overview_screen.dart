// SmartBiz AI — Organization overview screen (Phase 16.2).
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

class OrgOverviewScreen extends StatelessWidget {
  const OrgOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrgState>();
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.account_tree, size: 20, color: Colors.white)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'org_title'), style: AppTypography.headingLarge),
              Text(tr(context, 'org_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ── Organization Mode ─────────────────────────
          Container(
            padding: const EdgeInsets.all(AppSpacing.base),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.tune, size: 18, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(tr(context, 'org_mode_title'), style: AppTypography.labelLarge),
              ]),
              const SizedBox(height: AppSpacing.md),
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: OrgMode.values.map((m) {
                final isSelected = state.mode == m;
                final label = switch (m) { OrgMode.flat => tr(context, 'org_mode_flat'), OrgMode.departments => tr(context, 'org_mode_depts'), OrgMode.departmentsTeams => tr(context, 'org_mode_depts_teams') };
                final desc = switch (m) { OrgMode.flat => tr(context, 'org_mode_flat_desc'), OrgMode.departments => tr(context, 'org_mode_depts_desc'), OrgMode.departmentsTeams => tr(context, 'org_mode_dt_desc') };
                return InkWell(
                  onTap: () => state.setMode(m),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: isMobile ? double.infinity : 200, padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isSelected ? AppColors.primary : AppColors.neutral300, width: isSelected ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: isSelected ? AppColors.primary : AppColors.neutral400),
                        const SizedBox(width: 6),
                        Text(label, style: AppTypography.labelMedium.copyWith(color: isSelected ? AppColors.primary : AppColors.textPrimary)),
                      ]),
                      const SizedBox(height: 4),
                      Text(desc, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                );
              }).toList()),
            ]),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Stats
          LayoutBuilder(builder: (ctx, c) {
            final cols = isMobile ? 2 : 4;
            final sp = AppSpacing.md;
            final w = (c.maxWidth - sp * (cols - 1)) / cols;
            return Wrap(spacing: sp, runSpacing: sp, children: [
              if (state.deptsEnabled) SizedBox(width: w, child: _StatCard(icon: Icons.business, label: tr(context, 'org_departments'), value: '${state.deptCount}', color: AppColors.primary)),
              if (state.teamsEnabled) SizedBox(width: w, child: _StatCard(icon: Icons.groups, label: tr(context, 'org_teams'), value: '${state.teamCount}', color: AppColors.accent)),
              SizedBox(width: w, child: _StatCard(icon: Icons.supervisor_account, label: tr(context, 'org_managers'), value: '${state.managerCount}', color: AppColors.success)),
              SizedBox(width: w, child: _StatCard(icon: Icons.person_off, label: tr(context, 'org_unassigned'), value: '${state.unassignedCount}', color: AppColors.warning)),
            ]);
          }),
          const SizedBox(height: AppSpacing.xl),

          // Quick actions
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            if (state.deptsEnabled) _ActionBtn(icon: Icons.business, label: tr(context, 'org_view_depts'), onTap: () => context.go('/employees/departments')),
            if (state.teamsEnabled) _ActionBtn(icon: Icons.groups, label: tr(context, 'org_view_teams'), onTap: () => context.go('/employees/teams')),
            _ActionBtn(icon: Icons.account_tree, label: tr(context, 'org_view_chart'), onTap: () => context.go('/employees/chart')),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // Departments preview
          if (state.deptsEnabled) ...[
            _SectionHeader(icon: Icons.business, title: tr(context, 'org_departments')),
            const SizedBox(height: AppSpacing.md),
            ...state.departments.map((d) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _DeptPreview(dept: d, teamCount: state.teamsForDept(d.id).length, orgState: state))),
            const SizedBox(height: AppSpacing.xl),
          ],

          // Org chart preview
          _SectionHeader(icon: Icons.account_tree, title: tr(context, 'org_reporting')),
          const SizedBox(height: AppSpacing.md),
          _OrgChartPreview(tree: state.buildOrgTree(), state: state),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final String label; final String value; final Color color;
  const _StatCard({required this.icon, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: color)),
      const SizedBox(height: AppSpacing.md),
      Text(value, style: AppTypography.headingLarge.copyWith(fontSize: 22)),
      const SizedBox(height: 2),
      Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 16), label: Text(label),
    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)));
}

class _SectionHeader extends StatelessWidget {
  final IconData icon; final String title;
  const _SectionHeader({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: AppColors.accent), const SizedBox(width: AppSpacing.sm),
    Text(title, style: AppTypography.headingSmall),
  ]);
}

class _DeptPreview extends StatelessWidget {
  final Department dept; final int teamCount; final OrgState orgState;
  const _DeptPreview({required this.dept, required this.teamCount, required this.orgState});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
    child: Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.business, size: 16, color: AppColors.primary)),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dept.name, style: AppTypography.labelLarge),
        Text(dept.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        Text('$teamCount ${tr(context, 'org_teams')}', style: AppTypography.caption.copyWith(color: AppColors.accent)),
        if (dept.managerId != null) Text(orgState.empName(dept.managerId!), style: AppTypography.caption.copyWith(color: AppColors.success)),
      ]),
    ]),
  );
}

class _OrgChartPreview extends StatelessWidget {
  final OrgNode tree; final OrgState state;
  const _OrgChartPreview({required this.tree, required this.state});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [_OrgNodeTile(node: tree, depth: 0, state: state)]),
  );
}

class _OrgNodeTile extends StatelessWidget {
  final OrgNode node; final int depth; final OrgState state;
  const _OrgNodeTile({required this.node, required this.depth, required this.state});
  Color get _color => depth == 0 ? AppColors.primary : depth == 1 ? AppColors.accent : AppColors.info;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
    Padding(padding: EdgeInsetsDirectional.only(start: depth * 24.0),
      child: Row(children: [
        if (depth > 0) ...[Icon(Icons.subdirectory_arrow_right, size: 14, color: AppColors.neutral400), const SizedBox(width: 4)],
        CircleAvatar(radius: 14, backgroundColor: _color.withValues(alpha: 0.1),
          child: Text(node.name.isNotEmpty ? node.name[0] : '?', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(node.name, style: AppTypography.labelMedium),
            if (node.badge != null) ...[
              const SizedBox(width: 4),
              Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(tr(context, node.badge!), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: AppColors.warning))),
            ],
          ]),
          Row(children: [
            Text(state.roleLabel(node.role), style: AppTypography.caption.copyWith(color: _color)),
            if (node.title != null) ...[Text(' · ', style: AppTypography.caption.copyWith(color: AppColors.neutral400)), Text(node.title!, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))],
          ]),
        ])),
      ]),
    ),
    ...node.children.map((c) => Padding(padding: const EdgeInsets.only(top: 6), child: _OrgNodeTile(node: c, depth: depth + 1, state: state))),
  ]);
}
