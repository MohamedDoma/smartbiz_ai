// SmartBiz AI — Default dashboard template configurations (Phase 16.3).
//
// Each template defines widgets + quick actions for a dashboard type.
// All strings use localization keys. No hardcoded user-facing text.
import '../models/dashboard_config_models.dart';

// ═══════════════════════════════════════════════════════════
//  Helper constructors to reduce repetition
// ═══════════════════════════════════════════════════════════

DashboardWidgetConfig _metric(String id, String titleKey, String module, List<String> perms, int pos, {Map<String, dynamic> meta = const {}}) =>
    DashboardWidgetConfig(id: id, type: DashWidgetType.metric, titleKey: titleKey, module: module, requiredPermissions: perms, position: pos, size: WidgetSize.small, metadata: meta);

DashboardWidgetConfig _aiInsight(String id, String titleKey, String module, int pos, {String colorName = 'accent'}) =>
    DashboardWidgetConfig(id: id, type: DashWidgetType.aiInsight, titleKey: titleKey, module: module, requiredPermissions: [], position: pos, size: WidgetSize.large, metadata: {'colorName': colorName});

DashboardWidgetConfig _activity(String id, String titleKey, int pos) =>
    DashboardWidgetConfig(id: id, type: DashWidgetType.recentActivity, titleKey: titleKey, position: pos, size: WidgetSize.medium);

DashboardWidgetConfig _summary(String id, DashWidgetType type, String titleKey, String module, List<String> perms, int pos) =>
    DashboardWidgetConfig(id: id, type: type, titleKey: titleKey, module: module, requiredPermissions: perms, position: pos, size: WidgetSize.medium);

DashboardWidgetConfig _widget(String id, DashWidgetType type, String titleKey, int pos, {String? module, List<String> perms = const [], WidgetSize size = WidgetSize.medium, Map<String, dynamic> meta = const {}}) =>
    DashboardWidgetConfig(id: id, type: type, titleKey: titleKey, module: module, requiredPermissions: perms, position: pos, size: size, metadata: meta);

DashboardQuickActionConfig _action(String id, String labelKey, String icon, String route, int pos, {List<String> perms = const []}) =>
    DashboardQuickActionConfig(id: id, labelKey: labelKey, iconName: icon, route: route, requiredPermissions: perms, position: pos);

// ═══════════════════════════════════════════════════════════
//  Registry — access any template by enum
// ═══════════════════════════════════════════════════════════

class DefaultDashboardTemplates {
  DefaultDashboardTemplates._();

  static DashboardConfiguration forTemplate(DashboardTemplate t) => switch (t) {
    DashboardTemplate.executive => executive(),
    DashboardTemplate.sales => sales(),
    DashboardTemplate.finance => finance(),
    DashboardTemplate.inventory => inventory(),
    DashboardTemplate.hr => hr(),
    DashboardTemplate.projects => projects(),
    DashboardTemplate.operations => operations(),
    DashboardTemplate.support => support(),
    DashboardTemplate.service => service(),
    DashboardTemplate.basicEmployee => basicEmployee(),
    DashboardTemplate.custom => basicEmployee(), // fallback
  };

