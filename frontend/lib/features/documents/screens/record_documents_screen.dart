// SmartBiz AI — Record Documents screen (per pipeline record).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/document_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../document_state.dart';

class RecordDocumentsScreen extends StatefulWidget {
  final String recordId;
  const RecordDocumentsScreen({super.key, required this.recordId});
  @override
  State<RecordDocumentsScreen> createState() => _RecordDocumentsScreenState();
}

class _RecordDocumentsScreenState extends State<RecordDocumentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<DocumentState>();
      state.loadDocumentStatus(widget.recordId);
      state.loadDocuments(widget.recordId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'doc_record_documents'))),
      body: Consumer<DocumentState>(
        builder: (ctx, state, _) {
          if (state.loading && state.documentStatus == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.documentStatus == null) {
            return Center(child: Text(state.error!, style: TextStyle(color: AppColors.error)));
          }

          final st = state.documentStatus;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status summary
              if (st != null) ...[
                Card(
                  color: st.missingCount > 0 ? Colors.orange.withValues(alpha: 0.08) : Colors.green.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(st.recordTitle ?? '', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 12),
                      Row(children: [
                        _CountChip(label: tr(context, 'doc_required_count'), count: st.requiredCount, color: Colors.blue),
                        const SizedBox(width: 8),
                        _CountChip(label: tr(context, 'doc_completed_count'), count: st.completedCount, color: Colors.green),
                        const SizedBox(width: 8),
                        _CountChip(label: tr(context, 'doc_missing_count'), count: st.missingCount, color: Colors.orange),
                      ]),
                      if (st.missingCount > 0) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(tr(context, 'doc_missing_warning'), style: TextStyle(color: Colors.orange[800], fontSize: 13))),
                        ]),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // Document items list
                Text(tr(context, 'doc_status'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...st.items.map((item) => _DocumentItemCard(
                      item: item,
                      recordId: widget.recordId,
                      state: state,
                    )),
              ],

              const SizedBox(height: 24),

              // Provided documents
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr(context, 'doc_provided_documents'), style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: tr(context, 'doc_provide'),
                  onPressed: () => _showProvideDialog(context, state, null),
                ),
              ]),
              if (state.documents.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(tr(context, 'doc_no_documents')))
              else
                ...state.documents.map((doc) => Card(
                      child: ListTile(
                        leading: Icon(_statusIcon(doc.status), color: _statusColor(doc.status)),
                        title: Text(doc.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(doc.status.toUpperCase(), style: TextStyle(fontSize: 11, color: _statusColor(doc.status), fontWeight: FontWeight.w600)),
                            if (doc.originalFilename != null)
                              Text('📎 ${doc.originalFilename}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (doc.externalReference != null)
                              Text('🔗 ${doc.externalReference}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                            if (doc.notes != null && doc.notes!.isNotEmpty)
                              Text(doc.notes!, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }

  void _showProvideDialog(BuildContext context, DocumentState state, String? checklistItemId) {
    final titleCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String status = 'provided';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'doc_provide')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: tr(context, 'doc_item_title')),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(labelText: tr(context, 'doc_status')),
                items: const [
                  DropdownMenuItem(value: 'provided', child: Text('Provided')),
                  DropdownMenuItem(value: 'waived', child: Text('Waived')),
                ],
                onChanged: (v) => setDlg(() => status = v ?? 'provided'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: refCtrl,
                decoration: InputDecoration(labelText: tr(context, 'doc_external_ref')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(labelText: tr(context, 'doc_notes')),
                maxLines: 3,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty) return;
                await state.provideDocument(widget.recordId, RecordDocumentPayload(
                  documentChecklistItemId: checklistItemId,
                  title: titleCtrl.text.trim(),
                  status: status,
                  externalReference: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
                  notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'doc_provide')),
            ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(String st) => switch (st) {
        'uploaded' => Icons.cloud_done,
        'provided' => Icons.check_circle,
        'waived' => Icons.skip_next,
        _ => Icons.help_outline,
      };

  Color _statusColor(String st) => switch (st) {
        'uploaded' => Colors.green,
        'provided' => AppColors.primary,
        'waived' => Colors.grey,
        'missing' => Colors.orange,
        _ => Colors.grey,
      };
}

// ═══════════════════════════════════════════════════════
//  Reusable widgets
// ═══════════════════════════════════════════════════════

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $count', style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _DocumentItemCard extends StatelessWidget {
  final DocumentStatusItem item;
  final String recordId;
  final DocumentState state;
  const _DocumentItemCard({required this.item, required this.recordId, required this.state});

  @override
  Widget build(BuildContext context) {
    final isMissing = item.status == 'missing';
    return Card(
      color: isMissing && item.isRequired ? Colors.orange.withValues(alpha: 0.05) : null,
      child: ListTile(
        leading: Icon(
          isMissing ? Icons.warning_amber : Icons.check_circle,
          color: isMissing ? Colors.orange : Colors.green,
        ),
        title: Text(item.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(
                item.isRequired ? tr(context, 'doc_required') : tr(context, 'doc_optional'),
                style: TextStyle(fontSize: 11, color: item.isRequired ? Colors.orange[700] : Colors.grey[600]),
              ),
              if (item.checklist != null) ...[
                const Text(' · ', style: TextStyle(fontSize: 11)),
                Text(item.checklist!, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ]),
            Text(item.status.toUpperCase(),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isMissing ? Colors.orange : Colors.green)),
          ],
        ),
        trailing: isMissing
            ? TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: Text(tr(context, 'doc_provide'), style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  final screen = context.findAncestorStateOfType<_RecordDocumentsScreenState>();
                  screen?._showProvideDialog(context, state, item.itemId);
                },
              )
            : null,
      ),
    );
  }
}
