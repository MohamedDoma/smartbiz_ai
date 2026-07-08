# SmartBiz AI — Frontend Integration Readiness Audit

> **Date:** 2026-07-05  
> **Scope:** Flutter frontend (`lib/`) → Laravel backend (`backend/`)  
> **Status:** Pre-integration audit

---

## 1. Executive Summary

| Metric | Value |
|---|---|
| **Frontend readiness** | **~75%** — UI complete, data 100% mock |
| **Total Dart files** | 151 (115 features + 36 core) |
| **Feature modules** | 17 (auth, splash, onboarding, dashboard, products, inventory, invoices, payments, customers, employees, finance, settings, advisor, ai_chat, pos, super_admin, placeholder) |
| **Mock data files** | 11 |
| **API client code** | **0** — no HTTP client, no Dio, no service layer |
| **Backend controllers** | 26 (Laravel, with Sanctum auth + RBAC middleware) |
| **Backend API routes** | ~309 lines (comprehensive CRUD + discovery + provisioning) |
| **Local persistence** | Only `SharedPreferences` for navigation mode |

### What Is Ready
- Complete UI for all customer workspace modules (products, invoices, payments, customers, employees, inventory, finance, settings)
- Complete Super Admin console (tenants, plans, modules, usage, health/audit)
- Full auth screen set (splash, login, register, forgot-password, invite accept, mock session)
- Onboarding/discovery flow with AI conversation simulation
- Dynamic dashboard with module-aware widget visibility
- Blueprint-driven navigation with permissions + mode switching
- L10n (EN/AR) with RTL support
- Router with role-based guards (SA, owner, employee)

### What Is Still Mock/Local
- **Every data source** — all 11 mock files, all `ChangeNotifier` states use hardcoded data
- **Auth** — `signInAsOwner()` / `signInAsEmployee()` / `signInAsSuperAdmin()` are in-memory toggles
- **Session** — no token, no persistence, no refresh logic
- **Workspace** — created in-memory only, no tenant provisioning
- **All CRUD** — create/update/delete operations modify local lists only

---

## 2. Auth & Session

### Current Frontend Behavior
| Flow | Implementation |
|---|---|
| Login | Calls `AppState.signInAsOwner()` → sets `_authenticated = true` in-memory |
| Register | Calls `AppState.registerBusinessOwner(...)` → creates in-memory user + workspace |
| Forgot Password | Shows SnackBar — no backend call |
| Invite Accept | Calls `AppState.acceptEmployeeInvite(...)` → sets employee role in-memory |
| Sign Out | Resets all state to defaults |
| Session Persistence | **None** — refresh = back to `/login` |

### Required Backend Endpoints
| Endpoint | Method | Purpose |
|---|---|---|
| `POST /auth/login` | ✅ **Exists** | Login with email/password, returns Sanctum token |
| `POST /auth/logout` | ✅ **Exists** | Revoke current token |
| `GET /auth/me` | ✅ **Exists** | Return current user + workspace memberships |
| `POST /auth/register` | ⚠️ **Proposed** | Owner registration + tenant creation |
| `POST /auth/forgot-password` | ⚠️ **Proposed** | Send password reset email |
| `POST /auth/reset-password` | ⚠️ **Proposed** | Complete password reset |
| `POST /auth/invite/accept` | ⚠️ **Proposed** | Accept employee invite with token |
| `GET /auth/invite/:token` | ⚠️ **Proposed** | Validate invite token, return invite details |

### Required Frontend Work
1. Add HTTP client (Dio or http) with base URL config
2. Add token storage (`flutter_secure_storage`)
3. Add `AuthService` that wraps API calls
4. Replace `signInAsOwner()` with `AuthService.login(email, password)`
5. Add token interceptor to all API requests
6. Add session restore on app startup (splash screen reads stored token → `GET /auth/me`)
7. Add refresh token handling if applicable

### Blockers
- No `POST /auth/register` route in backend yet
- No invite token validation endpoint
- No password reset endpoints
- Frontend has no HTTP client package in `pubspec.yaml`

---

## 3. Business Owner / Workspace Registration

### Current Mock Flow
```
Register screen → registerBusinessOwner(name, email, workspaceName, size, type)
  → authenticated = true
  → creates in-memory UserInfo + WorkspaceInfo
  → onboardingCompleted = false
  → routes to /onboarding
```

### Required Backend Endpoints
| Endpoint | Method | Payload |
|---|---|---|
| `POST /auth/register` | ⚠️ Proposed | `{ full_name, email, password, workspace_name, business_size, business_type }` |

### Expected Response
```json
{
  "token": "sanctum_token",
  "user": { "id", "full_name", "email" },
  "workspace": { "id", "name", "plan": "trial" },
  "role": "owner"
}
```

### Blockers
- Backend `AuthController` only has `login` / `logout` / `me` — no `register`
- Backend tenant provisioning controller exists (`ProvisioningController`) but may not be wired to registration
- Need to verify if `DiscoveryController` handles onboarding data persistence

---

## 4. Employee Invite Flow

