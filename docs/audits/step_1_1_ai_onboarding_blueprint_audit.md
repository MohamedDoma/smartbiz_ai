# Step 1.1 — AI Onboarding & Blueprint Audit

> Generated: 2026-07-16  
> Scope: Backend (Laravel/PHP) + Frontend (Flutter/Dart)  
> Status: Read-only investigation — no code modified

---

## 1. Executive Summary

The SmartBiz AI onboarding & blueprint system consists of **two parallel provisioning paths** and a **frontend that uses neither of them**:

| Path | Backend Status | Frontend Status | Connected? |
|------|---------------|-----------------|------------|
| **A. AI Discovery → Blueprint → Provisioning** | Fully implemented: routes, controllers, services, models, resources | **No frontend API client, no frontend models that parse backend responses** | ❌ Disconnected |
| **B. Business Templates → Apply** | Fully implemented: routes, controller, service, models | Connected via `BusinessTemplateService` + `AppState.applyBusinessTemplate()` | ✅ Connected |

**The frontend onboarding flow is 100% mock-driven.** It uses hardcoded `MockDiscovery` data and a static `BlueprintModel`. The discovery conversation simulates AI Q&A with `Future.delayed(800ms)`. The "Accept" button calls `startRealProvisioning()` which maps the mock blueprint to a `template_key` and calls Path B (business template apply). **Path A is never invoked from the frontend.**

The backend's discovery/blueprint/provisioning tables (`discovery_sessions`, `discovery_messages`, `discovery_blueprints`, `provisioning_runs`, `workspace_configurations`) have **no migration file** — the tables exist only as Eloquent models. They are not in the database.

---

## 2. Current End-to-End Flow

```text
Register → Login → Router gate: onboarding_completed == false
  → /onboarding route (standalone, no shell)
    → OnboardingPage → WelcomeScreen (static)
      → "Start" button → OnboardingState.startDiscovery()
        → Phase: discovery → DiscoveryScreen
          → MockDiscovery.responses[0..5] (canned questions)
          → User types/taps quick replies → 6 scripted rounds
          → Progress bar advances → isComplete = true
          → "View Blueprint" CTA appears
            → OnboardingState.goToBlueprint()
              → _blueprint = MockDiscovery.sampleBlueprint (static)
              → Phase: blueprint → BlueprintScreen
                → Renders mock BlueprintModel (Retail Store)
                → "Accept" button
                  → OnboardingState.startRealProvisioning(appState)
                    → resolveTemplateKey() maps mock businessType to template_key
                    → appState.applyBusinessTemplate(templateKey)
                      → POST /api/business-templates/{key}/apply ← real API
                      → loadCurrentSession() (GET /auth/me)
                        → onboarding_completed = true ← from ProvisioningRun or TemplateApplication
                    → Phase: complete → _ProvisioningView
                      → "Go to Dashboard" → context.go('/dashboard')
```

**Critical observation:** The entire discovery conversation is fake. No backend discovery session is created. No AI classification occurs. The blueprint shown to the user is a static retail template regardless of what they type.

---

## 3. Relevant Backend Files and Responsibilities

### Discovery / Blueprint Pipeline (Path A — backend only)

| File | Responsibility | Lines |
|------|---------------|-------|
| [DiscoveryController.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Controllers/Api/DiscoveryController.php) | REST endpoints: index, show, start, answer, classify, generateBlueprint, showBlueprint | 118 |
| [DiscoverySessionService.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/DiscoverySessionService.php) | Session lifecycle: start, submitAnswers, classify (rule+LLM), generateBlueprint, gatherContext | 317 |
| [BlueprintGeneratorService.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/BlueprintGeneratorService.php) | Rule-based classifier + 6 business templates (retail, restaurant, service, manufacturing, distribution, hybrid) + follow-up question generation | 721 |
| [ProvisioningService.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/ProvisioningService.php) | Preview/apply/rollback provisioning from blueprint → WorkspaceConfiguration | 221 |
| [ProvisioningController.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Controllers/Api/ProvisioningController.php) | REST endpoints: preview, apply, rollback, config, updateModules, updateRole | 114 |
| [DiscoverySession.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Models/DiscoverySession.php) | Eloquent model: `discovery_sessions` table | 55 |
| [DiscoveryMessage.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Models/DiscoveryMessage.php) | Eloquent model: `discovery_messages` table | 41 |
| [DiscoveryBlueprint.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Models/DiscoveryBlueprint.php) | Eloquent model: `discovery_blueprints` table | 43 |
| [ProvisioningRun.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Models/ProvisioningRun.php) | Eloquent model: `provisioning_runs` table | 37 |
| [WorkspaceConfiguration.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Models/WorkspaceConfiguration.php) | Eloquent model: `workspace_configurations` table | 37 |
| [DiscoverySessionResource.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Resources/DiscoverySessionResource.php) | JSON serialization for session | 28 |
| [DiscoveryBlueprintResource.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Resources/DiscoveryBlueprintResource.php) | JSON serialization for blueprint | 24 |
| [DiscoveryMessageResource.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Resources/DiscoveryMessageResource.php) | JSON serialization for messages | — |
| [StartDiscoveryRequest.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Requests/StartDiscoveryRequest.php) | Validation: `business_description` required, min 20 chars | 23 |
| [AnswerDiscoveryRequest.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Requests/AnswerDiscoveryRequest.php) | Validation: `message_id` UUID, `answers[]` required | 18 |

