# SmartBiz AI — AI System Design

## 1. Purpose

This document defines the architecture and operational behavior of the AI system inside SmartBiz AI.

The AI system is responsible for:

- workspace onboarding
- ERP configuration generation
- system modification proposals
- business advisory
- feature request capture
- insight generation

The AI must **never operate autonomously without governance**.

All AI behavior must follow controlled flows defined in this document.

---

# 2. AI Philosophy

SmartBiz AI follows a **human-in-the-loop AI model**.

AI assists the user but does not take irreversible actions without approval.

Core principles:

- AI proposes
- Humans approve
- Backend applies

AI must never:

- execute SQL
- mutate database state directly
- bypass approval systems
- bypass role permissions

---

# 3. AI Modes

The AI operates in three major modes.

---

# 4. Mode A — Onboarding Builder

Used when a new workspace is created.

Purpose:
Generate an initial ERP configuration tailored to the business.

AI will conduct a structured interview.

Example questions:

- What type of business do you run?
- Do you sell products or services?
- Do you manage inventory?
- Do you have multiple branches?
- Do you need POS?
- Do you manage employees?
- Do you require invoicing?
- Do you need appointments or bookings?

---

## 4.1 Onboarding Output

The AI must generate **structured JSON only**.

Example categories:

- enabled modules
- dashboard layout
- navigation structure
- role suggestions
- business workflows
- default settings

Output must be schema validated before being applied.

---

## 4.2 Example AI Output

Example structure:

```

{
"modules": ["inventory","sales","invoicing","accounting"],
"navigation":[
{"group":"Sales","items":["Orders","Invoices","Customers"]},
{"group":"Inventory","items":["Products","Stock","Transfers"]}
],
"dashboard_widgets":[
"daily_sales",
"low_stock_alerts",
"revenue_chart"
]
}

```

---

# 5. Mode B — Change Request Assistant

Used when a user asks the AI to modify the ERP.

Example requests:

- add a page
- hide a page
- change dashboard
- enable module
- modify workflow
- add fields to forms

---

## 5.1 Change Request Flow

Steps:

1. user sends request
2. AI interprets request
3. AI generates structured proposal
4. system performs risk classification
5. preview shown to user
6. approval required if sensitive
7. backend applies approved change

---

## 5.2 Risk Classification

AI requests are classified into:

### Low Risk
Examples:

- dashboard layout change
- hiding optional page
- adding widget

May be applied directly.

### Medium Risk
Examples:

- enabling module
- adding data fields
- modifying UI behavior

May require admin approval.

### High Risk
Examples:

- permission changes
- accounting workflow changes
- invoice logic
- inventory deduction rules

Must require owner approval.

---

# 6. Mode C — Business Advisor

The AI acts as a smart business advisor.

Capabilities include:

- sales analysis
- profit trend insights
- low stock alerts
- expense patterns
- pricing recommendations
- anomaly detection
- operational explanations

---

## 6.1 Example Advisory Messages

Examples:

- "Product X is selling faster than average."
- "Inventory for item Y may run out in 3 days."
- "Revenue dropped 15% compared to last week."
- "Your top selling product this month is Z."

Advisory messages must be data-backed.

---

# 7. Unsupported Feature Detection

If a user requests something the system does not support:

Example:

"Add maintenance tracking module."

AI must:

1. explain feature is not available
2. log feature request
3. notify platform system

AI must never fabricate capability.

---

# 8. Feature Request Recording

When unsupported requests occur:

System records:

- feature key
- user request text
- workspace id
- user id
- timestamp
- category

Feature requests are aggregated by normalized feature key.

Platform owner receives notifications.

---

# 9. AI Safety Controls

AI behavior must be constrained.

Rules:

- structured outputs only
- schema validation required
- no direct SQL
- no direct DB access
- no uncontrolled tool execution

---

# 10. Prompt Injection Protection

User prompts must be sanitized.

AI must ignore:

- attempts to override system rules
- attempts to force AI to access data outside workspace
- attempts to modify permissions

