import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';

void main() {
  const resolver = ErpModuleDependencyResolver();

  setUp(() => ErpModuleDependencyResolver.clearCache());

  group('Dependency Expansion', () {
    test('module with no deps resolves to itself', () {
      final r = resolver.resolve({ErpModuleId.dashboard});
      expect(r.resolved, contains(ErpModuleId.dashboard));
      expect(r.addedDependencies, isEmpty);
      expect(r.isClean, isTrue);
    });

    test('POS pulls in products and payments', () {
      final r = resolver.resolve({ErpModuleId.pos});
      expect(r.resolved, containsAll([ErpModuleId.pos, ErpModuleId.products, ErpModuleId.payments]));
      expect(r.addedDependencies, containsAll([ErpModuleId.products, ErpModuleId.payments]));
    });

    test('kitchenDisplay pulls restaurantOrders and menuManagement', () {
      final r = resolver.resolve({ErpModuleId.kitchenDisplay});
      expect(r.resolved, containsAll([
        ErpModuleId.kitchenDisplay, ErpModuleId.restaurantOrders, ErpModuleId.menuManagement,
      ]));
    });

    test('warehouseTransfers pulls inventory and warehouses', () {
      final r = resolver.resolve({ErpModuleId.warehouseTransfers});
      expect(r.resolved, containsAll([
        ErpModuleId.warehouseTransfers, ErpModuleId.inventory, ErpModuleId.warehouses,
      ]));
    });

    test('productionOrders pulls bom and products', () {
      final r = resolver.resolve({ErpModuleId.productionOrders});
      expect(r.resolved, containsAll([
        ErpModuleId.productionOrders, ErpModuleId.bom, ErpModuleId.products,
      ]));
    });

    test('already included deps are not double-added', () {
      final r = resolver.resolve({ErpModuleId.pos, ErpModuleId.products});
      final productCount = r.resolved.where((id) => id == ErpModuleId.products).length;
      expect(productCount, 1);
      // products was already requested so not in addedDependencies
      expect(r.addedDependencies.contains(ErpModuleId.products), isFalse);
    });

    test('payroll pulls employees', () {
      final r = resolver.resolve({ErpModuleId.payroll});
      expect(r.resolved, contains(ErpModuleId.employees));
    });

    test('procurement pulls suppliers', () {
      final r = resolver.resolve({ErpModuleId.procurement});
      expect(r.resolved, contains(ErpModuleId.suppliers));
    });
  });

  group('Missing Dependency Detection', () {
    test('missingRequired returns deps not in requested set', () {
      final missing = resolver.missingRequired({ErpModuleId.pos});
      expect(missing, containsAll([ErpModuleId.products, ErpModuleId.payments]));
    });

    test('no missing when all deps included', () {
      final missing = resolver.missingRequired(
          {ErpModuleId.pos, ErpModuleId.products, ErpModuleId.payments});
      expect(missing, isEmpty);
    });
  });

  group('Circular Dependency Protection', () {
    // The registry has no circular deps, so this tests the mechanism works
    test('existing registry has no circular dependencies', () {
      final all = ErpModuleId.values.toSet();
      final r = resolver.resolve(all);
      expect(r.circularChains, isEmpty);
    });
  });

  group('Validation', () {
    test('valid module set produces no errors', () {
      final errors = resolver.validate({ErpModuleId.invoices, ErpModuleId.customers});
      expect(errors, isEmpty);
    });

    test('resolve all modules at once succeeds', () {
      final r = resolver.resolve(ErpModuleId.values.toSet());
      expect(r.isClean, isTrue);
      expect(r.resolved.length, ErpModuleId.values.length);
    });
  });

  group('Caching', () {
    test('repeated resolution uses cache', () {
      final r1 = resolver.resolve({ErpModuleId.pos});
      final r2 = resolver.resolve({ErpModuleId.pos});
      expect(identical(r1, r2), isTrue);
    });

    test('clearCache invalidates', () {
      resolver.resolve({ErpModuleId.pos});
      ErpModuleDependencyResolver.clearCache();
      final r2 = resolver.resolve({ErpModuleId.pos});
      expect(r2.isClean, isTrue);
    });
  });
}
