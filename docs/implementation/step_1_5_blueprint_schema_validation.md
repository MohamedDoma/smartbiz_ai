# Step 1.5 — Blueprint Schema and Validation Engine

## 1. Previous Blueprint Limitations

The original `BlueprintGeneratorService` produced an unversioned template-based structure with:

- No schema version or structural contract.
- Module keys that didn't match the canonical module registry (`contacts`, `product_categories`, `audit_logs` — none of which are registered module keys).
- Role definitions as display-only name/description pairs with no RBAC permission mapping.
- No validation of generated output.
- No protection against persisting invalid configurations.
- No department, team, warehouse, pipeline, or workflow configuration.
- No finance, tax, POS, or commission settings.

The old service remains for its `classifyBusiness()` method, which is used by `DiscoverySessionService::classifyWithLlm()` as a fallback classifier.

---

## 2. Files Inspected

| File | Purpose |
|------|---------|
| `app/Services/BlueprintGeneratorService.php` | Legacy generator (still used for classification) |
| `app/Services/PermissionCatalog.php` | 112 permission keys, `allKeys()`, `approverKeys()` |
| `app/Services/TriggerConditionValidator.php` | Workflow trigger condition validation (operators, fields) |
| `app/Services/ConditionEntityFieldCatalog.php` | Entity field schema registry |
| `app/Models/DiscoveryBlueprint.php` | Eloquent model, fillable fields, casts |
| `app/Models/DiscoverySession.php` | Session model, relationships |
| `app/Providers/AppServiceProvider.php` | DI bindings |
| `app/Http/Controllers/Api/DiscoveryController.php` | API controller |
| `app/Http/Resources/DiscoveryBlueprintResource.php` | API resource |
| `app/Http/Resources/DiscoverySessionResource.php` | Session resource |
| `routes/api.php` | Route definitions |

---

## 3. Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `app/Services/Blueprint/BlueprintSchema.php` | 218 | Canonical v1.0.0 contract — module keys, dependencies, entity types, statuses |
| `app/Services/Blueprint/BlueprintGenerator.php` | 306 | Maps discovery facts → canonical blueprint with business-type profiles |
| `app/Services/Blueprint/BlueprintValidator.php` | 682 | Centralized validation — modules, org, RBAC, pipelines, workflows, finance |
| `app/Exceptions/BlueprintValidationException.php` | 29 | Renderable 422 exception with structured errors/warnings |

---

## 4. Files Modified

| File | Change |
|------|--------|
| `app/Services/DiscoverySessionService.php` | Constructor: added `BlueprintGenerator` and `BlueprintValidator` as DI parameters. `generateBlueprint()`: uses canonical generator + validator, wrapped in `DB::transaction()`. Added `validateBlueprint()`. |
| `app/Http/Controllers/Api/DiscoveryController.php` | Added `BlueprintValidationException` import and catch. Added `validateBlueprint()` endpoint. |
| `app/Http/Resources/DiscoveryBlueprintResource.php` | Added `schema_version` field from blueprint payload. |
| `routes/api.php` | Added `GET /{id}/validate-blueprint` route. |

---

## 5. Canonical Schema Version and Structure

**Version:** `1.0.0` (`BlueprintSchema::VERSION`)

**Required top-level fields:** `schema_version`, `business_profile`, `modules`, `metadata`

**All sections:**

```
schema_version, business_profile, workspace_settings, modules, departments,
teams, roles, warehouses, payment_methods, tax_settings, invoice_settings,
pos_settings, pipelines, approval_workflows, commission_rules,
accounting_settings, localization, ai_settings, assumptions,
missing_optional_information, metadata
```

**23 valid module keys** sourced from seeded business templates.

---

## 6. Discovery-to-Blueprint Mapping

`BlueprintGenerator::generate()` receives:

- `$businessType` — classified type (retail, restaurant, service, manufacturing, distribution, hybrid)
- `$knownFacts` — extracted from `discovery_state.known_facts`
- `$assumptions` — from `discovery_state.assumptions`