### Current Mock Flow
```
/invite/:token → InviteAcceptScreen
  → shows hardcoded workspace name, email, role
  → user fills name + password
  → acceptEmployeeInvite(name, email, workspaceName)
  → authenticated = true, role = employee, onboarding = true
  → routes to /dashboard
```

### Required Backend Endpoints
| Endpoint | Method | Purpose |
|---|---|---|
| `GET /auth/invite/:token` | ⚠️ Proposed | Validate token, return { workspace_name, email, role, expired } |
| `POST /auth/invite/accept` | ⚠️ Proposed | `{ token, full_name, password }` → create user, return auth token |

### Blockers
- No invite endpoints in backend `api.php`
- Need invite token generation (from employee management or SA console)
- Need email delivery for invites

---

## 5. Customer Workspace Modules

### Module Data Source Matrix

| Module | Mock Data File | State Class | Lines | Backend Controller | Status |
|---|---|---|---|---|---|
| **Products** | `mock_products.dart` | `ProductsState` | 19 | `ProductController` ✅ | Ready to integrate |
| **Inventory** | `mock_inventory.dart` | `InventoryState` | 29 | `InventoryMovementController` ✅ | Ready to integrate |
| **Invoices** | `mock_invoices.dart` | `InvoicesState` | 61 | `InvoiceController` ✅ | Ready to integrate |
| **Payments** | `mock_payments.dart` | `PaymentsState` | 58 | `PaymentController` ✅ | Ready to integrate |
| **Customers** | `mock_customers.dart` | `CustomersState` | 20 | `ContactController` ✅ | Ready — note: backend uses "contacts" |
| **Employees** | `mock_employees.dart` | `EmployeesState` + `RolesState` + `OrgState` | 44 | ⚠️ Not found | Needs backend controller |
| **Finance** | `mock_finance.dart` | `FinanceState` | 38 | `AccountController` + `JournalEntryController` ✅ | Partial — need chart of accounts + reports |
| **Settings** | — (hardcoded) | `SettingsState` | — | ⚠️ Not found | Needs backend workspace settings endpoint |
| **AI Advisor** | `mock_advisor.dart` | `AdvisorState` | 41 | `AiAdvisorController` ✅ | Ready to integrate |
| **AI Chat** | — (in-state) | `AiChatState` | — | `AiChatController` ✅ | Ready to integrate |
| **Dashboard** | — (resolver) | `DynamicDashboardState` | — | ⚠️ Proposed | Needs dashboard config + widget data endpoints |
| **Onboarding** | `mock_discovery.dart` | `OnboardingState` | 83 | `DiscoveryController` + `ProvisioningController` ✅ | Ready to integrate |
| **POS** | — | — | — | ⚠️ Not found | Placeholder module |

### Integration Pattern (per module)
Each module integration requires:
1. Add repository/service class with HTTP calls
2. Replace `Mock*.dart` lazy init with API `fetchAll()` call
3. Replace local CRUD methods (add/update/delete) with API calls
4. Add loading/error states to `ChangeNotifier`
5. Add pagination support where applicable
6. Map backend JSON response to existing frontend model classes

### Key Model Mapping Notes
- Frontend `Customer` ↔ Backend `Contact` (name mismatch)
- Frontend `Product.stockLevel` is computed client-side; backend may differ
- Frontend `Invoice.customer` is embedded; backend likely returns `contact_id`
- All frontend models lack `fromJson` / `toJson` factories

---

## 6. Super Admin

### Screen Data Source Matrix

| Screen | Data Source | Backend | Status |
|---|---|---|---|
| **Dashboard** | Hardcoded summary stats | `SuperAdminController` ✅ | Need stats endpoints |
| **Tenants** | `mock_tenants.dart` (87 lines) | `SuperAdminController` ✅ | Ready — has list/show |
| **Tenant Detail** | `mock_tenants.dart` | `SuperAdminController` ✅ | Ready — has show/update |
| **Plans** | `_seedPlans()` local state | ⚠️ Not found | Needs plans CRUD endpoint |
| **Modules** | `ErpModuleRegistry` (static) | ⚠️ Not found | Module config is frontend-only for now |
| **Usage/Billing** | Derived from `mock_tenants.dart` | ⚠️ Proposed | Needs AI usage aggregation endpoint |
| **Health/Audit** | All inline local data | `HealthController` ✅ + `AuditLogController` ✅ | Ready to integrate |

### Required SA Endpoints
| Endpoint | Status |
|---|---|
| `GET /admin/tenants` | ✅ Exists (`SuperAdminController`) |
| `GET /admin/tenants/:id` | ✅ Exists |
| `PUT /admin/tenants/:id` | ✅ Exists |
| `POST /admin/tenants/:id/suspend` | ✅ Exists |
| `GET /admin/plans` | ⚠️ Proposed |
| `POST /admin/plans` | ⚠️ Proposed |
| `PUT /admin/plans/:id` | ⚠️ Proposed |
| `GET /admin/usage/summary` | ⚠️ Proposed |
| `GET /admin/usage/tenants` | ⚠️ Proposed |
| `GET /admin/health` | ✅ Exists |
| `GET /admin/audit-logs` | ✅ Exists (`AuditLogController`) |

