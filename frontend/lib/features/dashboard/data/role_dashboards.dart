// SmartBiz AI — Role-specific mock dashboard data.
import '../models/dashboard_models.dart';

/// Cashier-focused mock data.
class CashierDashboard {
  CashierDashboard._();
  static const List<DashboardMetric> metrics = [
    DashboardMetric(id: 'sales_today', labelKey: 'dash_metric_sales_today', value: '\$2,480', trend: '+18%', trendUp: true, iconName: 'point_of_sale', colorName: 'primary'),
    DashboardMetric(id: 'invoices_today', labelKey: 'rd_invoices_today', value: '12', trend: '+3', trendUp: true, iconName: 'receipt_long', colorName: 'success'),
    DashboardMetric(id: 'pending_invoices', labelKey: 'rd_pending_inv', value: '4', trend: '1 overdue', trendUp: false, iconName: 'receipt', colorName: 'warning'),
    DashboardMetric(id: 'customers_served', labelKey: 'rd_customers_served', value: '18', trend: '+5', trendUp: true, iconName: 'people', colorName: 'info'),
  ];
  static const List<DashboardQuickAction> quickActions = [
    DashboardQuickAction(id: 'new_invoice', labelKey: 'rd_qa_new_invoice', iconName: 'receipt_long', route: '/invoices/create'),
    DashboardQuickAction(id: 'customers', labelKey: 'rd_qa_customers', iconName: 'people', route: '/customers'),
    DashboardQuickAction(id: 'ai_help', labelKey: 'rd_qa_ai_help', iconName: 'auto_awesome', route: '/ai-chat'),
  ];
  static const List<DashboardActivity> recentActivity = [
    DashboardActivity(id: 'c1', titleKey: 'rd_act_sale', timeKey: 'dash_act_just_now', iconName: 'point_of_sale', colorName: 'primary'),
    DashboardActivity(id: 'c2', titleKey: 'rd_act_refund', timeKey: 'dash_act_2h', iconName: 'payment', colorName: 'warning'),
    DashboardActivity(id: 'c3', titleKey: 'rd_act_cust_added', timeKey: 'dash_act_3h', iconName: 'person_add', colorName: 'info'),
  ];
}

/// Warehouse-focused mock data.
class WarehouseDashboard {
  WarehouseDashboard._();
  static const List<DashboardMetric> metrics = [
    DashboardMetric(id: 'total_products', labelKey: 'rd_total_products', value: '148', trend: '+6', trendUp: true, iconName: 'inventory_2', colorName: 'primary'),
    DashboardMetric(id: 'low_stock', labelKey: 'rd_low_stock_items', value: '3', trend: '1 critical', trendUp: false, iconName: 'warning', colorName: 'error'),
    DashboardMetric(id: 'movements_today', labelKey: 'rd_movements_today', value: '7', trend: '+2', trendUp: true, iconName: 'trending_up', colorName: 'success'),
    DashboardMetric(id: 'total_units', labelKey: 'rd_total_units', value: '599', iconName: 'warehouse', colorName: 'info'),
  ];
  static const List<DashboardQuickAction> quickActions = [
    DashboardQuickAction(id: 'inventory', labelKey: 'rd_qa_inventory', iconName: 'warehouse', route: '/inventory'),
    DashboardQuickAction(id: 'adjust', labelKey: 'rd_qa_adjust', iconName: 'add_box', route: '/inventory/adjustments'),
    DashboardQuickAction(id: 'movements', labelKey: 'rd_qa_movements', iconName: 'trending_up', route: '/inventory/movements'),
  ];
  static const List<DashboardActivity> recentActivity = [
    DashboardActivity(id: 'w1', titleKey: 'rd_act_received', timeKey: 'dash_act_just_now', iconName: 'add_box', colorName: 'success'),
    DashboardActivity(id: 'w2', titleKey: 'rd_act_adjusted', timeKey: 'dash_act_2h', iconName: 'bolt', colorName: 'warning'),
    DashboardActivity(id: 'w3', titleKey: 'rd_act_low_alert', timeKey: 'dash_act_5h', iconName: 'warning', colorName: 'error'),
  ];
}

/// Accountant-focused mock data.
class AccountantDashboard {
  AccountantDashboard._();
  static const List<DashboardMetric> metrics = [
    DashboardMetric(id: 'revenue', labelKey: 'dash_metric_revenue_month', value: '\$34,250', trend: '+12%', trendUp: true, iconName: 'trending_up', colorName: 'success'),
    DashboardMetric(id: 'expenses', labelKey: 'rd_total_expenses', value: '\$12,800', trend: '-3%', trendUp: true, iconName: 'trending_down', colorName: 'warning'),
    DashboardMetric(id: 'profit', labelKey: 'rd_net_profit', value: '\$21,450', trend: '+15%', trendUp: true, iconName: 'account_balance', colorName: 'primary'),
    DashboardMetric(id: 'receivables', labelKey: 'rd_receivables', value: '\$8,400', trend: '3 overdue', trendUp: false, iconName: 'receipt_long', colorName: 'error'),
  ];
  static const List<DashboardQuickAction> quickActions = [
    DashboardQuickAction(id: 'accounting', labelKey: 'rd_qa_accounting', iconName: 'account_balance', route: '/accounting'),
    DashboardQuickAction(id: 'reports', labelKey: 'dash_action_reports', iconName: 'bar_chart', route: '/reports'),
    DashboardQuickAction(id: 'customers', labelKey: 'rd_qa_customers', iconName: 'people', route: '/customers'),
  ];
  static const List<DashboardActivity> recentActivity = [
    DashboardActivity(id: 'a1', titleKey: 'rd_act_payment_in', timeKey: 'dash_act_just_now', iconName: 'payment', colorName: 'success'),
    DashboardActivity(id: 'a2', titleKey: 'rd_act_expense', timeKey: 'dash_act_2h', iconName: 'receipt', colorName: 'warning'),
    DashboardActivity(id: 'a3', titleKey: 'rd_act_overdue', timeKey: 'dash_act_3h', iconName: 'warning', colorName: 'error'),
  ];
}

/// Basic employee mock data.
class EmployeeDashboard {
  EmployeeDashboard._();
  static const List<DashboardMetric> metrics = [
    DashboardMetric(id: 'tasks', labelKey: 'rd_my_tasks', value: '3', iconName: 'task_alt', colorName: 'primary'),
    DashboardMetric(id: 'ai_credits', labelKey: 'dash_metric_ai_credits', value: '50', trend: '50%', trendUp: true, iconName: 'auto_awesome', colorName: 'accent'),
  ];
  static const List<DashboardQuickAction> quickActions = [
    DashboardQuickAction(id: 'ai_chat', labelKey: 'dash_action_ai_chat', iconName: 'auto_awesome', route: '/ai-chat'),
    DashboardQuickAction(id: 'settings', labelKey: 'rd_qa_my_settings', iconName: 'bolt', route: '/settings'),
  ];
  static const List<DashboardActivity> recentActivity = [
    DashboardActivity(id: 'e1', titleKey: 'rd_act_welcome', timeKey: 'dash_act_just_now', iconName: 'auto_awesome', colorName: 'accent'),
  ];
}
