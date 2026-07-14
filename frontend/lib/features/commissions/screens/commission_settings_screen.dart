// SmartBiz AI — Commission settings screen (plans + rules).
// Gated by commissions.settings.view (read) and commissions.settings.manage (write).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/api/commission_models.dart';
import '../../../core/api/commission_service.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/modules/blueprint_navigation_controller.dart';
import '../../../core/state/app_state.dart';
import '../commission_state.dart';

class CommissionSettingsScreen extends StatefulWidget {
  const CommissionSettingsScreen({super.key});
  @override
  State<CommissionSettingsScreen> createState() => _CommissionSettingsScreenState();
}

class _CommissionSettingsScreenState extends State<CommissionSettingsScreen> {
  String? _selectedPlanId;
  bool _busy = false;

  // ── Permission helpers ────────────────────────────────────

  Set<String> _perms(BuildContext context) =>
      context.read<BlueprintNavigationController>().effectivePermissions;

  bool _canView(BuildContext context) =>
      _perms(context).contains('commissions.settings.view');

  bool _canManage(BuildContext context) =>
      _perms(context).contains('commissions.settings.manage');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_canView(context)) {
        if (mounted) GoRouter.of(context).go('/commissions');
        return;
      }
      context.read<CommissionState>().loadPlans();
    });
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr(context, key)), duration: const Duration(seconds: 2)),
    );
  }

  void _snackText(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_canView(context)) {
      return Scaffold(
        appBar: AppBar(title: Text(tr(context, 'comm_settings'))),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(tr(context, 'comm_settings_forbidden'),
              style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ])),
      );
    }

    final canManage = _canManage(context);

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'comm_settings'))),
      body: Consumer<CommissionState>(builder: (ctx, state, _) {
        if (state.loading && state.plans.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.plans.isEmpty) {
          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.monetization_on_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(tr(context, 'comm_no_commissions'),
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            if (canManage) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr(context, 'comm_create_plan')),
                onPressed: () => _showCreatePlanDialog(state),
              ),
            ],
          ]));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          // Read-only banner
          if (!canManage)
            _readOnlyBanner(),

          // Plans header
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(tr(context, 'comm_plans'), style: Theme.of(context).textTheme.titleMedium),
            if (canManage)
              IconButton(icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showCreatePlanDialog(state)),
          ]),

          // Plan cards
          ...state.plans.map((plan) => _buildPlanCard(plan, state, canManage)),

          // Rules section
          if (_selectedPlanId != null) ...[
            const SizedBox(height: 24),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(tr(context, 'comm_rules'), style: Theme.of(context).textTheme.titleMedium),
              if (canManage)
                IconButton(icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showCreateRuleDialog(state, _selectedPlanId!)),
            ]),
            if (state.rules.isEmpty)
              Padding(padding: const EdgeInsets.all(16),
                  child: Text(tr(context, 'comm_no_rules')))
            else
              ...state.rules.map((rule) => _buildRuleCard(rule, state, canManage)),
          ],
        ]);
      }),
    );
  }

  Widget _readOnlyBanner() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.1),
      border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(children: [
      Icon(Icons.info_outline, size: 18, color: Colors.amber[800]),
      const SizedBox(width: 8),
      Expanded(child: Text(tr(context, 'comm_settings_readonly'),
          style: TextStyle(fontSize: 13, color: Colors.amber[900]))),
    ]),
  );

  // ── Plan card ─────────────────────────────────────────────

  Widget _buildPlanCard(CommissionPlan plan, CommissionState state, bool canManage) {
    final isSelected = _selectedPlanId == plan.id;
    return Card(
      color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: Icon(Icons.monetization_on,
            color: plan.isActive ? AppColors.accent : Colors.grey),
        title: Row(children: [
          Expanded(child: Text(plan.name)),
          if (!plan.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tr(context, 'comm_inactive'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
        ]),
        subtitle: Text(
          '${plan.rulesCount ?? 0} ${tr(context, 'comm_rules')}${plan.description != null ? ' · ${plan.description}' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (v) => _handlePlanAction(v, plan, state),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit',
                      child: Text(tr(context, 'comm_edit_plan'))),
                  PopupMenuItem(value: 'toggle',
                      child: Text(plan.isActive
                          ? tr(context, 'comm_deactivate_plan')
                          : tr(context, 'comm_activate_plan'))),
                  PopupMenuItem(value: 'delete',
                      child: Text(tr(context, 'comm_delete_plan'),
                          style: const TextStyle(color: Colors.red))),
                ],
              )
            : Icon(plan.isActive ? Icons.check_circle : Icons.cancel,
                color: plan.isActive ? Colors.green : Colors.grey, size: 18),
        onTap: () {
          setState(() => _selectedPlanId = plan.id);
          state.loadRules(planId: plan.id);
        },
      ),
    );
  }

  // ── Rule card ─────────────────────────────────────────────

  Widget _buildRuleCard(CommissionRule rule, CommissionState state, bool canManage) {
    final isPct = rule.calculationType == 'percentage';
    return Card(
      child: ListTile(
        leading: Icon(isPct ? Icons.percent : Icons.attach_money,
            color: rule.isActive ? AppColors.primary : Colors.grey),
        title: Row(children: [
          Text(
            isPct ? '${rule.percentageRate}%' : '${rule.fixedAmount} ${rule.currency ?? "LYD"}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (!rule.isActive) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tr(context, 'comm_inactive'),
                  style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ],
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _targetLabel(rule.targetType),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          if (rule.pipeline != null || rule.stage != null)
            Text(
              [
                if (rule.pipeline != null) rule.pipeline!['name'] as String,
                if (rule.stage != null) rule.stage!['name'] as String,
              ].join(' → '),
              style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.7)),
            ),
          if (rule.minRecordValue != null || rule.maxRecordValue != null)
            Text(
              [
                if (rule.minRecordValue != null) 'Min: ${rule.minRecordValue}',
                if (rule.maxRecordValue != null) 'Max: ${rule.maxRecordValue}',
              ].join(' · '),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
        ]),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (v) => _handleRuleAction(v, rule, state),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit',
                      child: Text(tr(context, 'comm_edit_rule'))),
                  PopupMenuItem(value: 'toggle',
                      child: Text(rule.isActive
                          ? tr(context, 'comm_deactivate_rule')
                          : tr(context, 'comm_activate_rule'))),
                  PopupMenuItem(value: 'delete',
                      child: Text(tr(context, 'comm_delete_rule'),
                          style: const TextStyle(color: Colors.red))),
                ],
              )
            : Icon(rule.isActive ? Icons.check_circle : Icons.cancel,
                color: rule.isActive ? Colors.green : Colors.grey, size: 18),
      ),
    );
  }

  // ── Action handlers ───────────────────────────────────────

  void _handlePlanAction(String action, CommissionPlan plan, CommissionState state) {
    if (!_canManage(context)) return;
    switch (action) {
      case 'edit':   _showEditPlanDialog(plan, state);
      case 'toggle': _togglePlan(plan, state);
      case 'delete': _confirmDeletePlan(plan, state);
    }
  }

  void _handleRuleAction(String action, CommissionRule rule, CommissionState state) {
    if (!_canManage(context)) return;
    switch (action) {
      case 'edit':   _showEditRuleDialog(rule, state);
      case 'toggle': _toggleRule(rule, state);
      case 'delete': _confirmDeleteRule(rule, state);
    }
  }

  // ── Plan CRUD dialogs ────────────────────────────────────

  void _showCreatePlanDialog(CommissionState state) {
    if (!_canManage(context)) return;
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'comm_create_plan')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true,
              decoration: InputDecoration(labelText: tr(context, 'comm_plan_name'))),
          const SizedBox(height: 8),
          TextField(controller: descCtrl, maxLines: 2,
              decoration: InputDecoration(labelText: tr(context, 'doc_description'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final result = await state.createPlan(CommissionPlanPayload(
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
              if (result != null) {
                _snack('comm_plan_updated');
              } else if (state.error != null) {
                _snackText(state.error!);
              }
            },
            child: Text(tr(context, 'create')),
          ),
        ],
      ),
    );
  }

  void _showEditPlanDialog(CommissionPlan plan, CommissionState state) {
    if (!_canManage(context)) return;
    final nameCtrl = TextEditingController(text: plan.name);
    final descCtrl = TextEditingController(text: plan.description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'comm_edit_plan')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, autofocus: true,
              decoration: InputDecoration(labelText: tr(context, 'comm_plan_name'))),
          const SizedBox(height: 8),
          TextField(controller: descCtrl, maxLines: 2,
              decoration: InputDecoration(labelText: tr(context, 'doc_description'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final result = await state.updatePlan(plan.id, CommissionPlanUpdatePayload(
                name: nameCtrl.text.trim(),
                description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
              if (result != null) {
                _snack('comm_plan_updated');
              } else if (state.error != null) {
                _snackText(state.error!);
              }
            },
            child: Text(tr(context, 'gen_save')),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlan(CommissionPlan plan, CommissionState state) async {
    if (!_canManage(context) || _busy) return;
    setState(() => _busy = true);
    final ok = await state.togglePlanActive(plan.id, isActive: !plan.isActive);
    if (mounted) setState(() => _busy = false);
    if (ok) {
      _snack(plan.isActive ? 'comm_plan_deactivated' : 'comm_plan_activated');
    } else if (state.error != null) {
      _snackText(state.error!);
    }
  }

  void _confirmDeletePlan(CommissionPlan plan, CommissionState state) {
    if (!_canManage(context)) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'comm_delete_plan')),
        content: Text(tr(context, 'comm_delete_plan_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_busy) return;
              setState(() => _busy = true);
              final ok = await state.deletePlan(plan.id);
              if (mounted) {
                setState(() {
                  _busy = false;
                  if (_selectedPlanId == plan.id) _selectedPlanId = null;
                });
              }
              if (ok) {
                _snack('comm_plan_deleted');
              } else if (state.error != null) {
                _snackText(state.error!);
              }
            },
            child: Text(tr(context, 'comm_delete_plan')),
          ),
        ],
      ),
    );
  }

  // ── Rule CRUD dialogs ────────────────────────────────────

  CommissionService get _commSvc => CommissionService(context.read<AppState>().apiClient);

  void _showCreateRuleDialog(CommissionState state, String planId) {
    if (!_canManage(context)) return;
    _showRuleFormDialog(
      title: tr(context, 'comm_create_rule'),
      confirmLabel: tr(context, 'create'),
      onSubmit: (data) async {
        final result = await state.createRule(CommissionRulePayload(
          commissionPlanId: planId,
          pipelineId: data['pipeline_id'] as String?,
          stageId: data['stage_id'] as String?,
          targetType: data['target_type'] as String,
          calculationType: data['calculation_type'] as String,
          percentageRate: data['percentage_rate'] as double?,
          fixedAmount: data['fixed_amount'] as double?,
          minRecordValue: data['min_record_value'] as double?,
          maxRecordValue: data['max_record_value'] as double?,
        ));
        if (result != null) { _snack('comm_rule_updated'); return true; }
        if (state.error != null) _snackText(state.error!);
        return false;
      },
    );
  }

  void _showEditRuleDialog(CommissionRule rule, CommissionState state) {
    if (!_canManage(context)) return;
    _showRuleFormDialog(
      title: tr(context, 'comm_edit_rule'),
      confirmLabel: tr(context, 'gen_save'),
      initialTargetType: rule.targetType,
      initialCalcType: rule.calculationType,
      initialRate: rule.percentageRate,
      initialFixed: rule.fixedAmount,
      initialPipelineId: rule.pipelineId,
      initialStageId: rule.stageId,
      initialMinValue: rule.minRecordValue,
      initialMaxValue: rule.maxRecordValue,
      onSubmit: (data) async {
        final result = await state.updateRule(rule.id, CommissionRuleUpdatePayload(
          pipelineId: data['pipeline_id'] as String?,
          stageId: data['stage_id'] as String?,
          targetType: data['target_type'] as String,
          calculationType: data['calculation_type'] as String,
          percentageRate: data['percentage_rate'] as double?,
          fixedAmount: data['fixed_amount'] as double?,
          minRecordValue: data['min_record_value'] as double?,
          maxRecordValue: data['max_record_value'] as double?,
        ));
        if (result != null) { _snack('comm_rule_updated'); return true; }
        if (state.error != null) _snackText(state.error!);
        return false;
      },
    );
  }

  /// Shared dialog for creating and editing rules.
  void _showRuleFormDialog({
    required String title,
    required String confirmLabel,
    required Future<bool> Function(Map<String, dynamic> data) onSubmit,
    String initialTargetType = 'assigned_employee',
    String initialCalcType = 'percentage',
    double? initialRate,
    double? initialFixed,
    String? initialPipelineId,
    String? initialStageId,
    double? initialMinValue,
    double? initialMaxValue,
  }) {
    String targetType = initialTargetType;
    String calcType = initialCalcType;
    String? selectedPipelineId = initialPipelineId;
    String? selectedStageId = initialStageId;
    final rateCtrl = TextEditingController(text: initialRate?.toString() ?? '');
    final fixedCtrl = TextEditingController(text: initialFixed?.toString() ?? '');
    final minCtrl = TextEditingController(text: initialMinValue?.toString() ?? '');
    final maxCtrl = TextEditingController(text: initialMaxValue?.toString() ?? '');
    bool submitting = false;

    // Permission-safe pipeline/stage data (single request)
    List<CommissionPipelineOption> pipelines = [];
    List<CommissionStageOption> eligibleStages = [];
    bool loadingOptions = true;
    String? optionsError;

    // Derive stages for the currently selected pipeline from the cached list
    void syncStages(StateSetter setDlg) {
      if (selectedPipelineId == null) {
        eligibleStages = [];
      } else {
        final match = pipelines.where((p) => p.id == selectedPipelineId);
        eligibleStages = match.isNotEmpty ? match.first.stages : [];
      }
      // Legacy rule with no stage: auto-select if exactly one eligible stage
      if (selectedStageId == null && eligibleStages.length == 1) {
        selectedStageId = eligibleStages.first.id;
      } else if (selectedStageId != null &&
          !eligibleStages.any((s) => s.id == selectedStageId)) {
        selectedStageId = null;
      }
      setDlg(() {});
    }

    // Load all options in one permission-safe call
    Future<void> loadOptions(StateSetter setDlg) async {
      try {
        final opts = await _commSvc.getSettingsOptions();
        pipelines = opts.pipelines;
        optionsError = pipelines.isEmpty ? 'comm_no_pipelines' : null;
        syncStages(setDlg);
      } on Exception catch (e) {
        final msg = e.toString();
        if (msg.contains('403') || msg.contains('Forbidden')) {
          optionsError = 'comm_no_permission';
        } else {
          optionsError = 'pip_load_failed';
        }
      }
      loadingOptions = false;
      setDlg(() {});
    }

    // Handle pipeline selection change (local filtering, no extra API call)
    void onPipelineChanged(String? pipelineId, StateSetter setDlg) {
      selectedPipelineId = pipelineId;
      selectedStageId = null;
      syncStages(setDlg);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        // Trigger initial options load
        if (loadingOptions && pipelines.isEmpty) {
          loadOptions(setDlg);
        }
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              // ── Pipeline selector ──
              if (loadingOptions)
                const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
              else if (optionsError != null && pipelines.isEmpty)
                Padding(padding: const EdgeInsets.all(8),
                  child: Text(tr(context, optionsError!), style: TextStyle(color: Colors.orange[700])))
              else
                DropdownButtonFormField<String>(
                  initialValue: selectedPipelineId,
                  decoration: InputDecoration(labelText: tr(context, 'comm_select_pipeline')),
                  items: pipelines.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => onPipelineChanged(v, setDlg),
                  validator: (v) => v == null ? tr(context, 'comm_pipeline_required') : null,
                ),
              const SizedBox(height: 8),
              // ── Stage selector ──
              if (selectedPipelineId != null && eligibleStages.isEmpty && !loadingOptions)
                Padding(padding: const EdgeInsets.all(8),
                  child: Text(tr(context, 'comm_no_eligible_stages'),
                    style: TextStyle(color: Colors.orange[700], fontSize: 13)))
              else if (selectedPipelineId != null && eligibleStages.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: eligibleStages.any((s) => s.id == selectedStageId) ? selectedStageId : null,
                  decoration: InputDecoration(labelText: tr(context, 'comm_select_stage')),
                  items: eligibleStages.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                  onChanged: (v) => setDlg(() => selectedStageId = v),
                  validator: (v) => v == null ? tr(context, 'comm_stage_required') : null,
                ),
              const SizedBox(height: 8),
              // Target type
              DropdownButtonFormField<String>(
                initialValue: targetType,
                decoration: InputDecoration(labelText: tr(context, 'comm_target_type')),
                items: kTargetTypes.map((t) => DropdownMenuItem(value: t, child: Text(_targetLabel(t)))).toList(),
                onChanged: (v) => setDlg(() => targetType = v ?? 'assigned_employee'),
              ),
              const SizedBox(height: 8),
              // Calculation type
              DropdownButtonFormField<String>(
                initialValue: calcType,
                decoration: InputDecoration(labelText: tr(context, 'comm_calc_type')),
                items: kCalculationTypes.map((t) => DropdownMenuItem(value: t, child: Text(_calcLabel(t)))).toList(),
                onChanged: (v) => setDlg(() => calcType = v ?? 'percentage'),
              ),
              const SizedBox(height: 8),
              // Rate / Amount
              if (calcType == 'percentage')
                TextField(controller: rateCtrl,
                    decoration: InputDecoration(
                        labelText: tr(context, 'comm_percentage_rate'), suffixText: '%'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true))
              else
                TextField(controller: fixedCtrl,
                    decoration: InputDecoration(
                        labelText: tr(context, 'comm_fixed_amount'), suffixText: 'LYD'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              // Min / Max record value
              TextField(controller: minCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'comm_min_value')),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              const SizedBox(height: 8),
              TextField(controller: maxCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'comm_max_value')),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ])),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: submitting ? null : () async {
                if (selectedPipelineId == null) { _snack('comm_pipeline_required'); return; }
                if (selectedStageId == null) { _snack('comm_stage_required'); return; }
                if (calcType == 'percentage') {
                  final rate = double.tryParse(rateCtrl.text.trim());
                  if (rate == null || rate < 0 || rate > 100) return;
                } else {
                  final amt = double.tryParse(fixedCtrl.text.trim());
                  if (amt == null || amt < 0) return;
                }
                setDlg(() => submitting = true);
                final data = <String, dynamic>{
                  'pipeline_id': selectedPipelineId,
                  'stage_id': selectedStageId,
                  'target_type': targetType,
                  'calculation_type': calcType,
                  'percentage_rate': calcType == 'percentage'
                      ? double.tryParse(rateCtrl.text.trim()) : null,
                  'fixed_amount': calcType == 'fixed_amount'
                      ? double.tryParse(fixedCtrl.text.trim()) : null,
                  'min_record_value': minCtrl.text.trim().isNotEmpty
                      ? double.tryParse(minCtrl.text.trim()) : null,
                  'max_record_value': maxCtrl.text.trim().isNotEmpty
                      ? double.tryParse(maxCtrl.text.trim()) : null,
                };
                final ok = await onSubmit(data);
                if (ctx.mounted && ok) Navigator.pop(ctx);
                if (ctx.mounted && !ok) setDlg(() => submitting = false);
              },
              child: submitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(confirmLabel),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _toggleRule(CommissionRule rule, CommissionState state) async {
    if (!_canManage(context) || _busy) return;
    setState(() => _busy = true);
    final ok = await state.toggleRuleActive(rule.id, isActive: !rule.isActive);
    if (mounted) setState(() => _busy = false);
    if (ok) {
      _snack(rule.isActive ? 'comm_rule_deactivated' : 'comm_rule_activated');
    } else if (state.error != null) {
      _snackText(state.error!);
    }
  }

  void _confirmDeleteRule(CommissionRule rule, CommissionState state) {
    if (!_canManage(context)) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'comm_delete_rule')),
        content: Text(tr(context, 'comm_delete_rule_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              if (_busy) return;
              setState(() => _busy = true);
              final ok = await state.deleteRule(rule.id);
              if (mounted) setState(() => _busy = false);
              if (ok) {
                _snack('comm_rule_deleted');
              } else if (state.error != null) {
                _snackText(state.error!);
              }
            },
            child: Text(tr(context, 'comm_delete_rule')),
          ),
        ],
      ),
    );
  }

  // ── Label helpers ─────────────────────────────────────────

  String _targetLabel(String t) => switch (t) {
    'assigned_employee' => tr(context, 'comm_assigned_employee'),
    'direct_manager' => tr(context, 'comm_direct_manager'),
    'team_manager' => tr(context, 'comm_team_manager'),
    'department_manager' => tr(context, 'comm_department_manager'),
    _ => t,
  };

  String _calcLabel(String t) => switch (t) {
    'percentage' => tr(context, 'comm_percentage'),
    'fixed_amount' => tr(context, 'comm_fixed_amount'),
    _ => t,
  };
}