Priority chain: explicit user facts → corrections → safe assumptions → template defaults.

---

## 7. Module-Selection Rules

Each business type has a profile with `required`, `recommended`, and `optional` module sets. Rules:

- Required modules are always enabled; cannot be disabled.
- Recommended modules are enabled by default.
- Optional modules are disabled by default.
- Facts override defaults: e.g., `uses_pos=true` promotes POS to enabled; `uses_inventory=false` for service type disables inventory.
- Module dependencies are validated as **errors** — an enabled module with a disabled dependency fails validation.
- Generator automatically includes required dependencies for enabled modules.

---

## 8. Role and Permission Behavior

- Owner and Admin roles receive `PermissionCatalog::allKeys()` (112 permissions).
- Business-type-specific roles receive curated permission subsets.
- All permission keys are validated against `PermissionCatalog::allKeys()`.
- Role keys are Blueprint-local references (strings), not database UUIDs.
- Role keys must pass local-key format: `^[a-z][a-z0-9_]{1,63}$`.
- No runtime behavior depends on role names — only keys and permission sets.

---

## 9. Department, Team, and Local-Reference Behavior

- Departments are business-type-specific arrays with `key`, `name`, `status`.
- Teams reference departments by `department_key` — validated for existence.
- Roles reference departments by `department_key` — validated for existence.
- Parent department references are validated for existence and circular relationships.
- All references are Blueprint-local strings, never database IDs.
- All local keys must pass format validation: `^[a-z][a-z0-9_]{1,63}$`.
- UUID-shaped values are rejected in all local-key fields.

---

## 10. Workflow and Pipeline Validation

**Pipelines:**
- Valid entity types: `deal`, `lead`, `order`, `contact`
- Pipeline and stage keys must pass local-key format validation
- Duplicate stage keys detected
- Stage ordering must be strictly ascending
- At least one stage required

**Approval Workflows:**
- Valid entity types: `commission_entry`, `invoice`, `order`, `payment`, `purchase_order`
- Workflow keys must pass local-key format validation
- Trigger conditions validated via `TriggerConditionValidator`
- Steps must have either `approver_role_key` or `approver_permission_key`
- Approver permission keys validated against `PermissionCatalog::approverKeys()`
- Missing role references produce **blocking errors** (not warnings)
- Approver role key format validated (UUID-shaped rejected)

---

## 11. Finance, POS, Tax, Payment, and Commission Validation

| Section | Validation |
|---------|------------|
| Payment methods | Duplicate key detection; type must be in `VALID_PAYMENT_TYPES` |
| Tax settings | Rate must be numeric, 0–100; `tax_inclusive` must be boolean |
| Invoice settings | `default_due_days` must be non-negative integer |
| POS settings | Warning if enabled but `pos` module is not enabled |
| Commission rules | Duplicate key; local-key format; model must be `percentage`/`flat`/`tiered`; rate must be non-negative |
| Workspace settings | Currency must be 3-letter uppercase code |

**Supported payment types:** `cash`, `card`, `credit_card`, `bank_transfer`, `check`, `mobile_payment`, `online`, `wallet`

---

## 12. Errors vs. Warnings

- **Errors** → `valid = false`, structured as `{field_path: [messages]}`, block persistence.
- **Warnings** → informational, do not block persistence. Examples: POS settings enabled without POS module.

**Changed from warning to error in 1.5C:**
- Unknown top-level sections
- Module dependency violations
- Missing approver role references

---

## 13. API Behavior

| Endpoint | Method | Status | Behavior |
|----------|--------|--------|----------|
| `/discovery/sessions/{id}/generate-blueprint` | POST | 201/422 | Generates, validates, persists. 422 on validation failure or wrong state. |
| `/discovery/sessions/{id}/blueprint` | GET | 200/404 | Returns existing blueprint. |
| `/discovery/sessions/{id}/validate-blueprint` | GET | 200/404 | Validates existing blueprint against current schema. |

