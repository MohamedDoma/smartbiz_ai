# Step 1.6C — Operational Entity Provisioning

**Status:** CLOSED ✅  
**Date:** 2026-07-17  
**Predecessor:** Step 1.6B (Core Entity Provisioning)  
**Successor:** Step 1.6D (Onboarding Finalization — not started)

---

## Implemented Operational Entities

| Entity | Model | Table | Provisioner Method |
|--------|-------|-------|--------------------|
| Warehouses | `Warehouse` | `warehouses` | `provisionWarehouses()` |
| Pipelines | `Pipeline` | `pipelines` | `provisionPipelines()` |
| Pipeline Stages | `PipelineStage` | `pipeline_stages` | `provisionStages()` |
| Approval Workflows | `ApprovalWorkflow` | `approval_workflows` | `provisionApprovalWorkflows()` |
| Approval Workflow Steps | `ApprovalWorkflowStep` | `approval_workflow_steps` | `provisionWorkflowSteps()` |
| Commission Plans | `CommissionPlan` | `commission_plans` | `provisionCommissionRules()` |
| Commission Rules | `CommissionRule` | `commission_rules` | (nested within plan provisioning) |
| Workspace Settings | `Workspace` | `workspaces` | `provisionSettings()` |

**Source files:**
- `app/Services/Provisioning/OperationalEntityProvisioner.php`
- `app/Services/ProvisioningService.php` (`applyOperational()`, `rollbackOperationalEntities()`)

---

## Transaction and State Transition

```
foundation_applied ──applyOperational()──► applied ──rollback()──► rolled_back
```

- `applyOperational()` requires a `foundation_applied` run; calling without one returns **409 `invalid_status_transition`**.
- All operational entity creation runs inside a single `DB::transaction()`. A mid-run failure rolls back every operational entity atomically — the run remains `foundation_applied`.
- On success, the run transitions to `applied` via `ProvisioningRun::transitionTo()`.

---

## Binding and Idempotency Strategy

Every operational entity is tracked by a `ProvisioningEntityBinding` row:

| Entity Type | `local_key` Format | Example |
|-------------|---------------------|---------|
| `warehouse` | Blueprint key | `main_wh` |
| `pipeline` | Blueprint key | `sales_pipeline` |
| `pipeline_stage` | `{pipeline_key}.{stage_key}` | `sales_pipeline.prospect` |
| `approval_workflow` | Blueprint key | `invoice_approval` |
| `approval_workflow_step` | `{workflow_key}.{step_key}` | `invoice_approval.mgr_review` |
| `commission_plan` | Blueprint key | `sales_commission` |
| `commission_rule` | `{plan_key}.{rule_key}` | `sales_commission.base_pct` |

- **First apply:** creates entity + binding.
- **Re-apply (same version):** `applyOperational()` returns `already_applied: true` without touching entities.
- **Re-apply (new version):** updates existing bound entities via their binding `entity_id`.

---

## Reference Resolution

Cross-entity references are resolved through the binding table:

| Source Entity | Reference Field | Resolved Via |
|---------------|-----------------|--------------|
| Warehouse | `location_key` | `findBinding('location', key)` → `branch_id` |
| Commission Rule | `role_key` | `findBinding('role', key)` → `role_id` |
| Commission Rule | `pipeline_key` | `findBinding('pipeline', key)` → `pipeline_id` |

Unresolved references throw **422 `unresolved_reference`** — no partial entities are created.

---

## Rollback Order

Operational rollback deletes entities in reverse dependency order:

```
commission_rules → commission_plans → approval_workflow_steps →
approval_workflows → pipeline_stages → pipelines → warehouses
```

After operational entities are removed, the existing 1.6B core rollback runs (teams → departments → roles → locations → bindings → feature flags → workspace config).

---

## Verification Results

### 10 Operational Scenarios (1.6C)

| # | Scenario | Result |
|---|----------|--------|
| 1 | Full operational apply creates warehouses, pipelines, approvals, commissions | ✅ |
| 2 | Pipeline stages created in correct order with bindings | ✅ |
| 3 | Warehouse linked to provisioned branch via location_key binding | ✅ |
| 4 | Commission rule resolves role_key via binding | ✅ |
| 5 | Approval workflow steps created with correct workflow_id | ✅ |
| 6 | Workspace settings applied (currency, timezone, locale) | ✅ |
| 7 | Idempotent applyOperational (same version) | ✅ |
| 8 | applyOperational without foundation_applied → 409 | ✅ |
| 9 | Mid-run failure → atomic rollback (no partial entities) | ✅ |
| 10 | Rollback of applied run deletes operational + core entities | ✅ |

### 14 Core Regression Scenarios (1.6B)

| # | Scenario | Result |
|---|----------|--------|
| 1 | Exact Blueprint permissions stored | ✅ |
| 2 | Unknown permission → 422 rejection | ✅ |
| 3 | Idempotent apply (same version) | ✅ |
| 4 | Same-workspace concurrent apply blocked | ✅ |
| 5 | Different workspaces independent | ✅ |
| 6 | Mid-run failure → atomic rollback | ✅ |
| 7 | Clean rollback restores state | ✅ |
| 8 | Created entities deleted on rollback | ✅ |
| 9 | Adopted entities restored, not deleted | ✅ |
| 10 | Manual change → rollback_conflict 409 | ✅ |
| 11 | Absent WC deleted on rollback | ✅ |
| 12 | Template adoption (role, dept, team) | ✅ |
| 13 | Unmanaged entity conflict 409 | ✅ |
| 14 | Missing bound entity 409 | ✅ |

**Total: 24/24 PASSED**

### Infrastructure Checks

| Check | Result |
|-------|--------|
| `smartbiz:demo-reset --yes` | ✅ Clean reset, 14 users, 13 roles, 2 warehouses seeded |
| `migrate --force` | ✅ Nothing to migrate |
| Test data cleanup | ✅ No temporary test data remains |

---

## Remaining Step 1.6D Scope

Step 1.6D (Onboarding Finalization) is **not started**. Expected scope:

- Transition `applied → onboarding_complete`
- Mark workspace `status = 'active'` with `onboarding_completed_at` timestamp
- Generate owner membership assignment from Blueprint primary_owner role
- Fire `WorkspaceOnboardingCompleted` event
- API endpoint integration (`POST /provisioning/{run}/finalize`)
- Verification suite for onboarding lifecycle
