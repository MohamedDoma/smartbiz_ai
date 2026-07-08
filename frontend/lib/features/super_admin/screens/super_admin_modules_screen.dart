// SmartBiz AI — Super Admin Module Control screen.
// Platform-wide module catalog driven by ErpModuleRegistry.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/modules/erp_module_models.dart';
import '../../../core/modules/erp_module_registry.dart';

class _ModuleDraft {
  String id;
  String name;
  String apiKey;
  ModuleCategory category;
  String maturity; // 'planned' or 'partial'
  String visibility; // 'basic','advanced','both'
  String routePlaceholder;
  String permissions;
  String featureFlags;
  bool planStarter;
  bool planPro;
  bool planEnterprise;
  bool enabled;

  _ModuleDraft({required this.id, required this.name, this.apiKey = '',
    this.category = ModuleCategory.core, this.maturity = 'planned',
    this.visibility = 'both', this.routePlaceholder = '', this.permissions = '',
    this.featureFlags = '', this.planStarter = false, this.planPro = true,
    this.planEnterprise = true, this.enabled = true});

  _ModuleDraft copy() => _ModuleDraft(
    id: '${id}_copy_${DateTime.now().millisecondsSinceEpoch}',
    name: '$name Copy', apiKey: apiKey, category: category,
    maturity: maturity, visibility: visibility,
    routePlaceholder: routePlaceholder, permissions: permissions,
    featureFlags: featureFlags, planStarter: planStarter,
    planPro: planPro, planEnterprise: planEnterprise, enabled: enabled);
}

class SuperAdminModulesScreen extends StatefulWidget {
  const SuperAdminModulesScreen({super.key});

  @override
  State<SuperAdminModulesScreen> createState() => _SuperAdminModulesScreenState();
}

class _SuperAdminModulesScreenState extends State<SuperAdminModulesScreen> {
  String _search = '';
  ModuleMaturity? _maturityFilter;
  ModuleCategory? _categoryFilter;
  final List<_ModuleDraft> _drafts = [];

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