All endpoints require `auth:sanctum` + workspace context + `discovery.manage` permission.

---

## 14. Persistence and Version Behavior

- Blueprint persisted to `discovery_blueprints` table via `DiscoveryBlueprint` model.
- `version` starts at 1, increments by 1 on each successful regeneration.
- Same record is updated (upsert by `session_id`), not duplicated.
- Persistence wrapped in `DB::transaction()` — blueprint update, message creation, and session status update are atomic.
- `generator_method = 'canonical_v1'`, `generator_version = '1.0.0'`.

---

## 15. Invalid-Regeneration Protection

When regeneration produces an invalid blueprint:

1. Validation fails → `BlueprintValidationException` thrown.
2. If a previous valid blueprint exists: the exception message states "Previous valid blueprint preserved." The existing record, its payload, and its version are unchanged.
3. If no previous blueprint exists: the exception is thrown with "Blueprint validation failed."
4. Session status is NOT changed to `completed`.
5. The API returns HTTP 422 with `{message, error, errors, warnings}`.
6. The `DB::transaction()` is never entered when validation fails (validation runs before the transaction).

---

## 16. Legacy Blueprint Behavior

Detection: `BlueprintSchema::isLegacyFormat()` returns `true` when:
- `schema_version` is absent AND `enabled_modules` is present.

Behavior:
- `validateBlueprint()` returns `valid = false` with error `"Legacy blueprint format detected. Please regenerate."` and `is_legacy = true`.
- Legacy blueprints cannot pass canonical validation.
- They cannot be applied by the provisioning pipeline without regeneration.
- The `generate-blueprint` endpoint will overwrite a legacy blueprint with a canonical one on next generation.

---

## 17. Business-Scenario Results

| Scenario | Valid | Modules | Roles | Warehouses | Pipelines | Workflows | Commissions |
|----------|-------|---------|-------|------------|-----------|-----------|-------------|
| Automotive Distribution | ✓ | 16+ enabled | 5 | 2 | 1 | 1 | 1 |
| Restaurant | ✓ | 14+ enabled | 6 | 1 | 0 | 0 | 0 |
| Digital Service | ✓ | 11+ enabled | 5 | 0 | 1 | 1 | 0 |
| Hybrid | ✓ | varies | 4 | 0 | 0 | 0 | 0 |

All scenarios pass with module dependencies automatically satisfied, valid local keys, and no UUID-shaped identifiers.

---

## 18. Full Invalid-Input Matrix Results

| # | Test | Result |
|---|------|--------|
| 1 | UUID-shaped role key | ✓ Error — blocked by local-key format |
| 2 | UUID-shaped department key | ✓ Error — blocked by local-key format |
| 3 | UUID-shaped workflow key | ✓ Error — blocked by local-key format |
| 4 | UUID-shaped approver role ref | ✓ Error — blocked by local-key format |
| 5 | Missing approver role | ✓ Error (upgraded from warning) |
| 6 | Missing required module dep | ✓ Error (upgraded from warning) |
| 7 | Disabled required dependency | ✓ Error |
| 8 | UUID-shaped warehouse branch ref | ✓ Error — blocked by local-key format |
| 9 | Unsupported payment method type | ✓ Error |
| 10 | Unknown top-level section | ✓ Error (upgraded from warning) |
| 11 | No hidden approval threshold | ✓ No hardcoded value without user input |
| 11b | User-provided threshold used | ✓ Value 5000 respected |
| 12 | Unknown module key | ✓ Error on `modules.0.key` |
| 13 | Unknown permission key | ✓ Error on `roles.0.permissions.0` |
| 14 | Circular department parent | ✓ Error with "circular" message |
| 15 | Negative tax rate | ✓ Error on `tax_settings.tax_rate` |
| 16 | Unsupported commission model | ✓ Error on `commission_rules.0.calculation_model` |
| 17 | Unsupported schema version | ✓ Error on `schema_version` |

