// SmartBiz AI — Report templates screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/report_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../report_state.dart';

class ReportTemplatesScreen extends StatefulWidget {
  const ReportTemplatesScreen({super.key});
  @override
  State<ReportTemplatesScreen> createState() => _ReportTemplatesScreenState();
}

class _ReportTemplatesScreenState extends State<ReportTemplatesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<ReportState>();
      s.loadTemplates();
      s.loadCatalog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'rpt_templates')),
        actions: [
          IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _showCreateDialog(context)),
        ],
      ),
      body: Consumer<ReportState>(builder: (ctx, state, _) {
        if (state.loading && state.templates.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.templates.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'rpt_no_reports'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr(context, 'rpt_create_template')),
                onPressed: () => _showCreateDialog(context),
              ),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.templates.length,
          itemBuilder: (ctx, i) {
            final t = state.templates[i];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${tr(context, 'rpt_data_source')}: ${t.dataSource}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  Text('${tr(context, 'rpt_columns')}: ${t.columns.join(", ")}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (t.description != null)
                    Text(t.description!, style: TextStyle(fontSize: 11, color: Colors.grey[500], fontStyle: FontStyle.italic)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Colors.green),
                    onPressed: () async {
                      final result = await state.runTemplate(t.id);
                      if (result != null && context.mounted) {
                        Navigator.of(context).pushNamed('/reports/results');
                      }
                    },
                    tooltip: tr(context, 'rpt_run_report'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => state.deleteTemplate(t.id),
                    tooltip: tr(context, 'delete'),
                  ),
                ]),
              ),
            );
          },
        );
      }),
    );
  }

  void _showCreateDialog(BuildContext context) {
    final state = context.read<ReportState>();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String? dataSource;
    final selectedCols = <String>{};
    ReportDataSource? dsDetail;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) {
        return AlertDialog(
          title: Text(tr(context, 'rpt_create_template')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'rpt_name')),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(labelText: tr(context, 'rpt_description')),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: tr(context, 'rpt_data_source')),
                  items: state.catalog
                      .map((ds) => DropdownMenuItem(value: ds.key, child: Text(ds.displayName)))
                      .toList(),
                  onChanged: (v) async {
                    if (v == null) return;
                    dataSource = v;
                    selectedCols.clear();
                    await state.loadDataSource(v);
                    dsDetail = state.activeDataSource;
                    setDlg(() {});
                  },
                ),
                const SizedBox(height: 8),
                if (dsDetail != null) ...[
                  Text(tr(context, 'rpt_select_columns'), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: dsDetail!.columns
                        .map((col) => FilterChip(
                              label: Text(col.label, style: const TextStyle(fontSize: 12)),
                              selected: selectedCols.contains(col.key),
                              onSelected: (v) => setDlg(() {
                                if (v) {
                                  selectedCols.add(col.key);
                                } else {
                                  selectedCols.remove(col.key);
                                }
                              }),
                            ))
                        .toList(),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || dataSource == null || selectedCols.isEmpty) return;
                await state.createTemplate(ReportTemplatePayload(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  dataSource: dataSource!,
                  columns: selectedCols.toList(),
                  visibility: 'workspace',
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'create')),
            ),
          ],
        );
      }),
    );
  }
}
