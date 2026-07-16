// SmartBiz AI — Approval Workflow Management screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/approval_models.dart';
import '../../../core/api/entity_field_catalog_models.dart';
import '../../../core/api/role_permission_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../employees/role_permission_state.dart';
import '../approval_state.dart';
import '../entity_field_catalog_state.dart';
import '../../../core/state/app_state.dart';

/// Shared display resolver for workspace members.
///
/// Ensures identical resolution rules across the dropdown menu items,
/// the selected-value display, and the step card. Never returns a
/// concatenated "name (role)" string.
class MemberDisplayData {
  /// The stored full name (never translated).
  final String primaryName;

  /// Locale-aware role label, or empty string when unavailable.
  final String roleName;

  const MemberDisplayData({required this.primaryName, this.roleName = ''});

  /// Resolves display data for a [WorkspaceEmployeeMember].
  ///
  /// Uses the `role_key` to look up a localized role name via the
  /// existing `bk_role_*` l10n keys (e.g. `bk_role_owner`,
  /// `bk_role_sales_manager`). Falls back to the stored role `name`
  /// for custom user-created roles that have no l10n key.
  factory MemberDisplayData.fromMember(
    BuildContext context,
    WorkspaceEmployeeMember member,
  ) {
    final name =
        member.fullName ??
        member.email ??
        tr(context, 'approval_unknown_member');
    final role = member.primaryRole;
    final roleName = _resolveRoleName(context, role);
    return MemberDisplayData(primaryName: name, roleName: roleName);
  }

  /// Resolves a localized role name from a [MemberRoleSummary].
  static String _resolveRoleName(
    BuildContext context,
    MemberRoleSummary? role,
  ) {
    if (role == null) return '';
    // Try the l10n key first (e.g. bk_role_owner, bk_role_sales_manager).
    final key = role.roleKey;
    if (key != null && key.isNotEmpty) {
      final l10nKey = 'bk_role_$key';
      final localized = tr(context, l10nKey);
      // tr() returns the key itself when no translation is found.
      if (localized != l10nKey) return localized;
    }
    // Fall back to the stored role name for custom roles.
    return role.name ?? '';
  }
}

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
      final approvalState = context.read<ApprovalState>();
      approvalState.loadWorkflows().then((_) {
        if (!mounted) return;
        // After workflows arrive, preload metadata for their entity types.
        final catState = context.read<EntityFieldCatalogState>();
        catState.loadMetadataForWorkflows(approvalState.workflows);
      });
      // Pre-load permission catalog and employees at screen level so that
      // step cards can resolve permission labels and member names without
      // waiting for a dialog to open. This fixes the F5 "Unavailable" bug.
      final rpState = context.read<RolePermissionState>();
      rpState.loadCatalog();
      rpState.loadEmployees();
      // Sync workspace ID to catalog state for cache scoping.
      final wsId = context.read<AppState>().currentWorkspace.id;
      final catState = context.read<EntityFieldCatalogState>();
      catState.setWorkspace(wsId);
      // Pre-load entity types so the create dialog opens instantly.
      catState.loadEntityTypes();
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
    return Consumer<ApprovalState>(
      builder: (ctx, state, _) {
        if (state.loading && state.workflows.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.error != null && !state.isForbidden) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: TextStyle(color: Colors.red[400], fontSize: 14),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(tr(context, 'retry')),
                  onPressed: () => state.loadWorkflows(),
                ),
              ],
            ),
          );
        }
        if (state.isForbidden) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 12),
                Text(
                  tr(context, 'approval_no_permission'),
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
              ],
            ),
          );
        }
        if (state.workflows.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.route_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'approval_no_workflows'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(tr(context, 'approval_create_workflow')),
                  onPressed: () => _showCreateDialog(context),
                ),
              ],
            ),
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
                        icon: Icon(
                          Icons.add_circle_outline,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          tr(context, 'approval_create_workflow'),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primary,
                          ),
                        ),
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
      },
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const _WorkflowFormDialog());
  }
}