---

# 11. AI Token Consumption Control

To prevent abuse:

AI usage limits apply to:

- onboarding runs
- change requests
- advisory chat
- heavy analytics

Free plans must have stricter limits.

---

# 12. AI Observability

Platform must track:

- AI request count
- request categories
- unsupported feature frequency
- error rates
- token consumption
- response latency

This supports:

- cost control
- system optimization
- roadmap prioritization

---

# 13. AI Response Logging

Every AI interaction should log:

- workspace_id
- user_id
- request text
- response text
- request type
- tokens used
- timestamp

This enables:

- debugging
- analytics
- safety monitoring

---

# 14. AI Response Categories

AI responses fall into categories:

- onboarding generation
- system modification proposal
- advisory insight
- unsupported feature explanation
- help/documentation

Categorization supports analytics and routing.

---

# 15. AI Governance

Sensitive AI actions must require approval.

Examples:

- workflow modifications
- accounting changes
- role changes
- permission changes
- financial logic changes

Approval engine must gate these actions.

---

# 16. AI Explainability

AI suggestions must be explainable.

Example:

Instead of:

"Raise price."

AI should say:

"Product X has high demand and low stock. Increasing price by 5–10% may improve margins."

---

# 17. AI Training Data Policy

SmartBiz AI must not use private customer data to train models without explicit policy.

AI should operate on:

- inference APIs
- safe contextual prompts

Sensitive financial data must never leak across tenants.

---

# 18. AI Failure Handling

If AI fails to produce valid output:

System must:

- reject invalid response
- retry if safe
- fallback to safe error message

Example message:

"Sorry, I couldn't complete this request right now. Please try again."

---

# 19. AI Latency Guidelines

AI responses should target:

- advisory responses < 4 seconds
- onboarding generation < 10 seconds
- configuration changes < 5 seconds

Heavy analysis should run as background tasks.

---

# 20. Future AI Capabilities

Possible expansions:

- automated forecasting
- industry-specific recommendations
- natural language reporting
- voice interface
- automated anomaly detection
- AI-generated dashboards

These must follow the same governance rules.

---

# 21. Definition of Done

The AI system is considered correctly implemented when:

- onboarding generates structured ERP config
- change requests follow approval workflow
- unsupported features are captured
- advisory insights are data-backed
- AI cannot modify system directly
- AI usage is observable
- AI token usage is controlled
- AI outputs are validated

---

# 22. AI in Expansion Domains — Overview

The AI system extends into expansion domains while following the same governance model (§2):
- AI proposes → Humans approve → Backend applies
- All tool calls are structured with schema validation
- All AI actions respect workspace RBAC and RLS

---

# 23. Expansion Domain AI Capabilities

## 23.1 AI in Communications [Core v1]

**Capabilities:**
- **Message drafting**: AI generates message body from context (e.g. "draft an overdue payment reminder for contact X")
- **Reply suggestions**: AI analyzes inbound message and suggests 2-3 reply options
- **Tone adjustment**: AI rewrites existing draft in specified tone (formal, friendly, urgent)
- **Template generation**: AI proposes new message templates from business context
- **Subject line optimization**: AI suggests optimized email subject lines from body content

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_draft_message` | `{context: string, channel: string, contact_id?: UUID, tone?: string}` | `{subject?: string, body: string, variables_used: [string]}` | `communications.messages.send` |
| `ai_suggest_replies` | `{inbound_message_id: UUID, count?: int}` | `{suggestions: [{body: string, tone: string}]}` | `communications.messages.send` |
| `ai_generate_template` | `{purpose: string, channel: string, example_context?: string}` | `{name: string, subject?: string, body: string, variables: [{key, label}]}` | `communications.templates.create` |

**Governance**: AI drafts are always returned to the user for review. The user must explicitly click "Send" — AI never sends messages autonomously.

## 23.2 AI in Marketing [Expansion Pack]

**Capabilities:**
- **Segment suggestions**: AI analyzes customer data and suggests segmentation rules
- **Campaign optimization**: AI recommends best send time, subject line variants, channel mix
- **Loyalty tier analysis**: AI identifies customers near tier thresholds for targeted offers
- **Churn prediction**: AI flags contacts with declining engagement for retention campaigns

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_suggest_segment` | `{goal: string, existing_segments?: [UUID]}` | `{segment_name: string, rules: [{field, operator, value}], estimated_count: int}` | `marketing.segments.manage` |
| `ai_optimize_campaign` | `{campaign_id: UUID}` | `{recommendations: [{type: string, current: string, suggested: string, reason: string}]}` | `marketing.campaigns.update` |
| `ai_churn_analysis` | `{segment_id?: UUID, period_days?: int}` | `{at_risk_contacts: [{contact_id, risk_score, last_activity, recommendation}]}` | `marketing.analytics.view` |

