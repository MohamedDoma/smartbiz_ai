// SmartBiz AI — Dynamic Dashboard State (Phase 16.3).
//
// Lightweight ChangeNotifier that resolves and caches the current
// DashboardConfiguration via DashboardResolver. No Flutter widgets,
// no Provider, no BuildContext. Uses foundation.dart for ChangeNotifier.
//
// After the resolver produces a base config, module visibility filtering
// is applied by DashboardModuleVisibilityResolver to hide widgets/actions
// whose owning ERP module is disabled. This uses a two-layer strategy:
//   1. Widget-level metadata (DashboardWidgetConfig.module apiId)
//   2. Registry reverse-lookup (supportedWidgetIds / supportedQuickActionIds)
import 'package:flutter/foundation.dart';
import '../../core/modules/erp_module_models.dart';
import '../../core/modules/erp_module_registry.dart';
import '../../core/modules/module_route_guard.dart';
import 'dashboard_module_visibility_resolver.dart';
import 'engine/dashboard_resolver.dart';
import 'models/dashboard_config_models.dart';

class DynamicDashboardState extends ChangeNotifier {
  final DashboardResolver _resolver = const DashboardResolver();

  // ── Current inputs (cached for change detection) ────────
  String _primaryRoleId = 'sys_employee';
  List<String> _extraRoleIds = const [];
  Set<String> _effectivePermissions = const {};
  Set<String> _enabledModules = const {'dashboard', 'aiChat'};
  DashboardTemplate? _templateOverride;
  DashboardConfiguration? _workspaceRoleConfig;
  DashboardConfiguration? _employeeOverride;

  // ── Cached result ───────────────────────────────────────
  late DashboardConfiguration _config = _applyModuleVisibility(_resolve());

  // ═══════════════════════════════════════════════════════════
  //  Public getters
  // ═══════════════════════════════════════════════════════════

  DashboardConfiguration get configuration => _config;
  DashboardTemplate get template => _config.template;
  List<DashboardWidgetConfig> get widgets => _config.widgets;
  List<DashboardQuickActionConfig> get quickActions => _config.quickActions;
  String get landingRoute => _config.landingRoute;
  bool get hasContent => _config.widgets.isNotEmpty;

  String get primaryRoleId => _primaryRoleId;
  List<String> get extraRoleIds => List.unmodifiable(_extraRoleIds);
  Set<String> get effectivePermissions => Set.unmodifiable(_effectivePermissions);
  Set<String> get enabledModules => Set.unmodifiable(_enabledModules);

  // ═══════════════════════════════════════════════════════════
  //  Update context — main entry point
  // ═══════════════════════════════════════════════════════════

  /// Updates all dashboard inputs and re-resolves if anything changed.
  void updateContext({
    required String primaryRoleId,
    required List<String> extraRoleIds,
    required Set<String> effectivePermissions,
    required Set<String> enabledModules,
    DashboardTemplate? templateOverride,
    DashboardConfiguration? workspaceRoleConfig,
    DashboardConfiguration? employeeOverride,
  }) {
    if (_inputsEqual(primaryRoleId, extraRoleIds, effectivePermissions,
        enabledModules, templateOverride, workspaceRoleConfig, employeeOverride)) {
      return; // no change — skip resolution
    }
    _primaryRoleId = primaryRoleId;
    _extraRoleIds = List.unmodifiable(extraRoleIds);
    _effectivePermissions = Set.unmodifiable(effectivePermissions);
    _enabledModules = Set.unmodifiable(enabledModules);
    _templateOverride = templateOverride;
    _workspaceRoleConfig = workspaceRoleConfig;
    _employeeOverride = employeeOverride;
    _recompute();
  }

  // ═══════════════════════════════════════════════════════════
  //  Individual setters (future API integration)
  // ═══════════════════════════════════════════════════════════

  void setWorkspaceRoleConfig(DashboardConfiguration? config) {
    if (identical(_workspaceRoleConfig, config)) return;
    _workspaceRoleConfig = config;
    _recompute();
  }

  void setEmployeeOverride(DashboardConfiguration? config) {
    if (identical(_employeeOverride, config)) return;
    _employeeOverride = config;
    _recompute();
  }

  void clearEmployeeOverride() => setEmployeeOverride(null);

  void reset() {
    _primaryRoleId = 'sys_employee';
    _extraRoleIds = const [];
    _effectivePermissions = const {};
    _enabledModules = const {'dashboard', 'aiChat'};
    _templateOverride = null;
    _workspaceRoleConfig = null;
    _employeeOverride = null;
    _recompute();
  }

  // ═══════════════════════════════════════════════════════════
  //  Preview — does NOT modify current state
  // ═══════════════════════════════════════════════════════════

