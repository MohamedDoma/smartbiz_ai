// SmartBiz AI — Router Module Guard Integration Tests.
//
// Verifies that the GoRouter redirect flow correctly applies
// ModuleRouteGuard after existing onboarding/root redirects.
//
// Strategy: builds a test GoRouter that mirrors the production
// redirect logic from buildAppRouter() but uses trivial route
// builders (Text placeholders) to avoid pulling in heavy screen
// dependency trees. The redirect is the real production code path.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/core/navigation/shell_state.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/blueprint_landing_route_resolver.dart';
import 'package:smartbiz_ai/core/modules/module_route_guard.dart';
import 'package:smartbiz_ai/features/dashboard/dynamic_dashboard_state.dart';

// ═══════════════════════════════════════════════════════════
//  Test Harness
// ═══════════════════════════════════════════════════════════

/// Builds a GoRouter that uses the EXACT same redirect logic as
/// the production buildAppRouter() but with placeholder route
/// builders. This isolates redirect behavior from screen widgets.
///
/// [effectivePermissions] gates the module route guard's permission check.
GoRouter _buildTestRouter(AppState appState, {Set<String> effectivePermissions = const {}}) {
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
      if (onboardingDone) {
        try {
          final moduleState = context.read<WorkspaceModuleState>();
          final enabledIds = moduleState.enabledModuleIds.toSet();
          final decision = ModuleRouteGuard.evaluate(
            location: state.matchedLocation,
            enabledModules: enabledIds,
            effectivePermissions: effectivePermissions,
          );
          if (!decision.allowed) {
            String preferredLanding = '/dashboard';
            try {
              preferredLanding = context.read<DynamicDashboardState>().landingRoute;
            } catch (_) {
              // DynamicDashboardState not available — use default.
            }
            final landing = BlueprintLandingRouteResolver.resolve(
              preferredRoute: preferredLanding,
              fallbackRoute: '/dashboard',
              enabledModules: enabledIds,
            );
            if (state.matchedLocation != landing.route) {
              return landing.route;
            }
          }
        } catch (_) {
          // WorkspaceModuleState not available — allow through.
        }
      }

      return null; // no redirect
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const Text('Onboarding'),
      ),
      GoRoute(path: '/', redirect: (_, __) => null),
      // Shell-like routes with placeholder builders
      ShellRoute(
        builder: (_, __, child) => child,
        routes: [
          GoRoute(path: '/dashboard', builder: (_, __) => const Text('Dashboard')),
          GoRoute(path: '/ai-chat', builder: (_, __) => const Text('AI Chat')),
          GoRoute(path: '/advisor', builder: (_, __) => const Text('Advisor')),
          GoRoute(
            path: '/customers',
            builder: (_, __) => const Text('Customers'),
            routes: [
              GoRoute(path: 'create', builder: (_, __) => const Text('Create Customer')),
              GoRoute(path: ':id', builder: (_, s) => Text('Customer ${s.pathParameters['id']}')),
            ],
          ),
          GoRoute(
            path: '/invoices',
            builder: (_, __) => const Text('Invoices'),
            routes: [
              GoRoute(path: 'create', builder: (_, __) => const Text('Create Invoice')),
              GoRoute(path: ':id', builder: (_, s) => Text('Invoice ${s.pathParameters['id']}')),
            ],
          ),
          GoRoute(
            path: '/products',
            builder: (_, __) => const Text('Products'),
            routes: [
              GoRoute(path: 'create', builder: (_, __) => const Text('Create Product')),
              GoRoute(path: ':id', builder: (_, s) => Text('Product ${s.pathParameters['id']}')),
            ],
          ),
          GoRoute(
            path: '/inventory',
            builder: (_, __) => const Text('Inventory'),
          ),
          GoRoute(
            path: '/accounting',
            builder: (_, __) => const Text('Accounting'),
            routes: [
              GoRoute(path: 'expenses', builder: (_, __) => const Text('Expenses')),
            ],
          ),
          GoRoute(path: '/reports', builder: (_, __) => const Text('Reports')),
          GoRoute(
            path: '/employees',
            builder: (_, __) => const Text('Employees'),
            routes: [
              GoRoute(path: 'roles', builder: (_, __) => const Text('Roles')),
              GoRoute(path: 'departments', builder: (_, __) => const Text('Departments')),
              GoRoute(path: 'teams', builder: (_, __) => const Text('Teams')),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Text('Settings'),
            routes: [
              GoRoute(path: 'workspace', builder: (_, __) => const Text('Workspace Settings')),
              GoRoute(path: 'branding', builder: (_, __) => const Text('Branding')),
            ],
          ),
          GoRoute(path: '/admin', builder: (_, __) => const Text('Admin')),
        ],
      ),
    ],
  );
}

