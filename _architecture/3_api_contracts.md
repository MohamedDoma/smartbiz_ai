# SmartBiz AI — API Contract Specification (v1.0)

> **Authority**: This document is the authoritative API contract specification for the SmartBiz AI platform.
>
> **Cross-references**: Schema: `1_database_schema.sql` | RBAC: `7_roles_permissions_matrix.md` | Business Rules: `6_business_rules.md`
>
> **Convention**: Every endpoint specifies a required RBAC permission key + scope code. No hardcoded job titles.

---

## 1. Introduction & Design Standard

### 1.1 Purpose

This specification defines every API endpoint required to enforce the 168 approved business rules, expose all 17 entity lifecycle FSMs, and serve Flutter clients, platform administration, and AI orchestration services.

### 1.2 Endpoint Specification Fields

| Field | Description |
|-------|-------------|
| **Method** | HTTP verb |
| **Path** | Full versioned path |
| **Purpose** | One-line description |
| **Permission** | RBAC key + scope |
| **Scope** | How scope filters results |
| **Headers** | Required headers |
| **Path params** | URL parameters |
| **Query params** | Filters/pagination |
| **Request body** | JSON with types/constraints |
| **Success response** | HTTP status + body |
| **Error responses** | Error codes + conditions |
| **Idempotency** | required / recommended / not needed |
| **Audit** | Event type logged |
| **Transaction** | DB transaction required? |
| **Business rules** | BR-* IDs enforced |
| **Schema** | Tables involved |

### 1.3 Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Base | `/api/v1/{resource}` | `/api/v1/orders` |
| Resource | Plural nouns, kebab-case | `/api/v1/purchase-orders` |
| Sub-resource | `/{parent}/{id}/{child}` | `/api/v1/orders/{id}/items` |
| Action | `POST /{resource}/{id}/{action}` | `POST /orders/{id}/confirm` |
| Platform | `/api/v1/platform/{resource}` | `/api/v1/platform/workspaces` |
| Batch | `POST /{resource}/batch/{action}` | `POST /approvals/batch/approve` |

---

## 2. API Versioning & Base URLs

| Environment | Base URL |
|-------------|----------|
| Workspace APIs | `/api/v1/` |
| Platform APIs | `/api/v1/platform/` |

Breaking changes MUST NOT occur within the same version.

---

## 3. Authentication & Session Management

### 3.1 Workspace Auth

- **Primary credential**: `email` + `password` (globally unique identity per migration 011/012)
- **Alternative credential**: `phone_number` + `password` (workspace-scoped, requires `X-Workspace-ID` header)
- **Tokens**: JWT access (default 30min) + refresh (rotated on each use)
- **Concurrent sessions**: configurable, default 5
- **Auth database connection**: service-role (bypasses RLS — no workspace context exists at login time)

**Login flow**:
1. User authenticates via `POST /api/v1/auth/login` with `email + password` (or `phone_number + password + X-Workspace-ID`)
2. On success, backend returns user identity + list of workspace memberships
3. Client selects workspace → backend sets `app.workspace_id` for RLS on all subsequent requests
4. Token payload includes: `user_id`, `workspace_id`, `membership_id`

### 3.2 Password Reset

**`POST /api/v1/auth/forgot-password`**

- Request: `{ "email": "string" }`
- Success: `200` (always — prevents email enumeration)
- Side-effect: sends password reset email with time-limited token (1 hour)
- Rate limit: 3 requests per email per hour

**`POST /api/v1/auth/reset-password`**

- Request: `{ "token": "string", "new_password": "string" }`
- Success: `200` with new access + refresh tokens
- Errors: `400` (invalid/expired token), `422` (password policy violation)
- Side-effect: invalidates all existing sessions for the user (security measure)

### 3.3 Headers (all workspace endpoints)

```
Authorization: Bearer <access_token>
X-Workspace-ID: <workspace_uuid>
```

Backend resolves membership via `workspace_memberships` table. Validates: active membership, permission, scope, RLS.

✅ Resolved: `workspace_memberships` table implemented in migration 002.
✅ Resolved: dual RLS policy (`ws_users` + `ws_users_via_membership`) implemented in migration 012.

### 3.4 Platform Auth

- **Credential**: `email` + `password` (via `platform_users` table)
- **Namespace**: `/api/v1/platform/`

---

## 4. Standard Response Format

Success: `{ "success": true, "data": {}, "meta": { "page", "page_size", "total_count", "total_pages" } }`

Error: `{ "success": false, "error": { "code": "...", "message": "...", "details": [...] } }`

---

## 5. Query, Filtering & Search Standard

| Feature | Syntax | Default |
|---------|--------|---------|
| Pagination | `?page=1&page_size=50` | page_size: 50, max: 200 |
| Sorting | `?sort=created_at&order=desc` | created_at desc |
| Exact filter | `?status=draft` | — |
| Multi-value | `?status=draft,confirmed` | — |
| Date range | `?created_after=&created_before=` | — |
| Text search | `?q=term` | — |
| Include | `?include=items,contact` | minimal (no nesting) |

**Search implementation rule** [Core v1]: All `?q=` text search queries MUST be routed through `SearchService` (§28 backend architecture). Controllers MUST NOT use raw SQL `LIKE` / `ILIKE` queries. The SearchService uses PostgreSQL `tsvector` + GIN indexes for v1 and can be swapped to Meilisearch without API changes.

---

## 6. Error, Validation & Concurrency Standard

| Code | HTTP | When |
|------|------|------|
| `validation_error` | 400 | Invalid input |
| `auth_error` | 401 | Missing/expired token |
| `permission_error` | 403 | Insufficient permission/scope |
| `not_found` | 404 | Resource not found or out of scope |
| `conflict_error` | 409 | Duplicate, invalid transition, stale data |
| `approval_required` | 202 | Action needs approval first |
| `entitlement_required` | 402 | Feature requires plan upgrade (BR-SYS-006 Layer 1) |
| `rate_limit` | 429 | Rate limit exceeded |
| `quota_exceeded` | 429 | Usage quota exhausted (BR-SYS-006 Layer 4) |
| `ai_error` | 503 | AI service unavailable |

**Entitlement enforcement** [Core v1]: All feature-gated endpoints pass through `EntitlementMiddleware` (§31 backend architecture). Denial responses include `error_code`, `required_plan`, and `upgrade_url` for frontend upgrade prompts.
| `internal_error` | 500 | Unexpected |

**Stale-transition prevention**: Transition endpoints accept optional `expected_status`. Mismatch → `409`.

**Idempotency**: Financial writes require `Idempotency-Key: <uuid>` header. Same key + same body → cached response. Same key + different body → `409`.

---

## 7. RBAC & Scope Enforcement Standard

Every endpoint annotates: `Permission: {key} @ {scope}`

| Scope | GET effect | Write effect |
|-------|-----------|-------------|
| `own` | Own resources only | Modify own only |
| `team` | Direct reports | Modify team's |
| `dept` | Department-filtered | Modify department |
| `branch` | Branch-filtered | Modify branch |
| `ws` | Workspace-wide | Modify any |
| `wh` | Assigned warehouses | Modify assigned warehouses |

**Field masking**: `base_salary` visible only to `hr.employees.view @ dept|ws`. `cost_price` visible only with finance permissions.

**Resolution**: role permissions → user grants → user denials. Denial wins.

---

## 8. Lifecycle Transition Endpoint Model

- Transitions always use `POST /{resource}/{id}/{action}`, never PATCH for status
- Field updates on drafts use `PATCH /{id}`
- Invalid transition → `409 conflict_error` with `{ current_status, attempted_action }`
- Approval-gated transitions → `202 Accepted` with `{ approval_request_id }`
- `reject` / `cancel` → mandatory `reason` in body
- `reverse` → creates contra record, never deletes

---

## 9. Batch, Async & Heavy Operation Model

**Batch**: `POST /{resource}/batch/{action}` with `{ "ids": [...] }`. Returns per-item results.

**Async**: Operations >30s return `202` with `{ job_id }`. Poll via `GET /jobs/{job_id}`.

**Export**: `GET /{resource}/export?format=csv|pdf`. <10k rows: sync. ≥10k: async job.

---

## 10. Auth Endpoints

### 10.1 Register

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/register` |
| **Purpose** | Create user account |
| **Permission** | Public |
| **Request body** | `{ phone_number: string (required), password: string (required, min 8), full_name: string (required) }` |
| **Success** | `201` `{ user_id, message: "Registration successful" }` |
| **Errors** | `400 validation_error`, `409 conflict_error` (phone exists) |
| **Audit** | `user_registered` |
| **Transaction** | Yes |
| **Business rules** | BR-MBR-004 |
| **Schema** | `users` |

### 10.2 Login

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/login` |
| **Purpose** | Authenticate and obtain tokens |
| **Permission** | Public |
| **Request body** | `{ phone_number: string, password: string }` |
| **Success** | `200` `{ access_token, refresh_token, user: { id, full_name, phone_number, workspace_id, is_active } }` |
| **Errors** | `401 auth_error` (bad credentials), `429 rate_limit` (5/min per IP) |
| **Audit** | `user_login` |
| **Business rules** | BR-MBR-006 |

### 10.3 Refresh Token

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/refresh` |
| **Request body** | `{ refresh_token: string }` |
| **Success** | `200` `{ access_token, refresh_token }` |
| **Errors** | `401 auth_error` |
| **Business rules** | BR-MBR-005 |

### 10.4 Logout

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/logout` |
| **Permission** | Authenticated |
| **Success** | `200` |
| **Audit** | `user_logout` |
| **Business rules** | BR-MBR-005 |

### 10.5 Change Password

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/change-password` |
| **Permission** | Authenticated |
| **Request body** | `{ current_password: string, new_password: string (min 8) }` |
| **Success** | `200` — all sessions invalidated |
| **Errors** | `401 auth_error` (wrong current), `400 validation_error` |
| **Audit** | `password_changed` |
| **Business rules** | BR-MBR-004 |

### 10.6 Request Password Reset

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/reset-password/request` |
| **Permission** | Public |
| **Request body** | `{ phone_number: string }` |
| **Success** | `200` (always, to prevent enumeration) |
| **Rate limit** | 3/hour per phone |

### 10.7 Confirm Password Reset

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/auth/reset-password/confirm` |
| **Request body** | `{ phone_number: string, reset_code: string, new_password: string }` |
| **Success** | `200` — all sessions invalidated |
| **Errors** | `400 validation_error` (invalid/expired code) |

---

## 11. Workspace Endpoints

### 11.1 Create Workspace

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces` |
| **Purpose** | Create a new workspace |
| **Permission** | Authenticated (any user without workspace) |
| **Request body** | `{ name: string (required), industry_type: string, business_size: "micro"|"small"|"medium"|"enterprise" }` |
| **Success** | `201` `{ workspace_id, name, invite_code, subscription_status: "freemium", max_users: 1 }` |
| **Audit** | `workspace_created` |
| **Transaction** | Yes |
| **Business rules** | BR-WKS-001 |
| **Schema** | `workspaces` |

### 11.2 Get Workspace

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/workspaces/{workspace_id}` |
| **Permission** | `admin.workspace.view @ ws` |
| **Success** | `200` workspace object |

### 11.3 Update Workspace Settings

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/workspaces/{workspace_id}` |
| **Permission** | `admin.workspace.update @ ws` |
| **Request body** | `{ name?, industry_type?, business_size?, ui_configuration?: object, onboarding_data?: object }` |
| **Audit** | `workspace_updated` |
| **Business rules** | BR-WKS-002 |

### 11.4 Transfer Ownership

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces/{workspace_id}/transfer-ownership` |
| **Permission** | `admin.workspace.update @ ws` (owner only) |
| **Request body** | `{ new_owner_user_id: UUID }` |
| **Errors** | `403 permission_error` (not owner), `400 validation_error` (target not active) |
| **Audit** | `workspace_ownership_transferred` |
| **Business rules** | BR-WKS-002 |

### 11.5 Request Deletion

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces/{workspace_id}/request-deletion` |
| **Permission** | `admin.workspace.delete @ ws` (owner only) |
| **Success** | `200` `{ status: "pending_deletion", deletion_date }` |
| **Audit** | `workspace_deletion_requested` |
| **Business rules** | BR-WKS-003 |

### 11.6 Cancel Deletion

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces/{workspace_id}/cancel-deletion` |
| **Permission** | `admin.workspace.delete @ ws` (owner only) |
| **Errors** | `409 conflict_error` (not in pending_deletion) |
| **Business rules** | BR-WKS-003 |

### 11.7 Regenerate Invite Code

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces/{workspace_id}/regenerate-invite` |
| **Permission** | `admin.workspace.update @ ws` |
| **Audit** | `invite_code_regenerated` |

### 11.8 Get Workspace Stats

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/workspaces/{workspace_id}/stats` |
| **Permission** | `admin.workspace.view @ ws` |
| **Success** | `200` `{ member_count, active_members, subscription_status, max_users, ai_requests_today }` |

---

## 12. Membership Endpoints

### 12.1 Join Workspace

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/workspaces/join` |
| **Permission** | Authenticated |
| **Request body** | `{ invite_code: string }` |
| **Success** | `201` `{ membership_id, status: "pending" }` |
| **Errors** | `400 validation_error` (invalid code), `409 conflict_error` (already member) |
| **Audit** | `membership_requested` |
| **Business rules** | BR-MBR-001, BR-MBR-002 |
| **✅ Resolved** | `workspace_memberships` — migration 002 |

