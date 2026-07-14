// SmartBiz AI — Module Navigation Resolver (Phase 17).
//
// Pure, UI-independent resolver that converts enabled modules + permissions
// into an ordered list of navigation items. No Flutter widgets, no Provider,
// no BuildContext, no ChangeNotifier.
import 'erp_module_models.dart';
import 'erp_module_registry.dart';

/// Immutable resolved navigation item derived from the module registry.
class ResolvedNavItem {
  /// The source module ID.
  final ErpModuleId moduleId;

  /// Navigation item ID (matches legacy nav_model IDs where applicable).
  final String navItemId;

  /// Localization key for the label.
  final String labelKey;

  /// Icon identifier string.
  final String iconId;

  /// Primary route path.
  final String route;

  /// Sort order (lower = earlier).
  final int order;

  /// Whether this item is available in Basic Mode.
  final bool isBasic;

  /// Whether this item is available in Advanced Mode.
  final bool isAdvanced;

  /// The module's category.
  final ModuleCategory category;

  const ResolvedNavItem({
    required this.moduleId,
    required this.navItemId,
    required this.labelKey,
    required this.iconId,
    required this.route,
    required this.order,
    required this.isBasic,
    required this.isAdvanced,
    required this.category,
  });
}

/// Whether to resolve for Basic or Advanced mode.
enum NavigationMode { basic, advanced }

/// Pure resolver: enabled modules + permissions → navigation items.
class ModuleNavigationResolver {
  const ModuleNavigationResolver();

  /// Resolves the navigation item list from the given inputs.
  ///
  /// [enabledModules] — module IDs enabled for this workspace.
  /// [effectivePermissions] — the user's effective permission keys.
  /// [mode] — Basic or Advanced UI mode.
  ///
  /// Returns an immutable, deterministically ordered list.
  List<ResolvedNavItem> resolve({
    required Set<ErpModuleId> enabledModules,
    required Set<String> effectivePermissions,
    NavigationMode mode = NavigationMode.advanced,
  }) {
    final items = <ResolvedNavItem>[];
    final seenNavIds = <String>{};

    for (final id in enabledModules) {
      final def = ErpModuleRegistry.tryGet(id);
      if (def == null) continue;

      // Skip modules without a working frontend.
      if (!def.isUsable) continue;

      // Skip modules without routes (nothing to navigate to).
      if (!def.hasRoutes) continue;

      // Skip modules without navigation metadata.
      if (def.navigationItemIds.isEmpty) continue;

      // Visibility / mode filtering.
      if (!_passesVisibilityFilter(def, mode, enabledModules)) continue;

      // Permission check: if the module declares a *.view permission,
      // the user must have it. Modules without a view perm pass through.
      if (!_passesPermissionCheck(def, effectivePermissions)) continue;

      // Multi-navigation safety:
      // Some modules may declare multiple navigationItemIds (e.g. a module
      // with sub-sections). Until we have a reliable one-to-one mapping
      // between each navItemId and a specific route, we emit ONLY the
      // primary (first) navigation item paired with the primary (first)
      // route. This avoids incorrectly mapping unrelated nav items to the
      // same route. Future phases may introduce explicit navId→route pairs.
      final primaryNavId = def.navigationItemIds.first;
      if (seenNavIds.contains(primaryNavId)) continue;
      seenNavIds.add(primaryNavId);

      items.add(ResolvedNavItem(
        moduleId: id,
        navItemId: primaryNavId,
        labelKey: def.labelKey,
        iconId: def.iconId,
        route: def.routePaths.first,
        order: def.defaultOrder,
        isBasic: def.supportsBasicMode,
        isAdvanced: def.supportsAdvancedMode,
        category: def.category,
      ));
    }

    // Sort deterministically by order, with dashboard first / settings last.
    items.sort((a, b) {
      // Dashboard always first.
      if (a.moduleId == ErpModuleId.dashboard) return -1;
      if (b.moduleId == ErpModuleId.dashboard) return 1;
      // Settings always last.
      if (a.moduleId == ErpModuleId.settings) return 1;
      if (b.moduleId == ErpModuleId.settings) return -1;
      return a.order.compareTo(b.order);
    });

    return List.unmodifiable(items);
  }

  // ─────────────────────────────────────────────────────────

  /// Returns true if the module passes visibility filtering for [mode].
  ///
  /// Mode semantics:
  ///   Basic    → shows: both, basicOnly
  ///   Advanced → shows: both, basicOnly, advancedOnly (superset of Basic)
  ///
  /// hiddenUnlessEnabled → only shown when explicitly in [enabledModules],
  /// then respects supportsBasicMode / supportsAdvancedMode.
  bool _passesVisibilityFilter(
    ErpModuleDefinition def,
    NavigationMode mode,
    Set<ErpModuleId> enabledModules,
  ) {
    switch (def.visibility) {
      case ModuleVisibility.both:
        // Visible in all modes.
        return true;
      case ModuleVisibility.basicOnly:
        // Visible in Basic AND Advanced (Advanced is a superset).
        return true;
      case ModuleVisibility.advancedOnly:
        // Visible only in Advanced mode.
        return mode == NavigationMode.advanced;
      case ModuleVisibility.hiddenUnlessEnabled:
        // Only shown if explicitly present in the enabled module set.
        // (The caller already iterates over enabledModules, so reaching
        // here means the module IS enabled. But we still gate on mode.)
        if (!enabledModules.contains(def.id)) return false;
        if (mode == NavigationMode.basic) return def.supportsBasicMode;
        return def.supportsAdvancedMode;
    }
  }

  /// Returns true if the user has the required navigation permission.
  ///
  /// Uses the module's explicit [navigationPermissionKeys]. If the module
  /// declares no navigation permission keys, it always passes (no gate).
  /// Otherwise the user must hold at least one of the declared keys.
  bool _passesPermissionCheck(
    ErpModuleDefinition def,
    Set<String> effectivePermissions,
  ) {
    // No navigation permission declared → always visible.
    if (def.navigationPermissionKeys.isEmpty) return true;

    // User must have at least one of the navigation permission keys.
    return def.navigationPermissionKeys
        .any((p) => effectivePermissions.contains(p));
  }
}
