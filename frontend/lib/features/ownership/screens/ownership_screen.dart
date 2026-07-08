// SmartBiz AI — Ownership assignments screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/ownership_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../ownership_state.dart';

class OwnershipScreen extends StatefulWidget {
  const OwnershipScreen({super.key});
  @override
  State<OwnershipScreen> createState() => _OwnershipScreenState();
}

class _OwnershipScreenState extends State<OwnershipScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<OwnershipState>().loadAssignments();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'own_ownership')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showAssignDialog(context),
          ),
        ],
      ),
      body: Consumer<OwnershipState>(
        builder: (ctx, state, _) {
          if (state.loading && state.assignments.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.assignments.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.person_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'own_no_assignments'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'own_assign_owner')),
                  onPressed: () => _showAssignDialog(context),
                ),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.assignments.length,
            itemBuilder: (ctx, i) => _AssignmentCard(assignment: state.assignments[i], state: state),
          );
        },
      ),
    );
  }

  void _showAssignDialog(BuildContext context) {
    final entityIdCtrl = TextEditingController();
    final memberIdCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String entityType = 'contact';
    String source = 'manual';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'own_assign_owner')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: entityType,
                decoration: InputDecoration(labelText: tr(context, 'dup_entity_type')),
                items: kEntityTypes.map((t) => DropdownMenuItem(value: t, child: Text(_entityLabel(context, t)))).toList(),
                onChanged: (v) => setDlg(() => entityType = v ?? 'contact'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: entityIdCtrl,
                decoration: InputDecoration(labelText: 'Entity ID', hintText: 'UUID'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: memberIdCtrl,
                decoration: InputDecoration(labelText: tr(context, 'own_owner'), hintText: 'Membership UUID'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: source,
                decoration: InputDecoration(labelText: tr(context, 'own_source')),
                items: kOwnershipSources.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (v) => setDlg(() => source = v ?? 'manual'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(labelText: tr(context, 'own_notes')),
                maxLines: 2,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (entityIdCtrl.text.trim().isEmpty || memberIdCtrl.text.trim().isEmpty) return;
                await context.read<OwnershipState>().createAssignment(OwnershipAssignmentPayload(
                  entityType: entityType,
                  entityId: entityIdCtrl.text.trim(),
                  ownerMembershipId: memberIdCtrl.text.trim(),
                  source: source,
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
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
}

class _AssignmentCard extends StatelessWidget {
  final OwnershipAssignment assignment;
  final OwnershipState state;
  const _AssignmentCard({required this.assignment, required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(
                assignment.owner?['full_name'] ?? tr(context, 'own_owner'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _entityLabel(context, assignment.entityType),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('ID: ${assignment.entityId.substring(0, 8)}…',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text('${tr(context, 'own_source')}: ${assignment.source}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (assignment.team != null)
            Text('${assignment.team!['name']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (assignment.department != null)
            Text('${assignment.department!['name']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (assignment.notes != null)
            Text(assignment.notes!, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: Text(tr(context, 'own_transfer'), style: const TextStyle(fontSize: 12)),
              onPressed: () => _showTransferDialog(context),
            ),
          ]),
        ]),
      ),
    );
  }

  void _showTransferDialog(BuildContext context) {
    final memberCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'own_transfer')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: memberCtrl,
            decoration: InputDecoration(labelText: tr(context, 'own_new_owner'), hintText: 'Membership UUID'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: reasonCtrl,
            decoration: InputDecoration(labelText: tr(context, 'own_reason')),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (memberCtrl.text.trim().isEmpty) return;
              await state.transferAssignment(
                assignment.id,
                OwnershipTransferPayload(
                  toMembershipId: memberCtrl.text.trim(),
                  reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
                ),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr(context, 'own_transfer')),
          ),
        ],
      ),
    );
  }
}

String _entityLabel(BuildContext context, String t) => switch (t) {
      'contact' => tr(context, 'dup_contact'),
      'pipeline_record' => tr(context, 'dup_pipeline_record'),
      _ => t,
    };
