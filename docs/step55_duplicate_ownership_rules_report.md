# Step 55 — Duplicate / Ownership Rules

**Status:** ✅ Complete  
**Date:** 2026-07-08

---

## Summary

Added duplicate detection and ownership assignment foundation to SmartBiz AI: configurable duplicate rules for contacts and pipeline records, ownership assignment with transfer logs, ownership resolution with pipeline fallback, and duplicate match resolution workflow. Arabic-first UI with full localization.

---

## Migration

**File:** `database/migrations/031_duplicate_ownership_rules.php`

| Table | Purpose |
|---|---|
| `ownership_assignments` | One active owner per entity (contact/pipeline_record) |
| `ownership_transfer_logs` | History of ownership transfers |
| `duplicate_rules` | Configurable matching rules per entity type |
| `duplicate_matches` | Detected duplicate pairs with resolution status |

Key constraints:
- `ownership_ws_entity_unique`: workspace + entity_type + entity_id (one owner)
- `dup_rules_ws_type_name_unique`: workspace + entity_type + name
- `dup_match_unique`: workspace + entity_type + source + matched + rule (no duplicate-duplicates)

---

## Backend Files

### New Files (9)
| File | Purpose |
|---|---|
| `database/migrations/031_duplicate_ownership_rules.php` | 4 tables |
| `app/Models/OwnershipAssignment.php` | Owner, team, department, assignedBy relations |
| `app/Models/OwnershipTransferLog.php` | From/to membership, assignment relations |
| `app/Models/DuplicateRule.php` | Match fields JSON cast, matches relation |
| `app/Models/DuplicateMatch.php` | Rule, resolvedBy relations |
| `app/Services/OwnershipService.php` | Assign, transfer, resolve (with pipeline fallback) |
| `app/Services/DuplicateDetectionService.php` | Rule-based matching, normalization, match creation |
| `app/Http/Controllers/Api/OwnershipController.php` | List, create, show, transfer, resolve |
| `app/Http/Controllers/Api/DuplicateRuleController.php` | CRUD with soft-deactivate |
| `app/Http/Controllers/Api/DuplicateMatchController.php` | Check, list, resolve |

### Modified Files (1)
| File | Change |
|---|---|
| `routes/api.php` | +3 use statements, +13 new routes |

### Endpoints (13 routes)

**Ownership:**
```
GET    /api/ownership-assignments
POST   /api/ownership-assignments
GET    /api/ownership-assignments/{id}
PUT    /api/ownership-assignments/{id}/transfer
GET    /api/ownership/resolve?entity_type=...&entity_id=...
```

**Duplicate Rules:**
```
GET    /api/duplicate-rules
POST   /api/duplicate-rules
GET    /api/duplicate-rules/{id}
PUT    /api/duplicate-rules/{id}
DELETE /api/duplicate-rules/{id}
```

**Duplicate Checks & Matches:**
```
POST   /api/duplicates/check
GET    /api/duplicate-matches
POST   /api/duplicate-matches/{id}/resolve
```

---

## Ownership Behavior

- One active owner per entity per workspace (unique constraint)
- Owner assignment auto-fills team_id/department_id from membership
- Transfer updates owner and creates transfer log
- Resolve endpoint returns explicit assignment OR pipeline fallback (assigned_membership_id)
- Admin-gated writes (owner/admin/general_manager/manager)
- Duplicate assignment returns 409

## Duplicate Rule Behavior

- Rules are per workspace + entity type
- Match fields: any existing contact/pipeline_record column
- Match strategies: exact, normalized_exact (trim + lowercase + phone normalization)
- Actions: warn (return matches), block (controller may reject)
- Delete = soft deactivate (is_active = false)
- Phone normalization removes spaces, dashes, brackets, plus signs

## Duplicate Check Behavior

- Finds all active rules for entity_type
- Compares payload against all existing entities in workspace
- Creates DuplicateMatch records only when `exclude_entity_id` provided
- Returns `{blocked: bool, matches: [...]}`
- RLS-aware: sets `app.workspace_id` session variable for PostgreSQL policies

## Duplicate Match Resolution

- Statuses: open → resolved, open → ignored
- Resolutions: keep_separate, duplicate_confirmed, merged_later
- Admin-gated resolution
- No automatic merging (by design for Step 55)

---

## API Test Results (20/20)

