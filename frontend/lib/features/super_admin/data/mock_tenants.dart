// SmartBiz AI — Shared mock tenant data for Super Admin screens.
// Used by both tenants list and tenant detail screens.

enum TenantStatus { active, trial, suspended }
enum TenantPlan { starter, professional, enterprise }

class MockTenant {
  final String id;
  final String name;
  final String ownerName;
  final String ownerEmail;
  final TenantPlan plan;
  final TenantStatus status;
  final int usersCount;
  final int modulesEnabled;
  final int aiRequests30d;
  final String createdDate;
  final String lastActive;
  final List<String> enabledModules;

  const MockTenant({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.ownerEmail,
    required this.plan,
    required this.status,
    required this.usersCount,
    required this.modulesEnabled,
    required this.aiRequests30d,
    required this.createdDate,
    required this.lastActive,
    this.enabledModules = const [],
  });
}

const mockTenants = <MockTenant>[
  MockTenant(id: 't1', name: 'Acme Corp', ownerName: 'Ahmed Khalil', ownerEmail: 'ahmed@acme.com',
    plan: TenantPlan.professional, status: TenantStatus.active,
    usersCount: 12, modulesEnabled: 8, aiRequests30d: 2340, createdDate: '2025-03-15', lastActive: '2h ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'Inventory', 'Reports', 'AI Chat']),
  MockTenant(id: 't2', name: 'Nile Trading', ownerName: 'Sara Hassan', ownerEmail: 'sara@nile.com',
    plan: TenantPlan.professional, status: TenantStatus.active,
    usersCount: 8, modulesEnabled: 7, aiRequests30d: 1850, createdDate: '2025-04-02', lastActive: '1h ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'Reports', 'AI Chat']),
  MockTenant(id: 't3', name: 'Delta Logistics', ownerName: 'Omar Fathy', ownerEmail: 'omar@delta.io',
    plan: TenantPlan.enterprise, status: TenantStatus.active,
    usersCount: 45, modulesEnabled: 12, aiRequests30d: 5200, createdDate: '2024-11-20', lastActive: '30m ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'POS', 'Inventory', 'Accounting', 'Reports', 'Employees', 'Roles', 'AI Chat']),
  MockTenant(id: 't4', name: 'Sunrise Bakery', ownerName: 'Layla Mohamed', ownerEmail: 'layla@sunrise.co',
    plan: TenantPlan.starter, status: TenantStatus.active,
    usersCount: 3, modulesEnabled: 4, aiRequests30d: 420, createdDate: '2025-06-10', lastActive: '5h ago',
    enabledModules: ['Dashboard', 'Products', 'POS', 'AI Chat']),
  MockTenant(id: 't5', name: 'Pharaoh Tech', ownerName: 'Youssef Ali', ownerEmail: 'youssef@pharaoh.dev',
    plan: TenantPlan.enterprise, status: TenantStatus.active,
    usersCount: 30, modulesEnabled: 11, aiRequests30d: 3800, createdDate: '2024-09-05', lastActive: '15m ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Payments', 'Inventory', 'Accounting', 'Reports', 'Employees', 'Roles', 'AI Chat']),
  MockTenant(id: 't6', name: 'Fresh Market', ownerName: 'Mona Ibrahim', ownerEmail: 'mona@fresh.store',
    plan: TenantPlan.starter, status: TenantStatus.trial,
    usersCount: 2, modulesEnabled: 3, aiRequests30d: 180, createdDate: '2025-06-25', lastActive: '1d ago',
    enabledModules: ['Dashboard', 'Products', 'AI Chat']),
  MockTenant(id: 't7', name: 'Alpha Imports', ownerName: 'Karim Nasser', ownerEmail: 'karim@alpha.trade',
    plan: TenantPlan.professional, status: TenantStatus.trial,
    usersCount: 5, modulesEnabled: 6, aiRequests30d: 920, createdDate: '2025-06-20', lastActive: '3h ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Reports', 'AI Chat']),
  MockTenant(id: 't8', name: 'Green Gardens', ownerName: 'Hana Saleh', ownerEmail: 'hana@green.land',
    plan: TenantPlan.starter, status: TenantStatus.trial,
    usersCount: 1, modulesEnabled: 3, aiRequests30d: 85, createdDate: '2025-06-28', lastActive: '2d ago',
    enabledModules: ['Dashboard', 'Products', 'AI Chat']),
  MockTenant(id: 't9', name: 'Desert Motors', ownerName: 'Tarek Mansour', ownerEmail: 'tarek@desert.auto',
    plan: TenantPlan.professional, status: TenantStatus.suspended,
    usersCount: 7, modulesEnabled: 6, aiRequests30d: 0, createdDate: '2025-01-10', lastActive: '15d ago',
    enabledModules: ['Dashboard', 'Customers', 'Products', 'Invoices', 'Reports', 'AI Chat']),
  MockTenant(id: 't10', name: 'Blue Wave Media', ownerName: 'Dina Roshdy', ownerEmail: 'dina@bluewave.co',
    plan: TenantPlan.starter, status: TenantStatus.suspended,
    usersCount: 2, modulesEnabled: 3, aiRequests30d: 0, createdDate: '2025-05-01', lastActive: '30d ago',
    enabledModules: ['Dashboard', 'Products', 'AI Chat']),
];

/// Lookup a tenant by ID, returns null if not found.
MockTenant? findTenantById(String id) {
  try {
    return mockTenants.firstWhere((t) => t.id == id);
  } catch (_) {
    return null;
  }
}
