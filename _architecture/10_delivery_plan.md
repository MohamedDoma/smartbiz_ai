# SmartBiz AI — Delivery Plan

## 1. Purpose

This document defines the **implementation roadmap** for building SmartBiz AI.

The goal is to move from architecture to a working production system in a **structured, safe, and scalable way**.

The delivery plan focuses on:

* minimizing architectural risk
* shipping usable milestones
* validating core workflows early
* controlling AI complexity
* ensuring ERP correctness

The system will be built using **modular monolith architecture** first.

---

# 2. Development Philosophy

SmartBiz AI development follows these principles:

### 2.1 Modular Monolith First

Instead of microservices from day one, the system will start as:

```
single backend service
multiple internal modules
shared database
```

This reduces complexity while maintaining clean architecture.

Modules include:

* auth
* workspace
* users
* inventory
* sales
* invoices
* payments
* accounting
* approvals
* notifications
* AI

Microservices can be introduced later if needed.

---

### 2.2 Vertical Delivery

Features should be delivered **end-to-end**.

Example:

Instead of building all database models first, build full vertical slices such as:

```
Product → API → UI → Testing
```

---

### 2.3 Data Integrity First

ERP systems handle **financial data**, therefore:

* accounting must be correct
* inventory must be consistent
* transactional safety must exist

Data correctness is more important than feature count.

---

# 3. Project Phases

The development will be divided into **6 phases**.

---

# Phase 1 — Backend Foundation

Goal: Establish secure system base.

Duration estimate: **1–2 weeks**

Deliverables:

* Laravel backend
* database connection
* migration system
* auth system
* workspace system
* membership system
* role system

Modules delivered:

```
auth
workspace
users
roles
```

Endpoints:

```
/auth/register
/auth/login
/workspaces
/workspaces/join
/users
```

Infrastructure:

```
PostgreSQL
Redis
Docker
```

---

# Phase 2 — ERP Core

Goal: Build essential ERP operations.

Duration estimate: **2–3 weeks**

Modules delivered:

```
products
categories
units
contacts
inventory
warehouses
orders
invoices
payments
```

Key workflows implemented:

* product management
* stock tracking
* order creation
* invoice creation
* payment recording

---

# Phase 3 — Accounting Engine

Goal: Financial correctness.

Duration estimate: **1–2 weeks**

Modules delivered:

```
accounts
journal entries
journal lines
posting engine
```

Rules implemented:

* balanced journal entries
* invoice posting
* payment posting
* ledger source of truth

---

# Phase 4 — Approval System

Goal: Governance for sensitive operations.

Duration estimate: **1 week**

Modules delivered:

```
approval requests
approval workflows
approval policies
approval logs
```

Used for:

* employee join approvals
* AI change approvals
* stock transfer approvals
* workflow approvals

---

# Phase 5 — AI System Integration

Goal: Intelligent ERP setup and advisory.

Duration estimate: **2 weeks**

Modules delivered:

```
ai_onboarding_service
ai_change_service
ai_advisor_service
feature_request_capture
```

Capabilities:

* AI onboarding interview
* AI ERP configuration generation
* AI change proposals
* AI advisory insights
* feature request logging

---

# Phase 6 — Frontend System

Goal: Complete ERP user interface.

Duration estimate: **2–3 weeks**

Frontend features:

* authentication screens
* workspace switching
* dynamic navigation
* product management UI
* inventory UI
* sales UI
* invoice UI
* dashboard system
* AI chat interface

Technology:

```
Flutter
Riverpod or Bloc
Dio HTTP client
```

---

# Phase 7 — Platform Admin System

Goal: Operate the SaaS platform.

Duration estimate: **1–2 weeks**

Modules delivered:

```
workspace directory
feature request center
broadcast system
survey system
platform analytics
AI oversight dashboard
```

Used by:

```
platform_owner
platform_admin
platform_support
```

---

# Phase 8 — Offline POS

Goal: Partial offline capability.

Duration estimate: **1–2 weeks**

Capabilities:

* cached product catalog
* POS draft creation
* offline sale queue
* sync replay
* conflict detection

---

# Phase 9 — Stabilization

Goal: production readiness.

Duration estimate: **1–2 weeks**

Tasks include:

