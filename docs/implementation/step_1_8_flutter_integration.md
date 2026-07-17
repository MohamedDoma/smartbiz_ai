# Step 1.8 — Flutter Integration & Provisioning Pipeline

## Overview

Step 1.8 wires the Flutter frontend to the Laravel provisioning backend, enabling the full onboarding lifecycle: preview → core apply → operational apply → finalize → session refresh → ERP dashboard entry.

---

## 1. Provider Wiring

The onboarding pipeline is driven by `OnboardingState` (ChangeNotifier), provided at the app root via `MultiProvider`. It communicates with the backend through `ProvisioningService`, which is injected via `Provider<ProvisioningService>`.

```
main.dart
  └─ MultiProvider
       ├─ AppState (auth, session, onboardingCompleted flag)
       ├─ OnboardingState (pipeline orchestrator)
       ├─ ProvisioningService (HTTP client)
       └─ BlueprintNavigationController (module nav)
```

`AppState` holds `isOnboardingCompleted` and `isAuthenticated`, which the router's redirect callback consumes. `OnboardingState` orchestrates the multi-step pipeline and calls `AppState.completeOnboarding()` after finalization + session refresh.

---

## 2. Pipeline Flow

### 2.1 Preview

`OnboardingState.preview()` → `POST /api/provisioning/preview`

Returns a dry-run summary of what will be provisioned (branches, roles, modules, pipelines). No mutations. Allows the user to review before committing.

### 2.2 Core Apply

`OnboardingState.apply()` → `POST /api/provisioning/apply`

Creates the provisioning run and applies foundation entities: branches, departments, roles, default permissions. Returns a `run_id` used for subsequent steps.

### 2.3 Operational Apply

`OnboardingState.applyOperational(runId)` → `POST /api/provisioning/{run}/apply-operational`

Applies operational entities: warehouses, pipelines, approval workflows, commission rules, workspace settings. All linked to foundation entities via `provisioning_entity_bindings`.

### 2.4 Finalize

`OnboardingState.finalize(runId)` → `POST /api/provisioning/{run}/finalize`

Transitions the provisioning run to `onboarding_complete`. Dispatches `WorkspaceOnboardingCompleted` event. Returns `session_refresh: true` to signal the client to refresh its session.

### 2.5 Session Refresh

When `finalize()` returns `session_refresh: true`, the client calls `AppState.refreshSession()` which re-fetches the user's workspace membership. The refreshed session includes `onboarding_completed: true`, which sets `AppState.isOnboardingCompleted = true`. This triggers `notifyListeners()` → GoRouter re-evaluates redirect → user lands on `/dashboard`.

---

## 3. Resume Rules

If the user abandons onboarding mid-flow:

1. **Before apply**: No run exists. User restarts from preview.
2. **After apply, before operational**: Run exists with `status: applied`. `OnboardingState.resume()` detects this and offers to continue from operational apply.
3. **After operational, before finalize**: Run exists with `status: operational_applied`. Resume offers finalize.
4. **After finalize**: Session refresh completes the flow. If the browser closed before refresh, the next login refreshes the session and the router gate redirects to `/dashboard`.

---

## 4. Strengthened 409 Status Recheck

The `applyOperational` endpoint returns `409 Conflict` if:
- Foundation was not applied (`foundation_applied` flag is false)
- The run is not in `applied` status (already operational or finalized)

The frontend handles 409 by:
1. Checking `error_code` in the response body
2. If `already_operational`: treats as idempotent success, proceeds to finalize
3. If `foundation_not_applied`: shows error, offers to re-run core apply
4. Does **not** silently retry — surfaces the conflict to the user

---

## 5. Duplicate-Request Call Counts

Both `applyOperational` and `finalize` are idempotent:
- Calling `applyOperational` twice with the same run returns 409 with `already_operational` — the frontend treats this as success (0 additional mutations)
- Calling `finalize` twice returns 409 with `already_finalized` — no duplicate event dispatch
- The provisioning service checks `status` before mutating, inside a DB transaction

---

## 6. Session Refresh Behavior

| `session_refresh` | Action |
|---|---|
| `true` | Client calls `AppState.refreshSession()`, which re-fetches workspace membership and sets `isOnboardingCompleted = true` |
| `false` | Client does not refresh. This occurs on idempotent finalize calls where the session was already refreshed |

---

## 7. Real Router Redirect Verification

The onboarding gate logic is extracted into a single reusable function:

```dart
// router.dart
String? evaluateOnboardingGate({
  required bool isAuthenticated,
  required bool isSuperAdmin,
  required bool onboardingDone,
  required String loc,
})
```

Both `buildAppRouter()` and the router integration tests call this exact function — no duplicated conditions. The router wraps the result in `guard()` to prevent redirect loops.

### Test Coverage (7 scenarios):

