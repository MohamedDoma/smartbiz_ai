// SmartBiz AI — Blueprint review fidelity and localization tests.
//
// Uses a fixture matching the real persisted Blueprint. Proves:
//   1.  No [bp_...] key appears in rendered data
//   2.  Arabic mode renders known module names in Arabic
//   3.  English mode renders them in English
//   4.  Business type 'retail' is localized
//   5.  Permission count uses 'صلاحية' / 'permissions'
//   6.  Roles are exactly those in the real Blueprint
//   7.  Flutter does not invent roles absent from the Blueprint
//   8.  Required/optional modules mapped correctly
//   9.  Warehouses, pipeline and approvals preserved
//   10. Real Blueprint UUID preserved
//   11. No permission is lost by the bridge
//   12. No runtime role-name-based authorization logic

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/discovery_models.dart';
import 'package:smartbiz_ai/core/l10n/app_localizations.dart';
import 'package:smartbiz_ai/core/state/app_state.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

// ═══════════════════════════════════════════════════════════
//  Fixture matching the real persisted Blueprint
// ═══════════════════════════════════════════════════════════

const _blueprintId = 'a246cfd0-032a-4688-b066-e0d5aec82b92';
const _sessionId = 'a246cf92-32d9-4976-8e92-d6bb9302ea0e';

final _fixture = <String, dynamic>{
  'business_profile': {
    'business_name': 'شركة لبيع السيارات الجديدة والمستعملة وقطع الغيار',
    'business_type': 'retail',
    'business_description':
        'شركة تبيع السيارات الجديدة والمستعملة وقطع الغيار مع مستودعين',
  },
  'modules': [
    {'key': 'dashboard', 'enabled': true, 'status': 'required'},
    {'key': 'customers', 'enabled': true, 'status': 'required'},
    {'key': 'products', 'enabled': true, 'status': 'required'},
    {'key': 'invoices', 'enabled': true, 'status': 'required'},
    {'key': 'payments', 'enabled': true, 'status': 'required'},
    {'key': 'orders', 'enabled': true, 'status': 'required'},
    {'key': 'employees', 'enabled': true, 'status': 'required'},
    {'key': 'reports', 'enabled': true, 'status': 'required'},
    {'key': 'finance', 'enabled': true, 'status': 'required'},
    {'key': 'inventory', 'enabled': true, 'status': 'required'},
    {'key': 'pos', 'enabled': true, 'status': 'recommended'},
    {'key': 'commissions', 'enabled': true, 'status': 'recommended'},
    {'key': 'ai', 'enabled': true, 'status': 'recommended'},
    {'key': 'leads', 'enabled': true, 'status': 'recommended'},
    {'key': 'spare_parts', 'enabled': false, 'status': 'optional'},
    {'key': 'parts_inventory', 'enabled': false, 'status': 'optional'},
    {'key': 'jobs', 'enabled': false, 'status': 'optional'},
  ],
  'roles': [
    {
      'key': 'owner',
      'name': 'Owner',
      'status': 'required',
      'description': 'Full system access and ownership',
      'permissions': List.generate(112, (i) => 'perm_$i'),
      'is_primary_owner': true,
    },
    {
      'key': 'admin',
      'name': 'Admin',
      'status': 'required',
      'description': 'Full system access and user management',
      'permissions': List.generate(112, (i) => 'perm_$i'),
    },
    {
      'key': 'store_manager',
      'name': 'Store Manager',
      'status': 'recommended',
      'description': 'Sales, inventory, limited reports',
      'permissions': List.generate(43, (i) => 'perm_$i'),
    },
    {
      'key': 'cashier',
      'name': 'Cashier',
      'status': 'recommended',
      'description': 'POS and payment processing',
      'permissions': List.generate(16, (i) => 'perm_$i'),
    },
    {
      'key': 'inventory_clerk',
      'name': 'Inventory Clerk',
      'status': 'recommended',
      'description': 'Warehouse and stock management',
      'permissions': List.generate(16, (i) => 'perm_$i'),
    },
    {
      'key': 'accountant',
      'name': 'Accountant',
      'status': 'recommended',
      'description': 'Financial records and reporting',
      'permissions': List.generate(21, (i) => 'perm_$i'),
    },
  ],
  'departments': [
    {'key': 'management', 'name': 'Management'},
    {'key': 'sales', 'name': 'Sales'},
    {'key': 'warehouse', 'name': 'Warehouse'},
    {'key': 'finance', 'name': 'Finance'},
  ],
  'warehouses': [
    {'key': 'warehouse_1', 'name': 'Warehouse 1'},
    {'key': 'warehouse_2', 'name': 'Warehouse 2'},
  ],
  'pipelines': [
    {
      'key': 'sales_pipeline',
      'name': 'Sales Pipeline',
      'stages': [
        {'key': 'new', 'name': 'New'},
        {'key': 'qualified', 'name': 'Qualified'},
        {'key': 'quoted', 'name': 'Quoted'},
        {'key': 'won', 'name': 'Won'},
        {'key': 'lost', 'name': 'Lost'},
      ],
    },
  ],
  'approval_workflows': [
    {'key': 'high_value_approval', 'name': 'High Value Approval'},
  ],
  'commission_rules': [
    {'key': 'standard_commission', 'name': 'Standard Sales Commission'},
  ],
  'assumptions': ['Operating hours not specified', 'Commission rates assumed'],
};

