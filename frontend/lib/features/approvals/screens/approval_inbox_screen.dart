// SmartBiz AI — Approval inbox & requests screen.
import 'package:flutter/material.dart';
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
  late TabController _tabCtrl;
  late bool _canManage;

  @override
  void initState() {
    super.initState();
    _canManage = _hasManagePermission();
    _tabCtrl = TabController(length: _canManage ? 4 : 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<ApprovalState>();
      state.loadInbox();
      state.loadRequests();
    });
  }

  bool _hasManagePermission() {
    try {
      return context
          .read<BlueprintNavigationController>()
          .effectivePermissions
          .contains('approvals.manage');
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'approvals')),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: _canManage,
          tabs: [
            Tab(text: tr(context, 'approval_inbox')),
            Tab(text: tr(context, 'approval_my_requests')),
            Tab(text: tr(context, 'approval_all')),
            if (_canManage)
              Tab(text: tr(context, 'approval_workflows')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _InboxTab(),
          _RequestsTab(scope: 'my_requests'),
          _RequestsTab(scope: 'all'),
          if (_canManage)
            const ApprovalWorkflowsScreen(embedded: true),
        ],
      ),
    );
  }
}

/// Inbox tab — pending requests for the current actor.
class _InboxTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ApprovalState>(builder: (ctx, state, _) {
      if (state.loading && state.inbox.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.inbox.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(tr(context, 'approval_inbox_empty'),
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ]),
        );
      }
      return RefreshIndicator(
        onRefresh: () => state.loadInbox(),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.inbox.length,
          itemBuilder: (ctx, i) =>
              _ApprovalCard(request: state.inbox[i], showActions: true),
        ),
      );
    });
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
    return Consumer<ApprovalState>(builder: (ctx, state, _) {
      if (state.loading && state.requests.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      if (state.requests.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.assignment_outlined, size: 64,
                color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(tr(context, 'approval_no_requests'),
                style: TextStyle(color: Colors.grey[600], fontSize: 16)),
          ]),
        );
      }
      return RefreshIndicator(
        onRefresh: () => state.loadRequests(scope: widget.scope),
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.requests.length,
          itemBuilder: (ctx, i) => _ApprovalCard(
            request: state.requests[i],
            showActions: widget.scope == 'my_requests',
          ),
        ),
      );
    });
  }
}

/// Card for a single approval request.
class _ApprovalCard extends StatelessWidget {
  final ApprovalRequest request;
  final bool showActions;
  const _ApprovalCard({required this.request, this.showActions = false});

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
                          fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: request.status),
                ],
              ),
              const SizedBox(height: 6),
              // Entity info
              Text(
                '${request.entityType} • ${request.entityId.substring(0, 8)}…',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              // Requester
              Row(children: [
                Icon(Icons.person_outline, size: 14,
                    color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(request.requesterName,
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ]),
              // Progress
              if (request.stepsCount != null && request.stepsCount! > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
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
                    '${request.completedSteps ?? 0}/${request.stepsCount}',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ]),
              ],
              // Actions (only for inbox items)
              if (showActions && request.status == 'pending') ...[
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    icon: Icon(Icons.close, size: 16,
                        color: Colors.red[400]),
                    label: Text(tr(context, 'reject'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.red[400])),
                    onPressed: () =>
                        _showDecisionDialog(context, request.id, false),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(tr(context, 'approve'),
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () =>
                        _showDecisionDialog(context, request.id, true),
                  ),
                ]),
              ],
              // Cancel (for own pending requests)
              if (showActions && request.status == 'pending') ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(Icons.cancel_outlined, size: 14,
                        color: Colors.grey[400]),
                    label: Text(tr(context, 'cancel'),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
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

  void _showDecisionDialog(
      BuildContext context, String id, bool isApprove) {
    final notesCtrl = TextEditingController();
    final state = context.read<ApprovalState>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isApprove
            ? tr(context, 'approval_confirm_approve')
            : tr(context, 'approval_confirm_reject')),
        content: TextField(
          controller: notesCtrl,
          decoration: InputDecoration(
            labelText: tr(context, 'notes'),
            hintText: tr(context, 'optional'),
          ),
          maxLines: 3,
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
              Navigator.pop(ctx);
              if (isApprove) {
                await state.approve(id, notes: notesCtrl.text);
              } else {
                await state.reject(id, notes: notesCtrl.text);
              }
              state.loadInbox();
            },
            child: Text(isApprove
                ? tr(context, 'approve')
                : tr(context, 'reject')),
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
  const _ApprovalDetailSheet(
      {required this.requestId, required this.state});

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
              return Center(
                  child: Text(tr(context, 'approval_not_found')));
            }
            return ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Title
                Row(children: [
                  Expanded(
                    child: Text(req.workflowName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  _StatusBadge(status: req.status),
                ]),
                const SizedBox(height: 12),
                _infoRow(Icons.category, 'Entity', req.entityType),
                _infoRow(Icons.person, 'Requester', req.requesterName),
                if (req.createdAt != null)
                  _infoRow(Icons.access_time, 'Submitted',
                      req.createdAt!.substring(0, 10)),
                const Divider(height: 24),
                // Steps timeline
                Text(tr(context, 'approval_steps'),
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ...req.steps.map((s) => _StepTile(step: s)),
                // Decisions audit trail
                if (req.decisions.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(tr(context, 'approval_audit_trail'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
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
      child: Row(children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(
            fontSize: 13, color: Colors.grey[600])),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ]),
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
        child: Icon(_stepIcon(step.status), size: 16,
            color: _stepColor(step.status)),
      ),
      title: Text(step.stepName ?? 'Step ${step.stepOrder}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      subtitle: Text(
        step.status == 'pending'
            ? 'Awaiting decision'
            : '${step.status} by ${step.decidedByName}',
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      trailing: step.decidedAt != null
          ? Text(step.decidedAt!.substring(0, 10),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]))
          : null,
    );
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
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        decision.decision == 'approved'
            ? Icons.thumb_up_alt
            : Icons.thumb_down_alt,
        size: 18,
        color: decision.decision == 'approved'
            ? Colors.green
            : Colors.red,
      ),
      title: Text(
        '${decision.actorName} — ${decision.decision}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: decision.notes != null
          ? Text(decision.notes!,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]))
          : null,
      trailing: decision.createdAt != null
          ? Text(decision.createdAt!.substring(0, 10),
              style: TextStyle(fontSize: 10, color: Colors.grey[400]))
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
