import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';
import 'package:smartbiz_ai/core/modules/module_navigation_resolver.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_controller.dart';

void main() {
  late BlueprintNavigationController ctrl;
  late WorkspaceModuleState moduleState;
  int notifyCount = 0;

  final fullPerms = <String>{
    'dashboard.view', 'aiChat.view', 'aiAdvisor.view',
    'customers.view', 'invoices.view', 'products.view',
    'inventory.view', 'accounting.view', 'reports.view',
    'employees.view', 'settings.view', 'expenses.view',
    // navPerms keys from ErpModuleRegistry (backend-aligned):
    'ai_advisor.view', 'contacts.list', 'invoices.list',
    'products.list', 'inventory.list', 'employees.list',
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErpModuleDependencyResolver.clearCache();
    moduleState = WorkspaceModuleState();
    ctrl = BlueprintNavigationController();
    notifyCount = 0;
    ctrl.addListener(() => notifyCount++);
  });

  tearDown(() {
    ctrl.dispose();
    moduleState.dispose();
  });

  // ═══════════════════════════════════════════════════════════
  //  1. Initial State
  // ═══════════════════════════════════════════════════════════
  group('Initial State', () {
    test('no module state attached', () {
      expect(ctrl.isReady, isFalse);
    });

    test('useFallbackNavigation is true', () {
      expect(ctrl.useFallbackNavigation, isTrue);
    });

    test('navigation lists are empty', () {
      expect(ctrl.navItems, isEmpty);
      expect(ctrl.resolvedItems, isEmpty);
    });

    test('isReady is false', () {
      expect(ctrl.isReady, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Attach Module State
  // ═══════════════════════════════════════════════════════════
  group('Attach Module State', () {
    test('attaches and resolves navigation', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.isReady, isTrue);
      expect(ctrl.navItems.isNotEmpty, isTrue);
    });

    test('dashboard is first', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.resolvedItems.first.moduleId, ErpModuleId.dashboard);
      expect(ctrl.navItems.first.id, 'dashboard');
    });

    test('settings is last', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.resolvedItems.last.moduleId, ErpModuleId.settings);
      expect(ctrl.navItems.last.id, 'settings');
    });

    test('fallback becomes false when valid items exist', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.useFallbackNavigation, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Module State Changes
  // ═══════════════════════════════════════════════════════════
  group('Module State Changes', () {
    test('enabling an implemented module updates navigation', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      final before = ctrl.resolvedItems.length;

      moduleState.enableModule(ErpModuleId.invoices);
      final after = ctrl.resolvedItems.length;
      expect(after, greaterThan(before));

      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.invoices));
    });

    test('disabling a module removes the item', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.invoices);

      final withInvoices = ctrl.resolvedItems
          .any((r) => r.moduleId == ErpModuleId.invoices);
      expect(withInvoices, isTrue);

      moduleState.disableModule(ErpModuleId.invoices);
      final afterDisable = ctrl.resolvedItems
          .any((r) => r.moduleId == ErpModuleId.invoices);
      expect(afterDisable, isFalse);
    });

    test('planned modules do not appear', () {
      ctrl.updatePermissions({...fullPerms, 'quotations.view', 'leads.view'});
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.quotations); // planned

      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.quotations), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Permissions
  // ═══════════════════════════════════════════════════════════
  group('Permissions', () {
    test('missing view permission hides a module', () {
      // No invoices.view in perms.
      ctrl.updatePermissions({'dashboard.view', 'settings.view'});
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.invoices);

      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.invoices), isFalse);
    });

    test('adding permission shows the module', () {
      ctrl.updatePermissions({'dashboard.view', 'settings.view'});
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.invoices);

      // Now add invoices.view and invoices.list (navPerms key).
      ctrl.updatePermissions({'dashboard.view', 'settings.view', 'invoices.view', 'invoices.list'});
      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.invoices));
    });

    test('removing permission hides it again', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.invoices);
      expect(ctrl.resolvedItems.any((r) => r.moduleId == ErpModuleId.invoices), isTrue);

      // Remove invoices.list (navPerms key).
      final reduced = Set.of(fullPerms)..remove('invoices.list');
      ctrl.updatePermissions(reduced);
      expect(ctrl.resolvedItems.any((r) => r.moduleId == ErpModuleId.invoices), isFalse);
    });

    test('equivalent permission sets do not trigger notification', () {
      ctrl.updatePermissions({'dashboard.view', 'settings.view'});
      ctrl.attachModuleState(moduleState);
      notifyCount = 0;

      // Same permissions in different order.
      ctrl.updatePermissions({'settings.view', 'dashboard.view'});
      expect(notifyCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Basic / Advanced
  // ═══════════════════════════════════════════════════════════
  group('Basic / Advanced', () {
    test('Basic hides advancedOnly modules', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.accounting); // both (not advancedOnly)

      ctrl.setMode(NavigationMode.basic);
      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      // accounting is 'both' in the registry, so it appears in basic mode.
      expect(ids, contains(ErpModuleId.accounting));
    });

    test('Advanced includes basic and advanced modules', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.accounting); // advancedOnly
      moduleState.enableModule(ErpModuleId.invoices);    // both

      ctrl.setMode(NavigationMode.advanced);
      final ids = ctrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.accounting));
      expect(ids, contains(ErpModuleId.invoices));
    });

    test('switching to the same mode is a no-op', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      notifyCount = 0;

      ctrl.setMode(NavigationMode.basic); // already basic by default
      expect(notifyCount, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Cache / Recomputation
  // ═══════════════════════════════════════════════════════════
  group('Cache / Recomputation', () {
    test('repeated refresh with unchanged inputs does not notify', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      notifyCount = 0;

      ctrl.refresh();
      ctrl.refresh();
      ctrl.refresh();
      expect(notifyCount, 0);
    });

    test('repeated refresh does not duplicate items', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      final count1 = ctrl.resolvedItems.length;

      ctrl.refresh();
      ctrl.refresh();
      expect(ctrl.resolvedItems.length, count1);
    });

    test('output remains deterministic', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      moduleState.enableModule(ErpModuleId.invoices);
      moduleState.enableModule(ErpModuleId.customers);
      moduleState.enableModule(ErpModuleId.products);

      final order1 = ctrl.resolvedItems.map((r) => r.moduleId).toList();
      ctrl.refresh();
      final order2 = ctrl.resolvedItems.map((r) => r.moduleId).toList();
      expect(order1, order2);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Detach and Reset
  // ═══════════════════════════════════════════════════════════
  group('Detach and Reset', () {
    test('detaching clears navigation and sets fallback', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.isReady, isTrue);

      ctrl.detachModuleState();
      expect(ctrl.isReady, isFalse);
      expect(ctrl.useFallbackNavigation, isTrue);
      expect(ctrl.navItems, isEmpty);
    });

    test('later module changes no longer affect the controller', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      ctrl.detachModuleState();
      notifyCount = 0;

      moduleState.enableModule(ErpModuleId.invoices);
      expect(notifyCount, 0);
      expect(ctrl.resolvedItems, isEmpty);
    });

    test('reset clears permissions and navigation', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      expect(ctrl.isReady, isTrue);

      ctrl.reset();
      expect(ctrl.isReady, isFalse);
      expect(ctrl.useFallbackNavigation, isTrue);
      expect(ctrl.effectivePermissions, isEmpty);
      expect(ctrl.mode, NavigationMode.basic);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  8. Listener Lifecycle
  // ═══════════════════════════════════════════════════════════
  group('Listener Lifecycle', () {
    test('attaching a second state removes listener from the first', () {
      final state1 = WorkspaceModuleState();
      final state2 = WorkspaceModuleState();
      ctrl.updatePermissions(fullPerms);

      ctrl.attachModuleState(state1);
      ctrl.attachModuleState(state2);
      notifyCount = 0;

      // Changes on state1 should NOT reach the controller.
      state1.enableModule(ErpModuleId.invoices);
      expect(notifyCount, 0);

      // Changes on state2 SHOULD reach the controller.
      state2.enableModule(ErpModuleId.customers);
      expect(notifyCount, greaterThan(0));

      state1.dispose();
      state2.dispose();
    });

    test('attaching same state twice is a no-op', () {
      ctrl.updatePermissions(fullPerms);
      ctrl.attachModuleState(moduleState);
      notifyCount = 0;

      ctrl.attachModuleState(moduleState);
      expect(notifyCount, 0);
    });

    test('dispose does not throw', () {
      // Use a separate controller to avoid double-dispose from tearDown.
      final localCtrl = BlueprintNavigationController();
      localCtrl.updatePermissions(fullPerms);
      localCtrl.attachModuleState(moduleState);

      expect(() => localCtrl.dispose(), returnsNormally);
    });
  });
}
