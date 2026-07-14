// SmartBiz AI — Blueprint Navigation Coordinator (Phase 17).
//
// StatefulWidget that connects WorkspaceModuleState, AppState,
// RolesState, OrgState → BlueprintNavigationController.
//
// Mirrors the DashboardCoordinator pattern:
//   - explicit listeners for RolesState, OrgState, WorkspaceModuleState
//   - context.select for AppState (role, workspace, language)
//   - post-frame sync to avoid build-loop violations
//   - mounted checks everywhere
//
// Renders its child unchanged.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/employees/roles_state.dart';
import '../../features/employees/org_state.dart';
import '../../features/dashboard/engine/dashboard_context_adapter.dart';
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
  static const _adapter = DashboardContextAdapter();

  RolesState? _rolesState;
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
    final newRoles = context.read<RolesState>();
    final newOrg = context.read<OrgState>();
    final newModules = context.read<WorkspaceModuleState>();

    if (identical(_rolesState, newRoles) &&
        identical(_orgState, newOrg) &&
        identical(_moduleState, newModules)) {
      return; // already listening
    }

    // Detach old listeners.
    _rolesState?.removeListener(_onDependencyChanged);
    _orgState?.removeListener(_onDependencyChanged);
    _moduleState?.removeListener(_onDependencyChanged);

    // Attach new listeners.
    _rolesState = newRoles;
    _orgState = newOrg;
    _moduleState = newModules;
    _rolesState!.addListener(_onDependencyChanged);
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
    final rolesState = _rolesState;
    final orgState = _orgState;
    final modules = _moduleState;
    if (rolesState == null || orgState == null || modules == null) return;

    final navCtrl = context.read<BlueprintNavigationController>();

    // Attach module state (no-op if already same instance).
    // On first attachment the controller defaults to advanced mode;
    // after that, the user's mode selection is preserved across syncs.
    navCtrl.attachModuleState(modules);

    // Build the employee context to get effective permissions.
    final empCtx = _adapter.build(
      appState: appState,
      rolesState: rolesState,
      orgState: orgState,
    );

    // Determine the effective permission set.
    // When a real backend session exists, its permissions are the sole
    // authority — the backend RBAC system is the source of truth.
    // Frontend-computed permissions (from mock role templates) are only
    // used as a fallback when no backend session is available.
    final Set<String> effectivePermissions;
    final session = appState.lastSession;
    if (session?.activeWorkspace != null) {
      // Backend is authoritative — use its permissions exclusively.
      effectivePermissions = Set<String>.from(session!.activeWorkspace!.permissions);
    } else {
      // No backend session — fall back to frontend-computed permissions.
      effectivePermissions = empCtx.effectivePermissions;
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
    _rolesState?.removeListener(_onDependencyChanged);
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