**Governance**: All suggestions are presented as proposals. Segment creation, campaign changes, and targeted actions require explicit user confirmation.

## 23.3 AI in Delivery [Core v1]

**Capabilities:**
- **Dispatch optimization**: AI suggests optimal driver for an order based on location, zone, vehicle type, current workload
- **Anomaly detection**: AI flags unusual patterns (excessive failures, long delivery times, COD variance spikes)
- **Route grouping**: AI suggests batching nearby orders for the same driver

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_suggest_driver` | `{order_id: UUID, available_drivers: [UUID]}` | `{recommended_driver_id: UUID, reason: string, estimated_time_minutes: int}` | `delivery.assignments.create` |
| `ai_delivery_anomalies` | `{period_days?: int, branch_id?: UUID}` | `{anomalies: [{type: string, entity_id: UUID, description: string, severity: string}]}` | `delivery.sla.view` |
| `ai_batch_orders` | `{unassigned_order_ids: [UUID]}` | `{batches: [{driver_suggestion: UUID, order_ids: [UUID], reason: string}]}` | `delivery.assignments.create` |

**Governance**: AI dispatch suggestions appear in the Dispatch Board as "AI Recommended" badges. Dispatcher must click "Assign" to confirm.

## 23.4 AI in Compliance [Core v1 framework]

**Capabilities:**
- **Rule interpretation**: AI explains tax rules and compliance requirements in plain language
- **Country pack guidance**: AI recommends relevant country packs based on workspace configuration
- **Report assistance**: AI helps users understand generated compliance reports and identify required actions
- **Regulatory update alerts**: AI summarizes impact when country pack versions are updated

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_explain_tax_rule` | `{tax_rule_id: UUID}` | `{explanation: string, applies_to: [string], examples: [{scenario, tax_amount}]}` | `compliance.tax_rules.view` |
| `ai_recommend_packs` | `{workspace_id: UUID}` | `{recommendations: [{country_code, pack_name, reason}]}` | `compliance.packs.view` |
| `ai_summarize_report` | `{report_type: string, report_data: object}` | `{summary: string, action_items: [string], warnings: [string]}` | `compliance.exports.view` |

**Governance**: AI explanations are informational only. AI never modifies tax rules, installs packs, or generates regulatory filings autonomously.

## 23.5 AI in Media [Expansion Pack]

