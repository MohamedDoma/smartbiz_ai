# Demo Credentials

Password for all: `SmartBiz@123456`

| # | Name | Email | Role | AI Finance | AI Pipeline | AI Inventory |
|---|------|-------|------|-----------|-------------|-------------|
| 0 | Super Admin | superadmin@smartbiz.test | Super Admin | ✅ | ✅ | ✅ |
| 1 | مالك الشركة | owner@demo.smartbiz.test | Owner | ✅ | ✅ | ✅ |
| 2 | مدير النظام | admin@demo.smartbiz.test | Admin | ✅ | ✅ | ✅ |
| 3 | المدير العام | general.manager@demo.smartbiz.test | General Manager | ✅ | ✅ | ✅ |
| 4 | مدير المبيعات | sales.manager@demo.smartbiz.test | Sales Manager | ❌ | ✅ | ❌ |
| 5 | وكيل المبيعات | sales.agent@demo.smartbiz.test | Sales Agent | ❌ | ✅ | ❌ |
| 6 | المحاسب | accountant@demo.smartbiz.test | Accountant | ✅ | ❌ | ❌ |
| 7 | مدير المخزون | inventory.manager@demo.smartbiz.test | Inventory Manager | ❌ | ❌ | ✅ |
| 8 | موظف المستودع | warehouse.staff@demo.smartbiz.test | Warehouse Staff | ❌ | ❌ | ✅ |
| 9 | الكاشير | cashier@demo.smartbiz.test | Cashier | ❌ | ❌ | ❌ |
| 10 | الموارد البشرية | hr@demo.smartbiz.test | HR | ❌ | ❌ | ❌ |
| 11 | رئيس القسم | department.head@demo.smartbiz.test | Department Head | ❌ | ❌ | ❌ |
| 12 | موظف عادي | employee@demo.smartbiz.test | Employee | ❌ | ❌ | ❌ |
| 13 | مستخدم للعرض فقط | viewer@demo.smartbiz.test | Viewer | ❌ | ❌ | ❌ |

## AI Tool → Permission Mapping
- **Finance** → `reports.view` — only Owner/Admin/GM/Accountant
- **Pipeline** → `pipelines.list` — Owner/Admin/GM/Sales Manager/Sales Agent
- **Inventory** → `inventory.list` — Owner/Admin/GM/Inventory Mgr/Warehouse Staff

## API Protection
`pipelines.list` protects both:
- **AI Pipeline tool** (`get_pipeline_summary`) — via `AiToolPermissionGuard`
- **Pipeline read API endpoints** — via `CheckPermission:pipelines.list` middleware on GET routes

## Important Notes
- The Cashier role retains `contacts.list` for customer lookup but does NOT have `pipelines.list`.
- The role→permission mapping above applies only to the Demo workspace.
- Real workspaces can assign `pipelines.list` to any standard or custom role.
- Template assignments are defaults only and can be customized after provisioning.
- Cashier, Technician, and Consultant are not globally blocked from pipelines; they simply don't receive the permission by default.
