// SmartBiz AI — ERP Module Models (Phase 17).
//
// Universal, data-driven module registry types.
// Pure Dart — no Flutter, no Provider, no BuildContext.
// These models describe what every ERP module IS, not how it looks.
import '../../features/dashboard/models/dashboard_config_models.dart';

// ═══════════════════════════════════════════════════════════
//  Canonical Module Identifier
// ═══════════════════════════════════════════════════════════

/// Every module in the SmartBiz AI universe.
/// New modules are added here; no hardcoded industry switches needed.
enum ErpModuleId {
  // ── Core ───────────────────────────────────────────────
  dashboard,
  aiChat,
  aiAdvisor,
  notifications,
  settings,

  // ── Sales & CRM ────────────────────────────────────────
  customers,
  leads,
  opportunities,
  quotations,
  invoices,
  payments,
  pos,
  recurringBilling,
  pipelines,
  commissions,

  // ── Products & Operations ──────────────────────────────
  products,
  inventory,
  warehouses,
  warehouseTransfers,
  suppliers,
  procurement,
  purchaseOrders,

  // ── Finance ────────────────────────────────────────────
  accounting,
  expenses,
  reports,
  assets,
  budgets,

  // ── People & Organization ──────────────────────────────
  employees,
  roles,
  departments,
  teams,
  attendance,
  leave,
  payroll,
  approvals,

  // ── Service & Project Work ─────────────────────────────
  projects,
  tasks,
  timesheets,
  bookings,
  appointments,
  serviceJobs,
  support,

  // ── Industry Building Blocks ───────────────────────────
  restaurantTables,
  restaurantOrders,
  kitchenDisplay,
  menuManagement,
  ingredients,
  manufacturing,
  bom,
  productionOrders,
  delivery,
  fleet,
  branches,
}

// ═══════════════════════════════════════════════════════════
//  Module Category
// ═══════════════════════════════════════════════════════════

enum ModuleCategory {
  core,
  sales,
  crm,
  inventory,
  finance,
  people,
  projects,
  service,
  restaurant,
  manufacturing,
  logistics,
  platform;

  String get labelKey => 'mcat_$name';
}

// ═══════════════════════════════════════════════════════════
//  Module Maturity
// ═══════════════════════════════════════════════════════════

/// Frontend implementation state — must be truthful.
enum ModuleMaturity {
  /// Fully functional screens and state management.
  implemented,
  /// Some screens exist but incomplete features.
  partial,
  /// Blueprint/metadata only, no screens.
  blueprintOnly,
  /// On the roadmap, no code yet.
  planned,
  /// Not available in the system.
  unavailable;

  String get labelKey => 'mmat_$name';
}

// ═══════════════════════════════════════════════════════════
//  Module Visibility
// ═══════════════════════════════════════════════════════════

/// Determines Basic vs Advanced mode filtering.
enum ModuleVisibility {
  /// Shown in Basic and Advanced modes.
  both,
  /// Only shown in Basic mode (simple).
  basicOnly,
  /// Only shown in Advanced mode (power users).
  advancedOnly,
  /// Hidden unless explicitly enabled by blueprint/admin.
  hiddenUnlessEnabled;

  String get labelKey => 'mvis_$name';
}

// ═══════════════════════════════════════════════════════════
//  Module Definition
// ═══════════════════════════════════════════════════════════

/// Immutable description of an ERP module.
/// This is the single source of truth for what a module IS.
class ErpModuleDefinition {
  /// Canonical module identifier.
  final ErpModuleId id;

  /// API identifier for backend communication (e.g. "invoices", "pos").
  final String apiId;

  /// Localization key for the module display name.
  final String labelKey;

  /// Localization key for the module description.
  final String descriptionKey;

  /// Icon identifier (Material icon name string).
  final String iconId;

  /// Functional category.
  final ModuleCategory category;

  /// Current frontend implementation maturity.
  final ModuleMaturity maturity;

  /// Basic/Advanced visibility classification.
  final ModuleVisibility visibility;

  /// Registered route paths (e.g. ['/invoices', '/invoices/create']).
  /// Empty for unimplemented modules.
  final List<String> routePaths;

  /// Navigation sidebar item IDs that map to this module.
  final List<String> navigationItemIds;

