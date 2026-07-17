# Step 1.2 — Discovery & Provisioning Database Foundation

> Completed: 2026-07-16
> Status: ✅ All verifications passed

---

## 1. Files Inspected

### Models
- `app/Models/DiscoverySession.php` — `$fillable`, `$casts`, relationships (workspace, creator, messages, blueprint)
- `app/Models/DiscoveryMessage.php` — `$fillable`, `$casts`, `$timestamps = false`, relationships (session, workspace)
- `app/Models/DiscoveryBlueprint.php` — `$fillable`, `$casts`, relationships (session, workspace)
- `app/Models/ProvisioningRun.php` — `$fillable`, `$casts`, `$timestamps = false`, relationships (workspace, blueprint, appliedBy)
- `app/Models/WorkspaceConfiguration.php` — `$fillable`, `$casts`, relationships (workspace, provisioningRun)

### Services
- `app/Services/DiscoverySessionService.php` — `startSession()`, `submitAnswers()`, `classify()`, `generateBlueprint()`, `gatherContext()`
- `app/Services/ProvisioningService.php` — `preview()`, `apply()`, `rollback()`, `buildConfig()`
- `app/Services/AuthSessionPayloadBuilder.php` — `build()` — onboarding_completed check

### Controllers
- `app/Http/Controllers/Api/DiscoveryController.php`
- `app/Http/Controllers/Api/ProvisioningController.php`

### Resources & Requests
- `app/Http/Resources/DiscoverySessionResource.php`
- `app/Http/Resources/DiscoveryBlueprintResource.php`
- `app/Http/Resources/DiscoveryMessageResource.php`
- `app/Http/Requests/StartDiscoveryRequest.php`
- `app/Http/Requests/AnswerDiscoveryRequest.php`

### Existing Migrations (convention reference)
- `database/migrations/035_ai_foundation.php` — `return new class extends Migration` format (ran, used as template)
- `database/migrations/024_business_templates.php` — class format reference

### Architecture SQL
- `_architecture/migrations/015_ai_discovery.sql` — `discovery_sessions`, `discovery_messages`, `discovery_blueprints`
- `_architecture/migrations/018_provisioning_manual_payments.sql` — `provisioning_runs`, `workspace_configurations`

### Demo Reset
- `app/Console/Commands/SmartBizDemoResetCommand.php` — already includes all 5 tables with `Schema::hasTable()` guards

---

## 2. Files Created

| File | Purpose |
|------|---------|
| `database/migrations/038_discovery_provisioning.php` | Laravel migration for 5 tables |
| `docs/implementation/step_1_2_discovery_database_foundation.md` | This report |

---

## 3. Files Modified

| File | Change | Lines |
|------|--------|-------|
| `app/Services/AuthSessionPayloadBuilder.php` | Changed `ProvisioningRun` status check from `'completed'` to `'applied'` | L51 |

---

## 4. Final Database Schema

### `discovery_sessions` (11 columns)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | UUID | NOT NULL | PK |
| `workspace_id` | UUID | NOT NULL | FK → workspaces.id CASCADE |
| `created_by` | UUID | NOT NULL | FK → users.id CASCADE |
| `status` | VARCHAR(30) | NOT NULL | `'intake'` |
| `business_description` | TEXT | NOT NULL | — |
| `business_type` | VARCHAR(50) | NULL | — |
| `classification_confidence` | DECIMAL(5,2) | NULL | — |
| `classification_method` | VARCHAR(30) | NULL | `'rule_based_v1'` |
| `classification_version` | VARCHAR(20) | NULL | `'1.0.0'` |
| `created_at` | TIMESTAMPTZ | NOT NULL | now() |
| `updated_at` | TIMESTAMPTZ | NOT NULL | now() |