* performance optimization
* query indexing
* caching strategies
* error monitoring
* logging improvements
* security review

---

# 4. Deployment Strategy

Initial deployment architecture:

```
API container
Worker container
PostgreSQL
Redis
Object storage
Nginx
```

Cloud options:

```
AWS
DigitalOcean
Hetzner
```

---

# 5. Testing Strategy

Testing layers include:

### Unit Tests

Test:

* services
* validators
* accounting logic

### Integration Tests

Test:

* API endpoints
* database transactions
* workflows

### End-to-End Tests

Test:

* login
* workspace creation
* product creation
* invoice flow
* payment flow

---

# 6. Observability

Production system must include:

* error monitoring
* API metrics
* AI request metrics
* slow query monitoring
* audit logs

Suggested tools:

```
Sentry
Prometheus
Grafana
```

---

# 7. Security Review

Before production release:

* review authentication system
* verify role permissions
* validate RLS policies
* test tenant isolation
* audit AI actions

---

# 8. Definition of Done

The system is considered **production ready** when:

* authentication works
* workspace isolation works
* ERP operations work
* accounting entries balance
* approval flows work
* AI onboarding works
* AI change proposals work
* offline POS works
* platform admin tools work
* monitoring exists

---

# 9. Future Expansion (Superseded)

> The items below are now covered by Phases 10–20 in this delivery plan. This section is retained for reference only.

After initial launch the system may expand with:

* payroll engine
* appointment scheduling
* CRM automation
* industry-specific modules
* advanced analytics
* forecasting AI
* marketplace integrations

---

# Phase 10 — Communications Engine [Core v1]

**Scope**: Build the messaging infrastructure for email, SMS, WhatsApp, and push notifications.

**Dependencies**: Phase 1 (auth), Phase 2 (contacts), Migration 013

**Deliverables**:
- Communication channels CRUD (connect email/SMS/push providers)
- Message template CRUD with variable interpolation
- Outbound message send API with channel routing
- Message delivery tracking (queued → sent → delivered → failed)
- Retry logic (3 retries, exponential backoff — BR-COM-003)
- Message log page with filtering and search
- AI message drafting tool (`ai_draft_message`)

**Definition of Done**:
- [ ] A workspace can configure at least one email channel
- [ ] A user can send a message via template or free-form
- [ ] Failed messages retry automatically up to 3 times
- [ ] Message log shows status transitions in real-time
- [ ] AI draft produces a valid message body with variable interpolation

**Duration estimate**: 1–2 weeks

---

# Phase 11 — Marketing Foundation (Segments & Loyalty) [Core v1]

**Scope**: Build customer segmentation and loyalty program core.

**Dependencies**: Phase 2 (contacts, orders), Phase 10 (communications), Migration 013

**Deliverables**:
- Segments CRUD with dynamic rule builder
- Segment recalculation background job (BR-MKT-005)
- Loyalty programs CRUD (tiers, earn rules, reward catalog)
- Loyalty accounts (auto-created on first purchase)
- Points earn on order completion
- Points redeem via POS (BR-MKT-001, BR-MKT-002)
- POS loyalty widget integration
- Loyalty transaction history

**Definition of Done**:
- [ ] Admin can create a segment with rules — recalculation populates contacts
- [ ] Loyalty program with 3 tiers can be created
- [ ] Points auto-earned on POS sale completion
- [ ] Cashier can redeem points at POS terminal
- [ ] Insufficient point balance is rejected
- [ ] Tier promotion is immediate on threshold crossing

**Duration estimate**: 2–3 weeks

---

# Phase 12 — Delivery & Fleet Management [Core v1]

**Scope**: Build dispatch, driver management, and delivery tracking.

**Dependencies**: Phase 2 (orders), Phase 1 (auth — driver role), Migration 013

**Deliverables**:
- Drivers CRUD (status, vehicle info, zone assignments)
- Delivery zones CRUD
- Dispatch Board (real-time Kanban UI)
- Delivery assignment lifecycle (BR-DEL-001, BR-DEL-002)
- Driver app screens (accept/reject, pickup, deliver, fail)
- Proof of delivery (photo, signature, PIN — BR-DEL-004)
- COD collection with variance tracking (BR-DEL-003)
- Push notifications for driver assignment
- COD reconciliation page

