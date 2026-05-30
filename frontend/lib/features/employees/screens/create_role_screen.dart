// SmartBiz AI — Create custom role screen with template picker + permission editor.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../models/role_models.dart';
import '../roles_state.dart';

class CreateRoleScreen extends StatefulWidget {
  const CreateRoleScreen({super.key});
  @override
  State<CreateRoleScreen> createState() => _CreateRoleScreenState();
}

class _CreateRoleScreenState extends State<CreateRoleScreen> {
  final _nameC = TextEditingController();
  final _descC = TextEditingController();
  DashboardType _dashType = DashboardType.employee;
  RoleAiAccess _aiAccess = RoleAiAccess.limited;
  late Map<AppModule, ModulePermissions> _permissions;
  int _step = 0; // 0 = template, 1 = details + permissions

  @override
  void initState() {
    super.initState();
    _permissions = {for (final m in AppModule.values) m: ModulePermissions(module: m)};
  }

  @override
  void dispose() { _nameC.dispose(); _descC.dispose(); super.dispose(); }

  void _applyTemplate(CustomRole template) {
    setState(() {
      _nameC.text = '';
      _descC.text = template.description;
      _dashType = template.dashboardType;
      _aiAccess = template.aiAccess;
      _permissions = {for (final e in template.permissions.entries) e.key: e.value.copyWith()};
      _step = 1;
    });
  }

  void _startBlank() {
    setState(() {
      _nameC.text = '';
      _descC.text = '';
      _dashType = DashboardType.employee;
      _aiAccess = RoleAiAccess.limited;
      _permissions = {for (final m in AppModule.values) m: ModulePermissions(module: m)};
      _permissions[AppModule.dashboard]!.enabled.add(PermAction.view);
      _permissions[AppModule.aiChat]!.enabled.add(PermAction.view);
      _step = 1;
    });
  }

  void _save() {
    if (_nameC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cr_name_required')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      return;
    }
    context.read<RolesState>().addRole(CustomRole(
      id: '', name: _nameC.text.trim(), description: _descC.text.trim(), type: RoleType.custom,
      dashboardType: _dashType, aiAccess: _aiAccess, permissions: _permissions,
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cr_created')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    context.go('/employees/roles');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            IconButton(onPressed: () => _step == 1 ? setState(() => _step = 0) : context.go('/employees/roles'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, _step == 0 ? 'cr_pick_template' : 'cr_create'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.lg),
          if (_step == 0) _TemplateGrid(onSelect: _applyTemplate, onBlank: _startBlank)
          else ..._buildEditor(),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  List<Widget> _buildEditor() => [
    // Name + Description
    Text(tr(context, 'cr_role_name'), style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.sm),
    TextField(controller: _nameC, decoration: InputDecoration(hintText: tr(context, 'cr_name_hint'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
    const SizedBox(height: AppSpacing.lg),
    Text(tr(context, 'cr_description'), style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.sm),
    TextField(controller: _descC, maxLines: 2, decoration: InputDecoration(hintText: tr(context, 'cr_desc_hint'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
    const SizedBox(height: AppSpacing.xl),

    // Dashboard type
    Text(tr(context, 'cr_dashboard_type'), style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.sm),
    Wrap(spacing: 8, runSpacing: 8, children: DashboardType.values.map((d) => ChoiceChip(
      label: Text(tr(context, dashTypeKey(d))), selected: _dashType == d,
      onSelected: (_) => setState(() => _dashType = d),
      selectedColor: AppColors.primarySurface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    )).toList()),
    const SizedBox(height: AppSpacing.xl),

    // AI access
    Text(tr(context, 'cr_ai_access'), style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.sm),
    Wrap(spacing: 8, runSpacing: 8, children: RoleAiAccess.values.map((a) {
      final color = switch (a) { RoleAiAccess.full => AppColors.success, RoleAiAccess.limited => AppColors.warning, RoleAiAccess.none => AppColors.neutral500 };
      return ChoiceChip(
        label: Text(tr(context, roleAiKey(a))), selected: _aiAccess == a,
        onSelected: (_) => setState(() => _aiAccess = a),
        selectedColor: color.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
    }).toList()),
    const SizedBox(height: AppSpacing.xl),

    // Permission matrix
    Text(tr(context, 'cr_permissions'), style: AppTypography.headingSmall),
    Text(tr(context, 'cr_perm_hint'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
    const SizedBox(height: AppSpacing.md),
    ...AppModule.values.map((m) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: _ModulePermCard(module: m, perms: _permissions[m]!, onChanged: () => setState(() {})))),
    const SizedBox(height: AppSpacing.lg),

    // Save
    Row(children: [
      Expanded(child: OutlinedButton(onPressed: () => setState(() => _step = 0), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        child: Text(tr(context, 'stk_cancel')))),
      const SizedBox(width: AppSpacing.md),
      Expanded(flex: 2, child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check, size: 16), label: Text(tr(context, 'cr_save_role')),
        style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
    ]),
  ];
}

// ═══════════════════════════════════════════════════════════
//  Template grid
// ═══════════════════════════════════════════════════════════
class _TemplateGrid extends StatelessWidget {
  final void Function(CustomRole) onSelect;
  final VoidCallback onBlank;
  const _TemplateGrid({required this.onSelect, required this.onBlank});

  @override
  Widget build(BuildContext context) {
    final templates = RoleTemplates.allTemplates();
    final systemTemplates = RoleTemplates.allSystem().where((r) => r.id != 'sys_owner').toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Blank
      InkWell(onTap: onBlank, borderRadius: BorderRadius.circular(14),
        child: Container(width: double.infinity, padding: const EdgeInsets.all(AppSpacing.base),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)), boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 8)]),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add, size: 20, color: AppColors.primary)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'cr_blank'), style: AppTypography.labelLarge),
              Text(tr(context, 'cr_blank_desc'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            ])),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.neutral400),
          ]),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      Text(tr(context, 'cr_from_system'), style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      ...systemTemplates.map((t) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _TemplateTile(role: t, onTap: () => onSelect(t)))),
      const SizedBox(height: AppSpacing.xl),
      Text(tr(context, 'cr_from_template'), style: AppTypography.labelLarge),
      const SizedBox(height: AppSpacing.sm),
      ...templates.map((t) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _TemplateTile(role: t, onTap: () => onSelect(t)))),
    ]);
  }
}

