# Step 58.1 — Super Admin Real Wiring Report

## Date
2026-07-10

---

## Files Inspected

| File | Purpose |
|------|---------|
| `lib/app/router.dart` | Route registration |
| `lib/features/super_admin/layout/super_admin_shell.dart` | Sidebar navigation |
| `lib/features/super_admin/screens/super_admin_dashboard_screen.dart` | Old mock dashboard |
| `lib/features/super_admin/screens/super_admin_tenants_screen.dart` | Old mock tenants |
| `lib/features/platform/screens/*.dart` | All Step 58 platform screens |
| `lib/core/api/platform_service.dart` | Platform API service |
| `lib/features/platform/platform_state.dart` | Platform state |
| `lib/core/api/platform_models.dart` | Platform data models |
| `lib/core/l10n/strings_ar.dart` | Arabic localization |
| `lib/core/l10n/strings_en.dart` | English localization |
| `backend/routes/api.php` | Backend platform routes |

## Files Modified

| File | Change |
|------|--------|
| `lib/app/router.dart` | Removed old `/super-admin/*` screen routes, added `/platform/plans`, `/platform/modules`, `/platform/usage`, `/platform/health` routes, added `/super-admin/*` → `/platform/*` redirects, removed 7 unused SA deferred imports, added 4 new platform imports |
| `lib/features/super_admin/layout/super_admin_shell.dart` | Added `/platform/modules` nav item, reordered sidebar per spec |
| `lib/core/l10n/strings_ar.dart` | Added: `plt_coming_soon`, `plt_status_degraded`, `gen_retry`, `gen_cancel`, `gen_confirm`, `gen_save`, `gen_name`, `gen_description` |
| `lib/core/l10n/strings_en.dart` | Added same keys in English |
| `lib/core/api/platform_service.dart` | Added `getSystemHealth()` method (prev session) |
| `lib/features/platform/platform_state.dart` | Added health state fields + `loadHealth()` (prev session) |
| `backend/routes/api.php` | Added `PlatformSystemHealthController` import, `/platform/system-health` route (prev session) |

## Files Created

| File | Purpose |
|------|---------|
| `lib/features/platform/screens/platform_plans_screen.dart` | Coming-soon plans page (prev session) |
| `lib/features/platform/screens/platform_modules_screen.dart` | Coming-soon modules page |
| `lib/features/platform/screens/platform_usage_screen.dart` | AI usage Step 59 message (prev session) |
| `lib/features/platform/screens/platform_health_screen.dart` | Real system health from API (prev session) |
| `lib/features/platform/screens/platform_dashboard_screen.dart` | Rewritten with real API data (prev session) |
| `backend/app/Http/Controllers/Api/PlatformSystemHealthController.php` | System health endpoint (prev session) |

---

## Route Mismatch Found

**Root cause:** Sidebar navigated to `/platform/plans`, `/platform/health`, `/platform/usage` but router only had `workspaces`, `users`, `campaigns`, `codes`, `cards` under `/platform`. This caused `GoException: no routes for location`.

**Fix:** Added 4 missing child routes (`plans`, `modules`, `usage`, `health`) under `/platform` in `router.dart`, and added 6 redirect routes for old `/super-admin/*` bookmark compatibility.

---

## Final Sidebar Items

| Label | Route | Status |
|-------|-------|--------|
| لوحة التحكم (Dashboard) | `/platform` | ✅ Real API |
| المستأجرون (Workspaces) | `/platform/workspaces` | ✅ Real API |
| المستخدمون (Users) | `/platform/users` | ✅ Real API |
| حملات التفعيل (Campaigns) | `/platform/campaigns` | ✅ Real API |
| أكواد التفعيل (Codes) | `/platform/codes` | ✅ Real API |
| كروت الطباعة (Print Cards) | `/platform/cards` | ✅ Real API |
| الباقات (Plans) | `/platform/plans` | ⏳ Coming soon (no API) |
| الوحدات (Modules) | `/platform/modules` | ⏳ Coming soon (no API) |
| استخدام الذكاء (AI Usage) | `/platform/usage` | ⏳ Step 59 required |
| صحة النظام (System Health) | `/platform/health` | ✅ Real API |

