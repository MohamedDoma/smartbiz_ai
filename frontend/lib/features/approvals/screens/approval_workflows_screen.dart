// SmartBiz AI — Approval Workflow Management screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/approval_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../approval_state.dart';

/// Full-featured workflow management UI for administrators.
///
/// Lists all approval workflows, supports create/edit/deactivate,
/// and displays step configuration per workflow.
///
/// When [embedded] is `true`, the screen omits its own Scaffold/AppBar
/// so it can be placed inside a parent TabBarView without nesting.
class ApprovalWorkflowsScreen extends StatefulWidget {
  final bool embedded;
  const ApprovalWorkflowsScreen({super.key, this.embedded = false});
  @override
  State<ApprovalWorkflowsScreen> createState() =>
      _ApprovalWorkflowsScreenState();
}

class _ApprovalWorkflowsScreenState extends State<ApprovalWorkflowsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApprovalState>().loadWorkflows();
    });
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody(context);
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'approval_workflows')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: tr(context, 'approval_create_workflow'),
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    return Consumer<ApprovalState>(builder: (ctx, state, _) {
      if (state.loading && state.workflows.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.error != null && !state.isForbidden) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 12),
            Text(state.error!,
                style: TextStyle(color: Colors.red[400], fontSize: 14)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr(context, 'retry')),
              onPressed: () => state.loadWorkflows(),
            ),
          ]),
        );
      }
      if (state.isForbidden) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(tr(context, 'approval_no_permission'),
                style: TextStyle(color: Colors.grey[500], fontSize: 14)),
          ]),
        );
      }
      if (state.workflows.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.route_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(tr(context, 'approval_no_workflows'),
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr(context, 'approval_create_workflow')),
              onPressed: () => _showCreateDialog(context),
            ),
          ]),
        );
      }
      return RefreshIndicator(
        onRefresh: () => state.loadWorkflows(),
        child: Column(
          children: [
            // Persistent "Add Workflow" action when embedded (no AppBar)
            if (widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.add_circle_outline, size: 18,
                          color: AppColors.primary),
                      label: Text(tr(context, 'approval_create_workflow'),
                          style: TextStyle(
                              fontSize: 13, color: AppColors.primary)),
                      onPressed: () => _showCreateDialog(context),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: state.workflows.length,
                itemBuilder: (ctx, i) =>
                    _WorkflowCard(workflow: state.workflows[i]),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _WorkflowFormDialog(),
    );
  }
}

/// Card displaying a single workflow with its steps.
class _WorkflowCard extends StatefulWidget {
  final ApprovalWorkflow workflow;
  const _WorkflowCard({required this.workflow});

  @override
  State<_WorkflowCard> createState() => _WorkflowCardState();
}

