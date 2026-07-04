// SmartBiz AI — Dashboard Resolver Engine (Phase 16.3).
//
// Pure business logic — no Flutter widgets, no Provider, no BuildContext.
// Resolves the final DashboardConfiguration for any employee by merging
// template defaults, workspace overrides, employee overrides, then filtering
// by effective permissions and enabled modules.
import '../data/default_dashboard_templates.dart';
import '../models/dashboard_config_models.dart';

// ═══════════════════════════════════════════════════════════
//  Role → Template mapping
// ═══════════════════════════════════════════════════════════

/// Maps a role ID to its primary dashboard template.
DashboardTemplate templateForRole(String roleId) => switch (roleId) {
  'sys_owner'            => DashboardTemplate.executive,
  'sys_cashier'          => DashboardTemplate.sales,
  'sys_warehouse'        => DashboardTemplate.inventory,
  'sys_accountant'       => DashboardTemplate.finance,
  'sys_employee'         => DashboardTemplate.basicEmployee,
  'tpl_gen_manager'      => DashboardTemplate.executive,
  'tpl_dept_manager'     => DashboardTemplate.operations,
  'tpl_manager'          => DashboardTemplate.executive,
  'tpl_team_leader'      => DashboardTemplate.operations,
  'tpl_sales'            => DashboardTemplate.sales,
  'tpl_hr_mgr'           => DashboardTemplate.hr,
  'tpl_hr'               => DashboardTemplate.hr,
  'tpl_wh_mgr'           => DashboardTemplate.inventory,
  'tpl_procurement_off'  => DashboardTemplate.operations,
  'tpl_support'          => DashboardTemplate.support,
  'tpl_pm'               => DashboardTemplate.projects,
  'tpl_service'          => DashboardTemplate.service,
  'tpl_delivery'         => DashboardTemplate.operations,
  _                      => DashboardTemplate.basicEmployee,
};

// ═══════════════════════════════════════════════════════════
//  Permission + Module helpers
// ═══════════════════════════════════════════════════════════

/// Returns true if ALL required permissions are present.
bool canRenderWidget(DashboardWidgetConfig w, Set<String> perms) {
  if (w.requiredPermissions.isEmpty) return true;
  return w.requiredPermissions.every(perms.contains);
}

/// Returns true if ALL required permissions for a quick action are present.
bool canRenderAction(DashboardQuickActionConfig a, Set<String> perms) {
  if (a.requiredPermissions.isEmpty) return true;
  return a.requiredPermissions.every(perms.contains);
}

/// Returns true if the widget's module is in the enabled set (or has none).
bool _moduleEnabled(String? module, Set<String> enabledModules) {
  if (module == null || module.isEmpty) return true;
  return enabledModules.contains(module);
}

// ═══════════════════════════════════════════════════════════
//  Merge helpers
// ═══════════════════════════════════════════════════════════

List<DashboardWidgetConfig> _mergeWidgets(
  List<DashboardWidgetConfig> base,
  List<DashboardWidgetConfig> extra,
) {
  final ids = base.map((w) => w.id).toSet();
  final merged = [...base];
  for (final w in extra) {
    if (!ids.contains(w.id)) {
      merged.add(w);
      ids.add(w.id);
    }
  }
  return merged;
}

List<DashboardQuickActionConfig> _mergeActions(
  List<DashboardQuickActionConfig> base,
  List<DashboardQuickActionConfig> extra,
) {
  final ids = base.map((a) => a.id).toSet();
  final merged = [...base];
  for (final a in extra) {
    if (!ids.contains(a.id)) {
      merged.add(a);
      ids.add(a.id);
    }
  }
  return merged;
}