### 12.2 List Members

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/workspaces/{workspace_id}/members` |
| **Permission** | `admin.users.view @ scope` |
| **Scope** | `own` = self; `dept` = department; `ws` = all |
| **Query params** | `?status=pending|active|suspended&q=&page=&page_size=` |
| **Success** | `200` paginated `{ user_id, full_name, role_id, role_name, department_id, branch_id, status, joined_at }` |

### 12.3 Approve Member

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/memberships/{membership_id}/approve` |
| **Permission** | `admin.users.update @ ws` |
| **Request body** | `{ role_id?: UUID }` |
| **Errors** | `409 conflict_error` (not pending) |
| **Audit** | `membership_approved` |
| **Business rules** | BR-MBR-002 |

### 12.4 Reject Member

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/memberships/{membership_id}/reject` |
| **Permission** | `admin.users.update @ ws` |
| **Request body** | `{ reason: string (required) }` |
| **Audit** | `membership_rejected` |
| **Business rules** | BR-MBR-002 |

### 12.5 Suspend Member

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/memberships/{membership_id}/suspend` |
| **Permission** | `admin.users.update @ ws` |
| **Request body** | `{ reason: string }` |
| **Side-effects** | Sessions invalidated |
| **Audit** | `membership_suspended` |
| **Business rules** | BR-MBR-003 |

### 12.6 Remove Member

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/memberships/{membership_id}/remove` |
| **Permission** | `admin.users.update @ ws` |
| **Request body** | `{ reason: string }` |
| **Side-effects** | Sessions invalidated, offboarding triggered |
| **Audit** | `membership_removed` |
| **Transaction** | Yes |
| **Business rules** | BR-MBR-003, BR-HR-002 |

---

## 13. Role & Permission Endpoints

### 13.1 List Roles

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/roles` |
| **Permission** | `admin.roles.view @ ws` |
| **Query params** | `?is_system=true|false&page=&page_size=` |
| **Success** | `200` paginated `{ id, name, description, is_system, permissions_count, members_count }` |
| **Schema** | `roles` |

### 13.2 Create Role

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/roles` |
| **Permission** | `admin.roles.create @ ws` |
| **Request body** | `{ name: string, description?: string, permissions: [{ key: string, scopes: string[] }], template_from?: UUID }` |
| **Success** | `201` role object |
| **Errors** | `400 validation_error` (invalid key), `409 conflict_error` (name exists) |
| **Audit** | `role_created` |
| **Business rules** | BR-ROL-005 |

### 13.3 Update Role

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/roles/{role_id}` |
| **Permission** | `admin.roles.update @ ws` |
| **Request body** | `{ name?, description?, permissions?: [{ key, scopes }] }` |
| **Errors** | `403 permission_error` (system role), `400 validation_error` (SoD conflict) |
| **Audit** | `role_updated` with old/new permissions |
| **Business rules** | BR-ROL-003, BR-ROL-004, BR-ROL-005 |

### 13.4 Delete Role

| Field | Value |
|-------|-------|
| **Method** | DELETE |
| **Path** | `/api/v1/roles/{role_id}` |
| **Permission** | `admin.roles.delete @ ws` |
| **Errors** | `409 conflict_error` (has members), `403 permission_error` (system role) |
| **Audit** | `role_deleted` |

### 13.5 Assign Role to User

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/users/{user_id}/roles` |
| **Permission** | `admin.roles.assign @ ws` |
| **Request body** | `{ role_id: UUID }` |
| **Errors** | `403 permission_error` (hierarchy violation), `400 validation_error` (SoD) |
| **Side-effects** | Session invalidated |
| **Audit** | `role_assigned` |
| **Business rules** | BR-ROL-001, BR-ROL-003 |

### 13.6 Set User Permission Override

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/users/{user_id}/permission-overrides` |
| **Permission** | `admin.roles.assign @ ws` |
| **Request body** | `{ permission_key: string, scope: string, type: "grant"|"deny" }` |
| **Audit** | `permission_override_set` |
| **Business rules** | BR-ROL-006 |

### 13.7 Remove User Permission Override

| Field | Value |
|-------|-------|
| **Method** | DELETE |
| **Path** | `/api/v1/users/{user_id}/permission-overrides/{override_id}` |
| **Permission** | `admin.roles.assign @ ws` |
| **Audit** | `permission_override_removed` |

### 13.8 Validate SoD

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/roles/validate-sod` |
| **Permission** | `admin.roles.view @ ws` |
| **Request body** | `{ permissions: [{ key, scopes }] }` |
| **Success** | `200` `{ valid: boolean, conflicts: [{ pair, reason }] }` |
| **Business rules** | BR-ROL-004 |

### 13.9 Create Delegation

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delegations` |
| **Permission** | `admin.roles.assign @ ws` |
| **Request body** | `{ delegator_user_id: UUID, delegate_user_id: UUID, permission_keys: string[], start_date: datetime, end_date: datetime, reason: string }` |
| **Audit** | `delegation_created` |
| **Business rules** | BR-ROL-007 |
| **✅ Resolved** | `permission_delegations` — migration 002 |

---

## 14. User / Employee Endpoints

### 14.1 List Users

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/users` |
| **Permission** | `admin.users.view @ scope` |
| **Scope** | `own` = self; `team` = reports; `dept` = department; `ws` = all |
| **Query params** | `?status=active|suspended&department_id=&branch_id=&role_id=&q=&page=&page_size=&include=role` |
| **Success** | `200` paginated `{ id, full_name, phone_number, role_id, department_id, branch_id, is_active, hire_date }` |
| **Field masking** | `base_salary`, `annual_leave_balance` visible only with `hr.employees.view @ scope` |

### 14.2 Get User

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/users/{user_id}` |
| **Permission** | `admin.users.view @ scope` |
| **Query params** | `?include=role,department,branch` |

### 14.3 Get Own Profile

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/users/me` |
| **Permission** | Authenticated |
| **Success** | `200` full profile including salary, leave balance, shift, manager |

### 14.4 Update Own Profile

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/users/me` |
| **Permission** | `admin.users.update @ own` |
| **Request body** | `{ phone_number?, emergency_contact?, profile_photo_url?, preferred_language?, notification_preferences? }` |
| **Restricted** | `full_name`, `base_salary`, `department_id`, `branch_id`, `role_id` NOT self-editable |
| **Audit** | `profile_self_updated` |
| **Business rules** | BR-HR-004 |

### 14.5 Update User Assignment

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/users/{user_id}/assignment` |
| **Permission** | `hr.employees.update @ scope` |
| **Request body** | `{ department_id?, branch_id?, manager_id?, shift_id?, base_salary?, hire_date? }` |
| **Audit** | `user_assignment_updated` |
| **Business rules** | BR-HR-001 |

### 14.6 Deactivate User

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/users/{user_id}/deactivate` |
| **Permission** | `admin.users.update @ ws` |
| **Side-effects** | Sessions invalidated, leave settled, final payroll triggered |
| **Audit** | `employee_offboarded` |
| **Transaction** | Yes |
| **Business rules** | BR-HR-002 |

### 14.7 Department CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|--------|
| GET | `/api/v1/departments` | `admin.departments.view @ ws` | List departments |
| POST | `/api/v1/departments` | `admin.departments.create @ ws` | Create department |
| GET | `/api/v1/departments/{id}` | `admin.departments.view @ ws` | Get department |
| PATCH | `/api/v1/departments/{id}` | `admin.departments.update @ ws` | Update |
| DELETE | `/api/v1/departments/{id}` | `admin.departments.delete @ ws` | Delete (if no members) |

Create body: `{ name: string (required), parent_department_id?: UUID, manager_user_id?: UUID, description?: string }`
Schema: `departments`
✅ Resolved: `departments` table exists in base schema.

### 14.8 Branch CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|--------|
| GET | `/api/v1/branches` | `admin.branches.view @ ws` | List branches |
| POST | `/api/v1/branches` | `admin.branches.create @ ws` | Create branch |
| GET | `/api/v1/branches/{id}` | `admin.branches.view @ ws` | Get branch |
| PATCH | `/api/v1/branches/{id}` | `admin.branches.update @ ws` | Update |
| DELETE | `/api/v1/branches/{id}` | `admin.branches.delete @ ws` | Delete (if no members) |

Create body: `{ name: string (required), address?: string, phone?: string, is_active?: boolean }`
Schema: `branches`
✅ Resolved: `branches` table exists in base schema.

### 14.9 Shift CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|--------|
| GET | `/api/v1/shifts` | `hr.shifts.view @ ws` | List shifts |
| POST | `/api/v1/shifts` | `hr.shifts.create @ ws` | Create shift |
| GET | `/api/v1/shifts/{id}` | `hr.shifts.view @ ws` | Get shift |
| PATCH | `/api/v1/shifts/{id}` | `hr.shifts.update @ ws` | Update |
| DELETE | `/api/v1/shifts/{id}` | `hr.shifts.delete @ ws` | Delete (if unassigned) |

Create body: `{ name: string (required), start_time: time, end_time: time, break_minutes?: int, is_overnight?: boolean }`
Schema: `shifts`
✅ Resolved: `shifts` table exists in base schema.

---

## 15. Contact Endpoints

### 15.1 List Contacts

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/contacts` |
| **Permission** | `sales.contacts.view @ scope` or `purchasing.contacts.view @ scope` |
| **Query params** | `?type=customer|supplier|both&q=&is_active=&page=&page_size=` |
| **Success** | `200` paginated `{ id, name, type, email, phone, tax_number, balance, is_active }` |
| **Schema** | `contacts` |

### 15.2 Create Contact

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/contacts` |
| **Permission** | `sales.contacts.create @ scope` or `purchasing.contacts.create @ scope` |
| **Request body** | `{ name: string (required), type: "customer"|"supplier"|"both" (required), email?, phone?, address?, tax_number?, credit_limit?: decimal, payment_terms_days?: int }` |
| **Success** | `201` contact |
| **Errors** | `409 conflict_error` (duplicate) |
| **Audit** | `contact_created` |

### 15.3 Get Contact

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/contacts/{contact_id}` |
| **Permission** | `sales.contacts.view @ scope` or `purchasing.contacts.view @ scope` |
| **Query params** | `?include=orders,invoices,payments` |

### 15.4 Update Contact

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/contacts/{contact_id}` |
| **Permission** | `sales.contacts.update @ scope` or `purchasing.contacts.update @ scope` |
| **Audit** | `contact_updated` |

### 15.5 Get Contact Balance

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/contacts/{contact_id}/balance` |
| **Permission** | `finance.payments.view @ scope` |
| **Success** | `200` `{ total_invoiced, total_paid, total_outstanding, total_overdue, credit_balance }` |

### 15.6 Batch Import Contacts

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/contacts/batch/import` |
| **Permission** | `sales.contacts.create @ ws` |
| **Request body** | `{ contacts: [...] }` (max 500) |
| **Success** | `200` `{ imported: N, failed: N, errors: [...] }` |

---

## 16. Product & Catalog Endpoints

### 16.1 List Products

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/products` |
| **Permission** | `inventory.products.view @ scope` |
| **Query params** | `?category_id=&type=physical|service|digital|subscription&q=&is_active=&page=&page_size=&include=category,tax` |
| **Field masking** | `cost_price` hidden without finance permissions |
| **Schema** | `products` |

### 16.2 Create Product

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/products` |
| **Permission** | `inventory.products.create @ scope` |
| **Request body** | `{ name: string (required), base_price: decimal (required), cost_price?: decimal, sku?: string, type: "physical"|"service"|"digital"|"subscription" (required), category_id?: UUID, unit_id?: UUID, tax_id?: UUID, min_stock_alert?: int, description?: string, dynamic_attributes?: object }` |
| **Errors** | `409 conflict_error` (SKU duplicate) |
| **Audit** | `product_created` |

### 16.3 Get Product

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/products/{product_id}` |
| **Permission** | `inventory.products.view @ scope` |
| **Query params** | `?include=category,tax,stock_levels,variants` |

### 16.4 Update Product

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/products/{product_id}` |
| **Permission** | `inventory.products.update @ scope` |
| **Audit** | `product_updated` |

### 16.5 Delete Product (Soft)

| Field | Value |
|-------|-------|
| **Method** | DELETE |
| **Path** | `/api/v1/products/{product_id}` |
| **Permission** | `inventory.products.delete @ scope` |
| **Errors** | `409 conflict_error` (referenced by active orders/invoices) |
| **Audit** | `product_deleted` |
| **Business rules** | BR-XMD-008 |

### 16.6 Batch Import Products

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/products/batch/import` |
| **Permission** | `inventory.products.create @ ws` |
| **Request body** | `{ products: [...] }` (max 500) |
| **Success** | `200` `{ imported, failed, errors }` |

### 16.7 Category CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/categories` | `inventory.products.view @ scope` | List (tree) |
| POST | `/api/v1/categories` | `inventory.products.create @ ws` | Create |
| PATCH | `/api/v1/categories/{id}` | `inventory.products.update @ ws` | Update |
| DELETE | `/api/v1/categories/{id}` | `inventory.products.delete @ ws` | Delete (if empty) |

### 16.8 Tax Rate CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/tax-rates` | `finance.settings.view @ ws` | List |
| POST | `/api/v1/tax-rates` | `finance.settings.update @ ws` | Create |
| PATCH | `/api/v1/tax-rates/{id}` | `finance.settings.update @ ws` | Update |

Create body: `{ name, rate: decimal, type: "inclusive"|"exclusive", is_compound: boolean }`
Business rules: BR-INV-007 | Schema: `taxes`

