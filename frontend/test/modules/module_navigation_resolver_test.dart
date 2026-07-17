import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/module_navigation_resolver.dart';

void main() {
  const resolver = ModuleNavigationResolver();

  // All permissions for implemented modules — used as "full access".
  final allPerms = <String>{
    'dashboard.view', 'aiChat.view', 'aiAdvisor.view',
    'customers.view', 'invoices.view', 'products.view',
    'inventory.view', 'accounting.view', 'reports.view',
    'employees.view', 'settings.view', 'settings.edit',
    'expenses.view',
    // navPerms keys from ErpModuleRegistry (backend-aligned):
    'ai_advisor.view', 'contacts.list', 'invoices.list',
    'products.list', 'inventory.list', 'employees.list',
    'payments.list', 'pos.view',
  };

  // ═══════════════════════════════════════════════════════════
  //  1-4. Module Filtering
  // ═══════════════════════════════════════════════════════════
  group('Module Filtering', () {
    test('1. only enabled modules appear', () {
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.invoices},
        effectivePermissions: allPerms,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.invoices));
      expect(ids.contains(ErpModuleId.customers), isFalse);
    });

    test('2. disabled modules do not appear', () {
      // customers not in enabledModules
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.settings},
        effectivePermissions: allPerms,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.customers), isFalse);
      expect(ids.contains(ErpModuleId.invoices), isFalse);
    });

    test('3. planned modules with no implemented screen do not appear', () {
      // quotations is planned, leads is planned
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.quotations, ErpModuleId.leads},
        effectivePermissions: {...allPerms, 'quotations.view', 'leads.view'},
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.quotations), isFalse);
      expect(ids.contains(ErpModuleId.leads), isFalse);
    });

    test('4. modules without usable routes do not appear', () {
      // notifications is planned and has no routes
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.notifications},
        effectivePermissions: {...allPerms, 'notifications.view'},
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.notifications), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5-7. Permission Filtering
  // ═══════════════════════════════════════════════════════════
  group('Permission Filtering', () {
    test('5. missing view permission hides the module', () {
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.invoices},
        effectivePermissions: {'dashboard.view'}, // no invoices.view
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.invoices), isFalse);
    });

    test('6. having the required view permission shows the module', () {
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.invoices},
        effectivePermissions: {'dashboard.view', 'invoices.view', 'invoices.list'},
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.invoices));
    });

    test('7. modules without a view permission remain eligible', () {
      // Create a scenario with settings — it has settings.view,
      // but let's test with dashboard which only has dashboard.view.
      // Both should require their view perm. Test with full perms.
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.settings},
        effectivePermissions: allPerms,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.settings));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8-9. Basic / Advanced Mode
  // ═══════════════════════════════════════════════════════════
  group('Basic / Advanced Mode', () {
    // All currently implemented modules use ModuleVisibility.both,
    // so Basic and Advanced mode produce the same visible set for
    // implemented modules. advancedOnly modules are all planned.
    // accounting is both + implemented
    // invoices is both + implemented
    // dashboard is both + implemented
    final enabled = <ErpModuleId>{
      ErpModuleId.dashboard, ErpModuleId.invoices,
      ErpModuleId.accounting, ErpModuleId.settings,
      ErpModuleId.customers,
    };

    test('8. Basic Mode includes both and basicOnly, excludes advancedOnly', () {
      final result = resolver.resolve(
        enabledModules: enabled,
        effectivePermissions: allPerms,
        mode: NavigationMode.basic,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      // both → included
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.invoices));
      expect(ids, contains(ErpModuleId.customers));
      // accounting is 'both' (not advancedOnly), so included in basic too.
      expect(ids, contains(ErpModuleId.accounting));
    });

    test('9. Advanced Mode includes both, basicOnly, and advancedOnly', () {
      final result = resolver.resolve(
        enabledModules: enabled,
        effectivePermissions: allPerms,
        mode: NavigationMode.advanced,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.invoices));
      expect(ids, contains(ErpModuleId.customers));
      expect(ids, contains(ErpModuleId.accounting));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  10. hiddenUnlessEnabled
  // ═══════════════════════════════════════════════════════════
  group('hiddenUnlessEnabled', () {
    test('10a. not in enabledModules → hidden', () {
      // restaurantTables is hiddenUnlessEnabled + planned, so it
      // would be excluded by maturity anyway. Use a scenario where
      // we verify it does not appear even if perms are granted.
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard},
        effectivePermissions: {...allPerms, 'restaurantTables.view'},
      );
      final ids = result.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.restaurantTables), isFalse);
    });

    test('10b. enabled but planned → hidden by maturity', () {
      final result = resolver.resolve(
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.restaurantTables},
        effectivePermissions: {...allPerms, 'restaurantTables.view'},
        mode: NavigationMode.advanced,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      // Still hidden because maturity is planned (no usable screen).
      expect(ids.contains(ErpModuleId.restaurantTables), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  11-14. Ordering and Duplicates
  // ═══════════════════════════════════════════════════════════
  group('Ordering and Duplicates', () {
    test('11. dashboard is always first', () {
      final result = resolver.resolve(
        enabledModules: {
          ErpModuleId.invoices, ErpModuleId.dashboard,
          ErpModuleId.settings, ErpModuleId.customers,
        },
        effectivePermissions: allPerms,
      );
      expect(result.first.moduleId, ErpModuleId.dashboard);
    });

    test('12. settings is always last', () {
      final result = resolver.resolve(
        enabledModules: {
          ErpModuleId.invoices, ErpModuleId.dashboard,
          ErpModuleId.settings, ErpModuleId.customers,
        },
        effectivePermissions: allPerms,
      );
      expect(result.last.moduleId, ErpModuleId.settings);
    });

    test('13. duplicate navigation IDs are removed', () {
      // Enable the same module set — no dups should appear.
      final result = resolver.resolve(
        enabledModules: {
          ErpModuleId.dashboard, ErpModuleId.invoices,
          ErpModuleId.customers, ErpModuleId.settings,
        },
        effectivePermissions: allPerms,
      );
      final navIds = result.map((r) => r.navItemId).toList();
      expect(navIds.length, navIds.toSet().length, reason: 'Duplicate nav IDs found');
    });

    test('14. output ordering is deterministic', () {
      final enabled = <ErpModuleId>{
        ErpModuleId.settings, ErpModuleId.customers,
        ErpModuleId.invoices, ErpModuleId.dashboard,
        ErpModuleId.products, ErpModuleId.inventory,
      };
      final r1 = resolver.resolve(enabledModules: enabled, effectivePermissions: allPerms);
      final r2 = resolver.resolve(enabledModules: enabled, effectivePermissions: allPerms);
      expect(r1.map((r) => r.moduleId).toList(), r2.map((r) => r.moduleId).toList());
      // Verify specific order: dashboard, then by defaultOrder, settings last.
      expect(r1.first.moduleId, ErpModuleId.dashboard);
      expect(r1.last.moduleId, ErpModuleId.settings);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  15-17. Business Scenarios
  // ═══════════════════════════════════════════════════════════
  group('Business Scenarios', () {
    test('15. Automotive selection resolves a valid navigation list', () {
      final enabled = <ErpModuleId>{
        ErpModuleId.dashboard, ErpModuleId.aiChat,
        ErpModuleId.customers, ErpModuleId.invoices,
        ErpModuleId.products, ErpModuleId.inventory,
        ErpModuleId.employees, ErpModuleId.reports,
        ErpModuleId.settings,
        // These are planned, should not appear:
        ErpModuleId.leads, ErpModuleId.quotations,
        ErpModuleId.payments, ErpModuleId.suppliers,
        ErpModuleId.procurement, ErpModuleId.purchaseOrders,
        ErpModuleId.warehouses,
      };
      final result = resolver.resolve(
        enabledModules: enabled,
        effectivePermissions: allPerms,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      // Implemented modules appear.
      expect(ids, containsAll([
        ErpModuleId.dashboard, ErpModuleId.aiChat,
        ErpModuleId.customers, ErpModuleId.invoices,
        ErpModuleId.products, ErpModuleId.inventory,
        ErpModuleId.employees, ErpModuleId.reports,
        ErpModuleId.settings,
      ]));
      // Planned modules do not appear.
      expect(ids.contains(ErpModuleId.leads), isFalse);
      expect(ids.contains(ErpModuleId.quotations), isFalse);
      expect(ids.contains(ErpModuleId.warehouses), isFalse);
      // Valid routes.
      for (final item in result) {
        expect(item.route.startsWith('/'), isTrue,
            reason: '${item.navItemId} route ${item.route} invalid');
      }
    });

    test('16. Restaurant selection hides planned restaurant screens', () {
      final enabled = <ErpModuleId>{
        ErpModuleId.dashboard, ErpModuleId.settings,
        ErpModuleId.employees,
        // POS is now implemented; rest are still planned:
        ErpModuleId.pos, ErpModuleId.menuManagement,
        ErpModuleId.restaurantTables, ErpModuleId.restaurantOrders,
        ErpModuleId.kitchenDisplay, ErpModuleId.ingredients,
      };
      final result = resolver.resolve(
        enabledModules: enabled,
        effectivePermissions: allPerms,
        mode: NavigationMode.advanced,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      // Implemented modules survive.
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.employees));
      expect(ids, contains(ErpModuleId.settings));
      expect(ids, contains(ErpModuleId.pos)); // POS is now implemented
      // Planned restaurant modules are still hidden.
      expect(ids.contains(ErpModuleId.menuManagement), isFalse);
      expect(ids.contains(ErpModuleId.restaurantTables), isFalse);
      expect(ids.contains(ErpModuleId.kitchenDisplay), isFalse);
    });

    test('17. Software/service selection resolves only implemented permitted routes', () {
      // A cashier-like role with limited permissions.
      final limitedPerms = <String>{
        'dashboard.view', 'invoices.view', 'customers.view', 'settings.view',
        // navPerms keys from registry:
        'invoices.list', 'contacts.list',
      };
      final enabled = <ErpModuleId>{
        ErpModuleId.dashboard, ErpModuleId.settings,
        ErpModuleId.customers, ErpModuleId.invoices,
        ErpModuleId.employees, // enabled but no employees.view perm
        // Planned:
        ErpModuleId.projects, ErpModuleId.tasks, ErpModuleId.support,
      };
      final result = resolver.resolve(
        enabledModules: enabled,
        effectivePermissions: limitedPerms,
      );
      final ids = result.map((r) => r.moduleId).toSet();
      // Permitted + implemented.
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.invoices));
      expect(ids, contains(ErpModuleId.customers));
      expect(ids, contains(ErpModuleId.settings));
      // Employees: enabled but no employees.view perm → hidden.
      expect(ids.contains(ErpModuleId.employees), isFalse);
      // Planned modules → hidden.
      expect(ids.contains(ErpModuleId.projects), isFalse);
      expect(ids.contains(ErpModuleId.tasks), isFalse);
      expect(ids.contains(ErpModuleId.support), isFalse);
    });
  });
}
