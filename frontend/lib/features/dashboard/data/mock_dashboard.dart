// SmartBiz AI — Mock dashboard data for demo/development.
import '../models/dashboard_models.dart';

class MockDashboard {
  MockDashboard._();

  static const List<DashboardMetric> metrics = [
    DashboardMetric(id: 'sales_today', labelKey: 'dash_metric_sales_today', value: '\$2,480', trend: '+18%', trendUp: true, iconName: 'point_of_sale', colorName: 'primary'),
    DashboardMetric(id: 'revenue_month', labelKey: 'dash_metric_revenue_month', value: '\$34,250', trend: '+12%', trendUp: true, iconName: 'trending_up', colorName: 'success'),
    DashboardMetric(id: 'open_invoices', labelKey: 'dash_metric_open_invoices', value: '7', trend: '3 overdue', trendUp: false, iconName: 'receipt_long', colorName: 'warning'),
    DashboardMetric(id: 'inventory_alerts', labelKey: 'dash_metric_inventory_alerts', value: '4', trend: '2 critical', trendUp: false, iconName: 'inventory_2', colorName: 'error'),
    DashboardMetric(id: 'active_customers', labelKey: 'dash_metric_active_customers', value: '156', trend: '+8 new', trendUp: true, iconName: 'people', colorName: 'info'),
    DashboardMetric(id: 'ai_credits', labelKey: 'dash_metric_ai_credits', value: '820', trend: '82%', trendUp: true, iconName: 'auto_awesome', colorName: 'accent'),
  ];

  static const List<DashboardRecommendation> recommendations = [
    DashboardRecommendation(
      id: 'rec_low_stock', titleKey: 'dash_rec_low_stock_title', descriptionKey: 'dash_rec_low_stock_desc',
      category: RecommendationCategory.inventory, impact: RecommendationImpact.high, iconName: 'warning',
    ),
    DashboardRecommendation(
      id: 'rec_overdue', titleKey: 'dash_rec_overdue_title', descriptionKey: 'dash_rec_overdue_desc',
      category: RecommendationCategory.finance, impact: RecommendationImpact.high, iconName: 'payment',
    ),
    DashboardRecommendation(
      id: 'rec_revenue_drop', titleKey: 'dash_rec_revenue_title', descriptionKey: 'dash_rec_revenue_desc',
      category: RecommendationCategory.revenue, impact: RecommendationImpact.medium, iconName: 'trending_down',
    ),
    DashboardRecommendation(
      id: 'rec_auto_reorder', titleKey: 'dash_rec_auto_title', descriptionKey: 'dash_rec_auto_desc',
      category: RecommendationCategory.automation, impact: RecommendationImpact.low, iconName: 'bolt',
    ),
  ];

  static const List<DashboardQuickAction> quickActions = [
    DashboardQuickAction(id: 'chat', labelKey: 'dash_action_ai_chat', iconName: 'auto_awesome', route: '/ai-chat'),
    DashboardQuickAction(id: 'reports', labelKey: 'dash_action_reports', iconName: 'bar_chart', route: '/reports'),
    DashboardQuickAction(id: 'invoice', labelKey: 'dash_action_invoice', iconName: 'receipt_long', route: '/accounting'),
    DashboardQuickAction(id: 'product', labelKey: 'dash_action_product', iconName: 'add_box', route: '/products'),
    DashboardQuickAction(id: 'employee', labelKey: 'dash_action_employee', iconName: 'person_add', route: '/employees'),
    DashboardQuickAction(id: 'advisor', labelKey: 'dash_action_advisor', iconName: 'lightbulb', route: '/advisor'),
  ];

  static const List<DashboardActivity> recentActivity = [
    DashboardActivity(id: 'act_1', titleKey: 'dash_act_invoice_created', timeKey: 'dash_act_just_now', iconName: 'receipt', colorName: 'primary'),
    DashboardActivity(id: 'act_2', titleKey: 'dash_act_payment_received', timeKey: 'dash_act_2h', iconName: 'payment', colorName: 'success'),
    DashboardActivity(id: 'act_3', titleKey: 'dash_act_ai_recommendation', timeKey: 'dash_act_3h', iconName: 'auto_awesome', colorName: 'accent'),
    DashboardActivity(id: 'act_4', titleKey: 'dash_act_low_stock', timeKey: 'dash_act_5h', iconName: 'warning', colorName: 'warning'),
    DashboardActivity(id: 'act_5', titleKey: 'dash_act_customer_added', timeKey: 'dash_act_1d', iconName: 'person_add', colorName: 'info'),
  ];

  static const List<OpsSnapshotItem> opsSnapshot = [
    OpsSnapshotItem(labelKey: 'dash_ops_sales', value: '\$2,480', statusKey: 'good', iconName: 'point_of_sale'),
    OpsSnapshotItem(labelKey: 'dash_ops_inventory', value: '4 alerts', statusKey: 'warning', iconName: 'warehouse'),
    OpsSnapshotItem(labelKey: 'dash_ops_payments', value: '3 pending', statusKey: 'warning', iconName: 'account_balance'),
    OpsSnapshotItem(labelKey: 'dash_ops_tasks', value: '2 active', statusKey: 'good', iconName: 'task_alt'),
  ];

  static const SetupStatus setupStatus = SetupStatus(
    modulesEnabled: 5,
    totalModules: 7,
    rolesConfigured: 4,
    aiAdvisorActive: true,
    planKey: 'dash_plan_starter',
  );
}