class _WorkflowCardState extends State<_WorkflowCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final wf = widget.workflow;
    final state = context.read<ApprovalState>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          // Header
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(wf.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15)),
                      ),
                      _ActiveBadge(isActive: wf.isActive),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.category, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(wf.entityType,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(width: 12),
                    Icon(Icons.key, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(wf.workflowKey,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
                  ]),
                  if (wf.description != null && wf.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(wf.description!,
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  // Steps summary
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.linear_scale, size: 14,
                        color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '${wf.steps.length} ${tr(context, 'approval_steps')}',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                  ]),
                ],
              ),
            ),
          ),
          // Expanded steps + actions
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Steps list with edit/delete
                  ...wf.steps.asMap().entries.map(
                    (entry) => _StepRow(
                      step: entry.value,
                      index: entry.key,
                      onEdit: () => _showEditStepDialog(context, entry.value),
                      onDelete: () => _confirmDeleteStep(context, entry.value),
                    ),
                  ),
                  if (wf.steps.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(tr(context, 'approval_no_steps'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ),
                  const SizedBox(height: 8),
                  // Actions row
                  Row(
                    children: [
                      // Add step button
                      TextButton.icon(
                        icon: Icon(Icons.add_circle_outline, size: 14,
                            color: AppColors.primary),
                        label: Text(tr(context, 'approval_add_step'),
                            style: TextStyle(
                                fontSize: 12, color: AppColors.primary)),
                        onPressed: () => _showAddStepDialog(context, wf),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: Icon(Icons.edit_outlined, size: 14,
                            color: Colors.grey[600]),
                        label: Text(tr(context, 'edit'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                        onPressed: () => _showEditDialog(context, wf),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        icon: Icon(
                          wf.isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          size: 14,
                          color:
                              wf.isActive ? Colors.orange : Colors.green,
                        ),
                        label: Text(
                          wf.isActive
                              ? tr(context, 'deactivate')
                              : tr(context, 'activate'),
                          style: TextStyle(
                              fontSize: 12,
                              color: wf.isActive
                                  ? Colors.orange
                                  : Colors.green),
                        ),
                        onPressed: () async {
                          if (wf.isActive) {
                            await state.deleteWorkflow(wf.id);
                          } else {
                            await state.updateWorkflow(
                              wf.id,
                              const ApprovalWorkflowUpdatePayload(
                                  isActive: true),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, ApprovalWorkflow wf) {
    showDialog(
      context: context,
      builder: (ctx) => _WorkflowFormDialog(existing: wf),
    );
  }

  void _showAddStepDialog(BuildContext context, ApprovalWorkflow wf) {
    showDialog(
      context: context,
      builder: (ctx) => _StepFormDialog(
        workflowId: wf.id,
        nextOrder: wf.steps.isEmpty ? 1 : wf.steps.last.stepOrder + 1,
      ),
    );
  }

  void _showEditStepDialog(BuildContext context, ApprovalWorkflowStep step) {
    showDialog(
      context: context,
      builder: (ctx) => _StepFormDialog(workflowId: step.workflowId, existing: step),
    );
  }

  void _confirmDeleteStep(BuildContext context, ApprovalWorkflowStep step) {
    final state = context.read<ApprovalState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'confirm_delete')),
        content: Text('${tr(context, 'approval_delete_step_confirm')}: "${step.name}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await state.deleteStep(step.id);
            },
            child: Text(tr(context, 'delete')),
          ),
        ],
      ),
    );
  }
}

/// Row for a single workflow step inside the expanded card.
class _StepRow extends StatelessWidget {
  final ApprovalWorkflowStep step;
  final int index;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _StepRow({required this.step, required this.index, this.onEdit, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: step.isActive
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: step.isActive ? AppColors.primary : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.name,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  _approverTypeLabel(context, step),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          if (!step.isActive)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tr(context, 'inactive'),
                  style:
                      const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          // Step action buttons
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit, size: 16, color: Colors.grey[500]),
              onPressed: onEdit,
              tooltip: tr(context, 'edit'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 16, color: Colors.red[300]),
              onPressed: onDelete,
              tooltip: tr(context, 'delete'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  String _approverTypeLabel(
      BuildContext context, ApprovalWorkflowStep step) {
    switch (step.approverType) {
      case 'permission':
        return '${tr(context, 'approval_requires_permission')}: ${step.approverPermissionKey ?? "—"}';
      case 'requester_manager':
        return tr(context, 'approval_requester_manager');
      case 'specific_membership':
        return tr(context, 'approval_specific_member');
      default:
        return step.approverType;
    }
  }
}

/// Active/Inactive badge.
class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? Colors.green : Colors.grey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isActive ? tr(context, 'active') : tr(context, 'inactive'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isActive ? Colors.green : Colors.grey,
        ),
      ),
    );
  }
}

/// Dialog for creating or editing a workflow.
class _WorkflowFormDialog extends StatefulWidget {
  final ApprovalWorkflow? existing;
  const _WorkflowFormDialog({this.existing});

  @override
  State<_WorkflowFormDialog> createState() => _WorkflowFormDialogState();
}

