// SmartBiz AI — Blueprint Landing Route Resolver (Phase 17).
//
// Pure Dart helper that determines the safest route to land on after
// login, onboarding, or a fallback redirect. Delegates all route-to-module
// ownership checks to ModuleRouteGuard so ownership logic is never
// duplicated.
//
// Usage:
//   final decision = BlueprintLandingRouteResolver.resolve(
//     preferredRoute: dashboardState.landingRoute,
//     enabledModules: workspaceModuleState.enabledModuleIds,
//   );
//   router.go(decision.route);
import 'erp_module_models.dart';
import 'module_route_guard.dart';

// ═══════════════════════════════════════════════════════════
//  Decision Result
// ═══════════════════════════════════════════════════════════

/// Result of a landing route resolution attempt.
class BlueprintLandingRouteDecision {
  /// The resolved route to navigate to.
  final String route;

  /// Whether the fallback route was used instead of the preferred one.
  final bool usedFallback;

  /// Human-readable explanation of the decision.
  final String reason;

  const BlueprintLandingRouteDecision._({
    required this.route,
    required this.usedFallback,
    required this.reason,
  });

  @override
  String toString() => 'BlueprintLandingRouteDecision('
      'route: $route, '
      'usedFallback: $usedFallback, '
      'reason: $reason)';
}

// ═══════════════════════════════════════════════════════════
//  Resolver
// ═══════════════════════════════════════════════════════════

/// The hard-coded ultimate fallback when everything else is blocked.
/// Dashboard is a system-required module that should always be available.
const _ultimateFallback = '/dashboard';

class BlueprintLandingRouteResolver {
  BlueprintLandingRouteResolver._();

  /// Resolves which route the user should land on.
  ///
  /// [preferredRoute] — the route the user or role config wants (e.g.
  ///   from `DashboardConfiguration.landingRoute`). May be null/empty.
  ///
  /// [fallbackRoute] — used if the preferred route is null, empty, or
  ///   blocked by the module guard. Defaults to `/dashboard`.
  ///
  /// [enabledModules] — the set of module IDs enabled for the current
  ///   workspace, sourced from `WorkspaceModuleState.enabledModuleIds`.
  /// [effectivePermissions] — the user's current permission strings,
  ///   forwarded to the module route guard for permission gating.
  ///
  /// Resolution order:
  ///   1. Try normalized preferred route → allowed? → use it.
  ///   2. Try normalized fallback route → allowed? → use it.
  ///   3. Use `/dashboard` as the ultimate fallback.
  static BlueprintLandingRouteDecision resolve({
    String? preferredRoute,
    String fallbackRoute = '/dashboard',
    required Set<ErpModuleId> enabledModules,
    Set<String> effectivePermissions = const {},
  }) {
    // ── 1. Normalize preferred route ─────────────────────────
    final normalizedPreferred = _normalize(preferredRoute);

    if (normalizedPreferred == null) {
      // No preferred route given → go straight to fallback.
      return _tryFallback(
        fallbackRoute: fallbackRoute,
        enabledModules: enabledModules,
        effectivePermissions: effectivePermissions,
        reason: 'No preferred route provided',
      );
    }

    // ── 2. Validate preferred route against module guard ─────
    final guardDecision = ModuleRouteGuard.evaluate(
      location: normalizedPreferred,
      enabledModules: enabledModules,
      effectivePermissions: effectivePermissions,
      fallbackRoute: fallbackRoute,
    );

    if (guardDecision.allowed) {
      return BlueprintLandingRouteDecision._(
        route: normalizedPreferred,
        usedFallback: false,
        reason: 'Preferred route allowed: ${guardDecision.reason}',
      );
    }

    // ── 3. Preferred is blocked → try fallback ───────────────
    return _tryFallback(
      fallbackRoute: fallbackRoute,
      enabledModules: enabledModules,
      effectivePermissions: effectivePermissions,
      reason: 'Preferred route blocked: ${guardDecision.reason}',
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Internals
  // ═══════════════════════════════════════════════════════════

  /// Attempts to use [fallbackRoute]. If the fallback itself is blocked,
  /// falls through to the ultimate fallback (`/dashboard`).
  static BlueprintLandingRouteDecision _tryFallback({
    required String fallbackRoute,
    required Set<ErpModuleId> enabledModules,
    Set<String> effectivePermissions = const {},
    required String reason,
  }) {
    final normalizedFallback = _normalize(fallbackRoute) ?? _ultimateFallback;

    // Prevent self-referencing loop: if the fallback IS the ultimate
    // fallback, skip the double-check.
    if (normalizedFallback == _ultimateFallback) {
      return BlueprintLandingRouteDecision._(
        route: _ultimateFallback,
        usedFallback: true,
        reason: '$reason → using dashboard fallback',
      );
    }

    final fallbackGuard = ModuleRouteGuard.evaluate(
      location: normalizedFallback,
      enabledModules: enabledModules,
      effectivePermissions: effectivePermissions,
      fallbackRoute: _ultimateFallback,
    );

    if (fallbackGuard.allowed) {
      return BlueprintLandingRouteDecision._(
        route: normalizedFallback,
        usedFallback: true,
        reason: '$reason → fallback route allowed: ${fallbackGuard.reason}',
      );
    }

    // Fallback also blocked → ultimate fallback.
    return BlueprintLandingRouteDecision._(
      route: _ultimateFallback,
      usedFallback: true,
      reason: '$reason → fallback also blocked: ${fallbackGuard.reason} '
          '→ using dashboard ultimate fallback',
    );
  }

  /// Normalizes a route string:
  ///   - trims whitespace
  ///   - ensures it starts with '/'
  ///   - strips query string and hash fragment
  ///   - strips trailing slash (except root '/')
  ///   - returns null if the result is empty after normalization
  static String? _normalize(String? route) {
    if (route == null) return null;

    var path = route.trim();
    if (path.isEmpty) return null;

    // Ensure leading slash.
    if (!path.startsWith('/')) {
      path = '/$path';
    }

    // Strip query string.
    final queryIdx = path.indexOf('?');
    if (queryIdx >= 0) path = path.substring(0, queryIdx);

    // Strip hash fragment.
    final hashIdx = path.indexOf('#');
    if (hashIdx >= 0) path = path.substring(0, hashIdx);

    // Strip trailing slash (except root).
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Final check after stripping.
    if (path.isEmpty) return null;

    return path;
  }
}
