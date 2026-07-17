# Step 1.4 — Adaptive AI Discovery Conversation

> Completed: 2026-07-16
> Status: ✅ All verifications passed

---

## 1. Previous Behavior

| Aspect | Task 1.3 Behavior |
|--------|-------------------|
| Question generation | Rule-based, 8 fixed categories, max 4 per round |
| Fact extraction | None — raw text stored only |
| State tracking | None — session had no structured state |
| Completeness | Not measured |
| Readiness | Manual — user had to call classify then generate |
| Question relevance | Category-based keyword check only |
| Correction handling | Not supported |
| Duplicate protection | Category-based only |
| Business context | Not considered — all companies got same question set |

---

## 2. New Adaptive Conversation Flow

```
User sends initial description
  → LLM analyzes full text
  → Extracts 10-25 structured facts from rich descriptions
  → Validates keys against centralized catalog
  → Calculates completeness (0-100%)
  → Deterministic minimum check (business_identity + scale + products_services)
  → If ready: save "ready" message, no questions
  → If not ready: save ONE focused adaptive question

User answers question
  → LLM re-analyzes ENTIRE conversation (all messages)
  → Merges new facts with existing (corrections override)
  → Recalculates completeness
  → Checks duplicate protection
  → If ready: save "ready" message
  → If not ready: save next relevant question

When LLM fails at any step:
  → Deterministic keyword extraction runs
  → Keyword-based type inference
  → Catalog-based next question selection
  → Same completeness and readiness checks

When ready_for_blueprint=true:
  → User calls classify (LLM classification)
  → User calls generate-blueprint (existing template system)
```

---

## 3. Files Inspected

| File | Purpose |
|------|---------|
| `app/Services/DiscoverySessionService.php` | Main service — full rewrite target |
| `app/Services/BlueprintGeneratorService.php` | Rule-based classification and templates |
| `app/Services/Ai/LlmService.php` | LLM service wrapper |
| `app/Services/Ai/OpenAiProvider.php` | OpenAI API client |
| `app/Models/DiscoverySession.php` | Session model — needed discovery_state |
| `app/Models/DiscoveryMessage.php` | Message model |
| `app/Http/Controllers/Api/DiscoveryController.php` | Controller — no changes needed |
| `app/Http/Resources/DiscoverySessionResource.php` | Resource — added completeness/ready |
| `app/Http/Resources/DiscoveryMessageResource.php` | Message resource — no changes needed |
| `app/Http/Requests/StartDiscoveryRequest.php` | Validation — no changes needed |
| `app/Http/Requests/AnswerDiscoveryRequest.php` | Validation — no changes needed |
| `database/migrations/038_discovery_provisioning.php` | Original migration — reference |

---

## 4. Files Created

| File | Purpose |
|------|---------|
| `database/migrations/039_discovery_state.php` | Adds `discovery_state` JSONB + `ready` message type |
| `app/Services/Discovery/DiscoveryInformationCatalog.php` | Centralized information catalog |
| `app/Services/Discovery/DiscoveryAnalyzer.php` | LLM + deterministic conversation analyzer |

---

## 5. Files Modified

| File | Change |
|------|--------|
| `app/Models/DiscoverySession.php` | Added `discovery_state` to `$fillable` and `$casts` (as `array`) |
| `app/Services/DiscoverySessionService.php` | Rewired to use DiscoveryAnalyzer; adaptive startSession, submitAnswers; state persistence; duplicate protection; ready message |
| `app/Http/Resources/DiscoverySessionResource.php` | Added `completeness` and `ready_for_blueprint` fields |

---

## 6. Database Changes

### Migration 039: `discovery_state`

```sql
ALTER TABLE discovery_sessions
ADD COLUMN discovery_state JSONB DEFAULT NULL;

ALTER TABLE discovery_messages
DROP CONSTRAINT IF EXISTS discovery_messages_message_type_check;

ALTER TABLE discovery_messages
ADD CONSTRAINT discovery_messages_message_type_check
CHECK (message_type IN ('description', 'follow_up_question', 'answer', 'classification', 'blueprint', 'ready'));
```

---

## 7. Discovery State Structure

```json
{
  "known_facts": {
    "business_name": "Doma Auto Parts",
    "business_type_hint": "distribution",
    "branch_count": 2,
    "employee_count": 25,
    "sales_channels": ["counter POS", "wholesale orders"],
    "uses_inventory": true,
    "uses_pos": true,
    "warehouse_count": 2,
    "payment_methods": ["cash", "bank transfers"],
    "uses_invoicing": true,
    "uses_accounting": true,
    "uses_commissions": true,
    "needs_approvals": true,
    "has_suppliers": true,
    "customer_types": ["garages", "workshops"]
  },
  "business_type_hint": "distribution",
  "missing_categories": ["geography", "delivery"],
  "completeness": 79,
  "ready_for_blueprint": true,
  "asked_categories": ["geography"],
  "analysis_method": "llm",
  "version": "1.4.0"
}
```

