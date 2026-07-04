import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_registry.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';

void main() {
  const resolver = ErpModuleDependencyResolver();

  setUp(() => ErpModuleDependencyResolver.clearCache());

  group('Scenario A — Automotive Dealership', () {
    final requested = <ErpModuleId>{
      ErpModuleId.dashboard, ErpModuleId.aiChat,
      ErpModuleId.customers, ErpModuleId.leads, ErpModuleId.quotations,
      ErpModuleId.invoices, ErpModuleId.payments,
      ErpModuleId.products, ErpModuleId.inventory,
      ErpModuleId.warehouses, ErpModuleId.suppliers,
      ErpModuleId.procurement, ErpModuleId.purchaseOrders,
      ErpModuleId.reports, ErpModuleId.employees, ErpModuleId.settings,
    };

    test('resolves without errors', () {
      final r = resolver.resolve(requested);
      expect(r.isClean, isTrue);
    });

    test('all requested modules are in resolved set', () {
      final r = resolver.resolve(requested);
      for (final id in requested) {
        expect(r.resolved, contains(id), reason: '${id.name} missing');
      }
    });

    test('no restaurant or manufacturing modules included', () {
      final r = resolver.resolve(requested);
      expect(r.resolved.contains(ErpModuleId.restaurantTables), isFalse);
      expect(r.resolved.contains(ErpModuleId.manufacturing), isFalse);
      expect(r.resolved.contains(ErpModuleId.kitchenDisplay), isFalse);
    });

    test('all resolved modules exist in registry', () {
      final r = resolver.resolve(requested);
      for (final id in r.resolved) {
        expect(ErpModuleRegistry.tryGet(id), isNotNull);
      }
    });
  });

  group('Scenario B — Restaurant', () {
    final requested = <ErpModuleId>{
      ErpModuleId.dashboard, ErpModuleId.aiChat,
      ErpModuleId.pos, ErpModuleId.menuManagement,
      ErpModuleId.restaurantTables, ErpModuleId.restaurantOrders,
      ErpModuleId.kitchenDisplay, ErpModuleId.payments,
      ErpModuleId.customers, ErpModuleId.ingredients,
      ErpModuleId.inventory, ErpModuleId.employees,
      ErpModuleId.reports, ErpModuleId.settings,
    };

    test('resolves without errors', () {
      final r = resolver.resolve(requested);
      expect(r.isClean, isTrue);
    });

    test('POS dependency on products is auto-added', () {
      final r = resolver.resolve(requested);
      expect(r.resolved, contains(ErpModuleId.products));
    });

    test('kitchenDisplay chain resolves correctly', () {
      final r = resolver.resolve(requested);
      expect(r.resolved, containsAll([
        ErpModuleId.kitchenDisplay,
        ErpModuleId.restaurantOrders,
        ErpModuleId.menuManagement,
      ]));
    });

    test('no manufacturing or fleet modules included', () {
      final r = resolver.resolve(requested);
      expect(r.resolved.contains(ErpModuleId.manufacturing), isFalse);
      expect(r.resolved.contains(ErpModuleId.fleet), isFalse);
      expect(r.resolved.contains(ErpModuleId.projects), isFalse);
    });
  });

  group('Scenario C — Software/Service Company', () {
    final requested = <ErpModuleId>{
      ErpModuleId.dashboard, ErpModuleId.aiChat,
      ErpModuleId.customers, ErpModuleId.leads,
      ErpModuleId.projects, ErpModuleId.tasks,
      ErpModuleId.timesheets, ErpModuleId.invoices,
      ErpModuleId.payments, ErpModuleId.support,
      ErpModuleId.employees, ErpModuleId.reports, ErpModuleId.settings,
    };

    test('resolves without errors', () {
      final r = resolver.resolve(requested);
      expect(r.isClean, isTrue);
    });

    test('all requested modules present', () {
      final r = resolver.resolve(requested);
      for (final id in requested) {
        expect(r.resolved, contains(id), reason: '${id.name} missing');
      }
    });

    test('no inventory or restaurant modules included', () {
      final r = resolver.resolve(requested);
      expect(r.resolved.contains(ErpModuleId.inventory), isFalse);
      expect(r.resolved.contains(ErpModuleId.restaurantTables), isFalse);
      expect(r.resolved.contains(ErpModuleId.manufacturing), isFalse);
    });

    test('timesheets dependency on employees satisfied', () {
      final r = resolver.resolve(requested);
      expect(r.resolved, contains(ErpModuleId.employees));
    });
  });

  group('Cross-Scenario', () {
    test('same registry serves all three without if-statements', () {
      final auto = resolver.resolve({ErpModuleId.invoices, ErpModuleId.procurement, ErpModuleId.suppliers});
      final rest = resolver.resolve({ErpModuleId.pos, ErpModuleId.kitchenDisplay, ErpModuleId.menuManagement, ErpModuleId.restaurantOrders});
      final soft = resolver.resolve({ErpModuleId.projects, ErpModuleId.support, ErpModuleId.timesheets, ErpModuleId.employees});
      expect(auto.isClean, isTrue);
      expect(rest.isClean, isTrue);
      expect(soft.isClean, isTrue);
    });
  });

  group('BlueprintModuleSelection', () {
    test('fromJson round-trip', () {
      final sel = BlueprintModuleSelection(
        moduleId: ErpModuleId.invoices,
        enabled: true,
        required: false,
        source: ModuleConfigurationSource.aiRecommended,
        navigationOrder: 5,
      );
      final json = sel.toJson();
      final restored = BlueprintModuleSelection.fromJson(json);
      expect(restored.moduleId, ErpModuleId.invoices);
      expect(restored.enabled, isTrue);
      expect(restored.source, ModuleConfigurationSource.aiRecommended);
      expect(restored.navigationOrder, 5);
    });

    test('fromJson with unknown module throws', () {
      expect(
        () => BlueprintModuleSelection.fromJson({'moduleId': 'nonexistent_xyz'}),
        throwsArgumentError,
      );
    });

    test('fromJson with defaults', () {
      final sel = BlueprintModuleSelection.fromJson({'moduleId': 'dashboard'});
      expect(sel.enabled, isTrue);
      expect(sel.required, isFalse);
      expect(sel.source, ModuleConfigurationSource.ownerSelected);
    });
  });
}
