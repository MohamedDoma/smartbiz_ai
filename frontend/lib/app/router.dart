/// SmartBiz AI — App router.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/navigation/nav_model.dart';
import '../core/navigation/shell_state.dart';
import '../features/ai_chat/ai_chat_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../shared/layout/app_shell.dart';

final appRouter = GoRouter(
  initialLocation: '/dashboard',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(child: child);
      },
      routes: [
        GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) {
            _syncIndex(context, 0);
            return const NoTransitionPage(child: DashboardScreen());
          },
        ),
        GoRoute(
          path: '/ai-chat',
          pageBuilder: (context, state) {
            _syncIndex(context, 1);
            return const NoTransitionPage(child: AiChatScreen());
          },
        ),
        GoRoute(
          path: '/advisor',
          pageBuilder: (context, state) {
            _syncIndex(context, 2);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'AI Advisor', icon: Icons.lightbulb_outlined, subtitle: 'AI-powered business recommendations will appear here.'),
            );
          },
        ),
        GoRoute(
          path: '/sales',
          pageBuilder: (context, state) {
            _syncIndex(context, 3);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Sales', icon: Icons.point_of_sale_outlined),
            );
          },
        ),
        GoRoute(
          path: '/products',
          pageBuilder: (context, state) {
            _syncIndex(context, 4);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Products', icon: Icons.inventory_2_outlined),
            );
          },
        ),
        GoRoute(
          path: '/inventory',
          pageBuilder: (context, state) {
            _syncIndex(context, 5);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Inventory', icon: Icons.warehouse_outlined),
            );
          },
        ),
        GoRoute(
          path: '/customers',
          pageBuilder: (context, state) {
            _syncIndex(context, 6);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Customers', icon: Icons.people_outline),
            );
          },
        ),
        GoRoute(
          path: '/accounting',
          pageBuilder: (context, state) {
            _syncIndex(context, 7);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Accounting', icon: Icons.account_balance_outlined),
            );
          },
        ),
        GoRoute(
          path: '/reports',
          pageBuilder: (context, state) {
            _syncIndex(context, 8);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Reports', icon: Icons.bar_chart_outlined),
            );
          },
        ),
        GoRoute(
          path: '/employees',
          pageBuilder: (context, state) {
            _syncIndex(context, 9);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Employees', icon: Icons.badge_outlined),
            );
          },
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) {
            _syncIndex(context, 10);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Settings', icon: Icons.settings_outlined),
            );
          },
        ),
        GoRoute(
          path: '/admin',
          pageBuilder: (context, state) {
            _syncIndex(context, 11);
            return const NoTransitionPage(
              child: PlaceholderScreen(title: 'Super Admin', icon: Icons.admin_panel_settings_outlined, subtitle: 'Platform administration panel.'),
            );
          },
        ),
      ],
    ),
  ],
);

/// Sync the shell's selected index when navigating via URL.
void _syncIndex(BuildContext context, int index) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final shell = context.read<ShellState>();
    if (shell.selectedIndex != index) {
      shell.selectIndex(index);
    }
  });
}
