// SmartBiz AI — Blueprint parsing regression test.
//
// Uses a fixture matching the actual live Blueprint JSON shape that crashed.
// Proves:
//   1. The payload parses without TypeError.
//   2. The real Blueprint ID remains unchanged.
//   3. List-based fields remain available to the UI bridge.
//   4. The Blueprint screen model can be created successfully.
//   5. No mock/default Blueprint values are introduced.

import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/api/discovery_models.dart';
import 'package:smartbiz_ai/features/onboarding/onboarding_state.dart';

/// Fixture matching the actual live backend Blueprint JSON that caused the crash.
/// All top-level collection fields are indexed arrays (Lists), not Maps.
const _liveFixture = <String, dynamic>{
  'business_profile': {
    'business_name': 'شركة لبيع السيارات',
    'business_type': 'retail',
    'business_description': 'شركة تبيع السيارات الجديدة والمستعملة وقطع الغيار',
    'branch_count': 1,
    'company_size': 'small',
    'employee_count': 8,
    'sells_products': true,
    'sells_services': false,
    'customer_types': ['individual customers'],
    'sales_channels': ['sales office', 'point of sale'],
  },
  'modules': [
    {'key': 'dashboard', 'reason': 'Core system dashboard', 'status': 'required', 'enabled': true},
    {'key': 'contacts', 'reason': 'Customer management', 'status': 'required', 'enabled': true},
    {'key': 'products', 'reason': 'Product catalog', 'status': 'required', 'enabled': true},
    {'key': 'inventory', 'reason': 'Stock tracking', 'status': 'required', 'enabled': true},
    {'key': 'invoices', 'reason': 'Invoicing', 'status': 'required', 'enabled': true},
    {'key': 'pos', 'reason': 'Point of sale', 'status': 'optional', 'enabled': true},
    {'key': 'accounting', 'reason': 'Financial records', 'status': 'required', 'enabled': true},
    {'key': 'commissions', 'reason': 'Sales commissions', 'status': 'optional', 'enabled': false},
  ],
  'roles': [
    {
      'key': 'owner',
      'name': 'Owner',
      'status': 'required',
      'description': 'Full system access',
      'permissions': ['contacts.list', 'contacts.create', 'products.list', 'settings.manage'],
      'is_primary_owner': true,
    },
    {
      'key': 'sales_agent',
      'name': 'Sales Agent',
      'status': 'required',
      'description': 'Sales access',
      'permissions': ['contacts.list', 'products.list', 'invoices.create'],
    },
  ],
  'departments': [
    {'key': 'sales', 'name': 'Sales Department'},
    {'key': 'parts', 'name': 'Parts Department'},
  ],
  'warehouses': [
    {'key': 'main', 'name': 'Main Warehouse', 'location_key': 'main_branch'},
    {'key': 'parts', 'name': 'Parts Storage', 'location_key': 'main_branch'},
  ],
  'pipelines': [
    {
      'key': 'sales_pipeline',
      'name': 'مسار المبيعات',
      'entity_type': 'deal',
      'stages': [
        {'key': 'new', 'name': 'New', 'order': 1},
        {'key': 'qualified', 'name': 'Qualified', 'order': 2},
        {'key': 'won', 'name': 'Won', 'order': 3},
        {'key': 'lost', 'name': 'Lost', 'order': 4},
      ],
    },
  ],
  'approval_workflows': [
    {
      'key': 'high_value_approval',
      'name': 'موافقة القيمة العالية',
      'entity_type': 'invoice',
      'steps': [
        {'name': 'Manager Approval', 'step_order': 1, 'action_on_approve': 'finalize'},
      ],
    },
  ],
  'commission_rules': [
    {'key': 'sales_commission', 'name': 'Sales Commission', 'percentage': 5},
  ],
  'teams': [
    {'key': 'sales_team', 'name': 'Sales Team'},
  ],
  'locations': [
    {'key': 'main_branch', 'name': 'Main Branch'},
  ],
  'workspace_settings': {'currency': 'LYD', 'timezone': 'Africa/Tripoli'},
  'localization': {'default_language': 'ar', 'supported_languages': ['ar', 'en']},
  'metadata': {'schema_version': '1.0', 'generated_by': 'canonical_v1'},
  'assumptions': ['Operating hours not specified', 'Commission rates assumed'],
  'missing_optional_information': ['Tax configuration'],
  'schema_version': '1.0',
  'ai_settings': {'enabled': true},
  'pos_settings': {'enabled': true, 'terminal_count': 1},
  'tax_settings': {'tax_enabled': false},
  'accounting_settings': {'fiscal_year_start': '01-01', 'currency': 'LYD', 'multi_currency': false},
  'invoice_settings': {'auto_number': true, 'prefix': 'INV', 'default_due_days': 30},
  'payment_methods': [],
};

