// SmartBiz AI — Dynamic Page Route Resolver.
//
// Thin wrapper that resolves a navigation location to a
// DynamicPageRegistryResult. No state, no side effects.
import 'dynamic_page_models.dart';
import 'dynamic_page_registry.dart';

class DynamicPageRouteResolver {
  const DynamicPageRouteResolver();

  /// Resolve a live navigation path to a page definition.
  /// Strips query parameters and fragments before lookup.
  DynamicPageRegistryResult resolve(String location) {
    // Strip query/fragment if present.
    var path = location;
    final qIdx = path.indexOf('?');
    if (qIdx >= 0) path = path.substring(0, qIdx);
    final hIdx = path.indexOf('#');
    if (hIdx >= 0) path = path.substring(0, hIdx);

    return DynamicPageRegistry.findByRoute(path);
  }
}
