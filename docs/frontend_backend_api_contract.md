# SmartBiz AI — Frontend ↔ Backend API Contract

> **Date:** 2026-07-05 | **Version:** 1.0-draft  
> **Frontend:** Flutter/Dart | **Backend:** Laravel 10 + Sanctum  
> **Source:** `docs/frontend_integration_readiness_audit.md`

---

## 1. Overview

The Flutter frontend UI is complete across all modules but uses **100% mock data**. Zero HTTP calls exist. This contract defines the exact API surface needed to replace mock data with backend calls.

**Status:** Frontend ready for integration. Backend has ~80 existing endpoints; ~12 are missing.

---

## 2. API Conventions

| Convention | Value |
|---|---|
| Base URL | `{BASE_URL}/api` (env-configured) |
| Auth | `Authorization: Bearer {sanctum_token}` |
| Workspace | `X-Workspace-Id: {uuid}` header on workspace-scoped routes |
| Content-Type | `application/json` |
| IDs | UUID strings |
| Dates | ISO 8601: `2026-07-05T10:00:00Z` |
| Pagination | `?page=1&per_page=25` |

### Success Response
```json
{ "data": { ... }, "message": "OK" }
```

### Paginated Response
```json
{
  "data": [ ... ],
  "meta": { "current_page": 1, "last_page": 5, "per_page": 25, "total": 120 }
}
```

### Error Response
```json
{ "message": "Unauthenticated.", "errors": {} }
```

### Validation Error (422)
```json
{
  "message": "The given data was invalid.",
  "errors": { "email": ["The email field is required."] }
}
```

---

## 3. Auth & Session

### 3.1 POST /auth/login — ✅ EXISTS

**Frontend:** `LoginScreen` → `AppState.signInAsOwner()` replacement  

```json
// Request
{ "email": "owner@company.com", "password": "secret123" }

// Response 200
{
  "data": {
    "token": "1|abc123...",
    "user": { "id": "uuid", "full_name": "Mohamed Doma", "email": "owner@company.com", "platform_role": "none" },
    "memberships": [
      { "workspace_id": "ws-uuid", "workspace_name": "My Business", "role": "owner", "onboarding_completed": false }
    ]
  }
}
```

**AppState impact:** Set `_authenticated=true`, `_currentUser`, `_currentWorkspace` from first membership, `_currentRole`, `_onboardingCompleted`.

### 3.2 POST /auth/logout — ✅ EXISTS

**Frontend:** Settings/profile sign-out button → `AppState.signOut()` replacement  
```json
// Request: (empty body, auth header only)
// Response 200
{ "message": "Logged out." }
```

### 3.3 GET /auth/me — ✅ EXISTS

**Frontend:** `SplashScreen._scheduleRouting()` — session restore on app startup  
```json
// Response 200
{
  "data": {
    "user": { "id": "uuid", "full_name": "Mohamed Doma", "email": "...", "platform_role": "none", "ui_language": "en" },
    "memberships": [
      { "workspace_id": "ws-uuid", "workspace_name": "My Business", "role": "owner", "onboarding_completed": true,
        "enabled_modules": ["sales", "inventory", "finance"],
        "permissions": ["products.list", "products.create", "invoices.list"] }
    ]
  }
}
```

**Splash flow:** Read stored token → `GET /auth/me` → success? restore session : clear token → `/login`.

### 3.4 POST /auth/register — ⚠️ PROPOSED (missing)

**Frontend:** `RegisterScreen` → `AppState.registerBusinessOwner()` replacement  
```json
// Request
{
  "full_name": "Mohamed Doma",
  "email": "owner@company.com",
  "password": "secret123",
  "password_confirmation": "secret123",
  "workspace_name": "My Business",
  "business_size": "small",
  "business_type": "retail"
}

// Response 201
{
  "data": {
    "token": "1|abc123...",
    "user": { "id": "uuid", "full_name": "Mohamed Doma", "email": "...", "platform_role": "none" },
    "workspace": { "id": "ws-uuid", "name": "My Business", "plan": "trial", "onboarding_completed": false }
  }
}
```