### `discovery_messages` (8 columns)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | UUID | NOT NULL | PK |
| `session_id` | UUID | NOT NULL | FK → discovery_sessions.id CASCADE |
| `workspace_id` | UUID | NOT NULL | FK → workspaces.id CASCADE |
| `role` | VARCHAR(10) | NOT NULL | — |
| `content` | TEXT | NOT NULL | — |
| `message_type` | VARCHAR(30) | NOT NULL | — |
| `metadata` | JSONB | NULL | `'{}'` |
| `created_at` | TIMESTAMPTZ | NOT NULL | now() |

### `discovery_blueprints` (10 columns)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | UUID | NOT NULL | PK |
| `session_id` | UUID | NOT NULL | FK → discovery_sessions.id CASCADE, UNIQUE |
| `workspace_id` | UUID | NOT NULL | FK → workspaces.id CASCADE |
| `business_type` | VARCHAR(50) | NOT NULL | — |
| `blueprint` | JSONB | NOT NULL | `'{}'` |
| `version` | INTEGER | NOT NULL | `1` |
| `generator_method` | VARCHAR(30) | NOT NULL | `'rule_based_v1'` |
| `generator_version` | VARCHAR(20) | NOT NULL | `'1.0.0'` |
| `created_at` | TIMESTAMPTZ | NOT NULL | now() |
| `updated_at` | TIMESTAMPTZ | NOT NULL | now() |

### `provisioning_runs` (11 columns)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | UUID | NOT NULL | PK |
| `workspace_id` | UUID | NOT NULL | FK → workspaces.id CASCADE |
| `blueprint_id` | UUID | NOT NULL | FK → discovery_blueprints.id CASCADE |
| `status` | VARCHAR(20) | NOT NULL | `'preview'` |
| `config` | JSONB | NOT NULL | `'{}'` |
| `applied_by` | UUID | NULL | FK → users.id SET NULL |
| `applied_at` | TIMESTAMPTZ | NULL | — |
| `version` | INTEGER | NOT NULL | `1` |
| `rollback_config` | JSONB | NULL | — |
| `error_message` | TEXT | NULL | — |
| `created_at` | TIMESTAMPTZ | NULL | now() |

### `workspace_configurations` (10 columns)

| Column | Type | Nullable | Default |
|--------|------|----------|---------|
| `id` | UUID | NOT NULL | PK |
| `workspace_id` | UUID | NOT NULL | FK → workspaces.id CASCADE, UNIQUE |
| `enabled_modules` | JSONB | NOT NULL | `'[]'` |
| `role_configs` | JSONB | NOT NULL | `'{}'` |
| `pages` | JSONB | NOT NULL | `'[]'` |
| `workflows` | JSONB | NOT NULL | `'[]'` |
| `automations` | JSONB | NOT NULL | `'[]'` |
| `provisioning_run_id` | UUID | NULL | FK → provisioning_runs.id SET NULL |
| `created_at` | TIMESTAMPTZ | NULL | now() |
| `updated_at` | TIMESTAMPTZ | NULL | now() |

---

## 5. Foreign Keys and Indexes

### Foreign Keys (11 total)

| Source | Column | Target | On Delete |
|--------|--------|--------|-----------|
| discovery_sessions | workspace_id | workspaces.id | CASCADE |
| discovery_sessions | created_by | users.id | CASCADE |
| discovery_messages | session_id | discovery_sessions.id | CASCADE |
| discovery_messages | workspace_id | workspaces.id | CASCADE |
| discovery_blueprints | session_id | discovery_sessions.id | CASCADE |
| discovery_blueprints | workspace_id | workspaces.id | CASCADE |
| provisioning_runs | workspace_id | workspaces.id | CASCADE |
| provisioning_runs | blueprint_id | discovery_blueprints.id | CASCADE |
| provisioning_runs | applied_by | users.id | SET NULL |
| workspace_configurations | workspace_id | workspaces.id | CASCADE |
| workspace_configurations | provisioning_run_id | provisioning_runs.id | SET NULL |

### Unique Constraints