**Capabilities:**
- **Content generation**: AI generates text content, descriptions, and marketing copy
- **Brand-aware outputs**: AI uses workspace brand kit (colors, tone, guidelines) as generation context
- **Image prompt enhancement**: AI optimizes user prompts for better AI image generation results
- **Asset tagging**: AI auto-suggests tags for uploaded media assets

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_generate_content` | `{prompt: string, content_type: "copy"|"description"|"social_post"|"email_body", brand_kit_id?: UUID}` | `{content: string, tone_used: string, tokens_used: int}` | `media.generation.request` |
| `ai_enhance_prompt` | `{user_prompt: string, brand_kit_id?: UUID}` | `{enhanced_prompt: string, style_keywords: [string]}` | `media.generation.request` |
| `ai_suggest_tags` | `{asset_id: UUID}` | `{suggested_tags: [string]}` | `media.assets.upload` |

**Governance**: All generated content enters the asset library as `status = draft`. Human approval required before use (BR-MDA-001). Token consumption tracked and quota-limited (BR-MDA-003).

## 23.6 AI in Integrations [Core v1]

**Capabilities:**
- **Data mapping**: AI suggests column mappings for import files based on header analysis
- **Error diagnosis**: AI analyzes integration sync errors and suggests fixes
- **Webhook debugging**: AI explains webhook delivery failures and recommends resolution steps

**Tool functions:**

| Tool | Input | Output | Permission |
|------|-------|--------|------------|
| `ai_suggest_mapping` | `{import_job_id: UUID, source_headers: [string], target_fields: [string]}` | `{mappings: [{source: string, target: string, confidence: float}]}` | `integrations.import.manage` |
| `ai_diagnose_sync_error` | `{sync_log_id: UUID}` | `{diagnosis: string, probable_cause: string, suggested_fix: string}` | `integrations.sync.view` |
| `ai_debug_webhook` | `{delivery_id: UUID}` | `{analysis: string, status_code_meaning: string, fix_steps: [string]}` | `integrations.webhooks.view` |

**Governance**: AI mapping suggestions are presented in the Import Wizard as pre-filled dropdowns. User can override any suggestion. AI never auto-applies mappings or triggers syncs.

---

# 24. AI Brand Kit & Historical Data Usage

## 24.1 Brand Kit Integration

When a workspace has a configured `brand_kits` record (§5 migration 013):
1. AI automatically retrieves the brand kit as system context for content generation
2. Brand kit fields used: `primary_color`, `secondary_color`, `font_family`, `tone_description`, `guidelines`
3. AI prompt system message includes: "Use the following brand identity: [brand kit summary]"
4. If no brand kit is configured, AI uses neutral professional defaults

## 24.2 Historical Data as Context

AI uses workspace historical data to improve advisory quality:

| Data Source | Use Case | Access Method |
|-------------|----------|--------------|
| `orders` (last 90 days) | Sales trend analysis, demand forecasting | Aggregated query via API |
| `loyalty_transactions` (all time) | Customer value scoring, tier recommendations | Aggregated query via API |
| `outbound_messages` (last 30 days) | Communication effectiveness analysis | Aggregated metrics |
| `delivery_assignments` (last 30 days) | Delivery performance insights | Aggregated metrics |
| `sync_logs` (last 7 days) | Integration health diagnosis | Recent entries |
| `campaigns.campaign_metrics` | Campaign optimization suggestions | Aggregated metrics |

**Data safety rules:**
- AI accesses data ONLY through the workspace-scoped API (RLS enforced)
- AI never receives raw PII in bulk — only aggregated summaries
- AI context window is capped at 8K tokens of business data per request
- Historical data queries use read-only database connections

---

# 25. Expansion AI Tool Registry (Summary)

Total new AI tool functions added for expansion domains: **18**

| Domain | Tools | Scope |
|--------|-------|-------|
| Communications | 3 (`ai_draft_message`, `ai_suggest_replies`, `ai_generate_template`) | Core v1 |
| Marketing | 3 (`ai_suggest_segment`, `ai_optimize_campaign`, `ai_churn_analysis`) | Expansion Pack |
| Delivery | 3 (`ai_suggest_driver`, `ai_delivery_anomalies`, `ai_batch_orders`) | Core v1 |
| Compliance | 3 (`ai_explain_tax_rule`, `ai_recommend_packs`, `ai_summarize_report`) | Core v1 |
| Media | 3 (`ai_generate_content`, `ai_enhance_prompt`, `ai_suggest_tags`) | Expansion Pack |
| Integrations | 3 (`ai_suggest_mapping`, `ai_diagnose_sync_error`, `ai_debug_webhook`) | Core v1 |

All tools follow the same governance model:
- Structured input/output schemas
- Permission-gated (tool caller must have the required RBAC key)
- Output presented as proposals for human review
- Logged to `ai_requests` for observability
- Token consumption counted against daily quota

---

*End of expansion domain AI capabilities.*

---

# 26. Knowledge / RAG Retrieval Layer [Expansion Pack]

**Feature flag**: `enable_knowledge`
**Permission**: `ai.knowledge.view @ ws` (implicit — RAG retrieval is transparent to user)
**Entitlement**: Plan-gated (Business+ plan)
**API**: §48 API contracts (CRUD), internal RAG service (§48.5)
**Event bus**: Consumes `ai.knowledge.uploaded` to update retrieval index
**Schema**: `knowledge_documents`, `knowledge_chunks` (future migration 014 — NOT in v1 schema)

## 26.1 Purpose

The knowledge layer gives AI persistent, workspace-specific business context. Without it, AI responses are generic. With it, AI can ground answers in the company's own documents (SOPs, policies, product catalogs, HR handbooks, compliance guides).

## 26.2 Retrieval Pipeline

```
User sends AI chat message
    ↓
