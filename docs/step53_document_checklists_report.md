# Step 53 — Document Checklists

**Status:** ✅ Complete
**Date:** 2026-07-08

---

## Summary

Added a document checklist foundation to SmartBiz AI: Document Checklists, Checklist Items, Record Documents, Document Status aggregation, file upload support, and manual/external document reference — with full Arabic-first UI.

---

## Migration

**File:** `database/migrations/029_document_checklists.php`

| Table | Purpose |
|---|---|
| `document_checklists` | Checklist definitions scoped to workspace, pipeline, and/or stage |
| `document_checklist_items` | Required/optional document items within a checklist |
| `record_documents` | Uploaded/provided documents per pipeline record |

---

## Backend Files

### Models Created
| Model | Location |
|---|---|
| `DocumentChecklist` | `app/Models/DocumentChecklist.php` |
| `DocumentChecklistItem` | `app/Models/DocumentChecklistItem.php` |
| `RecordDocument` | `app/Models/RecordDocument.php` |

### Controllers Created
| Controller | Location |
|---|---|
| `DocumentChecklistController` | `app/Http/Controllers/Api/DocumentChecklistController.php` |
| `DocumentChecklistItemController` | `app/Http/Controllers/Api/DocumentChecklistItemController.php` |
| `RecordDocumentController` | `app/Http/Controllers/Api/RecordDocumentController.php` |

### Endpoints (13 routes)

**Document Checklists:**
```
GET    /api/document-checklists
POST   /api/document-checklists
GET    /api/document-checklists/{id}
PUT    /api/document-checklists/{id}
DELETE /api/document-checklists/{id}
```

**Checklist Items:**
```
GET    /api/document-checklists/{checklistId}/items
POST   /api/document-checklists/{checklistId}/items
PUT    /api/document-checklist-items/{id}
DELETE /api/document-checklist-items/{id}
```

**Record Documents:**
```
GET    /api/pipeline-records/{recordId}/documents
POST   /api/pipeline-records/{recordId}/documents
GET    /api/pipeline-records/{recordId}/document-status
DELETE /api/record-documents/{id}
```

### Modified Files
| File | Change |
|---|---|
| `routes/api.php` | Added 13 new routes + 3 controller use statements |

---

## Behavior

### Document Checklists
- CRUD scoped to workspace
- Optional pipeline + stage linking
- Stage validated against pipeline when both present
- `checklist_key` auto-generated from name slug
- Delete = soft deactivate (`is_active = false`)
- Admin-gated writes (owner/admin/general_manager/manager)

### Checklist Items
- Nested under checklist
- Required/optional flag
- `accepted_file_types` as JSON array (e.g. `["pdf","jpg","png"]`)
- `max_file_size_mb` with default 10MB, max 50MB
- `item_key` auto-generated
- Soft deactivation on delete

### Record Documents
- Two modes: **file upload** and **manual/external reference**
- File upload validates extension against `accepted_file_types`
- File upload validates size against `max_file_size_mb`
- Manual mode supports `external_reference` and `notes`
- Status: `uploaded`, `provided`, `waived`
- Storage: `workspace-documents/{wsId}/pipeline-records/{recId}/...` (local disk)
- Uploaded-by membership tracked
- Admin-gated delete; any member can upload/provide

### Document Status
- Aggregates applicable checklists (pipeline-level, stage-level, global)
- Returns per-item status: missing, uploaded, provided, waived
- Counts: required, completed, missing, optional
- Missing warnings shown but **do NOT block** pipeline record movement

---

## API Test Results (17/17)

| # | Test | Result |
|---|---|---|
| 1 | Register owner | ✅ |
| 2 | Create pipeline | ✅ |
| 3 | Create stage | ✅ |
| 4 | Create pipeline record | ✅ |
| 5 | Create checklist (pipeline+stage) | ✅ |
| 6 | Create required checklist item | ✅ |
| 7 | Create optional checklist item | ✅ |
| 8 | Status before → missing=1 | ✅ |
| 9 | Provide manual document | ✅ |
| 10 | Status after → missing=0 | ✅ |
| 11 | List record documents | ✅ |
| 12 | Upload text file | ✅ |
| 13 | Invalid file type → 422 | ✅ |
| 14 | Missing workspace → 400 | ✅ |
| 15 | Unauthenticated → 401 | ✅ |
| 16 | List checklists | ✅ |
| 17 | Show checklist with items | ✅ |

---

## Frontend Files

### New Files
| File | Purpose |
|---|---|
| `lib/core/api/document_models.dart` | All models: DocumentChecklist, Item, RecordDocument, DocumentStatus, payloads |
| `lib/core/api/document_service.dart` | API service for all document endpoints |
| `lib/features/documents/document_state.dart` | State management with loading/error |
| `lib/features/documents/screens/document_checklists_screen.dart` | Checklist + items settings screen |
| `lib/features/documents/screens/record_documents_screen.dart` | Record document status + provide dialog |

### Modified Files
| File | Change |
|---|---|
| `lib/main.dart` | Added `DocumentService` + `DocumentState` provider |
| `lib/app/router.dart` | Added `/documents/checklists` + `/pipeline-records/:recordId/documents` routes |
| `lib/features/pipelines/screens/pipelines_screen.dart` | Added "Documents" action to record card popup menu |
| `lib/core/l10n/strings_ar.dart` | 32 new Arabic keys |
| `lib/core/l10n/strings_en.dart` | 32 matching English keys |

### Flutter Analyze
```
0 errors, 0 warnings, 0 issues
```

---

## Upload Support

| Mode | Status |
|---|---|
| Manual/External reference | ✅ Fully implemented |
| File upload (backend) | ✅ Fully implemented with validation |
| File upload (frontend) | ⚠️ Backend-only — no `file_picker` package in pubspec.yaml. Frontend supports manual reference mode. File picker UI deferred. |

---

## Arabic/RTL Status

- All 32 new keys have Arabic translations
- Default locale remains `ar`
- All UI text references use `tr(context, key)` — no hardcoded English
- RTL layout inherited from app-level config

---

## Remaining Gaps

1. **File picker UI** — No `file_picker` package. Frontend provides manual reference only. Add package when ready.
2. **Approval workflow** — Document approval/rejection deferred to Step 60.
3. **Blocking rules** — Missing documents do NOT block pipeline record movement (by design for Step 53).
4. **Sidebar navigation** — Document checklists route exists but sidebar entry not yet added.
5. **Employee permission test** — Admin-gated writes verified; employee read/upload tested indirectly.

---

## Step 54 Readiness

✅ **Safe to start Step 54.** Document checklist infrastructure is complete with verified API and clean frontend code.
