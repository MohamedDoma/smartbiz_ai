import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';

void main() {
  late WorkspaceModuleState state;
  int notifyCount = 0;

  setUp(() {
    ErpModuleDependencyResolver.clearCache();
    state = WorkspaceModuleState();
    notifyCount = 0;
    state.addListener(() => notifyCount++);
  });

  tearDown(() => state.dispose());

  // ═══════════════════════════════════════════════════════════
  //  1. Default State
  // ═══════════════════════════════════════════════════════════
  group('Default State', () {
    test('dashboard is enabled and system-required', () {
      expect(state.isEnabled(ErpModuleId.dashboard), isTrue);
      expect(state.sourceFor(ErpModuleId.dashboard), ModuleConfigurationSource.systemRequired);
    });

    test('settings is enabled and system-required', () {
      expect(state.isEnabled(ErpModuleId.settings), isTrue);
      expect(state.sourceFor(ErpModuleId.settings), ModuleConfigurationSource.systemRequired);
    });

    test('dashboard cannot be disabled', () {
      expect(state.canDisable(ErpModuleId.dashboard), isFalse);
      expect(state.disableModule(ErpModuleId.dashboard), isFalse);
      expect(state.isEnabled(ErpModuleId.dashboard), isTrue);
    });

    test('settings cannot be disabled', () {
      expect(state.canDisable(ErpModuleId.settings), isFalse);
      expect(state.disableModule(ErpModuleId.settings), isFalse);
      expect(state.isEnabled(ErpModuleId.settings), isTrue);
    });

    test('aiChat is enabled but CAN be disabled', () {
      expect(state.isEnabled(ErpModuleId.aiChat), isTrue);
      expect(state.sourceFor(ErpModuleId.aiChat), ModuleConfigurationSource.ownerSelected);
      expect(state.canDisable(ErpModuleId.aiChat), isTrue);
      expect(state.disableModule(ErpModuleId.aiChat), isTrue);
      expect(state.isEnabled(ErpModuleId.aiChat), isFalse);
    });

    test('aiAdvisor is enabled but CAN be disabled', () {
      expect(state.isEnabled(ErpModuleId.aiAdvisor), isTrue);
      expect(state.canDisable(ErpModuleId.aiAdvisor), isTrue);
      expect(state.disableModule(ErpModuleId.aiAdvisor), isTrue);
      expect(state.isEnabled(ErpModuleId.aiAdvisor), isFalse);
    });

    test('blueprintApplied is false initially', () {
      expect(state.blueprintApplied, isFalse);
    });

    test('default has exactly 4 enabled modules', () {
      expect(state.enabledModuleIds.length, 4);
      expect(state.enabledModuleIds, containsAll([
        ErpModuleId.dashboard, ErpModuleId.settings,
        ErpModuleId.aiChat, ErpModuleId.aiAdvisor,
      ]));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Dependency Enablement
  // ═══════════════════════════════════════════════════════════
  group('Dependency Enablement', () {
    test('enabling POS auto-adds products and payments', () {
      final added = state.enableModule(ErpModuleId.pos);
      expect(added, containsAll([ErpModuleId.products, ErpModuleId.payments]));
      expect(state.isEnabled(ErpModuleId.products), isTrue);
      expect(state.isEnabled(ErpModuleId.payments), isTrue);
    });

    test('auto-added deps have source: dependency', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.sourceFor(ErpModuleId.products), ModuleConfigurationSource.dependency);
      expect(state.sourceFor(ErpModuleId.payments), ModuleConfigurationSource.dependency);
    });

    test('POS itself has source: ownerSelected', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.sourceFor(ErpModuleId.pos), ModuleConfigurationSource.ownerSelected);
    });

    test('enabling already-enabled module returns empty set', () {
      state.enableModule(ErpModuleId.pos);
      final added2 = state.enableModule(ErpModuleId.pos);
      expect(added2, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Disable Protection
  // ═══════════════════════════════════════════════════════════
  group('Disable Protection', () {
    test('products cannot be disabled while POS requires it', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.canDisable(ErpModuleId.products), isFalse);
      expect(state.disableModule(ErpModuleId.products), isFalse);
      expect(state.isEnabled(ErpModuleId.products), isTrue);
    });

    test('payments cannot be disabled while POS requires it', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.canDisable(ErpModuleId.payments), isFalse);
      expect(state.disableModule(ErpModuleId.payments), isFalse);
    });

    test('dependentsOf returns the blocking module', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.dependentsOf(ErpModuleId.products), contains(ErpModuleId.pos));
      expect(state.dependentsOf(ErpModuleId.payments), contains(ErpModuleId.pos));
    });

    test('system-required modules cannot be disabled even with no dependents', () {
      expect(state.canDisable(ErpModuleId.dashboard), isFalse);
      expect(state.canDisable(ErpModuleId.settings), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Orphan Cleanup
  // ═══════════════════════════════════════════════════════════
  group('Orphan Cleanup', () {
    test('disabling POS cleans dependency-only products and payments', () {
      state.enableModule(ErpModuleId.pos);
      expect(state.isEnabled(ErpModuleId.products), isTrue);
      expect(state.isEnabled(ErpModuleId.payments), isTrue);

      state.disableModule(ErpModuleId.pos);
      expect(state.isEnabled(ErpModuleId.pos), isFalse);
      expect(state.isEnabled(ErpModuleId.products), isFalse);
      expect(state.isEnabled(ErpModuleId.payments), isFalse);
    });

    test('owner-selected dependency is NOT cleaned as orphan', () {
      // Explicitly enable products first as ownerSelected.
      state.enableModule(ErpModuleId.products);
      expect(state.sourceFor(ErpModuleId.products), ModuleConfigurationSource.ownerSelected);

      // Now enable POS — payments is added as dep, products already present.
      state.enableModule(ErpModuleId.pos);

      // Disable POS.
      state.disableModule(ErpModuleId.pos);

      // Products stays because it was ownerSelected, not dependency.
      expect(state.isEnabled(ErpModuleId.products), isTrue);
      // Payments was dependency-only, so it gets cleaned.
      expect(state.isEnabled(ErpModuleId.payments), isFalse);
    });

    test('AI-recommended dependency is NOT cleaned as orphan', () {
      state.enableModule(ErpModuleId.products,
          source: ModuleConfigurationSource.aiRecommended);
      state.enableModule(ErpModuleId.pos);
      state.disableModule(ErpModuleId.pos);

      // Products stays because it was aiRecommended.
      expect(state.isEnabled(ErpModuleId.products), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Nested Dependency Cleanup
  // ═══════════════════════════════════════════════════════════
  group('Nested Dependency Cleanup', () {
    test('kitchenDisplay chain is cleaned on disable', () {
      // kitchenDisplay → restaurantOrders → menuManagement
      state.enableModule(ErpModuleId.kitchenDisplay);
      expect(state.isEnabled(ErpModuleId.kitchenDisplay), isTrue);
      expect(state.isEnabled(ErpModuleId.restaurantOrders), isTrue);
      expect(state.isEnabled(ErpModuleId.menuManagement), isTrue);

      state.disableModule(ErpModuleId.kitchenDisplay);
      expect(state.isEnabled(ErpModuleId.kitchenDisplay), isFalse);
      expect(state.isEnabled(ErpModuleId.restaurantOrders), isFalse);
      expect(state.isEnabled(ErpModuleId.menuManagement), isFalse);
    });

    test('shared dependency stays if another module still needs it', () {
      // Enable kitchenDisplay (pulls restaurantOrders + menuManagement).
      state.enableModule(ErpModuleId.kitchenDisplay);
      // Also explicitly enable restaurantOrders as ownerSelected.
      state.enableModule(ErpModuleId.restaurantOrders,
          source: ModuleConfigurationSource.ownerSelected);

      // Disable kitchenDisplay — restaurantOrders stays (ownerSelected).
      state.disableModule(ErpModuleId.kitchenDisplay);
      expect(state.isEnabled(ErpModuleId.restaurantOrders), isTrue);
      // menuManagement is dep of restaurantOrders, so it stays too.
      expect(state.isEnabled(ErpModuleId.menuManagement), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Blueprint Application
  // ═══════════════════════════════════════════════════════════
  group('Blueprint Application', () {
    test('applies selections and sets blueprintApplied', () {
      state.applyBlueprint([
        BlueprintModuleSelection(
          moduleId: ErpModuleId.invoices,
          source: ModuleConfigurationSource.aiRecommended,
          navigationOrder: 1,
        ),
        BlueprintModuleSelection(
          moduleId: ErpModuleId.customers,
          source: ModuleConfigurationSource.ownerSelected,
          navigationOrder: 2,
          settings: {'showVip': true},
        ),
      ]);

      expect(state.blueprintApplied, isTrue);
      expect(state.isEnabled(ErpModuleId.invoices), isTrue);
      expect(state.isEnabled(ErpModuleId.customers), isTrue);
      expect(state.sourceFor(ErpModuleId.invoices), ModuleConfigurationSource.aiRecommended);
      expect(state.settingsFor(ErpModuleId.customers), {'showVip': true});
      expect(state.navigationOrderFor(ErpModuleId.invoices), 1);
    });

    test('blueprint always restores dashboard and settings', () {
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.invoices),
      ]);

      expect(state.isEnabled(ErpModuleId.dashboard), isTrue);
      expect(state.isEnabled(ErpModuleId.settings), isTrue);
      expect(state.sourceFor(ErpModuleId.dashboard), ModuleConfigurationSource.systemRequired);
    });

    test('blueprint with POS adds missing deps', () {
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.pos),
      ]);

      expect(state.isEnabled(ErpModuleId.pos), isTrue);
      expect(state.isEnabled(ErpModuleId.products), isTrue);
      expect(state.isEnabled(ErpModuleId.payments), isTrue);
      expect(state.sourceFor(ErpModuleId.products), ModuleConfigurationSource.dependency);
    });

    test('blueprint replaces previous state', () {
      state.enableModule(ErpModuleId.inventory);
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.customers),
      ]);

      // Inventory was not in the new blueprint.
      expect(state.isEnabled(ErpModuleId.inventory), isFalse);
      expect(state.isEnabled(ErpModuleId.customers), isTrue);
    });

    test('no duplicate selections', () {
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.invoices, navigationOrder: 1),
        BlueprintModuleSelection(moduleId: ErpModuleId.invoices, navigationOrder: 2),
      ]);
      // Last one wins in the map.
      expect(state.navigationOrderFor(ErpModuleId.invoices), 2);
      // Only one selection per module.
      final invoiceSelections = state.selections
          .where((s) => s.moduleId == ErpModuleId.invoices)
          .length;
      expect(invoiceSelections, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Reset
  // ═══════════════════════════════════════════════════════════
  group('Reset', () {
    test('reset returns to default state', () {
      state.enableModule(ErpModuleId.invoices);
      state.enableModule(ErpModuleId.pos);
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.customers),
      ]);

      state.reset();

      expect(state.blueprintApplied, isFalse);
      expect(state.enabledModuleIds.length, 4);
      expect(state.isEnabled(ErpModuleId.dashboard), isTrue);
      expect(state.isEnabled(ErpModuleId.settings), isTrue);
      expect(state.isEnabled(ErpModuleId.aiChat), isTrue);
      expect(state.isEnabled(ErpModuleId.aiAdvisor), isTrue);
      expect(state.isEnabled(ErpModuleId.invoices), isFalse);
      expect(state.isEnabled(ErpModuleId.pos), isFalse);
      expect(state.isEnabled(ErpModuleId.customers), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8. Change Notifications
  // ═══════════════════════════════════════════════════════════
  group('Change Notifications', () {
    test('enableModule notifies once', () {
      state.enableModule(ErpModuleId.invoices);
      expect(notifyCount, 1);
    });

    test('disableModule notifies once', () {
      state.enableModule(ErpModuleId.invoices);
      notifyCount = 0;
      state.disableModule(ErpModuleId.invoices);
      expect(notifyCount, 1);
    });

    test('enabling already-enabled does not notify', () {
      state.enableModule(ErpModuleId.invoices);
      notifyCount = 0;
      state.enableModule(ErpModuleId.invoices);
      expect(notifyCount, 0);
    });

    test('failed disable does not notify', () {
      state.enableModule(ErpModuleId.pos);
      notifyCount = 0;
      state.disableModule(ErpModuleId.products); // protected
      expect(notifyCount, 0);
    });

    test('applyBlueprint notifies once', () {
      state.applyBlueprint([
        BlueprintModuleSelection(moduleId: ErpModuleId.invoices),
        BlueprintModuleSelection(moduleId: ErpModuleId.customers),
        BlueprintModuleSelection(moduleId: ErpModuleId.products),
      ]);
      expect(notifyCount, 1);
    });

    test('reset notifies once', () {
      state.enableModule(ErpModuleId.invoices);
      notifyCount = 0;
      state.reset();
      expect(notifyCount, 1);
    });
  });
}