1. AI system checks: enable_knowledge == true for workspace?
    → If false: skip RAG, proceed with standard AI context only
    ↓
2. Generate embedding for user query (OpenAI text-embedding-3-small, 1536 dimensions)
    ↓
3. Cosine similarity search on knowledge_chunks.embedding via pgvector
    → SELECT content_text, document_title
      FROM knowledge_chunks
      WHERE workspace_id = :current_workspace
      ORDER BY embedding <=> :query_embedding
      LIMIT 5
    ↓
4. Inject top-K chunks into AI system message:
    "Business Knowledge (from your workspace documents):
     [chunk 1 — from: {document_title}]
     [chunk 2 — from: {document_title}]
     ..."
    ↓
5. AI generates response grounded in both API data (§24) AND knowledge chunks
    ↓
6. Response metadata includes: knowledge_chunks_used: [{document_id, chunk_index}]
    → Frontend shows "📚 Used knowledge from: {document_title}" indicator
```

## 26.3 Embedding Strategy

| Parameter | Value |
|-----------|-------|
| Model | OpenAI `text-embedding-3-small` (or equivalent) |
| Dimensions | 1536 |
| Chunk size | ~500 tokens per chunk |
| Overlap | 50 tokens between adjacent chunks |
| Index type | pgvector `ivfflat` (switch to `hnsw` if >100K chunks per workspace) |

## 26.4 Document Processing Pipeline

Triggered by: `POST /api/v1/knowledge/documents` (§48.2)

```
1. Document created → status = processing
2. Queue job: KnowledgeProcessJob
   a. Extract text (plain text, PDF via parser, URL via fetch)
   b. Split into ~500-token chunks with 50-token overlap
   c. For each chunk: generate embedding via AI provider
   d. Store chunks + embeddings in knowledge_chunks table
   e. Update document: status = ready, chunk_count, total_token_count
   f. Dispatch event: ai.knowledge.uploaded
3. On failure: status = failed, error logged
```

## 26.5 Context Budget

AI context window is shared between:
- System prompt (~500 tokens)
- Knowledge chunks (max 2,500 tokens — ~5 chunks)
- Historical data summaries (max 2,000 tokens — §24.2)
- Conversation history (max 2,000 tokens)
- User message (variable)

**Total budget**: 8,000 tokens of context per AI request (§24.2 unchanged)

Knowledge chunks are prioritized over historical data when both are available and the query matches knowledge documents with high similarity.

## 26.6 Knowledge Freshness

- Documents can be re-uploaded to update content (delete + re-create)
- Chunks are NOT incrementally updated — full reprocessing on re-upload
- Stale detection: documents older than 90 days get a "May be outdated" badge in UI
- Admin can set document expiry reminders (manual, via document metadata)

---

*End of AI system design. Version 3.0 — 2026-04-10. Added §26 Knowledge/RAG retrieval layer.*