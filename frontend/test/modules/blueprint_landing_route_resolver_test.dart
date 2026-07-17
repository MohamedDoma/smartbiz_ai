// SmartBiz AI — Blueprint Landing Route Resolver Tests (Phase 17).
//
// Unit tests for BlueprintLandingRouteResolver.resolve() covering
// normalization, allowed/blocked preferred routes, fallback cascading,
// module guard delegation, and determinism.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/blueprint_landing_route_resolver.dart';
import 'package:smartbiz_ai/core/modules/module_route_guard.dart';

void main() {
  setUp(() {
    ModuleRouteGuard.clearCache();
  });

  tearDown(() {
    ModuleRouteGuard.clearCache();
  });

  /// All navPerms keys from ErpModuleRegistry so the guard does not
  /// block routes for permission reasons — these tests focus on
  /// module enablement, not permission gating.
  final allPerms = <String>{
    'ai_advisor.view', 'contacts.list', 'pipelines.list',
    'commissions.list', 'invoices.list', 'payments.list',
    'pos.view', 'products.list', 'inventory.list',
    'accounting.view', 'reports.view', 'employees.list',
    'roles.list', 'departments.list', 'teams.list',
    'approvals.list', 'settings.view',
  };

  /// Baseline: all commonly-used modules enabled.
  final allEnabled = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.aiAdvisor,
    ErpModuleId.customers,
    ErpModuleId.invoices,
    ErpModuleId.products,
    ErpModuleId.inventory,
    ErpModuleId.accounting,
    ErpModuleId.expenses,
    ErpModuleId.reports,
    ErpModuleId.employees,
    ErpModuleId.roles,
    ErpModuleId.departments,
    ErpModuleId.teams,
  };

  /// Minimal system-only set.
  final systemOnly = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
  };

  // ═══════════════════════════════════════════════════════════
  //  1. Preferred Route Normalization
  // ═══════════════════════════════════════════════════════════
  group('Preferred Route Normalization', () {
    test('null preferred route uses fallback', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: null,
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
      expect(d.reason, contains('No preferred route'));
    });

    test('empty string preferred route uses fallback', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('whitespace-only preferred route uses fallback', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '   ',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('trims whitespace from preferred route', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '  /customers  ',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/customers');
      expect(d.usedFallback, isFalse);
    });

    test('adds leading slash if missing', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: 'products',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/products');
      expect(d.usedFallback, isFalse);
    });

    test('strips query string', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers?tab=active',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/customers');
      expect(d.usedFallback, isFalse);
    });

    test('strips hash fragment', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/products#details',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/products');
      expect(d.usedFallback, isFalse);
    });

    test('strips trailing slash', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/invoices/',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/invoices');
      expect(d.usedFallback, isFalse);
    });

    test('root / is preserved (not stripped to empty)', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/');
      expect(d.usedFallback, isFalse);
    });

    test('combined normalization: whitespace + no slash + query + hash', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '  customers?x=1#top  ',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/customers');
      expect(d.usedFallback, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Allowed Preferred Routes
  // ═══════════════════════════════════════════════════════════
  group('Allowed Preferred Routes', () {
    test('/dashboard allowed when dashboard enabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/dashboard',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isFalse);
      expect(d.reason, contains('allowed'));
    });

    test('/customers allowed when customers enabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/customers');
      expect(d.usedFallback, isFalse);
    });

    test('/products/123 allowed when products enabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/products/123',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/products/123');
      expect(d.usedFallback, isFalse);
    });

    test('/invoices/create allowed when invoices enabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/invoices/create',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/invoices/create');
      expect(d.usedFallback, isFalse);
    });

    test('non-module standalone route is allowed', () {
      // /onboarding is not module-owned → always allowed by guard.
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/onboarding',
        enabledModules: systemOnly,
      );
      expect(d.route, '/onboarding');
      expect(d.usedFallback, isFalse);
    });

    test('unknown route is allowed (not module-owned)', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/some-custom-page',
        enabledModules: systemOnly,
      );
      expect(d.route, '/some-custom-page');
      expect(d.usedFallback, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Blocked Preferred Routes
  // ═══════════════════════════════════════════════════════════
  group('Blocked Preferred Routes', () {
    test('/customers falls back when customers disabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
      expect(d.reason, contains('blocked'));
    });

    test('/products/123 falls back when products disabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/products/123',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('/invoices falls back when invoices disabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/invoices',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('/inventory falls back when inventory disabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/inventory',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('reason mentions blocked for disabled module', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: systemOnly,
      );
      expect(d.reason.toLowerCase(), contains('blocked'));
      expect(d.reason.toLowerCase(), contains('customers'));
    });

    test('nested detail route blocked when parent module disabled', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/employees/invite',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Fallback Route Behavior
  // ═══════════════════════════════════════════════════════════
  group('Fallback Route Behavior', () {
    test('custom fallback route is used when preferred is blocked', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/settings',
        enabledModules: systemOnly,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/settings');
      expect(d.usedFallback, isTrue);
    });

    test('custom fallback is validated by module guard', () {
      // Fallback is /invoices but invoices is disabled → ultimate fallback.
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/invoices',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
      expect(d.reason, contains('fallback also blocked'));
    });

    test('no fallback loop when fallback is /dashboard', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/dashboard',
        enabledModules: systemOnly,
      );
      // Should return /dashboard without a loop.
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('default fallback is /dashboard', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('fallback to non-module route is allowed', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/onboarding',
        enabledModules: systemOnly,
      );
      // /onboarding is not module-owned → allowed as fallback.
      expect(d.route, '/onboarding');
      expect(d.usedFallback, isTrue);
    });

    test('blocked preferred + blocked fallback → /dashboard', () {
      // Both preferred and fallback are disabled module routes.
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/products',
        fallbackRoute: '/invoices',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });

    test('null preferred + valid custom fallback → custom fallback', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: null,
        fallbackRoute: '/settings',
        enabledModules: systemOnly,
        effectivePermissions: allPerms,
      );
      expect(d.route, '/settings');
      expect(d.usedFallback, isTrue);
    });

    test('null preferred + blocked custom fallback → /dashboard', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: null,
        fallbackRoute: '/products',
        enabledModules: systemOnly,
      );
      expect(d.route, '/dashboard');
      expect(d.usedFallback, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Module Guard Delegation
  // ═══════════════════════════════════════════════════════════
  group('Module Guard Delegation', () {
    test('route ownership consistent with ModuleRouteGuard', () {
      // The landing resolver must produce the same allow/block as
      // ModuleRouteGuard for any given route + enabledModules.
      final routes = ['/customers', '/products', '/invoices', '/settings'];
      for (final route in routes) {
        final guardDecision = ModuleRouteGuard.evaluate(
          location: route,
          enabledModules: systemOnly,
        );
        final landingDecision = BlueprintLandingRouteResolver.resolve(
          preferredRoute: route,
          enabledModules: systemOnly,
        );
        if (guardDecision.allowed) {
          expect(landingDecision.route, route,
              reason: '$route allowed by guard → landing should use it');
          expect(landingDecision.usedFallback, isFalse);
        } else {
          expect(landingDecision.usedFallback, isTrue,
              reason: '$route blocked by guard → landing should fallback');
        }
      }
    });

    test('nested route delegation consistent with guard', () {
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/employees/roles',
        enabledModules: Set.of(allEnabled)..remove(ErpModuleId.roles),
        effectivePermissions: allPerms,
      );
      // /employees/roles is owned by roles module (longest prefix).
      expect(d.usedFallback, isTrue);
      expect(d.route, '/dashboard');
    });

    test('/accounting/expenses respects expenses module, not accounting', () {
      final withoutExpenses = Set.of(allEnabled)..remove(ErpModuleId.expenses);
      final d = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/accounting/expenses',
        enabledModules: withoutExpenses,
        effectivePermissions: allPerms,
      );
      expect(d.usedFallback, isTrue);
      expect(d.route, '/dashboard');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Determinism
  // ═══════════════════════════════════════════════════════════
  group('Determinism', () {
    test('repeated calls return same result', () {
      final d1 = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      final d2 = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      expect(d1.route, d2.route);
      expect(d1.usedFallback, d2.usedFallback);
    });

    test('different enabled sets produce different routes', () {
      final allowed = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: allEnabled,
        effectivePermissions: allPerms,
      );
      final blocked = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        enabledModules: systemOnly,
      );
      expect(allowed.route, '/customers');
      expect(allowed.usedFallback, isFalse);
      expect(blocked.route, '/dashboard');
      expect(blocked.usedFallback, isTrue);
    });

    test('same blocked route with different fallbacks', () {
      final d1 = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/settings',
        enabledModules: systemOnly,
        effectivePermissions: allPerms,
      );
      final d2 = BlueprintLandingRouteResolver.resolve(
        preferredRoute: '/customers',
        fallbackRoute: '/dashboard',
        enabledModules: systemOnly,
      );
      expect(d1.route, '/settings');
      expect(d2.route, '/dashboard');
    });
  });
}