/// Resolves an entity type key to a localized label.
///
/// Resolution order:
///   1. EntityFieldCatalogState descriptor → localized label.
///   2. EntityFieldCatalogState schema cache → localized label.
///   3. If still loading → localized "Loading entity type…".
///   4. If loading completed but absent → localized "Unavailable entity type".
///
/// **Never returns the raw entity_type key.**
///
/// Accepts [catState] directly so callers can use `context.watch` for
/// reactive rebuilds instead of the non-reactive `context.read`.
String _resolveEntityLabel(
  BuildContext context,
  String entityType,
  EntityFieldCatalogState catState,
) {
  final langCode = Localizations.localeOf(context).languageCode;
  // Try descriptor from entity-types list first.
  final descriptor = catState.descriptorFor(entityType);
  if (descriptor != null) return descriptor.localizedLabel(langCode);
  // Fall back to cached schema.
  final schema = catState.schemaFor(entityType);
  if (schema != null) return schema.localizedLabel(langCode);
  // Distinguish loading from genuinely unavailable.
  if (catState.entityTypesLoading || catState.isSchemaLoading(entityType)) {
    return tr(context, 'approval_entity_loading');
  }
  return tr(context, 'approval_entity_type_unavailable');
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
    // Watch EntityFieldCatalogState so the card rebuilds when
    // entity type descriptors or field schemas finish loading.
    return Consumer<EntityFieldCatalogState>(
      builder: (context, catState, _) {
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
                            child: Text(
                              wf.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          _ActiveBadge(isActive: wf.isActive),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.category,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _resolveEntityLabel(
                              context,
                              wf.entityType,
                              catState,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      if (wf.description != null &&
                          wf.description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          wf.description!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Trigger conditions summary
                      if (_hasTriggerConditions(wf)) ...[
                        const SizedBox(height: 6),
                        _TriggerConditionsSummary(
                          conditions: wf.triggerConditions!,
                          entityType: wf.entityType,
                        ),
                      ],
                      // Steps summary
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.linear_scale,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${wf.steps.length} ${tr(context, 'approval_steps')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_hasTriggerConditions(wf)) ...[
                            const SizedBox(width: 12),
                            Icon(
                              Icons.filter_alt_outlined,
                              size: 14,
                              color: Colors.deepPurple,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${_conditionCount(wf)} ${tr(context, 'approval_trigger_conditions')}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.deepPurple,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Expanded steps + actions
              if (_expanded) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Steps list with edit/delete
                      ...wf.steps.asMap().entries.map(
                        (entry) => _StepRow(
                          step: entry.value,
                          index: entry.key,
                          onEdit: () =>
                              _showEditStepDialog(context, entry.value),
                          onDelete: () =>
                              _confirmDeleteStep(context, entry.value),
                        ),
                      ),
                      if (wf.steps.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            tr(context, 'approval_no_steps'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Actions row
                      Row(
                        children: [
                          // Add step button
                          TextButton.icon(
                            icon: Icon(
                              Icons.add_circle_outline,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            label: Text(
                              tr(context, 'approval_add_step'),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                              ),
                            ),
                            onPressed: () => _showAddStepDialog(context, wf),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            label: Text(
                              tr(context, 'edit'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            onPressed: () => _showEditDialog(context, wf),
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: Icon(
                              wf.isActive
                                  ? Icons.pause_circle_outline
                                  : Icons.play_circle_outline,
                              size: 14,
                              color: wf.isActive ? Colors.orange : Colors.green,
                            ),
                            label: Text(
                              wf.isActive
                                  ? tr(context, 'deactivate')
                                  : tr(context, 'activate'),
                              style: TextStyle(
                                fontSize: 12,
                                color: wf.isActive
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ),
                            onPressed: () async {
                              if (wf.isActive) {
                                await state.deleteWorkflow(wf.id);
                              } else {
                                await state.updateWorkflow(
                                  wf.id,
                                  const ApprovalWorkflowUpdatePayload(
                                    isActive: true,
                                  ),
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
      }, // Consumer builder
    ); // Consumer
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
      builder: (ctx) =>
          _StepFormDialog(workflowId: step.workflowId, existing: step),
    );
  }

  void _confirmDeleteStep(BuildContext context, ApprovalWorkflowStep step) {
    final state = context.read<ApprovalState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'confirm_delete')),
        content: Text(
          '${tr(context, 'approval_delete_step_confirm')}: "${step.name}"',
        ),
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

  bool _hasTriggerConditions(ApprovalWorkflow wf) {
    final tc = wf.triggerConditions;
    if (tc == null) return false;
    final conds = tc['conditions'];
    return conds is List && conds.isNotEmpty;
  }

  int _conditionCount(ApprovalWorkflow wf) {
    final tc = wf.triggerConditions;
    if (tc == null) return 0;
    final conds = tc['conditions'];
    return conds is List ? conds.length : 0;
  }
}

/// Human-readable summary of trigger conditions.
///
/// When an [entityType] is provided, attempts to resolve localized
/// field labels from the [EntityFieldCatalogState] cache. Unknown
/// fields show localized "Unavailable field"; unknown operators show
/// localized "Operator no longer available". Raw keys are never displayed.
///
/// Uses `context.watch` to reactively rebuild when schema loads complete.
class _TriggerConditionsSummary extends StatelessWidget {
  final Map<String, dynamic> conditions;
  final String? entityType;
  const _TriggerConditionsSummary({required this.conditions, this.entityType});

  @override
  Widget build(BuildContext context) {
    final logic = conditions['logic'] as String? ?? 'and';
    final conds = conditions['conditions'] as List? ?? [];
    if (conds.isEmpty) return const SizedBox.shrink();

    // Watch the catalog state so the widget rebuilds when schemas load.
    final catState = context.watch<EntityFieldCatalogState>();

    // Try to resolve a cached schema for localized field labels.
    EntityFieldSchema? schema;
    bool schemaStillLoading = false;
    if (entityType != null && entityType!.isNotEmpty) {
      schema = catState.schemaFor(entityType!);
      schemaStillLoading = catState.isSchemaLoading(entityType!);
    }

    // If schema is still loading, show a loading placeholder.
    if (schema == null && schemaStillLoading) {
      return Row(
        children: [
          Icon(
            Icons.filter_alt_outlined,
            size: 13,
            color: Colors.deepPurple[300],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              tr(context, 'approval_field_loading'),
              style: TextStyle(
                fontSize: 11,
                color: Colors.deepPurple[300],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      );
    }

    final langCode = Localizations.localeOf(context).languageCode;

    final parts = <String>[];
    for (final c in conds) {
      if (c is! Map) continue;
      final fieldKey = c['field'] ?? '?';
      // Resolve localized label — NEVER display raw field key.
      final fieldLabel =
          schema?.fieldByKey(fieldKey.toString())?.localizedLabel(langCode) ??
          tr(context, 'approval_field_unavailable');
      final op = _opLabel(context, c['operator'] ?? '');
      final val = c['value']?.toString() ?? '?';
      parts.add('$fieldLabel $op $val');
    }

    final joiner = logic == 'or' ? ' OR ' : ' AND ';
    return Row(
      children: [
        Icon(
          Icons.filter_alt_outlined,
          size: 13,
          color: Colors.deepPurple[300],
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${tr(context, 'approval_trigger_summary')}: ${parts.join(joiner)}',
            style: TextStyle(fontSize: 11, color: Colors.deepPurple[400]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _opLabel(BuildContext context, String op) => switch (op) {
    'equals' => '=',
    'not_equals' => '≠',
    'greater_than' => '>',
    'greater_than_or_equal' => '≥',
    'less_than' => '<',
    'less_than_or_equal' => '≤',
    'contains' => '∋',
    'in' => '∈',
    'not_in' => '∉',
    'exists' => '∃',
    _ => tr(context, 'approval_trigger_op_unknown'),
  };
}

/// Row for a single workflow step inside the expanded card.
class _StepRow extends StatelessWidget {
  final ApprovalWorkflowStep step;
  final int index;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  const _StepRow({
    required this.step,
    required this.index,
    this.onEdit,
    this.onDelete,
  });

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
          Expanded(child: _buildStepContent(context, step)),
          if (!step.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tr(context, 'inactive'),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
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
              icon: Icon(
                Icons.delete_outline,
                size: 16,
                color: Colors.red[300],
              ),
              onPressed: onDelete,
              tooltip: tr(context, 'delete'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  /// Builds step content with proper multi-line hierarchy.
  ///
  /// For `specific_membership` steps:
  ///   Line 1: step name (bold)
  ///   Line 2: approver type label
  ///   Line 3: stored full name
  ///   Line 4: localized role name (if available)
  ///
  /// For other types:
  ///   Line 1: step name (bold)
  ///   Line 2: approver type detail
  Widget _buildStepContent(BuildContext context, ApprovalWorkflowStep step) {
    final children = <Widget>[
      Text(
        step.name,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ];

    if (step.approverType == 'specific_membership') {
      // Type label
      children.add(const SizedBox(height: 2));
      children.add(
        Text(
          tr(context, 'approval_specific_member'),
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      );
      // Resolve member display data
      final mdd = _resolveSpecificMember(context, step.approverMembershipId);
      if (mdd != null) {
        children.add(const SizedBox(height: 1));
        children.add(
          Text(
            mdd.primaryName,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        );
        if (mdd.roleName.isNotEmpty) {
          children.add(
            Text(
              mdd.roleName,
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
          );
        }
      }
    } else {
      children.add(const SizedBox(height: 2));
      children.add(
        Text(
          _approverTypeLabel(context, step),
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _approverTypeLabel(BuildContext context, ApprovalWorkflowStep step) {
    switch (step.approverType) {
      case 'permission':
        final label = _resolvePermissionLabel(
          context,
          step.approverPermissionKey,
        );
        return '${tr(context, 'approval_requires_permission')}: $label';
      case 'requester_manager':
        return tr(context, 'approval_requester_manager');
      case 'specific_membership':
        return tr(context, 'approval_specific_member');
      default:
        return step.approverType;
    }
  }

  /// Resolves a raw permission key to its locale-aware catalog label.
  ///
  /// Uses the `localizedLabel()` method on PermissionItem which returns
  /// Arabic or English labels based on the current UI language.
  ///
  /// Three cases:
  ///  1. Key found and `usableAsApprover` → display localized label.
  ///  2. Key found but NOT `usableAsApprover` → display localized label +
  ///     localized "(no longer selectable)" indicator.
  ///  3. Key not found in catalog at all → display localized
  ///     "Unavailable permission".
  String _resolvePermissionLabel(BuildContext context, String? key) {
    if (key == null || key.isEmpty) return '—';
    final langCode = Localizations.localeOf(context).languageCode;
    try {
      final rpState = context.read<RolePermissionState>();
      for (final cat in rpState.catalog) {
        for (final p in cat.permissions) {
          if (p.key == key) {
            final localLabel = p.localizedLabel(langCode);
            if (p.usableAsApprover) return localLabel;
            // Known but no longer eligible as approver.
            return '$localLabel ${tr(context, 'approval_permission_no_longer_selectable')}';
          }
        }
      }
    } catch (_) {
      // RolePermissionState may not be available; degrade gracefully.
    }
    // Not found in catalog at all.
    return tr(context, 'approval_permission_unavailable');
  }

  /// Resolves a membership ID to [MemberDisplayData] for step cards.
  /// Returns null when the member cannot be found.
  MemberDisplayData? _resolveSpecificMember(
    BuildContext context,
    String? membershipId,
  ) {
    if (membershipId == null || membershipId.isEmpty) return null;
    try {
      final rpState = context.read<RolePermissionState>();
      for (final m in rpState.employees) {
        if (m.membershipId == membershipId) {
          return MemberDisplayData.fromMember(context, m);
        }
      }
    } catch (_) {
      // RolePermissionState may not be available; degrade gracefully.
    }
    return null;
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

/// Fallback operator list for legacy/offline use when no schema is loaded.
/// Must match backend ApprovalTriggerEvaluator::evaluateSingle operators.
const _kFallbackOperators = [
  'equals',
  'not_equals',
  'greater_than',
  'greater_than_or_equal',
  'less_than',
  'less_than_or_equal',
  'contains',
  'in',
  'not_in',
  'exists',
];

/// A single editable trigger condition row model (schema-driven).
///
/// When a [FieldSchema] is available from the catalog, the field key
/// is selected via dropdown and operators are filtered per-field.
/// For legacy conditions whose field key doesn't match the current
/// catalog, [fieldKey] stores the raw key internally but the UI shows
/// a localized "Unavailable field" label — never the raw key.
class _ConditionRow {
  /// The selected field key (from catalog or legacy free-text).
  String? fieldKey;

  /// Free-text value controller (for string/number fields).
  final TextEditingController valueCtrl;

  /// Selected enum value (for enum-type fields).
  String? enumValue;

  /// Current operator.
  String operator;

  _ConditionRow({this.fieldKey, String value = '', this.operator = 'equals'})
    : valueCtrl = TextEditingController(text: value);

  void dispose() {
    valueCtrl.dispose();
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

  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _isSubmitting = false;

  // ── Entity type list (from server) ──
  List<ApprovalEntityTypeDescriptor>? _entityTypeList;
  bool _entityTypesLoading = false;
  String? _entityTypesError;

  // ── Entity type (schema-driven) ──
  String? _selectedEntityType;

  /// Loaded field schema for the selected entity type (null = not loaded).
  EntityFieldSchema? _entitySchema;
  bool _schemaLoading = false;
  String? _schemaError;

  // ── Trigger condition builder state ──
  String _conditionLogic = 'and';
  final List<_ConditionRow> _conditions = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();

    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');

    // Entity type: for edit mode, lock to existing; for create, null.
    _selectedEntityType = widget.existing?.entityType;

    // Seed conditions from existing workflow
    final tc = widget.existing?.triggerConditions;
    if (tc != null) {
      _conditionLogic = (tc['logic'] as String?) ?? 'and';
      final conds = tc['conditions'];
      if (conds is List) {
        for (final c in conds) {
          if (c is Map) {
            _conditions.add(
              _ConditionRow(
                fieldKey: c['field']?.toString(),
                value: c['value']?.toString() ?? '',
                operator: c['operator']?.toString() ?? 'equals',
              ),
            );
          }
        }
      }
    }

    // Load entity types for create mode, or schema for edit mode.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isEdit) {
        _loadEntityTypes();
      }
      if (_selectedEntityType != null && _selectedEntityType!.isNotEmpty) {
        _loadSchema();
      }
    });
  }

  /// Load the field schema for the currently selected entity type.
  Future<void> _loadSchema() async {
    final et = _selectedEntityType;
    if (et == null || et.isEmpty) {
      setState(() {
        _entitySchema = null;
        _schemaError = null;
      });
      return;
    }
    setState(() {
      _schemaLoading = true;
      _schemaError = null;
    });
    final catState = context.read<EntityFieldCatalogState>();
    final schema = await catState.loadSchema(et);
    if (!mounted) return;
    setState(() {
      _entitySchema = schema;
      _schemaLoading = false;
      _schemaError = schema == null
          ? catState.schemaError(et) ?? 'Schema not available'
          : null;
    });
  }

  /// Load the entity type list from the backend.
  Future<void> _loadEntityTypes() async {
    if (!mounted) return;
    setState(() {
      _entityTypesLoading = true;
      _entityTypesError = null;
    });
    final catState = context.read<EntityFieldCatalogState>();
    final types = await catState.loadEntityTypes();
    if (!mounted) return;
    setState(() {
      _entityTypeList = types;
      _entityTypesLoading = false;
      _entityTypesError = catState.entityTypesError;
    });
  }

  /// Called when the entity type dropdown changes.
  void _onEntityTypeChanged(String? newType) {
    setState(() {
      _selectedEntityType = newType;
      _entitySchema = null;
      // Reset conditions when entity type changes (fields differ).
      for (final c in _conditions) {
        c.dispose();
      }
      _conditions.clear();
    });
    _loadSchema();
  }

  /// Resolve the entity label for edit-mode display. Never returns raw key.
  String _resolveEntityLabelInDialog(BuildContext context) {
    final et = _selectedEntityType;
    if (et == null || et.isEmpty) {
      return tr(context, 'approval_entity_type_unavailable');
    }
    // Use the top-level resolver (checks descriptors and schema cache).
    final catState = context.read<EntityFieldCatalogState>();
    return _resolveEntityLabel(context, et, catState);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    for (final c in _conditions) {
      c.dispose();
    }
    super.dispose();
  }

  /// Build the trigger conditions JSON from builder state.
  ///
  /// Serialization rules:
  /// - `exists` operator → no `value` key (Phase 1 compatible).
  /// - Numeric fields → serialize as num, not string.
  /// - Enum fields → canonical raw option value.
  /// - `in`/`not_in` → value is a list.
  Map<String, dynamic>? _buildTriggerConditions() {
    final valid = _conditions
        .where((c) => c.fieldKey != null && c.fieldKey!.isNotEmpty)
        .toList();
    if (valid.isEmpty) return null;
    return {
      'logic': _conditionLogic,
      'conditions': valid.map((c) {
        final fieldSchema = _entitySchema?.fieldByKey(c.fieldKey!);
        final result = <String, dynamic>{
          'field': c.fieldKey,
          'operator': c.operator,
        };

        // exists operator → no value key at all.
        if (c.operator == 'exists') return result;

        // Resolve raw value.
        final rawVal = (fieldSchema != null && fieldSchema.isEnum)
            ? (c.enumValue ?? '')
            : c.valueCtrl.text.trim();

        // in/not_in → serialize as list.
        if (c.operator == 'in' || c.operator == 'not_in') {
          final items = rawVal
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          // Attempt numeric conversion for each item.
          if (fieldSchema != null && fieldSchema.isNumeric) {
            result['value'] = items.map((s) => num.tryParse(s) ?? s).toList();
          } else {
            result['value'] = items;
          }
          return result;
        }

        // Numeric fields → serialize as num.
        if (fieldSchema != null && fieldSchema.isNumeric) {
          result['value'] = num.tryParse(rawVal) ?? rawVal;
        } else {
          result['value'] = rawVal;
        }
        return result;
      }).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit
            ? tr(context, 'approval_edit_workflow')
            : tr(context, 'approval_create_workflow'),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Basic fields ──
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'name')),
                  validator: (v) => (v == null || v.isEmpty)
                      ? tr(context, 'field_required')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'description'),
                  ),
                  maxLines: 2,
                ),
                if (!_isEdit) ...[
                  const SizedBox(height: 12),
                  // Server-driven entity type dropdown.
                  // Shows localized labels; raw entity_type key is never exposed.
                  if (_entityTypesLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Loading entity types…',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_entityTypesError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 16,
                            color: Colors.red[400],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr(context, 'approval_entity_type_error'),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.red[400],
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _loadEntityTypes,
                            child: Text(tr(context, 'retry')),
                          ),
                        ],
                      ),
                    )
                  else if (_entityTypeList != null && _entityTypeList!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.orange[400],
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr(context, 'approval_entity_type_empty'),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.orange[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _selectedEntityType,
                      decoration: InputDecoration(
                        labelText: tr(context, 'approval_entity_type'),
                      ),
                      hint: Text(tr(context, 'approval_entity_type_select')),
                      items: (_entityTypeList ?? []).map((d) {
                        final lang = Localizations.localeOf(
                          context,
                        ).languageCode;
                        return DropdownMenuItem<String>(
                          value: d.entityType,
                          child: Text(d.localizedLabel(lang)),
                        );
                      }).toList(),
                      validator: (v) => (v == null || v.isEmpty)
                          ? tr(context, 'field_required')
                          : null,
                      onChanged: (v) {
                        if (v != _selectedEntityType) {
                          _onEntityTypeChanged(v);
                        }
                      },
                    ),
                ] else ...[
                  // Edit mode: show locked entity type with localized label.
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.category, size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Text(
                        '${tr(context, 'approval_entity_type')}: '
                        '${_resolveEntityLabelInDialog(context)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],

                // ── Trigger Conditions Builder ──
                const SizedBox(height: 20),
                _buildConditionsSection(context),
              ],
            ),
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
              : Text(_isEdit ? tr(context, 'save') : tr(context, 'create')),
        ),
      ],
    );
  }

  /// Builds the trigger conditions section with header, logic toggle,
  /// condition rows, and add button.
  Widget _buildConditionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(Icons.filter_alt_outlined, size: 16, color: Colors.deepPurple),
            const SizedBox(width: 6),
            Text(
              tr(context, 'approval_trigger_conditions'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Logic toggle (AND / OR)
        if (_conditions.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  tr(context, 'approval_trigger_logic'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('AND', style: TextStyle(fontSize: 11)),
                  selected: _conditionLogic == 'and',
                  onSelected: (_) => setState(() => _conditionLogic = 'and'),
                  selectedColor: Colors.deepPurple.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('OR', style: TextStyle(fontSize: 11)),
                  selected: _conditionLogic == 'or',
                  onSelected: (_) => setState(() => _conditionLogic = 'or'),
                  selectedColor: Colors.deepPurple.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

        // Condition rows
        if (_conditions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              tr(context, 'approval_trigger_no_conditions'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ..._conditions.asMap().entries.map(
          (entry) => _buildConditionRow(context, entry.key, entry.value),
        ),

        // Schema loading indicator
        if (_schemaLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  tr(context, 'loading'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),
          ),

        // Schema error with Retry
        if (_schemaError != null && !_schemaLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red[400]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(context, 'approval_schema_load_error'),
                    style: TextStyle(fontSize: 11, color: Colors.red[400]),
                  ),
                ),
                TextButton(
                  onPressed: _loadSchema,
                  child: Text(
                    tr(context, 'retry'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

        // Add condition button — disabled until schema is loaded
        const SizedBox(height: 6),
        TextButton.icon(
          icon: Icon(
            Icons.add_circle_outline,
            size: 15,
            color: _entitySchema != null ? Colors.deepPurple : Colors.grey,
          ),
          label: Text(
            tr(context, 'approval_trigger_add_condition'),
            style: TextStyle(
              fontSize: 12,
              color: _entitySchema != null ? Colors.deepPurple : Colors.grey,
            ),
          ),
          onPressed: _entitySchema != null
              ? () => setState(() => _conditions.add(_ConditionRow()))
              : null,
        ),
      ],
    );
  }

  /// Builds a single condition row with schema-driven selectors.
  ///
  /// Layout: [Field ▼] [Operator ▼] [Value input/dropdown] [✕]
  ///
  /// - Field: dropdown populated from [_entitySchema.fields], or shows
  ///   the raw key for legacy conditions not in the current catalog.
  /// - Operator: filtered to the selected field's allowed operators,
  ///   falling back to [_kFallbackOperators] when no schema is loaded.
  /// - Value: adaptive input—enum dropdown for enum fields, numeric
  ///   keyboard for number fields, free text otherwise.
  Widget _buildConditionRow(
    BuildContext context,
    int index,
    _ConditionRow cond,
  ) {
    final langCode = Localizations.localeOf(context).languageCode;
    final schema = _entitySchema;
    final fieldSchema = (cond.fieldKey != null && schema != null)
        ? schema.fieldByKey(cond.fieldKey!)
        : null;

    // Operators for this field: use schema's per-field list or fallback.
    final operators = fieldSchema != null && fieldSchema.operators.isNotEmpty
        ? fieldSchema.operators
        : _kFallbackOperators;

    // Ensure the current operator is valid for this field.
    if (!operators.contains(cond.operator)) {
      cond.operator = operators.first;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            // ── Field selector ──
            Expanded(
              flex: 3,
              child: _buildFieldSelector(context, cond, langCode),
            ),
            const SizedBox(width: 6),
            // ── Operator dropdown ──
            Expanded(
              flex: 4,
              child: DropdownButtonFormField<String>(
                key: ValueKey('op_${index}_${cond.fieldKey}_${cond.operator}'),
                initialValue: cond.operator,
                isDense: true,
                decoration: InputDecoration(
                  labelText: tr(context, 'approval_trigger_operator'),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  border: const OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                items: operators.map((op) {
                  return DropdownMenuItem(
                    value: op,
                    child: Text(
                      tr(context, 'approval_trigger_op_$op'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() {
                  cond.operator = v ?? operators.first;
                  // Clear value when switching to exists.
                  if (cond.operator == 'exists') {
                    cond.valueCtrl.clear();
                    cond.enumValue = null;
                  }
                }),
              ),
            ),
            const SizedBox(width: 6),
            // ── Value input (adaptive) ──
            Expanded(
              flex: 3,
              child: _buildValueInput(context, cond, fieldSchema, langCode),
            ),
            // ── Delete button ──
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.red[400]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: tr(context, 'delete'),
              onPressed: () => setState(() {
                _conditions[index].dispose();
                _conditions.removeAt(index);
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the field selector: a catalog dropdown when schema is loaded,
  /// or a read-only "Unavailable field" chip for legacy/unknown fields.
  /// **Never displays or edits the raw field key.**
  Widget _buildFieldSelector(
    BuildContext context,
    _ConditionRow cond,
    String langCode,
  ) {
    final schema = _entitySchema;
    if (schema != null && schema.fields.isNotEmpty) {
      // Check if the condition's current field is in the catalog.
      final fieldInCatalog =
          cond.fieldKey == null || schema.fieldByKey(cond.fieldKey!) != null;

      if (!fieldInCatalog) {
        // Historical field not in current catalog → read-only "unavailable"
        // with option to replace by selecting from dropdown.
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
            color: Colors.orange.withValues(alpha: 0.05),
          ),
          child: Text(
            tr(context, 'approval_field_unavailable'),
            style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }

      return DropdownButtonFormField<String>(
        key: ValueKey('field_${cond.fieldKey}'),
        initialValue: cond.fieldKey,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr(context, 'approval_trigger_field'),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        items: schema.fields.map((f) {
          return DropdownMenuItem(
            value: f.key,
            child: Text(
              f.localizedLabel(langCode),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (v) => setState(() {
          cond.fieldKey = v;
          // Reset operator and value when field changes.
          final newField = schema.fieldByKey(v ?? '');
          if (newField != null && newField.operators.isNotEmpty) {
            cond.operator = newField.operators.first;
          }
          cond.valueCtrl.clear();
          cond.enumValue = null;
        }),
      );
    }
    // Fallback: show localized "unavailable field" text — never raw keys.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(4),
        color: Colors.orange.withValues(alpha: 0.05),
      ),
      child: Text(
        tr(context, 'approval_field_unavailable'),
        style: TextStyle(fontSize: 12, color: Colors.orange[700]),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Builds the value input widget adapted to the field's data type.
  ///
  /// - **enum**: dropdown of predefined options from the catalog.
  /// - **number**: text field with numeric keyboard.
  /// - **string** / unknown: free-text input.
  Widget _buildValueInput(
    BuildContext context,
    _ConditionRow cond,
    FieldSchema? fieldSchema,
    String langCode,
  ) {
    // exists operator → no value input needed.
    if (cond.operator == 'exists') {
      return const SizedBox.shrink();
    }

    // Enum field → dropdown of options
    if (fieldSchema != null && fieldSchema.isEnum) {
      return DropdownButtonFormField<String>(
        key: ValueKey('val_${cond.fieldKey}_${cond.enumValue}'),
        initialValue: cond.enumValue,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr(context, 'approval_trigger_value'),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        items: fieldSchema.options!.map((opt) {
          return DropdownMenuItem(
            value: opt.value,
            child: Text(
              opt.localizedLabel(langCode),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (v) => setState(() => cond.enumValue = v),
      );
    }

    // Number field → numeric keyboard
    return TextFormField(
      controller: cond.valueCtrl,
      keyboardType: (fieldSchema != null && fieldSchema.isNumeric)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: tr(context, 'approval_trigger_value'),
        hintText: (fieldSchema != null && fieldSchema.isNumeric)
            ? 'e.g. 5000'
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: const OutlineInputBorder(),
      ),
      style: const TextStyle(fontSize: 12),
      validator: (fieldSchema != null && fieldSchema.isNumeric)
          ? (v) {
              if (v != null && v.isNotEmpty && double.tryParse(v) == null) {
                return tr(context, 'approval_trigger_invalid_number');
              }
              return null;
            }
          : null,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);

    final state = context.read<ApprovalState>();
    final tc = _buildTriggerConditions();

    if (_isEdit) {
      final result = await state.updateWorkflow(
        widget.existing!.id,
        ApprovalWorkflowUpdatePayload(
          name: _nameCtrl.text,
          description: _descCtrl.text,
          triggerConditions: tc,
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    } else {
      final result = await state.createWorkflow(
        ApprovalWorkflowPayload(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          entityType: _selectedEntityType ?? '',
          triggerConditions: tc,
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    }

    if (mounted) setState(() => _isSubmitting = false);
  }
}

/// Dialog for adding or editing a workflow step.
///
/// Loads real workspace permissions and employees from [RolePermissionState]
/// to provide dynamic selectors instead of hardcoded text fields.
class _StepFormDialog extends StatefulWidget {
  final String workflowId;
  final int? nextOrder;
  final ApprovalWorkflowStep? existing;
  const _StepFormDialog({
    required this.workflowId,
    this.nextOrder,
    this.existing,
  });

  @override
  State<_StepFormDialog> createState() => _StepFormDialogState();
}

class _StepFormDialogState extends State<_StepFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late String _approverType;
  late bool _allowSelfApproval;
  late bool _isActive;
  bool _isSubmitting = false;

  // Dynamic selector values
  String? _selectedPermissionKey;
  String? _selectedMembershipId;

  // Loaded data from workspace APIs
  List<PermissionItem> _allPermissions = [];
  List<WorkspaceEmployeeMember> _allMembers = [];
  bool _selectorsLoading = true;
  bool _selectorsError = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _approverType = widget.existing?.approverType ?? 'permission';
    _allowSelfApproval = widget.existing?.allowSelfApproval ?? false;
    _isActive = widget.existing?.isActive ?? true;
    _selectedPermissionKey = widget.existing?.approverPermissionKey;
    _selectedMembershipId = widget.existing?.approverMembershipId;

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSelectors());
  }

  /// Load workspace permissions and employees for dynamic selectors.
  Future<void> _loadSelectors() async {
    final rpState = context.read<RolePermissionState>();
    try {
      await Future.wait([rpState.loadCatalog(), rpState.loadEmployees()]);
      if (!mounted) return;
      setState(() {
        // Only include permissions flagged as approver-eligible.
        _allPermissions = rpState.catalog
            .expand((cat) => cat.permissions)
            .where((p) => p.usableAsApprover)
            .toList();
        _allMembers = rpState.employees
            .where((m) => m.status == 'active')
            .toList();
        _selectorsLoading = false;
        _selectorsError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selectorsLoading = false;
        _selectorsError = true;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEdit
            ? tr(context, 'approval_edit_step')
            : tr(context, 'approval_add_step'),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'name'),
                    hintText: 'e.g. Manager Review',
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? tr(context, 'field_required')
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _approverType,
                  decoration: InputDecoration(
                    labelText: tr(context, 'approval_approver_type'),
                  ),
                  items: kApproverTypes
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(_approverTypeLabel(context, t)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _approverType = v!;
                    _selectedPermissionKey = null;
                    _selectedMembershipId = null;
                  }),
                ),

                // ── Permission selector ──
                if (_approverType == 'permission') ...[
                  const SizedBox(height: 12),
                  _buildPermissionSelector(context),
                ],

                // ── Specific member selector ──
                if (_approverType == 'specific_membership') ...[
                  const SizedBox(height: 12),
                  _buildMemberSelector(context),
                ],

                const SizedBox(height: 12),
                SwitchListTile(
                  title: Text(
                    tr(context, 'approval_allow_self_approval'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: _allowSelfApproval,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _allowSelfApproval = v),
                ),
                if (_isEdit)
                  SwitchListTile(
                    title: Text(
                      tr(context, 'active'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    value: _isActive,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
              ],
            ),
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
              : Text(_isEdit ? tr(context, 'save') : tr(context, 'create')),
        ),
      ],
    );
  }

  /// Searchable dropdown for permission keys, loaded from the workspace
  /// permission catalog via [RolePermissionState].
  ///
  /// Only permissions flagged `usable_as_approver` appear in the list.
  Widget _buildPermissionSelector(BuildContext context) {
    if (_selectorsLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            tr(context, 'loading'),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    if (_selectorsError) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'approval_selector_error'),
              style: TextStyle(fontSize: 12, color: Colors.red[400]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () {
              setState(() => _selectorsLoading = true);
              _loadSelectors();
            },
            tooltip: tr(context, 'retry'),
          ),
        ],
      );
    }

    if (_allPermissions.isEmpty) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'approval_no_permissions'),
              style: TextStyle(fontSize: 12, color: Colors.orange[600]),
            ),
          ),
        ],
      );
    }

    // Validate current selection still exists in catalog.
    final validKeys = _allPermissions.map((p) => p.key).toSet();
    if (_selectedPermissionKey != null &&
        !validKeys.contains(_selectedPermissionKey)) {
      _selectedPermissionKey = null;
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedPermissionKey,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr(context, 'approval_select_permission'),
        helperText: tr(context, 'approval_permission_approver_hint'),
        helperMaxLines: 2,
        isDense: true,
      ),
      items: _allPermissions.map((p) {
        final langCode = Localizations.localeOf(context).languageCode;
        return DropdownMenuItem(
          value: p.key,
          child: Text(
            p.localizedLabel(langCode),
            style: const TextStyle(fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedPermissionKey = v),
      validator: (v) =>
          (_approverType == 'permission' && (v == null || v.isEmpty))
          ? tr(context, 'field_required')
          : null,
    );
  }

  /// Dropdown for selecting a specific workspace member, loaded from
  /// [RolePermissionState.employees].
  Widget _buildMemberSelector(BuildContext context) {
    if (_selectorsLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            tr(context, 'loading'),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      );
    }

    if (_selectorsError) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'approval_selector_error'),
              style: TextStyle(fontSize: 12, color: Colors.red[400]),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            onPressed: () {
              setState(() => _selectorsLoading = true);
              _loadSelectors();
            },
            tooltip: tr(context, 'retry'),
          ),
        ],
      );
    }

    if (_allMembers.isEmpty) {
      return Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: Colors.orange[400]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(context, 'approval_no_members'),
              style: TextStyle(fontSize: 12, color: Colors.orange[600]),
            ),
          ),
        ],
      );
    }

    // Validate current selection still exists.
    final validIds = _allMembers.map((m) => m.membershipId).toSet();
    if (_selectedMembershipId != null &&
        !validIds.contains(_selectedMembershipId)) {
      _selectedMembershipId = null;
    }

    // Build display data for all members once.
    final memberDisplays = _allMembers
        .map((m) => MemberDisplayData.fromMember(context, m))
        .toList();

    return DropdownButtonFormField<String>(
      initialValue: _selectedMembershipId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr(context, 'approval_select_member'),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      // Menu items: two-line layout (name + localized role).
      items: List.generate(_allMembers.length, (i) {
        final m = _allMembers[i];
        final mdd = memberDisplays[i];
        return DropdownMenuItem(
          value: m.membershipId,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mdd.primaryName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (mdd.roleName.isNotEmpty)
                Text(
                  mdd.roleName,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        );
      }),
      // Selected value: single-line compact display to prevent overflow.
      selectedItemBuilder: (ctx) {
        return List.generate(_allMembers.length, (i) {
          final mdd = memberDisplays[i];
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              mdd.primaryName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          );
        });
      },
      onChanged: (v) => setState(() => _selectedMembershipId = v),
      validator: (v) =>
          (_approverType == 'specific_membership' && (v == null || v.isEmpty))
          ? tr(context, 'field_required')
          : null,
    );
  }

  String _approverTypeLabel(BuildContext context, String t) => switch (t) {
    'permission' => tr(context, 'approval_type_permission'),
    'requester_manager' => tr(context, 'approval_type_requester_manager'),
    'specific_membership' => tr(context, 'approval_type_specific_member'),
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
        data['approver_permission_key'] = _selectedPermissionKey;
      }
      if (_approverType == 'specific_membership') {
        data['approver_membership_id'] = _selectedMembershipId;
      }
      final result = await state.updateStep(widget.existing!.id, data);
      if (result != null && mounted) Navigator.pop(context);
    } else {
      final result = await state.addStep(
        widget.workflowId,
        ApprovalWorkflowStepPayload(
          name: _nameCtrl.text.trim(),
          approverType: _approverType,
          approverPermissionKey: _approverType == 'permission'
              ? _selectedPermissionKey
              : null,
          approverMembershipId: _approverType == 'specific_membership'
              ? _selectedMembershipId
              : null,
          allowSelfApproval: _allowSelfApproval,
        ),
      );
      if (result != null && mounted) Navigator.pop(context);
    }

    if (mounted) setState(() => _isSubmitting = false);
  }
}