### 16.9 Unit CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/units` | `inventory.products.view @ scope` | List |
| POST | `/api/v1/units` | `inventory.products.create @ ws` | Create |
| PATCH | `/api/v1/units/{id}` | `inventory.products.update @ ws` | Update |

---

## 17. Warehouse & Inventory Endpoints

### 17.1 Warehouse CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/warehouses` | `inventory.warehouses.view @ scope` | List warehouses |
| POST | `/api/v1/warehouses` | `inventory.warehouses.create @ ws` | Create warehouse |
| GET | `/api/v1/warehouses/{id}` | `inventory.warehouses.view @ scope` | Get warehouse |
| PATCH | `/api/v1/warehouses/{id}` | `inventory.warehouses.update @ ws` | Update |

Schema: `warehouses`

### 17.2 Get Inventory Levels

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/inventory-levels` |
| **Permission** | `inventory.levels.view @ scope` |
| **Scope** | `wh` = assigned warehouses; `ws` = all |
| **Query params** | `?warehouse_id=&product_id=&below_reorder=true&page=&page_size=` |
| **Success** | `200` paginated `{ product_id, warehouse_id, quantity, reserved_quantity, available_quantity, reorder_point }` |
| **Schema** | `inventory_levels` |

### 17.3 Adjust Inventory

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/inventory/adjust` |
| **Purpose** | Manual stock adjustment (damage, shrinkage, count correction) |
| **Permission** | `inventory.levels.adjust @ scope` |
| **Request body** | `{ product_id: UUID, warehouse_id: UUID, variant_id?: UUID, change_type: "manual_adjustment"|"damage"|"shrinkage"|"expired", quantity_changed: decimal, notes: string (required) }` |
| **Success** | `200` `{ new_quantity, movement_id }` |
| **Errors** | `409 conflict_error` (negative stock if not allowed per BR-STK-004) |
| **Idempotency** | Recommended |
| **Audit** | `inventory_adjusted` |
| **Transaction** | Yes |
| **Business rules** | BR-STK-005, BR-STK-006, BR-STK-013 |
| **Schema** | `inventory_movements`, `inventory_levels` |

### 17.4 List Inventory Movements

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/inventory-movements` |
| **Permission** | `inventory.levels.view @ scope` |
| **Query params** | `?product_id=&warehouse_id=&type=sale|purchase|adjustment|transfer|production_consume|production_output&created_after=&created_before=&page=&page_size=` |
| **Schema** | `inventory_movements` |

### 17.5 Set Opening Balance

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/inventory/opening-balance` |
| **Permission** | `inventory.levels.adjust @ ws` |
| **Request body** | `{ product_id: UUID, warehouse_id: UUID, quantity: decimal }` |
| **Business rules** | BR-STK-014 |

### 17.6 Get Low-Stock Alerts

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/inventory/low-stock` |
| **Permission** | `inventory.levels.view @ scope` |
| **Success** | `200` list of products below `reorder_point` |
| **Business rules** | BR-STK-012 |

### 17.7 Get Product Stock by Warehouse

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/products/{product_id}/stock` |
| **Permission** | `inventory.levels.view @ scope` |
| **Success** | `200` `[ { warehouse_id, warehouse_name, quantity, reserved, available } ]` |

### 17.8 List Batches / Lots

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/inventory-batches` |
| **Permission** | `inventory.levels.view @ scope` |
| **Query params** | `?product_id=&warehouse_id=&expiry_before=&page=&page_size=` |
| **Business rules** | BR-STK-007 |

---

## 18. Stock Transfer Endpoints

### 18.1 Create Transfer

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/stock-transfers` |
| **Permission** | `inventory.transfers.create @ scope` |
| **Request body** | `{ from_warehouse_id: UUID, to_warehouse_id: UUID, items: [{ product_id, variant_id?, quantity }], notes? }` |
| **Success** | `201` transfer in `draft` status |
| **Schema** | `stock_transfers`, `stock_transfer_items` |
| **Business rules** | BR-STK-008 |

### 18.2 List Transfers

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/stock-transfers` |
| **Permission** | `inventory.transfers.view @ scope` |
| **Query params** | `?status=draft|pending_approval|approved|in_transit|received|cancelled&warehouse_id=&page=&page_size=` |

### 18.3 Get Transfer

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/stock-transfers/{transfer_id}` |
| **Permission** | `inventory.transfers.view @ scope` |
| **Query params** | `?include=items` |

### 18.4 Submit for Approval

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/stock-transfers/{transfer_id}/submit` |
| **Permission** | `inventory.transfers.create @ scope` |
| **Errors** | `409 conflict_error` (not draft) |
| **Business rules** | BR-STK-008, BR-APR-001 |

### 18.5 Approve Transfer

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/stock-transfers/{transfer_id}/approve` |
| **Permission** | `inventory.transfers.approve @ scope` |
| **Errors** | `409 conflict_error` (not pending_approval) |
| **Audit** | `transfer_approved` |

### 18.6 Dispatch Transfer

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/stock-transfers/{transfer_id}/dispatch` |
| **Permission** | `inventory.transfers.update @ scope` |
| **Side-effects** | Stock deducted from source warehouse (in_transit) |
| **Audit** | `transfer_dispatched` |
| **Transaction** | Yes |

### 18.7 Receive Transfer

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/stock-transfers/{transfer_id}/receive` |
| **Permission** | `inventory.transfers.update @ scope` |
| **Request body** | `{ received_items: [{ product_id, quantity_received }] }` |
| **Side-effects** | Stock added to destination warehouse |
| **Audit** | `transfer_received` |
| **Transaction** | Yes |

---

## 19. Sales Order Endpoints

### 19.1 Create Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/orders` |
| **Permission** | `sales.orders.create @ scope` |
| **Request body** | `{ contact_id?: UUID, branch_id?: UUID, order_type: "sale_order"|"dine_in"|"takeaway"|"quote", currency: string (default "LYD"), exchange_rate?: decimal, valid_until?: date, notes?: string, items: [{ product_id: UUID, variant_id?: UUID, unit_id?: UUID, quantity: decimal, unit_price: decimal }] }` |
| **Success** | `201` order in `draft` with auto-generated `order_number` |
| **Idempotency** | Recommended |
| **Audit** | `order_created` |
| **Transaction** | Yes |
| **Business rules** | BR-ORD-001, BR-ORD-002 |
| **Schema** | `orders`, `order_items`, `document_sequences` |

### 19.2 List Orders

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/orders` |
| **Permission** | `sales.orders.view @ scope` |
| **Query params** | `?status=draft|confirmed|partially_fulfilled|fulfilled|cancelled|closed&contact_id=&order_type=&created_after=&created_before=&page=&page_size=&include=items,contact` |

### 19.3 Get Order

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/orders/{order_id}` |
| **Permission** | `sales.orders.view @ scope` |
| **Query params** | `?include=items,contact,invoices,shipments` |

### 19.4 Update Draft Order

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/orders/{order_id}` |
| **Permission** | `sales.orders.update @ scope` |
| **Errors** | `409 conflict_error` (not in draft) |
| **Business rules** | BR-ORD-001 |

### 19.5 Confirm Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/orders/{order_id}/confirm` |
| **Permission** | `sales.orders.update @ scope` |
| **Request body** | `{ expected_status?: "draft" }` |
| **Side-effects** | Stock reservations created (BR-STK-001), price snapshot locked |
| **Errors** | `409 conflict_error` (not draft, insufficient stock) |
| **Audit** | `order_confirmed` |
| **Transaction** | Yes |
| **Business rules** | BR-ORD-001, BR-ORD-003, BR-ORD-006, BR-STK-001 |

### 19.6 Cancel Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/orders/{order_id}/cancel` |
| **Permission** | `sales.orders.update @ scope` |
| **Request body** | `{ reason: string (required), expected_status?: string }` |
| **Errors** | `409 conflict_error` (fully fulfilled or closed) |
| **Side-effects** | Reservations released, unfulfilled shipments cancelled |
| **Audit** | `order_cancelled` |
| **Transaction** | Yes |
| **Business rules** | BR-ORD-005, BR-XMD-007 |

### 19.7 Close Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/orders/{order_id}/close` |
| **Permission** | `sales.orders.update @ scope` |
| **Errors** | `409 conflict_error` (not fulfilled) |
| **Business rules** | BR-ORD-001 |

### 19.8 Convert to Invoice

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/orders/{order_id}/convert-to-invoice` |
| **Permission** | `finance.invoices.create @ scope` |
| **Success** | `201` draft invoice linked to order |
| **Transaction** | Yes |

---

## 20. Invoice & Credit Note Endpoints

### 20.1 Create Invoice

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/invoices` |
| **Permission** | `finance.invoices.create @ scope` |
| **Request body** | `{ contact_id?: UUID, order_id?: UUID, branch_id?: UUID, invoice_type: "sale"|"purchase", currency: string (default "LYD"), exchange_rate?: decimal, due_date: date, notes?: string, items: [{ product_id: UUID, variant_id?: UUID, unit_id?: UUID, warehouse_id?: UUID, quantity: decimal, unit_price: decimal, discount_amount?: decimal, tax_id?: UUID }] }` |
| **Success** | `201` invoice in `draft` with auto-generated `invoice_number`, server-computed totals |
| **Idempotency** | Required |
| **Audit** | `invoice_created` |
| **Transaction** | Yes |
| **Business rules** | BR-INV-001, BR-INV-005, BR-INV-007, BR-INV-008, BR-INV-010 |
| **Schema** | `invoices`, `invoice_items`, `document_sequences` |

### 20.2 List Invoices

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/invoices` |
| **Permission** | `finance.invoices.view @ scope` |
| **Query params** | `?status=draft|issued|partially_paid|paid|overdue|cancelled|voided&invoice_type=&contact_id=&due_before=&due_after=&page=&page_size=&include=contact` |

### 20.3 Get Invoice

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/invoices/{invoice_id}` |
| **Permission** | `finance.invoices.view @ scope` |
| **Query params** | `?include=items,payments,order,credit_notes` |

### 20.4 Update Draft Invoice

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/invoices/{invoice_id}` |
| **Permission** | `finance.invoices.update @ scope` |
| **Errors** | `409 conflict_error` (not draft) |

### 20.5 Issue Invoice

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/invoices/{invoice_id}/issue` |
| **Permission** | `finance.invoices.update @ scope` |
| **Side-effects** | Journal entry posted (debit receivable, credit revenue), invoice immutable |
| **Audit** | `invoice_issued` |
| **Transaction** | Yes |
| **Business rules** | BR-INV-001, BR-INV-002, BR-FIN-001, BR-XMD-001 |

### 20.6 Cancel Invoice

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/invoices/{invoice_id}/cancel` |
| **Permission** | `finance.invoices.update @ scope` |
| **Request body** | `{ reason: string (required) }` |
| **Errors** | `409 conflict_error` (has payments — must refund first) |
| **Side-effects** | Reversal journal entry if issued |
| **Audit** | `invoice_cancelled` |
| **Business rules** | BR-INV-003 |

### 20.7 Create Credit Note

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/invoices/{invoice_id}/credit-note` |
| **Permission** | `finance.invoices.create @ scope` |
| **Request body** | `{ items: [{ invoice_item_id: UUID, quantity: decimal, reason: string }] }` |
| **Side-effects** | Reversal journal entry posted |
| **Audit** | `credit_note_issued` |
| **Transaction** | Yes |
| **Business rules** | BR-INV-004, BR-XMD-003 |
| **✅ Resolved** | `credit_notes` + `credit_note_items` — migration 003 |

### 20.8 Export Invoice PDF

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/invoices/{invoice_id}/export` |
| **Permission** | `finance.invoices.view @ scope` |
| **Query params** | `?format=pdf` |
| **Business rules** | BR-INV-009 |

### 20.9 List Invoice Payments

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/invoices/{invoice_id}/payments` |
| **Permission** | `finance.payments.view @ scope` |

---

## 21. Payment Endpoints

### 21.1 Record Payment

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payments` |
| **Permission** | `finance.payments.create @ scope` |
| **Request body** | `{ invoice_id: UUID, account_id?: UUID, amount: decimal (>0), payment_method: "cash"|"bank_transfer"|"check"|"card"|"mobile_payment", reference_number?: string, payment_date: date }` |
| **Success** | `201` payment with auto-generated `payment_number` |
| **Side-effects** | Invoice status updated; journal entry posted; overpayment → customer credit |
| **Idempotency** | Required |
| **Audit** | `payment_recorded` |
| **Transaction** | Yes |
| **Business rules** | BR-PAY-001, BR-PAY-002, BR-PAY-003, BR-PAY-004, BR-PAY-009, BR-XMD-001 |
| **Headers** | `Idempotency-Key: <uuid>` (REQUIRED per BR-PAY-009) |
| **Schema** | `payments`, `invoices`, `journal_entries`, `journal_lines`, `idempotency_keys` |

### 21.2 List Payments

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/payments` |
| **Permission** | `finance.payments.view @ scope` |
| **Query params** | `?status=pending|completed|failed|reversed&payment_method=&contact_id=&created_after=&created_before=&page=&page_size=` |

### 21.3 Get Payment

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/payments/{payment_id}` |
| **Permission** | `finance.payments.view @ scope` |

### 21.4 Reverse Payment

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payments/{payment_id}/reverse` |
| **Permission** | `finance.payments.approve @ scope` |
| **Request body** | `{ reason: string (required) }` |
| **Side-effects** | Contra payment, reversal journal, invoice status updated |
| **Approval** | May return `202 approval_required` if above threshold |
| **Audit** | `payment_reversed` |
| **Transaction** | Yes |
| **Business rules** | BR-PAY-005, BR-APR-001 |
| **✅ Resolved** | `payments.reversal_of`, `payments.is_reversal` — migration 003 |

