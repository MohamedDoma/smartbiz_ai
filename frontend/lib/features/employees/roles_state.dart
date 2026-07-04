// SmartBiz AI — Roles state management with templates + CRUD.
import 'package:flutter/material.dart';
import '../dashboard/models/dashboard_config_models.dart';
import 'models/role_models.dart';

/// Predefined role templates.
class RoleTemplates {
  RoleTemplates._();

  static Map<AppModule, ModulePermissions> _perms(Map<AppModule, Set<PermAction>> map) {
    return {
      for (final m in AppModule.values)
        m: ModulePermissions(module: m, enabled: map[m] ?? {}),
    };
  }

  static CustomRole owner() => CustomRole(id: 'sys_owner', name: 'Owner / Admin', description: 'Full access to all modules and settings.', type: RoleType.system, dashboardTemplate: DashboardTemplate.executive, aiAccess: RoleAiAccess.full, assignedCount: 1,
    permissions: _perms({for (final m in AppModule.values) m: Set.from(m.applicableActions)}));

  static CustomRole cashier() => CustomRole(id: 'sys_cashier', name: 'Cashier', description: 'Point-of-sale, invoices, and customer lookup.', type: RoleType.system, dashboardTemplate: DashboardTemplate.sales, aiAccess: RoleAiAccess.limited, assignedCount: 2,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.invoices: {PermAction.view, PermAction.create}, AppModule.customers: {PermAction.view},
      AppModule.payments: {PermAction.view, PermAction.create},
      AppModule.pos: {PermAction.view, PermAction.create},
    }));

  static CustomRole warehouse() => CustomRole(id: 'sys_warehouse', name: 'Warehouse', description: 'Inventory management and stock operations.', type: RoleType.system, dashboardTemplate: DashboardTemplate.inventory, aiAccess: RoleAiAccess.limited, assignedCount: 1,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.products: {PermAction.view, PermAction.edit}, AppModule.inventory: {PermAction.view, PermAction.create, PermAction.edit, PermAction.manage},
    }));

  static CustomRole accountant() => CustomRole(id: 'sys_accountant', name: 'Accountant', description: 'Financial records, reports, and invoice management.', type: RoleType.system, dashboardTemplate: DashboardTemplate.finance, aiAccess: RoleAiAccess.full, assignedCount: 1,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.invoices: {PermAction.view, PermAction.export}, AppModule.accounting: {PermAction.view, PermAction.create, PermAction.edit, PermAction.export},
      AppModule.reports: {PermAction.view, PermAction.export}, AppModule.customers: {PermAction.view},
      AppModule.payments: {PermAction.view},
    }));

  static CustomRole employee() => CustomRole(id: 'sys_employee', name: 'Employee', description: 'Basic access with AI assistant.', type: RoleType.system, dashboardTemplate: DashboardTemplate.basicEmployee, aiAccess: RoleAiAccess.limited, assignedCount: 1,
    permissions: _perms({AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}}));

  // Extended templates for custom roles
  static CustomRole manager() => CustomRole(id: 'tpl_manager', name: 'Manager', description: 'Oversees operations, employees, and reports.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.executive, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.invoices: {PermAction.view, PermAction.create, PermAction.edit, PermAction.approve}, AppModule.customers: {PermAction.view, PermAction.create, PermAction.edit},
      AppModule.products: {PermAction.view}, AppModule.inventory: {PermAction.view},
      AppModule.accounting: {PermAction.view}, AppModule.reports: {PermAction.view, PermAction.export},
      AppModule.employees: {PermAction.view, PermAction.create},
    }));

  static CustomRole genManager() => CustomRole(id: 'tpl_gen_manager', name: 'General Manager', description: 'Full operational oversight with team management.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.executive, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      for (final m in AppModule.values) m: Set.from(m.applicableActions.where((a) => a != PermAction.manage || m == AppModule.employees || m == AppModule.inventory)),
    }));

  static CustomRole deptManager() => CustomRole(id: 'tpl_dept_manager', name: 'Department Manager', description: 'Manages a specific department and its employees.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.operations, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.employees: {PermAction.view, PermAction.create, PermAction.edit}, AppModule.roles: {PermAction.view},
      AppModule.reports: {PermAction.view, PermAction.export}, AppModule.customers: {PermAction.view},
      AppModule.invoices: {PermAction.view, PermAction.approve},
    }));

  static CustomRole teamLeader() => CustomRole(id: 'tpl_team_leader', name: 'Team Leader', description: 'Leads a team with limited management access.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.operations, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.employees: {PermAction.view}, AppModule.reports: {PermAction.view},
    }));

  static CustomRole sales() => CustomRole(id: 'tpl_sales', name: 'Sales Representative', description: 'Customer relations, invoicing, and quotations.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.sales, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.invoices: {PermAction.view, PermAction.create, PermAction.edit}, AppModule.customers: {PermAction.view, PermAction.create, PermAction.edit},
      AppModule.products: {PermAction.view}, AppModule.reports: {PermAction.view},
      AppModule.payments: {PermAction.view, PermAction.create},
      AppModule.pos: {PermAction.view, PermAction.create},
    }));

  static CustomRole hrManager() => CustomRole(id: 'tpl_hr_mgr', name: 'HR Manager', description: 'Full HR and employee lifecycle management.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.hr, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.employees: {PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.manage},
      AppModule.roles: {PermAction.view, PermAction.create, PermAction.edit},
    }));

  static CustomRole hr() => CustomRole(id: 'tpl_hr', name: 'HR Assistant', description: 'Employee onboarding and basic HR tasks.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.hr, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.employees: {PermAction.view, PermAction.create, PermAction.edit},
      AppModule.roles: {PermAction.view},
    }));

  static CustomRole whManager() => CustomRole(id: 'tpl_wh_mgr', name: 'Warehouse Manager', description: 'Full warehouse and inventory control.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.inventory, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.products: {PermAction.view, PermAction.create, PermAction.edit, PermAction.delete},
      AppModule.inventory: {PermAction.view, PermAction.create, PermAction.edit, PermAction.manage},
      AppModule.reports: {PermAction.view, PermAction.export},
    }));

  static CustomRole procurement() => CustomRole(id: 'tpl_procurement_off', name: 'Procurement Officer', description: 'Purchasing, vendor relations, and stock receiving.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.operations, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.products: {PermAction.view, PermAction.create, PermAction.edit}, AppModule.inventory: {PermAction.view, PermAction.create, PermAction.edit},
      AppModule.accounting: {PermAction.view, PermAction.create},
    }));

  static CustomRole support() => CustomRole(id: 'tpl_support', name: 'Support Agent', description: 'Customer support and ticket handling.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.support, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.customers: {PermAction.view, PermAction.edit}, AppModule.invoices: {PermAction.view},
    }));

  static CustomRole projectManager() => CustomRole(id: 'tpl_pm', name: 'Project Manager', description: 'Project oversight and team coordination.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.projects, aiAccess: RoleAiAccess.full, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view}, AppModule.aiAdvisor: {PermAction.view},
      AppModule.employees: {PermAction.view}, AppModule.reports: {PermAction.view, PermAction.export},
      AppModule.customers: {PermAction.view},
    }));

  static CustomRole serviceProvider() => CustomRole(id: 'tpl_service', name: 'Service Provider', description: 'Field service and customer visits.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.service, aiAccess: RoleAiAccess.limited, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.aiChat: {PermAction.view},
      AppModule.customers: {PermAction.view}, AppModule.invoices: {PermAction.view, PermAction.create},
    }));

  static CustomRole delivery() => CustomRole(id: 'tpl_delivery', name: 'Delivery Driver', description: 'Delivery logistics and order fulfillment.', type: RoleType.custom, dashboardTemplate: DashboardTemplate.operations, aiAccess: RoleAiAccess.none, assignedCount: 0,
    permissions: _perms({
      AppModule.dashboard: {PermAction.view}, AppModule.invoices: {PermAction.view},
      AppModule.inventory: {PermAction.view},
    }));

  static List<CustomRole> allSystem() => [owner(), cashier(), warehouse(), accountant(), employee()];
  static List<CustomRole> allTemplates() => [genManager(), deptManager(), teamLeader(), manager(), sales(), hrManager(), hr(), whManager(), procurement(), support(), projectManager(), serviceProvider(), delivery()];
  static List<CustomRole> allSelectableRoles() => [...allSystem(), ...allTemplates()];
}