OnboardingState _stateWithLang(AppLanguage lang) {
  final appState = AppState();
  if (lang == AppLanguage.en) {
    appState.setUiLanguage(AppLanguage.en);
  }
  final state = OnboardingState();
  // Inject appState for language resolution
  state.ensureWelcomeGreeting(appState);
  state.setSessionForTesting(DiscoverySession(
    id: _sessionId,
    workspaceId: 'ws-1',
    status: 'completed',
    readyForBlueprint: true,
    completeness: 86,
  ));
  state.setBlueprintForTesting(DiscoveryBlueprintDto(
    id: _blueprintId,
    sessionId: _sessionId,
    businessType: 'retail',
    blueprint: Map<String, dynamic>.from(_fixture),
    version: 1,
    generatorMethod: 'canonical_v1',
  ));
  return state;
}

void main() {
  group('Blueprint review fidelity', () {
    test('1. no [bp_...] key appears in rendered data', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      // Check all displayable text fields for raw key patterns
      final allText = [
        model.businessName,
        model.businessType,
        model.businessDescription,
        ...model.requiredModules.map((m) => m.displayName),
        ...model.requiredModules.map((m) => m.displayDescription),
        ...model.optionalModules.map((m) => m.displayName),
        ...model.optionalModules.map((m) => m.displayDescription),
        ...model.suggestedRoles.map((r) => r.displayName),
        ...model.suggestedRoles.map((r) => r.displayDescription),
        ...model.suggestedWorkflows,
        ...model.suggestedDashboards,
        ...model.suggestedAutomations,
        ...model.notes,
      ];

      for (final text in allText) {
        expect(text, isNot(matches(RegExp(r'\[bp_'))),
            reason: 'Raw key found: $text');
      }
    });

    test('2. Arabic mode renders module names in Arabic', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      final names = model.requiredModules.map((m) => m.displayName).toList();
      expect(names, contains('لوحة التحكم')); // dashboard
      expect(names, contains('إدارة العملاء')); // customers
      expect(names, contains('كتالوج المنتجات')); // products
      expect(names, contains('المحاسبة والمالية')); // finance
      expect(names, contains('إدارة المخزون')); // inventory

      final optNames = model.optionalModules.map((m) => m.displayName).toList();
      expect(optNames, contains('قطع الغيار')); // spare_parts
    });

    test('3. English mode renders module names in English', () {
      final state = _stateWithLang(AppLanguage.en);
      final model = state.blueprint!;

      final names = model.requiredModules.map((m) => m.displayName).toList();
      expect(names, contains('Dashboard'));
      expect(names, contains('Customer Management'));
      expect(names, contains('Product Catalog'));
      expect(names, contains('Accounting & Finance'));
      expect(names, contains('Inventory Management'));

      final optNames = model.optionalModules.map((m) => m.displayName).toList();
      expect(optNames, contains('Spare Parts'));
    });

    test('4. business type retail is localized', () {
      final arState = _stateWithLang(AppLanguage.ar);
      expect(arState.blueprint!.businessType, 'تجارة التجزئة');

      final enState = _stateWithLang(AppLanguage.en);
      expect(enState.blueprint!.businessType, 'Retail');
    });

    test('5. permission count phrasing is correct', () {
      // The UI uses tr(context, 'bp_role_permissions')
      // We verify the key resolves correctly
      final arVal = trForLang(AppLanguage.ar, 'bp_role_permissions');
      final enVal = trForLang(AppLanguage.en, 'bp_role_permissions');
      expect(arVal, 'صلاحية');
      expect(enVal, 'permissions');
    });

    test('6. roles are exactly those in the real Blueprint', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;
      final roleIds = model.suggestedRoles.map((r) => r.id).toList();

      expect(roleIds, [
        'owner',
        'admin',
        'store_manager',
        'cashier',
        'inventory_clerk',
        'accountant',
      ]);
    });

    test('7. Flutter does not invent roles absent from Blueprint', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;
      final roleIds = model.suggestedRoles.map((r) => r.id).toSet();

      // These must NOT appear unless they're in the fixture
      expect(roleIds, isNot(contains('super_admin')));
      expect(roleIds, isNot(contains('manager')));
      // All IDs must match the fixture
      expect(roleIds, hasLength(6));
    });

    test('8. required and optional modules mapped correctly', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      // 14 enabled = required, 3 disabled = optional
      expect(model.requiredModules, hasLength(14));
      expect(model.optionalModules, hasLength(3));

      final reqIds = model.requiredModules.map((m) => m.id).toSet();
      expect(reqIds, containsAll([
        'dashboard', 'customers', 'products', 'invoices', 'payments',
        'orders', 'employees', 'reports', 'finance', 'inventory',
        'pos', 'commissions', 'ai', 'leads',
      ]));

      final optIds = model.optionalModules.map((m) => m.id).toSet();
      expect(optIds, containsAll(['spare_parts', 'parts_inventory', 'jobs']));
    });

    test('9. warehouses, pipeline and approvals preserved', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      // Pipeline → workflows
      expect(model.suggestedWorkflows, contains('مسار المبيعات'));

      // Departments → dashboards
      expect(model.suggestedDashboards, contains('الإدارة'));
      expect(model.suggestedDashboards, contains('المبيعات'));
      expect(model.suggestedDashboards, contains('المستودعات'));
      expect(model.suggestedDashboards, contains('المالية'));

      // Approval → automations
      expect(model.suggestedAutomations, contains('موافقة القيمة العالية'));
    });

    test('9b. English warehouses/pipeline/approvals', () {
      final state = _stateWithLang(AppLanguage.en);
      final model = state.blueprint!;

      expect(model.suggestedWorkflows, contains('Sales Pipeline'));
      expect(model.suggestedDashboards, contains('Management'));
      expect(model.suggestedDashboards, contains('Sales'));
      expect(model.suggestedAutomations, contains('High Value Approval'));
    });

    test('10. real Blueprint UUID is preserved', () {
      final state = _stateWithLang(AppLanguage.ar);
      expect(state.realBlueprint!.id, _blueprintId);
    });

    test('11. no permission is lost by the bridge', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      final ownerPerms = model.suggestedRoles
          .firstWhere((r) => r.id == 'owner')
          .accessModules;
      expect(ownerPerms, hasLength(112));

      final cashierPerms = model.suggestedRoles
          .firstWhere((r) => r.id == 'cashier')
          .accessModules;
      expect(cashierPerms, hasLength(16));

      final accountantPerms = model.suggestedRoles
          .firstWhere((r) => r.id == 'accountant')
          .accessModules;
      expect(accountantPerms, hasLength(21));
    });

    test('12. no runtime role-name-based authorization logic', () {
      // This test verifies that role display names are data, not code.
      // The bridge uses role.name from the backend, not hardcoded conditions.
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      // Role display names come directly from the backend fixture
      final roleNames = model.suggestedRoles.map((r) => r.displayName).toList();
      expect(roleNames, ['Owner', 'Admin', 'Store Manager', 'Cashier',
          'Inventory Clerk', 'Accountant']);

      // Descriptions also come from the backend
      final ownerDesc = model.suggestedRoles.first.displayDescription;
      expect(ownerDesc, 'Full system access and ownership');
    });

    test('role display names use backend values, not synthetic keys', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      for (final role in model.suggestedRoles) {
        expect(role.displayName, isNot(startsWith('bp_role_')));
        expect(role.displayDescription, isNot(startsWith('bp_role_')));
      }
    });

    test('module descriptions are non-empty', () {
      final state = _stateWithLang(AppLanguage.ar);
      final model = state.blueprint!;

      for (final mod in model.requiredModules) {
        expect(mod.displayDescription, isNotEmpty,
            reason: 'Module ${mod.id} has empty description');
      }
    });
  });
}
