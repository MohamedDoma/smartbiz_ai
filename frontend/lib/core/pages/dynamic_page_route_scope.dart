// SmartBiz AI — Dynamic Page Route Scope.
//
// InheritedWidget that exposes the DynamicPageRegistryResult for
// the current route to all descendant widgets. Wraps the shell
// content so any widget can read the current page definition
// without rebuilding on every navigation.
import 'package:flutter/widgets.dart';
import 'dynamic_page_models.dart';

class DynamicPageRouteScope extends InheritedWidget {
  const DynamicPageRouteScope({
    super.key,
    required this.result,
    required super.child,
  });

  /// Lookup result for the current route.
  final DynamicPageRegistryResult result;

  // ── Convenience getters ──────────────────────────────────

  /// The resolved page definition, or null.
  DynamicPageDefinition? get page => result.page;

  /// Whether a page definition was found for the current route.
  bool get found => result.found;

  /// The page type, or null if not found.
  DynamicPageType? get pageType => result.page?.pageType;

  // ── Static access ────────────────────────────────────────

  /// Read the scope from the widget tree. Returns null if not found.
  static DynamicPageRouteScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DynamicPageRouteScope>();

  /// Read the scope from the widget tree. Throws if not found.
  static DynamicPageRouteScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'DynamicPageRouteScope not found in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(DynamicPageRouteScope oldWidget) =>
      result.found != oldWidget.result.found ||
      result.page?.id != oldWidget.result.page?.id;
}
