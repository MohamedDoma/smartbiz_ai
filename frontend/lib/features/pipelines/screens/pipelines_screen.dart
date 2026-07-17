// SmartBiz AI — Pipelines screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/pipeline_models.dart';
import '../../../core/api/contact_models.dart';
import '../../../core/api/contact_service.dart';
import '../../../core/api/api_exceptions.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/modules/blueprint_navigation_controller.dart';
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

  /// Check if the current user has a specific permission.
  bool _hasPerm(BuildContext context, String key) {
    return context.read<BlueprintNavigationController>().effectivePermissions.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _hasPerm(context, 'pipelines.manage');
    final canCreateRecords = _hasPerm(context, 'pipeline_records.create');

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'pip_title')),
        actions: [
          if (canManage)
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
                if (canManage) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(tr(context, 'pip_create')),
                    onPressed: () => _showCreatePipelineDialog(context),
                  ),
                ],
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
                if (canManage) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: tr(context, 'pip_create'),
                    onPressed: () => _showCreatePipelineDialog(context),
                  ),
                ],
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
          if (state.activePipeline == null || state.stages.isEmpty || !canCreateRecords) return const SizedBox.shrink();
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

    // Customer selector state
    List<ApiContact> availableContacts = [];
    ApiContact? selectedContact;
    bool contactsLoading = true;
    bool contactsLoaded = false;
    String? contactsError;
    String contactSearch = '';

    // Quick-add customer state
    bool showAddForm = false;
    final newNameCtrl = TextEditingController();
    final newPhoneCtrl = TextEditingController();
    final newEmailCtrl = TextEditingController();
    bool addingSaving = false;
    String? addError;

    // Deal-creation error state
    String? dealError;

    // Load contacts — must be called after setDlg is available.
    final contactSvc = context.read<ContactService>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          // Kick off the load exactly once, now that setDlg is captured.
          if (!contactsLoaded && contactsLoading && contactsError == null) {
            contactSvc.listContacts(perPage: 100, type: 'customer').then((result) {
              availableContacts = result.data;
              contactsError = null;
            }).catchError((e) {
              contactsError = e.toString();
            }).whenComplete(() {
              contactsLoading = false;
              contactsLoaded = true;
              if (ctx.mounted) setDlg(() {});
            });
          }

          // Filter contacts
          final lowerSearch = contactSearch.toLowerCase();
          final filteredContacts = lowerSearch.isEmpty
              ? availableContacts
              : availableContacts.where((c) {
                  return c.name.toLowerCase().contains(lowerSearch) ||
                      (c.phone?.toLowerCase().contains(lowerSearch) ?? false) ||
                      (c.email?.toLowerCase().contains(lowerSearch) ?? false);
                }).toList();

          // Responsive width: use 90% of screen but cap at 400.
          final dialogWidth = MediaQuery.of(ctx).size.width * 0.9;
          final safeWidth = dialogWidth > 400.0 ? 400.0 : dialogWidth;
          // Cap the customer list at 30% of screen height to avoid overflow.
          final maxListH = MediaQuery.of(ctx).size.height * 0.3;
          final listHeight = maxListH > 150.0 ? 150.0 : maxListH;

          return AlertDialog(
            title: Text(tr(context, 'pip_create_record')),
            content: SizedBox(
              width: safeWidth,
              child: SingleChildScrollView(
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

                  // ── Customer selector ─────────────────────────
                  if (contactsLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (contactsError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(contactsError!, style: TextStyle(color: AppColors.error, fontSize: 13)),
                    )
                  else ...[
                    if (selectedContact != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: AppColors.primary,
                          child: Text(selectedContact!.name.isNotEmpty ? selectedContact!.name[0] : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        title: Text(selectedContact!.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(selectedContact!.phone ?? selectedContact!.email ?? '', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setDlg(() {
                            selectedContact = null;
                            dealError = null;
                          }),
                        ),
                        dense: true,
                      )
                    else if (showAddForm)
                      // ── Quick-add customer form ───────────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_add, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(tr(context, 'pip_add_customer'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setDlg(() {
                                  showAddForm = false;
                                  addError = null;
                                }),
                                tooltip: tr(context, 'cancel'),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: newNameCtrl,
                            decoration: InputDecoration(
                              labelText: '${tr(context, 'pip_customer_name')} *',
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: newPhoneCtrl,
                            decoration: InputDecoration(
                              labelText: tr(context, 'pip_customer_phone'),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: newEmailCtrl,
                            decoration: InputDecoration(
                              labelText: tr(context, 'pip_customer_email'),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          if (addError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(addError!, style: TextStyle(color: AppColors.error, fontSize: 12)),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              icon: addingSaving
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check, size: 16),
                              label: Text(addingSaving ? tr(context, 'pip_saving_customer') : tr(context, 'pip_save_record'),
                                  style: const TextStyle(fontSize: 13)),
                              onPressed: addingSaving ? null : () async {
                                if (newNameCtrl.text.trim().isEmpty) {
                                  setDlg(() => addError = tr(context, 'pip_customer_name_required'));
                                  return;
                                }
                                setDlg(() { addingSaving = true; addError = null; });
                                try {
                                  final created = await contactSvc.createContact(ContactPayload(
                                    name: newNameCtrl.text.trim(),
                                    type: 'customer',
                                    phone: newPhoneCtrl.text.trim().isNotEmpty ? newPhoneCtrl.text.trim() : null,
                                    email: newEmailCtrl.text.trim().isNotEmpty ? newEmailCtrl.text.trim() : null,
                                  ));
                                  // Auto-select the newly created customer
                                  availableContacts = [created, ...availableContacts];
                                  if (ctx.mounted) {
                                    setDlg(() {
                                      selectedContact = created;
                                      showAddForm = false;
                                      addingSaving = false;
                                    });
                                  }
                                } on ConflictException catch (ce) {
                                  if (ce.errorCode == 'contact_duplicate' && ce.existing != null) {
                                    // Visible duplicate — offer to use existing
                                    final existingName = ce.existing!['name'] as String? ?? '';
                                    final existingId = ce.existing!['id'] as String? ?? '';
                                    if (ctx.mounted) {
                                      setDlg(() {
                                        addingSaving = false;
                                        addError = '${tr(context, 'pip_dup_contact_visible')} ($existingName)';
                                      });
                                    }
                                    // Find or construct the existing contact
                                    final match = availableContacts.where((c) => c.id == existingId).toList();
                                    if (match.isNotEmpty) {
                                      if (ctx.mounted) {
                                        setDlg(() {
                                          selectedContact = match.first;
                                          showAddForm = false;
                                          addError = null;
                                        });
                                      }
                                    }
                                  } else {
                                    // Out of scope duplicate
                                    if (ctx.mounted) {
                                      setDlg(() {
                                        addingSaving = false;
                                        addError = tr(context, 'pip_dup_contact_outside_scope');
                                      });
                                    }
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setDlg(() {
                                      addingSaving = false;
                                      addError = e is ApiException ? e.message : e.toString();
                                    });
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      )
                    else
                      // ── Existing customer search ───────────────
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            decoration: InputDecoration(
                              labelText: tr(context, 'pip_select_customer'),
                              prefixIcon: const Icon(Icons.person_search, size: 20),
                              isDense: true,
                            ),
                            onChanged: (v) => setDlg(() => contactSearch = v),
                          ),
                          if (filteredContacts.isNotEmpty)
                            SizedBox(
                              height: listHeight,
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: filteredContacts.map((c) => ListTile(
                                    dense: true,
                                    title: Text(c.name, style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(c.phone ?? c.email ?? '', style: const TextStyle(fontSize: 11)),
                                    onTap: () => setDlg(() {
                                      selectedContact = c;
                                      contactSearch = '';
                                      dealError = null;
                                    }),
                                  )).toList(),
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),
                          // Quick-add toggle
                          InkWell(
                            onTap: () => setDlg(() {
                              showAddForm = true;
                              addError = null;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_add_alt_1, size: 16, color: AppColors.primary),
                                  const SizedBox(width: 6),
                                  Text(tr(context, 'pip_add_customer'),
                                      style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],

                  // ── Deal error banner ──────────────────────────
                  if (dealError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.error),
                            const SizedBox(width: 6),
                            Expanded(child: Text(dealError!, style: TextStyle(color: AppColors.error, fontSize: 12))),
                          ],
                        ),
                      ),
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
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
              FilledButton(
                onPressed: () async {
                  if (titleCtrl.text.trim().isEmpty || selectedStageId == null) return;
                  setDlg(() => dealError = null);
                  final rec = await state.createRecord(PipelineRecordPayload(
                    pipelineId: state.activePipeline!.id,
                    stageId: selectedStageId!,
                    title: titleCtrl.text.trim(),
                    contactId: selectedContact?.id,
                    valueAmount: double.tryParse(amountCtrl.text),
                    customValues: customValues.isNotEmpty ? customValues : null,
                  ));
                  if (rec != null && ctx.mounted) {
                    Navigator.pop(ctx);
                  } else if (ctx.mounted) {
                    // Check state.error for conflict codes
                    final err = state.error ?? '';
                    if (err.contains('open_deal_duplicate') || err.contains('open deal')) {
                      setDlg(() => dealError = tr(context, 'pip_dup_deal_visible'));
                    } else if (err.contains('outside_scope') || err.contains('another employee')) {
                      setDlg(() => dealError = tr(context, 'pip_dup_deal_outside_scope'));
                    } else if (err.isNotEmpty) {
                      setDlg(() => dealError = err);
                    }
                  }
                },
                child: Text(tr(context, 'pip_save_record')),
              ),
            ],
          );
        },
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

  /// Check if the current user has a specific permission.
  bool _hasPerm(BuildContext context, String key) {
    return context.read<BlueprintNavigationController>().effectivePermissions.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final canUpdate = _hasPerm(context, 'pipeline_records.update');
    final canDelete = _hasPerm(context, 'pipeline_records.delete');
    final canAssign = _hasPerm(context, 'pipeline_records.assign');

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
            } else if (val == '__assign__') {
              _showAssignDialog(context);
            } else if (val == '__delete__') {
              _confirmDelete(context);
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
            if (canAssign)
              PopupMenuItem(
                value: '__assign__',
                child: Row(children: [
                  const Icon(Icons.person_add_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(tr(context, 'pip_assign')),
                ]),
              ),
            if (canUpdate && _hasPerm(context, 'commissions.calculate'))
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
            if (canDelete)
              PopupMenuItem(
                value: '__delete__',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                  const SizedBox(width: 8),
                  Text(tr(context, 'delete'), style: TextStyle(color: AppColors.error)),
                ]),
              ),
            if (canUpdate) ...[
              const PopupMenuDivider(),
              ...stages
                  .where((s) => s.id != record.stageId && s.isActive)
                  .map((s) => PopupMenuItem(value: s.id, child: Text('→ ${s.name}'))),
            ],
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

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(context, 'delete')),
        content: Text('${tr(context, 'gen_confirm')} — ${record.title}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              state.deleteRecord(record.id);
              Navigator.pop(ctx);
            },
            child: Text(tr(context, 'delete')),
          ),
        ],
      ),
    );
  }

  void _showAssignDialog(BuildContext context) {
    final state = context.read<PipelineState>();
    state.loadAssignableMembers();
    String search = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          return AlertDialog(
            title: Text(tr(context, 'pip_assign_select')),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Consumer<PipelineState>(
                builder: (ctx2, ps, _) {
                  if (ps.assignableLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (ps.assignableError != null) {
                    return Center(child: Text(tr(context, 'pip_assign_error'), style: TextStyle(color: AppColors.error)));
                  }

                  final lower = search.toLowerCase();
                  final filtered = ps.assignableMembers.where((m) {
                    if (lower.isEmpty) return true;
                    final name = m.fullName.toLowerCase();
                    final role = (m.roleName ?? '').toLowerCase();
                    final dept = (m.department ?? '').toLowerCase();
                    return name.contains(lower) || role.contains(lower) || dept.contains(lower);
                  }).toList();

                  return Column(children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: tr(context, 'pip_assign_search'),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                      ),
                      onChanged: (v) => setDlg(() => search = v),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(child: Text(tr(context, 'pip_assign_no_results'), style: TextStyle(color: Colors.grey[500])))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx3, i) {
                                final m = filtered[i];
                                final isCurrentAssignee = record.assignedTo?.membershipId == m.membershipId;
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isCurrentAssignee ? AppColors.primary : Colors.grey[300],
                                    child: Text(
                                      m.fullName.isNotEmpty ? m.fullName[0].toUpperCase() : '?',
                                      style: TextStyle(color: isCurrentAssignee ? Colors.white : Colors.grey[700], fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text(
                                    [m.roleName, m.department].where((e) => e != null && e.isNotEmpty).join(' · '),
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  trailing: isCurrentAssignee ? Icon(Icons.check_circle, color: AppColors.primary, size: 20) : null,
                                  dense: true,
                                  onTap: () async {
                                    final updated = await state.updateRecord(record.id, {'assigned_membership_id': m.membershipId});
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(updated != null ? tr(context, 'pip_assigned_ok') : tr(context, 'pip_assign_failed'))),
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ]);
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'cancel'))),
            ],
          );
        },
      ),
    );
  }
}

