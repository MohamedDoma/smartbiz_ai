// SmartBiz AI — Test Navigation Permissions Helper.
//
// Provides a canonical set of navigation permission keys that match
// the registry's `navPerms` definitions. Tests that exercise the
// ModuleRouteGuard, ModuleNavigationResolver, or BlueprintNavigation
// must supply these keys (or a subset) to pass permission checks.
//
// These keys must stay in sync with the `navPerms` fields in
// erp_module_registry.dart. When a new module adds navPerms,
// add its key here.

/// All navPerms keys from the registry — grants "full access" for
/// any permission-gated navigation check.
const Set<String> kAllNavPerms = {
  // Core
  'ai_advisor.view',
  // CRM / Sales
  'contacts.list',
  'pipelines.list',
  'commissions.list',
  'invoices.list',
  'payments.list',
  'pos.view',
  // Products & Operations
  'products.list',
  'inventory.list',
  // Finance
  'accounting.view',
  'reports.view',
  // HR / People
  'employees.list',
  'roles.list',
  'departments.list',
  'teams.list',
  // Workflow
  'approvals.list',
  // System
  'settings.view',
};

/// A superset combining frontend-style permission keys (from role
/// templates) AND backend-style navPerms. Use this when testing
/// components that may check either format.
Set<String> kOwnerPermissions() => {
  // Frontend-style (DashboardContextAdapter output)
  'dashboard.view', 'aiChat.view', 'aiAdvisor.view',
  'customers.view', 'invoices.view', 'products.view',
  'inventory.view', 'accounting.view', 'reports.view',
  'employees.view', 'settings.view', 'expenses.view',
  'roles.view', 'billing.view', 'payments.view', 'pos.view',
  // Backend-style navPerms
  ...kAllNavPerms,
};
