// SmartBiz AI — App router with onboarding gate + shell routes.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/navigation/shell_state.dart';
import '../core/state/app_state.dart';
import '../features/ai_chat/ai_chat_screen.dart';
import '../features/advisor/advisor_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/invoices/screens/invoices_list_screen.dart';
import '../features/invoices/screens/create_invoice_screen.dart';
import '../features/invoices/screens/invoice_detail_screen.dart';
import '../features/products/screens/products_list_screen.dart';
import '../features/products/screens/create_product_screen.dart';
import '../features/products/screens/product_detail_screen.dart';
import '../features/finance/screens/finance_overview_screen.dart';
import '../features/finance/screens/expenses_screen.dart';
import '../features/finance/screens/reports_screen.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../features/settings/settings_screen.dart';
import '../shared/layout/app_shell.dart';

GoRouter buildAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: appState,
    redirect: (context, state) {
      final onboardingDone = appState.isOnboardingCompleted;
      final isOnboardingRoute = state.matchedLocation == '/onboarding';
      final isRoot = state.matchedLocation == '/';

      // Root → redirect based on onboarding status
      if (isRoot) {
        return onboardingDone ? '/dashboard' : '/onboarding';
      }

      // If onboarding not done and trying to access app pages, redirect
      if (!onboardingDone && !isOnboardingRoute) {
        return '/onboarding';
      }

      return null; // no redirect
    },
    routes: [
      // Onboarding — standalone (no shell)
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) {
          return const NoTransitionPage(child: OnboardingPage());
        },
      ),

      // Root redirect handled by redirect callback above
      GoRoute(path: '/', redirect: (_, __) => null),

      // Main app shell
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
                child: AdvisorScreen(),
              );
            },
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) {
              _syncIndex(context, 3);
              return const NoTransitionPage(
                child: InvoicesListScreen(),
              );
            },
            routes: [
              GoRoute(
                path: 'create',
                pageBuilder: (context, state) => const NoTransitionPage(child: CreateInvoiceScreen()),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(child: InvoiceDetailScreen(invoiceId: id));
                },
              ),
            ],
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (context, state) {
              _syncIndex(context, 4);
              return const NoTransitionPage(child: ProductsListScreen());
            },
            routes: [
              GoRoute(
                path: 'create',
                pageBuilder: (context, state) => const NoTransitionPage(child: CreateProductScreen()),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(child: ProductDetailScreen(productId: id));
                },
              ),
            ],
          ),
          GoRoute(
            path: '/inventory',
            pageBuilder: (context, state) {
              _syncIndex(context, 5);
              return const NoTransitionPage(
                child: PlaceholderScreen(titleKey: 'nav_inventory', icon: Icons.warehouse_outlined),
              );
            },
          ),
          GoRoute(
            path: '/customers',
            pageBuilder: (context, state) {
              _syncIndex(context, 6);
              return const NoTransitionPage(
                child: PlaceholderScreen(titleKey: 'nav_customers', icon: Icons.people_outline),
              );
            },
          ),
          GoRoute(
            path: '/accounting',
            pageBuilder: (context, state) {
              _syncIndex(context, 7);
              return const NoTransitionPage(child: FinanceOverviewScreen());
            },
            routes: [
              GoRoute(
                path: 'expenses',
                pageBuilder: (context, state) => const NoTransitionPage(child: ExpensesScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) {
              _syncIndex(context, 8);
              return const NoTransitionPage(child: ReportsScreen());
            },
          ),
          GoRoute(
            path: '/employees',
            pageBuilder: (context, state) {
              _syncIndex(context, 9);
              return const NoTransitionPage(
                child: PlaceholderScreen(titleKey: 'nav_employees', icon: Icons.badge_outlined),
              );
            },
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) {
              _syncIndex(context, 10);
              return const NoTransitionPage(child: SettingsScreen());
            },
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) {
              _syncIndex(context, 11);
              return const NoTransitionPage(
                child: PlaceholderScreen(titleKey: 'nav_admin', icon: Icons.admin_panel_settings_outlined, subtitleKey: 'admin_subtitle'),
              );
            },
          ),
        ],
      ),
    ],
  );
}

void _syncIndex(BuildContext context, int index) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final shell = context.read<ShellState>();
    if (shell.selectedIndex != index) {
      shell.selectIndex(index);
    }
  });
}
