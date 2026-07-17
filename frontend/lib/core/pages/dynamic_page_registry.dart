// SmartBiz AI — Dynamic Page Registry.
//
// Static registry mapping existing app routes to DynamicPageDefinitions.
// Pure Dart — no Flutter, no BuildContext, no UI.
//
// Only routes with implemented screens are registered.
// Lookup helpers provide type-safe access for future page rendering.
import '../modules/erp_module_models.dart' show ErpModuleId;
import 'dynamic_page_models.dart';

// Shorthand aliases for readability.
typedef _PT = DynamicPageType;
typedef _PC = DynamicPageCapability;

/// Canonical set of capabilities for common page archetypes.
const _listCaps = <DynamicPageCapability>{_PC.view, _PC.search, _PC.filter, _PC.export};
const _formCaps = <DynamicPageCapability>{_PC.view, _PC.create};
const _editFormCaps = <DynamicPageCapability>{_PC.view, _PC.create, _PC.edit};
const _reportCaps = <DynamicPageCapability>{_PC.view, _PC.filter, _PC.export, _PC.print};
const _settingsCaps = <DynamicPageCapability>{_PC.view, _PC.edit};
const _dashCaps = <DynamicPageCapability>{_PC.view};

class DynamicPageRegistry {
  DynamicPageRegistry._();

  // ═══════════════════════════════════════════════════════════
  //  Registered Pages
  // ═══════════════════════════════════════════════════════════

  static const List<DynamicPageDefinition> pages = [
    // ── Core ───────────────────────────────────────────────
    DynamicPageDefinition(
      id: 'dashboard', moduleId: ErpModuleId.dashboard,
      route: '/dashboard', titleKey: 'page_dashboard',
      pageType: _PT.dashboard, capabilities: _dashCaps,
    ),
    DynamicPageDefinition(
      id: 'ai_chat', moduleId: ErpModuleId.aiChat,
      route: '/ai-chat', titleKey: 'page_ai_chat',
      pageType: _PT.dashboard, capabilities: _dashCaps,
    ),
    DynamicPageDefinition(
      id: 'advisor', moduleId: ErpModuleId.aiAdvisor,
      route: '/advisor', titleKey: 'page_advisor',
      pageType: _PT.report, capabilities: {_PC.view, _PC.filter},
    ),

    // ── Customers ──────────────────────────────────────────
    DynamicPageDefinition(
      id: 'customers_list', moduleId: ErpModuleId.customers,
      route: '/customers', titleKey: 'page_customers',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'customers.view'},
    ),
    DynamicPageDefinition(
      id: 'customer_create', moduleId: ErpModuleId.customers,
      route: '/customers/create', titleKey: 'page_customer_create',
      pageType: _PT.form, capabilities: _formCaps,
      requiredPermissions: {'customers.create'},
    ),

