// SmartBiz AI — Approval inbox & requests screen.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/api/approval_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/modules/blueprint_navigation_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../approval_state.dart';
import 'approval_workflows_screen.dart';

class ApprovalInboxScreen extends StatefulWidget {
  const ApprovalInboxScreen({super.key});
  @override
  State<ApprovalInboxScreen> createState() => _ApprovalInboxScreenState();
}

class _ApprovalInboxScreenState extends State<ApprovalInboxScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabCtrl;

  /// Current visible tab descriptors, rebuilt when permissions change.
  List<_TabDescriptor> _visibleTabs = const [];

  @override
  void initState() {
    super.initState();
    // Defer tab build to didChangeDependencies where context is safe.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildTabsIfNeeded();
  }

  /// (Re)build the visible tab list from effective permissions and recreate
  /// the TabController when the set of visible tabs changes.
  void _rebuildTabsIfNeeded() {
    final perms = _effectivePermissions();
    final newTabs = _buildVisibleTabs(perms);

    // Short-circuit if tabs haven't changed.
    if (_tabsEqual(_visibleTabs, newTabs) && _tabCtrl != null) return;

    final oldIndex = _tabCtrl?.index ?? 0;
    _tabCtrl?.dispose();

    _visibleTabs = newTabs;
    final clampedIndex = oldIndex.clamp(0, newTabs.length - 1);
    _tabCtrl = TabController(
      length: newTabs.length,
      initialIndex: clampedIndex,
      vsync: this,
    );

    // Trigger initial data loads on first build.
    if (oldIndex == 0 && clampedIndex == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = context.read<ApprovalState>();
        state.loadInbox();
        state.loadRequests();
      });
    }
  }

  Set<String> _effectivePermissions() {
    try {
      return context.read<BlueprintNavigationController>().effectivePermissions;
    } catch (_) {
      return const {};
    }
  }

  /// Build the ordered list of tabs the current user may see.
  static List<_TabDescriptor> _buildVisibleTabs(Set<String> perms) {
    final tabs = <_TabDescriptor>[
      // 1. Inbox — always visible (same as current behavior)
      const _TabDescriptor(
        id: 'inbox',
        labelKey: 'approval_inbox',
        type: _TabType.inbox,
      ),
      // 2. My Requests — always visible (same as current behavior)
      const _TabDescriptor(
        id: 'my_requests',
        labelKey: 'approval_my_requests',
        type: _TabType.requests,
        scope: 'my_requests',
      ),
    ];

    // 3. All Requests — only when approvals.manage is present
    if (perms.contains('approvals.manage')) {
      tabs.add(
        const _TabDescriptor(
          id: 'all',
          labelKey: 'approval_all',
          type: _TabType.requests,
          scope: 'all',
        ),
      );
    }

    // 4. Workflow Management — preserve existing permission rule
    if (perms.contains('approvals.manage')) {
      tabs.add(
        const _TabDescriptor(
          id: 'workflows',
          labelKey: 'approval_workflows',
          type: _TabType.workflows,
        ),
      );
    }

    return tabs;
  }

  static bool _tabsEqual(List<_TabDescriptor> a, List<_TabDescriptor> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _tabCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guard: if _tabCtrl hasn't been created yet (shouldn't happen after
    // didChangeDependencies), show a loading indicator.
    if (_tabCtrl == null || _visibleTabs.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'approvals')),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: _visibleTabs.length > 3,
          tabs: [
            for (final tab in _visibleTabs)
              Tab(text: tr(context, tab.labelKey)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [for (final tab in _visibleTabs) _buildTabBody(tab)],
      ),
    );
  }

  Widget _buildTabBody(_TabDescriptor tab) {
    return switch (tab.type) {
      _TabType.inbox => _InboxTab(),
      _TabType.requests => _RequestsTab(scope: tab.scope!),
      _TabType.workflows => const ApprovalWorkflowsScreen(embedded: true),
    };
  }
}

// ── Tab descriptor ─────────────────────────────────────────

enum _TabType { inbox, requests, workflows }

class _TabDescriptor {
  final String id;
  final String labelKey;
  final _TabType type;
  final String? scope;

  const _TabDescriptor({
    required this.id,
    required this.labelKey,
    required this.type,
    this.scope,
  });
}

/// Inbox tab — pending requests for the current actor.
class _InboxTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ApprovalState>(
      builder: (ctx, state, _) {
        if (state.loading && state.inbox.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.inbox.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'approval_inbox_empty'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => state.loadInbox(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.inbox.length,
            itemBuilder: (ctx, i) => _ApprovalCard(request: state.inbox[i]),
          ),
        );
      },
    );
  }
}

/// Requests tab — my_requests or all.
class _RequestsTab extends StatefulWidget {
  final String scope;
  const _RequestsTab({required this.scope});
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ApprovalState>().loadRequests(scope: widget.scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<ApprovalState>(
      builder: (ctx, state, _) {
        if (state.loading && state.requests.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.requests.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.assignment_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  tr(context, 'approval_no_requests'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => state.loadRequests(scope: widget.scope),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.requests.length,
            itemBuilder: (ctx, i) => _ApprovalCard(request: state.requests[i]),
          ),
        );
      },
    );
  }
}