### 3.5 POST /auth/forgot-password — ⚠️ PROPOSED (missing)

**Frontend:** `ForgotPasswordScreen` → currently shows SnackBar only  
```json
// Request
{ "email": "user@company.com" }
// Response 200
{ "message": "Reset link sent." }
```

### 3.6 POST /auth/reset-password — ⚠️ PROPOSED (missing)

```json
// Request
{ "token": "reset-token", "email": "user@company.com", "password": "new123", "password_confirmation": "new123" }
// Response 200
{ "message": "Password reset." }
```

---

## 4. Employee Invite Flow

### 4.1 GET /auth/invite/{token} — ⚠️ PROPOSED (missing)

**Frontend:** `InviteAcceptScreen` → replaces hardcoded mock invite data  
```json
// Response 200
{
  "data": {
    "workspace_name": "SmartBiz Demo Co.",
    "email": "employee@smartbiz.ai",
    "role": "employee",
    "expired": false
  }
}
// Response 404 — invalid/expired token
{ "message": "Invite not found or expired." }
```

### 4.2 POST /auth/invite/accept — ⚠️ PROPOSED (missing)

**Frontend:** `InviteAcceptScreen._handleAccept()` → `AppState.acceptEmployeeInvite()` replacement  
```json
// Request
{ "token": "invite-token", "full_name": "Sara Ahmed", "password": "secret123", "password_confirmation": "secret123" }

// Response 200
{
  "data": {
    "token": "1|abc...",
    "user": { "id": "uuid", "full_name": "Sara Ahmed", "email": "employee@smartbiz.ai", "platform_role": "none" },
    "workspace": { "id": "ws-uuid", "name": "SmartBiz Demo Co.", "role": "employee", "onboarding_completed": true }
  }
}
```

---

## 5. Workspace / Session Restore

**Endpoint:** `GET /auth/me` (section 3.3 above)

The `/auth/me` response must include:
- `platform_role` — for SA guard (`superAdmin` | `none`)
- `memberships[]` — for workspace selection
- Per membership: `role`, `onboarding_completed`, `enabled_modules[]`, `permissions[]`

**Frontend mapping:**
| Backend field | AppState field |
|---|---|
| `user.platform_role` | `_platformRole` |
| `membership.role` | `_currentRole` |
| `membership.onboarding_completed` | `_onboardingCompleted` |
| `membership.enabled_modules` | `WorkspaceModuleState` |
| `membership.permissions` | `BlueprintNavigationController.updatePermissions()` |

---

## 6. Onboarding / Discovery / Blueprint

All endpoints **✅ EXIST** under workspace-scoped routes.

| Endpoint | Method | Frontend Usage |
|---|---|---|
| `POST /discovery/sessions` | ✅ | `OnboardingState` — start discovery |
| `POST /discovery/sessions/{id}/answer` | ✅ | Send user message |
| `POST /discovery/sessions/{id}/classify` | ✅ | AI classification step |
| `POST /discovery/sessions/{id}/generate-blueprint` | ✅ | Generate blueprint |
| `GET /discovery/sessions/{id}/blueprint` | ✅ | Show blueprint result |
| `POST /provisioning/preview` | ✅ | Preview before apply |
| `POST /provisioning/apply` | ✅ | Apply blueprint |
| `GET /provisioning/config` | ✅ | Get current module config |

---

## 7. Customer Workspace Modules

### 7.1 Products — ✅ EXISTS

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET /products` | `ProductsState._data` | `products.list` |
| `GET /products/{id}` | Product detail | `products.show` |
| `POST /products` | `ProductsState.add()` | `products.create` |
| `PUT /products/{id}` | `ProductsState.update()` | `products.update` |
| `DELETE /products/{id}` | `ProductsState.delete()` | `products.delete` |

**Also:** `GET/POST/PUT/DELETE /product-categories` ✅ EXISTS

### 7.2 Contacts (Frontend: "Customers") — ✅ EXISTS

> **⚠️ Naming mismatch:** Frontend uses `Customer` model, backend uses `Contact`.

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET /contacts` | `CustomersState._data` | `contacts.list` |
| `GET /contacts/{id}` | Customer detail | `contacts.show` |
| `POST /contacts` | `CustomersState.add()` | `contacts.create` |
| `PUT /contacts/{id}` | `CustomersState.update()` | `contacts.update` |
| `DELETE /contacts/{id}` | `CustomersState.delete()` | `contacts.delete` |