### 21.5 Create Refund

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/refunds` |
| **Permission** | `finance.payments.create @ scope` |
| **Request body** | `{ return_id?: UUID, invoice_id?: UUID, amount: decimal, payment_method: string, reason: string }` |
| **Approval** | `202 approval_required` if above threshold |
| **Audit** | `refund_processed` |
| **Transaction** | Yes |
| **Business rules** | BR-RFD-005, BR-RFD-006, BR-XMD-003 |

### 21.6 Get Payment Receipt

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/payments/{payment_id}/receipt` |
| **Permission** | `finance.payments.view @ scope` |
| **Success** | `200` PDF receipt |

### 21.7 Apply Customer Credit

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payments/apply-credit` |
| **Permission** | `finance.payments.create @ scope` |
| **Request body** | `{ contact_id: UUID, invoice_id: UUID, amount: decimal }` |
| **Business rules** | BR-PAY-004 |
| **✅ Resolved** | `customer_credits` table — migration 003 |

---

## 22. Purchasing Endpoints

### 22.1 Create Purchase Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders` |
| **Permission** | `purchasing.orders.create @ scope` |
| **Request body** | `{ supplier_contact_id: UUID, branch_id?: UUID, currency: string (default "LYD"), exchange_rate?: decimal, expected_delivery_date?: date, notes?: string, items: [{ product_id: UUID, variant_id?: UUID, quantity: decimal, unit_price: decimal }] }` |
| **Success** | `201` PO in `draft` with auto-generated `po_number` |
| **Audit** | `po_created` |
| **Business rules** | BR-PUR-001 |
| **Schema** | `purchase_orders`, `purchase_order_items`, `document_sequences` |

### 22.2 List Purchase Orders

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/purchase-orders` |
| **Permission** | `purchasing.orders.view @ scope` |
| **Query params** | `?status=draft|submitted|approved|partially_received|received|invoiced|closed|cancelled|rejected&supplier_id=&page=&page_size=` |

### 22.3 Get Purchase Order

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/purchase-orders/{po_id}` |
| **Permission** | `purchasing.orders.view @ scope` |
| **Query params** | `?include=items,supplier,grn` |

### 22.4 Update Draft PO

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/purchase-orders/{po_id}` |
| **Permission** | `purchasing.orders.update @ scope` |
| **Errors** | `409 conflict_error` (not draft) |

### 22.5 Submit PO

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/submit` |
| **Permission** | `purchasing.orders.update @ scope` |
| **Side-effects** | Creates approval request if above threshold |
| **Approval** | Auto-approved if ≤ threshold; `202 approval_required` if above |
| **Business rules** | BR-PUR-001, BR-PUR-002, BR-APR-001 |

### 22.6 Approve PO

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/approve` |
| **Permission** | `purchasing.orders.approve @ scope` |
| **Audit** | `po_approved` |

### 22.7 Reject PO

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/reject` |
| **Permission** | `purchasing.orders.approve @ scope` |
| **Request body** | `{ reason: string (required) }` |
| **Audit** | `po_rejected` |

### 22.8 Cancel PO

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/cancel` |
| **Permission** | `purchasing.orders.update @ scope` |
| **Request body** | `{ reason: string }` |
| **Errors** | `409 conflict_error` (has received items) |
| **Business rules** | BR-PUR-008 |

### 22.9 Record GRN (Goods Received)

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/receive` |
| **Permission** | `purchasing.receiving.create @ scope` |
| **Request body** | `{ warehouse_id: UUID, items: [{ po_item_id: UUID, quantity_received: decimal, batch_number?: string, expiry_date?: date }] }` |
| **Side-effects** | Inventory increased, PO status → `partially_received` or `received` |
| **Audit** | `grn_recorded` |
| **Transaction** | Yes |
| **Business rules** | BR-PUR-003, BR-XMD-002 |
| **✅ Resolved** | `goods_received_notes` + `grn_items` — migration 005 |

### 22.10 Match Supplier Invoice

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/purchase-orders/{po_id}/match-invoice` |
| **Purpose** | 3-way match: PO ↔ GRN ↔ supplier invoice |
| **Permission** | `purchasing.invoices.create @ scope` |
| **Request body** | `{ supplier_invoice_number: string, invoice_amount: decimal, invoice_date: date }` |
| **Errors** | `409 conflict_error` (amount mismatch beyond tolerance) |
| **Business rules** | BR-PUR-005 |

### 22.11 Export PO

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/purchase-orders/{po_id}/export` |
| **Permission** | `purchasing.orders.view @ scope` |
| **Query params** | `?format=pdf` |

---

## 23. Shipment & Fulfillment Endpoints

### 23.1 Create Shipment

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/shipments` |
| **Permission** | `shared.shipments.create @ scope` |
| **Request body** | `{ order_id: UUID, warehouse_id: UUID, items: [{ order_item_id: UUID, quantity: decimal }], carrier?: string, tracking_number?: string }` |
| **Success** | `201` shipment in `pending` |
| **Errors** | `409 conflict_error` (order not confirmed) |
| **Business rules** | BR-STK-009 |
| **Schema** | `shipments`, `shipment_items` |

### 23.2 List Shipments

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/shipments` |
| **Permission** | `shared.shipments.view @ scope` |
| **Query params** | `?status=pending|picking|packed|shipped|delivered|cancelled&order_id=&warehouse_id=&page=&page_size=` |

### 23.3 Get Shipment

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/shipments/{shipment_id}` |
| **Permission** | `shared.shipments.view @ scope` |
| **Query params** | `?include=items,order` |

### 23.4 Start Picking

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/shipments/{shipment_id}/pick` |
| **Permission** | `shared.shipments.update @ scope` |
| **Audit** | `shipment_picking_started` |

### 23.5 Pack

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/shipments/{shipment_id}/pack` |
| **Permission** | `shared.shipments.update @ scope` |
| **Audit** | `shipment_packed` |

### 23.6 Ship

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/shipments/{shipment_id}/ship` |
| **Permission** | `shared.shipments.update @ scope` |
| **Request body** | `{ carrier?: string, tracking_number?: string }` |
| **Side-effects** | Stock deducted from warehouse, reservations released |
| **Audit** | `shipment_shipped` |
| **Transaction** | Yes |
| **Business rules** | BR-STK-003, BR-XMD-001 |

### 23.7 Mark Delivered

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/shipments/{shipment_id}/deliver` |
| **Permission** | `shared.shipments.update @ scope` |
| **Side-effects** | Order status updated |
| **Audit** | `shipment_delivered` |

---

## 24. Return & Refund Endpoints

### 24.1 Create Return Request

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/returns` |
| **Permission** | `sales.returns.create @ scope` |
| **Request body** | `{ order_id?: UUID, invoice_id?: UUID, contact_id: UUID, reason: string, items: [{ product_id: UUID, quantity: decimal, reason_code: string }] }` |
| **Success** | `201` return in `requested` |
| **Business rules** | BR-RFD-002 |
| **Schema** | `returns`, `return_items` |

### 24.2 List Returns

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/returns` |
| **Permission** | `sales.returns.view @ scope` |
| **Query params** | `?status=requested|approved|received|inspected|restocked|disposed|rejected|cancelled&contact_id=&page=&page_size=` |

### 24.3 Approve Return

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/returns/{return_id}/approve` |
| **Permission** | `sales.returns.approve @ scope` |
| **Audit** | `return_approved` |
| **Business rules** | BR-RFD-003 |

### 24.4 Reject Return

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/returns/{return_id}/reject` |
| **Permission** | `sales.returns.approve @ scope` |
| **Request body** | `{ reason: string (required) }` |

### 24.5 Receive & Inspect

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/returns/{return_id}/inspect` |
| **Permission** | `sales.returns.update @ scope` |
| **Request body** | `{ items: [{ return_item_id: UUID, condition: "good"|"damaged"|"defective", disposition: "restock"|"dispose" }] }` |
| **Side-effects** | Inventory updated per disposition |
| **Audit** | `return_inspected` |
| **Transaction** | Yes |
| **Business rules** | BR-RFD-004, BR-XMD-003 |

### 24.6 Process Refund

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/returns/{return_id}/refund` |
| **Permission** | `finance.payments.create @ scope` |
| **Request body** | `{ amount: decimal, payment_method: string }` |
| **Approval** | `202 approval_required` if above threshold |
| **Side-effects** | Credit note issued, refund payment, journal entries |
| **Audit** | `refund_processed` |
| **Transaction** | Yes |
| **Business rules** | BR-RFD-005, BR-RFD-006 |

### 24.7 Create Supplier Return

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/supplier-returns` |
| **Permission** | `purchasing.returns.create @ scope` |
| **Request body** | `{ po_id: UUID, supplier_contact_id: UUID, items: [{ product_id, quantity, reason }] }` |
| **Side-effects** | Stock deducted, debit note created |
| **Business rules** | BR-RFD-007 |

---

## 25. HR: Attendance Endpoints

### 25.1 Clock In

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/attendance/clock-in` |
| **Permission** | `hr.attendance.create @ own` |
| **Request body** | `{ latitude?: decimal, longitude?: decimal, notes?: string }` |
| **Success** | `201` `{ attendance_id, clock_in_time, status: "clocked_in" }` |
| **Errors** | `409 conflict_error` (already clocked in) |
| **Audit** | `clock_in` |
| **Business rules** | BR-ATT-001 |

### 25.2 Clock Out

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/attendance/clock-out` |
| **Permission** | `hr.attendance.create @ own` |
| **Request body** | `{ latitude?, longitude?, notes? }` |
| **Side-effects** | Worked hours calculated |
| **Audit** | `clock_out` |
| **Business rules** | BR-ATT-002 |

### 25.3 List Attendance Records

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/attendance` |
| **Permission** | `hr.attendance.view @ scope` |
| **Scope** | `own` = self; `team` = reports; `dept` = department; `ws` = all |
| **Query params** | `?user_id=&date_after=&date_before=&status=&page=&page_size=` |

### 25.4 Request Correction

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/attendance/{attendance_id}/correct` |
| **Permission** | `hr.attendance.create @ own` |
| **Request body** | `{ corrected_clock_in?: datetime, corrected_clock_out?: datetime, reason: string }` |
| **Side-effects** | Creates approval request |
| **Business rules** | BR-ATT-003 |

### 25.5 Approve Correction

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/attendance/{attendance_id}/approve` |
| **Permission** | `hr.attendance.approve @ scope` |
| **Audit** | `attendance_approved` |
| **Business rules** | BR-ATT-004 |

---

## 26. HR: Leave Endpoints

### 26.1 List Leave Types

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/leave-types` |
| **Permission** | `hr.leaves.view @ scope` |
| **Success** | `200` `[{ id, name, max_days, requires_approval, is_paid, carry_over_allowed }]` |
| **✅ Resolved** | `leave_types` — migration 004 |

### 26.2 Get My Leave Balance

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/leave-balances/me` |
| **Permission** | `hr.leaves.view @ own` |
| **Success** | `200` `[{ leave_type_id, leave_type_name, total_entitled, used, remaining }]` |
| **✅ Resolved** | `leave_balances` — migration 004 |

### 26.3 Create Leave Request

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leave-requests` |
| **Permission** | `hr.leaves.create @ own` |
| **Request body** | `{ leave_type_id: UUID, start_date: date, end_date: date, reason?: string, half_day?: boolean }` |
| **Errors** | `400 validation_error` (insufficient balance, overlap) |
| **Business rules** | BR-LVE-001 |
| **✅ Resolved** | `leave_requests` — migration 004 |

### 26.4 List Leave Requests

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/leave-requests` |
| **Permission** | `hr.leaves.view @ scope` |
| **Query params** | `?status=draft|submitted|approved|rejected|cancelled|completed&user_id=&leave_type_id=&date_after=&date_before=&page=&page_size=` |

### 26.5 Approve Leave

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leave-requests/{leave_id}/approve` |
| **Permission** | `hr.leaves.approve @ scope` |
| **Side-effects** | Leave balance deducted |
| **Audit** | `leave_approved` |
| **Business rules** | BR-LVE-003 |

### 26.6 Reject Leave

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leave-requests/{leave_id}/reject` |
| **Permission** | `hr.leaves.approve @ scope` |
| **Request body** | `{ reason: string (required) }` |
| **Audit** | `leave_rejected` |

### 26.7 Cancel Leave

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leave-requests/{leave_id}/cancel` |
| **Permission** | `hr.leaves.create @ own` |
| **Errors** | `409 conflict_error` (already completed or in past) |
| **Side-effects** | Balance restored if previously approved |
| **Business rules** | BR-LVE-005 |

---

## 27. HR: Payroll Endpoints

### 27.1 Create Payroll Run

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payroll-runs` |
| **Permission** | `hr.payroll.process @ ws` |
| **Request body** | `{ period_start: date, period_end: date, department_id?: UUID, branch_id?: UUID }` |
| **Success** | `201` payroll run in `draft` |
| **Business rules** | BR-PRL-001 |
| **✅ Resolved** | `payroll_lines` — migration 004 |

### 27.2 Calculate Payroll

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payroll-runs/{run_id}/calculate` |
| **Permission** | `hr.payroll.process @ ws` |
| **Side-effects** | Generates payslip lines (base salary + attendance deductions + leave deductions + allowances) |
| **Success** | `202` (async: returns job_id for large payroll) |
| **Business rules** | BR-PRL-002 |

