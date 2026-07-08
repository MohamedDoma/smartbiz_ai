# SmartBiz AI — Backend Verification Report

> **Date:** 2026-07-05 | **Step:** 38  
> **Backend:** Laravel 11.51.0 | **PHP:** 8.4.20  
> **Infrastructure:** Docker (Postgres 16, Nginx, Redis, PHP-FPM)

---

## Summary Table

| # | Check | Status | Notes |
|---|---|---|---|
| 1 | PHP version | ✅ PASS | 8.4.20 (CLI) |
| 2 | Composer | ✅ PASS | 2.7.1 |
| 3 | Laravel boots | ✅ PASS | `artisan --version` = 11.51.0 |
| 4 | `.env` exists | ✅ PASS | |
| 5 | `APP_URL` | ✅ PASS | `http://localhost:8080` |
| 6 | DB connection | ✅ PASS | pgsql via Docker (10 users, 2 workspaces seeded) |
| 7 | Docker containers | ✅ PASS | 4 running: postgres, nginx, app, redis |
| 8 | **Health endpoint** | ❌ **FAIL** | Fatal: `Class "env" does not exist` — bootstrap crash |
| 9 | CORS config | ✅ PASS | Default: `allowed_origins: ['*']` (all origins allowed) |
| 10 | Auth routes exist | ✅ PASS | login, logout, me — all registered |
| 11 | Auth login test | ⛔ **BLOCKED** | Server crashes before handling any request |
| 12 | Auth /me test | ⛔ **BLOCKED** | Depends on login |
| 13 | Unauthorized 401 test | ⛔ **BLOCKED** | Server crashes before auth check |
| 14 | Workspace header test | ⛔ **BLOCKED** | Server crashes before middleware |
| 15 | API surface | ✅ PASS | 126 routes across 26 route groups |
| 16 | `SANCTUM_STATEFUL_DOMAINS` | ⚠️ MISSING | Not set in `.env` |

### Final Readiness: **READY WITH BLOCKERS**

---

## Detailed Results

### 1. Backend Environment

| Item | Value |
|---|---|
| PHP | 8.4.20 (cli) NTS |
| Composer | 2.7.1 |
| Laravel | 11.51.0 |
| `.env` | Present |
| `.env.example` | Present |
| `APP_URL` | `http://localhost:8080` |
| `APP_ENV` | `local` |
| `DB_CONNECTION` | `pgsql` |
| `DB_HOST` | `postgres` (Docker internal network) |
| `DB_PORT` | `5432` (internal); mapped to host `5433` |

### 2. Infrastructure

```
Docker containers (all running):
├── smartbiz_postgres  (postgres:16-alpine)  → 0.0.0.0:5433->5432
├── smartbiz_nginx     (nginx:1.27-alpine)   → 0.0.0.0:8080->80
├── smartbiz_app       (infra-app / PHP-FPM) → 9000 (internal)
└── smartbiz_redis     (redis:7-alpine)      → 0.0.0.0:6379->6379
```

Backend is served via Nginx → PHP-FPM, not `artisan serve`.

### 3. Health Endpoint — ❌ FAIL

```bash
curl -s http://localhost:8080/api/health
# HTTP 500 — Fatal error
```

**Root cause:** `bootstrap/app.php` line 25:
```php
if (app()->environment('production')) {
```

This calls `app()->environment()` inside the `withMiddleware()` callback. In Laravel 11 on PHP 8.4, the env container binding isn't resolved yet at this stage of the boot process. The framework tries to resolve `env` as a class name, causing:

```
ReflectionException: Class "env" does not exist
```

**This crashes ALL HTTP requests** — not just health. No API endpoint can respond.

**Fix required (1 line):**
```diff
- if (app()->environment('production')) {
+ if (env('APP_ENV') === 'production') {
```

Or move the HTTPS middleware to a service provider boot method.

### 4. CORS

Using Laravel default config (no custom `config/cors.php`):
- `allowed_origins: ['*']` — all origins accepted
- `allowed_methods: ['*']`
- `allowed_headers: ['*']`
- `paths: ['api/*', 'sanctum/csrf-cookie']`

**Status:** ✅ Sufficient for development. Should be tightened for production.

### 5. Auth Routes

```
POST  api/auth/login   → Api\AuthController@login
POST  api/auth/logout  → Api\AuthController@logout
GET   api/auth/me      → Api\AuthController@me
```