/// Card for a single approval request.
class _ApprovalCard extends StatelessWidget {
  final ApprovalRequest request;
  const _ApprovalCard({required this.request});

  @override
  Widget build(BuildContext context) {
    final state = context.read<ApprovalState>();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetail(context, request.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: entity type + status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      request.workflowName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: request.status),
                ],
              ),
              const SizedBox(height: 6),
              // Entity info — readable subject title with fallback chain
              Text(
                _subjectLine(context, request),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              // Requester
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
                  const SizedBox(width: 4),
                  Text(
                    request.requesterName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
              // Progress
              if (request.stepsCount != null && request.stepsCount! > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: request.progress,
                          minHeight: 4,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            request.status == 'rejected'
                                ? Colors.red
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _progressLabel(context, request),
                      style: TextStyle(
                        fontSize: 11,
                        color: request.status == 'rejected'
                            ? Colors.red[400]
                            : Colors.grey[500],
                        fontWeight: request.status == 'rejected'
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
              // Decide actions — server-authoritative: only show when can_decide is true
              if (request.canDecide) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.close, size: 16, color: Colors.red[400]),
                      label: Text(
                        tr(context, 'reject'),
                        style: TextStyle(fontSize: 12, color: Colors.red[400]),
                      ),
                      onPressed: () =>
                          _showDecisionDialog(context, request.id, false),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(
                        tr(context, 'approve'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () =>
                          _showDecisionDialog(context, request.id, true),
                    ),
                  ],
                ),
              ],
              // Cancel — server-authoritative: only show when can_cancel is true
              if (request.canCancel) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 14,
                      color: Colors.grey[400],
                    ),
                    label: Text(
                      tr(context, 'cancel'),
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                    onPressed: () => state.cancelRequest(request.id),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, String id) {
    final state = context.read<ApprovalState>();
    state.loadRequestDetail(id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ApprovalDetailSheet(requestId: id, state: state),
    );
  }

  void _showDecisionDialog(BuildContext context, String id, bool isApprove) {
    final notesCtrl = TextEditingController();
    final state = context.read<ApprovalState>();
    final formKey = GlobalKey<FormState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isApprove
              ? tr(context, 'approval_confirm_approve')
              : tr(context, 'approval_confirm_reject'),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: notesCtrl,
            decoration: InputDecoration(
              labelText: isApprove
                  ? tr(context, 'notes')
                  : tr(context, 'approval_rejection_reason'),
              hintText: isApprove
                  ? tr(context, 'optional')
                  : tr(context, 'approval_rejection_reason_hint'),
            ),
            maxLines: 3,
            validator: isApprove
                ? null
                : (value) {
                    if (value == null || value.trim().isEmpty) {
                      return tr(context, 'approval_rejection_reason_required');
                    }
                    return null;
                  },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(context, 'cancel')),
          ),
          FilledButton(
            style: isApprove
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // For rejections, validate the form (require notes)
              if (!isApprove && !(formKey.currentState?.validate() ?? false)) {
                return;
              }
              Navigator.pop(ctx);
              final notes = notesCtrl.text.trim();
              if (isApprove) {
                await state.approve(id, notes: notes.isEmpty ? null : notes);
              } else {
                await state.reject(id, notes: notes);
              }
              state.loadInbox();
            },
            child: Text(
              isApprove ? tr(context, 'approve') : tr(context, 'reject'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Status badge widget.
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _statusLabel(context, status),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _statusColor(status),
        ),
      ),
    );
  }
}