### 27.3 Approve Payroll

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payroll-runs/{run_id}/approve` |
| **Permission** | `hr.payroll.approve @ ws` |
| **Audit** | `payroll_approved` |
| **Business rules** | BR-PRL-002, BR-APR-001 |

### 27.4 Disburse Payroll

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payroll-runs/{run_id}/disburse` |
| **Permission** | `hr.payroll.approve @ ws` |
| **Side-effects** | Journal entries posted (debit salary expense, credit payable), notifications to employees |
| **Idempotency** | Required |
| **Audit** | `payroll_disbursed` |
| **Transaction** | Yes |
| **Business rules** | BR-PRL-003, BR-FIN-001 |

### 27.5 Lock Payroll

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/payroll-runs/{run_id}/lock` |
| **Permission** | `hr.payroll.approve @ ws` |
| **Purpose** | Mark payroll as final — no further edits |
| **Business rules** | BR-PRL-004 |

### 27.6 Get Payslip

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/payroll-runs/{run_id}/payslips/{user_id}` |
| **Permission** | `hr.payroll.view @ scope` or `hr.payroll.view @ own` (own payslip) |
| **Success** | `200` `{ base_salary, attendance_deductions, leave_deductions, allowances, gross, deductions, net }` |
| **Business rules** | BR-HR-005 |

---

## 28. Accounting Endpoints

### 28.1 Chart of Accounts CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/accounts` | `finance.accounts.view @ ws` | List accounts (tree) |
| POST | `/api/v1/accounts` | `finance.accounts.create @ ws` | Create account |
| GET | `/api/v1/accounts/{id}` | `finance.accounts.view @ ws` | Get account |
| PATCH | `/api/v1/accounts/{id}` | `finance.accounts.update @ ws` | Update account |

Schema: `chart_of_accounts`

### 28.2 Create Journal Entry

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/journal-entries` |
| **Permission** | `finance.journal_entries.create @ ws` |
| **Request body** | `{ date: date, reference?: string, description: string, currency: "LYD", lines: [{ account_id: UUID, debit: decimal, credit: decimal, description?: string }] }` |
| **Validation** | Sum of debits MUST equal sum of credits |
| **Success** | `201` journal in `draft` |
| **Errors** | `400 validation_error` (unbalanced) |
| **Business rules** | BR-FIN-001, BR-FIN-002 |
| **Schema** | `journal_entries`, `journal_lines` |

### 28.3 List Journal Entries

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/journal-entries` |
| **Permission** | `finance.journal_entries.view @ ws` |
| **Query params** | `?status=draft|posted|reversed&account_id=&date_after=&date_before=&page=&page_size=` |

### 28.4 Approve / Post Journal

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/journal-entries/{je_id}/post` |
| **Permission** | `finance.journal_entries.approve @ ws` |
| **Side-effects** | Account balances updated |
| **Audit** | `journal_posted` |
| **Transaction** | Yes |
| **Business rules** | BR-FIN-001 |

### 28.5 Reverse Journal Entry

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/journal-entries/{je_id}/reverse` |
| **Permission** | `finance.journal_entries.approve @ ws` |
| **Request body** | `{ reason: string (required) }` |
| **Side-effects** | Creates contra journal, account balances updated |
| **Audit** | `journal_reversed` |
| **Transaction** | Yes |
| **Business rules** | BR-FIN-003 |

### 28.6 Fiscal Period CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/fiscal-periods` | `finance.settings.view @ ws` | List periods |
| POST | `/api/v1/fiscal-periods` | `finance.settings.update @ ws` | Create period |

Business rules: BR-FIN-004
✅ Resolved: `fiscal_periods` table — migration 003.

### 28.7 Close Fiscal Period

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/fiscal-periods/{period_id}/close` |
| **Permission** | `finance.settings.update @ ws` |
| **Side-effects** | Prevents new postings to closed period |
| **Audit** | `fiscal_period_closed` |
| **Business rules** | BR-FIN-005 |

### 28.8 Lock Fiscal Period

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/fiscal-periods/{period_id}/lock` |
| **Permission** | `finance.settings.update @ ws` |
| **Purpose** | Permanent lock — no changes even with admin override |
| **Business rules** | BR-FIN-005 |

### 28.9 Get Trial Balance

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/accounts/trial-balance` |
| **Permission** | `finance.reports.view @ ws` |
| **Query params** | `?as_of=&fiscal_period_id=` |
| **Success** | `200` `[{ account_id, account_name, account_type, debit_balance, credit_balance }]` |

---

## 29. Approval Endpoints

### 29.1 List Pending Approvals

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/approvals` |
| **Permission** | `shared.approvals.view @ scope` |
| **Query params** | `?status=pending|approved|rejected|escalated|expired&entity_type=&created_after=&page=&page_size=` |

### 29.2 Get Approval Detail

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/approvals/{approval_id}` |
| **Permission** | `shared.approvals.view @ scope` |
| **Query params** | `?include=entity,requester,history` |

### 29.3 Approve

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/approvals/{approval_id}/approve` |
| **Permission** | `shared.approvals.approve @ scope` |
| **Request body** | `{ notes?: string }` |
| **Side-effects** | Original action auto-executed, requester notified |
| **Audit** | `approval_granted` |
| **Business rules** | BR-APR-001, BR-APR-002 |

### 29.4 Reject

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/approvals/{approval_id}/reject` |
| **Permission** | `shared.approvals.approve @ scope` |
| **Request body** | `{ reason: string (required) }` |
| **Audit** | `approval_rejected` |
| **Business rules** | BR-APR-001 |

### 29.5 Batch Approve

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/approvals/batch/approve` |
| **Permission** | `shared.approvals.approve @ scope` |
| **Request body** | `{ ids: UUID[] }` |
| **Success** | `200` per-item results |
| **Business rules** | BR-APR-008 |

### 29.6 Override (Break-Glass)

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/approvals/{approval_id}/override` |
| **Permission** | `shared.approvals.override @ ws` |
| **Request body** | `{ reason: string (required), justification: string (required) }` |
| **Side-effects** | Original action executed, security alert sent, audit flagged |
| **Audit** | `approval_overridden` (high priority) |
| **Business rules** | BR-APR-006 |

### 29.7 Escalate

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/approvals/{approval_id}/escalate` |
| **Permission** | `shared.approvals.escalate @ scope` |
| **Request body** | `{ reason?: string }` |
| **Audit** | `approval_escalated` |
| **Business rules** | BR-APR-007 |

---

## 30. Notification Endpoints

### 30.1 List Notifications

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/notifications` |
| **Permission** | Authenticated (own only) |
| **Query params** | `?is_read=true|false&type=&page=&page_size=` |
| **Schema** | `notifications` |

### 30.2 Mark Read

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/notifications/{notification_id}/read` |
| **Permission** | Authenticated (own only) |

### 30.3 Batch Mark Read

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/notifications/batch/read` |
| **Permission** | Authenticated |
| **Request body** | `{ ids: UUID[] }` |

### 30.4 Get Unread Count

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/notifications/unread-count` |
| **Permission** | Authenticated |
| **Success** | `200` `{ count: int }` |

---

## 31. CRM Endpoints

### 31.1 Create Lead

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leads` |
| **Permission** | `crm.leads.create @ scope` |
| **Request body** | `{ name: string (required), contact_id?: UUID, source?: string, estimated_value?: decimal, assigned_to?: UUID, notes?: string }` |
| **Success** | `201` lead in `new` status |
| **Audit** | `lead_created` |
| **Business rules** | BR-CRM-001 |
| **✅ Resolved** | `leads` table exists in base schema |

### 31.2 List Leads

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/leads` |
| **Permission** | `crm.leads.view @ scope` |
| **Scope** | `own` = assigned to me; `team` = team's leads; `ws` = all |
| **Query params** | `?status=new|contacted|qualified|converted|lost&assigned_to=&source=&page=&page_size=` |

### 31.3 Get Lead

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/leads/{lead_id}` |
| **Permission** | `crm.leads.view @ scope` |
| **Query params** | `?include=contact,activities,opportunities` |

### 31.4 Update Lead

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/leads/{lead_id}` |
| **Permission** | `crm.leads.update @ scope` |
| **Audit** | `lead_updated` |

### 31.5 Qualify Lead

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leads/{lead_id}/qualify` |
| **Permission** | `crm.leads.update @ scope` |
| **Business rules** | BR-CRM-002 |

### 31.6 Convert Lead

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leads/{lead_id}/convert` |
| **Permission** | `crm.leads.update @ scope` |
| **Side-effects** | Creates contact (if not exists) + opportunity |
| **Transaction** | Yes |
| **Business rules** | BR-CRM-003 |

### 31.7 Disqualify Lead

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/leads/{lead_id}/disqualify` |
| **Permission** | `crm.leads.update @ scope` |
| **Request body** | `{ reason: string }` |

### 31.8 Opportunity CRUD + Lifecycle

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/opportunities` | `crm.opportunities.view @ scope` | List |
| POST | `/api/v1/opportunities` | `crm.opportunities.create @ scope` | Create |
| GET | `/api/v1/opportunities/{id}` | `crm.opportunities.view @ scope` | Get detail |
| PATCH | `/api/v1/opportunities/{id}` | `crm.opportunities.update @ scope` | Update |
| POST | `/api/v1/opportunities/{id}/advance` | `crm.opportunities.update @ scope` | Move to next stage |
| POST | `/api/v1/opportunities/{id}/close-won` | `crm.opportunities.update @ scope` | Close as won |
| POST | `/api/v1/opportunities/{id}/close-lost` | `crm.opportunities.update @ scope` | Close as lost |

Business rules: BR-CRM-004, BR-CRM-005, BR-CRM-006
✅ Resolved: `opportunities` table exists in base schema.

### 31.9 Log CRM Activity

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/crm-activities` |
| **Permission** | `crm.activities.create @ scope` |
| **Request body** | `{ entity_type: "lead"|"opportunity"|"contact", entity_id: UUID, activity_type: "call"|"email"|"meeting"|"note", notes: string, scheduled_at?: datetime }` |
| **✅ Resolved** | `crm_activities` table exists in base schema |

---

## 32. Manufacturing Endpoints

### 32.1 Create Production Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders` |
| **Permission** | `manufacturing.production.create @ scope` |
| **Request body** | `{ product_id: UUID, quantity: decimal, warehouse_id: UUID, bom_id?: UUID, planned_start_date?: date, planned_end_date?: date }` |
| **Success** | `201` production order in `draft` |
| **Business rules** | BR-MFG-001 |
| **✅ Resolved** | `production_orders`, `bill_of_materials` exist in base schema |

### 32.2 List Production Orders

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/production-orders` |
| **Permission** | `manufacturing.production.view @ scope` |
| **Query params** | `?status=draft|confirmed|released|in_progress|completed|closed|cancelled&product_id=&page=&page_size=` |

### 32.3 Confirm Production Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/confirm` |
| **Permission** | `manufacturing.production.update @ scope` |
| **Side-effects** | BOM components verified for availability |
| **Business rules** | BR-MFG-002 |

### 32.4 Release Production Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/release` |
| **Permission** | `manufacturing.production.approve @ scope` |
| **Side-effects** | Raw materials reserved |
| **Business rules** | BR-MFG-003 |

### 32.5 Start Production

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/start` |
| **Permission** | `manufacturing.production.update @ scope` |
| **Side-effects** | Raw materials consumed from inventory |
| **Transaction** | Yes |
| **Business rules** | BR-MFG-004 |

### 32.6 Record Output

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/output` |
| **Permission** | `manufacturing.production.update @ scope` |
| **Request body** | `{ quantity_produced: decimal, warehouse_id: UUID }` |
| **Side-effects** | Finished goods added to inventory |
| **Transaction** | Yes |
| **Business rules** | BR-MFG-005 |

### 32.7 Record Scrap

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/scrap` |
| **Permission** | `manufacturing.production.update @ scope` |
| **Request body** | `{ quantity_scrapped: decimal, reason: string }` |
| **Audit** | `production_scrap_recorded` |
| **Business rules** | BR-MFG-006 |

### 32.8 Complete / Close Production Order

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/production-orders/{po_id}/complete` |
| **Permission** | `manufacturing.production.update @ scope` |
| **Side-effects** | Variance calculated (planned vs actual) |
| **Business rules** | BR-MFG-007 |

---

## 33. POS Session Endpoints

### 33.1 Open POS Session

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/pos-sessions/open` |
| **Permission** | `sales.pos_sessions.open @ scope` |
| **Request body** | `{ register_id?: string, opening_cash: decimal }` |
| **Success** | `201` `{ session_id, status: "open", opened_at }` |
| **Errors** | `409 conflict_error` (session already open for user) |
| **Audit** | `pos_session_opened` |
| **Business rules** | BR-FIN-010, BR-PAY-007 |
| **✅ Resolved** | `pos_sessions` table exists in base schema |

### 33.2 Close POS Session

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/pos-sessions/{session_id}/close` |
| **Permission** | `sales.pos_sessions.close @ scope` |
| **Request body** | `{ closing_cash: decimal, notes?: string }` |
| **Side-effects** | Cash variance calculated (expected vs actual), session reconciled |
| **Audit** | `pos_session_closed` |

### 33.3 Get POS Session

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/pos-sessions/{session_id}` |
| **Permission** | `sales.pos.view @ scope` |
| **Success** | `200` `{ session_id, opening_cash, closing_cash, total_sales, total_payments_by_method, variance, transactions_count }` |

---

## 34. AI Endpoints

### 34.1 Chat

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/ai/chat` |
| **Permission** | `ai.chat.use @ ws` |
| **Request body** | `{ message: string, context?: object, conversation_id?: UUID }` |
| **Success** | `200` `{ response, conversation_id, tokens_used }` |
| **Rate limit** | Per workspace tier |
| **Business rules** | BR-AI-001, BR-AI-002 |
| **Schema** | `ai_requests` |

