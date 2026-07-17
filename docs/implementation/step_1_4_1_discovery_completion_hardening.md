# Step 1.4.1 — Discovery Completion Hardening

> Completed: 2026-07-16
> Status: ✅ All verifications passed

---

## 1. Previous Readiness Problem

In Task 1.4, a service company was marked `ready_for_blueprint=true` at only **34% completeness** after providing only:

- Business identity (digital marketing agency)
- Scale (8 employees)
- Geography (Dubai, AED)

The system had no knowledge of:

- Services offered
- Customer types
- Billing model
- Payment methods
- Team structure
- Approval needs

This would produce a generic, unreliable ERP blueprint.

## 2. Root Cause

Three interacting weaknesses:

| Issue | Location | Detail |
|-------|----------|--------|
| **Weak minimum requirements** | `DiscoveryInformationCatalog::MINIMUM_REQUIRED` | Only required `business_identity`, `scale`, `products_services` — geography, finance, team structure were optional |
| **Shallow coverage check** | `coveredCategories()` | Any non-null value counted as "covered" — empty arrays, "unknown", "normally" all passed |
| **Business-type agnostic** | `meetsMinimumRequirements()` | Same 3-category check for all business types — service companies need customers, finance, and team but these weren't required |

Additionally:

- The LLM's `ready_for_blueprint=true` suggestion was trusted without sufficient backend validation.
- Conflicting facts without explicit correction language could silently overwrite the previous value.

## 3. Files Inspected

| File | Purpose |
|------|---------|
| `app/Services/Discovery/DiscoveryAnalyzer.php` | Conversation analyzer — needed hardening |
| `app/Services/Discovery/DiscoveryInformationCatalog.php` | Category catalog — unchanged, evaluator reads it |
| `app/Services/DiscoverySessionService.php` | Session service — state structure update |
| `app/Models/DiscoverySession.php` | Model — no changes needed |
| `app/Http/Resources/DiscoverySessionResource.php` | Resource — added review fields |
| `database/migrations/039_discovery_state.php` | Migration — no changes needed |

## 4. Files Created

| File | Purpose |
|------|---------|
| `app/Services/Discovery/DiscoveryReadinessEvaluator.php` | Centralized readiness evaluator |

## 5. Files Modified

| File | Change |
|------|--------|
| `app/Services/Discovery/DiscoveryAnalyzer.php` | Delegates readiness to evaluator; contradiction detection; silent-overwrite prevention |
| `app/Services/DiscoverySessionService.php` | Extended state structure (1.4.1); backward compatibility; improved duplicate protection |
| `app/Http/Resources/DiscoverySessionResource.php` | Added `critical_missing` and `has_blocking_contradictions` |

## 6. New Readiness Architecture

```
  ┌─────────────────────────┐
  │   DiscoveryAnalyzer     │  ← LLM + deterministic fact extraction
  │   (fact extraction)     │
  └────────┬────────────────┘
           │ merged facts
           ▼
  ┌─────────────────────────────────┐
  │   DiscoveryReadinessEvaluator   │  ← Single readiness authority
  │                                 │
  │   ┌─────────────────────┐       │
  │   │  Business Profile   │       │  ← Type-specific requirements
  │   │  (retail/service/…) │       │
  │   └─────────────────────┘       │
  │                                 │
  │   ┌─────────────────────┐       │
  │   │  Fact Depth Check   │       │  ← Validates value quality
  │   │  (hasMeaningfulFact)│       │
  │   └─────────────────────┘       │
  │                                 │
  │   ┌─────────────────────┐       │
  │   │  Contradiction      │       │  ← Detects/blocks conflicts
  │   │  Detection          │       │
  │   └─────────────────────┘       │
  │                                 │
  │   Result: ready_for_blueprint   │
  └─────────────────────────────────┘
```

The evaluator is the **only** place where `ready_for_blueprint` is decided. The LLM's opinion is a suggestion that must pass deterministic checks.

## 7. Required and Dynamic Readiness Groups

### Required for Every Business

| Group | Required Facts |
|-------|---------------|
| business_identity | Business activity, type hint |
| scale | Employee count, branch count, or company size |
| products_services | What the company sells or provides |
| geography | Country, currency |
| finance | Payment methods, invoicing, or accounting |

### Business-Type-Specific Critical Groups

| Business Type | Critical Groups | Important Groups |
|---------------|----------------|-----------------|
| **retail** | identity, scale, products, sales_channels, finance, geography | customers, inventory, team |
| **restaurant** | identity, scale, products, sales_channels, finance, geography | customers, inventory, team |
| **service** | identity, scale, products, **customers**, finance, geography, **team_structure** | approvals |
| **manufacturing** | identity, scale, products, **production**, **inventory**, **suppliers**, finance, geography | sales_channels, team, delivery |
| **distribution** | identity, scale, products, sales_channels, **inventory**, **suppliers**, finance, geography | customers, delivery, team |
| **hybrid** | identity, scale, products, sales_channels, finance, geography | customers, inventory, team |

