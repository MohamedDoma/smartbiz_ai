// SmartBiz AI — Report results screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../report_state.dart';

class ReportResultsScreen extends StatelessWidget {
  const ReportResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'rpt_results'))),
      body: Consumer<ReportState>(builder: (ctx, state, _) {
        final result = state.lastResult;
        if (result == null) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.table_chart_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'rpt_no_results'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            ]),
          );
        }

        final summary = result.summary;

        return Column(children: [
          // Summary bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Wrap(spacing: 16, runSpacing: 8, children: [
              _SummaryChip(label: tr(context, 'rpt_row_count'), value: '${summary.rowCount}'),
              if (summary.generatedAt != null)
                _SummaryChip(label: tr(context, 'rpt_generated_at'), value: summary.generatedAt!.split('T').first),
              if (summary.totals != null)
                ...summary.totals!.entries.map((e) => _SummaryChip(label: e.key, value: e.value)),
            ]),
          ),

          // Status counts
          if (summary.statusCounts != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                Text('${tr(context, 'rpt_status_counts')}:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ...summary.statusCounts!.entries.expand((col) => col.value.entries
                    .map((e) => Chip(
                          label: Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                        ))),
              ]),
            ),

          // Data table
          Expanded(
            child: result.rows.isEmpty
                ? Center(child: Text(tr(context, 'rpt_no_results'), style: TextStyle(color: Colors.grey[500])))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columnSpacing: 20,
                        columns: result.columns.map((col) => DataColumn(label: Text(col, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)))).toList(),
                        rows: result.rows.map((row) {
                          return DataRow(
                            cells: result.columns.map((col) {
                              final val = row[col]?.toString() ?? '';
                              return DataCell(Text(val, style: const TextStyle(fontSize: 13)));
                            }).toList(),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ]);
      }),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label: $value', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    );
  }
}
