// SmartBiz AI — ERP Module Dependency Resolver (Phase 17).
// Pure Dart. No Flutter imports. Cacheable.
import 'erp_module_models.dart';
import 'erp_module_registry.dart';

/// Result of a dependency resolution.
class DependencyResult {
  /// The full expanded set of module IDs including dependencies.
  final Set<ErpModuleId> resolved;
  /// Required dependencies that were automatically added.
  final Set<ErpModuleId> addedDependencies;
  /// Required dependencies that are missing (module not in registry).
  final Set<ErpModuleId> missingDependencies;
  /// Any circular dependency chains detected.
  final List<List<ErpModuleId>> circularChains;

  const DependencyResult({
    this.resolved = const {},
    this.addedDependencies = const {},
    this.missingDependencies = const {},
    this.circularChains = const [],
  });

  bool get hasIssues => missingDependencies.isNotEmpty || circularChains.isNotEmpty;
  bool get isClean => !hasIssues;
}

class ErpModuleDependencyResolver {
  const ErpModuleDependencyResolver();

  // Cache for repeated resolutions.
  static final Map<int, DependencyResult> _cache = {};

  /// Expands a set of requested modules with their required dependencies.
  DependencyResult resolve(Set<ErpModuleId> requested) {
    final key = Object.hashAll(requested.toList()..sort((a, b) => a.index - b.index));
    if (_cache.containsKey(key)) return _cache[key]!;

    final resolved = <ErpModuleId>{};
    final added = <ErpModuleId>{};
    final missing = <ErpModuleId>{};
    final circular = <List<ErpModuleId>>[];

    for (final id in requested) {
      _expand(id, requested, resolved, added, missing, circular, []);
    }

    final result = DependencyResult(
      resolved: resolved,
      addedDependencies: added,
      missingDependencies: missing,
      circularChains: circular,
    );
    _cache[key] = result;
    return result;
  }

  void _expand(
    ErpModuleId id,
    Set<ErpModuleId> originalRequested,
    Set<ErpModuleId> resolved,
    Set<ErpModuleId> added,
    Set<ErpModuleId> missing,
    List<List<ErpModuleId>> circular,
    List<ErpModuleId> chain,
  ) {
    if (resolved.contains(id)) return;

    // Circular check
    if (chain.contains(id)) {
      final cycleStart = chain.indexOf(id);
      circular.add([...chain.sublist(cycleStart), id]);
      return;
    }

    final def = ErpModuleRegistry.tryGet(id);
    if (def == null) {
      missing.add(id);
      return;
    }

    final newChain = [...chain, id];
    for (final dep in def.dependencies) {
      _expand(dep, originalRequested, resolved, added, missing, circular, newChain);
      if (!originalRequested.contains(dep) && !added.contains(dep)) {
        added.add(dep);
      }
    }
    resolved.add(id);
  }

  /// Returns required dependencies missing from [requested].
  Set<ErpModuleId> missingRequired(Set<ErpModuleId> requested) {
    final result = resolve(requested);
    return result.addedDependencies;
  }

  /// Validates module set has no issues. Returns error messages.
  List<String> validate(Set<ErpModuleId> modules) {
    final errors = <String>[];
    final result = resolve(modules);
    for (final m in result.missingDependencies) {
      errors.add('Module ${m.name} is not registered in the registry');
    }
    for (final chain in result.circularChains) {
      errors.add('Circular dependency: ${chain.map((c) => c.name).join(' → ')}');
    }
    return errors;
  }

  /// Clears the internal cache.
  static void clearCache() => _cache.clear();
}