Key differences from Task 1.4:

- Service companies now require **customers** and **team_structure** (7 critical groups vs. 3)
- Manufacturing requires **production**, **inventory**, **suppliers** (8 critical groups)
- Distribution requires **inventory**, **suppliers** (8 critical groups)

## 8. Completeness Calculation

```
required_completeness = (critical_groups_covered / total_critical_groups) × 100
overall_completeness  = (all_covered_groups / all_relevant_groups) × 100
```

### Readiness Decision

```
ready_for_blueprint = ALL of:
  ✓ No critical groups missing
  ✓ No blocking contradictions
  ✓ required_completeness ≥ 70%
  ✓ overall_completeness ≥ 60%
```

## 9. Fact Depth Validation

| Value | Meaningful? | Reason |
|-------|-------------|--------|
| `null` | ❌ | Missing |
| `[]` (empty array) | ❌ | No data |
| `""` (empty string) | ❌ | No data |
| `"unknown"`, `"n/a"`, `"tbd"` | ❌ | Generic non-answer |
| `"normal"`, `"normally"`, `"the usual"` | ❌ | Vague non-answer |
| `"ok"` (short description field) | ❌ | Too short for descriptive fields |
| `0` (numeric) | ✅ | Confirmed zero |
| `false` (boolean) | ✅ | Confirmed negative |
| `true` (boolean) | ✅ | Confirmed positive |
| `["cash"]` (non-empty array) | ✅ | Specific value |
| `"Digital marketing"` (descriptive) | ✅ | Meaningful content |

## 10. Explicit Unknown and Assumption Handling

The discovery state now supports:

```json
{
  "explicitly_unknown": ["employee_count"],
  "assumptions": [
    {
      "field": "timezone",
      "value": "Asia/Dubai",
      "reason": "Inferred from country UAE",
      "requires_review": true
    }
  ]
}
```

- Explicitly unknown optional items do not block readiness
- Explicitly unknown critical items remain blocking
- Assumptions are visible in the state for future review

## 11. Contradiction Detection and Resolution

### Detection

```
On every answer:
  1. Compare existing confirmed facts with newly extracted facts
  2. For comparable keys (counts, country, currency, etc.):
     - If values differ AND text contains correction language → auto-resolve
     - If values differ WITHOUT correction language → create contradiction
```

### Correction Patterns

`correction`, `actually`, `i meant`, `change that`, `sorry, it is`, `no, we have`, `let me correct`, `update that`

### Contradiction States

| Status | Behavior |
|--------|----------|
| `needs_clarification` | Blocks readiness, generates clarification question |
| (resolved/removed) | No longer in contradictions array |

### Resolution Flow

```
Contradiction detected → fact reverted to original value →
  → clarification question generated →
    → user confirms correct value →
      → contradiction removed → fact updated
```

## 12. Question-Priority Behavior

```
1. Blocking contradictions → clarification question
2. Critical missing groups → highest priority first
3. Important missing groups → highest priority first
4. Optional missing groups → only if meaningful
```

A category asked but not meaningfully covered can be re-asked with a different question.

## 13. API Compatibility

### Endpoints Unchanged

All 7 discovery endpoints unchanged. All provisioning endpoints unchanged.

### Response Additions

```json
{
  "completeness": 70,
  "ready_for_blueprint": false,
  "critical_missing": ["finance", "team_structure"],
  "has_blocking_contradictions": false
}
```

### Backward Compatibility

- `completeness` field now maps to `overall_completeness` (was `completeness`)
- Old 1.4.0 states get safe defaults for new fields via `normalizeState()`
- Old sessions are automatically re-evaluated when accessed

## 14. Verification Scenarios and Results

### Scenario 1 — Detailed Automotive Company

| Metric | Result |
|--------|--------|
| Messages | 2 (description + ready) |
| Completeness | 86% |
| Required completeness | 100% |
| Critical missing | None |
| Contradictions | None |
| Ready immediately | ✅ |

### Scenario 2 — Minimal Restaurant

| Round | Completeness | Ready | Critical Missing | Question Topic |
|-------|-------------|-------|-----------------|----------------|
| Start | 15% | ❌ | scale, products_services, sales_channels, finance | Scale |
| Scale answer | 23% | ❌ | products_services, sales_channels, finance | Products |
| Products answer | 38% | ❌ | finance | Finance |
| Finance answer | 46% | ❌ | (none — asking important groups) | Customers |
| Team answer | 62% | ✅ | None | Ready |