**Definition of Done**:
- [ ] Dispatcher can assign an order to an available driver
- [ ] Driver can accept, pick up, deliver, or reject assignment
- [ ] COD variance is flagged when amount mismatch exceeds threshold
- [ ] Proof of delivery is required for COD orders
- [ ] Dispatch Board updates in real-time (≤ 15 second latency)
- [ ] Driver status auto-transitions on assignment lifecycle events

**Duration estimate**: 2–3 weeks

---

# Phase 13 — Compliance & Country Packs [Core v1 framework]

**Scope**: Build the localization framework with tax rules and country packs.

**Dependencies**: Phase 3 (accounting), Phase 2 (invoices), Migration 013

**Deliverables**:
- Country pack catalog (platform-managed)
- Country pack install/uninstall flow (BR-CMP-001)
- Tax rule engine (effective date-based — BR-CMP-002)
- Tax rule application on invoice creation
- Country pack upgrade flow (version management)
- Tax rules management page
- Platform admin country pack management page

**Definition of Done**:
- [ ] Platform admin can create a country pack with tax config
- [ ] Workspace admin can install a pack — tax rules seeded
- [ ] Invoice creation applies correct tax based on effective date
- [ ] Old tax rules are end-dated, not deleted, on rate change
- [ ] Re-installing already installed pack returns 409
- [ ] Pack uninstall does not affect historical invoices

**Duration estimate**: 1–2 weeks

---

# Phase 14 — Media & Brand Kit [Core v1 basic]

**Scope**: Build the media asset library and brand kit.

**Dependencies**: Phase 1 (auth, file storage), Migration 013

**Deliverables**:
- Media asset CRUD with upload to object storage
- Folder organization for assets
- Tag-based search and filtering
- Brand kit singleton CRUD (BR-MDA-002)
- Asset approval workflow (BR-MDA-001)
- Media library UI (grid/list view, lightbox preview)
- Brand kit editor with color picker and tone input

**Definition of Done**:
- [ ] User can upload images/documents to the asset library
- [ ] Assets can be organized in folders and tagged
- [ ] Search returns relevant results by name, tag, and folder
- [ ] Brand kit is limited to one per workspace (upsert)
- [ ] Uploaded assets are accessible via pre-signed URLs

**Duration estimate**: 1 week

---

# Phase 15 — Integration Hub [Core v1]

**Scope**: Build the integration framework with provider catalog, connections, webhooks, and import/export.

**Dependencies**: Phase 1 (auth), Phase 2 (products, contacts), Migration 013

**Deliverables**:
- Integration provider catalog (platform-managed)
- Workspace integration connect/disconnect/test (BR-INT-003, BR-INT-004)
- Integration health dashboard
- Webhook subscription CRUD
- Webhook delivery with retry (BR-INT-001)
- Payment gateway webhook verification (BR-INT-005)
- Import wizard: upload, column mapping, validation, apply (BR-INT-002)
- Export jobs (CSV/XLSX)
- AI column mapping suggestions (`ai_suggest_mapping`)
- Sync log viewer

**Definition of Done**:
- [ ] Platform admin can create an integration provider
- [ ] Workspace admin can connect and test an integration
- [ ] Webhook deliveries retry on failure (5 attempts, exponential backoff)
- [ ] Unverified payment webhooks are rejected with 400
- [ ] Import wizard validates all rows before apply step
- [ ] Disconnect preserves all historical sync data
- [ ] AI suggests accurate column mappings from CSV headers

**Duration estimate**: 2–3 weeks

---

# Phase 16 — Communication Automations [Expansion Pack]

**Scope**: Event-driven messaging automations.

**Dependencies**: Phase 10 (communications), Phase 4 (approvals/events)

**Deliverables**:
- Communication automation CRUD (trigger event, template, channel)
- Event listener for system events (invoice.overdue, order.confirmed, leave.approved)
- Automation execution engine (trigger → interpolate → queue)
- Automation trigger validation (BR-COM-002)
- Automation management page with enable/disable toggle

**Definition of Done**:
- [ ] Admin can create an automation for "invoice.overdue" event
- [ ] When invoice becomes overdue, message is auto-queued
- [ ] Invalid trigger events are rejected at creation time
- [ ] Automations can be paused/resumed without deletion