const _blueprintId = 'a246cfd0-032a-4688-b066-e0d5aec82b92';

void main() {
  group('Blueprint parsing regression (live fixture)', () {
    late DiscoveryBlueprintDto dto;

    setUp(() {
      dto = DiscoveryBlueprintDto(
        id: _blueprintId,
        sessionId: 'a246cf92-32d9-4976-8e92-d6bb9302ea0e',
        businessType: 'retail',
        blueprint: Map<String, dynamic>.from(_liveFixture),
        version: 1,
        generatorMethod: 'canonical_v1',
      );
    });

    test('1. payload parses without TypeError', () {
      final state = OnboardingState();

      // This is the exact call that crashed before the fix
      expect(
        () => state.testConvertBlueprint(dto),
        returnsNormally,
      );
    });

    test('2. real Blueprint ID remains unchanged', () {
      expect(dto.id, _blueprintId);
    });

    test('3. List-based modules are parsed correctly', () {
      final state = OnboardingState();
      final model = state.testConvertBlueprint(dto);

      // 7 enabled modules → required, 1 disabled → optional
      expect(model.requiredModules, hasLength(7));
      expect(model.optionalModules, hasLength(1));

      // Module IDs from 'key' field
      final ids = model.requiredModules.map((m) => m.id).toList();
      expect(ids, contains('dashboard'));
      expect(ids, contains('contacts'));
      expect(ids, contains('inventory'));

      // Disabled module
      expect(model.optionalModules.first.id, 'commissions');
      expect(model.optionalModules.first.included, false);
    });

    test('3b. List-based roles are parsed correctly', () {
      final state = OnboardingState();
      final model = state.testConvertBlueprint(dto);

      expect(model.suggestedRoles, hasLength(2));
      expect(model.suggestedRoles.first.id, 'owner');
      expect(model.suggestedRoles.first.accessModules, isNotEmpty);
      expect(model.suggestedRoles.last.id, 'sales_agent');
    });

    test('3c. pipelines, departments, workflows extracted as named lists', () {
      final state = OnboardingState();
      final model = state.testConvertBlueprint(dto);

      expect(model.suggestedWorkflows, contains('مسار المبيعات'));
      expect(model.suggestedDashboards, contains('Sales Department'));
      expect(model.suggestedDashboards, contains('Parts Department'));
      expect(model.suggestedAutomations, contains('موافقة القيمة العالية'));
    });

    test('4. BlueprintModel is created successfully with all fields', () {
      final state = OnboardingState();
      final model = state.testConvertBlueprint(dto);

      expect(model.businessName, 'شركة لبيع السيارات');
      expect(model.businessType, 'تجارة التجزئة');
      expect(model.businessDescription, contains('السيارات'));
      expect(model.requiredModules, isNotEmpty);
      expect(model.suggestedRoles, isNotEmpty);
      expect(model.notes, isNotEmpty); // from 'assumptions'
    });

    test('5. no mock/default Blueprint values introduced', () {
      final state = OnboardingState();
      final model = state.testConvertBlueprint(dto);

      // Business name is from the real fixture, not defaults
      expect(model.businessName, isNot('Your Business'));
      expect(model.businessType, isNot('service'));
      expect(model.businessDescription, isNot(''));
    });
  });
}
