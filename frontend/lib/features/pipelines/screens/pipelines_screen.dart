// SmartBiz AI — Pipelines screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/pipeline_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../pipeline_state.dart';
import '../../commissions/commission_state.dart';
import '../../duplicates/duplicate_state.dart';
import '../../ownership/ownership_state.dart';
import '../../../core/api/duplicate_models.dart';

class PipelinesScreen extends StatefulWidget {
  const PipelinesScreen({super.key});
  @override
  State<PipelinesScreen> createState() => _PipelinesScreenState();
}

class _PipelinesScreenState extends State<PipelinesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PipelineState>().loadPipelines();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'pip_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr(context, 'pip_settings'),
            onPressed: () => Navigator.of(context).pushNamed('/pipelines/settings'),
          ),
        ],
      ),
      body: Consumer<PipelineState>(
        builder: (ctx, state, _) {
          if (state.loading && state.pipelines.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.pipelines.isEmpty) {
            return Center(child: Text(state.error!, style: TextStyle(color: AppColors.error)));
          }
          if (state.pipelines.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.linear_scale, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'pip_no_pipelines'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(tr(context, 'pip_create')),
                  onPressed: () => _showCreatePipelineDialog(context),
                ),
              ]),
            );
          }
          return Column(children: [
            // Pipeline selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: state.activePipeline?.id,
                    decoration: InputDecoration(labelText: tr(context, 'pip_select'), isDense: true),
                    items: state.pipelines.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final p = state.pipelines.firstWhere((e) => e.id == id);
                      state.selectPipeline(p);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: tr(context, 'pip_create'),
                  onPressed: () => _showCreatePipelineDialog(context),
                ),
              ]),
            ),
            const Divider(height: 1),
            // Stage tabs + records
            if (state.stages.isEmpty)
              Expanded(child: Center(child: Text(tr(context, 'pip_no_stages'), style: TextStyle(color: Colors.grey[600]))))
            else
              Expanded(child: _StageRecordView(stages: state.stages, state: state)),
          ]);
        },
      ),
      floatingActionButton: Consumer<PipelineState>(
        builder: (ctx, state, _) {
          if (state.activePipeline == null || state.stages.isEmpty) return const SizedBox.shrink();
          return FloatingActionButton(
            onPressed: () => _showCreateRecordDialog(context, state),
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  void _showCreatePipelineDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'pip_create')),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(labelText: tr(context, 'pip_name')),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final state = context.read<PipelineState>();
              final p = await state.createPipeline(PipelinePayload(name: nameCtrl.text.trim()));
              if (p != null) await state.selectPipeline(p);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr(context, 'create')),
          ),
        ],
      ),
    );
  }

  void _showCreateRecordDialog(BuildContext context, PipelineState state) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String? selectedStageId = state.stages.isNotEmpty ? state.stages.first.id : null;
    final customValues = <String, dynamic>{};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(context, 'pip_create_record')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(labelText: tr(context, 'pip_record_title')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: selectedStageId,
                decoration: InputDecoration(labelText: tr(context, 'pip_select_stage')),
                items: state.stages.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                onChanged: (v) => setDlg(() => selectedStageId = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                decoration: InputDecoration(labelText: tr(context, 'pip_value_amount')),
                keyboardType: TextInputType.number,
              ),
              // Custom fields
              ...state.customFields.where((f) => f.isActive).map((f) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _buildFieldInput(f, customValues, setDlg),
                  )),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            FilledButton(
              onPressed: () async {
                if (titleCtrl.text.trim().isEmpty || selectedStageId == null) return;
                final rec = await state.createRecord(PipelineRecordPayload(
                  pipelineId: state.activePipeline!.id,
                  stageId: selectedStageId!,
                  title: titleCtrl.text.trim(),
                  valueAmount: double.tryParse(amountCtrl.text),
                  customValues: customValues.isNotEmpty ? customValues : null,
                ));
                if (rec != null && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr(context, 'pip_save_record')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldInput(CustomField f, Map<String, dynamic> values, StateSetter setDlg) {
    final key = f.fieldKey ?? f.id;
    switch (f.fieldType) {
      case 'select':
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: '${f.label}${f.isRequired ? " *" : ""}'),
          items: f.options?.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList() ?? [],
          onChanged: (v) => setDlg(() => values[key] = v),
        );
      case 'boolean':
        return SwitchListTile(
          title: Text(f.label),
          value: values[key] == true,
          onChanged: (v) => setDlg(() => values[key] = v),
        );
      case 'number':
      case 'currency':
        return TextField(
          decoration: InputDecoration(labelText: '${f.label}${f.isRequired ? " *" : ""}'),
          keyboardType: TextInputType.number,
          onChanged: (v) => values[key] = double.tryParse(v),
        );
      default:
        return TextField(
          decoration: InputDecoration(labelText: '${f.label}${f.isRequired ? " *" : ""}'),
          onChanged: (v) => values[key] = v,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════
//  Stage-based record view
// ═══════════════════════════════════════════════════════

class _StageRecordView extends StatefulWidget {
  final List<PipelineStage> stages;
  final PipelineState state;
  const _StageRecordView({required this.stages, required this.state});
  @override
  State<_StageRecordView> createState() => _StageRecordViewState();
}

class _StageRecordViewState extends State<_StageRecordView> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: widget.stages.length, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _StageRecordView old) {
    super.didUpdateWidget(old);
    if (old.stages.length != widget.stages.length) {
      _tabCtrl.dispose();
      _tabCtrl = TabController(length: widget.stages.length, vsync: this);
    }
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabs: widget.stages.map((s) {
          final count = widget.state.recordsForStage(s.id).length;
          return Tab(text: '${s.name} ($count)');
        }).toList(),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          children: widget.stages.map((s) {
            final recs = widget.state.recordsForStage(s.id);
            if (recs.isEmpty) {
              return Center(child: Text(tr(context, 'pip_no_records'), style: TextStyle(color: Colors.grey[500])));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: recs.length,
              itemBuilder: (ctx, i) => _RecordCard(record: recs[i], stages: widget.stages, state: widget.state),
            );
          }).toList(),
        ),
      ),
    ]);
  }
}

