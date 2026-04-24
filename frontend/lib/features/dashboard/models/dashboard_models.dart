// SmartBiz AI — Dashboard data models.

/// A single metric card value.
class DashboardMetric {
  final String id;
  final String labelKey;
  final String value;
  final String? trend;       // e.g. "+12%" or "-3%"
  final bool trendUp;        // true = positive, false = negative
  final String iconName;     // mapped in widget
  final String colorName;    // mapped in widget

  const DashboardMetric({
    required this.id,
    required this.labelKey,
    required this.value,
    this.trend,
    this.trendUp = true,
    required this.iconName,
    required this.colorName,
  });
}

/// AI recommendation severity.
enum RecommendationImpact { high, medium, low }

/// AI recommendation category.
enum RecommendationCategory { inventory, finance, revenue, automation, module }

/// A single AI advisor recommendation.
class DashboardRecommendation {
  final String id;
  final String titleKey;
  final String descriptionKey;
  final RecommendationCategory category;
  final RecommendationImpact impact;
  final String iconName;

  const DashboardRecommendation({
    required this.id,
    required this.titleKey,
    required this.descriptionKey,
    required this.category,
    required this.impact,
    required this.iconName,
  });
}

/// A single quick action button.
class DashboardQuickAction {
  final String id;
  final String labelKey;
  final String iconName;
  final String route;

  const DashboardQuickAction({
    required this.id,
    required this.labelKey,
    required this.iconName,
    required this.route,
  });
}

/// A single activity entry.
class DashboardActivity {
  final String id;
  final String titleKey;
  final String timeKey;
  final String iconName;
  final String colorName;

  const DashboardActivity({
    required this.id,
    required this.titleKey,
    required this.timeKey,
    required this.iconName,
    required this.colorName,
  });
}

/// Operations snapshot item.
class OpsSnapshotItem {
  final String labelKey;
  final String value;
  final String statusKey;   // 'good', 'warning', 'alert'
  final String iconName;

  const OpsSnapshotItem({
    required this.labelKey,
    required this.value,
    required this.statusKey,
    required this.iconName,
  });
}

/// System setup status.
class SetupStatus {
  final int modulesEnabled;
  final int totalModules;
  final int rolesConfigured;
  final bool aiAdvisorActive;
  final String planKey;

  const SetupStatus({
    required this.modulesEnabled,
    required this.totalModules,
    required this.rolesConfigured,
    required this.aiAdvisorActive,
    required this.planKey,
  });
}
