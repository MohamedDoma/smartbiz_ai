# Step 52 — Pipelines + Custom Fields

**Status:** ✅ Complete
**Date:** 2026-07-08

---

## Summary

Added a generic workflow engine foundation to SmartBiz AI: Pipelines, Pipeline Stages, Pipeline Records, Custom Fields, and Custom Field Values — with full Arabic-first UI.

---

## Migration

**File:** `database/migrations/028_pipelines_custom_fields.php`

| Table | Purpose |
|---|---|
| `pipelines` | Workflow definitions scoped to workspace |
| `pipeline_stages` | Ordered stages within a pipeline |
| `pipeline_records` | Individual items flowing through stages |
| `custom_fields` | Configurable field definitions per pipeline |
| `custom_field_values` | Polymorphic value storage for records |

---

## Backend Files

### Models Created
| Model | Location |
|---|---|
| `Pipeline` | `app/Models/Pipeline.php` |
| `PipelineStage` | `app/Models/PipelineStage.php` |
| `PipelineRecord` | `app/Models/PipelineRecord.php` |
| `CustomField` | `app/Models/CustomField.php` |
| `CustomFieldValue` | `app/Models/CustomFieldValue.php` |

### Controllers Created
| Controller | Location |
|---|---|
| `PipelineController` | `app/Http/Controllers/Api/PipelineController.php` |
| `PipelineStageController` | `app/Http/Controllers/Api/PipelineStageController.php` |
| `PipelineRecordController` | `app/Http/Controllers/Api/PipelineRecordController.php` |
| `CustomFieldController` | `app/Http/Controllers/Api/CustomFieldController.php` |

### Endpoints (20 routes)

**Pipelines:**
```
GET    /api/pipelines
POST   /api/pipelines
GET    /api/pipelines/{id}
PUT    /api/pipelines/{id}
DELETE /api/pipelines/{id}
```

**Stages:**
```
GET    /api/pipelines/{pipelineId}/stages
POST   /api/pipelines/{pipelineId}/stages
PUT    /api/pipeline-stages/{id}
DELETE /api/pipeline-stages/{id}
```

**Records:**
```
GET    /api/pipeline-records
POST   /api/pipeline-records
GET    /api/pipeline-records/{id}
PUT    /api/pipeline-records/{id}
POST   /api/pipeline-records/{id}/move
DELETE /api/pipeline-records/{id}
```

**Custom Fields:**
```
GET    /api/custom-fields
POST   /api/custom-fields
GET    /api/custom-fields/{id}
PUT    /api/custom-fields/{id}
DELETE /api/custom-fields/{id}
```

### Modified Files
| File | Change |
|---|---|
| `routes/api.php` | Added 20 new routes + 4 controller use statements |

---

## Behavior

### Pipelines
- CRUD scoped to workspace
- `pipeline_key` auto-generated from name slug
- Delete = soft deactivate (`is_active = false`)
- Admin-gated writes (owner/admin/general_manager/manager)

### Stages
- Nested under pipeline
- `status_type`: open, won, lost, completed, cancelled
- Soft deactivation on delete
- If stage has open records, deactivated instead of deleted

### Records
- Pipeline/stage ownership validated against workspace
- Contact and assigned membership validated against workspace
- Auto-close on move to won/lost/completed/cancelled stages
- Auto-reopen on move back to open stage
- `custom_values` validated against active custom fields
- Required field enforcement returns 422

### Custom Fields
- Scoped to pipeline or global (null pipeline_id)
- 8 field types: text, textarea, number, date, boolean, select, multi_select, currency
- Options required for select/multi_select
- `field_key` auto-generated from label
- Soft deactivation preserves existing values

---

## API Test Results (17/17)

| # | Test | Result |
|---|---|---|
| 1 | Register owner | ✅ |
| 2 | Create pipeline | ✅ |
| 3 | Create stage (Lead) | ✅ |
| 4 | Create stage (Negotiation) | ✅ |
| 5 | Create stage (Won) | ✅ |
| 6 | Create text custom field (required) | ✅ |
| 7 | Create select custom field | ✅ |
| 8 | Create record with custom values | ✅ |
| 9 | List records | ✅ |
| 10 | Move to Negotiation | ✅ |
| 11 | Move to Won (auto-close) | ✅ |
| 12 | Show with custom values | ✅ |
| 13 | Update custom values | ✅ |
| 14 | Required field missing → 422 | ✅ |
| 15 | Stage mismatch → 422 | ✅ |
| 16 | Missing workspace → 400 | ✅ |
| 17 | Unauthenticated → 401 | ✅ |

---

## Frontend Files

### New Files
| File | Purpose |
|---|---|
| `lib/core/api/pipeline_models.dart` | All models and payloads |
| `lib/core/api/pipeline_service.dart` | API client service |
| `lib/features/pipelines/pipeline_state.dart` | State management |
| `lib/features/pipelines/screens/pipelines_screen.dart` | Main screen with stage tabs |
| `lib/features/pipelines/screens/pipeline_settings_screen.dart` | Stages + custom fields management |

### Modified Files
| File | Change |
|---|---|
| `lib/main.dart` | Added `PipelineService` + `PipelineState` provider |
| `lib/app/router.dart` | Added `/pipelines` and `/pipelines/settings` routes |
| `lib/core/l10n/strings_ar.dart` | 35 new Arabic keys |
| `lib/core/l10n/strings_en.dart` | 35 matching English keys |

### Flutter Analyze
```
0 errors, 0 warnings, 0 issues
```

---

## Template Integration Status

Business template workflow/custom field tables (`business_template_workflows`, `business_template_custom_fields`) exist separately. Template→pipeline auto-creation is **deferred to a future step** — the system supports fully manual pipeline/custom field creation now. Template integration can be added later as a simple mapping in `BusinessTemplateApplicationService`.

---

## Browser Smoke Check

Flutter web compiled successfully. Headless browser test could not render (DDC bootstrap limitation in headless/WebGL-less environment). Code compiles cleanly and all backend endpoints verified.

---

## Arabic/RTL Status

- All 35 new keys have Arabic translations
- Default locale remains `ar` (from Step 50.6)
- All UI text references use `tr(context, key)` — no hardcoded English
- RTL layout inherited from app-level config

---

## Remaining Gaps

1. **Template auto-creation** — Business template workflows → auto-create pipelines when template is applied (deferred)
2. **Drag-and-drop Kanban** — Not implemented (simple tab + move action used instead)
3. **Record detail screen** — Only list/create/move implemented; dedicated detail view deferred
4. **Sidebar navigation link** — Pipeline route exists but sidebar entry not yet added (depends on blueprint navigation config)

---

## Step 53 Readiness

✅ **Safe to start Step 53.** All pipeline/custom field infrastructure is in place with verified API and clean frontend code.
