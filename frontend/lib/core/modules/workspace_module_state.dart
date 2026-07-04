// SmartBiz AI — Workspace Module State (Phase 17).
//
// Manages the set of modules enabled for the current workspace,
// as determined by an AI-generated blueprint or manual selection.
// Uses the module registry and dependency resolver to ensure consistency.
import 'package:flutter/foundation.dart';
import 'erp_module_models.dart';
import 'erp_module_registry.dart';
import 'erp_module_dependency_resolver.dart';

/// Modules that can never be disabled. Absolute system requirement.
const Set<ErpModuleId> _hardRequiredModules = {
  ErpModuleId.dashboard,
  ErpModuleId.settings,
};

/// Modules enabled by default in the demo/initial state but NOT
/// system-required — they can be disabled by blueprint or owner.
const Set<ErpModuleId> _defaultOptionalModules = {
  ErpModuleId.aiChat,
  ErpModuleId.aiAdvisor,
};

class WorkspaceModuleState extends ChangeNotifier {
  final ErpModuleDependencyResolver _resolver;

  /// Internal selection map: moduleId → selection.
  final Map<ErpModuleId, BlueprintModuleSelection> _selections = {};

  /// Whether a full blueprint has been applied.
  bool _blueprintApplied = false;

  WorkspaceModuleState({
    ErpModuleDependencyResolver? resolver,
  }) : _resolver = resolver ?? const ErpModuleDependencyResolver() {
    _applyDefaults();
  }

  // ═══════════════════════════════════════════════════════════
  //  Public Getters
  // ═══════════════════════════════════════════════════════════

  /// Whether a blueprint has been applied to this workspace.
  bool get blueprintApplied => _blueprintApplied;

  /// All current selections (enabled and disabled).
  List<BlueprintModuleSelection> get selections =>
      List.unmodifiable(_selections.values.toList());

  /// Only the enabled module IDs, sorted by navigation order.
  List<ErpModuleId> get enabledModuleIds {
    final enabled = _selections.entries
        .where((e) => e.value.enabled)
        .toList()
      ..sort((a, b) => a.value.navigationOrder.compareTo(b.value.navigationOrder));
    return enabled.map((e) => e.key).toList();
  }

  /// Enabled module definitions, sorted by navigation order.
  List<ErpModuleDefinition> get enabledModules {
    return enabledModuleIds
        .map((id) => ErpModuleRegistry.tryGet(id))
        .whereType<ErpModuleDefinition>()
        .toList();
  }

  /// Whether a specific module is currently enabled.
  bool isEnabled(ErpModuleId id) =>
      _selections[id]?.enabled ?? false;

  /// Get the selection for a module, or null if not present.
  BlueprintModuleSelection? selectionFor(ErpModuleId id) => _selections[id];

  /// Get the source/reason for a module's selection.
  ModuleConfigurationSource? sourceFor(ErpModuleId id) =>
      _selections[id]?.source;

  /// Get module-specific settings.
  Map<String, dynamic> settingsFor(ErpModuleId id) =>
      _selections[id]?.settings ?? const {};

  /// Get the navigation order for a module.
  int navigationOrderFor(ErpModuleId id) =>
      _selections[id]?.navigationOrder ?? 999;

  /// Returns modules that depend on [id] and are currently enabled.
  /// Used to explain why a module cannot be disabled.
  Set<ErpModuleId> dependentsOf(ErpModuleId id) {
    final dependents = <ErpModuleId>{};
    for (final entry in _selections.entries) {
      if (!entry.value.enabled) continue;
      final def = ErpModuleRegistry.tryGet(entry.key);
      if (def != null && def.dependencies.contains(id)) {
        dependents.add(entry.key);
      }
    }
    return dependents;
  }

  /// Whether a module can be safely disabled without breaking dependents.
  bool canDisable(ErpModuleId id) {
    // Hard-required modules can never be disabled.
    if (_hardRequiredModules.contains(id)) return false;
    final sel = _selections[id];
    if (sel == null || !sel.enabled) return false;
    // System-required modules cannot be disabled.
    if (sel.source == ModuleConfigurationSource.systemRequired) return false;
    // Cannot disable if other enabled modules depend on this one.
    return dependentsOf(id).isEmpty;
  }

  // ═══════════════════════════════════════════════════════════
  //  Mutation Methods
  // ═══════════════════════════════════════════════════════════

  /// Apply a full blueprint module selection list.
  /// Replaces the current state entirely.
  void applyBlueprint(List<BlueprintModuleSelection> blueprint) {
    _selections.clear();

    // Add all blueprint selections.
    for (final sel in blueprint) {
      _selections[sel.moduleId] = sel;
    }

    // Ensure hard-required modules are always present.
    _ensureHardRequired();

    // Resolve dependencies for enabled modules.
    _resolveAndAddDependencies();

    _blueprintApplied = true;
    notifyListeners();
  }