/// Detail bottom sheet for a single approval request.
class _ApprovalDetailSheet extends StatelessWidget {
  final String requestId;
  final ApprovalState state;
  const _ApprovalDetailSheet({required this.requestId, required this.state});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return ListenableBuilder(
          listenable: state,
          builder: (ctx, _) {
            final req = state.selectedRequest;
            if (state.loading && req == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (req == null) {
              return Center(child: Text(tr(context, 'approval_not_found')));
            }
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        req.workflowName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusBadge(status: req.status),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow(
                  Icons.category,
                  tr(context, 'approval_label_entity'),
                  _entityTypeLabel(context, req.entityType),
                ),
                if (req.displayTitle != null && req.displayTitle!.isNotEmpty)
                  _infoRow(
                    Icons.label_outline,
                    tr(context, 'approval_item_label'),
                    req.displayTitle!,
                  ),
                _infoRow(
                  Icons.person,
                  tr(context, 'approval_label_requester'),
                  req.requesterName,
                ),
                if (req.createdAt != null)
                  _infoRow(
                    Icons.access_time,
                    tr(context, 'approval_label_submitted'),
                    _formatDate(context, req.createdAt!),
                  ),
                const Divider(height: 24),
                // Steps timeline
                Text(
                  tr(context, 'approval_steps'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...req.steps.map((s) => _StepTile(step: s)),
                // Decisions audit trail
                if (req.decisions.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    tr(context, 'approval_audit_trail'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...req.decisions.map((d) => _DecisionTile(decision: d)),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// Step timeline tile.
class _StepTile extends StatelessWidget {
  final ApprovalRequestStepDetail step;
  const _StepTile({required this.step});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: _stepColor(step.status).withValues(alpha: 0.15),
        child: Icon(
          _stepIcon(step.status),
          size: 16,
          color: _stepColor(step.status),
        ),
      ),
      title: Text(
        step.stepName ??
            '${tr(context, 'approval_step_fallback')} ${step.stepOrder}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        _stepSubtitle(context, step),
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: step.decidedAt != null
          ? Text(
              _formatDate(context, step.decidedAt!),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            )
          : null,
    );
  }

  String _stepSubtitle(BuildContext context, ApprovalRequestStepDetail s) {
    switch (s.status) {
      case 'pending':
        return tr(context, 'approval_awaiting_decision');
      case 'approved':
        return '${tr(context, 'approval_step_approved_by')} ${s.decidedByName}';
      case 'rejected':
        return '${tr(context, 'approval_step_rejected_by')} ${s.decidedByName}';
      case 'skipped':
        return tr(context, 'approval_step_skipped');
      default:
        return s.status;
    }
  }

  Color _stepColor(String s) => switch (s) {
    'approved' => Colors.green,
    'rejected' => Colors.red,
    'skipped' => Colors.grey,
    _ => Colors.orange,
  };

  IconData _stepIcon(String s) => switch (s) {
    'approved' => Icons.check_circle,
    'rejected' => Icons.cancel,
    'skipped' => Icons.skip_next,
    _ => Icons.hourglass_empty,
  };
}

/// Decision audit trail tile.
class _DecisionTile extends StatelessWidget {
  final ApprovalDecisionDetail decision;
  const _DecisionTile({required this.decision});

  @override
  Widget build(BuildContext context) {
    final decisionLabel = decision.decision == 'approved'
        ? tr(context, 'approval_decision_approved')
        : tr(context, 'approval_decision_rejected');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        decision.decision == 'approved'
            ? Icons.thumb_up_alt
            : Icons.thumb_down_alt,
        size: 18,
        color: decision.decision == 'approved' ? Colors.green : Colors.red,
      ),
      title: Text(
        '${decision.actorName} — $decisionLabel',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: decision.notes != null
          ? Text(
              '${tr(context, 'approval_reason_label')}: ${decision.notes!}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            )
          : null,
      trailing: decision.createdAt != null
          ? Text(
              _formatDate(context, decision.createdAt!),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]),
            )
          : null,
    );
  }
}

// ── Helpers ──────────────────────────────────────────────

String _statusLabel(BuildContext context, String s) => switch (s) {
  'pending' => tr(context, 'approval_pending'),
  'approved' => tr(context, 'approved'),
  'rejected' => tr(context, 'rejected'),
  'cancelled' => tr(context, 'cancelled'),
  _ => s,
};

Color _statusColor(String s) => switch (s) {
  'pending' => Colors.orange,
  'approved' => Colors.green,
  'rejected' => Colors.red,
  'cancelled' => Colors.grey,
  _ => Colors.grey,
};

/// Map raw entity_type to a human-readable localized label.
String _entityTypeLabel(BuildContext context, String entityType) {
  final key = 'approval_entity_$entityType';
  final label = tr(context, key);
  // tr() returns '[$key]' for missing keys — fall back to formatted type.
  if (label.startsWith('[') && label.endsWith(']')) {
    return entityType.replaceAll('_', ' ');
  }
  return label;
}

/// Readable subject line for approval cards.
/// Priority: displayTitle → entity type label + shortened UUID.
String _subjectLine(BuildContext context, ApprovalRequest req) {
  final title = req.displayTitle;
  final entityLabel = _entityTypeLabel(context, req.entityType);
  if (title != null && title.isNotEmpty) {
    return '${tr(context, 'approval_item_label')}: $title';
  }
  return '$entityLabel • ${req.entityId.substring(0, 8)}…';
}

/// Localized progress label for an approval request.
String _progressLabel(BuildContext context, ApprovalRequest req) {
  final total = req.stepsCount ?? req.steps.length;
  final of = tr(context, 'approval_progress_of');
  if (req.status == 'rejected' && req.rejectedAtStep != null) {
    return '${tr(context, 'approval_progress_rejected_at')} ${req.rejectedAtStep} $of $total';
  }
  if (req.status == 'approved') {
    return '$total $of $total';
  }
  return '${req.completedSteps ?? 0} $of $total';
}

/// Format an ISO-8601 date string to a locale-aware display format.
/// e.g. "15 Jul 2026" (en) or "15 يوليو 2026" (ar).
String _formatDate(BuildContext context, String isoDate) {
  try {
    final dt = DateTime.parse(isoDate);
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMd(locale).format(dt);
  } catch (_) {
    // Graceful fallback to the raw first 10 chars.
    return isoDate.length >= 10 ? isoDate.substring(0, 10) : isoDate;
  }
}
