// SmartBiz AI — Role Management screen (real backend).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/role_permission_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../role_permission_state.dart';

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  @override
  void initState() {
    super.initState();
    final state = context.read<RolePermissionState>();
    state.loadRoles();
    state.loadCatalog();
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
                  gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.shield_outlined, size: 20, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'rpm_title'), style: AppTypography.headingLarge),
                  Text(tr(context, 'rpm_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () => _showRoleEditor(context, null),
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr(context, 'rpm_create_role')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            if (state.rolesLoading)
              const Center(child: CircularProgressIndicator())
            else if (state.rolesError != null)
              _ErrorBox(message: state.rolesError!, onRetry: () => state.loadRoles())
            else ...[
              // System roles
              _SectionLabel(label: tr(context, 'rpm_system_roles'), count: state.roles.where((r) => r.isSystem).length),
              const SizedBox(height: AppSpacing.md),
              ...state.roles.where((r) => r.isSystem).map((r) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RoleCard(
                  role: r,
                  onEdit: r.isOwner ? null : () => _showRoleEditor(context, r),
                ),
              )),
              const SizedBox(height: AppSpacing.xl),

              // Custom roles
              _SectionLabel(label: tr(context, 'rpm_custom_roles'), count: state.roles.where((r) => !r.isSystem).length),
              const SizedBox(height: AppSpacing.md),
              if (state.roles.where((r) => !r.isSystem).isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(children: [
                    const Icon(Icons.add_circle_outline, size: 40, color: AppColors.neutral400),
                    const SizedBox(height: AppSpacing.md),
                    Text(tr(context, 'rpm_no_custom'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  ]),
                )
              else
                ...state.roles.where((r) => !r.isSystem).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _RoleCard(
                    role: r,
                    onEdit: () => _showRoleEditor(context, r),
                    onDeactivate: r.isActive && r.assignedCount == 0 ? () => _deactivateRole(context, r) : null,
                  ),
                )),
            ],
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }

  Future<void> _showRoleEditor(BuildContext context, WorkspaceRole? existing) async {
    final state = context.read<RolePermissionState>();
    await showDialog(
      context: context,
      builder: (ctx) => _RoleEditorDialog(
        existing: existing,
        catalog: state.catalog,
        onSave: (payload) async {
          try {
            if (existing != null) {
              await state.updateRole(existing.id, payload);
            } else {
              await state.createRole(payload);
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(tr(context, existing != null ? 'rpm_role_updated' : 'rpm_role_created'))),
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
      ),
    );
  }

  Future<void> _deactivateRole(BuildContext context, WorkspaceRole role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'rpm_deactivate_confirm')),
        content: Text(role.name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(context, 'cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(context, 'confirm'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<RolePermissionState>().deactivateRole(role.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'rpm_role_deactivated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  Sub-widgets
// ═══════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  final String label;
  final int count;
  const _SectionLabel({required this.label, required this.count});
  @override
  Widget build(BuildContext context) => Row(children: [
    Text(label, style: AppTypography.headingSmall),
    const SizedBox(width: AppSpacing.sm),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
      child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
    ),
  ]);
}

class _RoleCard extends StatelessWidget {
  final WorkspaceRole role;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  const _RoleCard({required this.role, this.onEdit, this.onDeactivate});

  @override
  Widget build(BuildContext context) {
    final accent = role.isSystem ? AppColors.info : AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: role.isActive ? AppColors.surface : AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(role.isSystem ? Icons.shield : Icons.tune, size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(role.name, style: AppTypography.labelLarge),
            if (role.description?.isNotEmpty == true)
              Text(role.description!, style: AppTypography.caption.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          // Status badges
          if (!role.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, 'rpm_inactive'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.error)),
            ),
          if (role.isOwner)
            Container(
              margin: const EdgeInsetsDirectional.only(start: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(tr(context, 'rpm_protected'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.warning)),
            ),
        ]),
        const Divider(height: AppSpacing.lg),
        // Stats
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.sm, children: [
          _StatChip(icon: Icons.key, label: role.roleKey, color: AppColors.primary),
          _StatChip(icon: Icons.security, label: '${role.permissions.length} ${tr(context, 'rpm_perms')}', color: AppColors.accent),
          _StatChip(icon: Icons.people_outline, label: '${role.assignedCount} ${tr(context, 'rpm_assigned')}', color: AppColors.info),
        ]),
        // Actions
        if (onEdit != null || onDeactivate != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (onDeactivate != null)
              TextButton.icon(
                onPressed: onDeactivate,
                icon: const Icon(Icons.block, size: 14),
                label: Text(tr(context, 'rpm_deactivate'), style: const TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
              ),
            if (onEdit != null)
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 14),
                label: Text(tr(context, 'rpm_edit'), style: const TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
  ]);
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

// ═══════════════════════════════════════════════════════════
//  Role Editor Dialog
// ═══════════════════════════════════════════════════════════

class _RoleEditorDialog extends StatefulWidget {
  final WorkspaceRole? existing;
  final List<PermissionCategory> catalog;
  final Future<void> Function(WorkspaceRolePayload payload) onSave;

  const _RoleEditorDialog({this.existing, required this.catalog, required this.onSave});

  @override
  State<_RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<_RoleEditorDialog> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _selectedPerms = <String>{};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _descCtrl.text = widget.existing!.description ?? '';
      _selectedPerms.addAll(widget.existing!.permissions);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.base),
          child: Column(children: [
            // Title
            Row(children: [
              Icon(isEdit ? Icons.edit : Icons.add_circle, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(tr(context, isEdit ? 'rpm_edit_role' : 'rpm_create_role'), style: AppTypography.headingMedium),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: AppSpacing.md),

            // Name & Description
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'rpm_role_name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: tr(context, 'rpm_role_desc'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),

            // Permissions
            Row(children: [
              Text(tr(context, 'rpm_permissions'), style: AppTypography.labelLarge),
              const Spacer(),
              Text('${_selectedPerms.length} ${tr(context, 'rpm_selected')}',
                  style: AppTypography.caption.copyWith(color: AppColors.primary)),
            ]),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: widget.catalog.isEmpty
                  ? Center(child: Text(tr(context, 'rpm_catalog_empty')))
                  : ListView.builder(
                      itemCount: widget.catalog.length,
                      itemBuilder: (ctx, i) {
                        final cat = widget.catalog[i];
                        return _PermCategoryTile(
                          category: cat,
                          selected: _selectedPerms,
                          onChanged: (key, val) => setState(() {
                            if (val) {
                              _selectedPerms.add(key);
                            } else {
                              _selectedPerms.remove(key);
                            }
                          }),
                          onSelectAll: () => setState(() {
                            for (final p in cat.permissions) {
                              _selectedPerms.add(p.key);
                            }
                          }),
                          onClearAll: () => setState(() {
                            for (final p in cat.permissions) {
                              _selectedPerms.remove(p.key);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Actions
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr(context, 'cancel'))),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(tr(context, isEdit ? 'save' : 'rpm_create_role')),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(WorkspaceRolePayload(
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      permissions: _selectedPerms.toList(),
    ));
    if (mounted) setState(() => _saving = false);
  }
}

class _PermCategoryTile extends StatelessWidget {
  final PermissionCategory category;
  final Set<String> selected;
  final void Function(String key, bool val) onChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onClearAll;

  const _PermCategoryTile({
    required this.category,
    required this.selected,
    required this.onChanged,
    required this.onSelectAll,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final count = category.permissions.where((p) => selected.contains(p.key)).length;
    return ExpansionTile(
      leading: Icon(Icons.folder_outlined, size: 18, color: AppColors.primary),
      title: Row(children: [
        Expanded(child: Text(category.label, style: AppTypography.labelMedium)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: count > 0 ? AppColors.primary.withValues(alpha: 0.1) : AppColors.neutral200, borderRadius: BorderRadius.circular(8)),
          child: Text('$count/${category.permissions.length}', style: TextStyle(fontSize: 10, color: count > 0 ? AppColors.primary : AppColors.neutral500)),
        ),
      ]),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
          child: Row(children: [
            TextButton(onPressed: onSelectAll, child: Text(tr(context, 'rpm_select_all'), style: const TextStyle(fontSize: 11))),
            TextButton(onPressed: onClearAll, child: Text(tr(context, 'rpm_clear_all'), style: const TextStyle(fontSize: 11))),
          ]),
        ),
        ...category.permissions.map((p) => CheckboxListTile(
          value: selected.contains(p.key),
          onChanged: (v) => onChanged(p.key, v ?? false),
          title: Text(p.label, style: AppTypography.bodySmall),
          subtitle: p.description.isNotEmpty ? Text(p.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)) : null,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        )),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}