class _TemplateTile extends StatelessWidget {
  final CustomRole role; final VoidCallback onTap;
  const _TemplateTile({required this.role, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
    child: Container(padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.tune, size: 16, color: AppColors.accent)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(role.name, style: AppTypography.labelMedium),
          Text(role.description, style: AppTypography.caption.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Text('${role.enabledModuleCount} ${tr(context, 'cr_modules')}', style: AppTypography.caption.copyWith(color: AppColors.accent)),
        const SizedBox(width: AppSpacing.sm),
        const Icon(Icons.chevron_right, size: 16, color: AppColors.neutral400),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Module permission card (shared by Create + Detail)
// ═══════════════════════════════════════════════════════════
class _ModulePermCard extends StatelessWidget {
  final AppModule module;
  final ModulePermissions perms;
  final VoidCallback onChanged;
  const _ModulePermCard({required this.module, required this.perms, required this.onChanged});

  IconData get _icon => switch (module.iconName) {
    'dashboard_outlined' => Icons.dashboard_outlined,
    'auto_awesome' => Icons.auto_awesome,
    'lightbulb' => Icons.lightbulb_outlined,
    'people' => Icons.people,
    'receipt_long' => Icons.receipt_long,
    'inventory_2' => Icons.inventory_2,
    'warehouse' => Icons.warehouse,
    'account_balance' => Icons.account_balance,
    'bar_chart' => Icons.bar_chart,
    'badge' => Icons.badge,
    'shield' => Icons.shield,
    'settings' => Icons.settings,
    'credit_card' => Icons.credit_card,
    _ => Icons.circle,
  };

  @override
  Widget build(BuildContext context) {
    final hasAny = perms.hasAny;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: hasAny ? AppColors.primarySurface.withValues(alpha: 0.3) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasAny ? AppColors.primary.withValues(alpha: 0.2) : AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon, size: 18, color: hasAny ? AppColors.primary : AppColors.neutral500),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(tr(context, module.labelKey), style: AppTypography.labelLarge.copyWith(color: hasAny ? AppColors.primary : AppColors.textPrimary))),
          // Select all / clear
          if (perms.hasAll)
            InkWell(onTap: () { perms.clearAll(); onChanged(); }, child: Text(tr(context, 'cr_clear'), style: AppTypography.caption.copyWith(color: AppColors.error)))
          else
            InkWell(onTap: () { perms.selectAll(); onChanged(); }, child: Text(tr(context, 'cr_all'), style: AppTypography.caption.copyWith(color: AppColors.primary))),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: 6, runSpacing: 6, children: module.applicableActions.map((a) {
          final on = perms.enabled.contains(a);
          return FilterChip(
            label: Text(tr(context, permActionKey(a))),
            selected: on,
            onSelected: (_) { perms.toggle(a); onChanged(); },
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            checkmarkColor: AppColors.primary,
            side: BorderSide(color: on ? AppColors.primary : AppColors.neutral300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: on ? AppColors.primary : AppColors.textSecondary),
          );
        }).toList()),
      ]),
    );
  }
}
