# Step 1.6A — Provisioning Core Foundation

## 1. Previous Provisioning Behavior

### Preview
`ProvisioningService::preview()` loaded a `DiscoveryBlueprint` by workspace+id, called `buildConfig()` to map legacy blueprint keys (`enabled_modules`, `recommended_roles`, `role_homepages`, etc.) into a config blob, and created a new `ProvisioningRun` with status `preview` on every call — **unlimited duplicates**.

### Apply
`ProvisioningService::apply()` loaded the Blueprint, built config, captured a minimal rollback snapshot (enabled_modules, role_configs, pages, workflows, automations), created a `ProvisioningRun` with status `applied`, and immediately upserted `WorkspaceConfiguration`. **No validation**, **no idempotency**, **no concurrency protection**.

### Rollback
`ProvisioningService::rollback()` found an `applied` run, restored `WorkspaceConfiguration` from snapshot, and marked the run `rolled_back`. Functional but only covered config-level rollback.

### Config Builder
`buildConfig()` read legacy keys (`recommended_roles`, `role_homepages`, `role_navigation`) — none of which exist in the canonical Blueprint schema.

---

## 2. Files Inspected

| File | Purpose |
|------|---------|
| `app/Services/ProvisioningService.php` | Existing provisioning engine |
| `app/Http/Controllers/Api/ProvisioningController.php` | API endpoints |
| `app/Models/ProvisioningRun.php` | Run record model |
| `app/Models/WorkspaceConfiguration.php` | Workspace config model |
| `app/Models/DiscoveryBlueprint.php` | Blueprint persistence model |
| `app/Services/Blueprint/BlueprintValidator.php` | Canonical validation |
| `app/Services/Blueprint/BlueprintSchema.php` | Schema constants |
| `app/Services/BusinessTemplateApplicationService.php` | Template onboarding (preserved) |
| `app/Models/WorkspaceFeatureFlag.php` | Module flags (snapshot source) |
| `database/migrations/038_discovery_provisioning.php` | Original provisioning schema |
| `routes/api.php` | Route registration |

---

## 3. Files Created

| File | Purpose |
|------|---------|
| `app/Services/Provisioning/ProvisioningPlanBuilder.php` | Deterministic execution plan builder |
| `app/Exceptions/ProvisioningException.php` | Domain exception with error codes |
| `database/migrations/2026_07_16_170000_provisioning_status_extension.php` | Extends provisioning_runs status constraint |

---

## 4. Files Modified

| File | Change |
|------|--------|
| `app/Services/ProvisioningService.php` | Full refactor: Blueprint revalidation, idempotent preview, prepared apply, rollback snapshot |
| `app/Http/Controllers/Api/ProvisioningController.php` | Exception handling: 404/409/422 responses, no raw stack traces |
| `app/Models/ProvisioningRun.php` | Status constants (PREVIEW, PREPARED, PROCESSING, APPLIED, ROLLED_BACK, FAILED) |

---

## 5. Provisioning Plan Structure

```json
{
  "schema_version": "1.0.0",
  "blueprint_id": "uuid",
  "blueprint_version": 1,
  "workspace_id": "uuid",
  "operations": {
    "workspace_settings": {"business_type":"...","country":"...","currency":"...","timezone":"..."},
    "modules": [{"key":"dashboard","enabled":true,"status":"required"}, ...],
    "locations": [{"key":"branch_1","name":"Branch 1","type":"branch",...}],
    "departments": [...],
    "teams": [...],
    "roles": [{"key":"owner","name":"Owner","permission_count":112,...}],
    "warehouses": [...],
    "pipelines": [...],
    "approval_workflows": [...],
    "commission_rules": [...],
    "payment_methods": [...],
    "tax_settings": {...},
    "invoice_settings": {...},
    "pos_settings": {...},
    "accounting_settings": {...}
  },
  "summary": {
    "locations": 2,
    "departments": 5,
    "teams": 2,
    "roles": 5,
    "enabled_modules": 14,
    "total_modules": 16,
    "warehouses": 2,
    "pipelines": 1,
    "approval_workflows": 1,
    "commission_rules": 1,
    "payment_methods": 3,
    "has_tax_settings": true,
    "has_pos_settings": true,
    "has_accounting": true
  },
  "warnings": [
    "Location 'branch_1' has a placeholder name. Review before finalizing."
  ]
}
```

---

## 6. Blueprint Revalidation Behavior

Both `preview()` and `apply()`:

