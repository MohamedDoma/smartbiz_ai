# SmartBiz AI — Employee Invite Integration Report

> **Date:** 2026-07-07 | **Step:** 50
> **Scope:** Employee invite backend + frontend integration

---

## Backend Files Created (4)

| File | Purpose |
|---|---|
| `database/migrations/025_workspace_invitations.php` | Creates `workspace_invitations` table with token hashing, FKs, indexes, unique constraint |
| `app/Models/WorkspaceInvitation.php` | Eloquent model with UUID, relationships, scopes, status helpers |
| `app/Http/Controllers/Api/WorkspaceInvitationController.php` | Full controller: create, list, revoke, preview, accept, listRoles |
| `app/Services/AuthSessionPayloadBuilder.php` | Extracted session payload builder for reuse by AuthController + InvitationController |

## Backend Files Modified (2)

| File | Change |
|---|---|
| `app/Http/Controllers/Api/AuthController.php` | Delegates `buildSessionPayload()` to `AuthSessionPayloadBuilder::build()`. Removed ~100 lines of duplicated logic |
| `routes/api.php` | Added 6 new routes: 2 public + 3 workspace-scoped + 1 roles endpoint |

## Migration: `workspace_invitations`

| Column | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `workspace_id` | UUID FK → workspaces | indexed |
| `email` | string(255) | indexed |
| `full_name` | string nullable | |
| `role_id` | UUID FK → roles nullable | |
| `invited_by_user_id` | UUID FK → users | |
| `accepted_user_id` | UUID FK → users nullable | |
| `token_hash` | string(64) UNIQUE | SHA-256 hash; raw token never stored |
| `status` | string(20) default `pending` | pending/accepted/revoked/expired; indexed |
| `expires_at` | timestamp | indexed |
| `accepted_at` | timestamp nullable | |
| `revoked_at` | timestamp nullable | |
| `metadata` | jsonb nullable | |
| timestamps | | |

**Unique constraint:** `(workspace_id, email, status)` prevents duplicate pending invites.

---

## Endpoints Created (6)

### Authenticated Workspace-Scoped

| Method | Path | Behavior |
|---|---|---|
| GET | `/api/workspace-invitations` | List invites for current workspace |
| POST | `/api/workspace-invitations` | Create invite (owner/admin/general_manager only) |
| POST | `/api/workspace-invitations/{id}/revoke` | Revoke pending invite |
| GET | `/api/workspace-roles` | List roles for invite UI role selector |

### Public (No Auth)

| Method | Path | Behavior |
|---|---|---|
| GET | `/api/invites/{token}` | Preview invite (validate token) |
| POST | `/api/invites/{token}/accept` | Accept invite → create user + membership + role + Sanctum token |

---

## Security Decisions

| Decision | Detail |
|---|---|
| **Token storage** | Raw token NEVER stored. Only SHA-256 hash (`token_hash`) persisted |
| **Token length** | 64 random characters via `Str::random(64)` |
| **Token return** | Raw token returned ONCE in create response, never again |
| **Token logging** | Not logged |
| **Permission check** | Only `owner`, `admin`, `general_manager` role_keys can create invites |
| **Rate limiting** | Accept endpoint uses `throttle:auth` |
| **Duplicate prevention** | 409 if pending invite exists for same workspace + email |
| **Existing user** | 409 with "existing-user invite acceptance will be supported later" |
| **Expired invite** | Marked expired in DB, returns 410 |
| **Revoked invite** | Returns 410 |
| **Already accepted** | Returns 409 |

## Invite Acceptance Behavior

1. Validate invitation (pending, not expired)
2. Check no existing user with invite email
3. DB transaction:
   - Create User (email from invite, not request)
   - Create WorkspaceMembership (active, joined_at = now)
   - Create MembershipRole (role from invite, is_primary = true)
   - Update invitation (accepted, accepted_at, accepted_user_id)
4. Create Sanctum token (24hr expiry)
5. Return `AuthSession` payload (same shape as login/register)

---

## Frontend Files Created (2)

| File | Purpose |
|---|---|
| `lib/core/api/workspace_invite_models.dart` | `WorkspaceRoleSummary`, `WorkspaceInvitation`, `InvitePreview`, `CreateWorkspaceInvitationPayload`, `AcceptInvitePayload` |
| `lib/core/api/workspace_invite_service.dart` | `listWorkspaceRoles`, `listInvites`, `createInvite`, `revokeInvite`, `previewInvite`, `acceptInvite` |

## Frontend Files Modified (5)