class _WorkflowFormDialogState extends State<_WorkflowFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _keyCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _entityCtrl;
  bool _isSubmitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.existing?.workflowKey ?? '');
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
    _entityCtrl =
        TextEditingController(text: widget.existing?.entityType ?? '');
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _entityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit
          ? tr(context, 'approval_edit_workflow')
          : tr(context, 'approval_create_workflow')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEdit)
                TextFormField(
                  controller: _keyCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'approval_workflow_key'),
                    hintText: 'e.g. high_commission_approval',
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? tr(context, 'field_required')
                      : null,
                ),
              if (!_isEdit) const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: tr(context, 'name')),
                validator: (v) => (v == null || v.isEmpty)
                    ? tr(context, 'field_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(
                    labelText: tr(context, 'description')),
                maxLines: 2,
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _entityCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'approval_entity_type'),
                    hintText: 'e.g. commission_entry, invoice',
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? tr(context, 'field_required')
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _isEdit ? tr(context, 'save') : tr(context, 'create')),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final state = context.read<ApprovalState>();

    if (_isEdit) {
      final result = await state.updateWorkflow(
        widget.existing!.id,
        ApprovalWorkflowUpdatePayload(
          name: _nameCtrl.text,
          description: _descCtrl.text,
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    } else {
      final result = await state.createWorkflow(
        ApprovalWorkflowPayload(
          workflowKey: _keyCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          entityType: _entityCtrl.text.trim(),
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    }

    if (mounted) setState(() => _isSubmitting = false);
  }
}

/// Dialog for adding or editing a workflow step.
class _StepFormDialog extends StatefulWidget {
  final String workflowId;
  final int? nextOrder;
  final ApprovalWorkflowStep? existing;
  const _StepFormDialog({required this.workflowId, this.nextOrder, this.existing});

  @override
  State<_StepFormDialog> createState() => _StepFormDialogState();
}

class _StepFormDialogState extends State<_StepFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _permKeyCtrl;
  late String _approverType;
  late bool _allowSelfApproval;
  late bool _isActive;
  bool _isSubmitting = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _permKeyCtrl = TextEditingController(
        text: widget.existing?.approverPermissionKey ?? '');
    _approverType = widget.existing?.approverType ?? 'permission';
    _allowSelfApproval = widget.existing?.allowSelfApproval ?? false;
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _permKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit
          ? tr(context, 'approval_edit_step')
          : tr(context, 'approval_add_step')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                    labelText: tr(context, 'name'),
                    hintText: 'e.g. Manager Review'),
                validator: (v) => (v == null || v.isEmpty)
                    ? tr(context, 'field_required')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _approverType,
                decoration: InputDecoration(
                    labelText: tr(context, 'approval_approver_type')),
                items: kApproverTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(_approverTypeLabel(t)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _approverType = v!),
              ),
              if (_approverType == 'permission') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _permKeyCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'approval_permission_key'),
                    hintText: 'e.g. commissions.approve',
                  ),
                  validator: (v) => (_approverType == 'permission' &&
                          (v == null || v.isEmpty))
                      ? tr(context, 'field_required')
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(tr(context, 'approval_allow_self_approval'),
                    style: const TextStyle(fontSize: 13)),
                value: _allowSelfApproval,
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _allowSelfApproval = v),
              ),
              if (_isEdit)
                SwitchListTile(
                  title: Text(tr(context, 'active'),
                      style: const TextStyle(fontSize: 13)),
                  value: _isActive,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: Text(tr(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEdit ? tr(context, 'save') : tr(context, 'create')),
        ),
      ],
    );
  }

  String _approverTypeLabel(String t) => switch (t) {
        'permission' => 'Permission-based',
        'requester_manager' => 'Requester\'s Manager',
        'specific_membership' => 'Specific Member',
        _ => t,
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final state = context.read<ApprovalState>();

    if (_isEdit) {
      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'approver_type': _approverType,
        'allow_self_approval': _allowSelfApproval,
        'is_active': _isActive,
      };
      if (_approverType == 'permission') {
        data['approver_permission_key'] = _permKeyCtrl.text.trim();
      }
      final result = await state.updateStep(widget.existing!.id, data);
      if (result != null && mounted) Navigator.pop(context);
    } else {
      final result = await state.addStep(
        widget.workflowId,
        ApprovalWorkflowStepPayload(
          name: _nameCtrl.text.trim(),
          approverType: _approverType,
          approverPermissionKey:
              _approverType == 'permission' ? _permKeyCtrl.text.trim() : null,
          allowSelfApproval: _allowSelfApproval,
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    }

    if (mounted) setState(() => _isSubmitting = false);
  }
}