  List<ErpModuleDefinition> get _filtered {
    return ErpModuleRegistry.all.where((m) {
      if (_maturityFilter != null && m.maturity != _maturityFilter) return false;
      if (_categoryFilter != null && m.category != _categoryFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!m.apiId.toLowerCase().contains(q) &&
            !m.labelKey.toLowerCase().contains(q) &&
            !m.category.name.toLowerCase().contains(q) &&
            !m.id.name.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int _countMat(ModuleMaturity m) => ErpModuleRegistry.all.where((d) => d.maturity == m).length;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final filtered = _filtered;
    final all = ErpModuleRegistry.all;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(context, 'sam_title'), style: AppTypography.headingLarge),
                  const SizedBox(height: 4),
                  Text(tr(context, 'sam_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ])),
                const SizedBox(width: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: () => _openDraftDialog(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr(context, 'sam_add_draft')),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                ),
              ]),
              const SizedBox(height: AppSpacing.lg),

              // ── Summary ────────────────────────────────
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SummaryChip(label: tr(context, 'sam_total'), value: '${all.length}', color: AppColors.primary, icon: Icons.extension),
                  _SummaryChip(label: tr(context, 'sam_implemented'), value: '${_countMat(ModuleMaturity.implemented)}', color: AppColors.success, icon: Icons.check_circle),
                  _SummaryChip(label: tr(context, 'sam_partial'), value: '${_countMat(ModuleMaturity.partial)}', color: AppColors.warning, icon: Icons.pending),
                  _SummaryChip(label: tr(context, 'sam_planned'), value: '${_countMat(ModuleMaturity.planned)}', color: AppColors.info, icon: Icons.schedule),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Filters ────────────────────────────────
              _buildFilters(context),
              const SizedBox(height: AppSpacing.lg),

              // ── Plan Access section ────────────────────
              _buildPlanAccess(context),
              const SizedBox(height: AppSpacing.lg),

              // ── Results count ──────────────────────────
              Text(
                '${filtered.length} ${tr(context, 'sam_modules_found')}',
                style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Module cards ───────────────────────────
              if (filtered.isEmpty)
                _buildEmpty(context)
              else
                LayoutBuilder(builder: (_, constraints) {
                  final cols = constraints.maxWidth > 700 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisExtent: 210,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _ModuleCard(mod: filtered[i]),
                  );
                }),

              // ── Drafts section ──────────────────────────
              if (_drafts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Row(children: [
                  const Icon(Icons.drafts_outlined, size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${tr(context, 'sam_drafts')} (${_drafts.length})', style: AppTypography.labelLarge),
                ]),
                const SizedBox(height: AppSpacing.sm),
                LayoutBuilder(builder: (_, constraints) {
                  final cols = constraints.maxWidth > 700 ? 2 : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols, mainAxisSpacing: AppSpacing.sm,
                      crossAxisSpacing: AppSpacing.sm, mainAxisExtent: 200,
                    ),
                    itemCount: _drafts.length,
                    itemBuilder: (_, i) => _buildDraftCard(_drafts[i]),
                  );
                }),
              ],

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filters ──────────────────────────────────────────────

  Widget _buildFilters(BuildContext context) {
    final categories = ModuleCategory.values.toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Search
      TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: tr(context, 'sam_search_hint'),
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true, fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
        ),
        style: AppTypography.bodySmall,
      ),
      const SizedBox(height: AppSpacing.sm),

      // Maturity filter
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _Chip(label: tr(context, 'sam_all'), selected: _maturityFilter == null,
            onTap: () => setState(() => _maturityFilter = null)),
          const SizedBox(width: 6),
          _Chip(label: tr(context, 'sam_implemented'), selected: _maturityFilter == ModuleMaturity.implemented,
            color: AppColors.success, onTap: () => setState(() => _maturityFilter = _maturityFilter == ModuleMaturity.implemented ? null : ModuleMaturity.implemented)),
          const SizedBox(width: 6),
          _Chip(label: tr(context, 'sam_partial'), selected: _maturityFilter == ModuleMaturity.partial,
            color: AppColors.warning, onTap: () => setState(() => _maturityFilter = _maturityFilter == ModuleMaturity.partial ? null : ModuleMaturity.partial)),
          const SizedBox(width: 6),
          _Chip(label: tr(context, 'sam_planned'), selected: _maturityFilter == ModuleMaturity.planned,
            color: AppColors.info, onTap: () => setState(() => _maturityFilter = _maturityFilter == ModuleMaturity.planned ? null : ModuleMaturity.planned)),
          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: AppColors.divider),
          const SizedBox(width: 10),
          ...categories.map((c) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: _Chip(
              label: _categoryLabel(c),
              selected: _categoryFilter == c,
              color: _categoryColor(c),
              onTap: () => setState(() => _categoryFilter = _categoryFilter == c ? null : c),
            ),
          )),
        ]),
      ),
    ]);
  }

  // ── Plan Access ──────────────────────────────────────────

  Widget _buildPlanAccess(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.card_membership, size: 17, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Text(tr(context, 'sam_plan_access'), style: AppTypography.labelLarge),
        ]),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _PlanAccessCard(planKey: 'sa_plan_starter', count: 5, total: ErpModuleRegistry.all.length, color: AppColors.info),
            _PlanAccessCard(planKey: 'sa_plan_pro', count: 10, total: ErpModuleRegistry.all.length, color: AppColors.primary),
            _PlanAccessCard(planKey: 'sa_plan_enterprise', count: 15, total: ErpModuleRegistry.all.length, color: AppColors.success),
          ],
        ),
      ]),
    );
  }

  // ── Empty ────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: [
        const Icon(Icons.search_off, size: 40, color: AppColors.neutral300),
        const SizedBox(height: AppSpacing.md),
        Text(tr(context, 'sam_no_results'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => setState(() { _search = ''; _maturityFilter = null; _categoryFilter = null; }),
          child: Text(tr(context, 'sat_clear_filters')),
        ),
      ]),
    );
  }

  // ── Helpers ──────────────────────────────────────────────

  String _categoryLabel(ModuleCategory c) => switch (c) {
    ModuleCategory.core => 'Core',
    ModuleCategory.sales => 'Sales',
    ModuleCategory.crm => 'CRM',
    ModuleCategory.inventory => 'Inventory',
    ModuleCategory.finance => 'Finance',
    ModuleCategory.people => 'People',
    ModuleCategory.projects => 'Projects',
    ModuleCategory.service => 'Service',
    ModuleCategory.restaurant => 'Restaurant',
    ModuleCategory.manufacturing => 'Manufacturing',
    ModuleCategory.logistics => 'Logistics',
    ModuleCategory.platform => 'Platform',
  };

  Color _categoryColor(ModuleCategory c) => switch (c) {
    ModuleCategory.core => AppColors.primary,
    ModuleCategory.sales => AppColors.success,
    ModuleCategory.crm => AppColors.accent,
    ModuleCategory.inventory => AppColors.warning,
    ModuleCategory.finance => AppColors.info,
    ModuleCategory.people => const Color(0xFF8B5CF6),
    ModuleCategory.projects => const Color(0xFFEC4899),
    ModuleCategory.service => const Color(0xFF14B8A6),
    ModuleCategory.restaurant => const Color(0xFFF97316),
    ModuleCategory.manufacturing => const Color(0xFF6366F1),
    ModuleCategory.logistics => const Color(0xFF0EA5E9),
    ModuleCategory.platform => AppColors.neutral500,
  };

  // ── Draft Card ──────────────────────────────────────────

  Widget _buildDraftCard(_ModuleDraft d) {
    final catColor = _categoryColor(d.category);
    final matColor = d.maturity == 'partial' ? AppColors.warning : AppColors.info;
    return Opacity(
      opacity: d.enabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 30, height: 30,
              decoration: BoxDecoration(color: catColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
              child: Icon(Icons.construction, size: 15, color: catColor)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: AppTypography.labelMedium),
              if (d.apiKey.isNotEmpty) Text(d.apiKey, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ])),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(tr(context, 'sam_draft_badge'), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.accent))),
            const SizedBox(width: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: matColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(d.maturity, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: matColor))),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              onSelected: (a) => _draftAction(d, a),
              icon: const Icon(Icons.more_vert, size: 16, color: AppColors.neutral500),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_draft_edit'))])),
                PopupMenuItem(value: 'duplicate', child: Row(children: [const Icon(Icons.copy_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_draft_dup'))])),
                PopupMenuItem(value: 'toggle', child: Row(children: [
                  Icon(d.enabled ? Icons.block : Icons.check_circle_outline, size: 16, color: d.enabled ? AppColors.warning : AppColors.success), const SizedBox(width: 8),
                  Text(d.enabled ? tr(context, 'sam_draft_disable') : tr(context, 'sam_draft_enable')),
                ])),
                PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline, size: 16, color: AppColors.error), const SizedBox(width: 8),
                  Text(tr(context, 'sam_draft_delete'), style: const TextStyle(color: AppColors.error))])),
              ],
            ),
          ]),
          const Spacer(),
          Row(children: [
            Text(_categoryLabel(d.category), style: TextStyle(fontSize: 10, color: catColor, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Text(d.visibility, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            if (d.planStarter) _planDot('S', AppColors.info),
            if (d.planPro) _planDot('P', AppColors.primary),
            if (d.planEnterprise) _planDot('E', AppColors.success),
            const Spacer(),
            if (d.featureFlags.isNotEmpty)
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.flag_outlined, size: 11, color: AppColors.textTertiary),
                const SizedBox(width: 2),
                Text(d.featureFlags.split(',').length.toString(), style: const TextStyle(fontSize: 10, color: AppColors.textTertiary)),
              ]),
          ]),
        ]),
      ),
    );
  }

  Widget _planDot(String lbl, Color c) => Container(
    margin: const EdgeInsetsDirectional.only(end: 4),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
    child: Text(lbl, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: c)),
  );

  void _draftAction(_ModuleDraft d, String action) {
    switch (action) {
      case 'edit': _openDraftDialog(d);
      case 'duplicate': setState(() => _drafts.add(d.copy())); _snack('${tr(context, 'sam_draft_dup')}: ${d.name}');
      case 'toggle': setState(() => d.enabled = !d.enabled); _snack(d.enabled ? '${d.name} enabled' : '${d.name} disabled');
      case 'delete': setState(() => _drafts.remove(d)); _snack('${tr(context, 'sam_draft_delete')}: ${d.name}');
    }
  }

  // ── Draft Dialog ──────────────────────────────────────────

  void _openDraftDialog(_ModuleDraft? existing) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?.name ?? '');
    final keyC = TextEditingController(text: existing?.apiKey ?? '');
    final routeC = TextEditingController(text: existing?.routePlaceholder ?? '');
    final permC = TextEditingController(text: existing?.permissions ?? '');
    final flagsC = TextEditingController(text: existing?.featureFlags ?? '');
    var cat = existing?.category ?? ModuleCategory.core;
    var mat = existing?.maturity ?? 'planned';
    var vis = existing?.visibility ?? 'both';
    var pS = existing?.planStarter ?? false;
    var pP = existing?.planPro ?? true;
    var pE = existing?.planEnterprise ?? true;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
      return AlertDialog(
        title: Text(isEdit ? tr(context, 'sam_draft_edit') : tr(context, 'sam_add_draft')),
        content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'sam_field_name'), border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: keyC, decoration: InputDecoration(labelText: tr(context, 'sam_field_key'), hintText: 'e.g. fleet_mgmt', border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          DropdownButtonFormField<ModuleCategory>(initialValue: cat, decoration: InputDecoration(labelText: tr(context, 'sam_field_cat'), border: const OutlineInputBorder()),
            items: ModuleCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c)))).toList(),
            onChanged: (v) => setD(() => cat = v ?? cat)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(initialValue: mat, decoration: InputDecoration(labelText: tr(context, 'sam_field_mat'), border: const OutlineInputBorder()),
              items: ['planned', 'partial'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setD(() => mat = v ?? mat))),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(initialValue: vis, decoration: InputDecoration(labelText: tr(context, 'sam_field_vis'), border: const OutlineInputBorder()),
              items: ['basic', 'advanced', 'both'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setD(() => vis = v ?? vis))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: routeC, decoration: InputDecoration(labelText: tr(context, 'sam_field_route'), hintText: '/module-path', border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: permC, decoration: InputDecoration(labelText: tr(context, 'sam_field_perms'), hintText: 'perm1, perm2', border: const OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: flagsC, decoration: InputDecoration(labelText: tr(context, 'sam_field_flags'), hintText: 'flag1, flag2', border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          Text(tr(context, 'sam_plan_access'), style: AppTypography.labelSmall),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: CheckboxListTile(dense: true, title: const Text('Starter', style: TextStyle(fontSize: 12)), value: pS, onChanged: (v) => setD(() => pS = v ?? pS))),
            Expanded(child: CheckboxListTile(dense: true, title: const Text('Professional', style: TextStyle(fontSize: 12)), value: pP, onChanged: (v) => setD(() => pP = v ?? pP))),
            Expanded(child: CheckboxListTile(dense: true, title: const Text('Enterprise', style: TextStyle(fontSize: 12)), value: pE, onChanged: (v) => setD(() => pE = v ?? pE))),
          ]),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'sap_cancel'))),
          FilledButton(onPressed: () {
            if (nameC.text.trim().isEmpty) return;
            if (isEdit) {
              setState(() {
                existing.name = nameC.text.trim();
                existing.apiKey = keyC.text.trim();
                existing.category = cat; existing.maturity = mat; existing.visibility = vis;
                existing.routePlaceholder = routeC.text.trim();
                existing.permissions = permC.text.trim();
                existing.featureFlags = flagsC.text.trim();
                existing.planStarter = pS; existing.planPro = pP; existing.planEnterprise = pE;
              });
              _snack('${tr(context, 'sam_draft_updated')}: ${existing.name}');
            } else {
              final nd = _ModuleDraft(
                id: 'draft_${DateTime.now().millisecondsSinceEpoch}',
                name: nameC.text.trim(), apiKey: keyC.text.trim(),
                category: cat, maturity: mat, visibility: vis,
                routePlaceholder: routeC.text.trim(), permissions: permC.text.trim(),
                featureFlags: flagsC.text.trim(),
                planStarter: pS, planPro: pP, planEnterprise: pE);
              setState(() => _drafts.add(nd));
              _snack('${tr(context, 'sam_draft_created')}: ${nd.name}');
            }
            Navigator.pop(ctx);
          }, child: Text(isEdit ? tr(context, 'sap_save') : tr(context, 'sap_create'))),
        ],
      );
    }));
  }
}