**Duration estimate**: 1 week

---

# Phase 17 — Marketing Campaigns & Referrals [Expansion Pack]

**Scope**: Campaign management, referral programs, and advanced marketing.

**Dependencies**: Phase 11 (segments, loyalty), Phase 10 (communications)

**Deliverables**:
- Campaign CRUD with wizard (draft, launch, pause, complete)
- Campaign launch guard (BR-MKT-003)
- Campaign metrics tracking (sent, delivered, opened, clicked)
- Referral program CRUD
- Referral code generation and attribution
- Referral reward issuance on qualifying action (BR-MKT-004)
- Lead nurturing sequence builder
- Marketing analytics dashboard
- AI campaign optimization tool (`ai_optimize_campaign`)
- AI segment suggestion tool (`ai_suggest_segment`)

**Definition of Done**:
- [ ] User can create, launch, pause, and complete a campaign
- [ ] Campaign with empty segment cannot be launched (guard)
- [ ] Referral reward is issued only after qualifying action
- [ ] Campaign metrics update as messages are delivered
- [ ] AI optimization suggests improved send times and subject lines

**Duration estimate**: 2 weeks

---

# Phase 18 — Advanced Delivery Features [Expansion Pack]

**Scope**: Live GPS tracking, SLA monitoring, and AI dispatch.

**Dependencies**: Phase 12 (delivery core)

**Deliverables**:
- Driver location tracking (GPS broadcast via WebSocket)
- Live tracking map (real-time driver positions)
- SLA configuration per delivery zone
- SLA breach detection and escalation (BR-DEL-005)
- SLA report page
- AI dispatch optimization (`ai_suggest_driver`, `ai_batch_orders`)
- AI delivery anomaly detection (`ai_delivery_anomalies`)

**Definition of Done**:
- [ ] Driver location updates visible on live tracking map
- [ ] SLA breach auto-detected and escalation notification sent
- [ ] AI suggests optimal driver based on location and workload
- [ ] AI flags anomalies (excessive failures, long delivery times)
- [ ] Map markers update in real-time (≤ 5 second latency)

**Duration estimate**: 1–2 weeks

---

# Phase 19 — Advanced Compliance & Media AI [Expansion Pack]

**Scope**: Data retention policies, regulatory exports, and AI content generation.

**Dependencies**: Phase 13 (compliance core), Phase 14 (media core)

**Deliverables**:
- Data retention policy CRUD (BR-CMP-003)
- Archival job engine with audit logging (BR-CMP-004)
- Regulatory export generation (VAT return, payroll summary)
- AI content generation studio (BR-MDA-003)
- AI prompt enhancement (`ai_enhance_prompt`)
- AI asset tagging (`ai_suggest_tags`)
- Brand kit context injection for AI generation
- Generation quota enforcement

**Definition of Done**:
- [ ] Admin can set retention policies for each entity type
- [ ] Retention policies enforce regulatory minimum from country pack
- [ ] Archival job executes and logs results (irreversible)
- [ ] AI generates content respecting brand kit tone and colors
- [ ] AI generation respects daily quota (429 on exhaustion)
- [ ] Regulatory exports produce valid downloadable files

**Duration estimate**: 2 weeks

---

# Phase 20 — Final Hardening & Launch Readiness [Core v1]

**Scope**: Platform hardening, performance testing, security audit, and launch preparation.

**Dependencies**: All previous phases

**Deliverables**:
- End-to-end integration test suite (all expansion modules)
- Performance load testing (1000 concurrent workspaces simulation)
- Security audit: RLS validation across all 48 expansion tables
- Feature flag gating verification (all plan tiers)
- Module-plan matrix enforcement (backend middleware)
- Upgrade prompt implementation ("Upgrade Required" modal)
- Platform admin expansion dashboards (country packs, integrations, quotas)
- Documentation: API reference, webhook guide, import/export guide
- Deployment runbook: migration 013 rollout plan

**Definition of Done**:
- [ ] All 48 expansion tables pass RLS isolation test
- [ ] All expansion API endpoints enforce feature flag gating
- [ ] Load test: <200ms p95 response time under 1000 workspace load
- [ ] Security audit passes with no critical findings
- [ ] Platform admin can manage country packs, providers, and quotas
- [ ] Upgrade modal triggers correctly on gated feature access
- [ ] All expansion documentation is complete and published
- [ ] Migration 013 rollout tested in staging environment

