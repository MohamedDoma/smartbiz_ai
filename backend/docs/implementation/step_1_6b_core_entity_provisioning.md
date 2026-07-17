# Step 1.6B — Core Entity Provisioning

> **Status:** ✅ Complete — All 14 integration scenarios verified  
> **Last verified:** 2026-07-16  
> **Test runner:** `docker exec smartbiz_app php tests/provenance_verification.php`

---

## Overview

Task 1.6B implements the **foundation provisioning engine** that transforms validated Discovery Blueprints into workspace entities. It creates the structural backbone (locations, departments, teams, roles, permissions, module flags, workspace configuration) in a single atomic transaction with full rollback support.

### Scope Boundaries

| **In scope (1.6B)**              | **Out of scope (1.6C+)**                  |
|----------------------------------|--------------------------------------------|
| Locations (branches)             | Warehouses                                 |
| Departments (parent-safe order)  | Sales/purchase pipelines                   |
| Teams                            | Approval workflows                         |
| Roles + exact permissions        | Commission rules                           |
| Module feature flags             | Financial settings (tax, invoice, POS)     |
| WorkspaceConfiguration           | Onboarding finalization                    |

---

## Architecture

### Lifecycle

```
preview() → apply() → rollback()
```

| Method       | Purpose                                                                 |
|-------------|-------------------------------------------------------------------------|
| `preview()`  | Revalidate Blueprint, build execution plan, return summary (read-only) |
| `apply()`    | Revalidate, create entities atomically, transition to `foundation_applied` |
| `rollback()` | Revert entities + config, gated by manual change detection              |

### State Machine

```
preview → prepared → processing → foundation_applied → rolled_back
                                 ↘ failed
```

### Key Classes

| Class                          | Responsibility                                    |
|--------------------------------|---------------------------------------------------|
| `ProvisioningService`          | Orchestration, state transitions, rollback         |
| `CoreEntityProvisioner`        | Entity creation, binding management, snapshots     |
| `ProvisioningPlanBuilder`      | Deterministic plan generation from Blueprint       |
| `BlueprintValidator`           | Pre-apply revalidation (permissions, schema)       |
| `ProvisioningEntityBinding`    | Provenance tracking (created vs. adopted)          |

---

## Concurrency & Atomicity

- **Pessimistic locking**: `SELECT … FOR UPDATE` on `provisioning_runs` scoped to workspace ID prevents concurrent `apply()` calls for the same workspace.
- **Different workspaces are independent**: Row-level locking only affects the target workspace.
- **Full transaction wrapping**: All entity creation, binding, and config updates occur inside a single `DB::transaction()`. Any failure rolls back all mutations atomically.
- **Idempotency**: Re-applying the same Blueprint version returns the existing run without side effects.

---

## Rollback Design

### Snapshot Strategy

Before provisioning, `captureRollbackSnapshot()` captures:
- `workspace_configuration` — full state (enabled_modules, role_configs, pages, workflows, automations, provisioning_run_id), or `null` if absent
- `feature_flags` — all current flag states
- `entity_counts` — baseline counts for roles, departments, teams, warehouses

During provisioning, `CoreEntityProvisioner` tracks:
- `core_entities.created` — entities created by provisioning (deleted on rollback)
- `core_entities.updated` — entities updated during re-apply
- `adopted_entity_snapshots` — full before-state of template-adopted entities (restored on rollback)
- `role_permissions_before` — permission arrays before update
- `feature_flags_before` — flag states before update

### Ownership Model

| `ownership_type`            | On Rollback       |
|-----------------------------|--------------------|
| `created_by_provisioning`   | **Deleted**        |
| `adopted_template_entity`   | **Restored** to pre-adoption snapshot |
| `created_by_template`       | Eligible for adoption by provisioning |

### Manual Change Detection

`detectManualChanges()` runs before rollback and checks:
1. **WorkspaceConfiguration**: `provisioning_run_id` must match the run being rolled back
2. **Created entities**: `updated_at` must not be significantly after `applied_at`

If drift is detected → `409 rollback_conflict` is thrown, and the run remains `foundation_applied`.

### WorkspaceConfiguration Lifecycle

- If WC existed before provisioning → restored to snapshot on rollback
- If WC did **not** exist before provisioning → **deleted** on rollback

---

## Validation Pipeline

Permissions are validated at two stages:

1. **Pre-apply** (`BlueprintValidator::revalidate`): Catches invalid permission keys before any entities are created. Returns `validation_failed` array.
2. **Intra-apply** (`CoreEntityProvisioner::provisionRoles`): Second line of defense. Throws `ProvisioningException` with `invalid_permissions` (422) if any key is not in `PermissionCatalog`.

Both stages use `PermissionCatalog::allKeys()` as the authoritative source.

---

## Integration Test Suite

**Runner:** `docker exec smartbiz_app php tests/provenance_verification.php`

| # | Scenario | Validates |
|---|----------|-----------|
| 1 | Exact Blueprint permissions equal stored role permissions | Permission fidelity |
| 2 | Unknown permission is rejected with no partial changes | Validation + atomicity |
| 3 | Same Blueprint version creates no duplicates | Idempotency |
| 4 | Same-workspace concurrent apply is blocked | Pessimistic locking |
| 5 | Different workspaces are independent | Workspace isolation |
| 6 | Forced mid-run failure rolls back all entities | Transaction atomicity |
| 7 | Clean rollback restores previous state | Rollback correctness |
| 8 | Provisioning-created entities deleted on rollback | Ownership-based cleanup |
| 9 | Template-adopted entities restored, never deleted | Adoption preservation |
| 10 | Manual changes before rollback return `rollback_conflict` 409 | Drift detection |
| 11 | WC absent before provisioning is deleted on rollback | WC lifecycle |
| 12 | Template adoption works for role, department, and team | Cross-entity adoption |
| 13 | Unmanaged entity conflict returns 409 | Provenance enforcement |
| 14 | Missing bound entity detection returns 409 | Binding integrity |

### Test Infrastructure

- **Failure injection**: `CoreEntityProvisioner::$testFailureHook` — private static closure, set via reflection in tests only. Fires after locations, before departments.
- **Deterministic workspace IDs**: `aaaa0000-aaaa-4000-8000-aaaaaaaaa0XX` pattern for isolation.
- **Self-cleaning**: Each scenario cleans up its workspace after execution.

---

## Verification Commands

```bash
# Full pipeline verification
docker exec smartbiz_app php artisan smartbiz:demo-reset --yes
docker exec smartbiz_app php artisan migrate --force        # Should print "Nothing to migrate"
docker exec smartbiz_app php tests/provenance_verification.php  # All 14/14 PASSED ✅
```

---

## Files

| File | Purpose |
|------|---------|
| `app/Services/ProvisioningService.php` | Orchestration, preview/apply/rollback, manual change detection |
| `app/Services/Provisioning/CoreEntityProvisioner.php` | Entity provisioning, bindings, rollback snapshots |
| `app/Services/Provisioning/ProvisioningPlanBuilder.php` | Deterministic plan generation |
| `app/Services/Blueprint/BlueprintValidator.php` | Pre-apply revalidation |
| `app/Services/PermissionCatalog.php` | Authoritative permission registry |
| `app/Models/ProvisioningRun.php` | State machine model |
| `app/Models/ProvisioningEntityBinding.php` | Provenance tracking model |
| `app/Exceptions/ProvisioningException.php` | Domain exception with error codes |
| `tests/provenance_verification.php` | 14-scenario integration suite |