---

## 7. AppState / Local State Replacement Plan

### Keep Local (frontend-only)
| State | Reason |
|---|---|
| `NavigationMode` (basic/advanced) | UI preference, already persisted via SharedPreferences |
| `ShellState` (sidebar open/close) | Layout state |
| Filter/search state per screen | Ephemeral UI state |
| `DynamicDashboardState` layout preferences | May persist later |

### Must Come From Backend
| State | Current Source | Backend Source |
|---|---|---|
| `AppState.isAuthenticated` | In-memory flag | Token presence + `/auth/me` validation |
| `AppState.currentUser` | Hardcoded `_defaultUser` | `/auth/me` response |
| `AppState.currentWorkspace` | Hardcoded `_defaultWorkspace` | `/auth/me` → workspace memberships |
| `AppState.currentRole` | In-memory enum | Backend role from workspace membership |
| `AppState.platformRole` | In-memory enum | Platform role from user record |
| `AppState.isOnboardingCompleted` | In-memory flag | Workspace `onboarding_completed_at` field |
| All module data (products, invoices, etc.) | Mock data files | CRUD API endpoints |
| Employee permissions | Mock set | Backend RBAC role → permissions |

### Must Be Persisted (client-side)
| Item | Storage | Purpose |
|---|---|---|
| Auth token | `flutter_secure_storage` | Session survival across restarts |
| Active workspace ID | `SharedPreferences` | Multi-workspace support |
| UI language preference | `SharedPreferences` | Already in `AppState.uiLanguage` |
| Navigation mode | `SharedPreferences` | Already persisted |

### Should NOT Be Persisted
| Item | Reason |
|---|---|
| Module data (products, invoices, etc.) | Always fetch fresh from API |
| Filter/search state | Ephemeral |
| Dashboard widget data | Always computed fresh |

---

## 8. API Integration Priority

| # | Domain | Effort | Dependency | Notes |
|---|---|---|---|---|
| **1** | Auth/Session | Medium | None | Token storage, login, /auth/me, session restore in splash |
| **2** | Business Registration + Workspace | Medium | #1 | POST /auth/register, tenant provisioning |
| **3** | Employee Invite | Medium | #1 | Invite token endpoints, email delivery |
| **4** | Onboarding/Discovery | Medium | #1, #2 | DiscoveryController + ProvisioningController already exist |
| **5** | Module Navigation + Permissions | Low | #1 | Fetch enabled modules + user permissions from backend |
| **6** | Core Customer Modules | High | #1, #5 | Products → Invoices → Payments → Customers → Inventory → Finance |
| **7** | Super Admin | Medium | #1 | Tenants + health + audit already have controllers |
| **8** | AI Chat / Advisor | Medium | #1, #6 | AiChatController + AiAdvisorController exist |

---

## 9. Risks / Blockers

| # | Blocker | Impact | Mitigation |
|---|---|---|---|
| **1** | **No HTTP client in frontend** | Cannot make any API call | Add `dio` or `http` to pubspec.yaml, create `ApiClient` class |
| **2** | **No `fromJson`/`toJson` on any frontend model** | Cannot deserialize API responses | Add JSON factories to all 12+ model files |
| **3** | **No `POST /auth/register` backend route** | Cannot complete registration flow | Add to `AuthController` |
| **4** | **No invite endpoints** | Cannot complete employee invite flow | Add invite controller or extend AuthController |
| **5** | **"Contacts" vs "Customers" naming** | Frontend says "Customer", backend says "Contact" | Align naming or add mapping layer |
| **6** | **No loading/error states** in any ChangeNotifier | UI has no way to show loading spinners or error banners during API calls | Add `isLoading` / `error` fields to each state class |
| **7** | **No plans CRUD endpoint** | SA plans screen is entirely local | Add plans management to SuperAdminController |
| **8** | **No employee management controller** | Employees module has no backend CRUD | Add EmployeeController |

---

## 10. Final Recommendation

### Is the frontend ready for API contract drafting?

**Yes.** The frontend is structurally complete. Every screen has:
- Defined data models
- State management classes with clear getter/mutation patterns
- UI that renders from those models

The integration path is mechanical — not architectural. No frontend restructuring is needed.

### Recommended Next Steps

1. **Add `dio` + `flutter_secure_storage`** to `pubspec.yaml`
2. **Create `lib/core/api/api_client.dart`** — base client with token interceptor, workspace header, error handling
3. **Create `lib/core/api/auth_service.dart`** — login, register, logout, me, invite accept
4. **Add `fromJson` / `toJson`** to all model classes (can be batch-generated)
5. **Add backend `POST /auth/register`** route + controller method
6. **Replace `AppState` mock methods** with `AuthService` calls
7. **Update splash screen** to attempt session restore: read stored token → `GET /auth/me` → route accordingly
8. **Integrate modules one at a time** starting with Products (simplest CRUD, backend already exists)

> The frontend-to-backend gap is **a data layer gap**, not a UI gap. The UI is production-ready; only the plumbing is missing.