  /// Resolves a dashboard preview without affecting the current
  /// employee dashboard. Use in Role Builder / Role Detail preview.
  DashboardConfiguration preview({
    required String roleId,
    List<String> extraRoleIds = const [],
    required Set<String> effectivePermissions,
    required Set<String> enabledModules,
    DashboardTemplate? templateOverride,
    DashboardConfiguration? workspaceRoleConfig,
  }) {
    return _resolver.resolve(
      primaryRoleId: roleId,
      extraRoleIds: extraRoleIds,
      effectivePermissions: effectivePermissions,
      enabledModules: enabledModules,
      templateOverride: templateOverride,
      workspaceRoleConfig: workspaceRoleConfig,
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Internals
  // ═══════════════════════════════════════════════════════════

  DashboardConfiguration _resolve() => _resolver.resolve(
    primaryRoleId: _primaryRoleId,
    extraRoleIds: _extraRoleIds,
    effectivePermissions: _effectivePermissions,
    enabledModules: _enabledModules,
    templateOverride: _templateOverride,
    workspaceRoleConfig: _workspaceRoleConfig,
    employeeOverride: _employeeOverride,
  );

  void _recompute() {
    _config = _applyModuleVisibility(_resolve());
    notifyListeners();
  }

  /// Post-processing step: filters the resolved config through
  /// DashboardModuleVisibilityResolver to hide widgets/actions
  /// whose owning ERP module is disabled in the workspace.
  DashboardConfiguration _applyModuleVisibility(DashboardConfiguration config) {
    final erpIds = _toErpModuleIdSet(_enabledModules);
    // If conversion yielded no IDs (e.g. empty or all-unknown), skip
    // filtering to preserve the resolver's fallback behavior.
    if (erpIds.isEmpty && _enabledModules.isNotEmpty) return config;

    final filteredWidgets = config.widgets
        .where((w) => DashboardModuleVisibilityResolver.isWidgetVisible(
              widgetId: w.id,
              enabledModules: erpIds,
              moduleApiId: w.module,
            ))
        .toList();

    final filteredActions = <DashboardQuickActionConfig>[];
    for (final a in config.quickActions) {
      // Hide actions with no route — they are dead buttons.
      if (a.route.isEmpty) {
        continue;
      }
      // Use ModuleRouteGuard — the same check the router uses.
      final decision = ModuleRouteGuard.evaluate(
        location: a.route,
        enabledModules: erpIds,
        effectivePermissions: _effectivePermissions,
      );
      if (!decision.allowed) {
        continue;
      }
      filteredActions.add(a);
    }



    return DashboardConfiguration(
      id: config.id,
      template: config.template,
      source: config.source,
      roleId: config.roleId,
      employeeId: config.employeeId,
      widgets: filteredWidgets,
      quickActions: filteredActions,
      landingRoute: config.landingRoute,
      layout: config.layout,
    );
  }

  /// Converts enabledModules string keys to typed ErpModuleId set.
  ///
  /// Matches by registry `apiId` (snake_case: 'ai_chat') first,
  /// then falls back to matching by `ErpModuleId.name` (camelCase: 'aiChat').
  /// This handles both formats since the dashboard adapter outputs
  /// camelCase keys while the ERP registry uses snake_case apiIds.
  static Set<ErpModuleId> _toErpModuleIdSet(Set<String> moduleKeys) {
    final result = <ErpModuleId>{};
    for (final key in moduleKeys) {
      bool matched = false;
      // 1. Try matching by registry apiId (snake_case).
      for (final def in ErpModuleRegistry.all) {
        if (def.apiId == key) {
          result.add(def.id);
          matched = true;
          break;
        }
      }
      if (matched) continue;
      // 2. Fall back to matching by ErpModuleId.name (camelCase).
      for (final id in ErpModuleId.values) {
        if (id.name == key) {
          result.add(id);
          break;
        }
      }
    }
    return result;
  }

  bool _inputsEqual(
    String roleId,
    List<String> extras,
    Set<String> perms,
    Set<String> modules,
    DashboardTemplate? tplOverride,
    DashboardConfiguration? wsConfig,
    DashboardConfiguration? empOverride,
  ) {
    if (roleId != _primaryRoleId) return false;
    if (!listEquals(extras, _extraRoleIds)) return false;
    if (!setEquals(perms, _effectivePermissions)) return false;
    if (!setEquals(modules, _enabledModules)) return false;
    if (tplOverride != _templateOverride) return false;
    if (!identical(wsConfig, _workspaceRoleConfig)) return false;
    if (!identical(empOverride, _employeeOverride)) return false;
    return true;
  }
}
