# Step 59.2.0 — Demo Reset + Seed Report

## Files Created/Updated
- `app/Console/Commands/SmartBizDemoResetCommand.php`
- `database/seeders/SmartBizDemoSeeder.php`
- `docs/demo_credentials.csv` / `docs/demo_credentials.md`
- `docs/demo_seed_summary.md`

## Command
```bash
docker exec smartbiz_app php artisan smartbiz:demo-reset --yes
```

## Root Cause (Onboarding Issue)
Demo reset truncated `business_templates`, `workspace_template_applications`,
and `workspace_feature_flags` but never re-seeded them. The `AuthSessionPayloadBuilder`
checks for a `WorkspaceTemplateApplication` with `status=applied` to set
`onboarding_completed=true`.

## Fix Applied
1. Re-seed business templates via `BusinessTemplateSeeder`
2. Apply `automotive_dealer` template to demo workspace via `BusinessTemplateApplicationService`
3. Re-enforce restricted role permissions after template merge (prevents `reports.view` leakage)

## AI Permission Matrix (Corrected)
| Role | reports.view | pipelines.list | inventory.list | Finance AI | Pipeline AI | Inventory AI |
|------|-------------|----------------|----------------|-----------|-------------|-------------|
| Owner/Admin/GM | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Accountant | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Sales Mgr/Agent | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ |
| Inventory Mgr/WH | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| Cashier | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| HR/Emp/Viewer | ❌ | ❌ | varies | ❌ | ❌ | ❌ |

> **Note:** Cashier retains `contacts.list` for customer lookup but does NOT have `pipelines.list`.

## AI Tool → Permission Mapping
- `get_finance_summary` → `reports.view`
- `get_inventory_summary` → `inventory.list`
- `get_pipeline_summary` → `pipelines.list` (dedicated pipeline permission)

> The role→permission mapping above applies only to the Demo workspace.
> Real workspaces can assign `pipelines.list` to any standard or custom role.
