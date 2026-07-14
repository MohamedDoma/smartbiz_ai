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
import '../features/auth/screens/mock_session_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/invite_accept_screen.dart';
import '../features/splash/screens/splash_screen.dart';
import '../features/placeholder/placeholder_screen.dart';
import '../shared/layout/app_shell.dart';
import '../shared/widgets/deferred_route_loader.dart';
import '../features/dashboard/dynamic_dashboard_state.dart';
import '../core/modules/blueprint_navigation_coordinator.dart';
import '../core/modules/blueprint_navigation_controller.dart';
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
import '../features/finance/screens/finance_dashboard_screen.dart' deferred as fin_dashboard;
import '../features/finance/screens/finance_accounts_screen.dart' deferred as fin_accounts;
import '../features/finance/screens/finance_transactions_screen.dart' deferred as fin_transactions;
import '../features/finance/screens/finance_expenses_screen.dart' deferred as fin_expenses;
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
import '../features/employees/screens/role_management_real_screen.dart' deferred as role_mgmt;
import '../features/employees/screens/employee_roles_screen.dart' deferred as emp_roles;
import '../features/employees/screens/org_structure_screen.dart' deferred as org_struct;
import '../features/pipelines/screens/pipelines_screen.dart' deferred as pipe_main;
import '../features/pipelines/screens/pipeline_settings_screen.dart' deferred as pipe_settings;
import '../features/documents/screens/document_checklists_screen.dart' deferred as doc_checklists;
import '../features/documents/screens/record_documents_screen.dart' deferred as rec_docs;
import '../features/commissions/screens/commission_settings_screen.dart' deferred as comm_settings;
import '../features/commissions/screens/commission_entries_screen.dart' deferred as comm_entries;
import '../features/approvals/screens/approval_inbox_screen.dart' deferred as appr_inbox;
import '../features/duplicates/screens/duplicate_rules_screen.dart' deferred as dup_rules;
import '../features/duplicates/screens/duplicate_matches_screen.dart' deferred as dup_matches;
import '../features/ownership/screens/ownership_screen.dart' deferred as own_screen;
import '../features/reports/screens/report_templates_screen.dart' deferred as rpt_templates;
import '../features/reports/screens/report_results_screen.dart' deferred as rpt_results;
import '../features/reports/screens/report_runs_screen.dart' deferred as rpt_runs;
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
import '../features/super_admin/layout/super_admin_shell.dart' deferred as sa_shell;
import '../features/platform/screens/platform_dashboard_screen.dart' deferred as plt_dash;
import '../features/platform/screens/platform_workspaces_screen.dart' deferred as plt_ws;
import '../features/platform/screens/platform_users_screen.dart' deferred as plt_users;
import '../features/platform/screens/activation_campaigns_screen.dart' deferred as plt_camps;
import '../features/platform/screens/activation_codes_screen.dart' deferred as plt_codes;
import '../features/platform/screens/activation_cards_print_screen.dart' deferred as plt_cards;
import '../features/platform/screens/platform_plans_screen.dart' deferred as plt_plans;
import '../features/platform/screens/platform_modules_screen.dart' deferred as plt_mods;
import '../features/platform/screens/platform_usage_screen.dart' deferred as plt_usage;
import '../features/platform/screens/platform_health_screen.dart' deferred as plt_health;
import '../features/auth/screens/activation_code_screen.dart' deferred as act_code;
// ai_chat_59 import removed — /ai redirects to /ai-chat (consolidation Step 59.1.1)