No manufacturing, warehouse logistics, or irrelevant questions asked.

### Scenario 3 — Minimal Service Company

| Round | Completeness | Ready | Critical Missing | Question Topic |
|-------|-------------|-------|-----------------|----------------|
| Start | 20% | ❌ | products_services, customers, finance, geography, team_structure | Identity |
| Identity+geography | 30% | ❌ | products_services, customers, finance, team_structure | Services |
| Services | 40% | ❌ | customers, finance, team_structure | Customers |
| Customers | 50% | ❌ | finance, team_structure | Finance |
| Finance | 70% | ❌ | team_structure | Team |
| Team | 90% | ✅ | None | Ready |

**Key fix confirmed**: In Task 1.4, this session was ready at 34% after only 2 answers. Now it requires 6 rounds covering all 7 critical groups for service companies.

### Scenario 4 — Explicit Correction

| Metric | Before | After |
|--------|--------|-------|
| branch_count | 3 | 2 |
| employee_count | 30 | 20 |
| Contradictions | 0 | 0 (auto-resolved) |

### Scenario 5 — Unclear Contradiction

| Metric | Result |
|--------|--------|
| Contradiction detected | ✅ (branch_count: 3 → 2) |
| Status | `needs_clarification` |
| Original value preserved | ✅ (branch_count stays 3) |
| Readiness blocked | ✅ |
| Clarification question | "You previously mentioned 3 for the number of branches, but now mentioned 2. Which is correct?" |

### Scenario 6 — Weak Answer / Fact Depth

| Value | hasMeaningfulFact | Correct? |
|-------|-------------------|----------|
| `payment_methods: []` | false | ✅ |
| `payment_methods: ["cash"]` | true | ✅ |
| `employee_count: null` | false | ✅ |
| `employee_count: 0` | true | ✅ |
| `business_name: "unknown"` | false | ✅ |
| `business_description: "normally"` | false | ✅ |
| `business_description: "ok"` | false | ✅ |
| `uses_inventory: false` | true | ✅ |
| `business_name: "the usual"` | false | ✅ |

### Additional Verifications

| Test | Result |
|------|--------|
| LLM fallback (null LlmService) | ✅ deterministic, 8% completeness, 5 critical missing |
| Old 1.4.0 state compatibility | ✅ safe defaults applied, re-evaluated as not ready |
| Session reload preserves state | ✅ contradictions, missing groups, completeness persisted |
| Completed session rejects answers | ✅ 422 returned |
| Cross-workspace access blocked | ✅ 403 returned |
| Permission denied (viewer) | ✅ 403 "Permission denied: discovery.manage" |
| Unauthenticated | ✅ 401 "Unauthenticated" |
| Demo reset | ✅ 181 tables truncated, 0 skipped, seeded |
| Business template routes | ✅ 5 templates |
| No Flutter files changed | ✅ |
| No provisioning files changed | ✅ |

## 15. Remaining Limitations

| Limitation | Notes |
|-----------|-------|
| Contradiction detection only covers comparable keys | Lists and booleans not compared |
| Assumptions not yet generated by analyzer | Structure exists but not populated |
| Explicitly unknown not yet extracted by LLM | Prompt doesn't ask for it |
| Weak answer re-asking depends on LLM generating a different question | Deterministic fallback reuses same question text |
| Blueprint generation unchanged | Still uses rule-based templates |
| No streaming for real-time updates | Standard request-response |

## 16. Exact Recommended Scope for Task 1.5

### Task 1.5 — Blueprint Review & Provisioning Foundation

1. **Wire `ProvisioningService::preview()`** to blueprint → show what would be created
2. **Wire `ProvisioningService::apply()`** to blueprint → provision the workspace
3. **Set onboarding complete** after successful provisioning
4. **Use discovery_state.known_facts** to enrich blueprint content
5. **Do not yet** unify with BusinessTemplateApplicationService
6. **Do not yet** modify Flutter
7. **Do not yet** implement blueprint editing
8. **Do not yet** create actual resources (departments, roles, warehouses)

## 17. Exact Files Expected to Change in Task 1.5

| File | Expected Change |
|------|----------------|
| `app/Http/Controllers/Api/ProvisioningController.php` | Wire blueprint ID to preview/apply |
| `app/Services/ProvisioningService.php` | Implement preview() and apply() |
| `app/Models/ProvisioningRun.php` | Verify model matches service needs |
| `app/Models/WorkspaceConfiguration.php` | Verify model matches service needs |
| `app/Services/BlueprintGeneratorService.php` | Optional: use known_facts for richer output |
| `routes/api.php` | Optional: add provisioning routes |
