# Step 54 — Commission Rules

**Status:** ✅ Complete
**Date:** 2026-07-08

---

## Summary

Added a commission rules foundation to SmartBiz AI: Commission Plans, Commission Rules, Commission Calculation Service, Commission Entries with status lifecycle (pending → approved → paid / cancelled), percentage and fixed-amount calculation, employee/manager/team/department targeting, duplicate prevention, and full Arabic-first UI.

---

## Migration

**File:** `database/migrations/030_commission_rules.php`

| Table | Purpose |
|---|---|
| `commission_plans` | Named plans scoped to workspace (e.g., "Vehicle Sales Commission") |
| `commission_rules` | Rules with target type, calculation type, percentage/fixed, trigger status, pipeline/stage/role/dept/team filters |
| `commission_entries` | Calculated entries per record+rule+recipient with status lifecycle |

Unique constraint: `commission_rule_id + pipeline_record_id + recipient_membership_id` prevents duplicate entries.

---

## Backend Files

### New Files (8)
| File | Purpose |
|---|---|
| `database/migrations/030_commission_rules.php` | Migration for 3 tables |
| `app/Models/CommissionPlan.php` | Plan model with workspace + rules relationships |
| `app/Models/CommissionRule.php` | Rule model with plan, pipeline, stage, role, department, team relationships |
| `app/Models/CommissionEntry.php` | Entry model with plan, rule, record, recipient, source relationships |
| `app/Services/CommissionCalculationService.php` | Calculation engine with matching, recipient resolution, duplicate prevention |
| `app/Http/Controllers/Api/CommissionPlanController.php` | Plan CRUD controller |
| `app/Http/Controllers/Api/CommissionRuleController.php` | Rule CRUD controller |
| `app/Http/Controllers/Api/CommissionEntryController.php` | Entry list, calculate, approve, pay, cancel controller |

### Modified Files (1)
| File | Change |
|---|---|
| `routes/api.php` | +3 use statements, +16 new routes |

### Endpoints (16 routes)

**Commission Plans:**
```
GET    /api/commission-plans
POST   /api/commission-plans
GET    /api/commission-plans/{id}
PUT    /api/commission-plans/{id}
DELETE /api/commission-plans/{id}
```

**Commission Rules:**
```
GET    /api/commission-rules
POST   /api/commission-rules
GET    /api/commission-rules/{id}
PUT    /api/commission-rules/{id}
DELETE /api/commission-rules/{id}
```

**Commission Entries:**
```
GET    /api/commission-entries
GET    /api/commission-entries/{id}
POST   /api/commission-entries/{id}/mark-approved
POST   /api/commission-entries/{id}/mark-paid
POST   /api/commission-entries/{id}/cancel
POST   /api/pipeline-records/{recordId}/calculate-commissions
```

---

## Commission Plan Behavior

- CRUD scoped to workspace
- `plan_key` auto-generated from name slug
- Unique: workspace_id + name
- Delete = soft deactivate (`is_active = false`)
- Admin-gated writes (owner/admin/general_manager/manager)

## Commission Rule Behavior

- Linked to plan (required), pipeline/stage/role/department/team (all optional)
- `target_type`: assigned_employee, direct_manager, team_manager, department_manager
- `calculation_type`: percentage (requires percentage_rate), fixed_amount (requires fixed_amount)
- `trigger_status`: won, completed, open
- `min_record_value` / `max_record_value` range filters
- Validates plan/pipeline/stage belong to workspace
- Validates percentage_rate required for percentage, fixed_amount required for fixed_amount
- Delete = soft deactivate

## Commission Calculation Behavior

`POST /api/pipeline-records/{recordId}/calculate-commissions`

1. Finds active rules in active plans for the workspace
2. Rule matches if: pipeline matches (or null), stage matches (or null), trigger status matches record status
3. Value range check: record.value_amount within min/max bounds
4. Role/department/team filter check against assigned membership
5. Recipient resolution: assigned_employee → assigned_membership_id, direct_manager → manager_membership_id, team_manager → team.manager_membership_id, department_manager → department.manager_membership_id
6. Duplicate check: unique(rule_id, record_id, recipient_id)
7. Calculation: percentage = base_amount × rate / 100, fixed = fixed_amount
8. Currency: record.currency ?? rule.currency ?? 'LYD'
9. Created entries default to status = 'pending'

