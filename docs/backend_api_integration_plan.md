# SmartBiz AI — Backend/API Integration Execution Plan

> **Date:** 2026-07-05 | **Version:** 1.0  
> **Sources:** `frontend_integration_readiness_audit.md`, `frontend_backend_api_contract.md`

---

## 1. Executive Summary

| Item | Status |
|---|---|
| Frontend UI | ✅ Complete — 17 modules, 151 files |
| Backend API | ✅ ~80 endpoints exist (Laravel + Sanctum) |
| Missing endpoints | ⚠️ ~12 (register, invite, employees, settings) |
| Frontend data layer | ❌ Zero — no HTTP client, no JSON factories, no services |
| Session persistence | ❌ None — no token storage |
| Mock data files | 11 — all must be replaced |

**Strategy:** Build a thin API service layer, integrate auth first, then replace mock data module-by-module while keeping UI stable.

---

## 2. Integration Principles

1. **Auth first** — nothing works without token management
2. **One module end-to-end** before repeating the pattern
3. **Never replace all mock data at once** — keep fallback path
4. **Keep UI stable** — loading/error states before removing mock
5. **No hardcoded URLs** — env-configured base URL
6. **Service layer** — screens never call Dio directly
7. **Secure token storage** — `flutter_secure_storage`, not SharedPreferences
8. **Super Admin isolated** — integrate after customer modules
9. **Keep `/auth/mock-session`** as dev shortcut until real auth is stable

---

## 3. Phase 0 — Pre-Integration Setup

**Goal:** Verify backend runs and accepts requests before writing any client code.

| Task | Owner | Effort |
|---|---|---|
| Backend runs locally (`php artisan serve`) | Backend | XS |
| `GET /api/health` returns 200 | Backend | XS |
| CORS configured for Flutter web (`localhost:*`) | Backend | XS |
| `.env` has `SANCTUM_STATEFUL_DOMAINS` for mobile/web | Backend | XS |
| Confirm Sanctum token flow: login → token → use → logout | Backend | S |
| Confirm `X-Workspace-Id` header handling works | Backend | S |
| Confirm `SetWorkspaceContext` middleware resolves workspace | Backend | S |
| Define frontend `.env` or config for `API_BASE_URL` | Frontend | XS |

**Exit criteria:** `curl -X POST /api/auth/login` returns token; `curl -H "Authorization: Bearer {token}" /api/auth/me` returns user.

---

## 4. Phase 1 — Frontend API Foundation

**Goal:** Create reusable API client infrastructure.

### Files to Create

| File | Purpose | Effort |
|---|---|---|
| `lib/core/api/api_client.dart` | Dio instance, base URL, interceptors | M |
| `lib/core/api/api_exceptions.dart` | Typed error classes (auth, validation, network) | S |
| `lib/core/api/token_storage.dart` | Read/write/clear token via `flutter_secure_storage` | S |

### Files to Modify

| File | Change | Effort |
|---|---|---|
| `pubspec.yaml` | Add `dio`, `flutter_secure_storage` | XS |
| Each `ChangeNotifier` state | Add `isLoading`, `errorMessage` pattern | M (batch) |

### ApiClient Responsibilities
- Dio instance with `baseUrl` from env/config
- Request interceptor: attach `Authorization: Bearer {token}` from storage
- Request interceptor: attach `X-Workspace-Id` from `AppState`
- Response interceptor: 401 → clear token → redirect to `/login`
- Response interceptor: normalize errors into `ApiException`
- No retry logic in v1 (add later)

### Loading/Error State Pattern
```dart
// Add to each ChangeNotifier:
bool _loading = false;
String? _error;
bool get isLoading => _loading;
String? get error => _error;
```

**Risk:** Low — no existing code broken, additive only.  
**Total effort:** M

---

## 5. Phase 2 — Auth + Session Restore

**Goal:** Real login, logout, and session restore on app startup.

### Files to Create

| File | Purpose | Effort |
|---|---|---|
| `lib/core/api/auth_service.dart` | Login, logout, me, wrappers | M |

### Files to Modify

| File | Change | Effort |
|---|---|---|
| `login_screen.dart` | Call `AuthService.login()` instead of `signInAsOwner()` | S |
| `app_state.dart` | Add `restoreSession(token, user, workspace)` method | S |
| `splash_screen.dart` | Read stored token → `GET /auth/me` → route or clear | M |
| `router.dart` | No change needed — guards already use `AppState.isAuthenticated` | — |

