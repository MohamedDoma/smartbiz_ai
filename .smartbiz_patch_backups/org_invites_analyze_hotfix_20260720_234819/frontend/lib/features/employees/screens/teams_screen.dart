// SmartBiz AI — Teams management screen (backend-backed).
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

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<OrgState>();
    if (!state.initialized && !state.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.loadAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrgState>();
    final isMobile = Responsive.isMobile(context);

    if (!state.teamsEnabled) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const Icon(
                  Icons.groups_outlined,
                  size: 56,
                  color: AppColors.neutral300,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  tr(context, 'org_teams_disabled'),
                  style: AppTypography.headingSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr(context, 'org_teams_disabled_hint'),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.neutral400,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: () => context.go('/employees/organization'),
                  icon: const Icon(Icons.settings, size: 16),
                  label: Text(tr(context, 'org_change_mode')),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.go('/employees/organization'),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      tr(context, 'org_teams'),
                      style: AppTypography.headingLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: state.departments.isEmpty
                        ? null
                        : () => _showCreateDialog(context, state),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(tr(context, 'org_add_team')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Loading state
              if (state.loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xxl),
                    child: CircularProgressIndicator(),
                  ),
                ),

              // Error state
              if (state.error != null && !state.loading)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.base),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 32,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        state.error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        onPressed: () => state.loadAll(),
                        child: Text(tr(context, 'gen_retry')),
                      ),
                    ],
                  ),
                ),

              // Empty state
              if (!state.loading && state.error == null && state.teams.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.groups_outlined,
                        size: 48,
                        color: AppColors.neutral300,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        tr(context, 'org_no_teams'),
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

              // Teams grouped by department
              if (!state.loading &&
                  state.error == null &&
                  state.teams.isNotEmpty)
                ...state.departments.map((dept) {
                  final deptTeams = state.teamsForDept(dept.id);
                  if (deptTeams.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.business,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dept.name,
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      ...deptTeams.map(
                        (t) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: _TeamCard(team: t, dept: dept, state: state),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  );
                }),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog(BuildContext context, OrgState state) {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    String? selectedDept = state.departments.isNotEmpty
        ? state.departments.first.id
        : null;
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(tr(context, 'org_add_team')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedDept,
                decoration: InputDecoration(
                  labelText: tr(context, 'org_department'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
                items: state.departments
                    .map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                    )
                    .toList(),
                onChanged: (v) => setD(() => selectedDept = v),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameC,
                decoration: InputDecoration(
                  labelText: tr(context, 'org_team_name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: descC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr(context, 'cr_description'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(tr(context, 'stk_cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameC.text.trim().isEmpty || selectedDept == null)
                        return;
                      setD(() => saving = true);
                      final err = await state.addTeam(
                        departmentId: selectedDept!,
                        name: nameC.text.trim(),
                        description: descC.text.trim().isNotEmpty
                            ? descC.text.trim()
                            : null,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (err != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(err),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr(context, 'org_team_created')),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(tr(context, 'perm_create')),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Team team;
  final Department dept;
  final OrgState state;
  const _TeamCard({
    required this.team,
    required this.dept,
    required this.state,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.groups,
                size: 18,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: AppTypography.labelLarge),
                  if (team.description != null && team.description!.isNotEmpty)
                    Text(
                      team.description!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16),
                      const SizedBox(width: 8),
                      Text(tr(context, 'org_edit_team')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text(
                        tr(context, 'cr_delete'),
                        style: TextStyle(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        const Divider(height: AppSpacing.lg),
        Row(
          children: [
            _ChipInfo(
              icon: Icons.people,
              label: '${team.memberCount} ${tr(context, 'org_members')}',
              color: AppColors.info,
            ),
            const SizedBox(width: AppSpacing.sm),
            if (team.manager != null)
              _ChipInfo(
                icon: Icons.star,
                label: team.manager!.fullName,
                color: AppColors.warning,
              )
            else
              _ChipInfo(
                icon: Icons.person_off,
                label: tr(context, 'org_no_leader'),
                color: AppColors.neutral400,
              ),
          ],
        ),
      ],
    ),
  );

  void _handleAction(BuildContext context, String action) {
    switch (action) {
      case 'edit':
        _showEditDialog(context);
      case 'delete':
        _confirmDelete(context);
    }
  }

  void _showEditDialog(BuildContext context) {
    final nameC = TextEditingController(text: team.name);
    final descC = TextEditingController(text: team.description ?? '');
    bool saving = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(tr(context, 'org_edit_team')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: InputDecoration(
                  labelText: tr(context, 'org_team_name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: descC,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr(context, 'cr_description'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(tr(context, 'stk_cancel')),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameC.text.trim().isEmpty) return;
                      setD(() => saving = true);
                      final err = await state.editTeam(
                        team.id,
                        name: nameC.text.trim(),
                        description: descC.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (err != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(err),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr(context, 'org_team_saved')),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(tr(context, 'cr_save_changes')),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr(context, 'cr_delete_title')),
        content: Text('${tr(context, 'cr_delete_confirm')} "${team.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(context, 'stk_cancel')),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await state.deleteTeam(team.id);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(err),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr(context, 'org_team_deleted')),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(tr(context, 'cr_delete')),
          ),
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ChipInfo({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
