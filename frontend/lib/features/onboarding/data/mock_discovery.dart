// SmartBiz AI — Mock discovery data for demo/development.
// Language-aware: uses localization keys resolved at runtime.
import '../../../core/l10n/app_localizations.dart';
import '../models/onboarding_models.dart';

class MockResponse {
  final String textKey;
  final List<String>? quickReplyKeys;
  const MockResponse(this.textKey, {this.quickReplyKeys});
}

class MockDiscovery {
  MockDiscovery._();

  static const String welcomeMessageKey = 'disc_welcome';

  /// 6 AI responses — one per discovery category.
  static const List<MockResponse> responses = [
    MockResponse('disc_q1_business_type',
        quickReplyKeys: ['disc_qr_retail', 'disc_qr_restaurant', 'disc_qr_wholesale', 'disc_qr_services', 'disc_qr_manufacturing']),
    MockResponse('disc_q2_operations',
        quickReplyKeys: ['disc_qr_1_5', 'disc_qr_5_20', 'disc_qr_20_50', 'disc_qr_50_plus']),
    MockResponse('disc_q3_products',
        quickReplyKeys: ['disc_qr_physical', 'disc_qr_digital', 'disc_qr_professional', 'disc_qr_food']),
    MockResponse('disc_q4_finance',
        quickReplyKeys: ['disc_qr_yes_all', 'disc_qr_invoices_only', 'disc_qr_nothing', 'disc_qr_help']),
    MockResponse('disc_q5_special',
        quickReplyKeys: ['disc_qr_multi_branch', 'disc_qr_loyalty', 'disc_qr_online_store', 'disc_qr_generate']),
    MockResponse('disc_q6_ready'),
  ];

  /// Number of required discovery steps (= number of responses).
  static int get totalSteps => responses.length;

  /// Get response by user message number (0-indexed: 0 = after 1st user msg).
  static MockResponse getResponseForStep(int userMsgIndex) {
    final idx = userMsgIndex.clamp(0, responses.length - 1);
    return responses[idx];
  }

  static final BlueprintModel sampleBlueprint = BlueprintModel(
    businessName: 'SmartBiz Demo Store',
    businessType: 'Retail Store',
    businessDescription: 'A modern retail business with inventory tracking, point-of-sale, and customer management needs.',
    requiredModules: const [
      BlueprintModule(id: 'sales', nameKey: 'bp_mod_sales', descriptionKey: 'bp_mod_sales_desc', icon: 'point_of_sale'),
      BlueprintModule(id: 'products', nameKey: 'bp_mod_products', descriptionKey: 'bp_mod_products_desc', icon: 'inventory_2'),
      BlueprintModule(id: 'inventory', nameKey: 'bp_mod_inventory', descriptionKey: 'bp_mod_inventory_desc', icon: 'warehouse'),
      BlueprintModule(id: 'customers', nameKey: 'bp_mod_customers', descriptionKey: 'bp_mod_customers_desc', icon: 'people'),
      BlueprintModule(id: 'accounting', nameKey: 'bp_mod_accounting', descriptionKey: 'bp_mod_accounting_desc', icon: 'account_balance'),
    ],
    optionalModules: const [
      BlueprintModule(id: 'reports', nameKey: 'bp_mod_reports', descriptionKey: 'bp_mod_reports_desc', icon: 'bar_chart', included: false),
      BlueprintModule(id: 'employees', nameKey: 'bp_mod_employees', descriptionKey: 'bp_mod_employees_desc', icon: 'badge', included: false),
    ],
    suggestedRoles: const [
      BlueprintRole(id: 'owner', nameKey: 'bp_role_owner', descriptionKey: 'bp_role_owner_desc', accessModules: ['sales', 'products', 'inventory', 'customers', 'accounting', 'reports', 'employees']),
      BlueprintRole(id: 'cashier', nameKey: 'bp_role_cashier', descriptionKey: 'bp_role_cashier_desc', accessModules: ['sales', 'customers']),
      BlueprintRole(id: 'warehouse', nameKey: 'bp_role_warehouse', descriptionKey: 'bp_role_warehouse_desc', accessModules: ['products', 'inventory']),
      BlueprintRole(id: 'accountant', nameKey: 'bp_role_accountant', descriptionKey: 'bp_role_accountant_desc', accessModules: ['accounting', 'reports', 'customers']),
    ],
    suggestedWorkflows: const [
      'bp_wf_sale_to_invoice',
      'bp_wf_low_stock_alert',
      'bp_wf_payment_tracking',
      'bp_wf_daily_close',
    ],
    suggestedDashboards: const [
      'bp_dash_owner',
      'bp_dash_cashier',
      'bp_dash_warehouse',
      'bp_dash_accountant',
    ],
    suggestedAutomations: const [
      'bp_auto_reorder',
      'bp_auto_overdue_reminder',
      'bp_auto_daily_report',
    ],
    notes: const [
      'bp_note_multi_branch',
      'bp_note_payment_gateway',
    ],
  );
}
