// SmartBiz AI — Platform Users screen (Step 58).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_spacing.dart';
import '../platform_state.dart';

class PlatformUsersScreen extends StatefulWidget {
  const PlatformUsersScreen({super.key});

  @override
  State<PlatformUsersScreen> createState() => _PlatformUsersScreenState();
}

class _PlatformUsersScreenState extends State<PlatformUsersScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<PlatformState>().loadUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PlatformState>();

    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'plt_users'))),
      body: state.usersLoading
          ? const Center(child: CircularProgressIndicator())
          : state.users.isEmpty
              ? Center(child: Text(tr(context, 'plt_no_data')))
              : RefreshIndicator(
                  onRefresh: () => state.loadUsers(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.users.length,
                    itemBuilder: (context, i) {
                      final u = state.users[i];
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            u.isSuperAdmin ? Icons.admin_panel_settings : Icons.person,
                            color: u.isSuperAdmin ? Theme.of(context).colorScheme.primary : null,
                          ),
                          title: Text(u.fullName),
                          subtitle: Text(u.email),
                          trailing: Switch(
                            value: u.isSuperAdmin,
                            onChanged: (v) => _confirmToggle(u, v),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _confirmToggle(dynamic user, bool value) {
    final action = value ? tr(context, 'plt_make_admin') : tr(context, 'plt_remove_admin');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action),
        content: Text('${user.fullName} — ${user.email}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'gen_cancel'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<PlatformState>().togglePlatformAdmin(user.id, value);
            },
            child: Text(tr(context, 'gen_confirm')),
          ),
        ],
      ),
    );
  }
}