### Business Template Pipeline (Path B — connected)

| File | Responsibility |
|------|---------------|
| [BusinessTemplateController.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Http/Controllers/Api/BusinessTemplateController.php) | REST: index, show, apply | 
| [BusinessTemplateApplicationService.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/BusinessTemplateApplicationService.php) | Apply template → feature flags, roles, membership role, workspace metadata | 
| [AuthSessionPayloadBuilder.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/AuthSessionPayloadBuilder.php) | Builds session payload including `onboarding_completed` flag |

### AI / LLM Infrastructure

| File | Responsibility |
|------|---------------|
| [LlmService.php](file:///home/doma/Desktop/final/smartbiz_ai/backend/app/Services/Ai/LlmService.php) | LLM router with fallback (OpenAI, Anthropic) |
| DiscoverySessionService uses `LlmService` optionally | `classifyWithLlm()`, `generateFollowUpsWithLlm()` — LLM-enhanced versions with rule-based fallback |

---

## 4. Relevant Flutter Files and Responsibilities

| File | Responsibility | API Calls? |
|------|---------------|------------|
| [onboarding_page.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/onboarding_page.dart) | Phase router: welcome / discovery / blueprint | None |
| [onboarding_state.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/onboarding_state.dart) | ChangeNotifier: phases, messages, progress, mock AI, `startRealProvisioning()` | `applyBusinessTemplate()` only |
| [onboarding_models.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/models/onboarding_models.dart) | `DiscoveryMessage`, `DiscoveryProgress`, `BlueprintModel`, `BlueprintModule`, `BlueprintRole` | None — purely local |
| [mock_discovery.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/data/mock_discovery.dart) | Static `MockResponse` list (6 steps), static `sampleBlueprint` (hardcoded retail) | None |
| [welcome_screen.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/screens/welcome_screen.dart) | Welcome UI with animated orb, feature bullets, language toggle, "Start" CTA | None |
| [discovery_screen.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/screens/discovery_screen.dart) | Chat UI with message list, quick replies, text input, blueprint CTA | None |
| [blueprint_screen.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/screens/blueprint_screen.dart) | Blueprint preview (modules/roles/workflows), provisioning view, completion view | `startRealProvisioning()` |
| [chat_bubble.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/widgets/chat_bubble.dart) | Chat message bubble with quick replies and thinking indicator | None |
| [discovery_progress_bar.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/features/onboarding/widgets/discovery_progress_bar.dart) | Category progress bar with chips | None |
| [router.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/app/router.dart) | `redirect`: if `!onboardingDone && !isOnboardingRoute` → `/onboarding` | None |
| [app_state.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/core/state/app_state.dart) | `isOnboardingCompleted`, `completeOnboarding()`, `applyBusinessTemplate()` | `templateService.applyTemplate()`, `loadCurrentSession()` |
| [business_template_service.dart](file:///home/doma/Desktop/final/smartbiz_ai/frontend/lib/core/api/business_template_service.dart) | `listTemplates()`, `applyTemplate()` — real HTTP | POST `/api/business-templates/{key}/apply` |

---

## 5. Existing Database Tables and Important Fields

### Tables WITH Migration (exist in DB)

| Table | Migration | Key Fields |
|-------|-----------|------------|
| `workspaces` | (core migration) | `onboarding_data` (JSON), `industry_type` |
| `business_templates` | `024_business_templates.php` | `template_key`, `is_active`, `version` |
| `business_template_modules` | `024_business_templates.php` | `module_key`, `is_enabled`, `is_required` |
| `business_template_roles` | `024_business_templates.php` | `role_key`, `permissions[]`, `hierarchy_level` |
| `business_template_workflows` | `024_business_templates.php` | `workflow_key`, `config` |
| `workspace_template_applications` | `024_business_templates.php` | `status`, `applied_at`, `snapshot` |
| `workspace_feature_flags` | `024_business_templates.php` | `feature_key`, `is_enabled` |
| `roles` | `026_role_permission_management.php` | `role_key`, `permissions[]`, `is_system` |

### Tables WITHOUT Migration (models exist, tables do NOT)

| Table | Model | Status |
|-------|-------|--------|
| `discovery_sessions` | `DiscoverySession` | ⛔ No migration |
| `discovery_messages` | `DiscoveryMessage` | ⛔ No migration |
| `discovery_blueprints` | `DiscoveryBlueprint` | ⛔ No migration |
| `provisioning_runs` | `ProvisioningRun` | ⛔ No migration |
| `workspace_configurations` | `WorkspaceConfiguration` | ⛔ No migration |

---

## 6. Existing API Endpoints

### Discovery (Path A) — `discovery.manage` permission

| Method | Route | Controller | Status |
|--------|-------|-----------|--------|
| GET | `/api/discovery/sessions` | `DiscoveryController@index` | Backend only (no migration, no frontend) |
| GET | `/api/discovery/sessions/{id}` | `DiscoveryController@show` | Backend only |
| POST | `/api/discovery/sessions` | `DiscoveryController@start` | Backend only |
| POST | `/api/discovery/sessions/{id}/answer` | `DiscoveryController@answer` | Backend only |
| POST | `/api/discovery/sessions/{id}/classify` | `DiscoveryController@classify` | Backend only |
| POST | `/api/discovery/sessions/{id}/generate-blueprint` | `DiscoveryController@generateBlueprint` | Backend only |
| GET | `/api/discovery/sessions/{id}/blueprint` | `DiscoveryController@showBlueprint` | Backend only |

### Provisioning (Path A) — `discovery.manage` permission

| Method | Route | Controller | Status |
|--------|-------|-----------|--------|
| POST | `/api/provisioning/preview` | `ProvisioningController@preview` | Backend only |
| POST | `/api/provisioning/apply` | `ProvisioningController@apply` | Backend only |
| POST | `/api/provisioning/rollback` | `ProvisioningController@rollback` | Backend only |
| GET | `/api/provisioning/config` | `ProvisioningController@config` | Backend only |
| PUT | `/api/provisioning/modules` | `ProvisioningController@updateModules` | Backend only |
| PUT | `/api/provisioning/roles/{role}` | `ProvisioningController@updateRole` | Backend only |

### Business Templates (Path B) — no permission middleware

| Method | Route | Controller | Status |
|--------|-------|-----------|--------|
| GET | `/api/business-templates` | `BusinessTemplateController@index` | ✅ Working |
| GET | `/api/business-templates/{key}` | `BusinessTemplateController@show` | ✅ Working |
| POST | `/api/business-templates/{key}/apply` | `BusinessTemplateController@apply` | ✅ Working |

---

## 7. Existing Blueprint Structure

### Backend Blueprint (from `BlueprintGeneratorService`)

```json
{
  "business_type": "retail | restaurant | service | manufacturing | distribution | hybrid",
  "enabled_modules": ["contacts", "products", ...],
  "optional_modules": ["recurring_expenses", ...],
  "recommended_roles": [
    { "name": "owner", "description": "Full system access" }
  ],
  "role_homepages": { "owner": "/dashboard" },
  "role_navigation": { "owner": ["dashboard", "sales", ...] },
  "role_quick_actions": { "owner": ["create_invoice", ...] },
  "role_allowed_screens": { "owner": ["*"] },
  "role_dashboard_widgets": { "owner": ["revenue_chart", ...] },
  "recommended_pages": ["dashboard", "pos", ...],
  "recommended_workflows": [
    { "name": "sale_to_payment", "description": "Invoice → Payment → Receipt" }
  ],
  "recommended_dashboards": ["daily_sales", ...],
  "recommended_automations": [
    { "name": "low_stock_alert", "trigger": "...", "action": "..." }
  ],
  "assumptions": [],
  "missing_info": []
}
```

### Frontend Blueprint Model (from `onboarding_models.dart`)

```dart
class BlueprintModel {
  final String businessName;
  final String businessType;
  final String businessDescription;
  final List<BlueprintModule> requiredModules;      // id, nameKey, descriptionKey, icon
  final List<BlueprintModule> optionalModules;
  final List<BlueprintRole> suggestedRoles;         // id, nameKey, descriptionKey, accessModules
  final List<String> suggestedWorkflows;            // l10n keys
  final List<String> suggestedDashboards;
  final List<String> suggestedAutomations;
  final List<String> notes;
}
```

**Mismatch:** The backend blueprint has `role_homepages`, `role_navigation`, `role_quick_actions`, `role_allowed_screens`, `role_dashboard_widgets` — none of which exist in the frontend model. The frontend model uses l10n keys (e.g., `bp_mod_sales`); the backend uses raw identifiers (e.g., `contacts`).

---

## 8. Existing AI Prompt/Tool Flow

### Rule-Based (Active)

1. `BlueprintGeneratorService.classifyBusiness()` — keyword scoring against 5 type maps
2. `BlueprintGeneratorService.generateFollowUpQuestions()` — 8 canned question categories, skips already answered
3. `BlueprintGeneratorService.generateBlueprint()` — selects template by type, enhances with context clues

### LLM-Enhanced (Available but Unused by Frontend)

1. `DiscoverySessionService.classifyWithLlm()` — sends system prompt + context to `LlmService.chat()`, falls back to rule-based
2. `DiscoverySessionService.generateFollowUpsWithLlm()` — same pattern with fallback

The LLM service supports OpenAI and Anthropic with automatic fallback via `ProviderRouter`.

---

## 9. Existing Provisioning Flow

### Path A — Discovery → Blueprint → Provisioning (disconnected)

```
ProvisioningService.preview(workspaceId, blueprintId)
  → buildConfig(blueprint) → normalize into WorkspaceConfiguration shape
  → Creates ProvisioningRun with status='preview'

ProvisioningService.apply(workspaceId, blueprintId, userId)
  → DB::transaction
  → buildConfig(blueprint)
  → Captures rollback config from existing WorkspaceConfiguration
  → Creates ProvisioningRun with status='applied'
  → Upserts WorkspaceConfiguration

ProvisioningService.rollback(workspaceId, runId, userId)
  → DB::transaction → restores rollback config → marks run 'rolled_back'
```

**Blocker:** `AuthSessionPayloadBuilder` checks `ProvisioningRun::where('status', 'completed')` but `ProvisioningService::apply()` sets status to `'applied'` not `'completed'`. This means Path A would never set `onboarding_completed = true`.

### Path B — Business Templates (working)

```
BusinessTemplateApplicationService.apply(template, workspace, user)
  → DB::transaction
  → applyModules → WorkspaceFeatureFlag upserts
  → applyRoles → Role creates/updates + MembershipRole for owner
  → buildSnapshot
  → WorkspaceTemplateApplication.updateOrCreate with status='applied'
  → workspace.update(onboarding_data, industry_type)
```

`AuthSessionPayloadBuilder` checks `WorkspaceTemplateApplication::where('status', 'applied')->exists()` → returns `onboarding_completed = true`. **This path works.**

---

## 10. Gap Table

| Component | Status | Details |
|-----------|--------|---------|
| Backend Discovery routes | **Backend only** | 7 routes registered, controller & service complete, but tables don't exist |
| Backend Provisioning routes | **Backend only** | 6 routes registered, service complete, but tables don't exist |
| Backend Business Template routes | **Working** | 3 routes, tested and used by frontend |
| Database migration for discovery tables | **Missing** | 5 tables (`discovery_sessions`, `discovery_messages`, `discovery_blueprints`, `provisioning_runs`, `workspace_configurations`) have models but no migration |
| `ProvisioningRun.status` mismatch | **Blocking bug** | `apply()` sets `'applied'` but `AuthSessionPayloadBuilder` checks for `'completed'` |
| Frontend Discovery API service | **Missing** | No `DiscoveryService` or `DiscoveryRepository` in `frontend/lib/core/api/` |
| Frontend Discovery models (backend DTO) | **Missing** | No Dart model that parses `DiscoverySessionResource` JSON |
| Frontend Blueprint parsing from backend | **Missing** | `BlueprintModel` is a static l10n-key-based class, not a parser for backend blueprint JSON |
| Frontend `OnboardingState` → backend discovery | **Disconnected** | `sendMessage()` calls `MockDiscovery` not API; `goToBlueprint()` loads static data |
| Frontend provisioning API client | **Missing** | No calls to `/api/provisioning/*` |
| Frontend onboarding session persistence | **Missing** | No local storage of session ID; F5 restarts onboarding from welcome |
| Frontend retry/error in discovery | **Partial** | `_provisioningError` exists but only for template apply; discovery chat has no error states |
| Discovery → Blueprint → Provisioning integration | **Disconnected** | Two complete backends, zero frontend wiring |
| `OnboardingState.resolveTemplateKey()` | **Working** | Maps mock businessType → real template_key → `applyBusinessTemplate()` |
| Router onboarding gate | **Working** | Correctly redirects to `/onboarding` if `onboarding_completed == false` |
| Welcome screen | **Working** | Fully styled, localized, language toggle |
| Discovery chat UI | **Working** (mock) | Chat bubbles, quick replies, progress bar — all functional with mock data |
| Blueprint review UI | **Working** (static) | Modules, roles, workflows, automations — renders from mock model |
| Provisioning completion UI | **Working** | Shows spinner → success → "Go to Dashboard" |

---

## 11. Duplicate or Obsolete Code

| Item | Location | Notes |
|------|----------|-------|
| Two provisioning systems | `ProvisioningService` vs `BusinessTemplateApplicationService` | Both transform blueprints/templates into workspace config. `ProvisioningService` targets `WorkspaceConfiguration`; `BusinessTemplateApplicationService` targets `WorkspaceFeatureFlag` + `Role` + `WorkspaceTemplateApplication`. These are not converged. |
| `OnboardingState.startProvisioning()` | `onboarding_state.dart:56-69` | Mock-only provisioning with `Future.delayed(2s)`. Kept alongside `startRealProvisioning()`. Should be removed or guarded behind a debug flag. |
| `AppState.registerBusinessOwner()` (mock) | `app_state.dart:578-602` | Mock registration. Kept alongside `registerBusinessOwnerReal()`. |
| `MockDiscovery.sampleBlueprint` | `mock_discovery.dart:40-83` | Hardcoded retail blueprint used by all users regardless of their actual answers. |
| Backend `DiscoverySessionService.classifyWithLlm()` / `generateFollowUpsWithLlm()` | Never called | These LLM-enhanced methods exist but `DiscoveryController` calls the non-LLM methods (`classify()` → `classifyBusiness()`, `startSession()` → `generateFollowUpQuestions()`). The controller calls the rule-based path, not the LLM-enhanced one. |

---

## 12. Recommended Execution Order for Task 1.2 Onward

### Task 1.2 — Database Foundation
1. Create migration `038_discovery_provisioning.php` for all 5 tables
2. Fix `ProvisioningRun.status` vocabulary: add `'completed'` or update `AuthSessionPayloadBuilder` to also check `'applied'`
3. Run migration, verify tables exist

### Task 1.3 — Backend Integration Hardening
1. Wire `DiscoveryController.classify()` to use `classifyWithLlm()` instead of rule-based only
2. Add `'completed'` status transition in `ProvisioningService.apply()` or unify status vocabulary
3. Add backend tests for the discovery → classify → generate-blueprint → provisioning pipeline

### Task 1.4 — Frontend API Layer
1. Create `discovery_service.dart` with methods: `startSession()`, `submitAnswers()`, `classify()`, `generateBlueprint()`, `showBlueprint()`
2. Create `provisioning_service.dart` with methods: `preview()`, `apply()`
3. Create Dart DTOs: `DiscoverySessionDto`, `DiscoveryMessageDto`, `BlueprintDto` that parse backend JSON

### Task 1.5 — Frontend State Integration
1. Refactor `OnboardingState` to call real discovery API instead of `MockDiscovery`
2. Refactor `BlueprintModel` (or create adapter) to parse backend blueprint JSON into the existing UI structure
3. Add session persistence (store session ID in local storage for F5 recovery)
4. Add real error/retry states for each API call
5. Keep `MockDiscovery` behind a `kDebugMode` flag for offline development

### Task 1.6 — End-to-End Wiring
1. Wire blueprint "Accept" to call provisioning preview → apply (or keep business template path if that's the chosen strategy)
2. Ensure `onboarding_completed` correctly reflects the provisioning result
3. Test F5 resilience at each stage

### Task 1.7 — Polish
1. Remove or guard mock-only code paths
2. Ensure blueprint review UI adapts to dynamic backend data (not hardcoded retail modules)
3. Add loading skeletons for API-driven discovery conversation
4. Localize any new error/status messages

---

## 13. Exact Files That Should Be Modified in Task 1.2

| File | Action | Reason |
|------|--------|--------|
| `backend/database/migrations/038_discovery_provisioning.php` | **Create** | Migration for 5 tables: `discovery_sessions`, `discovery_messages`, `discovery_blueprints`, `provisioning_runs`, `workspace_configurations` |
| `backend/app/Services/AuthSessionPayloadBuilder.php` | **Modify** | Fix `onboarding_completed` check to include `ProvisioningRun` status `'applied'` (not just `'completed'`) |
| `backend/app/Services/ProvisioningService.php` | **Modify** (optional) | Add explicit `'completed'` status or document that `'applied'` is the terminal success status |

No frontend files should be modified in Task 1.2. The migration must be verified by running `php artisan migrate` and confirming all 5 tables are created.
