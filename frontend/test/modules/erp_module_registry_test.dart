import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_registry.dart';

void main() {
  group('Registry Integrity', () {
    test('every ErpModuleId has a definition', () {
      for (final id in ErpModuleId.values) {
        expect(ErpModuleRegistry.tryGet(id), isNotNull, reason: '${id.name} missing');
      }
    });

    test('every module ID is unique', () {
      final ids = ErpModuleRegistry.all.map((m) => m.id).toSet();
      expect(ids.length, ErpModuleRegistry.all.length);
    });

    test('every apiId is unique', () {
      final apis = ErpModuleRegistry.all.map((m) => m.apiId).toSet();
      expect(apis.length, ErpModuleRegistry.all.length);
    });

    test('every labelKey is unique', () {
      final keys = ErpModuleRegistry.all.map((m) => m.labelKey).toSet();
      expect(keys.length, ErpModuleRegistry.all.length);
    });

    test('all is sorted by defaultOrder', () {
      final all = ErpModuleRegistry.all;
      for (int i = 1; i < all.length; i++) {
        expect(all[i].defaultOrder >= all[i - 1].defaultOrder, isTrue,
            reason: '${all[i].id.name} order ${all[i].defaultOrder} < ${all[i - 1].id.name} order ${all[i - 1].defaultOrder}');
      }
    });

    test('dependencies reference valid module IDs', () {
      for (final m in ErpModuleRegistry.all) {
        for (final dep in m.dependencies) {
          expect(ErpModuleRegistry.tryGet(dep), isNotNull,
              reason: '${m.id.name} depends on unknown ${dep.name}');
        }
        for (final dep in m.optionalDependencies) {
          expect(ErpModuleRegistry.tryGet(dep), isNotNull,
              reason: '${m.id.name} optionally depends on unknown ${dep.name}');
        }
      }
    });
  });

  group('Maturity', () {
    test('implemented modules have routes', () {
      for (final m in ErpModuleRegistry.implementedModules()) {
        // Settings is special case
        if (m.id == ErpModuleId.settings) continue;
        expect(m.routePaths.isNotEmpty, isTrue,
            reason: '${m.id.name} is implemented but has no routes');
      }
    });

    test('planned modules truthfulness', () {
      final planned = ErpModuleRegistry.byMaturity(ModuleMaturity.planned);
      expect(planned.isNotEmpty, isTrue);
      for (final m in planned) {
        expect(m.maturity, ModuleMaturity.planned);
      }
    });

    test('dashboard is implemented', () {
      expect(ErpModuleRegistry.get(ErpModuleId.dashboard).maturity, ModuleMaturity.implemented);
    });

    test('pos is implemented', () {
      expect(ErpModuleRegistry.get(ErpModuleId.pos).maturity, ModuleMaturity.implemented);
    });

    test('manufacturing is planned', () {
      expect(ErpModuleRegistry.get(ErpModuleId.manufacturing).maturity, ModuleMaturity.planned);
    });
  });

  group('Category Filtering', () {
    test('core category contains dashboard', () {
      final core = ErpModuleRegistry.byCategory(ModuleCategory.core);
      expect(core.any((m) => m.id == ErpModuleId.dashboard), isTrue);
    });

    test('sales category contains invoices', () {
      final sales = ErpModuleRegistry.byCategory(ModuleCategory.sales);
      expect(sales.any((m) => m.id == ErpModuleId.invoices), isTrue);
    });

    test('every module has a valid category', () {
      for (final m in ErpModuleRegistry.all) {
        expect(ModuleCategory.values.contains(m.category), isTrue);
      }
    });
  });

  group('Basic/Advanced Filtering', () {
    test('basic mode includes dashboard, invoices, customers', () {
      final basic = ErpModuleRegistry.basicModeModules();
      final ids = basic.map((m) => m.id).toSet();
      expect(ids.contains(ErpModuleId.dashboard), isTrue);
      expect(ids.contains(ErpModuleId.invoices), isTrue);
      expect(ids.contains(ErpModuleId.customers), isTrue);
    });

    test('advanced mode includes roles, departments', () {
      final adv = ErpModuleRegistry.advancedModeModules();
      final ids = adv.map((m) => m.id).toSet();
      expect(ids.contains(ErpModuleId.roles), isTrue);
      expect(ids.contains(ErpModuleId.departments), isTrue);
    });

    test('manufacturing is advanced only', () {
      final m = ErpModuleRegistry.get(ErpModuleId.manufacturing);
      expect(m.supportsBasicMode, isFalse);
      expect(m.supportsAdvancedMode, isTrue);
    });

    test('restaurant modules are hidden unless enabled', () {
      final m = ErpModuleRegistry.get(ErpModuleId.restaurantTables);
      expect(m.visibility, ModuleVisibility.hiddenUnlessEnabled);
    });
  });

  group('Route Alignment', () {
    test('invoices routes match current router', () {
      final m = ErpModuleRegistry.get(ErpModuleId.invoices);
      expect(m.routePaths, contains('/invoices'));
      expect(m.routePaths, contains('/invoices/create'));
      expect(m.routePaths, contains('/invoices/:id'));
    });

    test('employees routes match current router', () {
      final m = ErpModuleRegistry.get(ErpModuleId.employees);
      expect(m.routePaths, contains('/employees'));
      expect(m.routePaths, contains('/employees/invite'));
    });

    test('inventory routes match current router', () {
      final m = ErpModuleRegistry.get(ErpModuleId.inventory);
      expect(m.routePaths, contains('/inventory'));
      expect(m.routePaths, contains('/inventory/movements'));
      expect(m.routePaths, contains('/inventory/adjustments'));
    });

    test('navigation IDs exist for implemented modules', () {
      for (final m in ErpModuleRegistry.implementedModules()) {
        if (m.id == ErpModuleId.expenses) continue; // sub-route of accounting
        if (m.id == ErpModuleId.roles) continue; // sub-route of employees
        if (m.id == ErpModuleId.departments) continue;
        if (m.id == ErpModuleId.teams) continue;
        expect(m.navigationItemIds.isNotEmpty, isTrue,
            reason: '${m.id.name} is implemented but has no navIds');
      }
    });
  });

  group('Permission Keys', () {
    test('every module has at least one permission (except system-accessible)', () {
      // dashboard and aiChat are intentionally permission-less —
      // they are accessible to all authenticated users.
      const systemAccessible = {ErpModuleId.dashboard, ErpModuleId.aiChat};
      for (final m in ErpModuleRegistry.all) {
        if (systemAccessible.contains(m.id)) continue;
        expect(m.permissionKeys.isNotEmpty, isTrue,
            reason: '${m.id.name} has no permission keys');
      }
    });

    test('permission keys use module-prefixed format', () {
      for (final m in ErpModuleRegistry.all) {
        for (final perm in m.permissionKeys) {
          expect(perm.contains('.'), isTrue,
              reason: 'Permission "$perm" on ${m.id.name} missing dot separator');
        }
      }
    });
  });
}