### Known fact keys (validated by catalog)

| Category | Fact Keys |
|----------|-----------|
| business_identity | business_name, business_description, business_type_hint |
| geography | country, timezone, currency, primary_language |
| scale | employee_count, branch_count, company_size |
| products_services | sells_products, sells_services, product_types, product_count_range |
| sales_channels | sales_channels, uses_pos, uses_ecommerce, uses_wholesale |
| customers | customer_types, customer_count_range, uses_crm |
| inventory | uses_inventory, warehouse_count, inventory_complexity |
| suppliers | has_suppliers, supplier_count_range, purchase_process |
| production | uses_manufacturing, production_type, uses_bom |
| delivery | uses_delivery, delivery_model, fleet_owned |
| finance | payment_methods, uses_invoicing, uses_accounting, tax_requirements |
| expenses | tracks_expenses, has_recurring_expenses, needs_budgeting |
| team_structure | department_count, role_names, has_teams, needs_permissions |
| approvals | needs_approvals, approval_types |
| commissions | uses_commissions, commission_model |

---

## 8. Structured Fact Extraction Behavior

### LLM Analysis

- Receives full conversation transcript + existing facts
- System prompt lists all valid keys
- Returns JSON with `facts`, `business_type_hint`, `missing_categories`, `completeness`, `ready_for_blueprint`, `next_question`
- Response is validated: only valid keys accepted, completeness clamped 0-100
- Unknown keys silently ignored
- Corrections handled: latest value overwrites previous

### Deterministic Fallback

- Keyword matching against full conversation text
- Regex patterns for numeric facts (employee_count, branch_count)
- Boolean facts from keyword presence (uses_inventory, uses_delivery)
- Array facts aggregated (sales_channels, payment_methods)
- Business type inferred from keyword scoring

---

## 9. Dynamic Required-Information Logic

### Category Relevance by Business Type

| Category | retail | restaurant | service | manufacturing | distribution |
|----------|--------|------------|---------|---------------|-------------|
| business_identity | ✅ | ✅ | ✅ | ✅ | ✅ |
| geography | ✅ | ✅ | ✅ | ✅ | ✅ |
| scale | ✅ | ✅ | ✅ | ✅ | ✅ |
| products_services | ✅ | ✅ | ✅ | ✅ | ✅ |
| sales_channels | ✅ | ✅ | ❌ | ✅ | ✅ |
| customers | ✅ | ✅ | ✅ | ✅ | ✅ |
| inventory | ✅ | ✅ | ❌ | ✅ | ✅ |
| suppliers | ✅ | ✅ | ❌ | ✅ | ✅ |
| production | ❌ | ❌ | ❌ | ✅ | ❌ |
| delivery | ✅ | ✅ | ❌ | ❌ | ✅ |
| finance | ✅ | ✅ | ✅ | ✅ | ✅ |
| expenses | ✅ | ✅ | ✅ | ✅ | ✅ |
| team_structure | ✅ | ✅ | ✅ | ✅ | ✅ |
| approvals | ✅ | ✅ | ✅ | ✅ | ✅ |
| commissions | ✅ | ❌ | ✅ | ❌ | ✅ |

Service companies are NOT asked about: inventory, suppliers, sales_channels, production, delivery.

---

## 10. Next-Question Generation Logic

### Priority (highest asked first when missing)

1. **business_identity** (10) — Business name and activity
2. **scale** (8) — Employees and branches
3. **products_services** (7) — What they sell
4. **sales_channels** (7) — How they sell
5. **production** (7) — Manufacturing (only for manufacturing type)
6. **geography** (6) — Country, currency
7. **inventory** (6) — Stock tracking
8. **finance** (6) — Payments, invoicing
9. **team_structure** (5) — Roles, departments
10. **customers** (5) — Customer types
11. **suppliers** (4) — Purchasing
12. **delivery** (4) — Logistics
13. **approvals** (3) — Workflows
14. **expenses** (3) — Cost tracking
15. **commissions** (2) — Incentives

### Selection Algorithm

```
1. Get relevant categories for inferred business type
2. Sort by priority descending
3. Skip categories with known facts (covered)
4. Skip categories already asked
5. Skip categories matching existing AI questions (duplicate check)
6. Return first remaining category's question
```

---

## 11. Completion Gate

### Dual Check System

| Check | Type | Criteria |
|-------|------|----------|
| Minimum requirements | Deterministic | business_identity + scale + products_services covered |
| LLM readiness | LLM | Model estimates ready_for_blueprint |
| Completeness threshold | Hybrid | Average of LLM + catalog-based completeness ≥ 75% |
| No more questions | Deterministic | All relevant categories covered or asked |