### 34.2 Submit Change Request

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/ai/change-request` |
| **Permission** | `ai.chat.use @ ws` |
| **Request body** | `{ description: string, entity_type: string, entity_id?: UUID }` |
| **Success** | `200` `{ changes_proposed: object, requires_approval: boolean }` |
| **Business rules** | BR-AI-003, BR-AI-004 |

### 34.3 Get AI Quota

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/ai/quota` |
| **Permission** | `ai.chat.use @ ws` |
| **Success** | `200` `{ daily_limit, used_today, remaining }` |
| **Business rules** | BR-AI-005 |

### 34.4 List AI History

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/ai/history` |
| **Permission** | `ai.chat.use @ ws` |
| **Query params** | `?conversation_id=&page=&page_size=` |

### 34.5 Submit Feature Request

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/feature-requests` |
| **Permission** | Authenticated |
| **Request body** | `{ title: string, description: string, category?: string }` |
| **Schema** | `feature_requests` |

---

## 35. Report & Dashboard Endpoints

### 35.1 Profit & Loss

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/reports/profit-loss` |
| **Permission** | `finance.reports.view @ ws` |
| **Query params** | `?period_start=&period_end=&branch_id=&department_id=` |
| **Success** | `200` grouped by account category; async via `202` + job_id if large |

### 35.2 Balance Sheet

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/reports/balance-sheet` |
| **Permission** | `finance.reports.view @ ws` |
| **Query params** | `?as_of=` |

### 35.3 Trial Balance

Canonical endpoint: `GET /api/v1/accounts/trial-balance` (§28.9). Reports module delegates to the accounting trial balance endpoint to avoid duplication.

### 35.4 Sales Summary

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/reports/sales-summary` |
| **Permission** | `reports.operational.view @ scope` |
| **Query params** | `?period_start=&period_end=&group_by=day|week|month&branch_id=` |

### 35.5 Inventory Report

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/reports/inventory` |
| **Permission** | `inventory.reports.view @ scope` |
| **Query params** | `?warehouse_id=&category_id=&valuation_method=avg|fifo` |

### 35.6 Export Report

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/reports/export` |
| **Permission** | Based on report type |
| **Request body** | `{ report_type: string, format: "csv"|"pdf", params: object }` |
| **Success** | `202` `{ job_id }` (async for large reports) |

---

## 36. Audit Log Endpoints

### 36.1 Query Audit Log

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/audit-logs` |
| **Permission** | `shared.audit_logs.view @ ws` |
| **Query params** | `?user_id=&event_type=&entity_type=&entity_id=&created_after=&created_before=&page=&page_size=` |
| **Success** | `200` paginated `{ id, user_id, user_name, event_type, entity_type, entity_id, old_values, new_values, ip_address, created_at }` |
| **Schema** | `audit_logs` |
| **Business rules** | BR-SYS-003 |

### 36.2 Get Entity Audit Trail

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/audit-logs/entity/{entity_type}/{entity_id}` |
| **Permission** | `shared.audit_logs.view @ ws` |
| **Success** | `200` chronological list of all changes to the entity |

---

## 37. Attachment / File Endpoints

### 37.1 Upload File

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/attachments` |
| **Permission** | Authenticated |
| **Request** | `multipart/form-data` with `file` + `{ entity_type, entity_id }` |
| **Validation** | Max size: 10MB; allowed types: jpg, png, pdf, csv, xlsx, docx |
| **Success** | `201` `{ attachment_id, url, filename, size }` |
| **Audit** | `file_uploaded` |
| **Business rules** | BR-PLT-007 |

### 37.2 Download File

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/attachments/{attachment_id}` |
| **Permission** | Same as parent entity view permission |
| **Success** | `200` binary file |

### 37.3 List Entity Attachments

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/{entity_type}/{entity_id}/attachments` |
| **Permission** | Same as parent entity view permission |

---

## 38. Platform Admin Endpoints

All platform endpoints use `/api/v1/platform/` prefix and require platform authentication.

### 38.1 Platform Login

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/auth/login` |
| **Request body** | `{ email: string, password: string }` |
| **Success** | `200` `{ access_token, refresh_token, platform_user }` |
| **Schema** | `platform_users` |

### 38.2 List All Workspaces

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/platform/workspaces` |
| **Permission** | `platform.workspaces.view` |
| **Query params** | `?subscription_status=&is_active=&q=&page=&page_size=` |

### 38.3 Suspend Workspace

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/workspaces/{workspace_id}/suspend` |
| **Permission** | `platform.workspaces.suspend` |
| **Request body** | `{ reason: string }` |
| **Audit** | `workspace_suspended_by_platform` |
| **Business rules** | BR-PLT-001 |

### 38.4 Reactivate Workspace

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/workspaces/{workspace_id}/reactivate` |
| **Permission** | `platform.workspaces.reactivate` |

### 38.5 Impersonate User

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/impersonate` |
| **Permission** | `platform.support.impersonate` |
| **Request body** | `{ workspace_id: UUID, user_id: UUID, reason: string }` |
| **Success** | `200` `{ impersonation_token, expires_at }` |
| **Audit** | `user_impersonated` (high priority) |
| **Business rules** | BR-PLT-002 |

### 38.6 Broadcast Notification

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/broadcasts` |
| **Permission** | `platform.broadcasts.manage` |
| **Request body** | `{ title: string, message: string, target: "all"|"tier"|"workspace_ids", target_ids?: UUID[], priority: "low"|"medium"|"high" }` |
| **Schema** | `platform_broadcasts` |

### 38.7 Create Survey

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/platform/surveys` |
| **Permission** | `platform.surveys.manage` |
| **Request body** | `{ title: string, questions: [{ text, type, options? }], target_audience }` |
| **Schema** | `platform_surveys` |

### 38.8 View Platform Analytics

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/platform/analytics` |
| **Permission** | `platform.analytics.view` |
| **Query params** | `?metric=active_workspaces|total_users|ai_requests|revenue&period=day|week|month` |
| **Schema** | `platform_analytics` |

### 38.9 View AI Request Logs

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/platform/ai-logs` |
| **Permission** | `platform.ai.view_logs` |
| **Query params** | `?workspace_id=&user_id=&created_after=&created_before=&page=&page_size=` |
| **Schema** | `ai_requests` |

### 38.10 Manage Subscription

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/platform/subscriptions` | `platform.billing.view` | List subscriptions |
| GET | `/api/v1/platform/subscriptions/{id}` | `platform.billing.view` | Get subscription |
| PATCH | `/api/v1/platform/subscriptions/{id}` | `platform.billing.manage` | Update tier/limits |

Schema: `workspace_subscriptions`

### 38.11 View Billing History

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/platform/billing-history` |
| **Permission** | `platform.billing.view` |
| **Query params** | `?workspace_id=&page=&page_size=` |
| **Schema** | `billing_invoices`, `billing_payments` |

### 38.12 Configure Entitlements

| Field | Value |
|-------|-------|
| **Method** | PATCH |
| **Path** | `/api/v1/platform/workspaces/{workspace_id}/entitlements` |
| **Permission** | `platform.billing.manage` |
| **Request body** | `{ max_users?: int, max_ai_requests_daily?: int, features_enabled?: string[] }` |

---

## 39. Offline Sync Endpoints

### 39.1 Push Offline Operations

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/sync` |
| **Permission** | Authenticated |
| **Request body** | `{ client_id: string, operations: [{ id: UUID, entity_type: string, action: "create"|"update"|"delete", data: object, timestamp: datetime }] }` |
| **Success** | `200` `{ synced: N, conflicts: [{ operation_id, conflict_type, server_state }] }` |
| **Idempotency** | Required (per operation ID) |
| **Business rules** | BR-PLT-009 |

### 39.2 Get Sync Status

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/sync/status` |
| **Permission** | Authenticated |
| **Query params** | `?client_id=&since=` |
| **Success** | `200` `{ pending_sync_count, last_sync_at, server_changes_since: [...] }` |

---

## 40. Async Job Endpoints

### 40.1 Get Job Status

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/jobs/{job_id}` |
| **Permission** | Authenticated (own jobs only) |
| **Success** | `200` `{ job_id, status: "pending"|"running"|"completed"|"failed", progress_pct: int, result_url?: string, error?: string, created_at, completed_at? }` |

### 40.2 Cancel Job

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/jobs/{job_id}/cancel` |
| **Permission** | Authenticated (own jobs only) |
| **Errors** | `409 conflict_error` (already completed or failed) |

---

## 41. Communications Endpoints [Core v1]

### 41.1 Channel CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/communications/channels` | `communications.templates.view @ ws` | List configured channels |
| POST | `/api/v1/communications/channels` | `communications.automations.manage @ ws` | Register channel provider |
| PATCH | `/api/v1/communications/channels/{id}` | `communications.automations.manage @ ws` | Update channel config |
| DELETE | `/api/v1/communications/channels/{id}` | `communications.automations.manage @ ws` | Remove channel |

- **Request body (POST)**: `{ type: "email"|"sms"|"whatsapp"|"push", provider_name: string, provider_config: object, is_default?: boolean }`
- **Errors**: `422 validation_error` (duplicate type+provider), `400 bad_request` (invalid provider_config schema)
- **Schema**: `communication_channels` (migration 013)

### 41.2 Template CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/communications/templates` | `communications.templates.view @ scope` | List templates |
| POST | `/api/v1/communications/templates` | `communications.templates.create @ scope` | Create template |
| GET | `/api/v1/communications/templates/{id}` | `communications.templates.view @ scope` | Get template detail |
| PATCH | `/api/v1/communications/templates/{id}` | `communications.templates.update @ scope` | Update template |
| DELETE | `/api/v1/communications/templates/{id}` | `communications.templates.delete @ scope` | Delete template |

- **Request body (POST)**: `{ channel_type: string, name: string, subject?: string, body: string, variables?: [{key, label, default}], locale?: string }`
- **Query params**: `?channel_type=&locale=&page=&page_size=`
- **Errors**: `422 validation_error` (duplicate name+channel+locale)
- **Schema**: `message_templates` (migration 013)

### 41.3 Send Message

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/communications/send` |
| **Permission** | `communications.messages.send @ scope` |
| **Request body** | `{ channel_type: string, template_id?: UUID, recipient_contact_id?: UUID, recipient_user_id?: UUID, recipient_address: string, subject?: string, body?: string, variables?: object }` |
| **Success** | `202` message queued `{ message_id, status: "queued" }` |
| **Errors** | `422 validation_error` (no channel configured for type), `400 bad_request` (missing recipient) |
| **Business rules** | BR-COM-001, BR-COM-004 |
| **Side-effects** | Creates `outbound_messages` row, enqueues dispatch job |

### 41.4 Communication Logs

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/communications/logs` | `communications.messages.view @ scope` | List all sent/received messages |
| GET | `/api/v1/communications/logs/contact/{contact_id}` | `communications.messages.view @ scope` | Contact communication timeline |

- **Query params**: `?channel_type=&status=&date_from=&date_to=&page=&page_size=`
- **Response**: Paginated list of `outbound_messages` + `inbound_messages` (merged, sorted by date)

### 41.5 Export Communication Logs

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/communications/logs/export` |
| **Permission** | `communications.logs.export @ ws` |
| **Request body** | `{ date_from: date, date_to: date, channel_type?: string, format?: "csv"|"xlsx" }` |
| **Success** | `202` async job started `{ job_id }` |

### 41.6 Automation CRUD [Expansion Pack]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/communications/automations` | `communications.automations.view @ scope` | List automations |
| POST | `/api/v1/communications/automations` | `communications.automations.manage @ scope` | Create automation |
| PATCH | `/api/v1/communications/automations/{id}` | `communications.automations.manage @ scope` | Update automation |
| DELETE | `/api/v1/communications/automations/{id}` | `communications.automations.manage @ scope` | Delete automation |

- **Request body (POST)**: `{ name: string, trigger_event: string, conditions?: object, template_id: UUID, channel_type: string, delay_minutes?: int }`
- **Business rules**: BR-COM-002
- **Schema**: `communication_automations` (migration 013)

### 41.7 Message Threads [Expansion Pack]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/communications/threads` | `communications.messages.view @ scope` | List threads |
| GET | `/api/v1/communications/threads/{id}` | `communications.messages.view @ scope` | Get thread with messages |

### 41.8 Channel Analytics

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/communications/analytics` |
| **Permission** | `communications.messages.view @ ws` |
| **Query params** | `?date_from=&date_to=&channel_type=` |
| **Response** | `{ sent_count, delivered_count, failed_count, bounce_count, delivery_rate_pct, by_channel: [{type, sent, delivered, failed}] }` |

---

## 42. Marketing Endpoints [Mixed]

### 42.1 Campaign CRUD [Expansion Pack]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/marketing/campaigns` | `marketing.campaigns.view @ scope` | List campaigns |
| POST | `/api/v1/marketing/campaigns` | `marketing.campaigns.create @ scope` | Create campaign |
| GET | `/api/v1/marketing/campaigns/{id}` | `marketing.campaigns.view @ scope` | Get campaign detail + metrics |
| PATCH | `/api/v1/marketing/campaigns/{id}` | `marketing.campaigns.update @ scope` | Update campaign |
| DELETE | `/api/v1/marketing/campaigns/{id}` | `marketing.campaigns.delete @ scope` | Delete (draft only) |

