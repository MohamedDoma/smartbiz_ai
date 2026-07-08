// SmartBiz AI — Commission settings screen (plans + rules).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/commission_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../commission_state.dart';

class CommissionSettingsScreen extends StatefulWidget {
  const CommissionSettingsScreen({super.key});
  @override
  State<CommissionSettingsScreen> createState() => _CommissionSettingsScreenState();
}

class _CommissionSettingsScreenState extends State<CommissionSettingsScreen> {
  String? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommissionState>().loadPlans();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'comm_settings'))),
      body: Consumer<CommissionState>(
        builder: (ctx, state, _) {
          if (state.loading && state.plans.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.plans.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.monetization_on_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'comm_no_commissions'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'comm_create_plan')),
                  onPressed: () => _showCreatePlanDialog(context, state),
                ),
              ]),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Plans
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr(context, 'comm_plans'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showCreatePlanDialog(context, state),
                ),
              ]),
              ...state.plans.map((plan) => Card(
                    color: _selectedPlanId == plan.id ? AppColors.primary.withValues(alpha: 0.08) : null,
                    child: ListTile(
                      leading: Icon(Icons.monetization_on, color: plan.isActive ? AppColors.accent : Colors.grey),
                      title: Text(plan.name),
                      subtitle: Text(
                        '${plan.rulesCount ?? 0} ${tr(context, 'comm_rules')}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: plan.isActive
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                          : const Icon(Icons.cancel, color: Colors.grey, size: 18),
                      onTap: () {
                        setState(() => _selectedPlanId = plan.id);
                        state.loadRules(planId: plan.id);
                      },
                    ),
                  )),

              if (_selectedPlanId != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                // Rules for selected plan
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(tr(context, 'comm_rules'), style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showCreateRuleDialog(context, state, _selectedPlanId!),
                  ),
                ]),
                if (state.rules.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'comm_no_commissions')))
                else
                  ...state.rules.map((rule) => _RuleCard(rule: rule)),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showCreatePlanDialog(BuildContext context, CommissionState state) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'comm_create_plan')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: tr(context, 'comm_plan_name')),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: descCtrl,
            decoration: InputDecoration(labelText: tr(context, 'doc_description')),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              await state.createPlan(CommissionPlanPayload(
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

  void _showCreateRuleDialog(BuildContext context, CommissionState state, String planId) {
    String targetType = 'assigned_employee';
    String calcType = 'percentage';
    String triggerStatus = 'won';
    final rateCtrl = TextEditingController();
    final fixedCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'comm_create_rule')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Target type
              DropdownButtonFormField<String>(
                initialValue: targetType,
                decoration: InputDecoration(labelText: tr(context, 'comm_target_type')),
                items: kTargetTypes.map((t) => DropdownMenuItem(value: t, child: Text(_targetLabel(context, t)))).toList(),
                onChanged: (v) => setDlg(() => targetType = v ?? 'assigned_employee'),
              ),
              const SizedBox(height: 8),
              // Calculation type
              DropdownButtonFormField<String>(
                initialValue: calcType,
                decoration: InputDecoration(labelText: tr(context, 'comm_calc_type')),
                items: kCalculationTypes.map((t) => DropdownMenuItem(value: t, child: Text(_calcLabel(context, t)))).toList(),
                onChanged: (v) => setDlg(() => calcType = v ?? 'percentage'),
              ),
              const SizedBox(height: 8),
              // Percentage rate / fixed amount
              if (calcType == 'percentage')
                TextField(
                  controller: rateCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'comm_percentage_rate'), suffixText: '%'),
                  keyboardType: TextInputType.number,
                )
              else
                TextField(
                  controller: fixedCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'comm_fixed_amount'), suffixText: 'LYD'),
                  keyboardType: TextInputType.number,
                ),
              const SizedBox(height: 8),
              // Trigger status
              DropdownButtonFormField<String>(
                initialValue: triggerStatus,
                decoration: InputDecoration(labelText: tr(context, 'comm_trigger_status')),
                items: kTriggerStatuses.map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase()))).toList(),
                onChanged: (v) => setDlg(() => triggerStatus = v ?? 'won'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (calcType == 'percentage' && rateCtrl.text.trim().isEmpty) return;
                if (calcType == 'fixed_amount' && fixedCtrl.text.trim().isEmpty) return;
                await state.createRule(CommissionRulePayload(
                  commissionPlanId: planId,
                  targetType: targetType,
                  calculationType: calcType,
                  percentageRate: calcType == 'percentage' ? double.tryParse(rateCtrl.text) : null,
                  fixedAmount: calcType == 'fixed_amount' ? double.tryParse(fixedCtrl.text) : null,
                  triggerStatus: triggerStatus,
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

  String _targetLabel(BuildContext context, String t) => switch (t) {
        'assigned_employee' => tr(context, 'comm_assigned_employee'),
        'direct_manager' => tr(context, 'comm_direct_manager'),
        'team_manager' => tr(context, 'comm_team_manager'),
        'department_manager' => tr(context, 'comm_department_manager'),
        _ => t,
      };

  String _calcLabel(BuildContext context, String t) => switch (t) {
        'percentage' => tr(context, 'comm_percentage'),
        'fixed_amount' => tr(context, 'comm_fixed_amount'),
        _ => t,
      };
}

class _RuleCard extends StatelessWidget {
  final CommissionRule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    final isPct = rule.calculationType == 'percentage';
    return Card(
      child: ListTile(
        leading: Icon(isPct ? Icons.percent : Icons.attach_money, color: AppColors.primary),
        title: Text(
          isPct ? '${rule.percentageRate}%' : '${rule.fixedAmount} ${rule.currency ?? "LYD"}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_targetLabel(context, rule.targetType)} · ${rule.triggerStatus.toUpperCase()}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (rule.pipeline != null)
              Text('${rule.pipeline!['name']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          ],
        ),
        trailing: rule.isActive
            ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
            : const Icon(Icons.cancel, color: Colors.grey, size: 18),
      ),
    );
  }

  String _targetLabel(BuildContext context, String t) => switch (t) {
        'assigned_employee' => tr(context, 'comm_assigned_employee'),
        'direct_manager' => tr(context, 'comm_direct_manager'),
        'team_manager' => tr(context, 'comm_team_manager'),
        'department_manager' => tr(context, 'comm_department_manager'),
        _ => t,
      };
}