### 7.3 Invoices — ✅ EXISTS

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET /invoices` | `InvoicesState._data` | `invoices.list` |
| `GET /invoices/{id}` | Invoice detail | `invoices.show` |
| `POST /invoices` | `InvoicesState.add()` | `invoices.create` |
| `PUT /invoices/{id}` | `InvoicesState.update()` | `invoices.update` |

### 7.4 Payments — ✅ EXISTS

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET /payments` | `PaymentsState._data` | `payments.list` |
| `GET /payments/{id}` | Payment detail | `payments.show` |
| `POST /payments` | `PaymentsState.add()` | `payments.create` |
| `POST /payments/{id}/reverse` | `PaymentsState.reverse()` | `payments.create` |

### 7.5 Inventory — ✅ EXISTS

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET /inventory-movements` | `InventoryState._data` | `inventory.list` |
| `GET /inventory-movements/levels` | Stock levels | `inventory.list` |
| `POST /inventory-movements` | `InventoryState.add()` | `inventory.create` |
| `GET/POST/PUT/DELETE /warehouses` | Warehouse management | `warehouses.*` |
| `GET/POST /stock-reservations` | Reservations | `reservations.*` |

### 7.6 Finance — ✅ EXISTS

| Endpoint | Frontend | Permission |
|---|---|---|
| `GET/POST/PUT/DELETE /accounts` | Chart of accounts | `accounts.*` |
| `GET/POST /journal-entries` | `FinanceState` | `journal_entries.*` |
| `GET /reports/sales` | Finance dashboard | `reports.view` |
| `GET /reports/account-balances` | Balance sheet | `reports.view` |
| `GET /reports/receivable-payable` | AR/AP | `reports.view` |

### 7.7 Orders — ✅ EXISTS

| Endpoint | Frontend |
|---|---|
| `GET/POST/PUT /orders` | POS / Order management |

### 7.8 Employees — ⚠️ PROPOSED (missing)

No employee management controller exists. Frontend `EmployeesState`, `RolesState`, `OrgState` need:

| Endpoint | Purpose |
|---|---|
| `GET /employees` | List workspace members |
| `GET /employees/{id}` | Member detail |
| `POST /employees/invite` | Send invite email |
| `PUT /employees/{id}/role` | Change role |
| `DELETE /employees/{id}` | Remove member |
| `GET /roles` | List workspace roles |
| `POST /roles` | Create custom role |
| `PUT /roles/{id}` | Update role permissions |
| `DELETE /roles/{id}` | Delete role |

### 7.9 Settings — ⚠️ PARTIAL

No dedicated workspace settings endpoint. `SettingsState` needs:

| Endpoint | Purpose |
|---|---|
| `GET /workspace/settings` | ⚠️ Proposed — workspace config (name, timezone, currency) |
| `PUT /workspace/settings` | ⚠️ Proposed — update workspace config |
| `GET /workspace/subscription` | ⚠️ Proposed — billing/plan info |

### 7.10 Notifications — ✅ EXISTS

| Endpoint | Frontend |
|---|---|
| `GET /notifications` | Notification list |
| `POST /notifications/{id}/read` | Mark read |
| `POST /notifications/read-all` | Mark all read |

### 7.11 Audit Logs — ✅ EXISTS

| Endpoint | Frontend |
|---|---|
| `GET /audit-logs` | Audit log list |
| `GET /audit-logs/{id}` | Log detail |

---

## 8. AI / Copilot — ✅ EXISTS

| Endpoint | Frontend | Middleware |
|---|---|---|
| `POST /ai/chat` | `AiChatState.sendMessage()` | `CheckAiCredits:ai_chat` |
| `GET /ai/history` | Chat history | — |
| `POST /ai/confirm-action` | Confirm AI suggestion | — |
| `POST /ai/reject-action` | Reject AI suggestion | — |
| `GET /ai/insights` | `AdvisorState._data` | — |
| `POST /ai/insights/generate` | Run analysis | — |
| `POST /ai/insights/{id}/dismiss` | Dismiss insight | — |
| `GET /ai/advisor/recommendations` | Advisor list | — |
| `POST /ai/advisor/run-analysis` | Trigger analysis | — |
| `POST /ai/advisor/{id}/accept` | Accept recommendation | — |
| `POST /ai/advisor/{id}/apply` | Apply recommendation | — |

---

## 9. Super Admin — ✅ MOSTLY EXISTS

All routes under `middleware(['auth:sanctum', SuperAdminMiddleware])`.

### 9.1 Dashboard
| Endpoint | Status | Frontend |
|---|---|---|
| `GET /admin/dashboard` | ✅ | `SuperAdminDashboardScreen` |

### 9.2 Workspaces (Tenants)
| Endpoint | Status | Frontend |
|---|---|---|
| `GET /admin/workspaces` | ✅ | `SuperAdminTenantsScreen` |
| `GET /admin/workspaces/{id}` | ✅ | `SuperAdminTenantDetailScreen` |
| `PUT /admin/workspaces/{id}/status` | ✅ | Suspend/activate |
| `PUT /admin/workspaces/{id}/subscription` | ✅ | Plan change |
| `PUT /admin/workspaces/{id}/trial` | ✅ | Trial extension |
| `PUT /admin/workspaces/{id}/features` | ✅ | Feature flags |
| `POST /admin/workspaces/{id}/credits` | ✅ | AI credit adjustment |

### 9.3 Plans
| Endpoint | Status | Frontend |
|---|---|---|
| `GET /admin/plans` | ✅ | `SuperAdminPlansScreen` |
| `POST /admin/plans` | ✅ | Add plan |
| `PUT /admin/plans/{id}` | ✅ | Edit plan |
| `POST /admin/plans/{id}/prices` | ✅ | Add pricing tier |

### 9.4 Settings / Monitoring
| Endpoint | Status | Frontend |
|---|---|---|
| `GET /admin/settings` | ✅ | Platform config |
| `PUT /admin/settings` | ✅ | Update config |
| `GET /admin/high-usage` | ✅ | `SuperAdminUsageScreen` |

### 9.5 Billing / Manual Payments
| Endpoint | Status | Frontend |
|---|---|---|
| `POST /admin/workspaces/{id}/setup-billing` | ✅ | Stripe setup |
| `GET /admin/workspaces/{id}/payments` | ✅ | Payment history |
| `GET /admin/manual-payments` | ✅ | Manual payments list |
| `POST /admin/manual-payments/{id}/confirm` | ✅ | Confirm payment |
| `POST /admin/manual-payments/{id}/reject` | ✅ | Reject payment |

### 9.6 Health — ✅ EXISTS
`GET /health` (public, unauthenticated)

---

## 10. Frontend Service Mapping

Future service files to create in `lib/core/api/`:

| Service File | Replaces | Endpoints |
|---|---|---|
| `api_client.dart` | — | Base Dio client, token interceptor, workspace header |
| `auth_service.dart` | `AppState` mock methods | `/auth/*` |
| `workspace_service.dart` | — | `/workspace/settings`, `/auth/me` memberships |
| `onboarding_service.dart` | `MockDiscovery` | `/discovery/*`, `/provisioning/*` |
| `products_service.dart` | `MockProducts` | `/products`, `/product-categories` |
| `contacts_service.dart` | `mockCustomers` | `/contacts` |
| `invoices_service.dart` | `MockInvoices` | `/invoices` |
| `payments_service.dart` | `MockPayments` | `/payments` |
| `inventory_service.dart` | `MockInventory` | `/inventory-movements`, `/warehouses` |
| `employees_service.dart` | `MockEmployees` | `/employees`, `/roles` (proposed) |
| `finance_service.dart` | `MockFinance` | `/accounts`, `/journal-entries`, `/reports/*` |
| `ai_service.dart` | `AiChatState` inline | `/ai/*` |
| `admin_service.dart` | `mockTenants` | `/admin/*` |

---

## 11. Backend Missing Endpoints

| # | Endpoint | Priority | Reason |
|---|---|---|---|
| 1 | `POST /auth/register` | **P0** | Cannot complete owner registration |
| 2 | `POST /auth/forgot-password` | **P1** | Forgot password screen is UI-only |
| 3 | `POST /auth/reset-password` | **P1** | Reset flow incomplete |
| 4 | `GET /auth/invite/{token}` | **P1** | Cannot validate invite tokens |
| 5 | `POST /auth/invite/accept` | **P1** | Cannot complete invite acceptance |
| 6 | `GET /employees` | **P2** | Employee list screen has no backend |
| 7 | `POST /employees/invite` | **P2** | Cannot send invites |
| 8 | `GET /roles` | **P2** | Role management has no backend |
| 9 | `POST /roles` | **P2** | Custom role creation |
| 10 | `GET /workspace/settings` | **P2** | Settings screen has no backend |
| 11 | `PUT /workspace/settings` | **P2** | Settings update |
| 12 | `GET /workspace/subscription` | **P3** | Billing info display |

**Total existing:** ~80 endpoints | **Total proposed/missing:** ~12 endpoints

---

## 12. Integration Readiness Checklist

### Frontend Prerequisites
- [ ] Add `dio` + `flutter_secure_storage` to `pubspec.yaml`
- [ ] Create `lib/core/api/api_client.dart` (base client, interceptors)
- [ ] Create `lib/core/api/auth_service.dart`
- [ ] Add `fromJson()` / `toJson()` to all model classes (~12 files)
- [ ] Add `isLoading` / `error` fields to all `ChangeNotifier` states
- [ ] Update `SplashScreen` to attempt token-based session restore
- [ ] Add `X-Workspace-Id` header support in API client
- [ ] Replace `AppState` mock sign-in methods with `AuthService` calls

### Backend Prerequisites
- [ ] Add `POST /auth/register` to `AuthController`
- [ ] Add `POST /auth/forgot-password` (can use Laravel's built-in)
- [ ] Add `POST /auth/reset-password`
- [ ] Add invite token validation + acceptance endpoints
- [ ] Add employee/role management controller
- [ ] Add workspace settings endpoints
- [ ] Verify `/auth/me` returns memberships with modules + permissions

### Integration Order
1. Auth (login/register/me/logout) + token storage
2. Session restore in splash
3. Onboarding/discovery (endpoints exist)
4. Products (simplest CRUD, backend exists)
5. Contacts/Invoices/Payments (backend exists)
6. Inventory + Finance (backend exists)
7. Employees + Roles (needs new controller)
8. Super Admin (backend exists)
9. AI Chat + Advisor (backend exists)

---

## 13. Model Mapping Notes

| Frontend Model | Backend Resource | Key Differences |
|---|---|---|
| `Customer` | `Contact` | **Name mismatch** — add alias or rename |
| `Product` | `Product` | `stockLevel` is computed client-side |
| `Invoice` | `Invoice` | Frontend embeds customer; backend uses `contact_id` |
| `Payment` | `Payment` | Frontend embeds invoice; backend uses `invoice_id` |
| `Warehouse` | `Warehouse` | Match |
| `Employee` | — | No backend model yet |
| `MockTenant` | `Workspace` (SA) | Frontend uses `MockTenant`; backend uses `Workspace` |

**All frontend models need:** `factory Model.fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()`.

---

## 14. Final Recommendation

### Is the frontend ready for integration?

**Yes.** The frontend is structurally complete. The backend has ~80 of the ~92 needed endpoints already implemented. The gap is a **data layer** (HTTP client + JSON serialization), not architecture.

### Recommended First Step

1. Add `dio` + `flutter_secure_storage` packages
2. Create `ApiClient` with token interceptor
3. Create `AuthService` — integrate login, `/auth/me`, logout
4. Update splash to restore session from stored token
5. Integrate Products module as proof-of-concept (backend fully ready)

> Once Products is integrated end-to-end, the same pattern applies to all remaining modules.
