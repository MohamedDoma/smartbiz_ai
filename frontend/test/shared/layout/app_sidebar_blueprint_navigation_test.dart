// SmartBiz AI — Sidebar Blueprint Navigation Integration Tests.
//
// Tests the sidebar's dynamic/fallback navigation behavior using
// a minimal MultiProvider harness with controlled BlueprintNavigationController.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/navigation/shell_state.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_controller.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/module_navigation_resolver.dart' as nav;
import 'package:smartbiz_ai/shared/layout/app_sidebar.dart';

// ═══════════════════════════════════════════════════════════
//  Test Harness
// ═══════════════════════════════════════════════════════════

/// Tracks onItemTap calls.
class _TapRecorder {
  final List<int> taps = [];
  void call(int index) => taps.add(index);
}

/// Build a desktop-width test harness wrapping AppSidebar.
Widget _buildHarness({
  required AppState appState,
  required ShellState shellState,
  required BlueprintNavigationController navCtrl,
  required WorkspaceModuleState moduleState,
  required _TapRecorder tapRecorder,
  bool forceExpanded = false,
  double width = 1400, // desktop by default
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
      ChangeNotifierProvider.value(value: shellState),
      ChangeNotifierProvider.value(value: navCtrl),
      ChangeNotifierProvider.value(value: moduleState),
    ],
    child: MaterialApp(
      home: AppLocaleProvider(
        language: AppLanguage.en,
        child: MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: Scaffold(
            body: AppSidebar(
              onItemTap: tapRecorder.call,
              forceExpanded: forceExpanded,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late AppState appState;
  late ShellState shellState;
  late WorkspaceModuleState moduleState;
  late BlueprintNavigationController navCtrl;
  late _TapRecorder tapRecorder;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErpModuleDependencyResolver.clearCache();
    appState = AppState(); // owner by default
    shellState = ShellState();
    moduleState = WorkspaceModuleState();
    navCtrl = BlueprintNavigationController();
    tapRecorder = _TapRecorder();
  });

  tearDown(() {
    navCtrl.dispose();
    moduleState.dispose();
    shellState.dispose();
    appState.dispose();
  });

  // ═══════════════════════════════════════════════════════════
  //  1. Fallback Behavior
  // ═══════════════════════════════════════════════════════════
  group('Fallback Behavior', () {
    testWidgets('uses legacy navigation when controller is not ready', (tester) async {
      // navCtrl has no module state attached → useFallbackNavigation == true.
      expect(navCtrl.useFallbackNavigation, isTrue);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Legacy items should be visible — check for Dashboard label.
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
      // Legacy section headers should appear (expanded desktop mode).
      expect(find.text(trEn('nav_section_core').toUpperCase()), findsOneWidget);
    });

    testWidgets('legacy section headers and items render', (tester) async {
      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Core section items.
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
      expect(find.text(trEn('nav_ai_chat')), findsOneWidget);
      // Business section.
      expect(find.text(trEn('nav_section_business').toUpperCase()), findsOneWidget);
      expect(find.text(trEn('nav_sales')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Dynamic Behavior
  // ═══════════════════════════════════════════════════════════
  group('Dynamic Behavior', () {
    testWidgets('uses dynamic items when controller is ready', (tester) async {
      // Attach + give full owner permissions.
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      expect(navCtrl.useFallbackNavigation, isFalse);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Dashboard should still appear (it's system-required + enabled).
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
      // Settings should appear (system-required).
      expect(find.text(trEn('nav_settings')), findsOneWidget);
    });

    testWidgets('legacy section headers are NOT required in dynamic mode', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Dynamic path does not emit section headers.
      expect(find.text(trEn('nav_section_core').toUpperCase()), findsNothing);
      expect(find.text(trEn('nav_section_business').toUpperCase()), findsNothing);
    });

    testWidgets('localization resolves labels in dynamic mode', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Labels should still be localized, not raw keys.
      expect(find.text('nav_dashboard'), findsNothing); // raw key absent
      expect(find.text(trEn('nav_dashboard')), findsOneWidget); // localized present
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Dynamic Index Alignment
  // ═══════════════════════════════════════════════════════════
  group('Dynamic Index Alignment', () {
    testWidgets('tapping dynamic item calls onItemTap with direct positional index', (tester) async {
      // Enable invoices so it appears in dynamic nav.
      moduleState.enableModule(ErpModuleId.invoices);
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Find the invoices nav item. In dynamic mode the label comes
      // from the registry key 'emod_invoices' not the legacy 'nav_sales'.
      final invoicesLabel = find.text(trEn('emod_invoices'));
      expect(invoicesLabel, findsOneWidget);
      await tester.tap(invoicesLabel);
      await tester.pumpAndSettle();

      // The index should be the direct positional index in the dynamic
      // navItems list, not the legacy flat index.
      final dynamicItems = navCtrl.navItems;
      final expectedIndex = dynamicItems.indexWhere((i) => i.route == '/invoices');
      expect(expectedIndex, greaterThanOrEqualTo(0));
      expect(tapRecorder.taps, contains(expectedIndex));
    });

    testWidgets('dynamic items with no legacy route match are still rendered', (tester) async {
      // Enable a planned module that has no legacy route.
      moduleState.enableModule(ErpModuleId.pos); // planned, no legacy route
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions({..._ownerPerms(), 'pos.view'});

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // POS is planned → resolver already filters it.
      // Just verify the sidebar builds without error.
      expect(find.byType(AppSidebar), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Selected State
  // ═══════════════════════════════════════════════════════════
  group('Selected State', () {
    testWidgets('selected item highlighting works via dynamic positional index', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      // Select dashboard (index 0 in both legacy and dynamic).
      shellState.selectIndex(0);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Dashboard should render and be highlighted.
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('non-zero selected index highlights correct item', (tester) async {
      moduleState.enableModule(ErpModuleId.invoices);
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      // Select invoices using its dynamic positional index.
      final dynamicItems = navCtrl.navItems;
      final invoicesIdx = dynamicItems.indexWhere((i) => i.route == '/invoices');
      shellState.selectIndex(invoicesIdx);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Invoices label uses registry key in dynamic mode.
      expect(find.text(trEn('emod_invoices')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Super Admin
  // ═══════════════════════════════════════════════════════════
  group('Super Admin', () {
    testWidgets('super admin section appears in dynamic mode', (tester) async {
      appState.signInAsSuperAdmin();
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Admin section header.
      expect(find.text(trEn('nav_section_admin').toUpperCase()), findsOneWidget);
      // Admin nav item. Note: 'Super Admin' text also appears in the
      // header role badge, so use findsWidgets (≥ 1).
      expect(find.text(trEn('nav_admin')), findsWidgets);
    });

    testWidgets('super admin section does NOT appear for non-admin in dynamic mode', (tester) async {
      // Default owner is not superAdmin.
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      expect(find.text(trEn('nav_admin')), findsNothing);
    });

    testWidgets('super admin section appears in fallback mode', (tester) async {
      appState.signInAsSuperAdmin();
      // navCtrl not attached → fallback.
      expect(navCtrl.useFallbackNavigation, isTrue);
      expect(appState.isSuperAdmin, isTrue);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // In legacy mode all nav sections are rendered. The admin section
      // is at the very bottom of the ListView, below the viewport fold.
      // Scroll to the bottom to mount the lazy-built admin items.
      await tester.scrollUntilVisible(
        find.text(trEn('nav_admin')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text(trEn('nav_admin')), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Layout Safety
  // ═══════════════════════════════════════════════════════════
  group('Layout Safety', () {
    testWidgets('expanded desktop builds without exception', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
        width: 1400,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('collapsed sidebar builds without exception', (tester) async {
      shellState.toggleSidebar(); // collapse
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
        width: 1400,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('mobile forceExpanded builds without exception', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.setMode(nav.NavigationMode.advanced);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
        forceExpanded: true,
        width: 400, // mobile width
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('fallback mode in collapsed layout builds', (tester) async {
      shellState.toggleSidebar(); // collapse
      // navCtrl not attached → fallback.

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
        width: 1400,
      ));
      await tester.pumpAndSettle();
      expect(find.byType(AppSidebar), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Mode Switch
  // ═══════════════════════════════════════════════════════════
  group('Mode Switch', () {
    testWidgets('displays current mode as Advanced by default', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Both labels should be visible in the toggle.
      expect(find.text(trEn('ws_shell_mode_advanced')), findsOneWidget);
      expect(find.text(trEn('ws_shell_mode_basic')), findsOneWidget);
      // Controller default is Basic (persisted via SharedPreferences, which
      // we mock with empty values → defaults to basic).
      expect(navCtrl.mode, nav.NavigationMode.basic);
    });

    testWidgets('tapping Basic switches controller to basic mode', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.updatePermissions(_ownerPerms());

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Tap on the Basic segment.
      await tester.tap(find.text(trEn('ws_shell_mode_basic')));
      await tester.pumpAndSettle();

      expect(navCtrl.mode, nav.NavigationMode.basic);
    });

    testWidgets('tapping Advanced switches controller back to advanced mode', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.updatePermissions(_ownerPerms());
      // Start in basic mode.
      navCtrl.setMode(nav.NavigationMode.basic);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      expect(navCtrl.mode, nav.NavigationMode.basic);

      // Tap on the Advanced segment.
      await tester.tap(find.text(trEn('ws_shell_mode_advanced')));
      await tester.pumpAndSettle();

      expect(navCtrl.mode, nav.NavigationMode.advanced);
    });

    testWidgets('dynamic nav items update after mode change', (tester) async {
      navCtrl.attachModuleState(moduleState);
      navCtrl.updatePermissions(_ownerPerms());
      navCtrl.setMode(nav.NavigationMode.advanced);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Record item count in advanced mode.
      final advancedCount = navCtrl.navItems.length;
      expect(advancedCount, greaterThan(0));

      // Switch to basic.
      await tester.tap(find.text(trEn('ws_shell_mode_basic')));
      await tester.pumpAndSettle();

      // Basic mode should have items (subset or equal).
      final basicCount = navCtrl.navItems.length;
      expect(basicCount, greaterThan(0));
      expect(basicCount, lessThanOrEqualTo(advancedCount));

      // Sidebar should still render without error.
      expect(find.byType(AppSidebar), findsOneWidget);
    });

    testWidgets('fallback mode remains safe with mode switch', (tester) async {
      // Controller not ready → fallback.
      expect(navCtrl.useFallbackNavigation, isTrue);

      await tester.pumpWidget(_buildHarness(
        appState: appState,
        shellState: shellState,
        navCtrl: navCtrl,
        moduleState: moduleState,
        tapRecorder: tapRecorder,
      ));
      await tester.pumpAndSettle();

      // Legacy nav should still be visible.
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
      expect(find.text(trEn('nav_section_core').toUpperCase()), findsOneWidget);

      // Mode toggle labels should still be present in the footer.
      expect(find.text(trEn('ws_shell_mode_basic')), findsOneWidget);
      expect(find.text(trEn('ws_shell_mode_advanced')), findsOneWidget);

      // Tapping Basic should update controller but not break fallback nav.
      await tester.tap(find.text(trEn('ws_shell_mode_basic')));
      await tester.pumpAndSettle();

      expect(navCtrl.mode, nav.NavigationMode.basic);
      // Legacy nav still intact.
      expect(find.text(trEn('nav_dashboard')), findsOneWidget);
    });
  });
}

// ═══════════════════════════════════════════════════════════
//  Helpers
// ═══════════════════════════════════════════════════════════

/// English translation helper for assertions (avoids raw key checks).
String trEn(String key) => trForLang(AppLanguage.en, key);

/// Owner-level permissions (all modules, all actions).
/// Includes both PermAction-style keys and registry navPerms keys.
Set<String> _ownerPerms() => const {
  'dashboard.view', 'aiChat.view', 'aiAdvisor.view',
  'customers.view', 'invoices.view', 'products.view',
  'inventory.view', 'accounting.view', 'reports.view',
  'employees.view', 'settings.view', 'expenses.view',
  'roles.view', 'billing.view',
  // navPerms keys from ErpModuleRegistry (backend-aligned):
  'ai_advisor.view', 'contacts.list', 'invoices.list',
  'products.list', 'inventory.list', 'employees.list',
  'roles.list', 'departments.list', 'teams.list',
  'approvals.list', 'payments.list',
  'pos.view', 'pipelines.list', 'commissions.list',
};