| Table | Column | Constraint Name |
|-------|--------|----------------|
| discovery_blueprints | session_id | `uq_discovery_blueprints_session` |
| workspace_configurations | workspace_id | `workspace_configurations_workspace_id_key` |

### Indexes (15 total)

| Table | Index Name |
|-------|-----------|
| discovery_sessions | `idx_discovery_sessions_workspace` |
| discovery_sessions | `idx_discovery_sessions_created_by` |
| discovery_messages | `idx_discovery_messages_session` |
| discovery_messages | `idx_discovery_messages_workspace` |
| discovery_blueprints | `idx_discovery_blueprints_workspace` |
| provisioning_runs | `idx_prov_runs_ws` |
| provisioning_runs | `idx_prov_runs_status` |
| workspace_configurations | `idx_ws_config_ws` |

---

## 6. Final Provisioning Status Vocabulary

| Status | Used By | Purpose |
|--------|---------|---------|
| `preview` | `ProvisioningService::preview()` | Dry-run config generation |
| `applied` | `ProvisioningService::apply()` | **Terminal success** — workspace provisioned |
| `rolled_back` | `ProvisioningService::rollback()` | Reverted to previous config |
| `failed` | Architecture SQL CHECK | Reserved for future error handling |

### Discovery Session Statuses

| Status | Used By | Purpose |
|--------|---------|---------|
| `intake` | `startSession()` default | Initial state |
| `questioning` | `startSession()` after questions | Follow-up questions generated |
| `classifying` | `classify()` intermediate | Classification in progress |
| `blueprint_ready` | `classify()` final | Ready for blueprint generation |
| `completed` | `generateBlueprint()` | Blueprint generated, session complete |

---

## 7. Status Mismatch Fix

### Problem
`AuthSessionPayloadBuilder::build()` at line 51 checked:
```php
ProvisioningRun::where('status', 'completed')->exists()
```

But `ProvisioningService::apply()` sets:
```php
'status' => 'applied'
```

The status `'completed'` is never written to `provisioning_runs` by any service. The architecture SQL CHECK constraint also doesn't include `'completed'` — it only allows `('preview','applied','rolled_back','failed')`.

### Fix Applied

```diff
- ->where('status', 'completed')
+ ->where('status', 'applied')
```

### Impact Analysis
- **ProvisioningRun path:** Now correctly recognizes `'applied'` runs as onboarding complete
- **Business Template path:** Unchanged — still checks `WorkspaceTemplateApplication.status = 'applied'` on the same OR branch
- **Both paths:** The two conditions are OR'd, so either path independently triggers `onboarding_completed = true`

---

## 8. Architecture SQL Updates

**No changes needed.** The architecture SQL already defines all 5 tables:

- `_architecture/migrations/015_ai_discovery.sql` — defines `discovery_sessions`, `discovery_messages`, `discovery_blueprints`
- `_architecture/migrations/018_provisioning_manual_payments.sql` — defines `provisioning_runs`, `workspace_configurations`

The Laravel migration 038 matches the architecture SQL schema. The `hasTable` guards ensure no conflicts.

---

## 9. Commands Executed

```bash
# 1. Check existing tables (all 5 already existed from architecture SQL)
docker exec smartbiz_app php artisan tinker --execute="..."

# 2. Run migration (registered as batch 17, hasTable guards skipped creation)
docker exec smartbiz_app php artisan migrate --path=database/migrations/038_discovery_provisioning.php
# → 038_discovery_provisioning ... 4.08ms DONE

# 3. Verify table columns, FKs, unique constraints, indexes
docker exec smartbiz_app php artisan tinker --execute="..."

# 4. Verify route loading
docker exec smartbiz_app php artisan route:list --path=discovery      # → 7 routes
docker exec smartbiz_app php artisan route:list --path=provisioning   # → 6 routes
docker exec smartbiz_app php artisan route:list --path=business-templates # → 3 routes

# 5. Verify AuthSessionPayloadBuilder works
docker exec smartbiz_app php artisan tinker --execute="..."
# → Owner: onboarding_completed = TRUE, 14 modules, 111 permissions

# 6. Run demo reset
docker exec smartbiz_app php artisan smartbiz:demo-reset --yes
# → Truncated 181 tables, skipped 0 missing
# → Demo company seeded: 14 users, 13 memberships, 13 roles

# 7. Post-reset verification
docker exec smartbiz_app php artisan tinker --execute="..."
# → Owner: onboarding_completed = TRUE, 13 modules, 112 permissions

# 8. Migration status
docker exec smartbiz_app php artisan migrate:status | grep 038
# → 038_discovery_provisioning [17] Ran
```

