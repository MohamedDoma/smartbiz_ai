// SmartBiz AI — Commission entries screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/commission_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../commission_state.dart';

class CommissionEntriesScreen extends StatefulWidget {
  const CommissionEntriesScreen({super.key});
  @override
  State<CommissionEntriesScreen> createState() => _CommissionEntriesScreenState();
}

class _CommissionEntriesScreenState extends State<CommissionEntriesScreen> {
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CommissionState>().loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_statusFilter != null
            ? '${tr(context, 'comm_entries')} (${_statusLabel(context, _statusFilter!)})'
            : tr(context, 'comm_entries')),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: tr(context, 'comm_trigger_status'),
            onSelected: (v) {
              setState(() => _statusFilter = v);
              context.read<CommissionState>().loadEntries(status: v);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: Text(tr(context, 'all'))),
              ...kEntryStatuses.map((s) => PopupMenuItem(value: s, child: Text(_statusLabel(context, s)))),
            ],
          ),
        ],
      ),
      body: Consumer<CommissionState>(
        builder: (ctx, state, _) {
          if (state.loading && state.entries.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.entries.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'comm_no_commissions'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.entries.length,
            itemBuilder: (ctx, i) => _EntryCard(entry: state.entries[i], state: state),
          );
        },
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final CommissionEntry entry;
  final CommissionState state;
  const _EntryCard({required this.entry, required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header: record + amount
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(
                entry.record?['title'] ?? entry.pipelineRecordId,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(entry.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusLabel(context, entry.status),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(entry.status)),
              ),
            ),
          ]),
          const SizedBox(height: 8),

          // Amount details
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${tr(context, 'comm_base_amount')}: ${entry.baseAmount} ${entry.currency}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                Text(
                  '${tr(context, 'comm_amount')}: ${entry.commissionAmount} ${entry.currency}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ]),
            ),
            if (entry.calculationType == 'percentage' && entry.percentageRate != null)
              Chip(
                label: Text('${entry.percentageRate}%', style: const TextStyle(fontSize: 12)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ]),
          const SizedBox(height: 6),

          // Recipient
          if (entry.recipient != null)
            Text('${tr(context, 'comm_recipient')}: ${entry.recipient!['full_name'] ?? ''}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (entry.plan != null)
            Text('${entry.plan!['name'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),

          // Actions
          if (entry.status == 'pending' || entry.status == 'approved') ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (entry.status == 'pending')
                TextButton.icon(
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(tr(context, 'comm_approve'), style: const TextStyle(fontSize: 12)),
                  onPressed: () => state.markApproved(entry.id),
                ),
              if (entry.status == 'pending' || entry.status == 'approved')
                TextButton.icon(
                  icon: const Icon(Icons.payment, size: 16),
                  label: Text(tr(context, 'comm_mark_paid'), style: const TextStyle(fontSize: 12)),
                  onPressed: () => state.markPaid(entry.id),
                ),
              TextButton.icon(
                icon: Icon(Icons.cancel_outlined, size: 16, color: Colors.red[300]),
                label: Text(tr(context, 'comm_cancel'), style: TextStyle(fontSize: 12, color: Colors.red[300])),
                onPressed: () => state.cancelEntry(entry.id),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

String _statusLabel(BuildContext context, String s) => switch (s) {
      'pending' => tr(context, 'comm_pending'),
      'approved' => tr(context, 'comm_approved'),
      'paid' => tr(context, 'comm_paid'),
      'cancelled' => tr(context, 'comm_cancelled'),
      _ => s,
    };

Color _statusColor(String s) => switch (s) {
      'pending' => Colors.orange,
      'approved' => Colors.blue,
      'paid' => Colors.green,
      'cancelled' => Colors.grey,
      _ => Colors.grey,
    };
