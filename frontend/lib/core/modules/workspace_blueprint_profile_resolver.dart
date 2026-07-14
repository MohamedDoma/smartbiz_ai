// SmartBiz AI — Workspace Blueprint Profile Resolver.
//
// Maps generic dashboard/role profiles to the set of ERP modules
// each profile logically requires. Used as a frontend-only temporary
// blueprint until AI/backend configuration is connected.
//
// Rules:
//   • Only includes modules with maturity == implemented or partial.
//   • Does not include planned/unavailable modules without screens.
//   • Profiles are generic (finance, sales, hr) — not industry-specific.
//   • Hard-required modules (dashboard, settings) are always included
//     by WorkspaceModuleState, so they don't need to be listed here
//     but are included for clarity.
import '../modules/erp_module_models.dart';
import '../../features/dashboard/models/dashboard_config_models.dart';

/// A frontend-only module profile for a dashboard/role context.
/// Temporary until AI/backend blueprint config is connected.
class BlueprintProfile {
  final String id;
  final Set<ErpModuleId> modules;

  const BlueprintProfile({required this.id, required this.modules});
}

class WorkspaceBlueprintProfileResolver {
  WorkspaceBlueprintProfileResolver._();

  // ═══════════════════════════════════════════════════════════
  //  Generic module profiles — implemented modules only
  // ═══════════════════════════════════════════════════════════

  /// Owner/executive: broad access to all implemented business modules.
  static const _ownerModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.aiAdvisor,
    ErpModuleId.customers,
    ErpModuleId.products,
    ErpModuleId.inventory,
    ErpModuleId.invoices,
    ErpModuleId.payments,
    ErpModuleId.pos,
    ErpModuleId.pipelines,
    ErpModuleId.accounting,
    ErpModuleId.reports,
    ErpModuleId.employees,
    ErpModuleId.roles,
    ErpModuleId.departments,
    ErpModuleId.teams,
    ErpModuleId.commissions,
    ErpModuleId.approvals,
  };

  /// Finance/accountant: accounting, reports, invoices.
  static const _financeModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.aiAdvisor,
    ErpModuleId.accounting,
    ErpModuleId.expenses,
    ErpModuleId.reports,
    ErpModuleId.invoices,
    ErpModuleId.payments,
    ErpModuleId.customers,
    ErpModuleId.commissions,
    ErpModuleId.approvals,
  };

  /// Sales/cashier: customers, products, invoices.
  static const _salesModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.customers,
    ErpModuleId.products,
    ErpModuleId.invoices,
    ErpModuleId.payments,
    ErpModuleId.pos,
    ErpModuleId.pipelines,
    ErpModuleId.reports,
    ErpModuleId.commissions,
    ErpModuleId.approvals,
  };

  /// Inventory/warehouse: products, inventory, stock management.
  static const _inventoryModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.products,
    ErpModuleId.inventory,
    ErpModuleId.reports,
  };

  /// HR: employees, roles, departments, teams.
  static const _hrModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.employees,
    ErpModuleId.roles,
    ErpModuleId.departments,
    ErpModuleId.teams,
    ErpModuleId.reports,
  };

  /// Operations: products, inventory, reports.
  static const _operationsModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
    ErpModuleId.products,
    ErpModuleId.inventory,
    ErpModuleId.reports,
    ErpModuleId.employees,
  };

  /// Basic employee: minimal — core + AI only.
  static const _basicModules = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.settings,
    ErpModuleId.aiChat,
  };

  // ═══════════════════════════════════════════════════════════
  //  Template → Profile mapping
  // ═══════════════════════════════════════════════════════════

  /// Resolves the module set for a given dashboard template.
  static BlueprintProfile forTemplate(DashboardTemplate template) =>
      switch (template) {
        DashboardTemplate.executive => const BlueprintProfile(
          id: 'owner',
          modules: _ownerModules,
        ),
        DashboardTemplate.finance => const BlueprintProfile(
          id: 'finance',
          modules: _financeModules,
        ),
        DashboardTemplate.sales => const BlueprintProfile(
          id: 'sales',
          modules: _salesModules,
        ),
        DashboardTemplate.inventory => const BlueprintProfile(
          id: 'inventory',
          modules: _inventoryModules,
        ),
        DashboardTemplate.hr => const BlueprintProfile(
          id: 'hr',
          modules: _hrModules,
        ),
        DashboardTemplate.operations => const BlueprintProfile(
          id: 'operations',
          modules: _operationsModules,
        ),
        DashboardTemplate.projects => const BlueprintProfile(
          id: 'operations',
          modules: _operationsModules,
        ),
        DashboardTemplate.support => const BlueprintProfile(
          id: 'basic',
          modules: _basicModules,
        ),
        DashboardTemplate.service => const BlueprintProfile(
          id: 'basic',
          modules: _basicModules,
        ),
        DashboardTemplate.basicEmployee => const BlueprintProfile(
          id: 'basic',
          modules: _basicModules,
        ),
        DashboardTemplate.custom => const BlueprintProfile(
          id: 'basic',
          modules: _basicModules,
        ),
      };

  /// All defined profile IDs for reference.
  static const allProfileIds = [
    'owner',
    'finance',
    'sales',
    'inventory',
    'hr',
    'operations',
    'basic',
  ];
}