GoRouter buildAppRouter(AppState appState) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: appState,
    redirect: (context, state) {
      final loc = state.uri.path;
      final isLoginRoute = loc == '/login';
      final isRegisterRoute = loc == '/register';
      final isForgotRoute = loc == '/forgot-password';
      final isMockSessionRoute = loc == '/auth/mock-session';
      final isSplashRoute = loc == '/splash';
      final isInviteRoute = loc.startsWith('/invite/');
      final isAuthRoute = isLoginRoute || isRegisterRoute || isForgotRoute || isMockSessionRoute;
      final isActivateRoute = loc == '/activate';
      final isPublicRoute = isAuthRoute || isSplashRoute || isInviteRoute || isActivateRoute;
      final isOnboardingRoute = loc == '/onboarding';
      final isSuperAdminRoute = loc.startsWith('/super-admin') || loc.startsWith('/platform');
      final isRoot = loc == '/';
      final isAuthenticated = appState.isAuthenticated;
      final onboardingDone = appState.isOnboardingCompleted;

      // Helper: prevent redirect loops — never return current location.
      String? guard(String target) => target == loc ? null : target;

      // ── 1. Public routes — always allow (splash, login, register, etc.) ──
      if (isPublicRoute && !isAuthenticated) {
        return null;
      }
      // Authenticated users on splash — let it run its routing logic.
      if (isSplashRoute && isAuthenticated) {
        return null;
      }
      // Invite route — always allow (both auth states).
      if (isInviteRoute) {
        return null;
      }

      // ── 2. Session not yet initialized (page reload) — go to splash ──
      // On web reload, auth state is lost. Splash will call loadCurrentSession()
      // to try restoring from the stored token before routing.
      if (!isAuthenticated && !appState.isSessionInitialized && !isPublicRoute && !isRoot) {
        return guard('/splash');
      }

      // ── 3. Unauthenticated gate — everything else requires auth ──
      if (!isAuthenticated && !isRoot) {
        return guard('/login');
      }

      // ── 3. Authenticated user on auth route — redirect away ──
      if (isAuthenticated && isAuthRoute) {
        if (appState.isSuperAdmin) return guard('/super-admin');
        return guard(onboardingDone ? '/dashboard' : '/onboarding');
      }

      // ── 4. Root — go to splash ──
      if (isRoot) {
        return guard('/splash');
      }

      // ── 5. Super Admin guard ──
      if (isSuperAdminRoute) {
        if (!isAuthenticated) return guard('/login');
        if (!appState.isSuperAdmin) return guard('/dashboard');
        // Super admin bypasses onboarding — allow through.
        return null;
      }

      // ── 6. Customer onboarding gate (authenticated non-SA only) ──
      if (isAuthenticated && !appState.isSuperAdmin) {
        if (!onboardingDone && !isOnboardingRoute) {
          return guard('/onboarding');
        }
        if (onboardingDone && isOnboardingRoute) {
          return guard('/dashboard');
        }
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
          // Read effective permissions for the navigation permission gate.
          Set<String> perms = const {};
          try {
            perms = context.read<BlueprintNavigationController>().effectivePermissions;
          } catch (_) {
            // Controller not yet mounted — allow module-enabled check only.
          }
          final decision = ModuleRouteGuard.evaluate(
            location: state.matchedLocation,
            enabledModules: enabledIds,
            effectivePermissions: perms,
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

        // ── Permission-based route guards ────────────────────
        // Some sub-routes require specific permissions beyond module
        // enablement. Block and redirect if the user lacks them.
        try {
          final perms = context.read<BlueprintNavigationController>().effectivePermissions;
          if (state.matchedLocation == '/commissions/settings' &&
              !perms.contains('commissions.settings.view')) {
            return guard('/commissions');
          }
        } catch (_) {
          // Controller not yet mounted — allow through.
        }
      }

      return null; // no redirect
    },
    routes: [
      // ── Splash ──────────────────────────────────────────
      GoRoute(path: '/splash', pageBuilder: (_, __) => const NoTransitionPage(child: SplashScreen())),

      // ── Public auth routes ──────────────────────────────
      GoRoute(path: '/login', pageBuilder: (_, __) => const NoTransitionPage(child: LoginScreen())),
      GoRoute(path: '/register', pageBuilder: (_, __) => const NoTransitionPage(child: RegisterScreen())),
      GoRoute(path: '/forgot-password', pageBuilder: (_, __) => const NoTransitionPage(child: ForgotPasswordScreen())),
      GoRoute(path: '/auth/mock-session', pageBuilder: (_, __) => const NoTransitionPage(child: MockSessionScreen())),
      GoRoute(
        path: '/activate',
        pageBuilder: (_, state) {
          final code = state.uri.queryParameters['code'] ?? '';
          return NoTransitionPage(
            child: DeferredRouteLoader(loader: act_code.loadLibrary, builder: () => act_code.ActivationCodeScreen(code: code)),
          );
        },
      ),
      GoRoute(
        path: '/invite/:token',
        pageBuilder: (_, state) => NoTransitionPage(
          child: InviteAcceptScreen(token: state.pathParameters['token'] ?? ''),
        ),
      ),

      // Onboarding — standalone (no shell)
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) {
          return const NoTransitionPage(child: OnboardingPage());
        },
      ),

      // Root → splash (handled by redirect callback above)
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
          GoRoute(
            path: '/ai',
            redirect: (_, __) => '/ai-chat',
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
                child: DeferredRouteLoader(loader: fin_dashboard.loadLibrary, builder: () => fin_dashboard.FinanceDashboardScreen()),
              );
            },
            routes: [
              GoRoute(
                path: 'expenses',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: fin_expenses.loadLibrary, builder: () => fin_expenses.FinanceExpensesScreen()),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/finance/accounts',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: fin_accounts.loadLibrary, builder: () => fin_accounts.FinanceAccountsScreen()),
            ),
          ),
          GoRoute(
            path: '/finance/transactions',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: fin_transactions.loadLibrary, builder: () => fin_transactions.FinanceTransactionsScreen()),
            ),
          ),
          GoRoute(
            path: '/finance/expenses',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: fin_expenses.loadLibrary, builder: () => fin_expenses.FinanceExpensesScreen()),
            ),
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
                path: 'role-management',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: role_mgmt.loadLibrary, builder: () => role_mgmt.RoleManagementScreen()),
                ),
              ),
              GoRoute(
                path: 'employee-roles',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: emp_roles.loadLibrary, builder: () => emp_roles.EmployeeRolesScreen()),
                ),
              ),
              GoRoute(
                path: 'org-structure',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: org_struct.loadLibrary, builder: () => org_struct.OrgStructureScreen()),
                ),
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

          // ── Pipelines ──────────────────────────────────
          GoRoute(
            path: '/pipelines',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: pipe_main.loadLibrary, builder: () => pipe_main.PipelinesScreen()),
            ),
            routes: [
              GoRoute(
                path: 'settings',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: DeferredRouteLoader(loader: pipe_settings.loadLibrary, builder: () => pipe_settings.PipelineSettingsScreen()),
                ),
              ),
            ],
          ),

          // ── Document Checklists ────────────────────────────
          GoRoute(
            path: '/documents/checklists',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: doc_checklists.loadLibrary, builder: () => doc_checklists.DocumentChecklistsScreen()),
            ),
          ),
          GoRoute(
            path: '/pipeline-records/:recordId/documents',
            pageBuilder: (context, state) {
              final recordId = state.pathParameters['recordId']!;
              return NoTransitionPage(
                child: DeferredRouteLoader(loader: rec_docs.loadLibrary, builder: () => rec_docs.RecordDocumentsScreen(recordId: recordId)),
              );
            },
          ),

          // ── Commissions ───────────────────────────────
          GoRoute(
            path: '/commissions/settings',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: comm_settings.loadLibrary, builder: () => comm_settings.CommissionSettingsScreen()),
            ),
          ),
          GoRoute(
            path: '/commissions',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: comm_entries.loadLibrary, builder: () => comm_entries.CommissionEntriesScreen()),
            ),
          ),

          // ── Approvals ─────────────────────────────────
          GoRoute(
            path: '/approvals',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: appr_inbox.loadLibrary, builder: () => appr_inbox.ApprovalInboxScreen()),
            ),
          ),

          // ── Duplicates & Ownership ───────────────────
          GoRoute(
            path: '/duplicates/rules',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: dup_rules.loadLibrary, builder: () => dup_rules.DuplicateRulesScreen()),
            ),
          ),
          GoRoute(
            path: '/duplicates/matches',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: dup_matches.loadLibrary, builder: () => dup_matches.DuplicateMatchesScreen()),
            ),
          ),
          GoRoute(
            path: '/ownership',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: own_screen.loadLibrary, builder: () => own_screen.OwnershipScreen()),
            ),
          ),

          // ── Reports ─────────────────────────────────
          GoRoute(
            path: '/reports',
            redirect: (_, __) => '/reports/templates',
          ),
          GoRoute(
            path: '/reports/templates',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: rpt_templates.loadLibrary, builder: () => rpt_templates.ReportTemplatesScreen()),
            ),
          ),
          GoRoute(
            path: '/reports/results',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: rpt_results.loadLibrary, builder: () => rpt_results.ReportResultsScreen()),
            ),
          ),
          GoRoute(
            path: '/reports/runs',
            pageBuilder: (context, state) => NoTransitionPage(
              child: DeferredRouteLoader(loader: rpt_runs.loadLibrary, builder: () => rpt_runs.ReportRunsScreen()),
            ),
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

      // ── Super Admin shell — separate from customer workspace ──
      ShellRoute(
        builder: (context, state, child) => DeferredRouteLoader(
          loader: sa_shell.loadLibrary,
          builder: () => sa_shell.SuperAdminShell(child: child),
        ),
        routes: [
          // ── Canonical /platform/* routes ─────────────────
          GoRoute(path: '/platform', pageBuilder: (_, __) => NoTransitionPage(
            child: DeferredRouteLoader(loader: plt_dash.loadLibrary, builder: () => plt_dash.PlatformDashboardScreen()),
          ), routes: [
            GoRoute(path: 'workspaces', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_ws.loadLibrary, builder: () => plt_ws.PlatformWorkspacesScreen()),
            )),
            GoRoute(path: 'users', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_users.loadLibrary, builder: () => plt_users.PlatformUsersScreen()),
            )),
            GoRoute(path: 'campaigns', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_camps.loadLibrary, builder: () => plt_camps.ActivationCampaignsScreen()),
            )),
            GoRoute(path: 'codes', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_codes.loadLibrary, builder: () => plt_codes.ActivationCodesScreen()),
            )),
            GoRoute(path: 'cards', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_cards.loadLibrary, builder: () => plt_cards.ActivationCardsPrintScreen()),
            )),
            GoRoute(path: 'plans', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_plans.loadLibrary, builder: () => plt_plans.PlatformPlansScreen()),
            )),
            GoRoute(path: 'modules', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_mods.loadLibrary, builder: () => plt_mods.PlatformModulesScreen()),
            )),
            GoRoute(path: 'usage', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_usage.loadLibrary, builder: () => plt_usage.PlatformUsageScreen()),
            )),
            GoRoute(path: 'health', pageBuilder: (_, __) => NoTransitionPage(
              child: DeferredRouteLoader(loader: plt_health.loadLibrary, builder: () => plt_health.PlatformHealthScreen()),
            )),
          ]),
          // ── Old /super-admin/* redirects (bookmark compat) ──
          GoRoute(path: '/super-admin', redirect: (_, __) => '/platform'),
          GoRoute(path: '/super-admin/tenants', redirect: (_, __) => '/platform/workspaces'),
          GoRoute(path: '/super-admin/plans', redirect: (_, __) => '/platform/plans'),
          GoRoute(path: '/super-admin/modules', redirect: (_, __) => '/platform/modules'),
          GoRoute(path: '/super-admin/usage', redirect: (_, __) => '/platform/usage'),
          GoRoute(path: '/super-admin/health', redirect: (_, __) => '/platform/health'),
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
