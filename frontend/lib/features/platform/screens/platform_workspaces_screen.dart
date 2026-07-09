// SmartBiz AI — Platform Workspaces screen (Step 58).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../platform_state.dart';

class PlatformWorkspacesScreen extends StatefulWidget {
  const PlatformWorkspacesScreen({super.key});

  @override
  State<PlatformWorkspacesScreen> createState() => _PlatformWorkspacesScreenState();
}

class _PlatformWorkspacesScreenState extends State<PlatformWorkspacesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<PlatformState>().loadWorkspaces());
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlatformState>();

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'plt_workspaces'))),
      body: state.wsLoading
          ? const Center(child: CircularProgressIndicator())
          : state.workspaces.isEmpty
              ? Center(child: Text(tr(context, 'plt_no_data')))
              : RefreshIndicator(
                  onRefresh: () => state.loadWorkspaces(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.workspaces.length,
                    itemBuilder: (context, i) {
                      final w = state.workspaces[i];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.business),
                          title: Text(w.name),
                          subtitle: Text(
                            '${tr(context, 'plt_status')}: ${w.status ?? '—'} · '
                            '${tr(context, 'plt_subscription')}: ${w.subscriptionStatus ?? '—'} · '
                            '${tr(context, 'plt_members')}: ${w.membersCount ?? '—'}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) => _updateStatus(w.id, v),
                            itemBuilder: (_) => [
                              PopupMenuItem(value: 'active', child: Text(tr(context, 'plt_activate'))),
                              PopupMenuItem(value: 'suspended', child: Text(tr(context, 'plt_suspend'))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _updateStatus(String id, String status) async {
    try {
      await context.read<PlatformState>().updateWorkspaceStatus(id, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}