**Duration estimate**: 2–3 weeks

---

# Phase 9.5 — Cross-Cutting Infrastructure [Core v1]

**Scope**: Build the foundational infrastructure services required by all expansion modules. Must be completed BEFORE Phase 10.

**Dependencies**: Phase 1 (auth, workspace), Phase 4 (approvals)

**Deliverables**:
- SearchService interface with PostgresSearchDriver (§28 backend architecture)
  - GIN tsvector indexes on: products, contacts, media_assets, employees, outbound_messages
  - `?q=` parameter routing through SearchService on all list endpoints
- Domain Event Bus (§29 backend architecture)
  - Base `DomainEvent` class with canonical envelope schema
  - Event naming registry (domain.entity.past_tense_verb)
  - `afterCommit` trait on all queued listeners
  - Core subscribers: AuditLogger, PlatformEventLogger, NotificationDispatcher, SearchIndexer
  - Redis queue configuration (default, notifications, webhooks, integrations)
  - Laravel Horizon dashboard for queue monitoring
- Analytics Data Boundary (§30 backend architecture)
  - Read replica connection configuration (`DB_READ_HOST`)
  - 5 materialized views with scheduled refresh jobs
  - Report services using read replica connection
- Entitlement Resolution Chain (§31 backend architecture)
  - `EntitlementMiddleware` implementation
  - `EntitlementService::check()` with 4-layer resolution
  - 402/429 error responses with upgrade_url and reset_at
  - Grace period enforcement (7-day configurable)
- Task Feed Service (§33 backend architecture)
  - `TaskFeedService` with 6 source entity queries
  - `GET /api/v1/tasks/my` endpoint
  - Task feed page in Flutter app
  - Push notification deep links for new tasks

**Definition of Done**:
- [ ] SearchService returns results for product name search via tsvector
- [ ] Domain event dispatched after order creation triggers AuditLogger and PlatformEventLogger
- [ ] Failed queued listener retries 3 times and lands in failed_jobs table
- [ ] Dashboard KPIs read from materialized views on read replica connection
- [ ] EntitlementMiddleware returns 402 when Starter plan user accesses campaigns endpoint
- [ ] Task feed merges approval_requests and delivery_assignments into unified list
- [ ] Task feed empty state shows "All caught up!" message

**Duration estimate**: 2–3 weeks

---

# Delivery Summary

| Phase | Name | Scope | Duration |
|-------|------|-------|----------|
| 1–6 | Core Foundation | Core v1 | 8–14 weeks |
| 7–9 | Deployment & Testing | Core v1 | 2–3 weeks |
| 9.5 | Cross-Cutting Infrastructure | Core v1 | 2–3 weeks |
| 10 | Communications Engine | Core v1 | 1–2 weeks |
| 11 | Marketing Foundation | Core v1 | 2–3 weeks |
| 12 | Delivery & Fleet | Core v1 | 2–3 weeks |
| 13 | Compliance & Country Packs | Core v1 | 1–2 weeks |
| 14 | Media & Brand Kit | Core v1 | 1 week |
| 15 | Integration Hub | Core v1 | 2–3 weeks |
| 16 | Communication Automations | Expansion Pack | 1 week |
| 17 | Marketing Campaigns & Referrals | Expansion Pack | 2 weeks |
| 18 | Advanced Delivery Features | Expansion Pack | 1–2 weeks |
| 19 | Advanced Compliance, Media AI & Knowledge | Expansion Pack | 2–3 weeks |
| 20 | Final Hardening & Launch | Core v1 | 2–3 weeks |

**Total estimated duration (Phases 9.5–20)**: 20–31 weeks

**Core v1 Phases**: 9.5, 10, 11, 12, 13, 14, 15, 20
**Expansion Pack Phases**: 16, 17, 18, 19

**Phase 19 update**: Now includes knowledge document store + pgvector RAG pipeline + knowledge management UI (§26 AI system design, §48 API contracts, §32 frontend architecture).

---

*End of delivery plan. Version 3.0 — 2026-04-10. Added Phase 9.5 (cross-cutting infrastructure). Updated Phase 19 scope to include knowledge layer.*