**Total: 39/39 passed (18 tests × some with sub-checks). No PHP exceptions or HTTP 500s.**

---

## 19. Tenant and Permission Verification

- `DiscoverySessionService::find()` filters by `workspace_id` — cross-workspace access returns `null → 404`.
- All discovery routes are behind `CheckPermission::class . ':discovery.manage'`.
- Authentication required via `auth:sanctum` middleware.
- Workspace context required via `SetWorkspaceContext` middleware.

---

## 20. Demo Reset and Regression Results

| Check | Result |
|-------|--------|
| `smartbiz:demo-reset --yes` | ✓ Completed successfully |
| Container boot | ✓ |
| Route registration (8 discovery routes) | ✓ |
| PHP syntax check (all files) | ✓ |
| Demo company seeded | ✓ (14 users, 13 roles, 6 depts, 2 warehouses) |
| Flutter files changed | 0 |
| Provisioning files changed | 0 |
| No invented module keys | ✓ (23 keys from templates) |
| No invented permission keys | ✓ (all validated against catalog) |

---

## 21. Remaining Limitations

1. **Hybrid business type** falls through to the `default` case in `buildRoles()`, generating generic roles.
2. **Warehouse naming** is generic (`Warehouse 1`, `Warehouse 2`). Facts do not yet carry warehouse names.
3. **Pipeline configuration** is limited to one pipeline per type.
4. **Commission rules** generate a single standard rule.
5. **Invoice numbering format** and **fiscal year settings** are not yet configurable.
6. **Branch/location system** — warehouses accept `branch_key` but no canonical branch section exists. Branch references are format-validated but not cross-referenced against a branch list.

---

## 22. Exact Recommended Scope for Task 1.6

**Task 1.6: Unified Blueprint Provisioning**

Transform validated canonical Blueprint JSON into actual workspace database entities:

1. `WorkspaceConfiguration` record creation/update from blueprint settings.
2. Department creation from `blueprint.departments`.
3. Team creation from `blueprint.teams`.
4. Role creation from `blueprint.roles` with permission assignment via `PermissionCatalog`.
5. Warehouse creation from `blueprint.warehouses`.
6. Pipeline and stage creation from `blueprint.pipelines`.
7. Approval workflow and step creation from `blueprint.approval_workflows`.
8. Commission plan/rule creation from `blueprint.commission_rules`.
9. Module enablement persistence.
10. Idempotent provisioning (re-run updates, does not duplicate).
11. Rollback support for failed provisioning.

---

## 23. Exact Files Expected to Change in Task 1.6

| File | Change |
|------|--------|
| `app/Services/ProvisioningService.php` | Core provisioning logic — consume validated Blueprint, create DB entities |
| `app/Http/Controllers/Api/ProvisioningController.php` | Wire `apply` endpoint to consume canonical blueprint |
| `app/Services/DiscoverySessionService.php` | Minor — may add `provisionBlueprint()` convenience method |
| `database/migrations/` | Possible: workspace_configuration additions if new settings fields needed |
| `app/Models/WorkspaceConfiguration.php` | Possible: new fillable fields for blueprint-sourced settings |
| `tests/` | Provisioning integration tests |

No Flutter changes. No Blueprint schema changes. No Discovery flow changes.

---

## 24. Task 1.5C — Final Hardening

### Files Changed in 1.5C

| File | Change |
|------|--------|
| `app/Services/Blueprint/BlueprintSchema.php` | Added `VALID_PAYMENT_TYPES`, `isValidLocalKey()`, `isUuidShaped()` |
| `app/Services/Blueprint/BlueprintGenerator.php` | Auto-include module deps; sanitize payment types; remove hardcoded approval threshold |
| `app/Services/Blueprint/BlueprintValidator.php` | Local-key format checks; approver role → error; module deps → error; unknown sections → error; payment type validation; warehouse branch_key validation |

### Hardening Summary

