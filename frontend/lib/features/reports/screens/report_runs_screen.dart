// SmartBiz AI — Report runs history screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../report_state.dart';

class ReportRunsScreen extends StatefulWidget {
  const ReportRunsScreen({super.key});
  @override
  State<ReportRunsScreen> createState() => _ReportRunsScreenState();
}

class _ReportRunsScreenState extends State<ReportRunsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReportState>().loadRuns();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'rpt_runs'))),
      body: Consumer<ReportState>(builder: (ctx, state, _) {
        if (state.loading && state.runs.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.runs.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(tr(context, 'rpt_no_reports'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
            ]),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.runs.length,
          itemBuilder: (ctx, i) {
            final run = state.runs[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  run.status == 'completed' ? Icons.check_circle : Icons.error,
                  color: run.status == 'completed' ? Colors.green : Colors.red,
                ),
                title: Text(
                  run.template?['name'] as String? ?? run.dataSource,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${tr(context, 'rpt_data_source')}: ${run.dataSource} · ${tr(context, 'rpt_row_count')}: ${run.rowCount}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (run.startedAt != null)
                    Text(run.startedAt!.split('T').first, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  if (run.errorMessage != null)
                    Text(run.errorMessage!, style: const TextStyle(fontSize: 11, color: Colors.red)),
                ]),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (run.status == 'completed' ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    run.status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: run.status == 'completed' ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
