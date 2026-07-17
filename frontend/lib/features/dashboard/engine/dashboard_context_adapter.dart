// SmartBiz AI — Dashboard Context Adapter.
//
// Pure adapter that converts app state into the normalized input
// required by DynamicDashboardState. No widgets, no Provider, no
// BuildContext, no notifyListeners.
//
// Permissions come exclusively from the backend session. When no
// session is available the permission set is empty — no mock role
// templates are used.
import '../../../core/state/app_state.dart';
import '../models/dashboard_config_models.dart';

// ═══════════════════════════════════════════════════════════
//  Immutable context model
// ═══════════════════════════════════════════════════════════

class DashboardEmployeeContext {
  final String workspaceId;
  final String workspaceName;
  final String primaryRoleId;
  final List<String> extraRoleIds;
  final Set<String> effectivePermissions;
  final Set<String> enabledModules;
  final String roleName;
  final DashboardTemplate? templateOverride;
  final DashboardConfiguration? workspaceRoleConfig;
  final DashboardConfiguration? employeeOverride;

  const DashboardEmployeeContext({
    required this.workspaceId,
    required this.workspaceName,
    required this.primaryRoleId,
    this.extraRoleIds = const [],
    this.effectivePermissions = const {},
    this.enabledModules = const {},
    this.roleName = '',
    this.templateOverride,
    this.workspaceRoleConfig,
    this.employeeOverride,
  });
}

// ═══════════════════════════════════════════════════════════
//  Adapter
// ═══════════════════════════════════════════════════════════

class DashboardContextAdapter {
  const DashboardContextAdapter();

  /// Builds a normalized DashboardEmployeeContext from current app state.
  ///
  /// Permissions come exclusively from the backend session.
  /// When no session is available, the permission set is empty.
  DashboardEmployeeContext build({
    required AppState appState,
  }) {
    // ── 1. Primary role ID ────────────────────────────────
    final primaryRoleId = _appRoleToRoleId(appState.currentRole);

    // ── 2. Effective permissions — backend only ───────────
    final session = appState.lastSession;
    final Set<String> effectivePerms;
    if (session?.activeWorkspace != null) {
      effectivePerms = Set<String>.from(session!.activeWorkspace!.permissions);
    } else {
      // No backend session — empty set; no mock permissions.
      effectivePerms = const {};
    }

    // ── 3. Enabled modules ───────────────────────────────
    final enabledModules = _resolveEnabledModules(appState);

    // ── 4. Role display name ─────────────────────────────
    final roleName = appState.displayRoleName(appState.uiLanguage);

    return DashboardEmployeeContext(
      workspaceId: appState.currentWorkspace.id,
      workspaceName: appState.currentWorkspace.name,
      primaryRoleId: primaryRoleId,
      extraRoleIds: const [],
      effectivePermissions: Set.unmodifiable(effectivePerms),
      enabledModules: Set.unmodifiable(enabledModules),
      roleName: roleName,
      templateOverride: null, // future: from backend role config
      workspaceRoleConfig: null, // future: from workspace settings
      employeeOverride: null, // future: from employee profile
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  AppRole → role ID mapping
  // ═══════════════════════════════════════════════════════════

  static String _appRoleToRoleId(AppRole role) => switch (role) {
    AppRole.owner => 'sys_owner',
    AppRole.cashier => 'sys_cashier',
    AppRole.warehouse => 'sys_warehouse',
    AppRole.accountant => 'sys_accountant',
    AppRole.employee => 'sys_employee',
    AppRole.superAdmin => 'sys_owner',
  };

  // ═══════════════════════════════════════════════════════════
  //  Enabled modules — derived from active workspace session
  // ═══════════════════════════════════════════════════════════

  /// Returns the set of currently enabled workspace modules.
  ///
  /// Uses only the backend session's activeWorkspace.enabledModules.
  /// Returns an empty set when the session hasn't loaded yet (cold
  /// start / F5 refresh). The DashboardCoordinator overrides this
  /// with WorkspaceModuleState as the authoritative source once
  /// the module state has been initialized.
  static Set<String> _resolveEnabledModules(AppState appState) {
    final session = appState.lastSession;
    final backendModules = session?.activeWorkspace?.enabledModules;

    if (backendModules == null || backendModules.isEmpty) {
      // Session not yet available — return empty set.
      // DashboardCoordinator will reconcile once WorkspaceModuleState loads.
      return const {};
    }

    return Set<String>.from(backendModules);
  }
}