## Commission Entry Status Behavior

| Transition | Allowed |
|---|---|
| pending → approved | ✅ |
| pending → paid | ✅ |
| approved → paid | ✅ |
| pending/approved → cancelled | ✅ |
| paid → cancelled | ❌ (409) |
| paid → anything | ❌ (409) |

---

## API Test Results (19/19)

| # | Test | Result |
|---|---|---|
| 1 | Register owner | ✅ |
| 2 | Create pipeline | ✅ |
| 3 | Create open stage | ✅ |
| 4 | Create won stage | ✅ |
| 5 | Create record (assigned, value=100000) | ✅ |
| 6 | Move to won | ✅ |
| 7 | Create commission plan | ✅ |
| 8 | Create percentage rule (1.5%) | ✅ |
| 9 | Calculate → 1 entry, 1500.00 LYD | ✅ |
| 10 | Calculate again → 0 new (no duplicates) | ✅ |
| 11 | List entries | ✅ |
| 12 | Mark approved | ✅ |
| 13 | Mark paid | ✅ |
| 14 | Cancel paid → 409 | ✅ |
| 15 | Create fixed amount rule (500 LYD) | ✅ |
| 16 | Calculate fixed → 500.00 | ✅ |
| 17 | Missing workspace → 400 | ✅ |
| 18 | Unauthenticated → 401 | ✅ |
| 19 | Verify math (1.5% × 100000 = 1500) | ✅ |

---

## Frontend Files

### New Files (5)
| File | Purpose |
|---|---|
| `lib/core/api/commission_models.dart` | CommissionPlan, CommissionRule, CommissionEntry, payloads, constants |
| `lib/core/api/commission_service.dart` | API service for all commission endpoints |
| `lib/features/commissions/commission_state.dart` | State management with plans, rules, entries, CRUD, status transitions |
| `lib/features/commissions/screens/commission_settings_screen.dart` | Plans + rules settings screen |
| `lib/features/commissions/screens/commission_entries_screen.dart` | Entries list with status filter, approve/pay/cancel actions |

### Modified Files (4)
| File | Change |
|---|---|
| `lib/main.dart` | Added CommissionService + CommissionState provider |
| `lib/app/router.dart` | Added `/commissions/settings` + `/commissions` routes |
| `lib/features/pipelines/screens/pipelines_screen.dart` | Added "Calculate Commission" action to record card popup menu |
| `lib/core/l10n/strings_ar.dart` | 35 new Arabic keys |
| `lib/core/l10n/strings_en.dart` | 35 matching English keys |

### Flutter Analyze
```
0 errors, 0 warnings, 0 issues
```

---

## Pipeline Integration

- Record card popup menu now has **"Calculate Commission"** action
- Triggers `POST /pipeline-records/{id}/calculate-commissions`
- Shows snackbar with created entry count
- Does NOT auto-calculate on record move (manual only for Step 54)

---

## Arabic/RTL Status

- All 35 new keys have Arabic translations
- Default locale remains `ar`
- All UI text uses `tr(context, key)` — no hardcoded English
- RTL layout inherited from app-level config

---

## Remaining Gaps

1. **Finance integration** — Commission payment does NOT create journal entries or payroll records (deferred to Step 57)
2. **Approval workflow** — Simple status transitions only; full approval workflow deferred to Step 60
3. **Auto-calculation** — Commissions are calculated manually via button; auto-trigger on pipeline move deferred
4. **Sidebar navigation** — Commission routes exist but sidebar entry not yet added
5. **Manager resolution** — Requires membership to have `manager_membership_id`, `team_id`, or `department_id` set to resolve manager targets
6. **Paid reversal** — Paid entries cannot be cancelled (by design); no void/reversal mechanism yet

---

## Step 55 Readiness

✅ **Safe to start Step 55.** Commission rules infrastructure is complete with verified API (19/19), clean frontend (0 issues), and proper separation from finance/approval layers.