### Decision Matrix

| Meets Minimum | LLM Says Ready | Completeness ≥ 75% | Decision |
|---------------|----------------|---------------------|----------|
| ❌ | ❌ | Any | Keep asking |
| ❌ | ✅ | Any | Keep asking |
| ✅ | ✅ | Any | Ready |
| ✅ | ❌ | ✅ | Ready |
| ✅ | ❌ | ❌ | Keep asking |

The LLM alone cannot decide completion — deterministic minimum requirements must always be met.

---

## 12. LLM Behavior

### Analysis Prompt Structure

```
System: Business discovery analysis engine.
- Lists ALL valid fact keys
- Lists categories and their keys
- Shows previously known facts
- Shows already-asked categories
- Rules: extract from ALL messages, handle corrections, validate types

User: Full conversation transcript
```

### Response Validation

- Parse JSON (handle markdown code blocks)
- Only accept valid fact keys (from catalog)
- Clamp completeness 0-100
- Average LLM completeness with catalog calculation
- Validate next_question category against catalog
- Reject duplicate question categories
- Fallback to deterministic question if LLM question rejected

---

## 13. Deterministic Fallback

### When It Activates

1. `LlmService` is null (not injected)
2. LLM API throws exception
3. LLM returns unparseable JSON
4. LLM returns no `facts` key

### Keyword Extraction Coverage

| Pattern | Example | Extracted Fact |
|---------|---------|---------------|
| `\d+ employee/staff` | "25 employees" | employee_count: 25 |
| `\d+ branch/location` | "2 branches" | branch_count: 2 |
| `inventory/stock/warehouse` | "track inventory" | uses_inventory: true |
| `wholesale/retail/online` | "wholesale orders" | sales_channels: [...] |
| `pos/point of sale` | "counter POS" | uses_pos: true |
| `invoice/invoicing` | "need invoicing" | uses_invoicing: true |
| `commission` | "sales commissions" | uses_commissions: true |
| `approval/approve` | "approval workflows" | needs_approvals: true |
| `manufactur/assembl/factory` | "manufacturing" | uses_manufacturing: true |
| `deliver/shipping/fleet` | "delivery service" | uses_delivery: true |

### Business Type Inference

Enhanced keyword scoring for distribution with focused synonyms:
- `spare parts`, `auto parts`, `automotive parts`, `dealer`, `importer`, `fulfillment`
- Hybrid detection when two types score within 70% of each other

---

## 14. Duplicate Protection

### Multi-Layer Checks

1. **Category match**: AI message metadata `category` matches new question category
2. **Text match**: Normalized question text equals existing AI question
3. **Fact coverage**: Category's fact keys already have values in discovery_state
4. **Asked categories**: Category listed in `discovery_state.asked_categories`

### Resolution When Duplicate Detected

```
1. Try to find alternative category from catalog
2. If alternative found and not duplicate → use it
3. If all alternatives are duplicates → mark as ready
```

---

## 15. Correction and Contradiction Handling

### Correction Flow

```
User says: "We have 3 branches"
  → known_facts.branch_count = 3

User says: "Correction: we actually have 2 branches"
  → LLM recognizes correction
  → known_facts.branch_count = 2 (overwritten)
```

### Verified Result

| Step | branch_count | employee_count |
|------|-------------|----------------|
| Initial ("3 branches, 30 employees") | 3 | 30 |
| After correction ("actually 2 branches, 20 employees") | 2 | 20 |

### Contradiction Handling

When the LLM detects conflicting information without explicit correction:
- LLM may ask a clarification question
- The next_question will target the conflicting category
- If both values appear without "correction" language, LLM uses latest value

---

## 16. API Compatibility

### Endpoints Unchanged

| Endpoint | Method | Changes |
|----------|--------|---------|
| `POST /api/discovery/sessions` | start | Now uses adaptive analysis |
| `POST /api/discovery/sessions/{id}/answer` | answer | Now uses adaptive re-analysis |
| `POST /api/discovery/sessions/{id}/classify` | classify | No changes |
| `POST /api/discovery/sessions/{id}/generate-blueprint` | generateBlueprint | No changes |
| `GET /api/discovery/sessions/{id}` | show | No changes |
| `GET /api/discovery/sessions/{id}/blueprint` | showBlueprint | No changes |
| `GET /api/discovery/sessions` | index | No changes |

### Response Changes

New fields in `DiscoverySessionResource`:
```json
{
  "completeness": 79,
  "ready_for_blueprint": true,
  ...existing fields...
}
```

### Message Types