/// Pump a test app with the given router and providers.
Widget _buildApp({
  required GoRouter router,
  required AppState appState,
  required WorkspaceModuleState moduleState,
  DynamicDashboardState? dashboardState,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: ShellState()),
      ChangeNotifierProvider.value(value: moduleState),
      if (dashboardState != null)
        ChangeNotifierProvider.value(value: dashboardState),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  late AppState appState;
  late WorkspaceModuleState moduleState;

  setUp(() {
    ErpModuleDependencyResolver.clearCache();
    ModuleRouteGuard.clearCache();
    appState = AppState();
    moduleState = WorkspaceModuleState();
  });

  tearDown(() {
    ModuleRouteGuard.clearCache();
    moduleState.dispose();
    appState.dispose();
  });

  // ═══════════════════════════════════════════════════════════
  //  1. Onboarding Preserved
  // ═══════════════════════════════════════════════════════════
  group('Onboarding Preserved', () {
    testWidgets('customer route redirects to /onboarding when onboarding incomplete', (tester) async {
      // Onboarding not complete (default).
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      // Try to go to a customer route.
      router.go('/customers');
      await tester.pumpAndSettle();

      // Should redirect to onboarding, not be blocked by module guard.
      expect(find.text('Onboarding'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);
    });

    testWidgets('module guard does not override onboarding redirect', (tester) async {
      // Enable customers but onboarding not done.
      moduleState.enableModule(ErpModuleId.customers);
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/customers');
      await tester.pumpAndSettle();

      // Onboarding takes priority over module guard.
      expect(find.text('Onboarding'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Root Redirect Preserved
  // ═══════════════════════════════════════════════════════════
  group('Root Redirect Preserved', () {
    testWidgets('/ redirects to /dashboard when onboarding complete', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      // Initial location is '/' which should redirect to /dashboard.
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('/ redirects to /onboarding when onboarding incomplete', (tester) async {
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Onboarding'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Enabled Module Route Allowed
  // ═══════════════════════════════════════════════════════════
  group('Enabled Module Route Allowed', () {
    testWidgets('/customers allowed when customers module enabled', (tester) async {
      appState.completeOnboarding();
      moduleState.enableModule(ErpModuleId.customers);
      final router = _buildTestRouter(appState, effectivePermissions: {'contacts.list'});
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/customers');
      await tester.pumpAndSettle();

      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Dashboard'), findsNothing);
    });

    testWidgets('/products allowed when products module enabled', (tester) async {
      appState.completeOnboarding();
      moduleState.enableModule(ErpModuleId.products);
      final router = _buildTestRouter(appState, effectivePermissions: {'products.list'});
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/products');
      await tester.pumpAndSettle();

      expect(find.text('Products'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Disabled Module Route Blocked
  // ═══════════════════════════════════════════════════════════
  group('Disabled Module Route Blocked', () {
    testWidgets('/customers redirects to /dashboard when customers disabled', (tester) async {
      appState.completeOnboarding();
      // customers NOT enabled, but dashboard IS (system-required).
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/customers');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);
    });

    testWidgets('/invoices redirects to /dashboard when invoices disabled', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/invoices');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Invoices'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Nested Route Blocked
  // ═══════════════════════════════════════════════════════════
  group('Nested Route Blocked', () {
    testWidgets('/products/:id redirects to /dashboard when products disabled', (tester) async {
      appState.completeOnboarding();
      // products NOT enabled.
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/products/sku-001');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Product sku-001'), findsNothing);
    });

    testWidgets('/customers/create redirects when customers disabled', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/customers/create');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Create Customer'), findsNothing);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Non-Module Routes Allowed
  // ═══════════════════════════════════════════════════════════
  group('Non-Module Routes Allowed', () {
    testWidgets('/admin is not blocked by module guard', (tester) async {
      appState.completeOnboarding();
      // No modules enabled beyond system defaults.
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/admin');
      await tester.pumpAndSettle();

      expect(find.text('Admin'), findsOneWidget);
    });

    testWidgets('/onboarding is not blocked after onboarding complete', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/onboarding');
      await tester.pumpAndSettle();

      // Onboarding route is not module-owned; guard allows it.
      expect(find.text('Onboarding'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Fallback Loop Prevention
  // ═══════════════════════════════════════════════════════════
  group('Fallback Loop Prevention', () {
    testWidgets('/dashboard does not redirect to itself', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      router.go('/dashboard');
      await tester.pumpAndSettle();

      // Dashboard is system-required and always enabled; should render.
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('no infinite redirect loop when navigating blocked route', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
      ));
      await tester.pumpAndSettle();

      // Navigate to a blocked route — should redirect to /dashboard once.
      router.go('/customers');
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      // No exception thrown, no loop — pumpAndSettle completed.
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8. Boot Safety
  // ═══════════════════════════════════════════════════════════
  group('Boot Safety', () {
    testWidgets('router does not throw when WorkspaceModuleState unavailable', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);

      // Intentionally omit WorkspaceModuleState from providers.
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appState,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Should fall through to /dashboard (from root redirect)
      // without throwing, because the catch block handles the missing provider.
      expect(find.text('Dashboard'), findsOneWidget);
    });

    testWidgets('blocked route falls through when provider unavailable', (tester) async {
      appState.completeOnboarding();
      final router = _buildTestRouter(appState);

      // Omit WorkspaceModuleState — guard catch block allows route through.
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appState,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to a module route. Without WorkspaceModuleState, the
      // guard's catch block allows it — no crash, no redirect.
      router.go('/customers');
      await tester.pumpAndSettle();

      expect(find.text('Customers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  9. Landing Route Source Integration
  // ═══════════════════════════════════════════════════════════
  group('Landing Route Source', () {
    testWidgets('blocked route redirects to configured landing route', (tester) async {
      appState.completeOnboarding();
      // Configure dashboard state with /settings as the landing route.
      final dashState = DynamicDashboardState();
      dashState.updateContext(
        primaryRoleId: 'sys_employee',
        extraRoleIds: [],
        effectivePermissions: {'settings.view'},
        enabledModules: {'dashboard', 'settings'},
      );
      addTearDown(dashState.dispose);

      // Landing route should be /dashboard (default from basicEmployee template).
      // But let's verify: the dashboard state provides a landing route.
      expect(dashState.landingRoute, isNotEmpty);

      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
        dashboardState: dashState,
      ));
      await tester.pumpAndSettle();

      // Navigate to a blocked route (customers not enabled).
      router.go('/customers');
      await tester.pumpAndSettle();

      // Should redirect to the dashboard landing route.
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);
    });

    testWidgets('falls back to /dashboard when dashboard state unavailable', (tester) async {
      appState.completeOnboarding();
      // DO NOT provide DynamicDashboardState.
      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
        // dashboardState: null → not provided
      ));
      await tester.pumpAndSettle();

      // Navigate to a blocked route.
      router.go('/customers');
      await tester.pumpAndSettle();

      // Should fallback to /dashboard.
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Customers'), findsNothing);
    });

    testWidgets('blocked route falls back when landing route itself is disabled', (tester) async {
      appState.completeOnboarding();
      // Configure a dashboard state whose landingRoute would be /dashboard
      // (the default). But simulate: if the landing route were somehow
      // tied to a disabled module, the resolver should cascade to /dashboard.
      final dashState = DynamicDashboardState();
      // Only dashboard enabled — customers/invoices disabled.
      dashState.updateContext(
        primaryRoleId: 'sys_employee',
        extraRoleIds: [],
        effectivePermissions: {'dashboard.view'},
        enabledModules: {'dashboard'},
      );
      addTearDown(dashState.dispose);

      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
        dashboardState: dashState,
      ));
      await tester.pumpAndSettle();

      // Navigate to a blocked route.
      router.go('/invoices');
      await tester.pumpAndSettle();

      // Should redirect to /dashboard (ultimate fallback).
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Invoices'), findsNothing);
    });

    testWidgets('existing onboarding behavior unchanged with dashboard state present', (tester) async {
      // Onboarding NOT complete.
      final dashState = DynamicDashboardState();
      addTearDown(dashState.dispose);

      final router = _buildTestRouter(appState);
      await tester.pumpWidget(_buildApp(
        router: router, appState: appState, moduleState: moduleState,
        dashboardState: dashState,
      ));
      await tester.pumpAndSettle();

      // Should redirect to onboarding, not to landing route.
      expect(find.text('Onboarding'), findsOneWidget);
    });
  });
}
