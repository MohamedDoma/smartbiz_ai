// SmartBiz AI — Dashboard Context Adapter (Phase 16.3).
//
// Pure adapter that converts app state into the normalized input
// required by DynamicDashboardState. No widgets, no Provider, no
// BuildContext, no notifyListeners.
import '../../employees/models/role_models.dart';
import '../../employees/org_state.dart';
import '../../employees/roles_state.dart';
import '../../../core/state/app_state.dart';
// erp_module_registry import removed — adapter must not mock modules from registry.
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
  /// [employeeId] — if null, uses the current user as the employee.
  DashboardEmployeeContext build({
    required AppState appState,
    required RolesState rolesState,
    required OrgState orgState,
    String? employeeId,
  }) {
    final empId = employeeId ?? appState.currentUser.id;

    // ── 1. Resolve assignment ─────────────────────────────
    final assignment = orgState.getAssignment(empId);

    // ── 2. Primary role ───────────────────────────────────
    final primaryRoleId = assignment?.primaryRoleId ?? _appRoleToRoleId(appState.currentRole);

    // ── 3. Extra roles (deduplicated, excluding primary) ──
    final extraRoleIds = <String>[];
    if (assignment != null) {
      for (final id in assignment.extraRoleIds) {
        if (id != primaryRoleId && !extraRoleIds.contains(id)) {
          extraRoleIds.add(id);
        }
      }
    }

    // ── 4. Build roles map for permission computation ─────
    final rolesMap = <String, CustomRole>{};
    for (final r in rolesState.allRoles) {
      rolesMap[r.id] = r;
    }
    // Also include templates that may be referenced by ID
    for (final t in RoleTemplates.allTemplates()) {
      rolesMap.putIfAbsent(t.id, () => t);
    }

    // ── 5. Effective permissions ──────────────────────────
    final effectivePerms = _computeEffectivePermissions(
      primaryRoleId: primaryRoleId,
      extraRoleIds: extraRoleIds,
      rolesMap: rolesMap,
      orgState: orgState,
      empId: empId,
    );

    // ── 6. Enabled modules ───────────────────────────────
    final enabledModules = _resolveEnabledModules(appState);

    // ── 7. Role display name ─────────────────────────────
    final roleName = rolesMap[primaryRoleId]?.name ?? orgState.roleLabel(primaryRoleId);

    // ── 8. Template override (custom roles override ID-based lookup) ──
    final primaryRole = rolesMap[primaryRoleId];
    final DashboardTemplate? tplOverride =
        (primaryRole != null && primaryRole.type == RoleType.custom)
            ? primaryRole.dashboardTemplate
            : null;

    return DashboardEmployeeContext(
      workspaceId: appState.currentWorkspace.id,
      workspaceName: appState.currentWorkspace.name,
      primaryRoleId: primaryRoleId,
      extraRoleIds: List.unmodifiable(extraRoleIds),
      effectivePermissions: Set.unmodifiable(effectivePerms),
      enabledModules: Set.unmodifiable(enabledModules),
      roleName: roleName,
      templateOverride: tplOverride,
      workspaceRoleConfig: null, // future: from workspace settings
      employeeOverride: null,    // future: from employee profile
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  AppRole → role ID mapping
  // ═══════════════════════════════════════════════════════════

  static String _appRoleToRoleId(AppRole role) => switch (role) {
    AppRole.owner      => 'sys_owner',
    AppRole.cashier    => 'sys_cashier',
    AppRole.warehouse  => 'sys_warehouse',
    AppRole.accountant => 'sys_accountant',
    AppRole.employee   => 'sys_employee',
    AppRole.superAdmin => 'sys_owner', // super admin uses owner perms
  };

  // ═══════════════════════════════════════════════════════════
  //  Effective permissions computation
  // ═══════════════════════════════════════════════════════════

  static Set<String> _computeEffectivePermissions({
    required String primaryRoleId,
    required List<String> extraRoleIds,
    required Map<String, CustomRole> rolesMap,
    required OrgState orgState,
    required String empId,
  }) {
    final perms = <String>{};

    void mergeRole(String roleId) {
      final role = rolesMap[roleId];
      if (role == null) return;
      for (final entry in role.permissions.entries) {
        final moduleName = _moduleToKey(entry.key);
        for (final action in entry.value.enabled) {
          perms.add('$moduleName.${action.name}');
        }
      }
    }

    // Primary role
    mergeRole(primaryRoleId);

    // Extra roles
    for (final id in extraRoleIds) {
      mergeRole(id);
    }

    // Manual extra permissions from assignment (if any)
    // Currently EmployeeAssignment.extraPermissions is private (_ExtraPerm)
    // so we cannot access it directly. When the backend API provides
    // explicit grant/deny overrides, they will be merged here.

    return perms;
  }

  /// Maps AppModule enum to the string key used in dashboard configs.
  static String _moduleToKey(AppModule m) => switch (m) {
    AppModule.dashboard  => 'dashboard',
    AppModule.aiChat     => 'aiChat',
    AppModule.aiAdvisor  => 'aiAdvisor',
    AppModule.customers  => 'customers',
    AppModule.invoices   => 'invoices',
    AppModule.products   => 'products',
    AppModule.inventory  => 'inventory',
    AppModule.accounting => 'accounting',
    AppModule.reports    => 'reports',
    AppModule.employees  => 'employees',
    AppModule.roles      => 'roles',
    AppModule.settings   => 'settings',
    AppModule.billing    => 'billing',
    AppModule.payments   => 'payments',
    AppModule.pos        => 'pos',
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