- **Request body (POST)**: `{ name: string, type: "email"|"sms"|"multi_channel", segment_id?: UUID, template_id?: UUID, budget?: decimal, scheduled_at?: datetime }`
- **Errors**: `422 validation_error` (cannot delete non-draft campaign)
- **Schema**: `campaigns`, `campaign_metrics` (migration 013)

### 42.2 Launch / Pause Campaign [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/marketing/campaigns/{id}/launch` |
| **Permission** | `marketing.campaigns.launch @ scope` |
| **Pre-conditions** | Status = `draft` or `paused`, segment has > 0 contacts |
| **Success** | `200` status → `active`, messages begin queueing |
| **Errors** | `409 conflict_error` (already active/completed), `422 validation_error` (empty segment) |
| **Business rules** | BR-MKT-003 |

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/marketing/campaigns/{id}/pause` |
| **Permission** | `marketing.campaigns.update @ scope` |
| **Pre-conditions** | Status = `active` |

### 42.3 Campaign Metrics [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/marketing/campaigns/{id}/metrics` |
| **Permission** | `marketing.campaigns.view @ scope` |
| **Response** | `{ sent_count, delivered_count, opened_count, clicked_count, converted_count, unsubscribed_count, open_rate_pct, click_rate_pct }` |

### 42.4 Segment CRUD [Core v1]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/marketing/segments` | `marketing.segments.view @ scope` | List segments |
| POST | `/api/v1/marketing/segments` | `marketing.segments.manage @ scope` | Create segment |
| GET | `/api/v1/marketing/segments/{id}` | `marketing.segments.view @ scope` | Get segment detail |
| PATCH | `/api/v1/marketing/segments/{id}` | `marketing.segments.manage @ scope` | Update segment rules |
| DELETE | `/api/v1/marketing/segments/{id}` | `marketing.segments.manage @ scope` | Delete segment |

- **Request body (POST)**: `{ name: string, rules: [{field: string, operator: string, value: any}], is_dynamic?: boolean }`
- **Business rules**: BR-MKT-005
- **Schema**: `segments`, `segment_contacts` (migration 013)

### 42.5 Segment Contacts

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/marketing/segments/{id}/contacts` |
| **Permission** | `marketing.segments.view @ scope` |
| **Query params** | `?page=&page_size=` |
| **Response** | Paginated list of contacts in segment |

### 42.6 Loyalty Program CRUD [Core v1]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/marketing/loyalty/programs` | `marketing.loyalty.view @ scope` | List programs |
| POST | `/api/v1/marketing/loyalty/programs` | `marketing.loyalty.manage @ scope` | Create program |
| PATCH | `/api/v1/marketing/loyalty/programs/{id}` | `marketing.loyalty.manage @ scope` | Update program |

- **Request body (POST)**: `{ name: string, earn_rules: [{type, rate}], burn_rules: [{points, discount}], tiers?: [{name, min_points, benefits}] }`
- **Schema**: `loyalty_programs` (migration 013)

### 42.7 Loyalty Account Lookup [Core v1]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/marketing/loyalty/accounts/{contact_id}` |
| **Permission** | `marketing.loyalty.view @ scope` |
| **Response** | `{ account_id, contact_id, program: {name, tiers}, points_balance, lifetime_points, current_tier, recent_transactions: [...] }` |

### 42.8 Redeem Loyalty Points [Core v1]

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/marketing/loyalty/redeem` |
| **Permission** | `marketing.loyalty.manage @ scope` |
| **Request body** | `{ account_id: UUID, points: int, reason?: string, reference_entity_type?: string, reference_entity_id?: UUID }` |
| **Success** | `200` `{ new_balance, transaction_id }` |
| **Errors** | `422 validation_error` (insufficient points) |
| **Business rules** | BR-MKT-001 |
| **Schema**: `loyalty_transactions` (type = `burn`) |

### 42.9 Referral Program CRUD [Expansion Pack]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/marketing/referrals/programs` | `marketing.referrals.view @ scope` | List programs |
| POST | `/api/v1/marketing/referrals/programs` | `marketing.referrals.manage @ scope` | Create program |
| PATCH | `/api/v1/marketing/referrals/programs/{id}` | `marketing.referrals.manage @ scope` | Update program |

- **Request body (POST)**: `{ name: string, referrer_reward: {type, amount}, referee_reward: {type, amount} }`
- **Business rules**: BR-MKT-004
- **Schema**: `referral_programs`, `referrals` (migration 013)

### 42.10 Nurturing Sequence CRUD [Expansion Pack]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/marketing/nurturing/sequences` | `marketing.nurturing.view @ scope` | List sequences |
| POST | `/api/v1/marketing/nurturing/sequences` | `marketing.nurturing.manage @ scope` | Create sequence |
| PATCH | `/api/v1/marketing/nurturing/sequences/{id}` | `marketing.nurturing.manage @ scope` | Update sequence |
| DELETE | `/api/v1/marketing/nurturing/sequences/{id}` | `marketing.nurturing.manage @ scope` | Delete sequence |

- **Request body (POST)**: `{ name: string, trigger_event: string, steps: [{delay_days, template_id, channel}] }`
- **Schema**: `nurturing_sequences`, `nurturing_enrollments` (migration 013)

### 42.11 Marketing Analytics [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/marketing/analytics` |
| **Permission** | `marketing.analytics.view @ ws` |
| **Query params** | `?date_from=&date_to=` |
| **Response** | `{ total_campaigns, active_campaigns, total_segments, loyalty_programs_active, points_issued, points_redeemed, referrals_converted, top_segments: [...], campaign_summary: [...] }` |

---

## 43. Delivery & Fleet Endpoints [Core v1]

### 43.1 Driver CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/delivery/drivers` | `delivery.drivers.view @ scope` | List drivers |
| POST | `/api/v1/delivery/drivers` | `delivery.drivers.manage @ scope` | Register driver |
| GET | `/api/v1/delivery/drivers/{id}` | `delivery.drivers.view @ scope` | Get driver detail |
| PATCH | `/api/v1/delivery/drivers/{id}` | `delivery.drivers.manage @ scope` | Update driver |

- **Request body (POST)**: `{ user_id: UUID, vehicle_type?: string, vehicle_plate?: string, license_number?: string, zone_ids?: [UUID], branch_id?: UUID }`
- **Query params**: `?status=available|busy|offline|suspended&branch_id=&page=&page_size=`
- **Scope**: `branch` = drivers at my branch; `ws` = all drivers
- **Schema**: `drivers` (migration 013)

### 43.2 Zone CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/delivery/zones` | `delivery.drivers.view @ ws` | List zones |
| POST | `/api/v1/delivery/zones` | `delivery.zones.manage @ ws` | Create zone |
| PATCH | `/api/v1/delivery/zones/{id}` | `delivery.zones.manage @ ws` | Update zone |
| DELETE | `/api/v1/delivery/zones/{id}` | `delivery.zones.manage @ ws` | Delete zone |

- **Request body (POST)**: `{ name: string, boundary_geojson?: object, sla_minutes?: int }`
- **Schema**: `delivery_zones` (migration 013)

### 43.3 Assign Delivery

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assign` |
| **Permission** | `delivery.assignments.create @ scope` |
| **Request body** | `{ order_id: UUID, driver_id: UUID, zone_id?: UUID }` |
| **Pre-conditions** | Driver status = `available`, order not already assigned to an active assignment |
| **Success** | `201` assignment in `pending` status, driver status → `busy` |
| **Errors** | `409 conflict_error` (driver not available), `409 conflict_error` (order already assigned) |
| **Business rules** | BR-DEL-001 |
| **Audit** | `delivery_assigned` |
| **Schema**: `delivery_assignments` (migration 013) |

### 43.4 Driver Accept / Reject

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assignments/{id}/accept` |
| **Permission** | `delivery.assignments.update @ own` |
| **Pre-conditions** | Status = `pending`, caller is assigned driver |
| **Success** | `200` status → `accepted` |
| **Business rules** | BR-DEL-002 |

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assignments/{id}/reject` |
| **Permission** | `delivery.assignments.update @ own` |
| **Pre-conditions** | Status = `pending`, caller is assigned driver |
| **Success** | `200` status → `rejected`, driver status → `available`, requeue for reassignment |

### 43.5 Mark Picked Up

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assignments/{id}/pickup` |
| **Permission** | `delivery.assignments.update @ own` |
| **Pre-conditions** | Status = `accepted` |
| **Success** | `200` status → `picked_up`, `picked_up_at` set |
| **Business rules** | BR-DEL-002 |

### 43.6 Mark Delivered (with proof)

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assignments/{id}/deliver` |
| **Permission** | `delivery.proof.capture @ own` |
| **Request body** | `{ receiver_name?: string, photo?: file_upload, signature?: file_upload, pin_code?: string, cod_amount_collected?: decimal }` |
| **Pre-conditions** | Status = `picked_up` or `in_transit` |
| **Success** | `200` status → `delivered`, proof saved, COD collection created (if applicable) |
| **Business rules** | BR-DEL-002, BR-DEL-004 |
| **Transaction** | Yes (assignment + proof + COD in one transaction) |

### 43.7 Mark Failed

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/assignments/{id}/fail` |
| **Permission** | `delivery.assignments.update @ own` |
| **Request body** | `{ reason: string }` |
| **Pre-conditions** | Status in (`accepted`, `picked_up`, `in_transit`) |
| **Success** | `200` status → `failed`, driver status → `available` |

### 43.8 Live Tracking [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/delivery/tracking/{assignment_id}` |
| **Permission** | `delivery.tracking.view @ scope` |
| **Response** | `{ assignment_id, driver: {name, vehicle_type}, status, current_location: {lat, lng, captured_at}, eta_minutes?: int, history: [{lat, lng, captured_at}] }` |

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/tracking/{assignment_id}/location` |
| **Permission** | `delivery.proof.capture @ own` (driver only) |
| **Request body** | `{ latitude: decimal, longitude: decimal }` |
| **Rate limit** | Max 1 per 10 seconds per driver |

### 43.9 COD Reconciliation

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/delivery/cod/daily` |
| **Permission** | `delivery.cod.view @ scope` |
| **Query params** | `?date=&driver_id=&settled=true|false` |
| **Response** | `{ total_expected, total_collected, total_variance, items: [{assignment_id, driver, expected, collected, variance, settled}] }` |

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/delivery/cod/{id}/settle` |
| **Permission** | `delivery.cod.reconcile @ ws` |
| **Pre-conditions** | COD record not already settled |
| **Success** | `200` `settled = true`, `settled_at` set |
| **Errors** | `409 conflict_error` (already settled) |
| **Business rules** | BR-DEL-003 |

### 43.10 SLA Report [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/delivery/sla/report` |
| **Permission** | `delivery.sla.view @ scope` |
| **Query params** | `?date_from=&date_to=&zone_id=&driver_id=` |
| **Response** | `{ total_deliveries, on_time_count, breach_count, on_time_pct, by_zone: [{zone_id, name, deliveries, breaches, avg_minutes}], by_driver: [{driver_id, name, deliveries, breaches}] }` |

---

## 44. Compliance Endpoints [Core v1 framework]

### 44.1 List Country Packs

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/compliance/packs` |
| **Permission** | `compliance.packs.view @ ws` |
| **Response** | `{ installed: [{pack_id, country_code, name, version, installed_at}], available: [{pack_id, country_code, name, version, description}] }` |

### 44.2 Install Country Pack

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/compliance/packs/{pack_id}/install` |
| **Permission** | `compliance.packs.install @ ws` |
| **Request body** | `{ config_overrides?: object }` |
| **Pre-conditions** | Pack not already installed for this workspace |
| **Success** | `201` pack installed, tax rules seeded from pack defaults |
| **Side-effects** | Creates `workspace_country_packs` row + copies default `tax_rules` from pack |
| **Business rules** | BR-CMP-001 |
| **Errors** | `409 conflict_error` (already installed) |

### 44.3 Tax Rules

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/compliance/tax-rules` | `compliance.tax_rules.view @ ws` | List active tax rules |
| POST | `/api/v1/compliance/tax-rules` | `compliance.tax_rules.manage @ ws` | Create custom tax rule |
| PATCH | `/api/v1/compliance/tax-rules/{id}` | `compliance.tax_rules.manage @ ws` | Update tax rule |

- **Request body (POST)**: `{ rule_type: string, rate: decimal, conditions?: object, effective_from: date, effective_to?: date, country_pack_id?: UUID }`
- **Query params (GET)**: `?effective_date=&rule_type=&country_pack_id=`
- **Business rules**: BR-CMP-002 (never delete, only supersede via `effective_to`)
- **Schema**: `tax_rules` (migration 013)

### 44.4 Generate VAT Return [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/compliance/exports/vat-return` |
| **Permission** | `compliance.exports.generate @ ws` |
| **Request body** | `{ period_from: date, period_to: date, format?: "xml"|"json"|"csv" }` |
| **Success** | `202` async job started `{ job_id }` |
| **Side-effects** | Creates `export_jobs` row |

### 44.5 Generate Payroll Filing [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/compliance/exports/payroll-filing` |
| **Permission** | `compliance.exports.generate @ ws` |
| **Request body** | `{ period_from: date, period_to: date, country_code: string }` |
| **Success** | `202` async job started `{ job_id }` |

### 44.6 Retention Policy Status [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/compliance/retention/status` |
| **Permission** | `compliance.retention.view @ ws` |
| **Response** | `{ policies: [{entity_type, retention_years, action, records_subject_to_archival_count, last_archival_at}] }` |

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| POST | `/api/v1/compliance/retention/policies` | `compliance.retention.manage @ ws` | Create/update retention policy |
| DELETE | `/api/v1/compliance/retention/policies/{id}` | `compliance.retention.manage @ ws` | Remove policy |

