# SmartBiz AI — Backend Register Endpoint Report

> **Date:** 2026-07-06 | **Step:** 42  
> **Scope:** `POST /api/auth/register` — production-ready business owner registration

---

## Files Changed

| File | Change |
|---|---|
| `app/Http/Controllers/Api/AuthController.php` | Added `register()` method + helpers: `seedOwnerRole()`, `defaultOwnerPermissions()`, `createTrialSubscription()` |
| `routes/api.php` | Added public route `POST /api/auth/register` with `throttle:auth` |

---

## Route Added

```
POST /api/auth/register  → Api\AuthController@register
```

- Public (no auth middleware)
- Throttled via `throttle:auth`
- Returns 201 on success, 422 on validation errors, 500 on server error

---

## Request Fields Supported

| Field | Rules | Notes |
|---|---|---|
| `full_name` | required, string, max 255 | |
| `email` | required, valid email, unique, max 255 | |
| `password` | required, string, min 8, confirmed | `password_confirmation` required |
| `phone_number` | nullable, string, max 30 | DB column is NOT NULL; defaults to `''` |
| `workspace_name` | nullable, string, max 255 | Either this or `business_name` required |
| `business_name` | nullable, string, max 255 | Alias for `workspace_name` |
| `business_type` | nullable, string, max 100 | |
| `business_size` | nullable, string, max 50 | |
| `preferred_locale` | nullable, string, `en` or `ar` | |

**Normalization:**
- If `workspace_name` missing → uses `business_name`
- If both missing → returns 422

---

## Transaction Behavior

All inside `DB::transaction()`:

1. **User** created (is_super_admin = false, is_active = true)
2. **Workspace** created (status = active, subscription_status = trial)
3. **Owner Role** seeded for workspace (copies permissions from existing seeded template)
4. **WorkspaceMembership** created (status = active, joined_at = now)
5. **MembershipRole** created (is_primary = true)
6. **WorkspaceSubscription** trial created (14-day trial on Free plan)

On any failure → full rollback, returns 500.

---

## Role Assignment

- **Source:** Copies permissions from existing seeded Owner role (`role_key = 'owner'`, `is_system = true`)
- **Fallback:** If no template exists, uses hardcoded 67-permission default list
- Creates workspace-scoped role with:
  - `role_key = 'owner'`, `hierarchy_level = 0`
  - `is_system = true`, `is_deletable = false`

---

## Subscription / Trial Behavior

✅ Trial subscription created using:
- **Plan:** Free plan (slug = `free`)
- **Plan Price:** First active price for the plan
- **Trial period:** 14 days
- **Billing cycle:** Monthly

Silently skips if no plans or prices are seeded — does not block registration.

---

## Response Shape (201)

Same structure as `/auth/login` and `/auth/me`:

```json
{
  "token": "<sanctum_token>",
  "user": {
    "id": "...",
    "full_name": "Test Owner",
    "email": "...",
    "platform_role": "none",
    "is_active": true,
    "preferred_locale": "en",
    "created_at": "..."
  },
  "active_workspace": {
    "id": "...",
    "name": "Test Cars",
    "role_key": "owner",
    "onboarding_completed": false,
    "enabled_modules": [],
    "permissions": ["contacts.list", "..."] 
  },
  "memberships": [{ ... }]
}
```

Reuses `buildSessionPayload()` — no duplicated response logic.

---

## Curl Test Summary

| Test | Expected | Result |
|---|---|---|
| A. Successful register (unique email) | 201, token + full session | ✅ token=true, user=Test Owner, ws=Test Cars, role=owner, permissions=67, onboarding=false |
| B. Duplicate email | 422 | ✅ |
| C. Missing required fields | 422 | ✅ |
| D. Login with new user | 200, token returned | ✅ |
| E. `/auth/me` with register token | 200, session payload | ✅ user + ws + 67 permissions |
| F. `GET /api/products` with workspace header | 200 (empty data) | ✅ products=[]\, workspace isolation works |

---

## Security

- ✅ Password hashed with `Hash::make()`
- ✅ Password never returned in response
- ✅ Password never logged
- ✅ Token not printed in report
- ✅ New users always have `platform_role = none`
- ✅ `is_super_admin = false` enforced

---

## Remaining Gaps

| # | Gap | When |
|---|---|---|
| 1 | Frontend register screen needs to call real API | Step 43 |
| 2 | Email verification (send verification email) | Future |
| 3 | Additional system roles (admin, cashier, etc.) seeding per workspace | Future provisioning |
| 4 | Workspace slug generation | Future (no slug column exists) |
| 5 | phone_number DB column should be nullable (currently NOT NULL) | DB migration fix |

---

## Step 43 Readiness: ✅ SAFE TO START

Backend register endpoint is fully operational:
- ✅ User + Workspace + Membership + Role + Subscription created atomically
- ✅ Returns same session payload shape as login/me
- ✅ 422 validation for duplicate email / missing fields
- ✅ Login works with newly registered user
- ✅ `/auth/me` works with register token
- ✅ Workspace-scoped routes (products) work with new workspace
