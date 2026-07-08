// SmartBiz AI — Document Checklists settings screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/document_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../document_state.dart';

class DocumentChecklistsScreen extends StatefulWidget {
  const DocumentChecklistsScreen({super.key});
  @override
  State<DocumentChecklistsScreen> createState() => _DocumentChecklistsScreenState();
}

class _DocumentChecklistsScreenState extends State<DocumentChecklistsScreen> {
  String? _selectedChecklistId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DocumentState>().loadChecklists();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'doc_checklists'))),
      body: Consumer<DocumentState>(
        builder: (ctx, state, _) {
          if (state.loading && state.checklists.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.checklists.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.checklist_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'doc_no_checklists'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'doc_create_checklist')),
                  onPressed: () => _showCreateChecklistDialog(context, state),
                ),
              ]),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Checklist list
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr(context, 'doc_checklists'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => _showCreateChecklistDialog(context, state),
                ),
              ]),
              ...state.checklists.map((cl) => Card(
                    color: _selectedChecklistId == cl.id ? AppColors.primary.withValues(alpha: 0.08) : null,
                    child: ListTile(
                      leading: Icon(Icons.checklist, color: cl.isActive ? AppColors.accent : Colors.grey),
                      title: Text(cl.name),
                      subtitle: Text(
                        [
                          if (cl.pipeline != null) cl.pipeline!['name'],
                          if (cl.stage != null) cl.stage!['name'],
                          '${cl.itemsCount ?? 0} ${tr(context, 'doc_items')}',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      trailing: cl.isActive
                          ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                          : const Icon(Icons.cancel, color: Colors.grey, size: 18),
                      onTap: () {
                        setState(() => _selectedChecklistId = cl.id);
                        state.loadItems(cl.id);
                      },
                    ),
                  )),

              if (_selectedChecklistId != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                // Items for selected checklist
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(tr(context, 'doc_checklist_items'), style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => _showCreateItemDialog(context, state, _selectedChecklistId!),
                  ),
                ]),
                if (state.items.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'doc_no_items')))
                else
                  ...state.items.map((item) => Card(
                        child: ListTile(
                          leading: Icon(
                            item.isRequired ? Icons.warning_amber : Icons.description_outlined,
                            color: item.isRequired ? Colors.orange : Colors.grey,
                          ),
                          title: Text(item.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.isRequired ? tr(context, 'doc_required') : tr(context, 'doc_optional'),
                                style: TextStyle(fontSize: 12, color: item.isRequired ? Colors.orange[700] : Colors.grey[600]),
                              ),
                              if (item.acceptedFileTypes != null && item.acceptedFileTypes!.isNotEmpty)
                                Text('${tr(context, 'doc_accepted_types')}: ${item.acceptedFileTypes!.join(", ")}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              if (item.maxFileSizeMb != null)
                                Text('${tr(context, 'doc_max_size')}: ${item.maxFileSizeMb}MB',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      )),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showCreateChecklistDialog(BuildContext context, DocumentState state) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'doc_create_checklist')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(labelText: tr(context, 'doc_checklist_name')),
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
              await state.createChecklist(DocumentChecklistPayload(
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

  void _showCreateItemDialog(BuildContext context, DocumentState state, String checklistId) {
    final titleCtrl = TextEditingController();
    final typesCtrl = TextEditingController();
    bool isRequired = true;
    int maxSize = 10;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'doc_create_item')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: tr(context, 'doc_item_title')),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(tr(context, 'doc_required')),
                value: isRequired,
                onChanged: (v) => setDlg(() => isRequired = v),
              ),
              TextField(
                controller: typesCtrl,
                decoration: InputDecoration(
                  labelText: tr(context, 'doc_accepted_types'),
                  helperText: 'pdf, jpg, png, docx',
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Text('${tr(context, 'doc_max_size')}: ${maxSize}MB'),
                Expanded(
                  child: Slider(
                    value: maxSize.toDouble(),
                    min: 1, max: 50,
                    divisions: 49,
                    onChanged: (v) => setDlg(() => maxSize = v.round()),
                  ),
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                List<String>? types;
                if (typesCtrl.text.trim().isNotEmpty) {
                  types = typesCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                }
                await state.createItem(checklistId, DocumentChecklistItemPayload(
                  title: titleCtrl.text.trim(),
                  isRequired: isRequired,
                  acceptedFileTypes: types,
                  maxFileSizeMb: maxSize,
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