/// Apply override config on top of a base config.
/// Override wins: replaces widgets/actions that share the same id,
/// adds new ones, and respects enabled/position overrides.
DashboardConfiguration _applyOverride(
  DashboardConfiguration base,
  DashboardConfiguration override,
) {
  // Build maps for override items
  final owMap = {for (final w in override.widgets) w.id: w};
  final oaMap = {for (final a in override.quickActions) a.id: a};

  // Merge widgets: override existing, keep base-only, add override-only
  final baseIds = base.widgets.map((w) => w.id).toSet();
  final mergedWidgets = <DashboardWidgetConfig>[];
  for (final w in base.widgets) {
    mergedWidgets.add(owMap[w.id] ?? w);
  }
  for (final w in override.widgets) {
    if (!baseIds.contains(w.id)) mergedWidgets.add(w);
  }

  final baseActionIds = base.quickActions.map((a) => a.id).toSet();
  final mergedActions = <DashboardQuickActionConfig>[];
  for (final a in base.quickActions) {
    mergedActions.add(oaMap[a.id] ?? a);
  }
  for (final a in override.quickActions) {
    if (!baseActionIds.contains(a.id)) mergedActions.add(a);
  }

  return DashboardConfiguration(
    id: override.id.isNotEmpty ? override.id : base.id,
    template: base.template,
    source: override.source,
    roleId: override.roleId ?? base.roleId,
    employeeId: override.employeeId ?? base.employeeId,
    widgets: mergedWidgets,
    quickActions: mergedActions,
    landingRoute: override.landingRoute.isNotEmpty ? override.landingRoute : base.landingRoute,
    layout: base.layout,
  );
}

// ═══════════════════════════════════════════════════════════
//  Main Resolver
// ═══════════════════════════════════════════════════════════

class DashboardResolver {
  const DashboardResolver();

  /// Resolves the final dashboard configuration for an employee.
  ///
  /// Resolution priority:
  /// 1. [employeeOverride] (highest)
  /// 2. [workspaceRoleConfig]
  /// 3. System default template (lowest)
  ///
  /// [templateOverride] — if a custom role explicitly specifies its template,
  /// pass it here to bypass the ID-based lookup in [templateForRole].
  ///
  /// After merging, filters by [effectivePermissions] and [enabledModules].
  /// Extra roles contribute additional widgets/actions via merge-by-id.
  DashboardConfiguration resolve({
    required String primaryRoleId,
    List<String> extraRoleIds = const [],
    required Set<String> effectivePermissions,
    required Set<String> enabledModules,
    DashboardTemplate? templateOverride,
    DashboardConfiguration? workspaceRoleConfig,
    DashboardConfiguration? employeeOverride,
  }) {
    // 1. Determine base template from primary role (or explicit override)
    final template = templateOverride ?? templateForRole(primaryRoleId);
    var config = DefaultDashboardTemplates.forTemplate(template);

    // 2. Merge extra-role widgets/actions (hybrid roles)
    for (final extraId in extraRoleIds) {
      final extraTemplate = templateForRole(extraId);
      if (extraTemplate == template) continue; // same template, skip
      final extraConfig = DefaultDashboardTemplates.forTemplate(extraTemplate);
      config = DashboardConfiguration(
        id: config.id,
        template: config.template,
        source: config.source,
        roleId: primaryRoleId,
        widgets: _mergeWidgets(config.widgets, extraConfig.widgets),
        quickActions: _mergeActions(config.quickActions, extraConfig.quickActions),
        landingRoute: config.landingRoute,
        layout: config.layout,
      );
    }

    // 3. Apply workspace role configuration override
    if (workspaceRoleConfig != null) {
      config = _applyOverride(config, workspaceRoleConfig);
    }

    // 4. Apply employee-level override (highest priority)
    if (employeeOverride != null) {
      config = _applyOverride(config, employeeOverride);
    }

    // 5. Filter by enabled status, permissions, and modules
    final filteredWidgets = config.widgets
        .where((w) => w.enabled)
        .where((w) => canRenderWidget(w, effectivePermissions))
        .where((w) => _moduleEnabled(w.module, enabledModules))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final filteredActions = config.quickActions
        .where((a) => a.enabled)
        .where((a) => canRenderAction(a, effectivePermissions))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));

    final result = DashboardConfiguration(
      id: config.id,
      template: config.template,
      source: config.source,
      roleId: config.roleId ?? primaryRoleId,
      employeeId: config.employeeId,
      widgets: filteredWidgets,
      quickActions: filteredActions,
      landingRoute: config.landingRoute,
      layout: config.layout,
    );

    // 6. Safe fallback — if empty, try basicEmployee
    if (result.widgets.isEmpty && template != DashboardTemplate.basicEmployee) {
      return resolve(
        primaryRoleId: 'sys_employee',
        effectivePermissions: effectivePermissions,
        enabledModules: enabledModules,
      );
    }

    return result;
  }
}
