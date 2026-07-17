# Step 1.7 — Flutter Provisioning API Layer

**Status:** COMPLETE  
**Date:** 2026-07-17  

---

## Backend Session Payload Change

`AuthSessionPayloadBuilder::build()` updated to recognize both `applied` and `onboarding_complete` as terminal success states:

```php
->whereIn('status', ['applied', 'onboarding_complete'])
```

This ensures `onboarding_completed: true` is returned in the session payload after Step 1.6D finalization runs.

## Flutter Session Compatibility

`AuthSession.fromJson`, `AuthMembership.fromJson`, and `AuthWorkspace.fromJson` already default `onboarding_completed` to `false` when the field is missing. No model changes were required — the existing parsers handle both old (missing field) and new (field present) payloads without breaking cached sessions.

## Provisioning Models

**File:** `lib/core/api/provisioning_models.dart`

| Model | Purpose |
|---|---|
| `ProvisioningRunStatus` | Enum matching all 8 backend status constants + `unknown` fallback |
| `ProvisioningRun` | Full run entity with config map, status, version |
| `PreviewResult` | Dry-run plan with validation errors |
| `PreviewOperation` | Single operation within a preview plan |
| `ApplyResult` | Apply outcome with entity list, idempotency, conflict detection |
| `ProvisionedEntity` | Single created/adopted entity from apply |
| `FinalizeResult` | Finalize outcome with owner role/membership assignment |
| `FinalizeOwnerRole` | Primary owner role info |
| `FinalizeOwnerMembership` | Owner membership info |
| `ProvisioningError` | Structured error with `errorCode` and status-based predicates |

All `fromJson` constructors use null-safe defaults (`?? ''`, `?? false`, `?? const {}`).

## Remote Service Methods

**File:** `lib/core/api/provisioning_service.dart`

| Method | Endpoint | Returns |
|---|---|---|
| `preview(blueprintId:)` | `POST /provisioning/preview` | `PreviewResult` |
| `apply(blueprintId:)` | `POST /provisioning/apply` | `ApplyResult` |
| `finalize(runId:)` | `POST /provisioning/{run}/finalize` | `FinalizeResult` |
| `getActiveConfig()` | `GET /provisioning/config` | `ProvisioningRun?` |

No new backend endpoints were invented. All methods map to existing routes under `discovery.manage` permission.

## Repository Methods

**File:** `lib/features/onboarding/data/provisioning_repository.dart`

Wraps `ProvisioningService` with `ProvisioningResult<T>` — a sealed-style result type that converts `ApiException` subclasses into `ProvisioningError` with typed `ProvisioningErrorType` enum values:

| Method | Result Type |
|---|---|
| `preview(blueprintId:)` | `ProvisioningResult<PreviewResult>` |
| `apply(blueprintId:)` | `ProvisioningResult<ApplyResult>` |
| `finalize(runId:)` | `ProvisioningResult<FinalizeResult>` |
| `getActiveConfig()` | `ProvisioningResult<ProvisioningRun?>` |

`ProvisioningErrorType` values: `none`, `unauthorized`, `forbidden`, `notFound`, `conflict`, `validation`, `server`, `network`.

## Structured Error Mapping

**Files:** `lib/core/api/api_exceptions.dart`, `lib/core/api/api_client.dart`

Added two new exception classes and integrated them into `ApiClient._mapException`:

| HTTP Status | Exception | Error Code Source |
|---|---|---|
| 401 | `AuthException` | (existing) |
| 403 | `ForbiddenException` | **new** |
| 404 | `NotFoundException` | `error` field from JSON — **new** |
| 409 | `ConflictException` | `error_code` field (existing) |
| 422 | `ValidationException` | `errors` map (existing) |

## Test Results

```
flutter test test/features/onboarding/provisioning_api_layer_test.dart
→ 38/38 passed (0 failures)

flutter test (full suite)
→ All tests passed, exit code 0
```

### Test Coverage by Regression Area

| Area | Tests | Result |
|---|---|---|
| Old session without `onboarding_completed` | 1 | ✅ |
| New session with `onboarding_completed: true` | 1 | ✅ |
| Null `active_workspace` | 1 | ✅ |
| Token field preserved | 1 | ✅ |
| `ProvisioningRunStatus` parsing (8 statuses + unknown + null) | 3 | ✅ |
| `PreviewResult` parsing (valid, validation_failed, empty) | 3 | ✅ |
| `ApplyResult` parsing (success, idempotent, conflict, empty) | 4 | ✅ |
| `FinalizeResult` parsing (success, idempotent, missing fields) | 3 | ✅ |
| `ProvisioningError` parsing (404, 409, 422, 403, empty) | 5 | ✅ |
| Exception hierarchy (403, 404, 409, 401, 422, network) | 6 | ✅ |
| `ProvisioningResult` types (success + 7 error types) | 8 | ✅ |
| `ProvisioningRun` model (full + empty) | 2 | ✅ |

## Analyze Result

```
flutter analyze (5 files) → No issues found
```

## Files Changed

| File | Change |
|---|---|
| `backend/app/Services/AuthSessionPayloadBuilder.php` | `whereIn` for `onboarding_complete` status |
| `frontend/lib/core/api/api_exceptions.dart` | Added `ForbiddenException`, `NotFoundException` |
| `frontend/lib/core/api/api_client.dart` | 403/404 mapping in `_mapException` |
| `frontend/lib/core/api/provisioning_models.dart` | **new** — all provisioning data models |
| `frontend/lib/core/api/provisioning_service.dart` | **new** — remote data source |
| `frontend/lib/features/onboarding/data/provisioning_repository.dart` | **new** — repository + result types |
| `frontend/test/features/onboarding/provisioning_api_layer_test.dart` | **new** — 38-test verification suite |

## Remaining Step 1.8 Scope

- Wire `ProvisioningRepository` into `OnboardingState` (replace mock provisioning)
- Call `preview` → `apply` → `finalize` through the real API during onboarding
- Refresh session after finalize to pick up `onboarding_completed: true`
- Route from onboarding complete to ERP dashboard
- Handle provisioning errors in the onboarding UI (retry, error display)
- Integration test with running backend