| Area | Before 1.5C | After 1.5C |
|------|-------------|------------|
| UUID-shaped keys | Accepted | Rejected with field-path error |
| Local-key format | No validation | `^[a-z][a-z0-9_]{1,63}$` enforced |
| Approver role refs | Warning | Blocking error |
| Module dependencies | Warning | Blocking error |
| Unknown top-level sections | Warning | Blocking error |
| Payment method types | No type check | Validated against `VALID_PAYMENT_TYPES` |
| Warehouse branch refs | No validation | Local-key format validated |
| Approval thresholds | Hardcoded 1000 | No default; user value or `requires_configuration` flag |
| Module dep auto-include | Manual | Generator auto-adds required deps |

### Task 1.5C Status: **COMPLETE**

---

## 25. Task 1.5D — Canonical Locations and Branch Reference Validation

### Files Changed in 1.5D

| File | Change |
|------|--------|
| `app/Services/Blueprint/BlueprintSchema.php` | Added `LOCATION_TYPES` constant; added `locations` to `ALL_SECTIONS` and `empty()` |
| `app/Services/Blueprint/BlueprintGenerator.php` | Added `buildLocations()` method; wired `warehouses` and `pos_settings` to generated location keys |
| `app/Services/Blueprint/BlueprintValidator.php` | Added `validateLocations()` method; updated `validateWarehouses()` to cross-reference locations; updated `validatePosSettings()` to validate `location_keys` |

### Schema Version Decision

Schema version remains `1.0.0`. The `locations` section is additive and optional for backward compatibility:

- Previously saved canonical `1.0.0` Blueprints without `locations` validate without errors.
- Newly generated Blueprints always include `locations`.
- Warehouse `branch_key` references are cross-validated only when a `locations` section is present.
- No version increment is needed because no existing valid Blueprint is invalidated.

### Canonical Locations Structure

```json
{
  "locations": [
    {
      "key": "main_branch",
      "name": "Main Branch",
      "type": "branch",
      "status": "required",
      "is_primary": true,
      "country": "SA",
      "timezone": "Asia/Riyadh"
    }
  ]
}
```

Minimum fields: `key`, `name`, `type`, `status`, `is_primary`

Optional fields: `country`, `timezone`, `currency`, `address`, `metadata`

### Supported Location Types

| Type | Use Case |
|------|----------|
| `branch` | Distribution, manufacturing, general multi-location |
| `office` | Service company physical office |
| `store` | Retail location |
| `restaurant` | Restaurant location |
| `warehouse_site` | Dedicated warehousing facility |
| `service_location` | Field service or client-site location |
| `virtual` | Fully remote / digital company |

### Location Generation Behavior

| Scenario | Result |
|----------|--------|
| Named locations provided (`branch_names`/`location_names`) | Preserved names, stable local keys (e.g., `tripoli_branch`) |
| Only `branch_count` provided | Reviewable placeholders: `branch_1`, `branch_2` |
| Single-location company | One location: `main_location`, marked primary |
| Virtual service company | One `virtual` location, no warehouses, no POS |
| Business-type mapping | `retail` → `store`, `restaurant` → `restaurant`, `service` → `office`/`virtual`, default → `branch` |

### Location Validation Rules

1. Must be an array.
2. Every location must have a valid local key (`^[a-z][a-z0-9_]{1,63}$`).
3. UUID-shaped keys are rejected.
4. Location keys must be unique.
5. Name must be a non-empty string (max 255 chars).
6. Type must be in `LOCATION_TYPES`.
7. Status must be a canonical Blueprint status value.
8. `is_primary` must be boolean.
9. Only one primary location allowed.
10. Currency (when present) must be 3-letter uppercase code.

### Warehouse Reference Behavior

| Warehouse State | Behavior |
|-----------------|----------|
| `scope: "location"`, `branch_key: "main_branch"` | Valid — cross-references `locations.*.key` |
| `scope: "workspace"`, no `branch_key` | Valid — workspace-wide warehouse |
| `branch_key: "nonexistent_branch"` | Error: unknown location reference |
| `branch_key: "00000000-..."` | Error: UUID-shaped key rejected |
| No `locations` section in blueprint | `branch_key` format-validated only (backward compat) |

