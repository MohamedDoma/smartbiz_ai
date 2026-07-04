// SmartBiz AI — Module Route Guard Tests (Phase 17).
//
// Unit tests for ModuleRouteGuard.evaluate() covering ownership,
// normalization, prefix matching, segment boundaries, and blocking.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/module_route_guard.dart';

void main() {
  setUp(() {
    ModuleRouteGuard.clearCache();
  });

  tearDown(() {
    ModuleRouteGuard.clearCache();
  });

  /// A baseline enabled set with all commonly-used implemented modules.
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

  // ═══════════════════════════════════════════════════════════
  //  1. Non-Module-Owned Routes (Always Allowed)
  // ═══════════════════════════════════════════════════════════
  group('Non-Module-Owned Routes', () {
    test('root / is allowed', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
      expect(d.blockedModuleId, isNull);
    });

    test('/onboarding is allowed', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/onboarding',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
    });

    test('/admin is allowed', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/admin',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
    });

    test('/unknown-route is allowed', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/unknown-route',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
    });

    test('/auth/login is allowed (hypothetical auth route)', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/auth/login',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Enabled Module Routes (Allowed)
  // ═══════════════════════════════════════════════════════════
  group('Enabled Module Routes', () {
    test('/dashboard allowed when dashboard enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/dashboard',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/settings allowed when settings enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/settings',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/customers allowed when customers enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/customers',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/products allowed when products enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/invoices allowed when invoices enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/invoices',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Disabled Module Routes (Blocked)
  // ═══════════════════════════════════════════════════════════
  group('Disabled Module Routes', () {
    test('/customers blocked when customers not enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/customers',
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.settings},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.customers);
      expect(d.redirectRoute, '/dashboard');
      expect(d.reason, contains('customers'));
    });

    test('/products blocked when products not enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.settings},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.products);
      expect(d.redirectRoute, '/dashboard');
    });

    test('/invoices blocked when invoices not enabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/invoices',
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.settings},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.invoices);
      expect(d.redirectRoute, '/dashboard');
    });

    test('custom fallback route is used when specified', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: {ErpModuleId.dashboard},
        fallbackRoute: '/settings',
      );
      expect(d.allowed, isFalse);
      expect(d.redirectRoute, '/settings');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Route Normalization
  // ═══════════════════════════════════════════════════════════
  group('Route Normalization', () {
    test('query string is stripped', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products?tab=active',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('hash fragment is stripped', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products#inventory',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('trailing slash is stripped', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products/',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('uppercase path is lowercased', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/PRODUCTS',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('query + trailing slash + uppercase all normalized', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/PRODUCTS/?sort=name#top',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('normalized disabled route is still blocked', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/PRODUCTS?x=1',
        enabledModules: {ErpModuleId.dashboard},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.products);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Nested / Detail Route Matching
  // ═══════════════════════════════════════════════════════════
  group('Nested Detail Route Matching', () {
    test('/customers/123 matches customers module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/customers/123',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/customers/123 blocked when customers disabled', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/customers/123',
        enabledModules: {ErpModuleId.dashboard},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.customers);
    });

    test('/products/sku-001 matches products module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/products/sku-001',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/invoices/INV-1 matches invoices module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/invoices/INV-1',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/invoices/create matches invoices module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/invoices/create',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/employees/invite matches employees module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/employees/invite',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/settings/workspace matches settings module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/settings/workspace',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Segment Boundary Safety
  // ═══════════════════════════════════════════════════════════
  group('Segment Boundary Safety', () {
    test('/custom does NOT match /customers', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/custom',
        enabledModules: {},
      );
      // Not module-owned → allowed, not matched to customers.
      expect(d.allowed, isTrue);
      expect(d.blockedModuleId, isNull);
    });

    test('/productivity does NOT match /products', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/productivity',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
      expect(d.blockedModuleId, isNull);
    });

    test('/inventorycheck does NOT match /inventory', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/inventorycheck',
        enabledModules: {},
      );
      expect(d.allowed, isTrue);
      expect(d.blockedModuleId, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Longest-Prefix Ownership
  // ═══════════════════════════════════════════════════════════
  group('Longest-Prefix Ownership', () {
    test('/accounting/expenses matches expenses module, not accounting', () {
      // Both expenses and accounting claim routes under /accounting.
      // The expenses module owns '/accounting/expenses' more specifically.
      final d = ModuleRouteGuard.evaluate(
        location: '/accounting/expenses',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/accounting/expenses blocked when expenses disabled but accounting enabled', () {
      final enabledWithoutExpenses = Set.of(allEnabled)..remove(ErpModuleId.expenses);
      final d = ModuleRouteGuard.evaluate(
        location: '/accounting/expenses',
        enabledModules: enabledWithoutExpenses,
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.expenses);
    });

    test('/accounting allowed when expenses disabled but accounting enabled', () {
      final enabledWithoutExpenses = Set.of(allEnabled)..remove(ErpModuleId.expenses);
      final d = ModuleRouteGuard.evaluate(
        location: '/accounting',
        enabledModules: enabledWithoutExpenses,
      );
      expect(d.allowed, isTrue);
    });

    test('/employees/roles matches roles module via prefix', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/employees/roles',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/employees/roles blocked when roles disabled but employees enabled', () {
      final enabledWithoutRoles = Set.of(allEnabled)..remove(ErpModuleId.roles);
      final d = ModuleRouteGuard.evaluate(
        location: '/employees/roles',
        enabledModules: enabledWithoutRoles,
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.roles);
    });

    test('/employees/departments matches departments module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/employees/departments',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('/employees/teams matches teams module', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/employees/teams',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8. System-Required Modules
  // ═══════════════════════════════════════════════════════════
  group('System-Required Modules', () {
    test('dashboard allowed when in enabled set', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/dashboard',
        enabledModules: {ErpModuleId.dashboard},
      );
      expect(d.allowed, isTrue);
    });

    test('settings allowed when in enabled set', () {
      final d = ModuleRouteGuard.evaluate(
        location: '/settings',
        enabledModules: {ErpModuleId.settings},
      );
      expect(d.allowed, isTrue);
    });

    test('dashboard blocked when intentionally omitted from enabled set (deterministic)', () {
      // This tests the guard's pure behavior — it does NOT auto-inject
      // system-required modules. WorkspaceModuleState enforces that
      // dashboard/settings are always enabled upstream.
      final d = ModuleRouteGuard.evaluate(
        location: '/dashboard',
        enabledModules: {},
      );
      expect(d.allowed, isFalse);
      expect(d.blockedModuleId, ErpModuleId.dashboard);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  9. Cache / Consistency
  // ═══════════════════════════════════════════════════════════
  group('Cache and Consistency', () {
    test('repeated evaluations return consistent results', () {
      final d1 = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      final d2 = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      expect(d1.allowed, d2.allowed);
      expect(d1.blockedModuleId, d2.blockedModuleId);
    });

    test('clearCache does not break subsequent evaluations', () {
      ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      ModuleRouteGuard.clearCache();
      final d = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      expect(d.allowed, isTrue);
    });

    test('different enabled sets produce different results for same route', () {
      final allowed = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: allEnabled,
      );
      final blocked = ModuleRouteGuard.evaluate(
        location: '/products',
        enabledModules: {ErpModuleId.dashboard},
      );
      expect(allowed.allowed, isTrue);
      expect(blocked.allowed, isFalse);
    });
  });
}
