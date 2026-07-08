# Step 56 — Report Templates

**Status:** ✅ Complete  
**Date:** 2026-07-08

---

## Summary

Added configurable report templates with catalog-based validation, safe execution against 8 data sources, run history tracking, and Arabic-first Flutter UI. Reports query existing workspace data (contacts, pipeline records, commissions, products, invoices, payments, ownership, duplicate matches) with whitelisted columns and filters — no raw SQL accepted.

---

## Migration

**File:** `database/migrations/032_report_templates.php`

| Table | Purpose |
|---|---|
| `report_templates` | Template configuration with data source, columns, filters, sort, visibility |
| `report_runs` | Execution history with status, row count, summary, error tracking |

Key constraints:
- `report_tpl_ws_name_unique`: workspace_id + name (no duplicate template names)
- FK cascade on workspace delete
- FK nullOnDelete for membership references

---

## Backend Files

### New Files (7)
| File | Purpose |
|---|---|
| `database/migrations/032_report_templates.php` | 2 tables |
| `app/Models/ReportTemplate.php` | JSON casts for columns/filters/sort/group |
| `app/Models/ReportRun.php` | JSON casts for parameters/summary |
| `app/Services/ReportCatalogService.php` | 8 data sources with whitelisted columns/filters |
| `app/Services/ReportExecutionService.php` | Template + ad-hoc execution with filter/sort/summary |
| `app/Http/Controllers/Api/ReportCatalogController.php` | List/show catalog |
| `app/Http/Controllers/Api/ReportTemplateController.php` | CRUD + run with validation |
| `app/Http/Controllers/Api/ReportRunController.php` | List/show/ad-hoc runs |

### Modified Files (1)
| File | Change |
|---|---|
| `routes/api.php` | +3 use statements, +11 new routes |

---

## Endpoints (11 routes)

**Catalog:**
```
GET  /api/report-catalog
GET  /api/report-catalog/{data_source}
```

**Templates:**
```
GET    /api/report-templates
POST   /api/report-templates
GET    /api/report-templates/{id}
PUT    /api/report-templates/{id}
DELETE /api/report-templates/{id}
POST   /api/report-templates/{id}/run
```

**Runs:**
```
GET    /api/report-runs
GET    /api/report-runs/{id}
POST   /api/reports/run  (ad-hoc)
```

---

## Supported Data Sources (8)

| Source | Table | Columns | Filters |
|---|---|---|---|
| contacts | contacts | 8 | 3 |
| pipeline_records | pipeline_records | 8 | 5 |
| commission_entries | commission_entries | 8 | 4 |
| products | products | 7 | 4 |
| invoices | invoices | 10 | 5 |
| payments | payments | 7 | 5 |
| ownership_assignments | ownership_assignments | 6 | 4 |
| duplicate_matches | duplicate_matches | 7 | 3 |

---

## Catalog Behavior

- Returns all supported data sources with column/filter definitions
- Each column has: key, label (Arabic), type (text/number/money/date/datetime/status)
- Each filter has: key, label, type, allowed operators
- Serves as the whitelist — unknown columns/filters rejected

## Template Behavior

- Validated against catalog on create/update
- Invalid data source → 422
- Invalid column → 422 with specific error
- Invalid filter field → 422
- Visibility: workspace (admin-gated) or private
- Delete = soft deactivate (is_active = false)
- Sort by any allowed column, asc/desc

## Execution Behavior

- Applies workspace scope (WHERE workspace_id = ?)
- Sets RLS context (SET app.workspace_id)
- Only selects whitelisted columns
- Applies filters with safe operators (equals, not_equals, contains, greater_than, less_than, between, date_from, date_to)
- ILIKE for contains (case-insensitive)
- Default limit: 100, max: 500
- Creates report_run row on every execution (success or failure)
- Returns rows + summary

## Summary Output

- `row_count`: total rows returned
- `totals`: sum of money/number columns
- `status_counts`: grouped counts for status columns
- `generated_at`: ISO timestamp

## Access Rules

- Admin roles create/update/delete workspace templates
- All active members list/run templates
- Admin roles see all runs; normal members see own runs
- Private templates visible only to creator

---

## API Test Results (18/18)

| # | Test | Result |
|---|---|---|
| 1 | Register | ✅ |
| 2 | Create contact | ✅ |
| 3 | Pipeline + record (value=75000) | ✅ |
| 4 | Get catalog (8 sources) | ✅ |
| 5 | Catalog detail (8 cols) | ✅ |
| 6 | Create template | ✅ |
| 7 | Run template (rows=1, total=75000.00) | ✅ |
| 8 | List runs | ✅ |
| 9 | Create contacts template | ✅ |
| 10 | Run contacts report | ✅ |
| 11 | Ad-hoc report with filter | ✅ |
| 12 | Invalid data source → 422 | ✅ |
| 13 | Invalid column → 422 | ✅ |
| 14 | Invalid filter field → 422 | ✅ |
| 15 | Delete template (deactivate) | ✅ |
| 16 | List templates (filtered) | ✅ |
| 17 | Missing workspace → 400 | ✅ |
| 18 | Unauthenticated → 401 | ✅ |

---

## Frontend Files

### New Files (5)
| File | Purpose |
|---|---|
| `lib/core/api/report_models.dart` | 9 model classes |
| `lib/core/api/report_service.dart` | API service with 9 methods |
| `lib/features/reports/report_state.dart` | State: catalog, templates, execution, runs |
| `lib/features/reports/screens/report_templates_screen.dart` | Templates list + create dialog |
| `lib/features/reports/screens/report_results_screen.dart` | Results table with summary |
| `lib/features/reports/screens/report_runs_screen.dart` | Run history list |

### Modified Files (4)
| File | Change |
|---|---|
| `lib/main.dart` | +2 imports, +1 provider (ReportState) |
| `lib/app/router.dart` | +3 deferred imports, +3 routes |
| `lib/core/l10n/strings_ar.dart` | +40 Arabic keys |
| `lib/core/l10n/strings_en.dart` | +40 English keys |

### Flutter Analyze
```
0 errors, 0 warnings, 0 issues
```

---

## Frontend Routes
```
/reports/templates  → ReportTemplatesScreen
/reports/results    → ReportResultsScreen
/reports/runs       → ReportRunsScreen
```

---

## Arabic/RTL Status

- 40 new keys with Arabic translations
- All UI text uses `tr(context, key)` — no hardcoded English
- RTL layout inherited from app-level config
- Data source labels in catalog are Arabic

---

## Remaining Gaps

1. **No charts** — Step 56 is data tables only (by design)
2. **No PDF/Excel export** — Deferred to future step
3. **No deep finance reports** — Step 57 scope
4. **No group_by execution** — Template stores group_by but execution doesn't aggregate (deferred)
5. **No scheduled/automated reports** — Manual execution only
6. **Sidebar entries not added** — Routes exist, sidebar not wired
7. **Filter UI in create dialog** — Basic create dialog doesn't expose filter builder (filters added via API)
8. **Private template creation** — Admin-gated; normal members can't create private templates in v1

---

## Step 57 Readiness

✅ **Safe to start Step 57.** Report templates infrastructure is complete with verified API (18/18), 8 data sources, clean frontend (0 issues), and proper separation from existing business logic.
