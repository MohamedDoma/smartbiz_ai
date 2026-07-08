// SmartBiz AI — Duplicate rules screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/duplicate_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../duplicate_state.dart';

class DuplicateRulesScreen extends StatefulWidget {
  const DuplicateRulesScreen({super.key});
  @override
  State<DuplicateRulesScreen> createState() => _DuplicateRulesScreenState();
}

class _DuplicateRulesScreenState extends State<DuplicateRulesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DuplicateState>().loadRules();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'dup_rules')),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _showCreateDialog(context),
          ),
        ],
      ),
      body: Consumer<DuplicateState>(
        builder: (ctx, state, _) {
          if (state.loading && state.rules.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.rules.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.content_copy_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'dup_no_duplicates'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'dup_create_rule')),
                  onPressed: () => _showCreateDialog(context),
                ),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.rules.length,
            itemBuilder: (ctx, i) {
              final rule = state.rules[i];
              return Card(
                child: ListTile(
                  leading: Icon(
                    rule.action == 'block' ? Icons.block : Icons.warning_amber_outlined,
                    color: rule.action == 'block' ? Colors.red : Colors.orange,
                  ),
                  title: Text(rule.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      '${_entityLabel(context, rule.entityType)} · ${rule.matchFields.join(", ")}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    Text(
                      '${rule.matchStrategy} · ${_actionLabel(context, rule.action)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ]),
                  trailing: rule.isActive
                      ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                      : const Icon(Icons.cancel, color: Colors.grey, size: 18),
                  onLongPress: () {
                    if (rule.isActive) {
                      state.deleteRule(rule.id);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    String entityType = 'contact';
    String action = 'warn';
    final selectedFields = <String>{};
    final contactFields = ['name', 'phone', 'email'];
    final recordFields = ['title', 'contact_id', 'pipeline_id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final fields = entityType == 'contact' ? contactFields : recordFields;
          return AlertDialog(
            title: Text(tr(context, 'dup_create_rule')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'dup_rule')),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: entityType,
                  decoration: InputDecoration(labelText: tr(context, 'dup_entity_type')),
                  items: [
                    DropdownMenuItem(value: 'contact', child: Text(tr(context, 'dup_contact'))),
                    DropdownMenuItem(value: 'pipeline_record', child: Text(tr(context, 'dup_pipeline_record'))),
                  ],
                  onChanged: (v) => setDlg(() {
                    entityType = v ?? 'contact';
                    selectedFields.clear();
                  }),
                ),
                const SizedBox(height: 8),
                Text(tr(context, 'dup_match_fields'), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                Wrap(
                  spacing: 8,
                  children: fields.map((f) => FilterChip(
                    label: Text(f),
                    selected: selectedFields.contains(f),
                    onSelected: (v) => setDlg(() {
                      if (v) {
                        selectedFields.add(f);
                      } else {
                        selectedFields.remove(f);
                      }
                    }),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: action,
                  decoration: InputDecoration(labelText: tr(context, 'dup_action')),
                  items: [
                    DropdownMenuItem(value: 'warn', child: Text(tr(context, 'dup_warn'))),
                    DropdownMenuItem(value: 'block', child: Text(tr(context, 'dup_block'))),
                  ],
                  onChanged: (v) => setDlg(() => action = v ?? 'warn'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty || selectedFields.isEmpty) return;
                  await context.read<DuplicateState>().createRule(DuplicateRulePayload(
                    name: nameCtrl.text.trim(),
                    entityType: entityType,
                    matchFields: selectedFields.toList(),
                    action: action,
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(tr(context, 'create')),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _entityLabel(BuildContext context, String t) => switch (t) {
      'contact' => tr(context, 'dup_contact'),
      'pipeline_record' => tr(context, 'dup_pipeline_record'),
      _ => t,
    };

String _actionLabel(BuildContext context, String a) => switch (a) {
      'warn' => tr(context, 'dup_warn'),
      'block' => tr(context, 'dup_block'),
      _ => a,
    };