1. Load Blueprint by ID filtered by authenticated workspace.
2. Verify not legacy format (`isLegacyFormat()` → `ProvisioningException(legacy_format)`).
3. Verify schema version is `1.0.0` (→ `ProvisioningException(unsupported_version)`).
4. Run `BlueprintValidator::validate()`.
5. If invalid → return `{status: "validation_failed", errors: [...], can_apply: false}`.
6. Controller returns HTTP 422 for validation failures.

---

## 7. Preview Behavior

- Revalidates Blueprint.
- Builds deterministic execution plan.
- Builds config mapping (WorkspaceConfiguration preview).
- **Idempotent**: Same workspace + blueprint + version → reuses existing preview run (update, not duplicate).
- Different version → deletes stale preview, creates new one.
- Returns: run_id, plan_summary, warnings, validation result, can_apply flag, config_mapping.
- Does NOT create entities, enable modules, or modify workspace.

---

## 8. Apply Preparation Behavior

- Revalidates Blueprint.
- **Idempotency**: Same blueprint already `applied` → returns existing result with `already_applied: true`.
- **Concurrency**: Active `prepared`/`processing` run → returns existing with `active_run: true` (HTTP 409).
- Uses `lockForUpdate()` to prevent race conditions.
- Captures rollback snapshot before any mutation.
- Creates `ProvisioningRun` with status `prepared`.
- Does NOT create entities, enable modules, or mark onboarding complete.
- Returns: run_id, plan_summary, warnings, message about pending entity creation.

---

## 9. Status Vocabulary

| Status | Meaning | Who sets it |
|--------|---------|------------|
| `preview` | Dry-run plan generation | `preview()` |
| `prepared` | Ready for entity provisioning, snapshot captured | `apply()` (1.6A) |
| `processing` | Entity creation in progress | Future (1.6B) |
| `applied` | Successfully provisioned | Future (1.6B) |
| `rolled_back` | Reverted to previous config | `rollback()` |
| `failed` | Error during provisioning | Future (1.6B) |

DB constraint updated: `CHECK (status IN ('preview', 'prepared', 'processing', 'applied', 'rolled_back', 'failed'))`

---

## 10. Idempotency Behavior

### Preview
- Same workspace + blueprint + version → reuse existing preview run (update config).
- Different version → replace stale preview.
- Never creates unlimited duplicates.

### Apply
- Same blueprint version already `applied` → return existing successful result.
- Same blueprint version `prepared`/`processing` → return active run (HTTP 409).
- New blueprint version → allowed to create new run.

---

## 11. Concurrency Protection

- `lockForUpdate()` on active `prepared`/`processing` runs inside DB transaction.
- Only one active apply run per workspace + blueprint at a time.
- No external distributed-lock infrastructure needed.

---

## 12. Rollback Snapshot Structure

```json
{
  "captured_at": "2026-07-16T17:07:07.013562Z",
  "workspace_configuration": {
    "enabled_modules": ["dashboard", "customers", ...],
    "role_configs": [],
    "pages": [],
    "workflows": [],
    "automations": [],
    "provisioning_run_id": null
  },
  "feature_flags": [
    {"feature_key": "dashboard", "is_enabled": true},
    ...
  ],
  "entity_counts": {
    "roles": 16,
    "departments": 6,
    "teams": 3,
    "warehouses": 2
  }
}
```

---

## 13. WorkspaceConfiguration Mapping

| Blueprint Source | WorkspaceConfiguration Field |
|-----------------|---------------------------|
| `modules[].key` (where enabled) | `enabled_modules` |
| `roles[]` (summary) | `role_configs` |
| N/A (Flutter-driven) | `pages` |
| `approval_workflows[]` (summary) | `workflows` |
| N/A | `automations` |
| Blueprint ID/version | `blueprint_meta` (in config_mapping) |

Config mapping is built but not persisted as final state — only stored in the preview/prepared run config for inspection.

---

## 14. Controller/API Behavior

| Route | Method | Behavior |
|-------|--------|----------|
| `/api/provisioning/preview` | POST | Revalidate + plan + idempotent preview run |
| `/api/provisioning/apply` | POST | Revalidate + prepare run with snapshot |
| `/api/provisioning/rollback` | POST | Restore from snapshot |
| `/api/provisioning/config` | GET | Current WorkspaceConfiguration |
| `/api/provisioning/modules` | PUT | Update module enablement (preserved) |
| `/api/provisioning/roles/{role}` | PUT | Update role config (preserved) |