### Splash Session Restore Flow
```
App starts → /splash
  → Read token from secure storage
  → Token found? → GET /auth/me
    → Success → populate AppState → route based on role/onboarding
    → 401/fail → clear token → /login
  → No token → /login
```

### Keep Mock Path
`/auth/mock-session` stays. `signInAsOwner()` / `signInAsEmployee()` / `signInAsSuperAdmin()` remain for dev/demo.

### Backend Blockers
None — `POST /auth/login`, `POST /auth/logout`, `GET /auth/me` all exist.

### QA Checklist
- [ ] Login with valid email/password → token stored → dashboard
- [ ] Login with invalid credentials → error message shown
- [ ] Close app → reopen → session restored from token
- [ ] Logout → token cleared → splash → login
- [ ] Token expired → 401 → redirect to login
- [ ] Mock session still works for dev

**Total effort:** M

---

## 6. Phase 3 — Register + Workspace Creation

**Goal:** Owner registration creates real tenant.

### Backend Work (⚠️ missing endpoint)

| Task | Effort |
|---|---|
| Add `register()` to `AuthController` | M |
| Create user + workspace + owner membership in transaction | M |
| Return token + user + workspace | S |
| Set `onboarding_completed_at = null` | XS |

### Frontend Work

| File | Change | Effort |
|---|---|---|
| `register_screen.dart` | Call `AuthService.register()` | S |
| `auth_service.dart` | Add `register()` method | S |

**Total effort:** M  
**Backend blocker:** `POST /auth/register` does not exist yet.

---

## 7. Phase 4 — Employee Invite Flow

**Goal:** Invite links work end-to-end.

### Backend Work (⚠️ missing endpoints)

| Task | Effort |
|---|---|
| Add `GET /auth/invite/{token}` — validate, return invite info | S |
| Add `POST /auth/invite/accept` — create user, join workspace | M |
| Add invite generation from employee management | M |
| Email delivery for invites | M |

### Frontend Work

| File | Change | Effort |
|---|---|---|
| `invite_accept_screen.dart` | Fetch invite info on load, call accept API | S |
| `auth_service.dart` | Add `getInvite()`, `acceptInvite()` | S |

**Total effort:** L (mostly backend)  
**Backend blocker:** No invite endpoints exist.

---

## 8. Phase 5 — Onboarding / Discovery / Blueprint

**Goal:** Real AI-powered discovery + blueprint provisioning.

### Backend Status
All endpoints **exist**: `POST /discovery/sessions`, `POST /{id}/answer`, `POST /{id}/generate-blueprint`, `POST /provisioning/apply`, etc.

### Frontend Work

| File | Change | Effort |
|---|---|---|
| `onboarding_state.dart` | Replace `MockResponse` with API calls | M |
| New `onboarding_service.dart` | Discovery + provisioning wrappers | M |
| `app_state.dart` | Update `isOnboardingCompleted` from backend | S |

### Post-Onboarding
After `POST /provisioning/apply`:
- Refresh `/auth/me` → get updated `enabled_modules` + `permissions`
- Update `WorkspaceModuleState` → navigation rebuilds automatically
- Set `onboarding_completed_at` → router allows dashboard access

**Total effort:** M  
**Backend blocker:** None — endpoints exist.

---

## 9. Phase 6 — First CRUD: Products

**Why Products first:** simplest model, fewest relations, backend fully ready (5 CRUD endpoints), no financial side effects.

### Files to Create

| File | Effort |
|---|---|
| `lib/features/products/products_service.dart` | S |

### Files to Modify

| File | Change | Effort |
|---|---|---|
| `product_models.dart` | Add `fromJson()` / `toJson()` | S |
| `products_state.dart` | Replace `MockProducts` with service calls | M |
| `mock_products.dart` | Keep as fallback, mark deprecated | XS |

### Integration Pattern (reusable for all modules)
1. Add `fromJson`/`toJson` to model
2. Create `XxxService` with CRUD methods using `ApiClient`
3. Replace `Mock` lazy init with `service.fetchAll()`
4. Replace local add/update/delete with service calls
5. Add loading/error states
6. Manual QA: list, create, edit, delete

**Total effort:** M

---

## 10. Phase 7 — Core Customer Modules

Apply the Products pattern to remaining modules.

