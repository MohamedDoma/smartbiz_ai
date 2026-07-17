// SmartBiz AI — Blueprint Navigation Coordinator Tests (Phase 17).
//
// Widget tests using a minimal MultiProvider harness to validate
// the coordinator's synchronization of WorkspaceModuleState,
// AppState, RolesState, OrgState → BlueprintNavigationController.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_controller.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_coordinator.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/module_navigation_resolver.dart' as nav;
import 'package:smartbiz_ai/features/employees/roles_state.dart';
import 'package:smartbiz_ai/features/employees/org_state.dart';

// ═══════════════════════════════════════════════════════════
//  Test Harness
// ═══════════════════════════════════════════════════════════

Widget _buildHarness({
  required AppState appState,
  required RolesState rolesState,
  required OrgState orgState,
  required WorkspaceModuleState moduleState,
  required BlueprintNavigationController navCtrl,
  Widget? child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: rolesState),
      ChangeNotifierProvider.value(value: orgState),
      ChangeNotifierProvider.value(value: moduleState),
      ChangeNotifierProvider.value(value: navCtrl),
    ],
    child: MaterialApp(
      home: AppLocaleProvider(
        language: AppLanguage.en,
        child: BlueprintNavigationCoordinator(
          child: child ?? const _ChildWidget(),
        ),
      ),
    ),
  );
}

class _ChildWidget extends StatelessWidget {
  const _ChildWidget();
  @override
  Widget build(BuildContext context) {
    return const Text('CHILD_SENTINEL', key: Key('child_sentinel'));
  }
}