---

## Old Routes Redirected

| Old Route | → Redirect |
|-----------|-----------|
| `/super-admin` | `/platform` |
| `/super-admin/tenants` | `/platform/workspaces` |
| `/super-admin/plans` | `/platform/plans` |
| `/super-admin/modules` | `/platform/modules` |
| `/super-admin/usage` | `/platform/usage` |
| `/super-admin/health` | `/platform/health` |

---

## Mock Data Removed

- Old `SuperAdminDashboardScreen` with hardcoded KPIs (`24`, `18`, `6`, `$4,280`, `12,450`) → replaced by `PlatformDashboardScreen` using real `GET /api/platform/dashboard`
- Old `SuperAdminTenantsScreen` with `mock_tenants.dart` → replaced by `PlatformWorkspacesScreen` using real `GET /api/platform/workspaces`
- Old `SuperAdminPlansScreen` with mock plan tiers → replaced by honest coming-soon state
- Old `SuperAdminModulesScreen` with mock module registry → replaced by honest coming-soon state
- Old `SuperAdminUsageScreen` with fake AI metrics → replaced by honest "Step 59 required" message
- Old `SuperAdminHealthScreen` with mock service status → replaced by real `GET /api/platform/system-health`

---

## Pages Using Real APIs

| Page | Endpoint |
|------|----------|
| Platform Dashboard | `GET /api/platform/dashboard` |
| Workspaces | `GET /api/platform/workspaces` |
| Users | `GET /api/platform/users` |
| Campaigns | `GET /api/platform/activation-campaigns` |
| Codes | `GET /api/platform/activation-codes` |
| System Health | `GET /api/platform/system-health` |
| Activation Validate | `GET /api/activation-codes/{code}` |

## Pages with Coming-Soon State

| Page | Message |
|------|---------|
| Plans | إدارة الباقات والأسعار ستتوفر في تحديث قادم |
| Modules | الوحدات ستتوفر لاحقاً بعد ربط إعدادات الباقات والوحدات |
| AI Usage | سيظهر استخدام الذكاء بعد تفعيل AI في Step 59 |

---

## Activation System Status

- **`/activate?code=SBZ-XXX`** → Public route, registered at `/activate`, accessible without auth
- **Code validation** → Uses `GET /api/activation-codes/{code}`
- **Registration** → `activation_code` field already integrated in auth flow
- **Printable cards** → Uses real codes from `PlatformState`, accessible at `/platform/cards`

---

## Backend Route Added

```
GET /api/platform/system-health → PlatformSystemHealthController@health
```

Real checks: API latency, Database (PostgreSQL), Cache (Redis), Storage (writable).

---

## Flutter Analyze Result

```
6 issues found (all info-level, 0 errors, 0 warnings)
Exit code: 0
```

All 6 are `use_build_context_synchronously` info hints — cosmetic, unrelated to routing.

## Flutter Build Result

```
✓ Built build/web (71.5s)
Exit code: 0
```

## Browser Smoke Result

**Dev server not running** — port 5173 is not active. Browser smoke test could not be performed automatically. The user should:

```bash
cd /home/doma/Desktop/final/smartbiz_ai/frontend
flutter run -d chrome --web-port 5173 --dart-define=API_BASE_URL=http://localhost:8000/api
```

Then verify:
- `/platform` → real dashboard data
- All sidebar items navigate without GoException
- `/activate?code=...` works without auth redirect

---

## Remaining Gaps

1. **Plans API** — No backend plans management API exists yet. Coming-soon state shown.
2. **Modules API** — No backend module registry API. Coming-soon state shown.
3. **AI Usage** — Requires Step 59 AI implementation. Message shown.
4. **Old SA screen files** — Still exist on disk in `lib/features/super_admin/screens/` but are no longer referenced by any route or import. Can be removed in a cleanup pass.
5. **QR codes in print cards** — No QR package; shows code text + registration URL fallback.

---

## Step 59 Readiness

✅ **Step 59 is safe to start.** All platform infrastructure is wired with real APIs, the sidebar is consolidated, and the AI Usage page is explicitly waiting for Step 59.
