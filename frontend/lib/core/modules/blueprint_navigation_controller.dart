// SmartBiz AI — Blueprint Navigation Controller (Phase 17).
//
// Lightweight ChangeNotifier that combines WorkspaceModuleState,
// effective permissions, and NavigationMode to produce a resolved,
// adapter-ready navigation list for the sidebar.
//
// Does not perform navigation, does not use BuildContext.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../navigation/nav_model.dart';
import 'module_navigation_resolver.dart';
import 'module_navigation_adapter.dart';
import 'workspace_module_state.dart';

class BlueprintNavigationController extends ChangeNotifier {
  final ModuleNavigationResolver _resolver;
  final ModuleNavigationAdapter _adapter;

  WorkspaceModuleState? _moduleState;
  Set<String> _effectivePermissions = const {};
  NavigationMode _mode = NavigationMode.basic;

  /// Cached resolved output — recomputed only when inputs change.
  List<NavItem> _cachedNavItems = const [];
  List<ResolvedNavItem> _cachedResolved = const [];

  /// Hash of last computation inputs for change detection.
  int _lastInputHash = 0;

  BlueprintNavigationController({
    ModuleNavigationResolver resolver = const ModuleNavigationResolver(),
    ModuleNavigationAdapter adapter = const ModuleNavigationAdapter(),
  })  : _resolver = resolver,
        _adapter = adapter {
    _loadSavedMode();
  }

  // ── Persistence ────────────────────────────────────────────
  static const _storageKey = 'smartbiz.navigation_mode';

  Future<void> _loadSavedMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);
      if (saved == 'basic') {
        _mode = NavigationMode.basic;
      } else if (saved == 'advanced') {
        _mode = NavigationMode.advanced;
      }
      // else: keep default (advanced)
      _recompute();
    } catch (_) {
      // Storage unavailable — keep default mode.
    }
  }

  Future<void> _saveMode(NavigationMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {
      // Storage unavailable — mode still works in-memory.
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Public Getters
  // ═══════════════════════════════════════════════════════════

  /// Resolved navigation items in legacy NavItem format.
  /// Empty list if navigation is not ready.
  List<NavItem> get navItems => _cachedNavItems;

  /// Resolved items in the richer ResolvedNavItem format.
  List<ResolvedNavItem> get resolvedItems => _cachedResolved;

  /// Current navigation mode.
  NavigationMode get mode => _mode;

  /// Whether the controller has a connected WorkspaceModuleState
  /// with at least one enabled module.
  bool get isReady => _moduleState != null && _cachedResolved.isNotEmpty;

  /// Whether the sidebar should fall back to the legacy hardcoded
  /// navigation. True when no module state is connected or when the
  /// resolved list is empty (e.g. before a blueprint is applied).
  bool get useFallbackNavigation => !isReady;

  /// The effective permission set currently applied.
  Set<String> get effectivePermissions =>
      Set.unmodifiable(_effectivePermissions);

  /// Whether the workspace has enabled modules that produce extra
  /// navigation items exclusive to Advanced mode. Used by the sidebar
  /// to show an honest empty-state when Advanced adds nothing.
  ///
  /// Computes by comparing the current resolved items' advancedOnly
  /// flag rather than re-resolving, keeping it O(n) on the cached list.
  bool get hasAdvancedOnlyItems {
    if (_moduleState == null) return false;
    return _cachedResolved.any((item) => item.isAdvanced && !item.isBasic);
  }

  /// Diagnostic: returns a map of resolved nav item IDs, their routes,
  /// and the current effective permissions. Does not print or log.
  Map<String, dynamic> debugVisibleNavIds() => {
    'mode': _mode.name,
    'isReady': isReady,
    'useFallback': useFallbackNavigation,
    'navIds': _cachedResolved.map((r) => r.navItemId).toList(),
    'routes': _cachedResolved.map((r) => r.route).toList(),
    'permCount': _effectivePermissions.length,
    'perms': _effectivePermissions.toList()..sort(),
  };

  // ═══════════════════════════════════════════════════════════
  //  Mutation Methods
  // ═══════════════════════════════════════════════════════════

  /// Attach to a WorkspaceModuleState and listen for changes.
  /// Replaces any previous subscription.
  void attachModuleState(WorkspaceModuleState state) {
    if (_moduleState == state) return;
    _moduleState?.removeListener(_onModuleStateChanged);
    _moduleState = state;
    _moduleState!.addListener(_onModuleStateChanged);
    _recompute();
  }

  /// Detach from the current WorkspaceModuleState.
  void detachModuleState() {
    _moduleState?.removeListener(_onModuleStateChanged);
    _moduleState = null;
    _invalidate();
  }

  /// Update the effective permission keys for the current user/role.
  void updatePermissions(Set<String> permissions) {
    if (setEquals(_effectivePermissions, permissions)) return;
    _effectivePermissions = Set.of(permissions);
    _recompute();
  }

  /// Switch between Basic and Advanced navigation mode.
  /// Persists the choice to local storage.
  void setMode(NavigationMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    _saveMode(newMode);
    _recompute();
  }

  /// Force a recomputation from the current WorkspaceModuleState.
  void refresh() => _recompute();

  /// Reset to an empty, disconnected state.
  void reset() {
    detachModuleState();
    _effectivePermissions = const {};
    _mode = NavigationMode.basic;
    // _invalidate already called by detachModuleState
  }

  @override
  void dispose() {
    _moduleState?.removeListener(_onModuleStateChanged);
    _moduleState = null;
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  Internal
  // ═══════════════════════════════════════════════════════════

  void _onModuleStateChanged() => _recompute();

  void _recompute() {
    final state = _moduleState;
    if (state == null) {
      _invalidate();
      return;
    }

    // Build a hash of the current inputs to skip redundant recomputation.
    final enabledIds = state.enabledModuleIds.toSet();
    final inputHash = Object.hashAll([
      Object.hashAllUnordered(enabledIds),
      Object.hashAllUnordered(_effectivePermissions),
      _mode,
    ]);

    if (inputHash == _lastInputHash) return;
    _lastInputHash = inputHash;

    final resolved = _resolver.resolve(
      enabledModules: enabledIds,
      effectivePermissions: _effectivePermissions,
      mode: _mode,
    );

    _cachedResolved = resolved;
    _cachedNavItems = _adapter.toNavItems(resolved);

    notifyListeners();
  }

  void _invalidate() {
    if (_cachedResolved.isEmpty && _lastInputHash == 0) return;
    _cachedResolved = const [];
    _cachedNavItems = const [];
    _lastInputHash = 0;
    notifyListeners();
  }
}