class _RecordCard extends StatelessWidget {
  final PipelineRecord record;
  final List<PipelineStage> stages;
  final PipelineState state;
  const _RecordCard({required this.record, required this.stages, required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        title: Text(record.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.valueAmount != null)
              Text('${record.currency ?? ""} ${record.valueAmount}',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
            if (record.assignedTo != null)
              Text(record.assignedTo!.fullName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            if (record.customValues != null && record.customValues!.isNotEmpty)
              Wrap(
                spacing: 6,
                children: record.customValues!.entries.map((e) =>
                    Chip(label: Text('${e.value.label ?? e.key}: ${e.value.value}', style: const TextStyle(fontSize: 11)),
                        visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap)).toList(),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: tr(context, 'pip_move_record'),
          onSelected: (val) {
            if (val == '__documents__') {
              Navigator.of(context).pushNamed('/pipeline-records/${record.id}/documents');
            } else if (val == '__calculate_commission__') {
              _calculateCommission(context);
            } else if (val == '__check_duplicate__') {
              _checkDuplicate(context);
            } else if (val == '__resolve_owner__') {
              _resolveOwner(context);
            } else {
              state.moveRecord(record.id, val);
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: '__documents__',
              child: Row(children: [
                const Icon(Icons.description_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tr(context, 'doc_record_documents')),
              ]),
            ),
            PopupMenuItem(
              value: '__calculate_commission__',
              child: Row(children: [
                const Icon(Icons.monetization_on_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tr(context, 'comm_calculate')),
              ]),
            ),
            PopupMenuItem(
              value: '__check_duplicate__',
              child: Row(children: [
                const Icon(Icons.content_copy_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tr(context, 'dup_check')),
              ]),
            ),
            PopupMenuItem(
              value: '__resolve_owner__',
              child: Row(children: [
                const Icon(Icons.person_search_outlined, size: 18),
                const SizedBox(width: 8),
                Text(tr(context, 'own_resolve')),
              ]),
            ),
            const PopupMenuDivider(),
            ...stages
                .where((s) => s.id != record.stageId && s.isActive)
                .map((s) => PopupMenuItem(value: s.id, child: Text('→ ${s.name}'))),
          ],
          icon: const Icon(Icons.more_vert, size: 20),
        ),
        isThreeLine: true,
      ),
    );
  }

  void _calculateCommission(BuildContext context) async {
    final commState = context.read<CommissionState>();
    final result = await commState.calculateForRecord(record.id);
    if (context.mounted) {
      final msg = result != null
          ? '${tr(context, 'comm_calculated')} (${result.createdCount})'
          : tr(context, 'comm_load_failed');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _checkDuplicate(BuildContext context) async {
    final dupState = context.read<DuplicateState>();
    final result = await dupState.checkDuplicate(DuplicateCheckPayload(
      entityType: 'pipeline_record',
      payload: {'title': record.title},
      excludeEntityId: record.id,
    ));
    if (context.mounted) {
      final count = result?.matches.length ?? 0;
      final msg = count > 0
          ? '${tr(context, 'dup_found')} ($count)'
          : tr(context, 'dup_no_duplicates');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _resolveOwner(BuildContext context) async {
    final ownState = context.read<OwnershipState>();
    final result = await ownState.resolveOwnership('pipeline_record', record.id);
    if (context.mounted) {
      final name = result?.owner?['full_name'] ?? '—';
      final src = result?.source ?? 'none';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tr(context, 'own_owner')}: $name ($src)')),
      );
    }
  }
}

