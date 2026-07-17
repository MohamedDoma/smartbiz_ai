# Step 1.6D — Onboarding Finalization

**Status**: ✅ Complete  
**Date**: 2026-07-17  
**Scope**: Status migration · Finalize endpoint · Event dispatch · Verification

---

## 1. Status Migration

**File**: `database/migrations/2026_07_17_050000_add_onboarding_complete_to_provisioning_runs_status.php`

Expands the PostgreSQL `CHECK` constraint on `provisioning_runs.status` to include `onboarding_complete`. The migration is idempotent — it inspects `pg_get_constraintdef()` before acting.

Allowed values after migration:

| Status | Description |
|---|---|
| `preview` | Dry-run plan generated |
| `prepared` | Plan validated and staged |
| `processing` | Entities being created |
| `foundation_applied` | Core entities committed |
| `applied` | Full operational apply complete |
| `onboarding_complete` | **New** — finalization done |
| `rolled_back` | Entities reverted |
| `failed` | Apply/rollback error |

---

## 2. Finalize Endpoint

**Route**: `POST /api/provisioning/{run}/finalize`  
**Permission**: `discovery.manage`  
**Controller**: `ProvisioningController::finalize()`  
**Service**: `ProvisioningService::finalize(string $workspaceId, string $runId, string $userId)`

### Owner Membership Resolution

The workspace owner is identified as the earliest-created active membership in `workspace_memberships`, consistent with `SendTrialEndingEmails` and session-builder conventions.

### Primary-Owner Role Binding

The primary owner role is resolved dynamically:

1. Read `config.operations.roles` from the provisioning run
2. Find the role entry with `is_primary_owner: true`
3. Resolve the role entity ID via `provisioning_entity_bindings` (key → UUID)
4. Verify the role entity exists in `roles`

No hardcoded role key is used.

### Role Assignment

Creates a `membership_roles` record linking the owner membership to the primary-owner role with `is_primary = true`. If the assignment already exists, ensures `is_primary` is set.

---

## 3. Idempotency

A pre-transaction check queries for the run in `onboarding_complete` status. If found, returns immediately with `already_finalized: true` — no side effects, no event dispatch, no transaction opened.

---

## 4. Concurrency Locking

Inside the transaction:

- `provisioning_runs` row locked with `lockForUpdate()`
- `workspaces` row locked with `lockForUpdate()`

This prevents concurrent finalization attempts from producing duplicate role assignments or double state transitions.

---

## 5. Event Dispatch

**Event**: `App\Events\WorkspaceOnboardingCompleted`

| Property | Type | Description |
|---|---|---|
| `workspaceId` | `string` | Workspace UUID |
| `provisioningRunId` | `string` | Run UUID |
| `finalizedBy` | `string` | Acting user UUID |
| `finalizedAt` | `string` | ISO 8601 timestamp |

**Dispatch rules**:

- Fired **after** `DB::transaction()` returns successfully
- Fired **exactly once** — the idempotent early-return path never reaches the dispatch call
- No test-only behavior exposed through the API

---

## 6. Authorization & Failure Cases

| Scenario | Error Code | HTTP |
|---|---|---|
| Run not found in workspace | `run_not_found` | 404 |
| Run not in `applied` status | `invalid_status_transition` | 409 |
| Workspace not found | `workspace_not_found` | 404 |
| No `is_primary_owner` role in blueprint | `missing_primary_owner_role` | 422 |
| Role binding missing | `missing_role_binding` | 422 |
| Bound role entity deleted | `missing_bound_entity` | 409 |
| No active membership | `no_active_membership` | 422 |
| Internal error | `internal_error` | 500 |

---

## 7. Verification Results

```
Onboarding finalization suite:   32/32 passed (100%)
Operational regression (1.6C):   10/10 passed (100%)
Provenance regression (1.6B):    14/14 passed (100%)
Demo reset:                      SUCCESS
Final migration:                 Nothing to migrate
```

---

## 8. Files Changed

| File | Change |
|---|---|
| `database/migrations/2026_07_17_050000_...` | CHECK constraint expansion |
| `app/Events/WorkspaceOnboardingCompleted.php` | New event class |
| `app/Services/ProvisioningService.php` | Event import + post-commit dispatch |
| `tests/onboarding_finalization_verification.php` | Standalone bootstrap + event/constraint tests |

Files unchanged from previous checkpoint (already implemented):

| File | Content |
|---|---|
| `app/Models/ProvisioningRun.php` | `STATUS_ONBOARDING_COMPLETE` + transitions |
| `app/Services/ProvisioningService.php` | `finalize()` core logic |
| `app/Http/Controllers/Api/ProvisioningController.php` | `finalize()` action |
| `routes/api.php` | `POST /{run}/finalize` route |

---

## 9. Remaining Step 1.7 Scope

Step 1.7 covers the **Flutter onboarding wizard integration**:

- Connect Flutter `OnboardingBloc` to the finalize endpoint
- Handle the `onboarding_complete` session flag in the auth payload
- Redirect to the main dashboard after finalization succeeds
- Display error states for finalization failures
- Update `AuthSessionPayloadBuilder` to include finalization status in the session payload

> Step 1.7 is **not started** and requires Flutter modifications.