| File | Change |
|---|---|
| `lib/core/state/app_state.dart` | Added `inviteService`, `acceptEmployeeInviteReal()` method |
| `lib/features/auth/screens/invite_accept_screen.dart` | **Rewrote** — real preview on load, phone field, async accept, error handling, loading states |
| `lib/features/employees/screens/invite_employee_screen.dart` | **Rewrote** — real role selector from API, async create, invite link display, pending invites list with revoke |
| `lib/core/l10n/strings_en.dart` | 12 new keys |
| `lib/core/l10n/strings_ar.dart` | 12 matching Arabic keys |

---

## Invite UI Behavior

### Invite Accept Screen (`/invite/:token`)

- **On load:** Calls `GET /api/invites/{token}` to preview
- **Shows:** Workspace name, invited email, role name
- **Fields:** Full name, phone number, password, confirm password
- **Submit:** Calls `acceptEmployeeInviteReal()` → stores token → routes to dashboard/onboarding
- **Error states:** Invalid token (404), expired (410), revoked (410), accepted (409), validation errors
- **Loading states:** Preview loading spinner, submit loading spinner

### Invite Employee Screen (`/employees/invite`)

- **On load:** Fetches workspace roles + existing invites
- **Fields:** Name, email, role dropdown (from backend)
- **Submit:** Creates invite → shows invite link (SelectableText)
- **Pending invites section:** Lists all invites with status badges + revoke button
- **Error handling:** Validation errors, duplicate invite (409)

---

## E2E Test Summary

| # | Test | Expected | Result |
|---|---|---|---|
| 1 | GET /workspace-roles | 200, roles list | ✅ 6 roles |
| 2 | POST /workspace-invitations | 201, token returned | ✅ |
| 3 | GET /workspace-invitations | 200, 1 pending invite | ✅ |
| 4 | GET /invites/{token} | 200, preview data | ✅ |
| 5 | POST /invites/{token}/accept | 201, session + token | ✅ |
| 6 | GET /auth/me (employee token) | 200, correct workspace/role | ✅ |
| 7 | GET /ping (employee, workspace header) | 200, workspace confirmed | ✅ |
| 8 | POST /invites/{token}/accept (duplicate) | 409 | ✅ |
| 9 | POST /workspace-invitations (duplicate email) | 409 | ✅ |
| 10 | POST /{id}/revoke + preview revoked | 200 + 410 | ✅ |
| 11 | POST /workspace-invitations (no workspace header) | 400 | ✅ |
| 12 | POST /workspace-invitations (unauthenticated) | 401 | ✅ |
| 13 | GET /invites/invalidtoken | 404 | ✅ |

---

## Flutter Analyze

```
flutter analyze (7 files): No issues found!
```

---

## Role Selection Behavior

- Roles fetched from `GET /api/workspace-roles` (workspace-scoped)
- Returns all roles for the workspace (created by template application)
- UI filters out `owner` role from invite dropdown
- Role ID sent with invite → stored in invitation → assigned to membership on accept

---

## Remaining Gaps

| # | Gap | Scope |
|---|---|---|
| 1 | Existing-user invite acceptance | Returns 409 — "will be supported later" |
| 2 | Real email sending | No email provider — link shown/copied in UI |
| 3 | Clipboard copy button | Not added (would need package) |
| 4 | Invite expiry display in UI | Stored but not prominently shown |
| 5 | Bulk invite | Not implemented |
| 6 | Invite resend | Not implemented |
| 7 | Employee permissions check middleware | Uses role_key check, not full permission engine |
| 8 | Frontend invite link uses localhost | Production would need env-based base URL |
| 9 | Departments/teams assignment in invite | Not in this step |
| 10 | HR fields (hire_date, salary) on invite | Future |

---

## Step 51 Readiness: ✅ SAFE TO START

Full invite pipeline operational:
- ✅ Backend: migration + model + controller + routes (6 endpoints)
- ✅ Token security: SHA-256 hash, 64-char random, returned once
- ✅ Permission check: owner/admin/general_manager only
- ✅ Session payload: reused via extracted `AuthSessionPayloadBuilder`
- ✅ Accept flow: creates user + membership + role + token in transaction
- ✅ Frontend: 2 API files + 2 screens rewritten + AppState updated
- ✅ Role selector from real backend roles
- ✅ Invite link display (SelectableText)
- ✅ Pending invites list with revoke
- ✅ Error handling (duplicate, expired, revoked, validation, auth)
- ✅ Loading states on all async operations
- ✅ Localization: EN + AR (12 new keys each)
- ✅ Zero backend modifications to existing controllers' behavior
- ✅ AuthController refactored (no behavior change, just delegation)
- ✅ Flutter analyze: 0 issues
- ✅ 13/13 API tests pass