| Module | Backend Ready | Dependencies | Effort |
|---|---|---|---|
| **Contacts/Customers** | ✅ `/contacts` | ⚠️ naming mismatch | M |
| **Invoices** | ✅ `/invoices` | Needs contacts | M |
| **Payments** | ✅ `/payments` | Needs invoices | M |
| **Inventory** | ✅ `/inventory-movements`, `/warehouses` | Needs products | M |
| **Finance** | ✅ `/accounts`, `/journal-entries`, `/reports/*` | — | L |
| **Orders/POS** | ✅ `/orders` | Needs products + contacts | M |
| **Employees** | ⚠️ Missing controller | Backend blocker | L |
| **Settings** | ⚠️ Missing endpoint | Backend blocker | M |
| **Notifications** | ✅ `/notifications` | — | S |

**Recommended order:** Contacts → Invoices → Payments → Inventory → Finance → Orders → Employees → Settings → Notifications

**Total effort:** XL (largest phase)

---

## 11. Phase 8 — Super Admin Integration

### Backend Status
All SA endpoints **exist** under `/admin/*` with `SuperAdminMiddleware`.

| Screen | Endpoint | Effort |
|---|---|---|
| Dashboard | `GET /admin/dashboard` | S |
| Tenants list | `GET /admin/workspaces` | S |
| Tenant detail | `GET /admin/workspaces/{id}` | M |
| Suspend/activate | `PUT /admin/workspaces/{id}/status` | S |
| Plans CRUD | `GET/POST/PUT /admin/plans` | M |
| Usage/billing | `GET /admin/high-usage` | S |
| Manual payments | `GET/POST /admin/manual-payments` | M |
| Health | `GET /health` | XS |
| Audit logs | `GET /audit-logs` (workspace-scoped) | S |

### Files to Create
`lib/core/api/admin_service.dart` — all SA API calls.

**Total effort:** L  
**Backend blocker:** None.

---

## 12. Phase 9 — AI / Copilot Integration

### Backend Status
All AI endpoints **exist**: `/ai/chat`, `/ai/history`, `/ai/insights`, `/ai/advisor/*`.

| Feature | Endpoint | Effort |
|---|---|---|
| Chat send | `POST /ai/chat` | S |
| Chat history | `GET /ai/history` | S |
| Confirm/reject action | `POST /ai/confirm-action`, `/reject-action` | S |
| Advisor list | `GET /ai/advisor/recommendations` | S |
| Run analysis | `POST /ai/advisor/run-analysis` | S |
| Accept/apply | `POST /ai/advisor/{id}/accept`, `/apply` | S |

### Safety
AI actions that modify data use a confirm/reject flow. Frontend already has confirmation UI.

**Total effort:** M  
**Backend blocker:** None — but AI provider cost depends on usage.

---

## 13. Data Model Work Plan

All models need `factory X.fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()`.

| Category | Files | Effort |
|---|---|---|
| Auth/User/Workspace | `app_state.dart` models | S |
| Product | `product_models.dart` | S |
| Contact/Customer | `customer_models.dart` | S |
| Invoice | `invoice_models.dart` | S |
| Payment | `payment_models.dart` | S |
| Inventory/Warehouse | `inventory_models.dart` | S |
| Employee/Role | `employee_models.dart`, `role_models.dart`, `org_models.dart` | M |
| Finance | `finance_models.dart` | S |
| Admin Tenant | `mock_tenants.dart` → proper model | M |
| AI Chat/Insight | `chat_models.dart`, `advisor_models.dart` | S |
| Dashboard | `dashboard_models.dart` | S |
| Settings | `settings_models.dart` | S |
| Onboarding | `onboarding_models.dart` | S |

**Total:** ~14 files, effort M (batch task).

---

## 14. Cost & Effort Overview

### Development Effort

| Phase | Effort | Notes |
|---|---|---|
| Phase 0 — Pre-Integration | S | Verification only |
| Phase 1 — API Foundation | M | ApiClient + packages |
| Phase 2 — Auth + Session | M | Login, logout, restore |
| Phase 3 — Register | M | Needs backend endpoint |
| Phase 4 — Invite | L | Needs backend + email |
| Phase 5 — Onboarding | M | Backend exists |
| Phase 6 — Products | M | First CRUD |
| Phase 7 — Core Modules | XL | 9 modules |
| Phase 8 — Super Admin | L | Backend exists |
| Phase 9 — AI/Copilot | M | Backend exists |
| Data models batch | M | ~14 files |
| **Total** | **XL** | Estimated 6–10 weeks full-time |