// ═══════════════════════════════════════════════════════════
//  Summary Chip
// ═══════════════════════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryChip({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 15, color: color)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Filter Chip
// ═══════════════════════════════════════════════════════════

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  const _Chip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: selected ? c.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? c.withValues(alpha: 0.3) : AppColors.divider)),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? c : AppColors.textSecondary)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Module Card
// ═══════════════════════════════════════════════════════════

class _ModuleCard extends StatelessWidget {
  final ErpModuleDefinition mod;
  const _ModuleCard({required this.mod});

  @override
  Widget build(BuildContext context) {
    final matColor = _maturityColor(mod.maturity);
    final catColor = _catColor(mod.category);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top: name + maturity badge + action
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: catColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(_catIcon(mod.category), size: 17, color: catColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, mod.labelKey), style: AppTypography.labelMedium),
            Text(_catLabel(mod.category), style: TextStyle(fontSize: 10, color: catColor, fontWeight: FontWeight.w500)),
          ])),
          _matBadge(context, mod.maturity, matColor),
          const SizedBox(width: 4),
          _actionMenu(context),
        ]),
        const SizedBox(height: AppSpacing.sm),

        // Visibility
        Row(children: [
          Icon(Icons.visibility_outlined, size: 12, color: AppColors.textTertiary),
          const SizedBox(width: 4),
          Text(_visLabel(mod.visibility), style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ]),
        const Spacer(),

        // Stats row
        Row(children: [
          _statChip(Icons.route, '${mod.routePaths.length}', tr(context, 'sam_routes')),
          const SizedBox(width: 8),
          _statChip(Icons.menu, '${mod.navigationItemIds.length}', tr(context, 'sam_nav')),
          const SizedBox(width: 8),
          _statChip(Icons.lock_outline, '${mod.permissionKeys.length}', tr(context, 'sam_perms')),
          const SizedBox(width: 8),
          _statChip(Icons.widgets_outlined, '${mod.supportedWidgetIds.length}', tr(context, 'sam_widgets')),
        ]),
        const SizedBox(height: 6),

        // Deps
        if (mod.dependencies.isNotEmpty)
          Row(children: [
            Icon(Icons.link, size: 11, color: AppColors.textTertiary),
            const SizedBox(width: 4),
            Expanded(child: Text(
              '${tr(context, 'sam_deps')}: ${mod.dependencies.map((d) => d.name).join(', ')}',
              style: TextStyle(fontSize: 9, color: AppColors.textTertiary),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
          ]),
      ]),
    );
  }

  Widget _matBadge(BuildContext context, ModuleMaturity m, Color c) {
    final key = switch (m) {
      ModuleMaturity.implemented => 'sam_implemented',
      ModuleMaturity.partial => 'sam_partial',
      ModuleMaturity.planned => 'sam_planned',
      ModuleMaturity.blueprintOnly => 'sam_blueprint',
      ModuleMaturity.unavailable => 'sam_unavailable',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(tr(context, key), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: c)),
    );
  }

  Widget _statChip(IconData icon, String value, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: AppColors.textTertiary),
        const SizedBox(width: 2),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _actionMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) {
        final name = tr(context, mod.labelKey);
        final msg = switch (action) {
          'view' => '${tr(context, 'sam_act_view')}: $name',
          'configure' => '${tr(context, 'sam_act_configure')}: $name',
          'flags' => '${tr(context, 'sam_act_flags')}: $name',
          'pricing' => '${tr(context, 'sam_act_pricing')}: $name',
          _ => action,
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));
      },
      icon: const Icon(Icons.more_vert, size: 16, color: AppColors.neutral500),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_act_view'))])),
        PopupMenuItem(value: 'configure', child: Row(children: [const Icon(Icons.tune, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_act_configure'))])),
        PopupMenuItem(value: 'flags', child: Row(children: [const Icon(Icons.flag_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_act_flags'))])),
        PopupMenuItem(value: 'pricing', child: Row(children: [const Icon(Icons.attach_money, size: 16), const SizedBox(width: 8), Text(tr(context, 'sam_act_pricing'))])),
      ],
    );
  }

  Color _maturityColor(ModuleMaturity m) => switch (m) {
    ModuleMaturity.implemented => AppColors.success,
    ModuleMaturity.partial => AppColors.warning,
    ModuleMaturity.planned => AppColors.info,
    ModuleMaturity.blueprintOnly => AppColors.neutral400,
    ModuleMaturity.unavailable => AppColors.error,
  };

  Color _catColor(ModuleCategory c) => switch (c) {
    ModuleCategory.core => AppColors.primary,
    ModuleCategory.sales => AppColors.success,
    ModuleCategory.crm => AppColors.accent,
    ModuleCategory.inventory => AppColors.warning,
    ModuleCategory.finance => AppColors.info,
    ModuleCategory.people => const Color(0xFF8B5CF6),
    ModuleCategory.projects => const Color(0xFFEC4899),
    ModuleCategory.service => const Color(0xFF14B8A6),
    ModuleCategory.restaurant => const Color(0xFFF97316),
    ModuleCategory.manufacturing => const Color(0xFF6366F1),
    ModuleCategory.logistics => const Color(0xFF0EA5E9),
    ModuleCategory.platform => AppColors.neutral500,
  };

  IconData _catIcon(ModuleCategory c) => switch (c) {
    ModuleCategory.core => Icons.hub,
    ModuleCategory.sales => Icons.storefront,
    ModuleCategory.crm => Icons.people,
    ModuleCategory.inventory => Icons.warehouse,
    ModuleCategory.finance => Icons.account_balance,
    ModuleCategory.people => Icons.badge,
    ModuleCategory.projects => Icons.folder,
    ModuleCategory.service => Icons.support_agent,
    ModuleCategory.restaurant => Icons.restaurant,
    ModuleCategory.manufacturing => Icons.precision_manufacturing,
    ModuleCategory.logistics => Icons.local_shipping,
    ModuleCategory.platform => Icons.settings,
  };

  String _catLabel(ModuleCategory c) => switch (c) {
    ModuleCategory.core => 'Core',
    ModuleCategory.sales => 'Sales',
    ModuleCategory.crm => 'CRM',
    ModuleCategory.inventory => 'Inventory',
    ModuleCategory.finance => 'Finance',
    ModuleCategory.people => 'People',
    ModuleCategory.projects => 'Projects',
    ModuleCategory.service => 'Service',
    ModuleCategory.restaurant => 'Restaurant',
    ModuleCategory.manufacturing => 'Manufacturing',
    ModuleCategory.logistics => 'Logistics',
    ModuleCategory.platform => 'Platform',
  };

  String _visLabel(ModuleVisibility v) => switch (v) {
    ModuleVisibility.both => 'Basic + Advanced',
    ModuleVisibility.basicOnly => 'Basic Only',
    ModuleVisibility.advancedOnly => 'Advanced Only',
    ModuleVisibility.hiddenUnlessEnabled => 'Hidden Unless Enabled',
  };
}

// ═══════════════════════════════════════════════════════════
//  Plan Access Card
// ═══════════════════════════════════════════════════════════

class _PlanAccessCard extends StatelessWidget {
  final String planKey;
  final int count;
  final int total;
  final Color color;
  const _PlanAccessCard({required this.planKey, required this.count, required this.total, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr(context, planKey), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
      const SizedBox(height: 4),
      Row(children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(' / $total', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: count / total, backgroundColor: AppColors.neutral100, color: color, minHeight: 5),
      ),
      const SizedBox(height: 2),
      Text(tr(context, 'sam_modules_allowed'), style: TextStyle(fontSize: 9, color: AppColors.textTertiary)),
    ]),
  );
}