| # | Test | Result |
|---|---|---|
| 1 | Register owner | ✅ |
| 2 | Create contact | ✅ |
| 3 | Create dup rule (phone) | ✅ |
| 4 | Dup check same phone (normalized) | ✅ |
| 4b | Create second contact (same phone) | ✅ |
| 4c | Dup check with exclude (creates match) | ✅ |
| 5 | Dup check different phone → 0 | ✅ |
| 6 | Assign owner to contact | ✅ |
| 7 | Duplicate assign → 409 | ✅ |
| 8 | Resolve owner (ownership_assignment) | ✅ |
| 9 | Create pipeline + record | ✅ |
| 10 | Resolve owner fallback (assigned_membership) | ✅ |
| 11 | Create dup rule (title) | ✅ |
| 12 | Dup check pipeline record → match | ✅ |
| 13 | List matches → count ≥ 1 | ✅ |
| 14 | Resolve match (keep_separate) | ✅ |
| 15 | List rules → 2 | ✅ |
| 16 | Delete rule (deactivate) | ✅ |
| 17 | Missing workspace → 400 | ✅ |
| 18 | Unauthenticated → 401 | ✅ |

---

## Frontend Files

### New Files (9)
| File | Purpose |
|---|---|
| `lib/core/api/ownership_models.dart` | OwnershipAssignment, payloads, resolve result |
| `lib/core/api/duplicate_models.dart` | DuplicateRule, DuplicateMatch, payloads, check result |
| `lib/core/api/ownership_service.dart` | API service for ownership endpoints |
| `lib/core/api/duplicate_service.dart` | API service for duplicate endpoints |
| `lib/features/ownership/ownership_state.dart` | State: assignments, create, transfer, resolve |
| `lib/features/duplicates/duplicate_state.dart` | State: rules, matches, check, resolve |
| `lib/features/duplicates/screens/duplicate_rules_screen.dart` | Rules list + create dialog |
| `lib/features/duplicates/screens/duplicate_matches_screen.dart` | Matches list + resolve actions |
| `lib/features/ownership/screens/ownership_screen.dart` | Assignments list + assign/transfer dialogs |

### Modified Files (5)
| File | Change |
|---|---|
| `lib/main.dart` | +4 imports, +2 providers (OwnershipState, DuplicateState) |
| `lib/app/router.dart` | +3 deferred imports, +3 routes |
| `lib/features/pipelines/screens/pipelines_screen.dart` | +3 imports, +2 menu items (Check Duplicate, Resolve Owner), +2 methods |
| `lib/core/l10n/strings_ar.dart` | +38 Arabic keys |
| `lib/core/l10n/strings_en.dart` | +38 English keys |

### Flutter Analyze
```
0 errors, 0 warnings, 0 issues
```

---

## Frontend Routes
```
/duplicates/rules     → DuplicateRulesScreen
/duplicates/matches   → DuplicateMatchesScreen
/ownership            → OwnershipScreen
```

---

## Pipeline Integration

- Record card popup menu now has **"Check Duplicate"** and **"Resolve Owner"** actions
- Check Duplicate: runs title match against all pipeline records, shows snackbar with count
- Resolve Owner: resolves ownership (explicit or fallback), shows snackbar with owner name + source

---

## Commission Integration

- No changes to CommissionCalculationService (per spec)
- Commission remains based on pipeline record assigned_membership_id
- Ownership assignment can be used by users to clarify disputes
- Future: commission could use ownership owner as fallback

---

## Arabic/RTL Status

- 38 new keys with Arabic translations in strings_ar.dart
- Default locale remains `ar`
- All UI text uses `tr(context, key)` — no hardcoded English
- RTL layout inherited from app-level config

---

## RLS Compatibility

- DuplicateDetectionService sets `SET app.workspace_id` before querying contacts/pipeline_records
- Handles PostgreSQL RLS policies transparently
- Wrapped in try-catch for non-RLS environments

---

## Browser Smoke Check

- Deferred to user testing (DDC/bootstrap limitation documented)
- Routes registered and analyze clean

---

## Remaining Gaps

1. **Contact screen integration** — Duplicate check not integrated into contact create/update (kept separate endpoint for safety)
2. **Auto-duplicate check on create** — Not wired into contact/record controllers (separate endpoint is v1)
3. **Block enforcement** — Duplicate check returns `blocked: true` but controllers don't reject (deferred)
4. **Employee picker** — Ownership assign/transfer uses UUID input (no membership picker in v1)
5. **Merge UI** — No merge capability (by design, deferred)
6. **Sidebar navigation** — Routes exist but sidebar entries not added
7. **Approval workflow** — Transfers are instant, no approval (deferred to Step 60)
8. **AI duplicate detection** — Not implemented (deferred)

---

## Step 56 Readiness

✅ **Safe to start Step 56.** Duplicate/ownership infrastructure is complete with verified API (20/20), clean frontend (0 issues), RLS-compatible services, and proper separation from commission/finance layers.
