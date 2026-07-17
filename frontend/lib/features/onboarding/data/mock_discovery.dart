// SmartBiz AI — Mock discovery data for demo/development.
// Language-aware: uses localization keys resolved at runtime.
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
      BlueprintModule(id: 'sales', displayName: 'Sales & POS', displayDescription: 'Point-of-sale, quotations, and order management.', icon: 'point_of_sale'),
      BlueprintModule(id: 'products', displayName: 'Product Catalog', displayDescription: 'Product, category, and pricing management.', icon: 'inventory_2'),
      BlueprintModule(id: 'inventory', displayName: 'Inventory Management', displayDescription: 'Stock tracking, warehouses, and movement logs.', icon: 'warehouse'),
      BlueprintModule(id: 'customers', displayName: 'Customer Management', displayDescription: 'Customer records, contacts, and history.', icon: 'people'),
      BlueprintModule(id: 'accounting', displayName: 'Accounting & Finance', displayDescription: 'Journal entries, balance sheet, and financial statements.', icon: 'account_balance'),
    ],
    optionalModules: const [
      BlueprintModule(id: 'reports', displayName: 'Reports & Analytics', displayDescription: 'Business performance dashboards and custom reports.', icon: 'bar_chart', included: false),
      BlueprintModule(id: 'employees', displayName: 'Employee Management', displayDescription: 'Employee records, roles, and access management.', icon: 'badge', included: false),
    ],
    suggestedRoles: const [
      BlueprintRole(id: 'owner', displayName: 'Owner / Admin', displayDescription: 'Full access to all modules and settings.', accessModules: ['sales', 'products', 'inventory', 'customers', 'accounting', 'reports', 'employees']),
      BlueprintRole(id: 'cashier', displayName: 'Cashier', displayDescription: 'Sales and customer interactions only.', accessModules: ['sales', 'customers']),
      BlueprintRole(id: 'warehouse', displayName: 'Warehouse Manager', displayDescription: 'Product catalog and inventory operations.', accessModules: ['products', 'inventory']),
      BlueprintRole(id: 'accountant', displayName: 'Accountant', displayDescription: 'Financial records and reporting.', accessModules: ['accounting', 'reports', 'customers']),
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
