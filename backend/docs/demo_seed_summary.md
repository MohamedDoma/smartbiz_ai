# Demo Seed Summary

## Workspace
- شركة سمارت بزنس التجريبية (Automotive: cars + spare parts + service)
- Template: `automotive_dealer` (applied via BusinessTemplateApplicationService)
- Onboarding: completed ✅

## Users: 14 (1 super admin + 13 workspace members)
## Roles: 13 workspace-scoped roles with real permission arrays
## Departments: 6 | Teams: 3
## Warehouses: 2 | Product Categories: 2 | Products: 10
## Contacts: 13 (10 customers + 3 suppliers)
## Pipeline: 1 pipeline, 8 stages, 12 records
## Invoices: 8 (3 paid, 2 partial, 3 unpaid) | Payments: 6
## Finance: 10 accounts + 5 expenses (if tables exist)
## Activation: 1 campaign + 5 codes

## Onboarding/Configuration
- workspace_template_applications: 1 (status=applied)
- workspace_feature_flags: 12 (all automotive_dealer modules)
- Business templates: 5 (re-seeded from BusinessTemplateSeeder)

## AI Tool Permission Mapping
- Finance → `reports.view` (owner/admin/gm/accountant only)
- Inventory → `inventory.list` (owner/admin/gm/inventory_manager/warehouse_staff)
- Pipeline → `pipelines.list` (owner/admin/gm/sales_manager/sales_agent)

## API Protection
`pipelines.list` also protects Pipeline read API endpoints via CheckPermission middleware.

## Permission Enforcement
After template application, restricted role permissions are re-enforced to prevent
the template merge from adding `reports.view` to sales/inventory roles.
