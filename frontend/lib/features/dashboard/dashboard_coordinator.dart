// SmartBiz AI — Dashboard Coordinator.
//
// Connects AppState, OrgState → DashboardContextAdapter
// → DynamicDashboardState → DynamicDashboardScreen.
// Only place where app state is wired to the dashboard engine.
//
// Reactivity: listens to OrgState via explicit listeners,
// and subscribes to AppState via context.select for role/workspace/lang.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/state/app_state.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/modules/workspace_module_state.dart';
import '../../core/modules/erp_module_models.dart';
import '../../core/modules/workspace_blueprint_profile_resolver.dart';
import '../employees/org_state.dart';
import 'dynamic_dashboard_state.dart';
import 'dynamic_dashboard_screen.dart';
import 'engine/dashboard_context_adapter.dart';
import 'engine/dashboard_resolver.dart' show templateForRole;

class DashboardCoordinator extends StatefulWidget {
  const DashboardCoordinator({super.key});

  @override
  State<DashboardCoordinator> createState() => _DashboardCoordinatorState();
}

class _DashboardCoordinatorState extends State<DashboardCoordinator> {
  static const _adapter = DashboardContextAdapter();

  OrgState? _orgState;
  WorkspaceModuleState? _moduleState;
  bool _callbackScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachListeners();
    _scheduleSync();
  }

  /// Attach explicit listeners to OrgState and WorkspaceModuleState.
  void _attachListeners() {
    final newOrg = context.read<OrgState>();
    final newModules = context.read<WorkspaceModuleState>();

    if (identical(_orgState, newOrg) &&
        identical(_moduleState, newModules)) {
      return; // already listening
    }

    // Detach old
    _orgState?.removeListener(_onStateChanged);
    _moduleState?.removeListener(_onStateChanged);

    // Attach new
    _orgState = newOrg;
    _moduleState = newModules;
    _orgState!.addListener(_onStateChanged);
    _moduleState!.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (!mounted) return;
    _scheduleSync();
  }

  /// Schedules a single post-frame sync. Prevents duplicate callbacks.
  void _scheduleSync() {
    if (_callbackScheduled) return;
    _callbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callbackScheduled = false;
      if (!mounted) return;
      _performSync();
    });
  }

  void _performSync() {
    final appState = context.read<AppState>();
    final moduleState = _moduleState;

    final dashState = context.read<DynamicDashboardState>();

    final ctx = _adapter.build(
      appState: appState,
    );

    // ── Frontend blueprint profile application ──────────────
    // When no real AI/backend blueprint has been applied, detect the
    // current role's dashboard template and apply the matching module
    // profile. When already applied, reconcile to pick up any newly
    // added profile modules (e.g. payments added after initial apply).
    // Temporary: replaced by AI/backend blueprint config in the future.
    if (moduleState != null) {
      final template = ctx.templateOverride ?? templateForRole(ctx.primaryRoleId);
      final profile = WorkspaceBlueprintProfileResolver.forTemplate(template);
      if (!moduleState.blueprintApplied) {
        moduleState.applyFrontendBlueprintProfile(profile.modules);
      } else {
        moduleState.reconcileFrontendBlueprintProfile(profile.modules);
      }

      // ── Backend enabled_modules bridge ─────────────────────
      // The backend session carries the workspace's enabled_modules
      // from business template feature flags. Map these backend keys
      // to ErpModuleId values and reconcile them into module state
      // so that modules like pipelines (enabled via 'leads' or
      // 'vehicle_sales' feature flags) are correctly activated.
      final session = appState.lastSession;
      if (session?.activeWorkspace != null) {
        final backendModules = session!.activeWorkspace!.enabledModules;
        if (backendModules.isNotEmpty) {
          final mappedIds = _mapBackendModuleKeys(backendModules);
          if (mappedIds.isNotEmpty) {
            moduleState.reconcileFrontendBlueprintProfile(mappedIds);
          }
        }
      }
    }

    // Enabled modules: use WorkspaceModuleState as the single source of
    // truth (same as router guard). Uses ErpModuleId.name (camelCase)
    // which _toErpModuleIdSet handles via enum-name fallback.
    // Future: replaced by backend/AI blueprint.
    final realEnabledModules = moduleState != null
        ? moduleState.enabledModuleIds.map((id) => id.name).toSet()
        : ctx.enabledModules; // fallback to adapter if state unavailable

    // DynamicDashboardState.updateContext compares all inputs internally
    // and is a no-op when nothing changed — no rebuild loop possible.
    dashState.updateContext(
      primaryRoleId: ctx.primaryRoleId,
      extraRoleIds: ctx.extraRoleIds,
      effectivePermissions: ctx.effectivePermissions,
      enabledModules: realEnabledModules,
      templateOverride: ctx.templateOverride,
      workspaceRoleConfig: ctx.workspaceRoleConfig,
      employeeOverride: ctx.employeeOverride,
    );
  }

  @override
  void dispose() {
    _orgState?.removeListener(_onStateChanged);
    _moduleState?.removeListener(_onStateChanged);
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  //  Backend feature key → ErpModuleId mapping
  // ═══════════════════════════════════════════════════════════

  /// Maps backend workspace feature flag keys to ErpModuleId values.
  ///
  /// Backend keys come from business_template_modules.module_key and are
  /// stored as workspace_feature_flags. These don't always match the
  /// ErpModuleId enum names, so we maintain a manual alias map for
  /// known mismatches.
  static Set<ErpModuleId> _mapBackendModuleKeys(List<String> keys) {
    final result = <ErpModuleId>{};
    for (final key in keys) {
      final mapped = _backendKeyToModuleId(key);
      if (mapped != null) result.add(mapped);
    }
    return result;
  }

  /// Maps a single backend feature key to an ErpModuleId.
  /// Returns null for unrecognized keys (industry-specific modules
  /// without frontend implementations).
  static ErpModuleId? _backendKeyToModuleId(String key) {
    // Direct enum name match (most common case).
    for (final id in ErpModuleId.values) {
      if (id.name == key) return id;
    }
    // Backend-specific aliases that don't match enum names.
    return switch (key) {
      'ai'            => ErpModuleId.aiChat,
      'finance'       => ErpModuleId.accounting,
      'leads'         => ErpModuleId.pipelines, // leads/CRM feature → pipelines module
      'vehicle_sales' => ErpModuleId.pipelines, // vehicle sales pipeline
      'spare_parts'   => ErpModuleId.products,  // spare parts → products
      'jobs'          => ErpModuleId.serviceJobs,
      'menu'          => ErpModuleId.menuManagement,
      'tables'        => ErpModuleId.restaurantTables,
      'orders'        => ErpModuleId.pos,       // order-taking → POS
      'vehicles'      => null,                  // no frontend implementation yet
      'parts_inventory' => ErpModuleId.inventory,
      _               => null,                  // unknown key — skip silently
    };
  }

  @override
  Widget build(BuildContext context) {
    // ── Narrow AppState selectors ─────────────────────────
    // These cause a rebuild ONLY when role, workspace, or language changes.
    // The rebuild triggers didChangeDependencies → _scheduleSync.
    context.select<AppState, AppRole>((s) => s.currentRole);
    context.select<AppState, String>((s) => s.currentWorkspace.id);
    context.select<AppState, AppLanguage>((s) => s.uiLanguage);

    // ── Read resolved dashboard config ────────────────────
    final dashState = context.watch<DynamicDashboardState>();
    final config = dashState.configuration;

    // ── Derive display values ─────────────────────────────
    final wsName = context.select<AppState, String>((s) => s.currentWorkspace.name);
    final roleName = context.select<AppState, String>(
      (s) => s.displayRoleName(s.uiLanguage),
    );

    // ── Loading state (first frame only) ──────────────────
    if (!dashState.hasContent) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return DynamicDashboardScreen(
      configuration: config,
      workspaceName: wsName,
      roleName: roleName,
    );
  }
}