| # | Scenario | Expected |
|---|----------|----------|
| 1 | Incomplete onboarding, `/dashboard` | → `/onboarding` |
| 2 | Completed onboarding, `/onboarding` | → `/dashboard` |
| 3 | During provisioning, `/onboarding` | stays (null) |
| 4 | After session refresh, `/onboarding` | → `/dashboard` |
| 5 | Browser reload, `/dashboard` (completed) | stays (null) |
| 6 | Router refreshListenable wired to AppState | ✅ |
| 7 | Truth table: all 8 route×status combinations | ✅ |

---

## 8. NavPerms Bridge Fix

**File**: `lib/features/dashboard/engine/dashboard_context_adapter.dart`

When operating without a backend session (cold start, demo mode, tests), the frontend computes permissions locally using `AppRole.canSee()`. These generated `*.view` keys (e.g., `invoices.view`) but the `ModuleRouteGuard` checks against the registry's `navPerms` keys (e.g., `invoices.list`).

**Fix**: Added a `navPermsMap` bridge table that injects the equivalent registry navPerms for any module where the user has at least `view` permission. This map must stay in sync with `ErpModuleRegistry` navPerms.

---

## 9. Quick-Action Permission Fix

**File**: `lib/features/dashboard/dynamic_dashboard_state.dart`

`_applyModuleVisibility()` called `ModuleRouteGuard.evaluate()` for quick action filtering but did not pass `effectivePermissions`, causing all quick actions to be hidden even when their owning module was enabled.

**Fix**: Now passes `effectivePermissions` from the `BlueprintNavigationController` to the guard evaluation.

---

## 10. Verification Results

### Flutter Test

```
562 passed, 0 failed
FLUTTER_TEST_EXIT=0
```

### Flutter Analyze

```
No issues found!
FLUTTER_ANALYZE_EXIT=0
```

### Backend Operational

```
10/10 scenarios PASSED
```

### Backend Finalization

```
32/32 passed (100%)
```

---

## 11. Files Changed

### Production Code

| File | Change |
|------|--------|
| `lib/app/router.dart` | Extracted `evaluateOnboardingGate()` as shared function; router calls it instead of inline conditions; removed unused `isOnboardingRoute` |
| `lib/features/dashboard/engine/dashboard_context_adapter.dart` | Added navPerms bridge map; renamed `_navPermsMap` → `navPermsMap` |
| `lib/features/dashboard/dynamic_dashboard_state.dart` | Pass `effectivePermissions` to quick action guard |
| `lib/core/api/platform_models.dart` | `///` → `//` (dangling library doc comment) |
| `lib/features/employees/screens/employee_roles_screen.dart` | Pre-capture ScaffoldMessenger + localized strings before await |
| `lib/features/employees/screens/role_management_real_screen.dart` | Pre-capture ScaffoldMessenger + localized strings + state before await |
| `lib/features/pipelines/screens/pipelines_screen.dart` | Add curly braces to 5 single-statement if bodies |
| `lib/features/platform/screens/activation_campaigns_screen.dart` | Add `mounted` guard to `Future.microtask` |
| `lib/features/platform/screens/activation_codes_screen.dart` | Add `mounted` guard to `Future.microtask` |
| `lib/features/platform/screens/platform_dashboard_screen.dart` | Add `mounted` guard to `Future.microtask` |
| `lib/features/platform/screens/platform_health_screen.dart` | Add `mounted` guard to `Future.microtask` |
| `lib/features/platform/screens/platform_users_screen.dart` | Add `mounted` guard to `Future.microtask` |
| `lib/features/platform/screens/platform_workspaces_screen.dart` | Add `mounted` guard to `Future.microtask` |

### Test Code

| File | Change |
|------|--------|
| `test/features/onboarding/router_onboarding_guard_test.dart` | Removed local `evaluateOnboardingGate()` duplicate; now calls shared function from `router.dart` |
| `test/modules/module_navigation_resolver_test.dart` | POS→implemented; added `invoices.list` navPerm; accounting→both visibility |
| `test/modules/blueprint_navigation_controller_test.dart` | Added SharedPreferences mock; POS→quotations; accounting→both |
| `test/modules/blueprint_navigation_coordinator_test.dart` | Added SharedPreferences mock; POS→quotations |
| `test/shared/layout/app_sidebar_blueprint_navigation_test.dart` | `signInAsSuperAdmin()`; scroll-to-visible for lazy ListView admin section; removed unused `_legacyFlatItems` + `nav_model` import; renamed `tr_en`→`trEn` |
| `test/features/dashboard/dynamic_dashboard_state_module_visibility_test.dart` | Added navPerms keys; removed unused import |
| `test/features/approvals/workflow_card_metadata_test.dart` | Removed unused import |

---

## 12. Remaining Step 1.9 Scope

Step 1.8 is fully closed. The following items are deferred to Step 1.9:

1. **End-to-end onboarding smoke test**: Full browser-level test using the running backend (preview → apply → operational → finalize → dashboard redirect)
2. **Error recovery UX**: Improve error messages for 409 conflicts, network failures, and partial rollbacks
3. **Module enablement UI**: Allow workspace owners to toggle modules post-onboarding
4. **Performance optimization**: Lazy-load deferred imports for platform admin screens
5. **Localization audit**: Verify all provisioning-related strings have Arabic translations