  /// Enable a single module. Automatically enables required dependencies.
  /// Returns the set of additionally enabled dependency module IDs.
  Set<ErpModuleId> enableModule(
    ErpModuleId id, {
    ModuleConfigurationSource source = ModuleConfigurationSource.ownerSelected,
    Map<String, dynamic> settings = const {},
    int? navigationOrder,
  }) {
    final existing = _selections[id];
    if (existing != null && existing.enabled) {
      // Already enabled — but upgrade source if the caller is providing
      // a stronger source (e.g. dependency → ownerSelected).
      if (_shouldUpgradeSource(existing.source, source)) {
        _selections[id] = BlueprintModuleSelection(
          moduleId: id,
          enabled: true,
          source: source,
          settings: settings.isNotEmpty ? settings : existing.settings,
          navigationOrder: navigationOrder ?? existing.navigationOrder,
        );
        notifyListeners();
      }
      return {};
    }

    final def = ErpModuleRegistry.tryGet(id);
    final order = navigationOrder ?? def?.defaultOrder ?? 999;

    _selections[id] = BlueprintModuleSelection(
      moduleId: id,
      enabled: true,
      source: source,
      settings: settings,
      navigationOrder: order,
    );

    // Resolve and add missing dependencies.
    final addedDeps = _resolveAndAddDependencies();
    notifyListeners();
    return addedDeps;
  }

  /// Disable a module. Fails silently if the module is required by
  /// other enabled modules or is system-required. Returns true if disabled.
  /// After disabling, cleans up orphaned dependency modules.
  bool disableModule(ErpModuleId id) {
    if (!canDisable(id)) return false;

    final existing = _selections[id];
    if (existing == null || !existing.enabled) return false;

    _selections[id] = BlueprintModuleSelection(
      moduleId: id,
      enabled: false,
      source: ModuleConfigurationSource.manuallyDisabled,
      settings: existing.settings,
      navigationOrder: existing.navigationOrder,
    );

    // Clean up orphaned dependencies.
    _cleanOrphanedDependencies();

    notifyListeners();
    return true;
  }

  /// Reset to the safe default core-only state.
  void reset() {
    _selections.clear();
    _blueprintApplied = false;
    _applyDefaults();
    notifyListeners();
  }

  /// Apply a frontend-only blueprint profile by enabling the given modules.
  ///
  /// Additive: does not disable already-enabled modules.
  /// Uses the standard [enableModule] path so dependency resolution applies.
  /// Marks [blueprintApplied] = true to suppress the "Setup" sidebar badge.
  ///
  /// Temporary: this method is the frontend demo/profile bridge until
  /// AI/backend blueprint configuration is connected.
  void applyFrontendBlueprintProfile(Set<ErpModuleId> moduleIds) {
    if (_blueprintApplied) return; // already applied — do not re-apply

    bool changed = false;
    for (final id in moduleIds) {
      // Skip if already enabled — enableModule handles this but we
      // avoid unnecessary notifyListeners churn by batching.
      if (isEnabled(id)) continue;
      // Skip modules without usable frontend (planned/unavailable).
      final def = ErpModuleRegistry.tryGet(id);
      if (def != null && !def.isUsable) continue;

      _selections[id] = BlueprintModuleSelection(
        moduleId: id,
        enabled: true,
        source: ModuleConfigurationSource.ownerSelected,
        navigationOrder: def?.defaultOrder ?? 999,
      );
      changed = true;
    }

    // Resolve dependencies for all newly enabled modules.
    if (changed) {
      _resolveAndAddDependencies();
    }

    _blueprintApplied = true;
    notifyListeners();
  }

