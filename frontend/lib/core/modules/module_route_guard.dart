// SmartBiz AI — Module Route Guard (Phase 17).
//
// Pure route guard helper that decides whether a navigation target
// is allowed based on enabled ERP modules. Does not perform navigation
// itself — returns a decision object for the caller (router redirect,
// middleware, etc.) to act on.
//
// Route → module ownership is derived from the module registry's
// `routePaths`, so adding a new module with routes automatically
// registers it for guard enforcement.
//
// Routes NOT owned by any module (onboarding, auth, admin, unknown)
// are always allowed — this guard only blocks module-owned routes
// when their module is disabled.
import 'erp_module_models.dart';
import 'erp_module_registry.dart';

// ═══════════════════════════════════════════════════════════
//  Decision Result
// ═══════════════════════════════════════════════════════════

/// The result of a route guard evaluation.
class ModuleRouteGuardDecision {
  /// Whether the route is allowed.
  final bool allowed;

  /// The module that owns this route (null if not module-owned).
  final ErpModuleId? blockedModuleId;

  /// The route to redirect to when blocked (null if allowed).
  final String? redirectRoute;

  /// Human-readable reason for the decision.
  final String reason;

  const ModuleRouteGuardDecision._({
    required this.allowed,
    this.blockedModuleId,
    this.redirectRoute,
    required this.reason,
  });

  /// Allowed decision.
  const ModuleRouteGuardDecision.allow(String reason)
      : this._(allowed: true, reason: reason);

  /// Blocked decision with redirect.
  const ModuleRouteGuardDecision.block({
    required ErpModuleId moduleId,
    required String redirectRoute,
    required String reason,
  }) : this._(
          allowed: false,
          blockedModuleId: moduleId,
          redirectRoute: redirectRoute,
          reason: reason,
        );

  @override
  String toString() => 'ModuleRouteGuardDecision('
      'allowed: $allowed, '
      'blockedModuleId: $blockedModuleId, '
      'redirectRoute: $redirectRoute, '
      'reason: $reason)';
}

// ═══════════════════════════════════════════════════════════
//  Route Guard
// ═══════════════════════════════════════════════════════════

class ModuleRouteGuard {
  ModuleRouteGuard._();

  // ── Cached route → module mapping ────────────────────────

  /// Lazily built map from normalized route prefix → owning module ID.
  /// Built once from the registry; covers all modules that declare routes.
  static Map<String, ErpModuleId>? _routeOwnerCache;

  static Map<String, ErpModuleId> get _routeOwners {
    if (_routeOwnerCache != null) return _routeOwnerCache!;

    final map = <String, ErpModuleId>{};
    for (final def in ErpModuleRegistry.all) {
      for (final route in def.routePaths) {
        // Normalize registry route templates:
        // '/invoices/:id' → '/invoices' (strip param segments for prefix matching).
        // '/accounting/expenses' → '/accounting/expenses' (keep static segments).
        final normalized = _normalizeRegistryRoute(route);
        // When two modules claim the same normalized route, the later
        // (more specialized) module wins. For example, the expenses module
        // (order 310) overwrites accounting's (order 300) claim on
        // '/accounting/expenses'. Since the registry is ordered by
        // defaultOrder, specialized sub-modules naturally come after
        // their parent modules.
        map[normalized] = def.id;
      }
    }
    _routeOwnerCache = map;
    return map;
  }

  /// Clears the cached route map. Useful in tests if the registry changes.
  static void clearCache() {
    _routeOwnerCache = null;
  }

  // ── Public API ───────────────────────────────────────────

  /// Evaluates whether [location] is allowed given [enabledModules].
  ///
  /// Returns a [ModuleRouteGuardDecision] indicating whether the route
  /// is allowed, and if not, which module owns it and where to redirect.
  ///
  /// Routes not owned by any module are always allowed.
  /// Dashboard and settings are always allowed when enabled (they are
  /// system-required and always present in [enabledModules]).
  static ModuleRouteGuardDecision evaluate({
    required String location,
    required Set<ErpModuleId> enabledModules,
    String fallbackRoute = '/dashboard',
  }) {
    final normalizedPath = _normalizeLocation(location);

    // Find the owning module for this route.
    final ownerModuleId = _findOwner(normalizedPath);

    // Not module-owned → always allowed.
    if (ownerModuleId == null) {
      return const ModuleRouteGuardDecision.allow(
        'Route is not owned by any module',
      );
    }

    // Module is enabled → allowed.
    if (enabledModules.contains(ownerModuleId)) {
      return ModuleRouteGuardDecision.allow(
        'Module ${ownerModuleId.name} is enabled',
      );
    }

    // Module is disabled → blocked.
    return ModuleRouteGuardDecision.block(
      moduleId: ownerModuleId,
      redirectRoute: fallbackRoute,
      reason: 'Module ${ownerModuleId.name} is not enabled',
    );
  }

  // ── Internals ────────────────────────────────────────────

  /// Normalizes a live navigation location for matching:
  ///   - strips query string and hash fragment
  ///   - strips trailing slash (except root '/')
  ///   - lowercases for safety
  static String _normalizeLocation(String location) {
    // Strip query string.
    var path = location;
    final queryIdx = path.indexOf('?');
    if (queryIdx >= 0) path = path.substring(0, queryIdx);
    // Strip hash fragment.
    final hashIdx = path.indexOf('#');
    if (hashIdx >= 0) path = path.substring(0, hashIdx);
    // Strip trailing slash (except root).
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return path.toLowerCase();
  }

  /// Normalizes a registry route template by stripping parameter segments.
  /// '/invoices/:id' → '/invoices'
  /// '/employees/:id/assignment' → '/employees'
  /// '/settings/workspace' → '/settings/workspace'
  static String _normalizeRegistryRoute(String route) {
    final segments = route.split('/');
    final normalized = <String>[];
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      if (seg.startsWith(':')) break; // stop at first param
      normalized.add(seg);
    }
    final result = '/${normalized.join('/')}';
    return result.toLowerCase();
  }

  /// Finds the owning module for a normalized path.
  ///
  /// Uses longest-prefix matching so that '/accounting/expenses' matches
  /// the expenses module before the accounting module. This is important
  /// for shared-prefix routes.
  static ErpModuleId? _findOwner(String normalizedPath) {
    final owners = _routeOwners;

    // Try exact match first (most common case).
    if (owners.containsKey(normalizedPath)) {
      return owners[normalizedPath];
    }

    // Try prefix matching for nested detail routes.
    // e.g. '/customers/123' should match '/customers'.
    // We walk from longest to shortest prefix to find the most specific match.
    ErpModuleId? bestMatch;
    int bestLength = 0;
    for (final entry in owners.entries) {
      final prefix = entry.key;
      if (normalizedPath.startsWith(prefix) &&
          prefix.length > bestLength &&
          // Ensure we match at a segment boundary:
          // '/customers' should match '/customers/123'
          // but '/custom' should NOT match '/customers'.
          (normalizedPath.length == prefix.length ||
           normalizedPath[prefix.length] == '/')) {
        bestMatch = entry.value;
        bestLength = prefix.length;
      }
    }
    return bestMatch;
  }
}