### Infrastructure Costs

| Item | Type | Notes |
|---|---|---|
| `dio`, `flutter_secure_storage` | Free packages | No usage cost |
| Backend hosting (Laravel) | Monthly | Cost depends on provider (VPS / managed) |
| Database (PostgreSQL) | Monthly | Included in hosting or separate |
| Domain + SSL | Annual | Standard web cost |
| Email service (invites, resets) | Usage-based | Cost depends on provider (Mailgun, SES, etc.) |
| AI/LLM API (chat, advisor) | Usage-based | Cost depends on provider/model/tokens |
| Payment gateway (Stripe) | Transaction-based | Cost depends on provider fees |
| File storage (S3 or equivalent) | Usage-based | If product images or documents needed |

> **Note:** Exact vendor prices must be checked separately. No prices are assumed.

---

## 15. MVP — What Can Be Released First

| Feature | Phase | Priority |
|---|---|---|
| Login + session restore | Phase 2 | ✅ MVP |
| Register + workspace creation | Phase 3 | ✅ MVP |
| Onboarding/discovery | Phase 5 | ✅ MVP |
| Products CRUD | Phase 6 | ✅ MVP |
| Contacts/Customers CRUD | Phase 7 | ✅ MVP |
| Invoices + Payments basic | Phase 7 | ✅ MVP |
| Settings basic | Phase 7 | ✅ MVP |

**MVP scope:** Login → Register → Onboarding → Products → Customers → Invoices → Payments  
**Estimated MVP effort:** L (3–5 weeks)

---

## 16. What Should Wait (Post-MVP)

| Feature | Reason |
|---|---|
| Advanced AI actions (auto-apply) | Safety review needed |
| Complex financial reporting | Needs data volume |
| Full billing automation (Stripe) | Needs business/legal setup |
| Advanced role builder | Needs employee management first |
| Multi-workspace switching | Not needed for single-workspace MVP |
| Employee invite flow | Needs email service setup |
| POS module | Placeholder, needs hardware integration planning |
| Super Admin integration | Internal tool, not customer-facing |

---

## 17. Risk Register

| # | Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|---|
| 1 | **Response shape mismatch** — backend JSON doesn't match frontend model fields | M | High | Write `fromJson` carefully, test with real responses early |
| 2 | **Missing backend endpoints** — register, invite, employees | L | Certain | Implement before frontend integration |
| 3 | **Auth token bugs** — 401 loops, token not cleared, stale session | H | Medium | Test splash restore + logout + expiry thoroughly |
| 4 | **Workspace header bugs** — wrong workspace, missing header on requests | H | Medium | Verify `SetWorkspaceContext` middleware with real requests |
| 5 | **Customer/Contact naming** — frontend says Customer, backend says Contact | M | Certain | Add mapping layer or rename consistently |
| 6 | **No loading states** — UI freezes during API calls | M | Certain | Add loading/error pattern before first API call |
| 7 | **AI cost overrun** — unthrottled AI usage | H | Low | Backend already has `CheckAiCredits` middleware |
| 8 | **CORS issues** — Flutter web blocked by backend CORS | M | Medium | Configure CORS before Phase 1 |

---

## 18. First Execution Prompt

### Phase 1A — Add ApiClient + Token Storage Foundation

**Do:**
- Add `dio: ^5.x` and `flutter_secure_storage: ^9.x` to `pubspec.yaml`
- Create `lib/core/api/api_client.dart`:
  - Singleton Dio instance
  - Base URL from compile-time env or config
  - Auth token interceptor (read from `TokenStorage`)
  - Workspace ID interceptor (read from `AppState`)
  - 401 handler: clear token, notify AppState
  - Standard error wrapping
- Create `lib/core/api/token_storage.dart`:
  - `readToken()`, `writeToken()`, `clearToken()`
  - Uses `flutter_secure_storage`
- Create `lib/core/api/api_exceptions.dart`:
  - `ApiException`, `AuthException`, `ValidationException`, `NetworkException`
- Run `flutter analyze` on new files

**Do NOT:**
- Modify any existing screens or state classes
- Replace any mock data yet
- Add auth service (that's Phase 2)
- Change router or AppState
- Run tests
- Touch backend code

**Effort:** M  
**Risk:** Low — purely additive, no existing code changed.

---

> **This plan is ready for execution.** Phase 0 (backend verification) and Phase 1A (API foundation) can start immediately with zero risk to the existing frontend.