  // ─────────────────────────────────────────────────────────
  //  1. EXECUTIVE
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration executive() => DashboardConfiguration(
    id: 'tpl_executive', template: DashboardTemplate.executive, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('exec_ai', 'dw_ai_business_insight', 'aiAdvisor', 1, colorName: 'accent'),
      _metric('exec_revenue', 'dw_revenue', 'accounting', ['accounting.view'], 2, meta: {'value': '\$34,250', 'trend': '+12%', 'trendUp': true, 'iconName': 'trending_up', 'colorName': 'success'}),
      _metric('exec_profit', 'dw_profit', 'accounting', ['accounting.view'], 3, meta: {'value': '\$21,450', 'trend': '+15%', 'trendUp': true, 'iconName': 'account_balance', 'colorName': 'primary'}),
      _metric('exec_receivables', 'dw_receivables', 'invoices', ['invoices.view'], 4, meta: {'value': '\$8,400', 'trend': '3 overdue', 'trendUp': false, 'iconName': 'receipt_long', 'colorName': 'warning'}),
      _metric('exec_inv_alerts', 'dw_inventory_alerts', 'inventory', ['inventory.view'], 5, meta: {'value': '4', 'trend': '2 critical', 'trendUp': false, 'iconName': 'inventory_2', 'colorName': 'error'}),
      _metric('exec_customers', 'dw_active_customers', 'customers', ['customers.view'], 6, meta: {'value': '156', 'trend': '+8 new', 'trendUp': true, 'iconName': 'people', 'colorName': 'info'}),
      _metric('exec_ai_credits', 'dw_ai_credits', 'aiChat', [], 7, meta: {'value': '820', 'trend': '82%', 'trendUp': true, 'iconName': 'auto_awesome', 'colorName': 'accent'}),
      _summary('exec_emp', DashWidgetType.employeeSummary, 'dw_employee_summary', 'employees', ['employees.view'], 8),
      _summary('exec_ops', DashWidgetType.operationsStatus, 'dw_ops_status', 'dashboard', [], 9),
      _widget('exec_recs', DashWidgetType.recommendations, 'dw_recommendations', 10, module: 'aiAdvisor'),
      _activity('exec_activity', 'dw_recent_activity', 11),
      _widget('exec_setup', DashWidgetType.setupStatus, 'dw_setup_status', 12),
    ],
    quickActions: [
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 1),
      _action('qa_reports', 'dqa_reports', 'bar_chart', '/reports', 2, perms: ['reports.view']),
      _action('qa_invoice', 'dqa_new_invoice', 'receipt_long', '/invoices/create', 3, perms: ['invoices.create']),
      _action('qa_product', 'dqa_add_product', 'add_box', '/products/create', 4, perms: ['products.create']),
      _action('qa_employee', 'dqa_invite_employee', 'person_add', '/employees/invite', 5, perms: ['employees.create']),
      _action('qa_advisor', 'dqa_advisor', 'lightbulb', '/advisor', 6),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  2. SALES
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration sales() => DashboardConfiguration(
    id: 'tpl_sales', template: DashboardTemplate.sales, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('sales_ai', 'dw_ai_sales_insight', 'aiChat', 1, colorName: 'success'),
      _metric('sales_today', 'dw_today_sales', 'invoices', ['invoices.view'], 2, meta: {'value': '\$2,480', 'trend': '+18%', 'trendUp': true, 'iconName': 'point_of_sale', 'colorName': 'primary'}),
      _metric('sales_invoices', 'dw_invoices_today', 'invoices', ['invoices.view'], 3, meta: {'value': '12', 'trend': '+3', 'trendUp': true, 'iconName': 'receipt_long', 'colorName': 'success'}),
      _metric('sales_pending', 'dw_pending_invoices', 'invoices', ['invoices.view'], 4, meta: {'value': '4', 'trend': '1 overdue', 'trendUp': false, 'iconName': 'receipt', 'colorName': 'warning'}),
      _metric('sales_customers', 'dw_customers_served', 'customers', ['customers.view'], 5, meta: {'value': '18', 'trend': '+5', 'trendUp': true, 'iconName': 'people', 'colorName': 'info'}),
      _summary('sales_cust_sum', DashWidgetType.customerSummary, 'dw_customer_summary', 'customers', ['customers.view'], 6),
      _activity('sales_activity', 'dw_recent_sales', 7),
    ],
    quickActions: [
      _action('qa_new_invoice', 'dqa_new_invoice', 'receipt_long', '/invoices/create', 1, perms: ['invoices.create']),
      _action('qa_customers', 'dqa_customers', 'people', '/customers', 2, perms: ['customers.view']),
      _action('qa_ai_help', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 3),
      _action('qa_products', 'dqa_products', 'inventory_2', '/products', 4, perms: ['products.view']),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  3. FINANCE
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration finance() => DashboardConfiguration(
    id: 'tpl_finance', template: DashboardTemplate.finance, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('fin_ai', 'dw_ai_finance_insight', 'aiChat', 1, colorName: 'primary'),
      _metric('fin_revenue', 'dw_revenue', 'accounting', ['accounting.view'], 2, meta: {'value': '\$34,250', 'trend': '+12%', 'trendUp': true, 'iconName': 'trending_up', 'colorName': 'success'}),
      _metric('fin_expenses', 'dw_expenses', 'accounting', ['accounting.view'], 3, meta: {'value': '\$12,800', 'trend': '-3%', 'trendUp': true, 'iconName': 'trending_down', 'colorName': 'warning'}),
      _metric('fin_profit', 'dw_profit', 'accounting', ['accounting.view'], 4, meta: {'value': '\$21,450', 'trend': '+15%', 'trendUp': true, 'iconName': 'account_balance', 'colorName': 'primary'}),
      _metric('fin_receivables', 'dw_receivables', 'invoices', ['invoices.view'], 5, meta: {'value': '\$8,400', 'trend': '3 overdue', 'trendUp': false, 'iconName': 'receipt_long', 'colorName': 'error'}),
      _summary('fin_summary', DashWidgetType.financeSummary, 'dw_finance_summary', 'accounting', ['accounting.view'], 6),
      _activity('fin_activity', 'dw_recent_transactions', 7),
    ],
    quickActions: [
      _action('qa_accounting', 'dqa_accounting', 'account_balance', '/accounting', 1, perms: ['accounting.view']),
      _action('qa_reports', 'dqa_reports', 'bar_chart', '/reports', 2, perms: ['reports.view']),
      _action('qa_expenses', 'dqa_expenses', 'receipt', '/accounting/expenses', 3, perms: ['accounting.create']),
      _action('qa_customers', 'dqa_customers', 'people', '/customers', 4, perms: ['customers.view']),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  4. INVENTORY
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration inventory() => DashboardConfiguration(
    id: 'tpl_inventory', template: DashboardTemplate.inventory, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('inv_ai', 'dw_ai_inventory_insight', 'aiChat', 1, colorName: 'warning'),
      _metric('inv_products', 'dw_total_products', 'products', ['products.view'], 2, meta: {'value': '148', 'trend': '+6', 'trendUp': true, 'iconName': 'inventory_2', 'colorName': 'primary'}),
      _metric('inv_low', 'dw_low_stock', 'inventory', ['inventory.view'], 3, meta: {'value': '3', 'trend': '1 critical', 'trendUp': false, 'iconName': 'warning', 'colorName': 'error'}),
      _metric('inv_movements', 'dw_movements_today', 'inventory', ['inventory.view'], 4, meta: {'value': '7', 'trend': '+2', 'trendUp': true, 'iconName': 'trending_up', 'colorName': 'success'}),
      _metric('inv_units', 'dw_total_units', 'inventory', ['inventory.view'], 5, meta: {'value': '599', 'iconName': 'warehouse', 'colorName': 'info'}),
      _summary('inv_summary', DashWidgetType.inventorySummary, 'dw_inventory_summary', 'inventory', ['inventory.view'], 6),
      _activity('inv_activity', 'dw_recent_movements', 7),
    ],
    quickActions: [
      _action('qa_inventory', 'dqa_inventory', 'warehouse', '/inventory', 1, perms: ['inventory.view']),
      _action('qa_adjust', 'dqa_adjust_stock', 'add_box', '/inventory/adjustments', 2, perms: ['inventory.create']),
      _action('qa_movements', 'dqa_movements', 'trending_up', '/inventory/movements', 3, perms: ['inventory.view']),
      _action('qa_products', 'dqa_products', 'inventory_2', '/products', 4, perms: ['products.view']),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  5. HR
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration hr() => DashboardConfiguration(
    id: 'tpl_hr', template: DashboardTemplate.hr, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('hr_ai', 'dw_ai_hr_insight', 'aiChat', 1, colorName: 'info'),
      _metric('hr_count', 'dw_employee_count', 'employees', ['employees.view'], 2, meta: {'value': '24', 'trend': '+3 new', 'trendUp': true, 'iconName': 'people', 'colorName': 'primary'}),
      _metric('hr_new', 'dw_new_employees', 'employees', ['employees.view'], 3, meta: {'value': '3', 'trend': 'This month', 'trendUp': true, 'iconName': 'person_add', 'colorName': 'success'}),
      _metric('hr_roles', 'dw_active_roles', 'roles', ['roles.view'], 4, meta: {'value': '7', 'iconName': 'shield', 'colorName': 'accent'}),
      _summary('hr_summary', DashWidgetType.hrSummary, 'dw_hr_summary', 'employees', ['employees.view'], 5),
      _widget('hr_tasks', DashWidgetType.taskList, 'dw_hr_tasks', 6, module: 'employees', perms: ['employees.edit']),
      _activity('hr_activity', 'dw_recent_activity', 7),
    ],
    quickActions: [
      _action('qa_employees', 'dqa_employees', 'people', '/employees', 1, perms: ['employees.view']),
      _action('qa_invite', 'dqa_invite_employee', 'person_add', '/employees/invite', 2, perms: ['employees.create']),
      _action('qa_roles', 'dqa_roles', 'shield', '/employees/roles', 3, perms: ['roles.view']),
      _action('qa_departments', 'dqa_departments', 'business', '/employees/departments', 4, perms: ['departments.view']),
      _action('qa_teams', 'dqa_teams', 'groups', '/employees/teams', 5, perms: ['teams.view']),
      _action('qa_org', 'dqa_organization', 'account_tree', '/employees/organization', 6, perms: ['employees.view']),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  6. PROJECTS
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration projects() => DashboardConfiguration(
    id: 'tpl_projects', template: DashboardTemplate.projects, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('proj_ai', 'dw_ai_project_insight', 'aiChat', 1, colorName: 'accent'),
      _metric('proj_active', 'dw_active_projects', 'dashboard', [], 2, meta: {'value': '5', 'trend': '2 on track', 'trendUp': true, 'iconName': 'folder', 'colorName': 'primary'}),
      _metric('proj_delayed', 'dw_delayed_tasks', 'dashboard', [], 3, meta: {'value': '3', 'trend': '1 critical', 'trendUp': false, 'iconName': 'warning', 'colorName': 'error'}),
      _metric('proj_deadlines', 'dw_upcoming_deadlines', 'dashboard', [], 4, meta: {'value': '4', 'trend': 'This week', 'trendUp': false, 'iconName': 'task_alt', 'colorName': 'warning'}),
      _summary('proj_summary', DashWidgetType.projectSummary, 'dw_project_summary', 'dashboard', [], 5),
      _widget('proj_workload', DashWidgetType.taskList, 'dw_team_workload', 6, module: 'employees', perms: ['employees.view']),
      _activity('proj_activity', 'dw_recent_activity', 7),
    ],
    quickActions: [
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 1),
      _action('qa_reports', 'dqa_reports', 'bar_chart', '/reports', 2, perms: ['reports.view']),
      _action('qa_employees', 'dqa_employees', 'people', '/employees', 3, perms: ['employees.view']),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  7. OPERATIONS
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration operations() => DashboardConfiguration(
    id: 'tpl_operations', template: DashboardTemplate.operations, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('ops_ai', 'dw_ai_ops_insight', 'aiChat', 1, colorName: 'warning'),
      _widget('ops_alerts', DashWidgetType.alerts, 'dw_operational_alerts', 2, module: 'dashboard'),
      _summary('ops_status', DashWidgetType.operationsStatus, 'dw_ops_status', 'dashboard', [], 3),
      _widget('ops_approvals', DashWidgetType.approvalQueue, 'dw_approvals', 4, module: 'invoices', perms: ['invoices.approve']),
      _widget('ops_team', DashWidgetType.employeeSummary, 'dw_team_summary', 5, module: 'employees', perms: ['employees.view']),
      _activity('ops_activity', 'dw_recent_activity', 6),
    ],
    quickActions: [
      _action('qa_inventory', 'dqa_inventory', 'warehouse', '/inventory', 1, perms: ['inventory.view']),
      _action('qa_employees', 'dqa_employees', 'people', '/employees', 2, perms: ['employees.view']),
      _action('qa_reports', 'dqa_reports', 'bar_chart', '/reports', 3, perms: ['reports.view']),
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 4),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  8. SUPPORT
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration support() => DashboardConfiguration(
    id: 'tpl_support', template: DashboardTemplate.support, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('sup_ai', 'dw_ai_support_insight', 'aiChat', 1, colorName: 'info'),
      _widget('sup_queue', DashWidgetType.supportQueue, 'dw_support_queue', 2, module: 'customers', perms: ['customers.view']),
      _metric('sup_open', 'dw_open_tickets', 'customers', ['customers.view'], 3, meta: {'value': '8', 'trend': '3 priority', 'trendUp': false, 'iconName': 'warning', 'colorName': 'warning'}),
      _metric('sup_resolved', 'dw_resolved_today', 'customers', ['customers.view'], 4, meta: {'value': '5', 'trend': '+2', 'trendUp': true, 'iconName': 'task_alt', 'colorName': 'success'}),
      _summary('sup_cust', DashWidgetType.customerSummary, 'dw_customer_summary', 'customers', ['customers.view'], 5),
      _activity('sup_activity', 'dw_recent_activity', 6),
    ],
    quickActions: [
      _action('qa_customers', 'dqa_customers', 'people', '/customers', 1, perms: ['customers.view']),
      _action('qa_invoices', 'dqa_invoices', 'receipt_long', '/invoices', 2, perms: ['invoices.view']),
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 3),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  9. SERVICE
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration service() => DashboardConfiguration(
    id: 'tpl_service', template: DashboardTemplate.service, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('svc_ai', 'dw_ai_service_insight', 'aiChat', 1, colorName: 'success'),
      _widget('svc_schedule', DashWidgetType.serviceSchedule, 'dw_today_schedule', 2, module: 'dashboard'),
      _metric('svc_jobs', 'dw_assigned_jobs', 'dashboard', [], 3, meta: {'value': '6', 'trend': '2 urgent', 'trendUp': false, 'iconName': 'build', 'colorName': 'warning'}),
      _metric('svc_completed', 'dw_completed_today', 'dashboard', [], 4, meta: {'value': '4', 'trend': '+1', 'trendUp': true, 'iconName': 'task_alt', 'colorName': 'success'}),
      _widget('svc_cust', DashWidgetType.customerSummary, 'dw_customer_followups', 5, module: 'customers', perms: ['customers.view']),
      _activity('svc_activity', 'dw_recent_activity', 6),
    ],
    quickActions: [
      _action('qa_customers', 'dqa_customers', 'people', '/customers', 1, perms: ['customers.view']),
      _action('qa_invoices', 'dqa_new_invoice', 'receipt_long', '/invoices/create', 2, perms: ['invoices.create']),
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 3),
    ],
  );

  // ─────────────────────────────────────────────────────────
  //  10. BASIC EMPLOYEE
  // ─────────────────────────────────────────────────────────
  static DashboardConfiguration basicEmployee() => DashboardConfiguration(
    id: 'tpl_basic', template: DashboardTemplate.basicEmployee, source: DashboardSource.systemDefault,
    widgets: [
      _aiInsight('emp_ai', 'dw_ai_assistant', 'aiChat', 1, colorName: 'info'),
      _widget('emp_tasks', DashWidgetType.taskList, 'dw_my_tasks', 2),
      _widget('emp_announce', DashWidgetType.announcements, 'dw_announcements', 3),
      _activity('emp_activity', 'dw_recent_activity', 4),
    ],
    quickActions: [
      _action('qa_ai_chat', 'dqa_ai_chat', 'auto_awesome', '/ai-chat', 1),
      _action('qa_settings', 'dqa_my_settings', 'settings', '/settings', 2),
    ],
  );

  /// All template enum values mapped for quick lookup.
  static final Map<DashboardTemplate, DashboardConfiguration> all = {
    for (final t in DashboardTemplate.values) t: forTemplate(t),
  };
}