    // ── Products ───────────────────────────────────────────
    DynamicPageDefinition(
      id: 'products_list', moduleId: ErpModuleId.products,
      route: '/products', titleKey: 'page_products',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'products.view'},
    ),
    DynamicPageDefinition(
      id: 'product_create', moduleId: ErpModuleId.products,
      route: '/products/create', titleKey: 'page_product_create',
      pageType: _PT.form, capabilities: _formCaps,
      requiredPermissions: {'products.create'},
    ),

    // ── Invoices ───────────────────────────────────────────
    DynamicPageDefinition(
      id: 'invoices_list', moduleId: ErpModuleId.invoices,
      route: '/invoices', titleKey: 'page_invoices',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'invoices.view'},
    ),
    DynamicPageDefinition(
      id: 'invoice_create', moduleId: ErpModuleId.invoices,
      route: '/invoices/create', titleKey: 'page_invoice_create',
      pageType: _PT.form, capabilities: _editFormCaps,
      requiredPermissions: {'invoices.create'},
    ),

    // ── Payments ───────────────────────────────────────────
    DynamicPageDefinition(
      id: 'payments_list', moduleId: ErpModuleId.payments,
      route: '/payments', titleKey: 'page_payments',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'payments.view'},
    ),

    // ── POS ────────────────────────────────────────────────
    DynamicPageDefinition(
      id: 'pos_screen', moduleId: ErpModuleId.pos,
      route: '/pos', titleKey: 'page_pos',
      pageType: _PT.pos, capabilities: {_PC.view, _PC.create, _PC.print},
      requiredPermissions: {'pos.view'},
    ),

    // ── Inventory ──────────────────────────────────────────
    DynamicPageDefinition(
      id: 'inventory_overview', moduleId: ErpModuleId.inventory,
      route: '/inventory', titleKey: 'page_inventory',
      pageType: _PT.dashboard, capabilities: {_PC.view, _PC.search, _PC.filter},
      requiredPermissions: {'inventory.view'},
    ),
    DynamicPageDefinition(
      id: 'inventory_movements', moduleId: ErpModuleId.inventory,
      route: '/inventory/movements', titleKey: 'page_inventory_movements',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'inventory.view'},
    ),
    DynamicPageDefinition(
      id: 'inventory_adjustments', moduleId: ErpModuleId.inventory,
      route: '/inventory/adjustments', titleKey: 'page_inventory_adjustments',
      pageType: _PT.list, capabilities: {_PC.view, _PC.create, _PC.search},
      requiredPermissions: {'inventory.adjust'},
    ),

    // ── Finance ────────────────────────────────────────────
    DynamicPageDefinition(
      id: 'accounting_overview', moduleId: ErpModuleId.accounting,
      route: '/accounting', titleKey: 'page_accounting',
      pageType: _PT.dashboard, capabilities: {_PC.view, _PC.filter},
      requiredPermissions: {'accounting.view'},
    ),
    DynamicPageDefinition(
      id: 'expenses', moduleId: ErpModuleId.expenses,
      route: '/accounting/expenses', titleKey: 'page_expenses',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'expenses.view'},
    ),
    DynamicPageDefinition(
      id: 'reports', moduleId: ErpModuleId.reports,
      route: '/reports', titleKey: 'page_reports',
      pageType: _PT.report, capabilities: _reportCaps,
      requiredPermissions: {'reports.view'},
    ),

    // ── People & Organization ──────────────────────────────
    DynamicPageDefinition(
      id: 'employees_list', moduleId: ErpModuleId.employees,
      route: '/employees', titleKey: 'page_employees',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'employees.view'},
    ),
    DynamicPageDefinition(
      id: 'employee_invite', moduleId: ErpModuleId.employees,
      route: '/employees/invite', titleKey: 'page_employee_invite',
      pageType: _PT.form, capabilities: _formCaps,
      requiredPermissions: {'employees.create'},
    ),
    DynamicPageDefinition(
      id: 'roles_list', moduleId: ErpModuleId.roles,
      route: '/employees/roles', titleKey: 'page_roles',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'roles.view'},
      isAdvancedOnly: true,
    ),
    DynamicPageDefinition(
      id: 'departments_list', moduleId: ErpModuleId.departments,
      route: '/employees/departments', titleKey: 'page_departments',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'departments.view'},
      isAdvancedOnly: true,
    ),
    DynamicPageDefinition(
      id: 'teams_list', moduleId: ErpModuleId.teams,
      route: '/employees/teams', titleKey: 'page_teams',
      pageType: _PT.list, capabilities: _listCaps,
      requiredPermissions: {'teams.view'},
      isAdvancedOnly: true,
    ),
    DynamicPageDefinition(
      id: 'org_overview', moduleId: ErpModuleId.employees,
      route: '/employees/organization', titleKey: 'page_organization',
      pageType: _PT.dashboard, capabilities: _dashCaps,
      requiredPermissions: {'employees.view'},
      isAdvancedOnly: true,
    ),
    DynamicPageDefinition(
      id: 'org_chart', moduleId: ErpModuleId.employees,
      route: '/employees/chart', titleKey: 'page_org_chart',
      pageType: _PT.dashboard, capabilities: _dashCaps,
      requiredPermissions: {'employees.view'},
      isAdvancedOnly: true,
    ),

    // ── Settings ───────────────────────────────────────────
    DynamicPageDefinition(
      id: 'settings_main', moduleId: ErpModuleId.settings,
      route: '/settings', titleKey: 'page_settings',
      pageType: _PT.settings, capabilities: _settingsCaps,
    ),
    DynamicPageDefinition(
      id: 'settings_workspace', moduleId: ErpModuleId.settings,
      route: '/settings/workspace', titleKey: 'page_settings_workspace',
      pageType: _PT.settings, capabilities: _settingsCaps,
    ),
    DynamicPageDefinition(
      id: 'settings_branding', moduleId: ErpModuleId.settings,
      route: '/settings/branding', titleKey: 'page_settings_branding',
      pageType: _PT.settings, capabilities: _settingsCaps,
    ),
    DynamicPageDefinition(
      id: 'settings_billing', moduleId: ErpModuleId.settings,
      route: '/settings/billing', titleKey: 'page_settings_billing',
      pageType: _PT.settings, capabilities: _settingsCaps,
    ),
    DynamicPageDefinition(
      id: 'settings_ai', moduleId: ErpModuleId.settings,
      route: '/settings/ai', titleKey: 'page_settings_ai',
      pageType: _PT.settings, capabilities: _settingsCaps,
    ),
  ];

  // ═══════════════════════════════════════════════════════════
  //  Lookup Helpers
  // ═══════════════════════════════════════════════════════════

  /// Lazily built route → page index for O(1) lookups.
  static Map<String, DynamicPageDefinition>? _routeIndex;

  static Map<String, DynamicPageDefinition> get _index {
    if (_routeIndex != null) return _routeIndex!;
    _routeIndex = {for (final p in pages) p.route: p};
    return _routeIndex!;
  }

  /// Find a page definition by its route path.
  /// Normalizes trailing slashes before matching.
  static DynamicPageRegistryResult findByRoute(String route) {
    final normalized = _normalize(route);
    final page = _index[normalized];
    if (page != null) {
      return DynamicPageRegistryResult.found(page);
    }
    return DynamicPageRegistryResult.notFound(
      'No page registered for route: $normalized',
    );
  }

  /// All pages belonging to a specific module.
  static List<DynamicPageDefinition> pagesForModule(ErpModuleId moduleId) =>
      pages.where((p) => p.moduleId == moduleId).toList();

  /// All pages marked as implemented.
  static List<DynamicPageDefinition> get implementedPages =>
      pages.where((p) => p.isImplemented).toList();

  /// All pages that are Advanced-only.
  static List<DynamicPageDefinition> get advancedOnlyPages =>
      pages.where((p) => p.isAdvancedOnly).toList();

  /// Total number of registered pages.
  static int get count => pages.length;

  // ── Internal ─────────────────────────────────────────────

  /// Strip trailing slash (except root '/').
  static String _normalize(String route) {
    if (route.length > 1 && route.endsWith('/')) {
      return route.substring(0, route.length - 1);
    }
    return route;
  }
}
