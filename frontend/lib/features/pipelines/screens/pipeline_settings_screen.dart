// SmartBiz AI — Pipeline settings screen (stages + custom fields).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/pipeline_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../pipeline_state.dart';

class PipelineSettingsScreen extends StatelessWidget {
  const PipelineSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'pip_settings'))),
      body: Consumer<PipelineState>(
        builder: (ctx, state, _) {
          if (state.activePipeline == null) {
            return Center(child: Text(tr(context, 'pip_select')));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Stages section ──
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr(context, 'pip_stages'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: tr(context, 'pip_create_stage'),
                  onPressed: () => _showCreateStageDialog(context, state),
                ),
              ]),
              if (state.stages.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'pip_no_stages')))
              else
                ...state.stages.map((s) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _statusColor(s.statusType).withValues(alpha: 0.15),
                          radius: 16,
                          child: Icon(Icons.circle, size: 12, color: _statusColor(s.statusType)),
                        ),
                        title: Text(s.name),
                        subtitle: Text('${s.statusType} · sort ${s.sortOrder}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                        trailing: s.isActive
                            ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                            : const Icon(Icons.cancel, color: Colors.grey, size: 18),
                      ),
                    )),

              const SizedBox(height: 24),

              // ── Custom fields section ──
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr(context, 'pip_custom_fields'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: tr(context, 'pip_create_field'),
                  onPressed: () => _showCreateFieldDialog(context, state),
                ),
              ]),
              if (state.customFields.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'pip_no_fields')))
              else
                ...state.customFields.map((f) => Card(
                      child: ListTile(
                        leading: Icon(_fieldTypeIcon(f.fieldType), color: AppColors.accent),
                        title: Text(f.label),
                        subtitle: Text('${f.fieldType}${f.isRequired ? " · ${tr(context, 'pip_required')}" : ""}',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  void _showCreateStageDialog(BuildContext context, PipelineState state) {
    final nameCtrl = TextEditingController();
    String statusType = 'open';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'pip_create_stage')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(labelText: tr(context, 'pip_stage_name')),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: statusType,
              decoration: const InputDecoration(labelText: 'Status type'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(value: 'won', child: Text('Won')),
                DropdownMenuItem(value: 'lost', child: Text('Lost')),
                DropdownMenuItem(value: 'completed', child: Text('Completed')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
              ],
              onChanged: (v) => setDlg(() => statusType = v ?? 'open'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await state.createStage(PipelineStagePayload(
                  name: nameCtrl.text.trim(),
                  statusType: statusType,
                  sortOrder: (state.stages.length + 1) * 10,
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

  void _showCreateFieldDialog(BuildContext context, PipelineState state) {
    final labelCtrl = TextEditingController();
    final optionsCtrl = TextEditingController();
    String fieldType = 'text';
    bool isRequired = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'pip_create_field')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: labelCtrl,
                decoration: InputDecoration(labelText: tr(context, 'pip_field_label')),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: fieldType,
                decoration: InputDecoration(labelText: tr(context, 'pip_field_type')),
                items: kFieldTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setDlg(() => fieldType = v ?? 'text'),
              ),
              if (fieldType == 'select' || fieldType == 'multi_select') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: optionsCtrl,
                  decoration: InputDecoration(
                    labelText: tr(context, 'pip_field_options'),
                    helperText: 'Comma separated',
                  ),
                  maxLines: 2,
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(tr(context, 'pip_required')),
                value: isRequired,
                onChanged: (v) => setDlg(() => isRequired = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (labelCtrl.text.trim().isEmpty) return;
                List<String>? options;
                if ((fieldType == 'select' || fieldType == 'multi_select') && optionsCtrl.text.trim().isNotEmpty) {
                  options = optionsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                }
                await state.createCustomField(CustomFieldPayload(
                  pipelineId: state.activePipeline?.id,
                  label: labelCtrl.text.trim(),
                  fieldType: fieldType,
                  options: options,
                  isRequired: isRequired,
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

  Color _statusColor(String st) => switch (st) {
        'won' => Colors.green,
        'lost' => Colors.red,
        'completed' => AppColors.primary,
        'cancelled' => Colors.grey,
        _ => AppColors.accent,
      };

  IconData _fieldTypeIcon(String ft) => switch (ft) {
        'number' || 'currency' => Icons.numbers,
        'date' => Icons.calendar_today,
        'boolean' => Icons.toggle_on,
        'select' || 'multi_select' => Icons.list_alt,
        'textarea' => Icons.subject,
        _ => Icons.text_fields,
      };
}
