// SmartBiz AI — Dynamic Page Models.
//
// Pure Dart models for a page registry that maps module routes to
// generic page types. No Flutter, no BuildContext, no UI.
//
// These models describe what a page IS, not how it renders.
// The actual page registry and UI rendering will be built on top.
import '../modules/erp_module_models.dart' show ErpModuleId;

// ═══════════════════════════════════════════════════════════
//  Page Type
// ═══════════════════════════════════════════════════════════

/// Generic page archetype — determines layout and interaction pattern.
enum DynamicPageType {
  /// Scrollable list of records (e.g. Employees, Invoices).
  list,
  /// Single record detail view (e.g. Employee Detail).
  detail,
  /// Create or edit form (e.g. Invite Employee, Create Invoice).
  form,
  /// Report or analytics view (e.g. Financial Reports).
  report,
  /// Dashboard or summary view (e.g. HR Dashboard).
  dashboard,
  /// Point-of-sale or transactional interface.
  pos,
  /// Kanban / board view (e.g. Tasks, Pipelines).
  kanban,
  /// Calendar or schedule view (e.g. Appointments, Leave).
  calendar,
  /// Settings or configuration page.
  settings,
  /// Empty / placeholder page for unimplemented routes.
  empty;

  String get labelKey => 'dpt_$name';
}

// ═══════════════════════════════════════════════════════════
//  Page Capability
// ═══════════════════════════════════════════════════════════

/// Actions a page can support. Used for toolbar/FAB rendering
/// and permission-gated feature toggling.
enum DynamicPageCapability {
  view,
  create,
  edit,
  delete,
  export,
  import,
  print,
  approve,
  assign,
  search,
  filter;

  String get labelKey => 'dpc_$name';
}

// ═══════════════════════════════════════════════════════════
//  Page Definition
// ═══════════════════════════════════════════════════════════

/// Immutable description of a page in the dynamic page registry.
/// Maps a route to its module, type, capabilities, and permissions.
class DynamicPageDefinition {
  /// Unique page identifier (e.g. 'employees_list', 'invoice_create').
  final String id;

  /// The ERP module this page belongs to.
  final ErpModuleId moduleId;

  /// Route path this page is registered under (e.g. '/employees').
  final String route;

  /// Localization key for the page title.
  final String titleKey;

  /// Generic page archetype.
  final DynamicPageType pageType;

  /// Actions this page supports.
  final Set<DynamicPageCapability> capabilities;

  /// Permission keys required to access this page.
  /// Empty means no specific permission check beyond module enablement.
  final Set<String> requiredPermissions;

  /// Whether a working frontend screen exists for this page.
  final bool isImplemented;

  /// Whether this page is only visible in Advanced navigation mode.
  final bool isAdvancedOnly;

  /// Arbitrary metadata for page-specific configuration.
  final Map<String, dynamic> metadata;

  const DynamicPageDefinition({
    required this.id,
    required this.moduleId,
    required this.route,
    required this.titleKey,
    required this.pageType,
    this.capabilities = const {},
    this.requiredPermissions = const {},
    this.isImplemented = true,
    this.isAdvancedOnly = false,
    this.metadata = const {},
  });

  // ── Convenience helpers ──────────────────────────────────

  /// Whether the page supports creating new records.
  bool get canCreate => capabilities.contains(DynamicPageCapability.create);

  /// Whether the page supports editing records.
  bool get canEdit => capabilities.contains(DynamicPageCapability.edit);

  /// Whether the page supports exporting data.
  bool get canExport => capabilities.contains(DynamicPageCapability.export);

  /// Whether the page has any permission requirements.
  bool get hasPermissions => requiredPermissions.isNotEmpty;

  @override
  String toString() => 'DynamicPageDefinition('
      'id: $id, module: ${moduleId.name}, route: $route, '
      'type: ${pageType.name}, implemented: $isImplemented)';
}

// ═══════════════════════════════════════════════════════════
//  Registry Lookup Result
// ═══════════════════════════════════════════════════════════

/// Result of a page lookup in the dynamic page registry.
class DynamicPageRegistryResult {
  /// The resolved page definition, or null if not found.
  final DynamicPageDefinition? page;

  /// Whether a matching page was found.
  final bool found;

  /// Human-readable reason (useful for debugging / fallback messages).
  final String reason;

  const DynamicPageRegistryResult({
    this.page,
    required this.found,
    required this.reason,
  });

  /// Shorthand for a successful lookup.
  const DynamicPageRegistryResult.found(DynamicPageDefinition this.page)
      : found = true,
        reason = 'Page found';

  /// Shorthand for a failed lookup.
  const DynamicPageRegistryResult.notFound(this.reason)
      : page = null,
        found = false;

  @override
  String toString() => 'DynamicPageRegistryResult('
      'found: $found, reason: $reason, page: ${page?.id})';
}