- **Business rules**: BR-CMP-003 (cannot set below regulatory minimum), BR-CMP-004
- **Schema**: `retention_policies`, `archival_jobs` (migration 013)

---

## 45. Media & Content Endpoints [Core v1 basic]

### 45.1 Asset Library CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/media/assets` | `media.assets.view @ scope` | List assets |
| POST | `/api/v1/media/assets` | `media.assets.upload @ scope` | Upload asset |
| GET | `/api/v1/media/assets/{id}` | `media.assets.view @ scope` | Get asset detail + pre-signed download URL |
| DELETE | `/api/v1/media/assets/{id}` | `media.assets.delete @ scope` | Delete asset |

- **Request body (POST)**: Multipart file upload + `{ name: string, tags?: [string], folder?: string }`
- **Query params (GET)**: `?folder=&tags=&source=upload|ai_generated&status=draft|approved|archived&page=&page_size=`
- **Schema**: `media_assets` (migration 013)

### 45.2 Asset Search

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/media/assets/search` |
| **Permission** | `media.assets.view @ scope` |
| **Query params** | `?q=&tags=&folder=&mime_type=&source=&page=&page_size=` |
| **Response** | Paginated asset list with thumbnail URLs |

### 45.3 Approve Asset

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/media/assets/{id}/approve` |
| **Permission** | `media.generation.approve @ scope` |
| **Pre-conditions** | Status = `draft` |
| **Success** | `200` status → `approved`, `approved_by` + `approved_at` set |
| **Business rules** | BR-MDA-001 |

### 45.4 AI Content Generation [Expansion Pack]

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/media/generate` |
| **Permission** | `media.generation.request @ scope` |
| **Request body** | `{ prompt: string, brand_kit_id?: UUID, ai_model?: string }` |
| **Success** | `202` generation request queued `{ request_id, status: "pending" }` |
| **Business rules** | BR-MDA-003 (consumes AI token quota) |
| **Side-effects** | Creates `media_generation_requests` row, enqueues AI job |

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/media/generate/{request_id}/status` |
| **Permission** | `media.generation.request @ scope` |
| **Response** | `{ request_id, status, result_asset_id?, tokens_used, error_message? }` |

### 45.5 Brand Kit CRUD [Core v1]

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/media/brand-kit` | `media.brand_kit.view @ scope` | Get workspace brand kit (singleton) |
| PUT | `/api/v1/media/brand-kit` | `media.brand_kit.manage @ scope` | Create or update brand kit |

- **Request body (PUT)**: `{ primary_color?: string, secondary_color?: string, accent_color?: string, font_family?: string, logo?: file_upload, tone_description?: string, guidelines?: object }`
- **Business rules**: BR-MDA-002 (singleton per workspace — upsert)
- **Schema**: `brand_kits` (migration 013)

---

## 46. Integration Hub Endpoints [Core v1]

### 46.1 List Available Providers

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/integrations/providers` |
| **Permission** | `integrations.providers.view @ ws` |
| **Response** | `{ providers: [{id, type, name, config_schema, is_available}] }` |
| **Notes** | Reads from platform-scoped `integration_providers` table (no RLS) |

### 46.2 Connect Provider

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/connect` |
| **Permission** | `integrations.connections.manage @ ws` |
| **Request body** | `{ provider_id: UUID, credentials: object }` |
| **Success** | `201` connection in `pending` status, test connection triggered |
| **Side-effects** | Creates `workspace_integrations` row, enqueues connection test job |
| **Errors** | `409 conflict_error` (provider already connected), `422 validation_error` (credentials don't match provider config_schema) |
| **Business rules** | BR-INT-003 |

### 46.3 Test Connection

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/{integration_id}/test` |
| **Permission** | `integrations.connections.manage @ ws` |
| **Success** | `200` `{ status: "active"|"error", message?: string }` |

### 46.4 Disconnect Provider

| Field | Value |
|-------|-------|
| **Method** | DELETE |
| **Path** | `/api/v1/integrations/{integration_id}/disconnect` |
| **Permission** | `integrations.connections.manage @ ws` |
| **Success** | `200` status → `disconnected` |
| **Business rules** | BR-INT-004 (does not delete sync history) |

### 46.5 Integration Health Dashboard

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/integrations/health` |
| **Permission** | `integrations.health.view @ ws` |
| **Response** | `{ connections: [{integration_id, provider_name, type, status, last_sync_at, error_message?, failure_count}] }` |

### 46.6 Webhook CRUD

| Method | Path | Permission | Purpose |
|--------|------|-----------|---------|
| GET | `/api/v1/integrations/webhooks` | `integrations.webhooks.view @ ws` | List webhook subscriptions |
| POST | `/api/v1/integrations/webhooks` | `integrations.webhooks.manage @ ws` | Create subscription |
| PATCH | `/api/v1/integrations/webhooks/{id}` | `integrations.webhooks.manage @ ws` | Update subscription |
| DELETE | `/api/v1/integrations/webhooks/{id}` | `integrations.webhooks.manage @ ws` | Delete subscription |

- **Request body (POST)**: `{ event_type: string, target_url: string, secret?: string }`
- **Available events**: `order.confirmed`, `order.shipped`, `order.delivered`, `payment.received`, `payment.refunded`, `invoice.issued`, `contact.created`, `product.updated`, `inventory.low_stock`
- **Business rules**: BR-INT-001 (retry policy), BR-INT-005 (signature verification for inbound)
- **Schema**: `webhook_subscriptions` (migration 013)

### 46.7 Webhook Deliveries

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/integrations/webhooks/{id}/deliveries` |
| **Permission** | `integrations.webhooks.view @ ws` |
| **Query params** | `?status=pending|delivered|failed&page=&page_size=` |
| **Response** | Paginated list of `{ delivery_id, event_type, status, attempts, last_attempted_at, response_code }` |

### 46.8 Import Job

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/import` |
| **Permission** | `integrations.import.manage @ ws` |
| **Request body** | Multipart file upload + `{ entity_type: "products"|"contacts"|"accounts"|"inventory", column_mapping?: object }` |
| **Success** | `202` job created in `uploaded` status `{ job_id }` |
| **Side-effects** | Creates `import_jobs` row, enqueues validation job |
| **Business rules** | BR-INT-002 |

### 46.9 Import Preview & Apply

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/integrations/import/{job_id}/preview` |
| **Permission** | `integrations.import.manage @ ws` |
| **Pre-conditions** | Job status = `preview` (validation complete) |
| **Response** | `{ job_id, total_rows, valid_rows, error_rows, errors: [{row, column, message}], preview_rows: [first 10 valid rows] }` |

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/import/{job_id}/apply` |
| **Permission** | `integrations.import.manage @ ws` |
| **Pre-conditions** | Job status = `preview`, valid_rows > 0 |
| **Success** | `202` job moves to `applying`, runs as background job |
| **Errors** | `409 conflict_error` (job not in preview state) |

### 46.10 Export Job

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/export` |
| **Permission** | `integrations.export.manage @ ws` |
| **Request body** | `{ entity_type: string, format: "csv"|"xlsx"|"xml"|"json", filters?: object }` |
| **Success** | `202` job queued `{ job_id }` |
| **Side-effects** | Creates `export_jobs` row, enqueues export job |

### 46.11 Sync Logs

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/integrations/sync-logs` |
| **Permission** | `integrations.sync.view @ ws` |
| **Query params** | `?integration_id=&direction=inbound|outbound&status=success|conflict|error&date_from=&date_to=&page=&page_size=` |
| **Response** | Paginated list of sync activity entries |

### 46.12 Trigger Manual Sync

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/integrations/{integration_id}/sync` |
| **Permission** | `integrations.sync.trigger @ ws` |
| **Success** | `202` sync job queued |
| **Errors** | `409 conflict_error` (sync already in progress) |

---

## §47 Task Feed Endpoints [Core v1]

**Module flag**: N/A (always available for authenticated users)
**Entitlement**: No plan gating — tasks are core infrastructure
**Backend**: `TaskFeedService` read model (§33 backend architecture)

### 47.1 My Tasks

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/tasks/my` |
| **Permission** | Implicit — each source query filters by the user's existing RBAC permissions (approval viewer, driver, manager, etc.) |
| **Query params** | `?type=approval,delivery,leave_review,ai_change,import_review,media_approval&status=pending&page=&page_size=` |
| **Response** | Paginated list of task items: `{ task_type, entity_type, entity_id, title, description, created_at, urgency: high|medium|low, action_url, source_permission }` |
| **Sorting** | Default: urgency DESC, created_at DESC |
| **Notes** | No new permission key needed — permission filtering is delegated to each source entity query. Results are merged from 6 source tables (§33.3 backend architecture). |

---

## §48 Knowledge Document Endpoints [Expansion Pack]

**Module flag**: `enable_knowledge` (sub-feature of AI module)
**Entitlement**: Plan-gated via `EntitlementMiddleware` — requires Business or Enterprise plan
**Backend**: Knowledge documents + pgvector RAG (§Decision 7 refinement report)
**Event bus**: Dispatches `ai.knowledge.uploaded`, `ai.knowledge.deleted` events (§29 backend architecture)

### 48.1 List Knowledge Documents

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/knowledge/documents` |
| **Permission** | `ai.knowledge.view @ ws` |
| **Query params** | `?q=&content_type=text,pdf,url&status=processing,ready,failed&page=&page_size=` |
| **Response** | Paginated list: `{ id, title, content_type, status, chunk_count, token_count, uploaded_by, created_at }` |
| **Search** | `?q=` uses SearchService (§28) against `knowledge_documents.title` |

### 48.2 Upload Knowledge Document

| Field | Value |
|-------|-------|
| **Method** | POST |
| **Path** | `/api/v1/knowledge/documents` |
| **Permission** | `ai.knowledge.upload @ ws` |
| **Body** | `{ title, content_type: "text"|"pdf"|"url", content?: string, file?: multipart }` |
| **Success** | `201` document created with `status: processing` |
| **Side-effects** | Background job: chunk text → generate embeddings → store in `knowledge_chunks`. Dispatches `ai.knowledge.uploaded` event on completion. |
| **Errors** | `413` file exceeds 10MB limit, `402` plan does not include knowledge feature, `429` workspace document quota exceeded |

### 48.3 Get Knowledge Document

| Field | Value |
|-------|-------|
| **Method** | GET |
| **Path** | `/api/v1/knowledge/documents/{id}` |
| **Permission** | `ai.knowledge.view @ ws` |
| **Response** | Document detail with chunk list: `{ id, title, content_type, status, chunks: [{ chunk_index, content_preview, token_count }], uploaded_by, created_at }` |

### 48.4 Delete Knowledge Document

| Field | Value |
|-------|-------|
| **Method** | DELETE |
| **Path** | `/api/v1/knowledge/documents/{id}` |
| **Permission** | `ai.knowledge.manage @ ws` |
| **Success** | `204` document and all chunks deleted |
| **Side-effects** | Dispatches `ai.knowledge.deleted` event. |

### 48.5 Knowledge RAG Query (Internal)

| Field | Value |
|-------|-------|
| **Method** | Internal service call (not exposed as public API) |
| **Called by** | AI chat service when processing advisory/chat requests |
| **Logic** | Generate embedding for user query → cosine similarity search on `knowledge_chunks.embedding` via pgvector → return top-K chunks (K=5, configurable) → inject into AI context window as "Business Knowledge" section |
| **Access** | Workspace-scoped via RLS — AI can only retrieve chunks belonging to the current workspace |

---

## §49 External Portal Endpoints [Architecture-Ready]

> These endpoints are NOT built in v1. This section defines the architectural contract for future portal implementation.

**Access model**: Token-based guest access via `portal_tokens` (future migration)
**Authentication**: `Authorization: Bearer {portal_token}` → resolved by `PortalAuthMiddleware`
**Scope restriction**: Portal users can ONLY access entities linked to their `contact_id`

### 49.1 Portal-Eligible Endpoints (future)

| Endpoint | Method | Portal Access | Scope |
|----------|--------|--------------|-------|
| `/api/v1/portal/orders` | GET | Customer | Own orders only (contact_id filter) |
| `/api/v1/portal/orders/{id}` | GET | Customer | Own order detail |
| `/api/v1/portal/invoices` | GET | Customer | Own invoices only |
| `/api/v1/portal/invoices/{id}` | GET | Customer | Own invoice detail |
| `/api/v1/portal/invoices/{id}/pay` | POST | Customer | Submit payment for own invoice |
| `/api/v1/portal/shipments` | GET | Customer / Supplier | Own shipments |
| `/api/v1/portal/purchase-orders` | GET | Supplier | POs addressed to supplier |
| `/api/v1/portal/purchase-orders/{id}/acknowledge` | POST | Supplier | Acknowledge PO receipt |

### 49.2 Portal Access Rules

1. Portal tokens are workspace-scoped and expire (default 30 days, renewable)
2. Portal users can NEVER access: admin, HR, finance, AI, platform, or settings endpoints
3. All portal queries enforce `WHERE contact_id = :portal_contact_id` in addition to workspace RLS
4. Portal authentication failures return `401` with generic error (no information leakage)

---

*End of API contracts. Version 3.0 — 2026-04-10. Added §47 Task Feed, §48 Knowledge Documents, §49 Portal (architecture-ready). Updated §5 search standard and §6 entitlement errors.*