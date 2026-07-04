// SmartBiz AI — Dynamic Dashboard Configuration Models (Phase 16.3).
//
// These models mirror a future backend API response shape.
// They drive the dynamic dashboard engine so every role (system, custom,
// hybrid) gets a data-driven dashboard without hardcoded per-role screens.

/// Dashboard template type — determines the visual and data focus.
enum DashboardTemplate {
  executive,
  sales,
  finance,
  inventory,
  hr,
  projects,
  operations,
  support,
  service,
  basicEmployee,
  custom;

  String get labelKey => 'dtpl_$name';
  String get descriptionKey => 'dtpl_${name}_desc';

  String get iconName => switch (this) {
    executive => 'shield',
    sales => 'point_of_sale',
    finance => 'account_balance',
    inventory => 'warehouse',
    hr => 'badge',
    projects => 'folder',
    operations => 'speed',
    support => 'support_agent',
    service => 'build',
    basicEmployee => 'person',
    custom => 'dashboard_customize',
  };

  String get colorName => switch (this) {
    executive => 'primary',
    sales => 'success',
    finance => 'primary',
    inventory => 'warning',
    hr => 'info',
    projects => 'accent',
    operations => 'warning',
    support => 'info',
    service => 'success',
    basicEmployee => 'info',
    custom => 'accent',
  };
}

/// Where a dashboard configuration originates from.
enum DashboardSource {
  systemDefault,
  workspaceRole,
  employeeOverride,
  aiGenerated,
}

/// Size hint for a dashboard widget.
enum WidgetSize { small, medium, large }

/// Supported dynamic widget types.
enum DashWidgetType {
  metric,
  aiInsight,
  quickActions,
  alerts,
  recentActivity,
  taskList,
  chartPlaceholder,
  moduleSummary,
  approvalQueue,
  employeeSummary,
  financeSummary,
  inventorySummary,
  customerSummary,
  projectSummary,
  supportQueue,
  hrSummary,
  serviceSchedule,
  operationsStatus,
  announcements,
  setupStatus,
  recommendations,
}

// ═══════════════════════════════════════════════════════════
//  Widget configuration (individual dashboard cell)
// ═══════════════════════════════════════════════════════════
class DashboardWidgetConfig {
  final String id;
  final DashWidgetType type;
  final String titleKey;
  /// The ERP module this widget relates to (for filtering).
  final String? module;
  /// Permission strings needed to render, e.g. ["invoices.view"].
  final List<String> requiredPermissions;
  final int position;
  final WidgetSize size;
  bool enabled;
  /// Extra data (mock values, thresholds, etc.)
  final Map<String, dynamic> metadata;

  DashboardWidgetConfig({
    required this.id,
    required this.type,
    required this.titleKey,
    this.module,
    this.requiredPermissions = const [],
    this.position = 0,
    this.size = WidgetSize.small,
    this.enabled = true,
    this.metadata = const {},
  });

  DashboardWidgetConfig copyWith({
    int? position,
    bool? enabled,
    WidgetSize? size,
  }) => DashboardWidgetConfig(
    id: id, type: type, titleKey: titleKey, module: module,
    requiredPermissions: requiredPermissions,
    position: position ?? this.position,
    size: size ?? this.size,
    enabled: enabled ?? this.enabled,
    metadata: metadata,
  );
}

// ═══════════════════════════════════════════════════════════
//  Quick action configuration
// ═══════════════════════════════════════════════════════════
class DashboardQuickActionConfig {
  final String id;
  final String labelKey;
  final String iconName;
  final String route;
  final List<String> requiredPermissions;
  final int position;
  bool enabled;

  DashboardQuickActionConfig({
    required this.id,
    required this.labelKey,
    required this.iconName,
    required this.route,
    this.requiredPermissions = const [],
    this.position = 0,
    this.enabled = true,
  });

  DashboardQuickActionConfig copyWith({
    int? position,
    bool? enabled,
  }) => DashboardQuickActionConfig(
    id: id, labelKey: labelKey, iconName: iconName, route: route,
    requiredPermissions: requiredPermissions,
    position: position ?? this.position,
    enabled: enabled ?? this.enabled,
  );
}

// ═══════════════════════════════════════════════════════════
//  Layout configuration
// ═══════════════════════════════════════════════════════════
class DashboardLayoutConfig {
  final int desktopColumns;
  final int tabletColumns;
  final int mobileColumns;

  const DashboardLayoutConfig({
    this.desktopColumns = 4,
    this.tabletColumns = 2,
    this.mobileColumns = 1,
  });
}

// ═══════════════════════════════════════════════════════════
//  Full dashboard configuration
// ═══════════════════════════════════════════════════════════
class DashboardConfiguration {
  final String id;
  final DashboardTemplate template;
  final DashboardSource source;
  /// Optional: if tied to a specific role.
  final String? roleId;
  /// Optional: employee-level override.
  final String? employeeId;
  final List<DashboardWidgetConfig> widgets;
  final List<DashboardQuickActionConfig> quickActions;
  final String landingRoute;
  final DashboardLayoutConfig layout;

  const DashboardConfiguration({
    required this.id,
    required this.template,
    required this.source,
    this.roleId,
    this.employeeId,
    this.widgets = const [],
    this.quickActions = const [],
    this.landingRoute = '/dashboard',
    this.layout = const DashboardLayoutConfig(),
  });

  /// Merge extra widgets from another configuration (hybrid-role).
  DashboardConfiguration mergeWith(DashboardConfiguration other) {
    final existingIds = widgets.map((w) => w.id).toSet();
    final mergedWidgets = [
      ...widgets,
      ...other.widgets.where((w) => !existingIds.contains(w.id)),
    ];
    mergedWidgets.sort((a, b) => a.position.compareTo(b.position));

    final existingActionIds = quickActions.map((a) => a.id).toSet();
    final mergedActions = [
      ...quickActions,
      ...other.quickActions.where((a) => !existingActionIds.contains(a.id)),
    ];
    mergedActions.sort((a, b) => a.position.compareTo(b.position));

    return DashboardConfiguration(
      id: id,
      template: template,
      source: source,
      roleId: roleId,
      employeeId: employeeId,
      widgets: mergedWidgets,
      quickActions: mergedActions,
      landingRoute: landingRoute,
      layout: layout,
    );
  }
}