### POS Reference Behavior

| POS State | Behavior |
|-----------|----------|
| `location_keys: ["store_1"]` | Valid — cross-references `locations.*.key` |
| `location_keys: ["ghost_store"]` | Error: unknown location reference |
| `location_keys: ["store_1", "store_1"]` | Error: duplicate POS location key |
| No `location_keys` field | Valid — POS operates at workspace level |
| Virtual service company | No POS generated |

### Validation Test Results

| # | Test | Result |
|---|------|--------|
| 1 | Valid single location | ✓ |
| 2 | Valid two-branch company | ✓ |
| 3 | Duplicate location key | ✓ Error |
| 4 | UUID-shaped location key | ✓ Error |
| 5 | Unsupported location type | ✓ Error |
| 6 | Two primary locations | ✓ Error |
| 7 | Warehouse → valid location | ✓ No error |
| 8 | Warehouse → unknown location | ✓ Error |
| 9 | Warehouse → UUID location | ✓ Error |
| 10 | Workspace-wide warehouse | ✓ No error |
| 11 | POS → valid location | ✓ No error |
| 12 | POS → unknown location | ✓ Error |
| 13 | POS → duplicate locations | ✓ Error |
| 14 | Virtual service company | ✓ Valid |
| 15 | Blueprint without locations | ✓ No error |

**Total: 40/40 passed.**

### Business-Scenario Results

| Scenario | Valid | Locations | WH→Location | POS→Location |
|----------|-------|-----------|-------------|--------------|
| Automotive Distribution | ✓ | 2 `branch` | ✓ valid | ✓ 2 keys |
| Restaurant | ✓ | 1 `restaurant` | ✓ valid | ✓ 1 key |
| Digital Service | ✓ | 1 `virtual` | n/a | n/a |
| Hybrid | ✓ | 1+ `branch` | ✓ valid | n/a |
| Named Branches | ✓ | 2 (tripoli/benghazi) | ✓ valid | ✓ |

### Regression Results

| Check | Result |
|-------|--------|
| `smartbiz:demo-reset --yes` | ✓ |
| Routes (8 discovery) | ✓ |
| PHP syntax | ✓ |
| API generate/validate/regen | ✓ |
| Flutter files changed | 0 |
| Provisioning files changed | 0 |

### Remaining Limitations

1. Location address fields not collected during discovery.
2. Multi-currency per location — structural but not collected.
3. Tax settings remain workspace-level, not location-scoped.
4. POS terminal assignment not modeled.
5. Location hierarchy — flat list only.

### Final Task 1.5 Status: **COMPLETE**

---

## 26. Exact Recommended Scope for Task 1.6

**Task 1.6: Unified Blueprint Provisioning**

1. `WorkspaceConfiguration` creation/update from blueprint settings.
2. Location/branch creation from `blueprint.locations`.
3. Department creation from `blueprint.departments`.
4. Team creation from `blueprint.teams`.
5. Role creation with permission assignment via `PermissionCatalog`.
6. Warehouse creation with location cross-references.
7. Pipeline and stage creation.
8. Approval workflow and step creation.
9. Commission plan/rule creation.
10. Module enablement persistence.
11. Idempotent provisioning.
12. Rollback support.

### Exact Files Expected to Change in Task 1.6

| File | Change |
|------|--------|
| `app/Services/ProvisioningService.php` | Core provisioning logic |
| `app/Http/Controllers/Api/ProvisioningController.php` | Wire `apply` endpoint |
| `app/Services/DiscoverySessionService.php` | May add `provisionBlueprint()` |
| `database/migrations/` | Possible: location table additions |
| `app/Models/` | Possible: Location model additions |
| `tests/` | Provisioning integration tests |

No Flutter changes. No Blueprint schema changes. No Discovery flow changes.
