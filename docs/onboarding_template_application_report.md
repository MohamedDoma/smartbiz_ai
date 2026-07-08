# SmartBiz AI — Onboarding → Template Application Report

> **Date:** 2026-07-07 | **Step:** 45  
> **Scope:** Connect onboarding to business template foundation

---

## Backend Files Created

| File | Purpose |
|---|---|
| `app/Services/BusinessTemplateApplicationService.php` | Core service: applies template to workspace (modules, roles, application record, onboarding marking) |

## Backend Files Modified

| File | Change |
|---|---|
| `app/Http/Controllers/Api/BusinessTemplateController.php` | Added `apply()` endpoint |
| `app/Http/Controllers/Api/AuthController.php` | Updated `onboarding_completed` to check `WorkspaceTemplateApplication` in addition to `ProvisioningRun` |
| `routes/api.php` | Added `POST /api/business-templates/{template_key}/apply` route |

## Frontend Files Created

| File | Purpose |
|---|---|
| `lib/core/api/business_template_models.dart` | `BusinessTemplateSummary` + `TemplateApplicationResult` models |
| `lib/core/api/business_template_service.dart` | `listTemplates()` + `applyTemplate()` methods |

## Frontend Files Modified

| File | Change |
|---|---|
| `lib/core/state/app_state.dart` | Added `BusinessTemplateService`, `applyBusinessTemplate()` method |
| `lib/features/onboarding/onboarding_state.dart` | Added `startRealProvisioning()` + `resolveTemplateKey()` |
| `lib/features/onboarding/screens/blueprint_screen.dart` | Wired Accept button to real provisioning |

---

## Endpoint

```
POST /api/business-templates/{template_key}/apply
```

| Header | Required | Purpose |
|---|---|---|
| `Authorization: Bearer {token}` | ✅ | Auth |
| `X-Workspace-Id: {uuid}` | ✅ | Target workspace |

| Scenario | HTTP | Response |
|---|---|---|
| Success | 200 | `{ message, application: { id, template_key, template_version, status, applied_at } }` |
| Re-apply same | 200 | Idempotent (updates timestamp/snapshot) |
| Different template | 409 | Conflict |
| Invalid template | 404 | Not found |
| Missing header | 400 | X-Workspace-Id required |
| Not a member | 403 | Forbidden |
| Unauthenticated | 401 | Unauthorized |

---

## How Modules Are Applied

- For each `business_template_modules` row → `WorkspaceFeatureFlag.updateOrCreate`
- Maps: `module_key → feature_key`, `is_enabled`, `override_reason = template:{key}`
- Idempotent: re-apply updates but doesn't duplicate

## How Roles Are Applied

- For each `business_template_roles` row → `Role.updateOrCreate` by workspace + role_key
- Existing roles: permissions merged (union), name/description updated
- New roles: created with `is_system = true`
- Owner role: `MembershipRole` upserted to ensure primary assignment
- Does NOT delete user-created roles

## How Onboarding Is Determined

```php
$onboardingCompleted = ProvisioningRun::completed() || WorkspaceTemplateApplication::applied();
```

- `/auth/me` → `active_workspace.onboarding_completed = true` after template apply
- `workspace.onboarding_data.onboarding_completed = true` written
- `workspace.industry_type` set from template

## How enabled_modules Is Returned

```php
WorkspaceFeatureFlag::where('workspace_id', ...)->where('is_enabled', true)->pluck('feature_key')
```

Returns actual module keys from the applied template.

---

## Curl Test Summary

| Test | Expected | Result |
|---|---|---|
| `/auth/me` before apply | `onboarding_completed: false`, `enabled_modules: []` | ✅ |
| Apply automotive_dealer | 200, template_key + status + applied_at | ✅ |
| `/auth/me` after apply | `onboarding_completed: true`, 12 modules | ✅ |
| Re-apply same template | 200 idempotent | ✅ |
| Apply different template | 409 conflict | ✅ |
| Invalid template | 404 | ✅ |
| Missing X-Workspace-Id | 400 | ✅ |
| Unauthenticated | 401 | ✅ |

---

## Frontend Analyze

```
lib/core/api + app_state.dart + lib/features/onboarding + lib/core/l10n:
No issues found! (0 errors, 0 warnings, 0 infos)
```

---

## Template Key Mapping (Frontend)

| Business Type | Template Key |
|---|---|
| automotive, car, vehicle, dealer | `automotive_dealer` |
| retail, shop, pos, store | `retail_pos` |
| workshop, garage, repair, maintenance | `workshop_service` |
| restaurant, food, café, fnb | `restaurant_fnb` |
| consulting, agency, professional, services | `professional_services` |
| (any other / default) | `professional_services` |

---

## Manual Frontend Checklist

1. Register new user → onboarding screen appears
2. Complete discovery chat → view blueprint
3. Click "Accept & Launch" → loading spinner appears
4. Backend applies template → spinner stops → success view
5. Click "Go to Dashboard" → routes to `/dashboard`
6. Refresh app → session restore → dashboard loads (onboarding_completed = true)
7. If API fails → reverts to blueprint view (user can retry)

---

## Remaining Gaps

| # | Gap | When |
|---|---|---|
| 1 | Template picker UI in onboarding (explicit selection instead of auto-detect) | Future |
| 2 | Force re-apply / template switch | Future |
| 3 | Custom fields rendering engine | Future |
| 4 | Workflow state machine engine | Future |
| 5 | Template versioning / upgrade | Future |
| 6 | Onboarding progress persistence to server | Future |

---

## Step 46 Readiness: ✅ SAFE TO START

Full pipeline operational:
- ✅ Backend: template application service, endpoint, auth session update
- ✅ Frontend: AppState.applyBusinessTemplate → session refresh
- ✅ Frontend: OnboardingState.startRealProvisioning → Accept button wired
- ✅ Modules created as workspace feature flags
- ✅ Roles created/merged from template
- ✅ Owner membership role ensured
- ✅ onboarding_completed = true after apply
- ✅ enabled_modules populated in /auth/me
- ✅ Idempotent: re-apply same template safe
- ✅ 409 conflict for different template
- ✅ All syntax checks pass (PHP + Dart)
- ✅ 8/8 curl tests pass
