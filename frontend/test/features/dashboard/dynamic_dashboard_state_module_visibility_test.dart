// SmartBiz AI — DynamicDashboardState Module Visibility Integration Tests.
//
// Verifies that DynamicDashboardState applies DashboardModuleVisibilityResolver
// as a post-processing step after DashboardResolver produces its base config.
// The resolver engine itself is NOT modified; filtering is layered on top.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/features/dashboard/dashboard_module_visibility_resolver.dart';
import 'package:smartbiz_ai/features/dashboard/dynamic_dashboard_state.dart';
import 'package:smartbiz_ai/features/dashboard/models/dashboard_config_models.dart';

void main() {
  late DynamicDashboardState state;

  /// All commonly used module apiIds (must match ErpModuleRegistry.apiId).
  final allModuleApiIds = <String>{
    'dashboard', 'ai_chat', 'ai_advisor', 'customers', 'invoices',
    'products', 'inventory', 'accounting', 'expenses', 'reports',
    'employees', 'roles', 'settings',
  };

  /// All permissions needed by the sales template.
  final salesPerms = <String>{
    'dashboard.view', 'invoices.view', 'invoices.create',
    'customers.view', 'customers.create', 'products.view',
    // navPerms keys from ErpModuleRegistry (backend-aligned):
    'invoices.list', 'contacts.list', 'products.list',
  };

  setUp(() {
    DashboardModuleVisibilityResolver.clearCache();
    state = DynamicDashboardState();
  });

  tearDown(() {
    DashboardModuleVisibilityResolver.clearCache();
    state.dispose();
  });

  // ═══════════════════════════════════════════════════════════
  //  1. Initial / Default Dashboard State
  // ═══════════════════════════════════════════════════════════
  group('Initial Default State', () {
    test('builds without throwing', () {
      expect(state.configuration, isNotNull);
      expect(state.template, isNotNull);
    });

    test('default state uses basicEmployee template', () {
      // Default role is sys_employee → basicEmployee template.
      expect(state.template, DashboardTemplate.basicEmployee);
    });

    test('default state has some widgets', () {
      // basicEmployee has emp_tasks, emp_announce, emp_activity.
      // emp_ai (module: aiChat) may or may not be visible depending on
      // default enabledModules. Default includes 'ai_chat' → should be visible.
      expect(state.widgets.isNotEmpty, isTrue);
    });

    test('widgets with no module are always visible', () {
      // emp_tasks and emp_announce have no module → always visible.
      final ids = state.widgets.map((w) => w.id).toSet();
      expect(ids.contains('emp_tasks'), isTrue,
          reason: 'Module-free widget emp_tasks should be visible');
      expect(ids.contains('emp_announce'), isTrue,
          reason: 'Module-free widget emp_announce should be visible');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Widget Filtering
  // ═══════════════════════════════════════════════════════════
  group('Widget Filtering', () {
    test('widgets owned by disabled module are hidden', () {
      // Use sales template with customers disabled.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'customers'}),
      );

      final ids = state.widgets.map((w) => w.id).toSet();
      // Customer-owned widgets should be hidden.
      expect(ids.contains('sales_customers'), isFalse,
          reason: 'sales_customers (module: customers) should be hidden');
      expect(ids.contains('sales_cust_sum'), isFalse,
          reason: 'sales_cust_sum (module: customers) should be hidden');
    });

    test('widgets owned by enabled module are visible', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );

      final ids = state.widgets.map((w) => w.id).toSet();
      expect(ids.contains('sales_customers'), isTrue);
      expect(ids.contains('sales_cust_sum'), isTrue);
    });

    test('widget order is preserved among visible widgets', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );

      for (int i = 1; i < state.widgets.length; i++) {
        expect(state.widgets[i].position >= state.widgets[i - 1].position, isTrue,
            reason: 'Widgets should maintain position order');
      }
    });

    test('widgets with no module remain visible when all modules disabled', () {
      // sales_activity has no module → always visible regardless of modules.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: <String>{},
      );

      // With empty enabledModules, _applyModuleVisibility skips filtering
      // (fallback safety), so all widgets should remain.
      expect(state.widgets.isNotEmpty, isTrue);
    });

    test('registry-owned widget hidden when module disabled', () {
      // w_customer_summary is owned by customers in registry.
      // sales_cust_sum has module:'customers' AND is also in registry.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: {'dashboard', 'ai_chat', 'invoices'},
      );

      final ids = state.widgets.map((w) => w.id).toSet();
      expect(ids.contains('sales_cust_sum'), isFalse,
          reason: 'Customer-module widget should be hidden');
      // Invoice-owned widgets should remain.
      expect(ids.contains('sales_today'), isTrue,
          reason: 'Invoice-module widget should be visible');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Quick Action Filtering
  // ═══════════════════════════════════════════════════════════
  group('Quick Action Filtering', () {
    test('actions owned by disabled module are hidden', () {
      // qa_new_invoice is owned by invoices in registry.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'invoices'}),
      );

      final actionIds = state.quickActions.map((a) => a.id).toSet();
      expect(actionIds.contains('qa_new_invoice'), isFalse,
          reason: 'qa_new_invoice should be hidden when invoices disabled');
    });

    test('actions owned by enabled module are visible', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );

      final actionIds = state.quickActions.map((a) => a.id).toSet();
      expect(actionIds.contains('qa_new_invoice'), isTrue,
          reason: 'qa_new_invoice should be visible when invoices enabled');
    });

    test('action order is preserved among visible actions', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );

      for (int i = 1; i < state.quickActions.length; i++) {
        expect(state.quickActions[i].position >= state.quickActions[i - 1].position, isTrue,
            reason: 'Actions should maintain position order');
      }
    });

    test('unknown action IDs with module-owned routes respect module state', () {
      // qa_ai_help has no registry owner, but its route '/ai-chat' is owned
      // by the aiChat module. With route-based filtering it should be hidden
      // when aiChat is disabled.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: {'dashboard'},
      );

      final actionIds = state.quickActions.map((a) => a.id).toSet();
      expect(actionIds.contains('qa_ai_help'), isFalse,
          reason: 'qa_ai_help route /ai-chat is owned by aiChat (disabled)');
    });

    test('unknown action IDs visible when their route module is enabled', () {
      // Same action, but now with aiChat enabled.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: {'dashboard', 'ai_chat', 'invoices', 'customers', 'products'},
      );

      final actionIds = state.quickActions.map((a) => a.id).toSet();
      expect(actionIds.contains('qa_ai_help'), isTrue,
          reason: 'qa_ai_help should be visible when aiChat is enabled');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Enabled Module Updates
  // ═══════════════════════════════════════════════════════════
  group('Enabled Module Updates', () {
    test('enabling a module makes its widgets visible', () {
      // Start with customers disabled.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'customers'}),
      );
      expect(
        state.widgets.any((w) => w.id == 'sales_customers'),
        isFalse,
      );

      // Now enable customers.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );
      expect(
        state.widgets.any((w) => w.id == 'sales_customers'),
        isTrue,
      );
    });

    test('disabling a module hides its widgets', () {
      // Start with all enabled.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );
      expect(
        state.widgets.any((w) => w.id == 'sales_today'),
        isTrue,
        reason: 'sales_today should be visible when invoices enabled',
      );

      // Disable invoices.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'invoices'}),
      );
      expect(
        state.widgets.any((w) => w.id == 'sales_today'),
        isFalse,
        reason: 'sales_today should be hidden when invoices disabled',
      );
    });

    test('disabling a module hides its quick actions', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );
      expect(
        state.quickActions.any((a) => a.id == 'qa_new_invoice'),
        isTrue,
      );

      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'invoices'}),
      );
      expect(
        state.quickActions.any((a) => a.id == 'qa_new_invoice'),
        isFalse,
      );
    });

    test('recomputation fires notifyListeners', () {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );
      expect(notifyCount, 1);

      // Update with different modules → should fire again.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds.difference({'customers'}),
      );
      expect(notifyCount, 2);
    });

    test('no-op when inputs are unchanged', () {
      int notifyCount = 0;
      state.addListener(() => notifyCount++);

      final modules = allModuleApiIds;
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: modules,
      );
      expect(notifyCount, 1);

      // Same inputs again → no-op.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: modules,
      );
      expect(notifyCount, 1, reason: 'No change → no notification');
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Fallback Safety
  // ═══════════════════════════════════════════════════════════
  group('Fallback Safety', () {
    test('unmappable module strings preserve config unchanged', () {
      // Use module apiIds that don't exist in registry.
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: {'nonexistent_module_a', 'nonexistent_module_b'},
      );

      // _toErpModuleIdSet returns empty, but _enabledModules is non-empty,
      // so _applyModuleVisibility skips filtering → config unchanged.
      expect(state.configuration, isNotNull);
      expect(state.widgets.isNotEmpty, isTrue,
          reason: 'Unmappable modules should not strip all widgets');
    });

    test('empty enabled modules does not crash', () {
      state.updateContext(
        primaryRoleId: 'sys_employee',
        extraRoleIds: [],
        effectivePermissions: {'dashboard.view'},
        enabledModules: <String>{},
      );
      expect(state.configuration, isNotNull);
    });

    test('reset returns to safe default', () {
      state.updateContext(
        primaryRoleId: 'sys_cashier',
        extraRoleIds: [],
        effectivePermissions: salesPerms,
        enabledModules: allModuleApiIds,
      );
      state.reset();

      expect(state.template, DashboardTemplate.basicEmployee);
      expect(state.configuration, isNotNull);
      expect(state.widgets.isNotEmpty, isTrue);
    });
  });
}