| Type | Purpose | New? |
|------|---------|------|
| description | Initial user description | No |
| follow_up_question | AI question (now adaptive) | No |
| answer | User response | No |
| classification | Business type classification | No |
| blueprint | Generated blueprint | No |
| ready | Blueprint readiness indicator | ✅ Yes |

---

## 17. All Verification Scenarios and Results

### Scenario 1 — Detailed Automotive Description

| Step | Result |
|------|--------|
| Initial description (detailed + country/currency) | 22 facts extracted, completeness=79% |
| Follow-up questions | Zero — already ready |
| Last message type | `ready` |
| Classification | distribution, 98% confidence, LLM method |
| Blueprint | 14 modules, 6 roles, version 1 |

### Scenario 2 — Minimal Restaurant

| Step | Result |
|------|--------|
| Initial: "I own a restaurant in downtown Cairo" | completeness=14%, 1 fact |
| Q1: Scale (employees, branches) | Answer: 12 employees, one location, POS → completeness=28% |
| Q2: Products/services (food types) | Answer: Egyptian cuisine, cash/card, EGP → completeness=46% |
| Q3: Customers (types, count) | Answer: families, 150-200/day, inventory, suppliers → completeness=73%, ready |
| Total questions | 3 adaptive questions |
| Irrelevant questions asked | Zero (no manufacturing, no warehouse logistics) |

### Scenario 3 — Service Company

| Step | Result |
|------|--------|
| Initial: "digital marketing and web design agency with 8 team members" | completeness=19% |
| Q1: Business identity/geography | Answer: PixelForge, Dubai, AED/USD → completeness=34%, ready |
| Total questions | 1 adaptive question |
| Irrelevant questions asked | Zero (no inventory, warehouse, manufacturing, POS) |

### Additional Verifications

| Test | Result |
|------|--------|
| LLM fallback (null LlmService) | ✅ Deterministic extraction + type inference + catalog question |
| Duplicate question rejection | ✅ Already-asked category skipped, next priority used |
| User correction (3→2 branches, 30→20 employees) | ✅ Latest values overwrite previous |
| Session reload retains state | ✅ completeness, ready, messages all persisted |
| Completed session rejects answers | ✅ 422 returned |
| Cross-workspace access blocked | ✅ 403 returned |
| Permission denied (viewer) | ✅ 403 "Permission denied: discovery.manage" |
| Unauthenticated access | ✅ 401 "Unauthenticated" |
| Demo reset | ✅ 181 tables truncated, 0 skipped, seeded |
| Business template routes | ✅ 5 templates available |

---

## 18. Remaining Limitations

| Limitation | Notes |
|-----------|-------|
| Blueprint generation still uses rule-based templates | LLM-enhanced blueprints not implemented |
| Completeness percentage is approximate | Based on category coverage, not fact depth |
| Language detection not explicit | LLM adapts to user language naturally |
| No multi-session comparison | Each session independent |
| No "undo" for corrections | Latest value always wins |
| Deterministic fallback less accurate than LLM | Keyword matching vs semantic understanding |
| No streaming/SSE for real-time question updates | Standard request-response |
| 34% completeness may trigger ready for service companies | Minimum requirements met but few categories relevant |

---

## 19. Exact Scope Recommended for Task 1.5

### Task 1.5 — Blueprint Review & Provisioning Foundation

1. **Blueprint review endpoint** — Allow users to see and optionally adjust the generated blueprint
2. **Wire `ProvisioningService::preview()`** to blueprint → show what would be created
3. **Wire `ProvisioningService::apply()`** to blueprint → actually provision the workspace
4. **Set `onboarding_completed = true`** after successful provisioning
5. **Consider LLM-enhanced blueprint generation** — Use discovery_state facts to influence blueprint content
6. **Do not yet** unify `ProvisioningService` with `BusinessTemplateApplicationService`
7. **Do not yet** modify Flutter onboarding UI
8. **Do not yet** implement blueprint editing by users
9. **Do not yet** create departments, teams, roles, warehouses — only provisioning structure

---

## 20. Exact Files Expected to Change in Task 1.5

| File | Expected Change |
|------|----------------|
| `app/Http/Controllers/Api/ProvisioningController.php` | Wire blueprint ID to preview/apply |
| `app/Services/ProvisioningService.php` | Implement preview() and apply() using blueprint |
| `app/Http/Controllers/Api/DiscoveryController.php` | Optional: add confirm/review endpoint |
| `app/Services/BlueprintGeneratorService.php` | Optional: use discovery_state facts for richer blueprints |
| `app/Http/Resources/DiscoveryBlueprintResource.php` | Optional: add provisioning preview data |
| `routes/api.php` | Optional: add provisioning routes |
| `app/Models/ProvisioningRun.php` | Verify model matches service needs |
| `app/Models/WorkspaceConfiguration.php` | Verify model matches service needs |
