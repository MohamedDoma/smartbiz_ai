# Step 1.9a — Adaptive Discovery Flutter Integration

## Summary

Replaced the mock, scripted 6-question discovery flow with the real backend adaptive AI discovery system. The Flutter frontend now drives discovery conversations through existing backend REST endpoints, with dynamic question counts, adaptive follow-ups, real Blueprint generation, and verified provisioning handoff.

## Verification Results

| Metric | Result |
|--------|--------|
| `flutter test` | **610 passed, 0 failed** (FLUTTER_TEST_EXIT=0) |
| `flutter analyze` | **No issues found** (FLUTTER_ANALYZE_EXIT=0) |
| Backend discovery | **26/26 passed** |
| Backend operational | **10/10 passed** |
| Backend finalization | **32/32 passed** |
| Live OpenAI smoke | **PASS** (1 AI call used) |

## Backend Adaptive Discovery Verification

**Script:** `tests/adaptive_discovery_integration_verification.php`
**Existing test file:** `tests/Feature/DiscoveryTest.php` (12 PHPUnit tests, DS01–DS12)

26/26 scenarios passed:

| # | Test | Status |
|---|------|--------|
| 1 | Detailed description → completeness analysis | ✅ |
| 2 | Sparse description → follow-up question | ✅ |
| 3 | Same session ID reused across answers | ✅ |
| 4 | Previous facts persist in later turns | ✅ |
| 5 | Corrections update the existing session | ✅ |
| 6 | Blueprint generation creates real Blueprint | ✅ |
| 7 | Blueprint belongs to correct workspace | ✅ |
| 8 | Cross-workspace isolation blocks access | ✅ |
| 9 | Validation & conflict errors preserved | ✅ |

## Real Blueprint ID Handoff

**Test:** `test/features/onboarding/blueprint_handoff_test.dart` (3 tests)

The provisioning pipeline was updated from keyword-based `resolveTemplateKey` to UUID-based `resolveBlueprintId`:

```
Discovery generates real blueprint_id (UUID)
  → preview receives that blueprint_id    ✅ (called once)
  → core apply receives that blueprint_id ✅ (called once)
  → core apply returns run_id
  → operational apply receives run_id     ✅ (called once)
  → finalize receives run_id             ✅ (called once)
```

**Critical fix applied:** `startRealProvisioning` now uses `resolveBlueprintId(appState)` which returns the real discovery Blueprint UUID instead of a keyword template key. The backend `/provisioning/preview` and `/provisioning/apply` endpoints require `blueprint_id` as a UUID.

## Resume Behavior

**Test:** `test/features/onboarding/resume_isolation_test.dart` (18 tests)

- `resumeDiscovery()` fetches the active session from the backend and restores messages, completeness, and blueprint state
- No local-only persistence — all state is server-side
- Without a DiscoveryService, resume is a safe no-op

## Logout / Account Isolation

**Fix applied:** Added `OnboardingState.resetOnboarding()` call to both logout paths:
- `shared/layout/app_top_bar.dart` → `_handleLogout`
- `features/super_admin/layout/super_admin_shell.dart` → `_handleLogout`

This clears:
- Discovery messages ✅
- Discovery session ID ✅
- Blueprint ID ✅
- Readiness flag ✅
- Discovery errors ✅
- Completeness ✅
- AI thinking state ✅
- Provisioning state ✅

Account B logging in after account A's logout starts with a clean state.

## Controlled Live OpenAI Smoke Test

| Field | Value |
|-------|-------|
| Description | Detailed automotive dealership (Al-Raya Motors) |
| Session ID | `a246c973-dff8-4feb-9c25-b8a181213094` |
| Blueprint ID | `a246c986-962b-4a8e-8b33-3f5ef656b273` |
| AI calls used | **1** |
| Completeness | 93% (ready immediately) |
| Classification | `hybrid` (confidence: 98) |
| Generator | `canonical_v1` |
| Scripted response | **NO** |
| Fixed 6-question counter | **NO** |
| Provisioning preview accepted | **YES** |

The detailed description achieved 93% completeness on the first AI call — no follow-up was needed. This validates the adaptive behavior: comprehensive input skips unnecessary questions.

## Regression Results

| Suite | Result |
|-------|--------|
| Operational (10 scenarios) | 10/10 ✅ |
| Finalization (32 scenarios) | 32/32 ✅ |

## Files Changed

### New Files

| File | Purpose |
|------|---------|
| `lib/core/api/discovery_models.dart` | `DiscoverySession`, `DiscoveryMessageDto`, `DiscoveryBlueprintDto` |
| `lib/core/api/discovery_service.dart` | REST client for 6 discovery endpoints |
| `test/features/onboarding/adaptive_discovery_test.dart` | 28 model + state tests |
| `test/features/onboarding/blueprint_handoff_test.dart` | 3 handoff chain tests |
| `test/features/onboarding/resume_isolation_test.dart` | 18 resume + isolation tests |
| `backend/tests/adaptive_discovery_integration_verification.php` | 26 backend tests |
| `backend/tests/live_openai_smoke_test.php` | 1 live smoke test |

### Modified Files

| File | Change |
|------|--------|
| `lib/features/onboarding/onboarding_state.dart` | Real API, Blueprint bridge, `resolveBlueprintId`, resume |
| `lib/features/onboarding/models/onboarding_models.dart` | Removed `DiscoveryCategory`/`DiscoveryProgress`, added `messageType` |
| `lib/features/onboarding/screens/discovery_screen.dart` | Dynamic completeness, error banner, classify+generate CTA |
| `lib/features/onboarding/widgets/discovery_progress_bar.dart` | Dynamic % bar |
| `lib/main.dart` | `DiscoveryService` injection |
| `lib/shared/layout/app_top_bar.dart` | Logout clears OnboardingState |
| `lib/features/super_admin/layout/super_admin_shell.dart` | Logout clears OnboardingState |
| `lib/core/api/discovery_models.dart` | Safe `Map.from` casting for empty maps |
| `test/features/onboarding/onboarding_state_provisioning_test.dart` | Removed `startProvisioning()` mock refs |

### Preserved (untouched)

- Full provisioning pipeline (`startRealProvisioning`, resume, 409 handling)
- Blueprint screen UI (`blueprint_screen.dart`)
- Welcome screen UI
- Router guards
- All 561 pre-existing tests

## Remaining Manual Step 1.9 Testing

1. **E2E browser test:** Complete an onboarding session in Chrome DevTools — verify the full discovery → blueprint → provisioning → dashboard flow
2. **Resume verification:** Close the browser mid-discovery, reopen, confirm conversation is restored
3. **Multi-account test:** Log in as user A, start discovery, log out, log in as user B — verify clean state
4. **Mobile responsive:** Run on a narrow viewport, verify the discovery chat and progress bar render correctly
5. **Error recovery:** Disconnect network during AI response, verify the error banner appears and retry works
