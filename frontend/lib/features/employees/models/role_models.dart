// SmartBiz AI — Custom Roles + Permission models.

/// Dashboard type for a role.
enum DashboardType { owner, cashier, warehouse, accountant, employee, custom }

/// Role type.
enum RoleType { system, custom }

/// AI access level for roles.
enum RoleAiAccess { none, limited, full }

/// A single permission action.
enum PermAction { view, create, edit, delete, export, approve, manage }

/// Available modules in the system.
enum AppModule {
  dashboard('mod_dashboard', 'dashboard_outlined'),
  aiChat('mod_ai_chat', 'auto_awesome'),
  aiAdvisor('mod_ai_advisor', 'lightbulb'),
  customers('mod_customers', 'people'),
  invoices('mod_invoices', 'receipt_long'),
  products('mod_products', 'inventory_2'),
  inventory('mod_inventory', 'warehouse'),
  accounting('mod_accounting', 'account_balance'),
  reports('mod_reports', 'bar_chart'),
  employees('mod_employees', 'badge'),
  roles('mod_roles', 'shield'),
  settings('mod_settings', 'settings'),
  billing('mod_billing', 'credit_card');

  final String labelKey;
  final String iconName;
  const AppModule(this.labelKey, this.iconName);

  /// Which permission actions are relevant for this module.
  List<PermAction> get applicableActions => switch (this) {
    AppModule.dashboard => [PermAction.view],
    AppModule.aiChat => [PermAction.view],
    AppModule.aiAdvisor => [PermAction.view],
    AppModule.customers => [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.export],
    AppModule.invoices => [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.export, PermAction.approve],
    AppModule.products => [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete],
    AppModule.inventory => [PermAction.view, PermAction.create, PermAction.edit, PermAction.manage],
    AppModule.accounting => [PermAction.view, PermAction.create, PermAction.edit, PermAction.export, PermAction.approve],
    AppModule.reports => [PermAction.view, PermAction.export],
    AppModule.employees => [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.manage],
    AppModule.roles => [PermAction.view, PermAction.create, PermAction.edit, PermAction.delete, PermAction.manage],
    AppModule.settings => [PermAction.view, PermAction.edit, PermAction.manage],
    AppModule.billing => [PermAction.view, PermAction.manage],
  };
}

/// Permission map for a module: which actions are enabled.
class ModulePermissions {
  final AppModule module;
  final Set<PermAction> enabled;

  ModulePermissions({required this.module, Set<PermAction>? enabled})
      : enabled = enabled ?? {};

  ModulePermissions copyWith({Set<PermAction>? enabled}) =>
      ModulePermissions(module: module, enabled: enabled ?? Set.from(this.enabled));

  bool get hasAny => enabled.isNotEmpty;
  bool get hasAll => enabled.length == module.applicableActions.length;

  void selectAll() => enabled.addAll(module.applicableActions);
  void clearAll() => enabled.clear();
  void toggle(PermAction action) {
    if (enabled.contains(action)) { enabled.remove(action); } else { enabled.add(action); }
  }
}

/// A custom (or system) role definition.
class CustomRole {
  final String id;
  String name;
  String description;
  final RoleType type;
  DashboardType dashboardType;
  RoleAiAccess aiAccess;
  final Map<AppModule, ModulePermissions> permissions;
  int assignedCount;
  final String? createdBy;
  DateTime lastUpdated;

  CustomRole({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.dashboardType,
    required this.aiAccess,
    required this.permissions,
    this.assignedCount = 0,
    this.createdBy,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  int get enabledModuleCount => permissions.values.where((p) => p.hasAny).length;
  int get totalPermissions => permissions.values.fold(0, (sum, p) => sum + p.enabled.length);

  CustomRole deepCopy({String? id, String? name, RoleType? type}) {
    return CustomRole(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description,
      type: type ?? this.type,
      dashboardType: dashboardType,
      aiAccess: aiAccess,
      permissions: {
        for (final e in permissions.entries)
          e.key: e.value.copyWith(),
      },
      assignedCount: 0,
      createdBy: createdBy,
    );
  }
}

/// Localization key for a PermAction.
String permActionKey(PermAction a) => switch (a) {
  PermAction.view => 'perm_view',
  PermAction.create => 'perm_create',
  PermAction.edit => 'perm_edit',
  PermAction.delete => 'perm_delete',
  PermAction.export => 'perm_export',
  PermAction.approve => 'perm_approve',
  PermAction.manage => 'perm_manage',
};

/// Localization key for DashboardType.
String dashTypeKey(DashboardType d) => switch (d) {
  DashboardType.owner => 'cr_dash_owner',
  DashboardType.cashier => 'cr_dash_cashier',
  DashboardType.warehouse => 'cr_dash_warehouse',
  DashboardType.accountant => 'cr_dash_accountant',
  DashboardType.employee => 'cr_dash_employee',
  DashboardType.custom => 'cr_dash_custom',
};

/// Localization key for RoleAiAccess.
String roleAiKey(RoleAiAccess a) => switch (a) {
  RoleAiAccess.none => 'ai_none',
  RoleAiAccess.limited => 'ai_limited',
  RoleAiAccess.full => 'ai_full',
};
