// SmartBiz AI — Blueprint Navigation Coordinator.
//
// StatefulWidget that connects WorkspaceModuleState, AppState,
// OrgState → BlueprintNavigationController.
//
// Mirrors the DashboardCoordinator pattern:
//   - explicit listeners for OrgState, WorkspaceModuleState
//   - context.select for AppState (role, workspace, language)
//   - post-frame sync to avoid build-loop violations
//   - mounted checks everywhere
//
// Renders its child unchanged.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/employees/org_state.dart';
import 'workspace_module_state.dart';
import 'blueprint_navigation_controller.dart';

class BlueprintNavigationCoordinator extends StatefulWidget {
  final Widget child;
  const BlueprintNavigationCoordinator({super.key, required this.child});

  @override
  State<BlueprintNavigationCoordinator> createState() =>
      _BlueprintNavigationCoordinatorState();
}

class _BlueprintNavigationCoordinatorState
    extends State<BlueprintNavigationCoordinator> {
  OrgState? _orgState;
  WorkspaceModuleState? _moduleState;
  bool _syncScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachListeners();
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════
  //  Listener Attachment
  // ═══════════════════════════════════════════════════════════

  void _attachListeners() {
    final newOrg = context.read<OrgState>();
    final newModules = context.read<WorkspaceModuleState>();

    if (identical(_orgState, newOrg) &&
        identical(_moduleState, newModules)) {
      return; // already listening
    }

    // Detach old listeners.
    _orgState?.removeListener(_onDependencyChanged);
    _moduleState?.removeListener(_onDependencyChanged);

    // Attach new listeners.
    _orgState = newOrg;
    _moduleState = newModules;
    _orgState!.addListener(_onDependencyChanged);
    _moduleState!.addListener(_onDependencyChanged);

    // NOTE: We do NOT call navCtrl.attachModuleState or setMode here
    // because we are inside didChangeDependencies (during build).
    // Those calls trigger notifyListeners synchronously, which would
    // cause "setState during build" exceptions. They are deferred
    // to _performSync via addPostFrameCallback.
  }

  void _onDependencyChanged() {
    if (!mounted) return;
    _scheduleSync();
  }

  // ═══════════════════════════════════════════════════════════
  //  Post-Frame Sync
  // ═══════════════════════════════════════════════════════════

  /// Schedules a single post-frame sync. Prevents duplicate callbacks.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _performSync();
    });
  }

  void _performSync() {
    final appState = context.read<AppState>();
    final modules = _moduleState;
    if (modules == null) return;

    final navCtrl = context.read<BlueprintNavigationController>();

    // Attach module state (no-op if already same instance).
    // On first attachment the controller defaults to advanced mode;
    // after that, the user's mode selection is preserved across syncs.
    navCtrl.attachModuleState(modules);

    // Determine the effective permission set.
    // When a real backend session exists, its permissions are the sole
    // authority — the backend RBAC system is the source of truth.
    // When no backend session is available, use an empty set — no mock
    // role permissions are used.
    final Set<String> effectivePermissions;
    final session = appState.lastSession;
    if (session?.activeWorkspace != null) {
      effectivePermissions = Set<String>.from(session!.activeWorkspace!.permissions);
    } else {
      effectivePermissions = const {};
    }

    // Push permissions to the navigation controller.
    // The controller internally skips if permissions are unchanged.
    navCtrl.updatePermissions(effectivePermissions);
  }

  // ═══════════════════════════════════════════════════════════
  //  Lifecycle
  // ═══════════════════════════════════════════════════════════

  @override
  void dispose() {
    _orgState?.removeListener(_onDependencyChanged);
    _moduleState?.removeListener(_onDependencyChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Narrow selectors: rebuild only when role, workspace, or language
    // changes. The rebuild triggers didChangeDependencies → _scheduleSync.
    context.select<AppState, AppRole>((s) => s.currentRole);
    context.select<AppState, String>((s) => s.currentWorkspace.id);
    context.select<AppState, AppLanguage>((s) => s.uiLanguage);

    return widget.child;
  }
}
