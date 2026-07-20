// SmartBiz AI — Employee & Role data models.

/// Employee status.
enum EmpStatus { active, invited, suspended }

/// AI access level.
enum AiAccess { none, limited, full }

/// System roles.
enum AppRole { owner, cashier, warehouse, accountant, employee }

/// A single employee.
class Employee {
  final String id;
  String name;
  String email;
  String? phone;
  AppRole role;
  String? department;
  String? branch;
  EmpStatus status;
  AiAccess aiAccess;
  String langPref; // 'en' or 'ar'
  DateTime? lastActive;

  Employee({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    required this.role,
    this.department,
    this.branch,
    this.status = EmpStatus.active,
    this.aiAccess = AiAccess.limited,
    this.langPref = 'en',
    this.lastActive,
  });
}

/// Role definition with permissions metadata.
class RoleDefinition {
  final AppRole role;
  final String nameKey;
  final String descKey;
  final List<String> moduleKeys;
  final List<String> permissionKeys;
  final AiAccess recommendedAi;
  final String dashboardKey;

  const RoleDefinition({
    required this.role,
    required this.nameKey,
    required this.descKey,
    required this.moduleKeys,
    required this.permissionKeys,
    required this.recommendedAi,
    required this.dashboardKey,
  });
}

/// Predefined role definitions.
class RoleDefinitions {
  RoleDefinitions._();

  static const List<RoleDefinition> all = [
    RoleDefinition(
      role: AppRole.owner,
      nameKey: 'role_owner',
      descKey: 'role_owner_desc',
      moduleKeys: ['nav_dashboard', 'nav_ai_chat', 'nav_advisor', 'nav_sales', 'nav_products', 'nav_inventory', 'nav_customers', 'nav_accounting', 'nav_reports', 'nav_employees', 'nav_settings'],
      permissionKeys: ['perm_full_access', 'perm_manage_users', 'perm_billing', 'perm_ai_config'],
      recommendedAi: AiAccess.full,
      dashboardKey: 'dash_owner',
    ),
    RoleDefinition(
      role: AppRole.cashier,
      nameKey: 'role_cashier',
      descKey: 'role_cashier_desc',
      moduleKeys: ['nav_sales', 'nav_customers'],
      permissionKeys: ['perm_create_invoice', 'perm_view_customers', 'perm_receive_payment'],
      recommendedAi: AiAccess.limited,
      dashboardKey: 'dash_cashier',
    ),
    RoleDefinition(
      role: AppRole.warehouse,
      nameKey: 'role_warehouse',
      descKey: 'role_warehouse_desc',
      moduleKeys: ['nav_products', 'nav_inventory'],
      permissionKeys: ['perm_view_products', 'perm_adjust_stock', 'perm_receive_goods'],
      recommendedAi: AiAccess.limited,
      dashboardKey: 'dash_warehouse',
    ),
    RoleDefinition(
      role: AppRole.accountant,
      nameKey: 'role_accountant',
      descKey: 'role_accountant_desc',
      moduleKeys: ['nav_accounting', 'nav_reports', 'nav_sales'],
      permissionKeys: ['perm_view_finance', 'perm_manage_expenses', 'perm_view_reports', 'perm_view_invoices'],
      recommendedAi: AiAccess.full,
      dashboardKey: 'dash_accountant',
    ),
    RoleDefinition(
      role: AppRole.employee,
      nameKey: 'role_employee',
      descKey: 'role_employee_desc',
      moduleKeys: ['nav_dashboard', 'nav_ai_chat'],
      permissionKeys: ['perm_view_dashboard', 'perm_use_chat'],
      recommendedAi: AiAccess.limited,
      dashboardKey: 'dash_employee',
    ),
  ];

  static RoleDefinition forRole(AppRole role) => all.firstWhere((r) => r.role == role);
}
