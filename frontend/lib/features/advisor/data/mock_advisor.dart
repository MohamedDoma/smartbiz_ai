// SmartBiz AI — Mock advisor recommendations.
import '../models/advisor_models.dart';

class MockAdvisor {
  MockAdvisor._();

  static List<Recommendation> recommendations() => [
    Recommendation(
      id: 'rec_01', titleKey: 'adv_rec_low_stock_title', descriptionKey: 'adv_rec_low_stock_desc', detailKey: 'adv_rec_low_stock_detail',
      category: RecCategory.inventory, impact: RecImpact.high, confidence: 0.95, createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    Recommendation(
      id: 'rec_02', titleKey: 'adv_rec_overdue_title', descriptionKey: 'adv_rec_overdue_desc', detailKey: 'adv_rec_overdue_detail',
      category: RecCategory.finance, impact: RecImpact.high, confidence: 0.92, createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    Recommendation(
      id: 'rec_03', titleKey: 'adv_rec_revenue_title', descriptionKey: 'adv_rec_revenue_desc', detailKey: 'adv_rec_revenue_detail',
      category: RecCategory.sales, impact: RecImpact.medium, confidence: 0.78, createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    ),
    Recommendation(
      id: 'rec_04', titleKey: 'adv_rec_reorder_title', descriptionKey: 'adv_rec_reorder_desc', detailKey: 'adv_rec_reorder_detail',
      category: RecCategory.operations, impact: RecImpact.low, confidence: 0.85, createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    ),
    Recommendation(
      id: 'rec_05', titleKey: 'adv_rec_pricing_title', descriptionKey: 'adv_rec_pricing_desc', detailKey: 'adv_rec_pricing_detail',
      category: RecCategory.sales, impact: RecImpact.medium, confidence: 0.72, createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
    Recommendation(
      id: 'rec_06', titleKey: 'adv_rec_cashflow_title', descriptionKey: 'adv_rec_cashflow_desc', detailKey: 'adv_rec_cashflow_detail',
      category: RecCategory.finance, impact: RecImpact.high, confidence: 0.88, createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 3)),
    ),
    Recommendation(
      id: 'rec_07', titleKey: 'adv_rec_module_title', descriptionKey: 'adv_rec_module_desc', detailKey: 'adv_rec_module_detail',
      category: RecCategory.system, impact: RecImpact.low, confidence: 0.68, createdAt: DateTime.now().subtract(const Duration(days: 2)),
    ),
    Recommendation(
      id: 'rec_08', titleKey: 'adv_rec_topsel_title', descriptionKey: 'adv_rec_topsel_desc', detailKey: 'adv_rec_topsel_detail',
      category: RecCategory.sales, impact: RecImpact.medium, confidence: 0.81, createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 5)),
    ),
  ];
}