### Error codes

| HTTP | Condition |
|------|-----------|
| 404 | Blueprint/run not found in workspace |
| 409 | Active apply run exists |
| 422 | Validation failure, legacy format, unsupported version |
| 401/403 | Authentication/permission (middleware) |

---

## 15. Tenant and Permission Checks

- Blueprint queries always filtered by `workspace_id` from authenticated context.
- Cross-workspace access → `ModelNotFoundException` → 404.
- Permission: `discovery.manage` (existing middleware on all provisioning routes).
- No role-name checks — only permission-based.

---

## 16. Failure Handling

- Validation failures → structured JSON, no ProvisioningRun created.
- `ProvisioningException` → error code + message, no stack trace in response.
- `ModelNotFoundException` → 404 with clean message.
- Blueprint remains unchanged after any failure.
- WorkspaceConfiguration unchanged after any failure.
- Onboarding completion unchanged.

---

## 17. Verification Scenarios and Results

| # | Scenario | Result |
|---|----------|--------|
| 1 | Automotive distribution preview | ✓ 2 locations, 2 warehouses, 5 roles, 14 modules, POS, approval, commission |
| 2 | Service company preview | ✓ No warehouses, no POS, has pipeline |
| 3 | Invalid Blueprint preview | ✓ Validation failed, no run created |
| 4 | Cross-workspace access | ✓ Blocked (404) |
| 5 | Repeated preview | ✓ Idempotent, same run_id, 1 preview row |
| 6 | Apply preparation | ✓ Status=prepared, plan_summary, repeated→409 |
| 7 | New Blueprint version | ✓ Separate run allowed |
| 8 | Rollback snapshot | ✓ workspace_configuration, feature_flags, entity_counts |
| 9 | Legacy format | ✓ Rejected with `legacy_format` error |
| 10 | Unsupported version | ✓ Rejected with `unsupported_version` error |
| 11 | Invalid Blueprint apply | ✓ Rejected, can_apply=false |
| 12 | Onboarding safety | ✓ Not modified by prepared run |

**Total: 45/45 passed, 0 failed.**

---

## 18. Demo Reset Result

```
Demo Reset Complete — 14 users, 13 memberships, 13 roles, 6 departments, 3 teams, 2 warehouses, 10 products
```

✓ Successful after all changes.

---

## 19. Remaining Limitations

1. **Entity provisioning not implemented** — `prepared` runs don't create departments, teams, roles, locations, warehouses, pipelines, workflows, or commissions.
2. **Module enablement not persisted** — `prepared` does not write to `WorkspaceConfiguration` or `WorkspaceFeatureFlag`.
3. **Onboarding not marked complete** — by design in 1.6A.
4. **`processing` status unused** — reserved for async provisioning in 1.6B.
5. **Rollback only covers config** — entity-level rollback (delete created entities) requires 1.6B.
6. **Business Template path unchanged** — `BusinessTemplateApplicationService` continues to work independently.

---

## 20. Exact Task 1.6B Scope

**Task 1.6B: Entity Provisioning Engine**

1. Transition `prepared` → `processing` → `applied`.
2. Create locations from `operations.locations`.
3. Create departments from `operations.departments`.
4. Create teams from `operations.teams`.
5. Create roles with permissions from `operations.roles`.
6. Create warehouses with location references from `operations.warehouses`.
7. Create pipelines and stages from `operations.pipelines`.
8. Create approval workflows from `operations.approval_workflows`.
9. Create commission rules from `operations.commission_rules`.
10. Enable modules in `WorkspaceFeatureFlag`.
11. Persist `WorkspaceConfiguration` with Blueprint metadata.
12. Mark onboarding complete.
13. Implement failure recovery → `failed` status with error capture.
14. Implement entity-level rollback.
15. Verify idempotency of full apply cycle.

---

## 21. Exact Files Expected to Change in Task 1.6B

| File | Change |
|------|--------|
| `app/Services/ProvisioningService.php` | Entity creation logic inside `apply()` |
| `app/Services/Provisioning/ProvisioningPlanBuilder.php` | Possible: entity creation helpers |
| `app/Services/Provisioning/EntityProvisioner.php` | New: actual entity creation orchestration |
| `app/Models/ProvisioningRun.php` | Possible: additional helper methods |
| `database/migrations/` | Possible: location or config table additions |

No Flutter changes. No Blueprint schema changes. No Discovery flow changes.