/// State for roles management.
/// Performance: lazy role list init on first access.
class RolesState extends ChangeNotifier {
  List<CustomRole>? _roles;
  int _counter = 3;

  List<CustomRole> get _data {
    _roles ??= [
      ...RoleTemplates.allSystem(),
      RoleTemplates.manager().deepCopy(id: 'cust_1', name: 'Manager'),
      RoleTemplates.sales().deepCopy(id: 'cust_2', name: 'Sales'),
    ];
    return _roles!;
  }

  // ── Getters ─────────────────────────────────────────────
  List<CustomRole> get allRoles => List.unmodifiable(_data);
  List<CustomRole> get systemRoles => _data.where((r) => r.type == RoleType.system).toList();
  List<CustomRole> get customRoles => _data.where((r) => r.type == RoleType.custom).toList();
  int get totalCount => _data.length;

  CustomRole? getById(String id) {
    try { return _data.firstWhere((r) => r.id == id); }
    catch (_) { return null; }
  }

  // ── CRUD ────────────────────────────────────────────────
  void addRole(CustomRole role) {
    _data.add(CustomRole(
      id: 'cust_${_counter++}',
      name: role.name,
      description: role.description,
      type: RoleType.custom,
      dashboardTemplate: role.dashboardTemplate,
      aiAccess: role.aiAccess,
      permissions: {for (final e in role.permissions.entries) e.key: e.value.copyWith()},
      landingRoute: role.landingRoute,
      enabledWidgetIds: role.enabledWidgetIds,
      disabledWidgetIds: role.disabledWidgetIds,
      enabledActionIds: role.enabledActionIds,
      disabledActionIds: role.disabledActionIds,
      configSource: DashboardSource.workspaceRole,
    ));
    notifyListeners();
  }

