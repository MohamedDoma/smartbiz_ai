// SmartBiz AI — Blueprint Navigation Coordinator Tests.
//
// The coordinator now treats backend session permissions as the sole RBAC
// authority. Local AppRole/OrgState changes must never synthesize permissions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_controller.dart';
import 'package:smartbiz_ai/core/modules/blueprint_navigation_coordinator.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/core/modules/erp_module_dependency_resolver.dart';
import 'package:smartbiz_ai/core/modules/workspace_module_state.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/employees/org_state.dart';

Widget _buildHarness({
  required AppState appState,
  required OrgState orgState,
  required WorkspaceModuleState moduleState,
  required BlueprintNavigationController navCtrl,
  Widget? child,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: appState),
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
  late OrgState orgState;
  late WorkspaceModuleState moduleState;
  late BlueprintNavigationController navCtrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ErpModuleDependencyResolver.clearCache();
    appState = AppState();
    orgState = OrgState();
    moduleState = WorkspaceModuleState();
    navCtrl = BlueprintNavigationController();
  });

  tearDown(() {
    navCtrl.dispose();
    moduleState.dispose();
    orgState.dispose();
    appState.dispose();
  });

  testWidgets('child renders unchanged', (tester) async {
    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('child_sentinel')), findsOneWidget);
  });

  testWidgets('module state is attached after the first frame', (tester) async {
    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    moduleState.enableModule(ErpModuleId.invoices);
    await tester.pumpAndSettle();

    expect(moduleState.isEnabled(ErpModuleId.invoices), isTrue);
    expect(navCtrl.effectivePermissions, isEmpty);
  });

  testWidgets('no backend session means no synthesized permissions',
      (tester) async {
    expect(appState.lastSession, isNull);

    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    expect(navCtrl.effectivePermissions, isEmpty);
  });

  testWidgets('legacy AppRole does not grant navigation permissions',
      (tester) async {
    appState.dispose();
    appState = AppState(role: AppRole.owner);

    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    expect(appState.currentRole, AppRole.owner);
    expect(appState.lastSession, isNull);
    expect(navCtrl.effectivePermissions, isEmpty);
  });

  testWidgets('organization UI mode changes do not create RBAC permissions',
      (tester) async {
    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    orgState.setMode(OrgMode.flat);
    await tester.pumpAndSettle();

    expect(orgState.mode, OrgMode.flat);
    expect(navCtrl.effectivePermissions, isEmpty);
  });

  testWidgets('AppState notifications resync without a build loop',
      (tester) async {
    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    appState.completeOnboarding();
    moduleState.enableModule(ErpModuleId.customers);
    orgState.setMode(OrgMode.departments);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('child_sentinel')), findsOneWidget);
    expect(navCtrl.effectivePermissions, isEmpty);
  });

  testWidgets('disposing coordinator removes listeners safely', (tester) async {
    await tester.pumpWidget(_buildHarness(
      appState: appState,
      orgState: orgState,
      moduleState: moduleState,
      navCtrl: navCtrl,
    ));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(
      () {
        moduleState.enableModule(ErpModuleId.invoices);
        orgState.setMode(OrgMode.flat);
        appState.completeOnboarding();
      },
      returnsNormally,
    );
  });
}
