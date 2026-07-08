# SmartBiz AI — Auth Session Contract Alignment Report

> **Date:** 2026-07-06 | **Step:** 39.5  
> **Scope:** Backend `AuthController` — login + /me session payload

---

## Files Changed

| File | Change |
|---|---|
| `app/Http/Controllers/Api/AuthController.php` | Replaced with product-grade session payload via `buildSessionPayload()` |

No other files modified. No migrations, no schema changes, no new models.

---

## Final `/api/auth/login` Response Shape

```json
{
  "token": "<MASKED>",
  "user": {
    "id": "20000000-...",
    "full_name": "Admin User",
    "email": "admin@smartbiz.test",
    "phone_number": "+10000000000",
    "is_active": true,
    "preferred_locale": null,
    "platform_role": "super_admin",
    "created_at": "2026-04-16T16:41:05+00:00"
  },
  "active_workspace": {
    "id": "10000000-...",
    "name": "Test Workspace",
    "role_key": "admin",
    "onboarding_completed": false,
    "enabled_modules": [],
    "permissions": ["contacts.list", "products.list", "..."]
  },
  "memberships": [
    {
      "id": "30000000-...",
      "workspace_id": "10000000-...",
      "workspace": { "id": "...", "name": "Test Workspace" },
      "status": "active",
      "department_id": null,
      "branch_id": null,
      "joined_at": "2026-04-16T16:41:05+00:00",
      "primary_role": {
        "role_id": "40000000-...",
        "role_name": "Admin",
        "role_key": "admin"
      },
      "roles": [{ "role_id": "...", "role_name": "Admin", "role_key": "admin", "is_primary": true }],
      "onboarding_completed": false,
      "enabled_modules": [],
      "permissions": ["contacts.list", "products.list", "..."]
    }
  ]
}
```

## Final `/api/auth/me` Response Shape

Identical to login, minus the `token` field.

---

## Field Sources

| Field | Source | Notes |
|---|---|---|
| `user.platform_role` | `users.is_super_admin` column | `true` → `"super_admin"`, else `"none"` |
| `active_workspace` | First active membership | Workspace + primary role + onboarding + modules + permissions |
| `*.onboarding_completed` | `provisioning_runs` table | `true` if at least 1 run with `status = 'completed'` for workspace |
| `*.enabled_modules` | `workspace_feature_flags` table | Array of `feature_key` where `is_enabled = true` |
| `*.permissions` | `roles.permissions` JSONB merged | All permissions from all assigned roles via `membership_roles → role` |
| `*.primary_role` | `membership_roles` where `is_primary = true` | Falls back to first role if none marked primary |
| `*.roles[]` | All `membership_roles` for membership | Full list with `is_primary` flag |

---

## Curl Test Results

| Test | Status | Notes |
|---|---|---|
| `POST /api/auth/login` | ✅ 200 | Token + user + active_workspace + memberships |
| `GET /api/auth/me` | ✅ 200 | user + active_workspace + memberships (same shape, no token) |
| `user.platform_role` | ✅ `"super_admin"` | Correct for seeded admin user |
| `active_workspace.role_key` | ✅ `"admin"` | From primary role |
| `active_workspace.onboarding_completed` | ✅ `false` | No provisioning runs exist for test workspace |
| `active_workspace.enabled_modules` | ✅ `[]` | No feature flags set for test workspace |
| `active_workspace.permissions` | ✅ 48 permissions | Full admin role permissions merged |
| `memberships[0].primary_role` | ✅ Present | role_id, role_name, role_key |
| `memberships[0].roles` | ✅ Array | 1 role with is_primary=true |

---

## Backward Compatibility

| Aspect | Status |
|---|---|
| Login still returns `token` | ✅ |
| Login still returns `user` | ✅ (now enriched with `platform_role`) |
| Logout unchanged | ✅ |
| Auth routes unchanged | ✅ |
| No DB schema changes | ✅ |
| No migrations needed | ✅ |

---

## Remaining Gaps

| # | Gap | Impact | When |
|---|---|---|---|
| 1 | `enabled_modules` is empty for test workspace | Expected — no feature flags seeded | Will populate after onboarding/provisioning integration |
| 2 | `onboarding_completed` is `false` for test workspace | Expected — no provisioning runs exist | Will become `true` after discovery + provisioning flow |
| 3 | No `POST /auth/register` endpoint | Registration blocked | Step 42 |

None of these gaps block Step 40 (frontend auth integration).

---

## Step 40 Readiness: ✅ SAFE TO START

The backend now returns every field the Flutter frontend needs for:
- **Platform role guard** (`platform_role: "super_admin" | "none"`)
- **Onboarding routing** (`onboarding_completed: bool`)
- **Module navigation** (`enabled_modules: string[]`)
- **RBAC enforcement** (`permissions: string[]`)
- **Workspace context** (`active_workspace.id`)
- **Role display** (`primary_role.role_key`)