  /// Permission keys provided by this module.
  final Set<String> permissionKeys;

  /// Explicit permission keys that gate sidebar navigation visibility.
  /// When non-empty, the user must hold at least one of these keys for the
  /// module's nav item to appear. When empty, the module is always visible
  /// (no permission gate on navigation). This replaces the old heuristic
  /// that searched for *.view / *.list suffixes in permissionKeys.
  final Set<String> navigationPermissionKeys;

  /// Modules that MUST be enabled for this module to function.
  final Set<ErpModuleId> dependencies;

  /// Modules that enhance this module but are not required.
  final Set<ErpModuleId> optionalDependencies;

  /// Dashboard templates that can display this module's widgets.
  final Set<DashboardTemplate> compatibleDashboardTemplates;

  /// Widget IDs this module can contribute to dashboards.
  final Set<String> supportedWidgetIds;

  /// Quick action IDs this module can contribute to dashboards.
  final Set<String> supportedQuickActionIds;

  /// Whether this module has a Basic mode variant.
  final bool supportsBasicMode;

  /// Whether this module has an Advanced mode variant.
  final bool supportsAdvancedMode;

  /// Default sort order in module lists / navigation.
  final int defaultOrder;

  const ErpModuleDefinition({
    required this.id,
    required this.apiId,
    required this.labelKey,
    required this.descriptionKey,
    required this.iconId,
    required this.category,
    required this.maturity,
    required this.visibility,
    this.routePaths = const [],
    this.navigationItemIds = const [],
    this.permissionKeys = const {},
    this.navigationPermissionKeys = const {},
    this.dependencies = const {},
    this.optionalDependencies = const {},
    this.compatibleDashboardTemplates = const {},
    this.supportedWidgetIds = const {},
    this.supportedQuickActionIds = const {},
    this.supportsBasicMode = true,
    this.supportsAdvancedMode = true,
    this.defaultOrder = 999,
  });

  /// Whether any route is registered.
  bool get hasRoutes => routePaths.isNotEmpty;

  /// Whether the module has a working frontend.
  bool get isUsable =>
      maturity == ModuleMaturity.implemented ||
      maturity == ModuleMaturity.partial;
}

// ═══════════════════════════════════════════════════════════
//  Blueprint Module Selection (AI/Owner generated)
// ═══════════════════════════════════════════════════════════

/// How a module was selected for the workspace.
enum ModuleConfigurationSource {
  /// AI recommended based on business analysis.
  aiRecommended,
  /// Owner explicitly selected.
  ownerSelected,
  /// Required by the system (e.g. dashboard).
  systemRequired,
  /// Pulled in as a dependency of another module.
  dependency,
  /// Manually disabled by the owner/admin.
  manuallyDisabled;

  String get labelKey => 'msrc_$name';
}

/// Represents one module's selection in a workspace blueprint.
/// Ready for backend JSON serialization.
class BlueprintModuleSelection {
  final ErpModuleId moduleId;
  final bool enabled;
  final bool required;
  final ModuleConfigurationSource source;
  final Map<String, dynamic> settings;
  final int navigationOrder;

  const BlueprintModuleSelection({
    required this.moduleId,
    this.enabled = true,
    this.required = false,
    this.source = ModuleConfigurationSource.ownerSelected,
    this.settings = const {},
    this.navigationOrder = 999,
  });

  /// Creates from a hypothetical JSON payload.
  factory BlueprintModuleSelection.fromJson(Map<String, dynamic> json) {
    return BlueprintModuleSelection(
      moduleId: ErpModuleId.values.firstWhere(
        (m) => m.name == json['moduleId'],
        orElse: () => throw ArgumentError('Unknown module: ${json['moduleId']}'),
      ),
      enabled: json['enabled'] as bool? ?? true,
      required: json['required'] as bool? ?? false,
      source: ModuleConfigurationSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => ModuleConfigurationSource.ownerSelected,
      ),
      settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
      navigationOrder: json['navigationOrder'] as int? ?? 999,
    );
  }

  Map<String, dynamic> toJson() => {
    'moduleId': moduleId.name,
    'enabled': enabled,
    'required': required,
    'source': source.name,
    'settings': settings,
    'navigationOrder': navigationOrder,
  };
}
