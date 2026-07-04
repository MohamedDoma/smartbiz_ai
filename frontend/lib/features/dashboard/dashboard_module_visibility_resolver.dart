// SmartBiz AI — Dashboard Module Visibility Resolver (Phase 17).
//
// Pure Dart helper that determines whether a dashboard widget or
// quick action should be visible based on enabled ERP modules.
//
// Two ownership sources are used (in priority order):
//
//   1. **Widget-level metadata**: `DashboardWidgetConfig.module` already
//      carries the owning module's apiId. When present, this is used
//      directly — no registry lookup needed.
//
//   2. **Registry reverse-lookup**: `ErpModuleDefinition.supportedWidgetIds`
//      and `supportedQuickActionIds` map module → widget/action IDs.
//      This resolver inverts that mapping at startup and caches it.
//
// Default behavior: widgets/actions with no known module owner are
// **allowed** (dashboard-system items like alerts or AI insights
// may not belong to any single module).
import '../../../core/modules/erp_module_models.dart';
import '../../../core/modules/erp_module_registry.dart';

// ═══════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════

class DashboardModuleVisibilityResolver {
  DashboardModuleVisibilityResolver._();

  // ── Cached reverse lookups ──────────────────────────────

  static Map<String, ErpModuleId>? _widgetOwnerCache;
  static Map<String, ErpModuleId>? _actionOwnerCache;

  /// Widget ID → owning module.
  /// Built from `ErpModuleDefinition.supportedWidgetIds`.
  static Map<String, ErpModuleId> get _widgetOwners {
    if (_widgetOwnerCache != null) return _widgetOwnerCache!;
    final map = <String, ErpModuleId>{};
    for (final def in ErpModuleRegistry.all) {
      for (final wId in def.supportedWidgetIds) {
        // Later (more specialized) modules overwrite, consistent with
        // the route guard strategy. In practice widget IDs are unique.
        map[wId] = def.id;
      }
    }
    _widgetOwnerCache = map;
    return map;
  }

  /// Quick-action ID → owning module.
  /// Built from `ErpModuleDefinition.supportedQuickActionIds`.
  static Map<String, ErpModuleId> get _actionOwners {
    if (_actionOwnerCache != null) return _actionOwnerCache!;
    final map = <String, ErpModuleId>{};
    for (final def in ErpModuleRegistry.all) {
      for (final qaId in def.supportedQuickActionIds) {
        map[qaId] = def.id;
      }
    }
    _actionOwnerCache = map;
    return map;
  }

  /// Clears cached lookups. Useful in tests.
  static void clearCache() {
    _widgetOwnerCache = null;
    _actionOwnerCache = null;
  }

  // ── Widget visibility ───────────────────────────────────

  /// Returns `true` if the dashboard widget [widgetId] should be shown.
  ///
  /// If [moduleApiId] is provided (from `DashboardWidgetConfig.module`),
  /// it is used as the primary ownership signal. Otherwise, the registry's
  /// `supportedWidgetIds` reverse-lookup is used.
  ///
  /// Widgets with no known owning module are **always visible** (they are
  /// considered system/dashboard-level items).
  static bool isWidgetVisible({
    required String widgetId,
    required Set<ErpModuleId> enabledModules,
    String? moduleApiId,
  }) {
    // 1. Try widget-level metadata (DashboardWidgetConfig.module).
    if (moduleApiId != null && moduleApiId.isNotEmpty) {
      final ownerId = _resolveByApiId(moduleApiId);
      if (ownerId != null) {
        return enabledModules.contains(ownerId);
      }
      // Unknown apiId → treat as system/unowned → allow.
    }

    // 2. Fall back to registry reverse-lookup.
    final registryOwner = _widgetOwners[widgetId];
    if (registryOwner != null) {
      return enabledModules.contains(registryOwner);
    }

    // 3. No owner found → allow by default.
    return true;
  }

  // ── Quick-action visibility ─────────────────────────────

  /// Returns `true` if the dashboard quick action [actionId] should be shown.
  ///
  /// Uses the registry's `supportedQuickActionIds` to determine module
  /// ownership. If no owner is found but [route] is provided, the action's
  /// target route is checked against the module route guard to prevent
  /// showing clickable buttons that silently redirect back to dashboard.
  /// Actions with no known owner and no route are **always visible**.
  static bool isActionVisible({
    required String actionId,
    required Set<ErpModuleId> enabledModules,
    String? route,
  }) {
    final owner = _actionOwners[actionId];
    if (owner != null) {
      return enabledModules.contains(owner);
    }
    // No registry owner — check route if provided.
    if (route != null && route.isNotEmpty) {
      return _isRouteModuleEnabled(route, enabledModules);
    }
    // No owner, no route → allow by default.
    return true;
  }

  /// Checks whether the module that owns [route] is enabled.
  /// Returns true if the route has no known owning module (standalone route).
  static bool _isRouteModuleEnabled(String route, Set<ErpModuleId> enabledModules) {
    // Find the module that owns this route.
    for (final def in ErpModuleRegistry.all) {
      for (final rp in def.routePaths) {
        // Normalize parameterized segments for prefix matching:
        // '/employees/invite' matches '/employees', '/invoices/create' matches '/invoices'.
        final normalizedRoute = rp.replaceAll(RegExp(r':[^/]+'), '');
        final normalizedTarget = route.replaceAll(RegExp(r':[^/]+'), '');
        if (normalizedTarget == normalizedRoute ||
            normalizedTarget.startsWith('$normalizedRoute/')) {
          return enabledModules.contains(def.id);
        }
      }
    }
    // No owning module found → standalone route → allow.
    return true;
  }

  // ── Batch helpers ───────────────────────────────────────

  /// Filters a list of widget IDs, returning only the visible ones.
  static List<String> visibleWidgetIds({
    required List<String> widgetIds,
    required Set<ErpModuleId> enabledModules,
  }) {
    return widgetIds
        .where((id) => isWidgetVisible(widgetId: id, enabledModules: enabledModules))
        .toList();
  }

  /// Filters a list of action IDs, returning only the visible ones.
  static List<String> visibleActionIds({
    required List<String> actionIds,
    required Set<ErpModuleId> enabledModules,
  }) {
    return actionIds
        .where((id) => isActionVisible(actionId: id, enabledModules: enabledModules))
        .toList();
  }

  // ── Module ID resolution ────────────────────────────────

  /// Resolves a module apiId string (e.g. 'invoices') to its ErpModuleId.
  ///
  /// This bridges the DashboardWidgetConfig.module string field to the
  /// typed ErpModuleId enum used by the module system.
  // TODO(dashboard): When dashboard configs carry ErpModuleId directly
  // instead of a string apiId, this bridge can be removed.
  static ErpModuleId? _resolveByApiId(String apiId) {
    // Linear scan is fine — small set, called infrequently per render.
    for (final def in ErpModuleRegistry.all) {
      if (def.apiId == apiId) return def.id;
    }
    return null;
  }
}