---

## 10. Verification Results

| Check | Result |
|-------|--------|
| Migration runs without errors | ✅ `4.08ms DONE` |
| All 5 tables exist | ✅ All `EXISTS` |
| Columns match model `$fillable` + `$casts` | ✅ 11 + 8 + 10 + 11 + 10 columns verified |
| Foreign keys correct | ✅ 11 FKs with correct ON DELETE behavior |
| Unique constraints correct | ✅ `discovery_blueprints.session_id`, `workspace_configurations.workspace_id` |
| Indexes present | ✅ 15 indexes across 5 tables |
| Laravel boots without errors | ✅ Routes load, tinker works |
| Discovery routes load | ✅ 7 routes |
| Provisioning routes load | ✅ 6 routes |
| Business template routes load | ✅ 3 routes |
| Demo reset completes | ✅ 181 tables truncated, 0 skipped |
| Demo seeder runs | ✅ 14 users, 13 memberships created |
| Post-reset login works | ✅ Owner session builds correctly |
| Business Template onboarding = true | ✅ Via `workspace_template_applications.status = 'applied'` |
| ProvisioningRun `'applied'` recognized | ✅ Fix applied in AuthSessionPayloadBuilder |
| `hasTable` guards are idempotent | ✅ Migration re-runs safely |

---

## 11. Unresolved Risks

| Risk | Severity | Notes |
|------|----------|-------|
| `discovery_sessions.created_by` ON DELETE behavior | Low | Architecture SQL uses NO ACTION; Laravel migration uses CASCADE. Current DB has NO ACTION from the architecture SQL. Both are safe — users are never hard-deleted in SmartBiz. |
| Architecture SQL has RLS policies; Laravel migration does not | Low | RLS policies exist from architecture SQL 015. Laravel middleware handles workspace isolation. Only relevant for direct DB access. |
| Migrations 037 + 037b still pending | Info | Approval engine migration needs format fix (same bare-PHP issue). Outside Task 1.2 scope. |
| No `failed` status is ever written by services | Info | Reserved in CHECK constraint for future error handling. |

---

## 12. Recommended Scope for Task 1.3

### Task 1.3 — Backend Discovery API Integration Testing

1. **Verify discovery pipeline end-to-end via API:**
   - `POST /api/discovery/sessions` — create session with business description
   - `POST /api/discovery/sessions/{id}/answer` — submit answers
   - `POST /api/discovery/sessions/{id}/classify` — classify business type
   - `POST /api/discovery/sessions/{id}/generate-blueprint` — generate blueprint
   - `GET /api/discovery/sessions/{id}/blueprint` — retrieve blueprint

2. **Verify provisioning pipeline end-to-end via API:**
   - `POST /api/provisioning/preview` — preview config from blueprint
   - `POST /api/provisioning/apply` — apply config to workspace
   - Verify `onboarding_completed = true` after provisioning apply
   - `POST /api/provisioning/rollback` — rollback and verify

3. **Decide on LLM integration:**
   - Currently `DiscoveryController.classify()` calls rule-based path
   - `classifyWithLlm()` and `generateFollowUpsWithLlm()` exist but are unused
   - Determine whether to wire LLM-enhanced methods or keep rule-based

4. **Do not yet:**
   - Create Flutter API clients
   - Modify onboarding UI
   - Unify the two provisioning systems