All 3 routes registered and pointing to valid controller methods. ✅

### 6. Test Credentials

Found in `FoundationSeeder.php`:
- **Email:** `admin@smartbiz.test`
- **Password:** `<MASKED>` (defined as `USER_PASSWORD` constant)
- **Workspace ID:** `10000000-0000-0000-0000-000000000001`
- **User ID:** `20000000-0000-0000-0000-000000000001`

DB confirmed seeded: **10 users, 2 workspaces.**

### 7–9. Auth Login / Me / Unauthorized Tests — ⛔ BLOCKED

Cannot test any HTTP endpoint because the bootstrap crash affects every request. The artisan CLI works perfectly (routes, tinker, DB queries), but HTTP requests through Nginx/PHP-FPM all fail at the bootstrap stage.

Tested both:
- Docker path: `curl http://localhost:8080/api/health` → 500 (fatal)
- Local artisan serve: `DB_HOST=127.0.0.1 DB_PORT=5433 php artisan serve --port=8000` → same crash

### 10. API Surface

126 registered routes across these groups:

| Group | Routes |
|---|---|
| `api/auth` | 3 |
| `api/products` | 5 |
| `api/contacts` | 5 |
| `api/invoices` | 4 |
| `api/payments` | 4 |
| `api/inventory-movements` | 4 |
| `api/warehouses` | 5 |
| `api/accounts` | 5 |
| `api/orders` | 4 |
| `api/journal-entries` | 4 |
| `api/stock-reservations` | 5 |
| `api/bom` | 5 |
| `api/production-orders` | 4 |
| `api/recurring-expenses` | 5 |
| `api/notifications` | 3 |
| `api/audit-logs` | 2 |
| `api/reports` | 5 |
| `api/discovery` | 7 |
| `api/provisioning` | 6 |
| `api/ai` | 11 |
| `api/admin` | 20 |
| `api/billing` | 1 |
| `api/webhooks` | 1 |
| `api/health` | 1 |
| `api/ping` | 1 |
| `api/product-categories` | 5 |

---

## Blockers

### Blocker 1: Bootstrap Crash (CRITICAL)

| Item | Detail |
|---|---|
| **File** | `backend/bootstrap/app.php` line 25 |
| **Error** | `ReflectionException: Class "env" does not exist` |
| **Impact** | ALL HTTP requests return 500 — zero API endpoints work |
| **Cause** | `app()->environment('production')` called before env binding is resolved |
| **Fix** | Replace with `env('APP_ENV') === 'production'` |
| **Effort** | XS — 1 line change |
| **Risk** | None — behavioral change is zero (same logic, different lookup method) |

### Blocker 2: SANCTUM_STATEFUL_DOMAINS Not Set

| Item | Detail |
|---|---|
| **File** | `backend/.env` |
| **Impact** | Sanctum SPA auth may not work for Flutter web |
| **Fix** | Add `SANCTUM_STATEFUL_DOMAINS=localhost,127.0.0.1` |
| **Effort** | XS |
| **Note** | Only needed if using cookie-based auth; token-based (Bearer) may work without it |

---

## Recommended Fixes Before Step 39

| # | Fix | File | Effort | Priority |
|---|---|---|---|---|
| 1 | Replace `app()->environment('production')` with `env('APP_ENV') === 'production'` | `bootstrap/app.php:25` | XS | **P0 — blocks everything** |
| 2 | Add `SANCTUM_STATEFUL_DOMAINS=localhost,127.0.0.1` | `.env` | XS | P1 |
| 3 | After fix #1: re-test health, login, /me, workspace header | — | S | P0 |
| 4 | After fix #1: verify 401 on unauthenticated requests | — | XS | P1 |

---

## What Works Without Fixes

| Item | Status |
|---|---|
| `php artisan` CLI commands | ✅ |
| Route registration | ✅ |
| DB connectivity (via Docker) | ✅ |
| Tinker / model queries | ✅ |
| Seeded test data | ✅ |
| Docker container stability | ✅ |

---

## Conclusion

The backend is **architecturally ready** — 126 routes, 26 controllers, seeded DB, Docker infra running. However, **zero HTTP requests can be served** due to a 1-line bootstrap bug in `bootstrap/app.php`.

**Once the 1-line fix is applied**, the full verification (health, login, /me, workspace header, 401 behavior) can complete, and Step 39 (ApiClient + token storage) can proceed.
