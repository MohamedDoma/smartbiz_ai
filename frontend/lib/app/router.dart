// SmartBiz AI — App router with onboarding gate + shell routes.
// Performance: heavy feature screens use deferred imports for code splitting.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/navigation/shell_state.dart';
import '../core/state/app_state.dart';
// Eagerly loaded — needed immediately or very lightweight
import '../features/ai_chat/ai_chat_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../shared/layout/app_shell.dart';
import '../shared/widgets/deferred_route_loader.dart';
import '../features/dashboard/dynamic_dashboard_state.dart';
import '../core/modules/blueprint_navigation_coordinator.dart';
import '../core/pages/dynamic_page_route_resolver.dart';
import '../core/pages/dynamic_page_route_scope.dart';

// Deferred imports — loaded on first route access
import '../features/advisor/advisor_screen.dart' deferred as advisor;
import '../features/invoices/screens/invoices_list_screen.dart' deferred as inv_list;
import '../features/invoices/screens/create_invoice_screen.dart' deferred as inv_create;
import '../features/invoices/screens/invoice_detail_screen.dart' deferred as inv_detail;
import '../features/products/screens/products_list_screen.dart' deferred as prod_list;
import '../features/products/screens/create_product_screen.dart' deferred as prod_create;
import '../features/products/screens/product_detail_screen.dart' deferred as prod_detail;
import '../features/finance/screens/finance_overview_screen.dart' deferred as fin_overview;
import '../features/finance/screens/expenses_screen.dart' deferred as fin_expenses;
import '../features/finance/screens/reports_screen.dart' deferred as fin_reports;
import '../features/employees/screens/employees_list_screen.dart' deferred as emp_list;
import '../features/employees/screens/invite_employee_screen.dart' deferred as emp_invite;
import '../features/employees/screens/employee_detail_screen.dart' deferred as emp_detail;
import '../features/employees/screens/roles_overview_screen.dart' deferred as roles_overview;
import '../features/employees/screens/create_role_screen.dart' deferred as role_create;
import '../features/employees/screens/role_detail_screen.dart' deferred as role_detail;
import '../features/employees/screens/org_overview_screen.dart' deferred as org_overview;
import '../features/employees/screens/departments_screen.dart' deferred as dept_screen;
import '../features/employees/screens/teams_screen.dart' deferred as teams_screen;
import '../features/employees/screens/org_chart_screen.dart' deferred as org_chart;
import '../features/employees/screens/employee_assignment_screen.dart' deferred as emp_assign;
import '../features/customers/screens/customers_list_screen.dart' deferred as cust_list;
import '../features/customers/screens/create_customer_screen.dart' deferred as cust_create;
import '../features/customers/screens/customer_detail_screen.dart' deferred as cust_detail;
import '../features/inventory/screens/inventory_overview_screen.dart' deferred as stk_overview;
import '../features/inventory/screens/movements_screen.dart' deferred as stk_movements;
import '../features/inventory/screens/adjustments_screen.dart' deferred as stk_adjust;
import '../features/payments/screens/payments_list_screen.dart' deferred as pay_list;
import '../features/pos/screens/pos_screen.dart' deferred as pos_screen;
import '../features/settings/screens/workspace_settings_screen.dart' deferred as set_workspace;
import '../features/settings/screens/branding_screen.dart' deferred as set_branding;
import '../features/settings/screens/billing_screen.dart' deferred as set_billing;
import '../features/settings/screens/ai_usage_screen.dart' deferred as set_ai;
import '../features/settings/settings_screen.dart' deferred as set_main;
import '../core/modules/blueprint_landing_route_resolver.dart';
import '../core/modules/module_route_guard.dart';
import '../core/modules/workspace_module_state.dart';

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
      // ── Module route guard ──────────────────────────────
      // Module ownership is determined by the ERP module registry.
      // The guard blocks routes whose owning module is not enabled in
      // the current workspace. Non-module routes (onboarding, admin,
      // unknown) pass through unblocked.
      //
      // When a route is blocked, BlueprintLandingRouteResolver determines
      // the safest redirect target, preventing fallback loops and
      // validating the fallback route itself against the module guard.
      if (onboardingDone) {
        try {
          final moduleState = context.read<WorkspaceModuleState>();
          final enabledIds = moduleState.enabledModuleIds.toSet();
          final decision = ModuleRouteGuard.evaluate(
            location: state.matchedLocation,
            enabledModules: enabledIds,
          );
          if (!decision.allowed) {
            // Read the configured landing route from the dashboard state.
            // Falls back to '/dashboard' if the state is not yet mounted
            // (e.g. during initial boot before the coordinator syncs).
            String preferredLanding = '/dashboard';
            try {
              preferredLanding = context.read<DynamicDashboardState>().landingRoute;
            } catch (_) {
              // DynamicDashboardState not yet available — use default.
            }
            final landing = BlueprintLandingRouteResolver.resolve(
              preferredRoute: preferredLanding,
              fallbackRoute: '/dashboard',
              enabledModules: enabledIds,
            );
            // Avoid redirect loop: if already on the resolved route, allow it.
            if (state.matchedLocation != landing.route) {
              return landing.route;
            }
          }
        } catch (_) {
          // WorkspaceModuleState not yet available in the widget tree
          // (e.g. during initial boot). Allow the route to proceed;
          // the coordinator will sync once providers are mounted.
        }
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

      // Main app shell — wrapped with BlueprintNavigationCoordinator
      // to sync WorkspaceModuleState → BlueprintNavigationController.
      // Coordinator runs only around the authenticated shell, not onboarding.
      ShellRoute(
        builder: (context, state, child) {
          const resolver = DynamicPageRouteResolver();
          final result = resolver.resolve(state.uri.path);
          return DynamicPageRouteScope(
            result: result,
            child: BlueprintNavigationCoordinator(
              child: AppShell(child: child),
            ),
          );
        },
        routes: [
          // ── Eager routes ──────────────────────────────
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

          // ── Deferred routes ───────────────────────────
          GoRoute(
            path: '/advisor',
            pageBuilder: (context, state) {
              _syncIndex(context, 2);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: advisor.loadLibrary, builder: () => advisor.AdvisorScreen()),
              );
            },
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) {
              _syncIndex(context, 3);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: inv_list.loadLibrary, builder: () => inv_list.InvoicesListScreen()),
              );
            },
            routes: [
              GoRoute(
                path: 'create',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: inv_create.loadLibrary, builder: () => inv_create.CreateInvoiceScreen()),
                ),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(
                    child: DeferredRouteLoader(loader: inv_detail.loadLibrary, builder: () => inv_detail.InvoiceDetailScreen(invoiceId: id)),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/payments',
            pageBuilder: (context, state) {
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: pay_list.loadLibrary, builder: () => pay_list.PaymentsListScreen()),
              );
            },
          ),
          GoRoute(
            path: '/pos',
            pageBuilder: (context, state) {
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: pos_screen.loadLibrary, builder: () => pos_screen.PosScreen()),
              );
            },
          ),
          GoRoute(
            path: '/products',
            pageBuilder: (context, state) {
              _syncIndex(context, 4);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: prod_list.loadLibrary, builder: () => prod_list.ProductsListScreen()),
              );
            },
            routes: [
              GoRoute(
                path: 'create',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: prod_create.loadLibrary, builder: () => prod_create.CreateProductScreen()),
                ),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(
                    child: DeferredRouteLoader(loader: prod_detail.loadLibrary, builder: () => prod_detail.ProductDetailScreen(productId: id)),
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/inventory',
            pageBuilder: (context, state) {
              _syncIndex(context, 5);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: stk_overview.loadLibrary, builder: () => stk_overview.InventoryOverviewScreen()),
              );
            },
            routes: [
              GoRoute(path: 'movements', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: stk_movements.loadLibrary, builder: () => stk_movements.MovementsScreen()),
              )),
              GoRoute(path: 'adjustments', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: stk_adjust.loadLibrary, builder: () => stk_adjust.AdjustmentsScreen()),
              )),
            ],
          ),
          GoRoute(
            path: '/customers',
            pageBuilder: (context, state) {
              _syncIndex(context, 6);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: cust_list.loadLibrary, builder: () => cust_list.CustomersListScreen()),
              );
            },
            routes: [
              GoRoute(path: 'create', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: cust_create.loadLibrary, builder: () => cust_create.CreateCustomerScreen()),
              )),
              GoRoute(path: ':id', pageBuilder: (context, state) {
                final id = state.pathParameters['id']!;
                return NoTransitionPage(
                  child: DeferredRouteLoader(loader: cust_detail.loadLibrary, builder: () => cust_detail.CustomerDetailScreen(customerId: id)),
                );
              }),
            ],
          ),
          GoRoute(
            path: '/accounting',
            pageBuilder: (context, state) {
              _syncIndex(context, 7);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: fin_overview.loadLibrary, builder: () => fin_overview.FinanceOverviewScreen()),
              );
            },
            routes: [
              GoRoute(
                path: 'expenses',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: fin_expenses.loadLibrary, builder: () => fin_expenses.ExpensesScreen()),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) {
              _syncIndex(context, 8);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: fin_reports.loadLibrary, builder: () => fin_reports.ReportsScreen()),
              );
            },
          ),
          GoRoute(
            path: '/employees',
            pageBuilder: (context, state) {
              _syncIndex(context, 9);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: emp_list.loadLibrary, builder: () => emp_list.EmployeesListScreen()),
              );
            },
            routes: [
              GoRoute(
                path: 'invite',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: emp_invite.loadLibrary, builder: () => emp_invite.InviteEmployeeScreen()),
                ),
              ),
              GoRoute(
                path: 'roles',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: roles_overview.loadLibrary, builder: () => roles_overview.RolesOverviewScreen()),
                ),
                routes: [
                  GoRoute(path: 'create', pageBuilder: (context, state) => NoTransitionPage(
                    child: DeferredRouteLoader(loader: role_create.loadLibrary, builder: () => role_create.CreateRoleScreen()),
                  )),
                  GoRoute(path: ':id', pageBuilder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return NoTransitionPage(
                      child: DeferredRouteLoader(loader: role_detail.loadLibrary, builder: () => role_detail.RoleDetailScreen(roleId: id)),
                    );
                  }),
                ],
              ),
              GoRoute(
                path: 'organization',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: org_overview.loadLibrary, builder: () => org_overview.OrgOverviewScreen()),
                ),
              ),
              GoRoute(
                path: 'departments',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: dept_screen.loadLibrary, builder: () => dept_screen.DepartmentsScreen()),
                ),
              ),
              GoRoute(
                path: 'teams',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: teams_screen.loadLibrary, builder: () => teams_screen.TeamsScreen()),
                ),
              ),
              GoRoute(
                path: 'chart',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: org_chart.loadLibrary, builder: () => org_chart.OrgChartScreen()),
                ),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id']!;
                  return NoTransitionPage(
                    child: DeferredRouteLoader(loader: emp_detail.loadLibrary, builder: () => emp_detail.EmployeeDetailScreen(employeeId: id)),
                  );
                },
                routes: [
                  GoRoute(
                    path: 'assignment',
                    pageBuilder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return NoTransitionPage(
                        child: DeferredRouteLoader(loader: emp_assign.loadLibrary, builder: () => emp_assign.EmployeeAssignmentScreen(employeeId: id)),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) {
              _syncIndex(context, 10);
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: set_main.loadLibrary, builder: () => set_main.SettingsScreen()),
              );
            },
            routes: [
              GoRoute(path: 'workspace', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: set_workspace.loadLibrary, builder: () => set_workspace.WorkspaceSettingsScreen()),
              )),
              GoRoute(path: 'branding', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: set_branding.loadLibrary, builder: () => set_branding.BrandingScreen()),
              )),
              GoRoute(path: 'billing', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: set_billing.loadLibrary, builder: () => set_billing.BillingScreen()),
              )),
              GoRoute(path: 'ai', pageBuilder: (context, state) => NoTransitionPage(
                child: DeferredRouteLoader(loader: set_ai.loadLibrary, builder: () => set_ai.AiUsageScreen()),
              )),
            ],
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