  /// Reconcile an already-applied frontend blueprint profile with new modules.
  ///
  /// Additive only: enables modules present in [moduleIds] that are usable
  /// but not yet enabled. Does not disable existing modules. Does not reset
  /// navigation mode. Only notifies listeners if something changed.
  ///
  /// Temporary: same as applyFrontendBlueprintProfile, this is the frontend
  /// demo/profile bridge until AI/backend blueprint configuration is connected.
  void reconcileFrontendBlueprintProfile(Set<ErpModuleId> moduleIds) {
    bool changed = false;
    for (final id in moduleIds) {
      if (isEnabled(id)) continue;
      final def = ErpModuleRegistry.tryGet(id);
      if (def != null && !def.isUsable) continue;

      _selections[id] = BlueprintModuleSelection(
        moduleId: id,
        enabled: true,
        source: ModuleConfigurationSource.ownerSelected,
        navigationOrder: def?.defaultOrder ?? 999,
      );
      changed = true;
    }

    if (changed) {
      _resolveAndAddDependencies();
      notifyListeners();
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Internal
  // ═══════════════════════════════════════════════════════════

  void _applyDefaults() {
    // Hard-required: systemRequired, cannot be disabled.
    for (final id in _hardRequiredModules) {
      final def = ErpModuleRegistry.tryGet(id);
      _selections[id] = BlueprintModuleSelection(
        moduleId: id,
        enabled: true,
        required: true,
        source: ModuleConfigurationSource.systemRequired,
        navigationOrder: def?.defaultOrder ?? 999,
      );
    }
    // Optional defaults: enabled initially, but ownerSelected so disableable.
    for (final id in _defaultOptionalModules) {
      final def = ErpModuleRegistry.tryGet(id);
      _selections[id] = BlueprintModuleSelection(
        moduleId: id,
        enabled: true,
        source: ModuleConfigurationSource.ownerSelected,
        navigationOrder: def?.defaultOrder ?? 999,
      );
    }
  }

  void _ensureHardRequired() {
    for (final id in _hardRequiredModules) {
      if (!_selections.containsKey(id) || !(_selections[id]!.enabled)) {
        final def = ErpModuleRegistry.tryGet(id);
        _selections[id] = BlueprintModuleSelection(
          moduleId: id,
          enabled: true,
          required: true,
          source: ModuleConfigurationSource.systemRequired,
          navigationOrder: def?.defaultOrder ?? 999,
        );
      }
    }
  }

  /// Resolves dependencies for all currently enabled modules.
  /// Returns the set of module IDs that were auto-added.
  Set<ErpModuleId> _resolveAndAddDependencies() {
    final enabledIds = _selections.entries
        .where((e) => e.value.enabled)
        .map((e) => e.key)
        .toSet();

    final result = _resolver.resolve(enabledIds);
    final added = <ErpModuleId>{};

    for (final depId in result.addedDependencies) {
      if (!_selections.containsKey(depId) || !_selections[depId]!.enabled) {
        final def = ErpModuleRegistry.tryGet(depId);
        _selections[depId] = BlueprintModuleSelection(
          moduleId: depId,
          enabled: true,
          required: true,
          source: ModuleConfigurationSource.dependency,
          navigationOrder: def?.defaultOrder ?? 999,
        );
        added.add(depId);
      }
    }

    return added;
  }

  /// After a module is disabled, remove dependency-sourced modules
  /// that are no longer required by any remaining enabled module.
  /// Only cleans modules with source == dependency.
  /// Handles nested chains by iterating until stable.
  void _cleanOrphanedDependencies() {
    bool changed = true;
    // Iterate until no more orphans are found (handles nested chains).
    while (changed) {
      changed = false;
      // Collect all required dependency IDs from currently enabled modules.
      final neededDeps = <ErpModuleId>{};
      for (final entry in _selections.entries) {
        if (!entry.value.enabled) continue;
        final def = ErpModuleRegistry.tryGet(entry.key);
        if (def != null) {
          neededDeps.addAll(def.dependencies);
        }
      }

      // Find dependency-sourced modules that are no longer needed.
      final toDisable = <ErpModuleId>[];
      for (final entry in _selections.entries) {
        if (!entry.value.enabled) continue;
        if (entry.value.source != ModuleConfigurationSource.dependency) continue;
        if (_hardRequiredModules.contains(entry.key)) continue;
        if (!neededDeps.contains(entry.key)) {
          toDisable.add(entry.key);
        }
      }

      for (final id in toDisable) {
        final existing = _selections[id]!;
        _selections[id] = BlueprintModuleSelection(
          moduleId: id,
          enabled: false,
          source: ModuleConfigurationSource.manuallyDisabled,
          settings: existing.settings,
          navigationOrder: existing.navigationOrder,
        );
        changed = true;
      }
    }
  }

  /// Whether [newSource] is a stronger explicit selection than [current].
  /// dependency is the weakest; ownerSelected/aiRecommended are stronger.
  static bool _shouldUpgradeSource(
    ModuleConfigurationSource current,
    ModuleConfigurationSource newSource,
  ) {
    const priority = {
      ModuleConfigurationSource.dependency: 0,
      ModuleConfigurationSource.manuallyDisabled: 0,
      ModuleConfigurationSource.ownerSelected: 1,
      ModuleConfigurationSource.aiRecommended: 1,
      ModuleConfigurationSource.systemRequired: 2,
    };
    return (priority[newSource] ?? 0) > (priority[current] ?? 0);
  }
}