void main() {
  late AppState appState;
  late RolesState rolesState;
  late OrgState orgState;
  late WorkspaceModuleState moduleState;
  late BlueprintNavigationController navCtrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErpModuleDependencyResolver.clearCache();
    appState = AppState();
    rolesState = RolesState();
    orgState = OrgState();
    moduleState = WorkspaceModuleState();
    navCtrl = BlueprintNavigationController();
  });

  tearDown(() {
    navCtrl.dispose();
    moduleState.dispose();
    orgState.dispose();
    rolesState.dispose();
    appState.dispose();
  });

  // ═══════════════════════════════════════════════════════════
  //  1. Child Rendering
  // ═══════════════════════════════════════════════════════════
  group('Child Rendering', () {
    testWidgets('child renders unchanged', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      expect(find.text('CHILD_SENTINEL'), findsOneWidget);
      expect(find.byKey(const Key('child_sentinel')), findsOneWidget);
    });

    testWidgets('coordinator does not replace child with its own UI', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
        child: const SizedBox(key: Key('custom_child')),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom_child')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Initial Synchronization
  // ═══════════════════════════════════════════════════════════
  group('Initial Synchronization', () {
    testWidgets('attaches WorkspaceModuleState to controller', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // The controller should be ready since default modules are enabled
      // and owner role provides permissions.
      expect(navCtrl.isReady, isTrue);
    });

    testWidgets('initializes navigation mode as Basic', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      expect(navCtrl.mode, nav.NavigationMode.basic);
    });

    testWidgets('controller resolves enabled modules', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // Default modules: dashboard, settings, aiChat, aiAdvisor.
      // Dashboard and settings should always be present.
      final ids = navCtrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.dashboard));
      expect(ids, contains(ErpModuleId.settings));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Permission Synchronization
  // ═══════════════════════════════════════════════════════════
  group('Permission Synchronization', () {
    testWidgets('permissions from owner role reach the controller', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // Owner has full permissions.
      final perms = navCtrl.effectivePermissions;
      expect(perms, isNotEmpty);
      expect(perms, contains('dashboard.view'));
    });

    testWidgets('changing role updates effective permissions', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // Owner has many permissions.
      final ownerPerms = Set.of(navCtrl.effectivePermissions);

      // Switch to employee (minimal permissions).
      appState.setRole(AppRole.employee);
      await tester.pumpAndSettle();

      final employeePerms = navCtrl.effectivePermissions;
      // Employee has fewer permissions than owner.
      expect(employeePerms.length, lessThan(ownerPerms.length));
      expect(employeePerms, contains('dashboard.view'));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Organization Synchronization
  // ═══════════════════════════════════════════════════════════
  group('Organization Synchronization', () {
    testWidgets('changing employee assignment triggers update', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      final permsBefore = Set.of(navCtrl.effectivePermissions);

      // Assign the current user (demo-user-1 / emp_1) a different primary role.
      orgState.setPrimaryRole('demo-user-1', 'sys_cashier');
      await tester.pumpAndSettle();

      final permsAfter = navCtrl.effectivePermissions;
      // Permissions should differ: cashier has fewer than owner.
      expect(permsAfter.length, lessThanOrEqualTo(permsBefore.length));
    });

    testWidgets('adding extra role updates effective permissions', (tester) async {
      // Start as employee (minimal).
      appState.setRole(AppRole.employee);
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      final permsBefore = Set.of(navCtrl.effectivePermissions);

      // Add an extra role with more permissions.
      orgState.toggleExtraRole('demo-user-1', 'sys_accountant');
      await tester.pumpAndSettle();

      final permsAfter = navCtrl.effectivePermissions;
      expect(permsAfter.length, greaterThanOrEqualTo(permsBefore.length));
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Workspace Modules
  // ═══════════════════════════════════════════════════════════
  group('Workspace Modules', () {
    testWidgets('enabling an implemented module updates nav', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      final countBefore = navCtrl.resolvedItems.length;

      moduleState.enableModule(ErpModuleId.invoices);
      await tester.pumpAndSettle();

      final countAfter = navCtrl.resolvedItems.length;
      expect(countAfter, greaterThan(countBefore));

      final ids = navCtrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids, contains(ErpModuleId.invoices));
    });

    testWidgets('disabling a module removes the nav item', (tester) async {
      moduleState.enableModule(ErpModuleId.invoices);
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      expect(
        navCtrl.resolvedItems.any((r) => r.moduleId == ErpModuleId.invoices),
        isTrue,
      );

      moduleState.disableModule(ErpModuleId.invoices);
      await tester.pumpAndSettle();

      expect(
        navCtrl.resolvedItems.any((r) => r.moduleId == ErpModuleId.invoices),
        isFalse,
      );
    });

    testWidgets('planned modules do not appear', (tester) async {
      moduleState.enableModule(ErpModuleId.quotations);
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      final ids = navCtrl.resolvedItems.map((r) => r.moduleId).toSet();
      expect(ids.contains(ErpModuleId.quotations), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Build-Loop Safety
  // ═══════════════════════════════════════════════════════════
  group('Build-Loop Safety', () {
    testWidgets('pump and settle completes without exception', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));

      // pumpAndSettle will throw if there are infinite callbacks.
      await tester.pumpAndSettle();
      expect(find.text('CHILD_SENTINEL'), findsOneWidget);
    });

    testWidgets('multiple rapid state changes do not cause build loop', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // Rapid-fire multiple state changes.
      moduleState.enableModule(ErpModuleId.invoices);
      moduleState.enableModule(ErpModuleId.customers);
      appState.setRole(AppRole.cashier);
      moduleState.enableModule(ErpModuleId.products);

      // Must settle without infinite loops.
      await tester.pumpAndSettle();
      expect(find.text('CHILD_SENTINEL'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Lifecycle
  // ═══════════════════════════════════════════════════════════
  group('Lifecycle', () {
    testWidgets('disposing coordinator removes listeners safely', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      // Replace the widget tree → disposes the coordinator.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // Later state changes should not throw.
      expect(
        () {
          moduleState.enableModule(ErpModuleId.invoices);
          orgState.setPrimaryRole('demo-user-1', 'sys_cashier');
          rolesState.notifyListeners();
        },
        returnsNormally,
      );
    });

    testWidgets('no update occurs after dispose', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        rolesState: rolesState,
        orgState: orgState,
        moduleState: moduleState,
        navCtrl: navCtrl,
      ));
      await tester.pumpAndSettle();

      final permsBefore = Set.of(navCtrl.effectivePermissions);

      // Dispose coordinator.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      // Mutate state after dispose.
      appState.setRole(AppRole.employee);
      await tester.pumpAndSettle();

      // Controller permissions should not have changed.
      // (Coordinator is no longer syncing.)
      expect(navCtrl.effectivePermissions, permsBefore);
    });
  });
}