  void updateRole(String id, {String? name, String? description, DashboardTemplate? dashboardTemplate, RoleAiAccess? aiAccess}) {
    final r = getById(id);
    if (r == null) return;
    if (name != null) r.name = name;
    if (description != null) r.description = description;
    if (dashboardTemplate != null) r.dashboardTemplate = dashboardTemplate;
    if (aiAccess != null) r.aiAccess = aiAccess;
    r.lastUpdated = DateTime.now();
    notifyListeners();
  }

  void deleteRole(String id) {
    _data.removeWhere((r) => r.id == id && r.type == RoleType.custom);
    notifyListeners();
  }

  void togglePermission(String roleId, AppModule module, PermAction action) {
    final r = getById(roleId);
    if (r == null) return;
    r.permissions[module]?.toggle(action);
    r.lastUpdated = DateTime.now();
    notifyListeners();
  }

  void selectAllModule(String roleId, AppModule module) {
    final r = getById(roleId);
    if (r == null) return;
    r.permissions[module]?.selectAll();
    r.lastUpdated = DateTime.now();
    notifyListeners();
  }

  void clearModule(String roleId, AppModule module) {
    final r = getById(roleId);
    if (r == null) return;
    r.permissions[module]?.clearAll();
    r.lastUpdated = DateTime.now();
    notifyListeners();
  }
}
