// SmartBiz AI — Duplicate matches screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/duplicate_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../duplicate_state.dart';

class DuplicateMatchesScreen extends StatefulWidget {
  const DuplicateMatchesScreen({super.key});
  @override
  State<DuplicateMatchesScreen> createState() => _DuplicateMatchesScreenState();
}

class _DuplicateMatchesScreenState extends State<DuplicateMatchesScreen> {
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DuplicateState>().loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_statusFilter != null
            ? '${tr(context, 'dup_matches')} (${_matchStatusLabel(context, _statusFilter!)})'
            : tr(context, 'dup_matches')),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (v) {
              setState(() => _statusFilter = v);
              context.read<DuplicateState>().loadMatches(status: v);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: null, child: Text(tr(context, 'all'))),
              ...kMatchStatuses.map((s) => PopupMenuItem(value: s, child: Text(_matchStatusLabel(context, s)))),
            ],
          ),
        ],
      ),
      body: Consumer<DuplicateState>(
        builder: (ctx, state, _) {
          if (state.loading && state.matches.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.matches.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.done_all, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(tr(context, 'dup_no_duplicates'), style: TextStyle(color: Colors.grey[600], fontSize: 16)),
              ]),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: state.matches.length,
            itemBuilder: (ctx, i) => _MatchCard(match: state.matches[i], state: state),
          );
        },
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final DuplicateMatch match;
  final DuplicateState state;
  const _MatchCard({required this.match, required this.state});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(
              child: Text(
                match.rule?['name'] ?? tr(context, 'dup_rule'),
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(match.status).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _matchStatusLabel(context, match.status),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _statusColor(match.status)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${tr(context, 'dup_entity_type')}: ${_entityLabel(context, match.entityType)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text('${tr(context, 'dup_source_entity')}: ${match.sourceEntityId.substring(0, 8)}…',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Text('${tr(context, 'dup_matched_entity')}: ${match.matchedEntityId.substring(0, 8)}…',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          if (match.matchFields != null)
            Text('${tr(context, 'dup_match_fields')}: ${match.matchFields!.join(", ")}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          if (match.resolution != null)
            Text('${tr(context, 'dup_resolve_match')}: ${_resolutionLabel(context, match.resolution!)}',
                style: TextStyle(fontSize: 11, color: AppColors.primary)),

          if (match.status == 'open') ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              ActionChip(
                label: Text(tr(context, 'dup_keep_separate'), style: const TextStyle(fontSize: 12)),
                onPressed: () => state.resolveMatch(match.id, resolution: 'keep_separate'),
              ),
              ActionChip(
                label: Text(tr(context, 'dup_confirmed'), style: const TextStyle(fontSize: 12)),
                onPressed: () => state.resolveMatch(match.id, resolution: 'duplicate_confirmed'),
              ),
              ActionChip(
                label: Text(tr(context, 'dup_merged_later'), style: const TextStyle(fontSize: 12)),
                onPressed: () => state.resolveMatch(match.id, resolution: 'merged_later'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

String _matchStatusLabel(BuildContext context, String s) => switch (s) {
      'open' => tr(context, 'dup_open'),
      'ignored' => tr(context, 'dup_ignored'),
      'resolved' => tr(context, 'dup_resolved'),
      _ => s,
    };

String _entityLabel(BuildContext context, String t) => switch (t) {
      'contact' => tr(context, 'dup_contact'),
      'pipeline_record' => tr(context, 'dup_pipeline_record'),
      _ => t,
    };

String _resolutionLabel(BuildContext context, String r) => switch (r) {
      'keep_separate' => tr(context, 'dup_keep_separate'),
      'duplicate_confirmed' => tr(context, 'dup_confirmed'),
      'merged_later' => tr(context, 'dup_merged_later'),
      _ => r,
    };

Color _statusColor(String s) => switch (s) {
      'open' => Colors.orange,
      'resolved' => Colors.green,
      'ignored' => Colors.grey,
      _ => Colors.grey,
    };
