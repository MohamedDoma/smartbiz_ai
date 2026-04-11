# SmartBiz AI — Platform Admin System

## 1. Purpose

This document defines the **platform-level administration system** for SmartBiz AI.

SmartBiz AI has two operating layers:

1. **Workspace Layer**  
   Used by companies to run their own ERP.

2. **Platform Layer**  
   Used by the SmartBiz AI team to operate, monitor, improve, and govern the platform itself.

The Platform Admin System enables:
- workspace monitoring
- global event tracking
- feature request collection
- platform notifications
- surveys
- usage analytics
- AI consumption oversight
- operational governance

---

## 2. Platform Roles

Platform roles are global and are not tied to a specific workspace.

### 2.1 platform_owner
The highest authority on the entire platform.

Can:
- view all workspaces
- view all platform events
- create and manage platform admins
- create and send broadcasts
- create and manage surveys
- review feature requests
- change feature request statuses
- review global analytics
- inspect AI usage
- inspect sync failures
- disable abusive workspaces
- restore suspended workspaces
- manage global feature flags
- manage platform policies
- manage roadmap priorities

### 2.2 platform_admin
Operational administrator of the platform.

Can:
- view workspaces
- view platform analytics
- review feature requests
- create targeted notifications
- create surveys
- inspect event streams
- support workspace issues

Cannot:
- remove platform owner
- change critical global governance rules unless allowed

### 2.3 platform_support
Support role for helping customers.

Can:
- inspect workspace metadata
- inspect join and approval states
- inspect logs and event trails
- inspect feature requests
- inspect AI request outcomes
- help diagnose issues

Cannot:
- impersonate without policy approval
- alter billing
- alter ownership
- change global configuration

### 2.4 platform_operations
Operations and analytics role.

Can:
- inspect system health
- inspect AI consumption
- inspect failure patterns
- inspect platform events
- inspect adoption metrics
- inspect notification delivery health

---

## 3. Scope of the Platform Admin System

The platform admin system is responsible for:

- monitoring all workspaces
- tracking cross-platform events
- handling feature requests
- managing product demand signals
- sending broadcasts to tenants
- delivering surveys
- tracking release adoption
- monitoring AI usage
- monitoring sync and operational failures
- observing global health and activity

It is **not** the same as a workspace ERP admin panel.

---

## 4. Platform Surfaces

The Platform Admin System should include the following major surfaces.

### 4.1 Platform Dashboard
Overview of:
- total workspaces
- active workspaces
- total users
- active users
- AI request volume
- top requested features
- unread critical events
- failed sync count
- pending broadcasts
- active surveys

### 4.2 Workspace Directory
List of all workspaces with filters and search.

### 4.3 Feature Request Center
Used to track and manage product demand from users and workspaces.

### 4.4 Broadcast Center
Used to create, schedule, and send notifications.

### 4.5 Survey Center
Used to create and analyze surveys.

### 4.6 Platform Events Explorer
Used to inspect global events and activity streams.

### 4.7 AI Oversight Center
Used to inspect AI usage, unsupported requests, and AI change requests.

### 4.8 Operations / Health View
Used to inspect sync failures, event failures, and operational anomalies.

---

## 5. Workspace Directory

The workspace directory is the main listing of all tenant workspaces.

Each record should include at minimum:
- workspace_id
- workspace_name
- business_type
- country if available
- plan
- subscription_status
- number_of_users
- active_user_count
- created_at
- last_active_at
- onboarding_status
- ai_usage_summary
- current_health_status

Possible actions:
- open workspace profile
- inspect usage
- inspect feature requests
- inspect survey participation
- inspect recent events
- suspend workspace
- reactivate workspace

---

## 6. Workspace Profile View

Each workspace should have a platform-side profile view.

Contents:
- workspace metadata
- ownership info
- admins list
- member counts
- enabled modules
- onboarding status
- AI usage snapshot
- recent notifications
- recent feature requests
- recent platform-visible events
- operational flags
- suspension state if any

This view is read-heavy and must not expose unnecessary sensitive customer data by default.

---

## 7. Feature Request System

## 7.1 Purpose
The feature request system captures unmet customer demand.

This is especially important when a workspace asks AI for a feature that does not exist yet.

Example:
- a user asks for a maintenance module
- a user asks for installment tracking page
- a user asks for clinic booking screen
- a user asks for kitchen display system

If the feature is unsupported, the system should:
- inform the user honestly
- register a platform-level request
- aggregate similar requests
- notify platform owner/admin

## 7.2 Feature Request Sources
Requests may come from:
- AI unsupported requests
- explicit user submission
- customer support submission
- internal platform tagging

## 7.3 Feature Request Fields
Each feature request should support:
- id
- title
- normalized_key
- category
- description
- source_type
- status
- priority
- request_count
- workspace_count
- user_count
- first_requested_at
- last_requested_at
- released_at
- rejected_at
- platform_note
- linked_release_note_id if applicable

## 7.4 Feature Request Statuses
Suggested statuses:
- new
- under_review
- planned
- in_progress
- released
- rejected
- duplicate

## 7.5 Feature Request Aggregation
The platform should aggregate similar requests into one product demand item.

The system should support:
- grouping by normalized feature key
- counting unique requesting workspaces
- counting total user requests
- tracking which industries requested it
- tracking which plans requested it

## 7.6 Feature Request Notifications
When a feature request is created or demand rises:
- notify platform owner/admin
- optionally notify product operations dashboard
- optionally trigger internal prioritization rules

## 7.7 Release Follow-up
When a requested feature is released:
- mark feature as released
- identify linked workspaces/users
- send notifications to requesters
- track adoption after release

---

## 8. AI Unsupported Feature Handling

When AI receives a request for an unsupported feature:

1. AI must not fake support.
2. AI must not promise a release date.
3. AI should respond honestly and politely.
4. The system should create or link a feature request.
5. The request should be visible in the platform admin system.

Suggested response pattern:
- the requested feature is not currently available
- the request has been recorded for review by the platform team

The platform admin system must provide:
- unsupported AI request logs
- grouped unsupported requests
- demand trends over time

---

## 9. Broadcast Notification System

## 9.1 Purpose
Allows platform team to send communication to workspaces or platform-wide audiences.

Use cases:
- feature releases
- maintenance announcements
- service alerts
- product education
- onboarding tips
- survey invitations
- plan updates later

## 9.2 Broadcast Audience Targeting
Broadcasts should support targeting by:
- all workspaces
- selected workspaces
- industry type
- plan type
- country
- module usage
- role type
- users who requested a certain feature

## 9.3 Broadcast Fields
A broadcast should support:
- id
- title
- message
- type
- audience_definition
- delivery_channels
- status
- scheduled_at
- sent_at
- created_by
- created_at

## 9.4 Broadcast Types
Examples:
- info
- release
- warning
- maintenance
- survey
- product_tip

## 9.5 Broadcast Statuses
Suggested:
- draft
- scheduled
- sending
- sent
- cancelled
- archived

## 9.6 Delivery Channels
Supported channels may include:
- in-app notification
- push notification
- email later

## 9.7 Broadcast Delivery Tracking
Track:
- targeted_count
- delivered_count
- opened_count
- failed_count
- clicked_count if link exists

---

## 10. Survey System

## 10.1 Purpose
Allows platform team to gather structured feedback from tenants and users.

Use cases:
- satisfaction measurement
- feature validation
- release feedback
- NPS-style questions
- targeted feedback after unsupported requests
- industry-specific discovery

## 10.2 Survey Audience
Support targeting by:
- all workspaces
- selected workspaces
- selected plans
- selected industries
- users of a released feature
- users who requested a missing feature

## 10.3 Survey Structure
A survey should support:
- id
- title
- description
- audience_definition
- questions
- status
- starts_at
- ends_at
- created_by
- created_at

## 10.4 Survey Statuses
Suggested:
- draft
- scheduled
- active
- closed
- archived

## 10.5 Question Types
Examples:
- single choice
- multiple choice
- rating
- NPS
- free text
- yes/no

## 10.6 Survey Analytics
Track:
- invites_sent
- responses_received
- completion_rate
- average_rating
- text feedback summaries later

---

## 11. Platform Event System

## 11.1 Purpose
Provides a global event stream for monitoring and analytics.

This is separate from workspace audit logs.

Workspace audit logs are tenant-scoped.  
Platform events are global platform telemetry.

## 11.2 Examples of Platform Events
- workspace_created
- workspace_suspended
- workspace_reactivated
- join_request_submitted
- join_request_approved
- invoice_created
- payment_recorded
- ai_change_requested
- ai_change_approved
- ai_change_applied
- unsupported_feature_requested
- survey_answer_submitted
- broadcast_sent
- sync_failed
- critical_error_detected

## 11.3 Event Fields
Each platform event should support:
- id
- event_type
- severity
- workspace_id nullable
- user_id nullable
- actor_type
- entity_type nullable
- entity_id nullable
- metadata JSON
- created_at

## 11.4 Event Severity
Suggested severities:
- info
- warning
- error
- critical

## 11.5 Event Explorer Features
Platform event explorer should support:
- filtering by event type
- filtering by severity
- filtering by workspace
- filtering by date range
- search by entity id
- export later if needed

---

## 12. AI Oversight Center

## 12.1 Purpose
Allows the platform team to inspect AI-related behavior across the system.

## 12.2 Key Areas
The platform should be able to inspect:
- AI request count
- unsupported feature requests
- AI change proposals
- AI approval conversions
- AI rejection patterns
- expensive workspaces by AI usage
- failure to parse structured outputs
- top categories of AI demand

## 12.3 Important Metrics
Examples:
- total AI messages
- onboarding AI runs
- change request AI runs
- advisory AI runs
- unsupported request count
- average AI latency
- estimated token usage
- token usage by workspace
- token usage by feature type

---

## 13. Operations and Health Monitoring

## 13.1 Purpose
Gives platform operations visibility into system issues.

## 13.2 Things to Monitor
- failed offline sync operations
- failed notifications
- failed background jobs
- abnormal AI failure rate
- high error workspaces
- repeated approval failures
- suspicious workspace creation patterns
- suspicious AI consumption patterns

## 13.3 Health Views
Recommended views:
- sync health
- notification health
- AI health
- background job health
- workspace anomaly view

---

## 14. Platform Analytics

The platform admin system should expose aggregated analytics such as:
- total workspaces
- active workspaces
- daily active users
- monthly active users
- feature adoption
- module usage
- AI usage trends
- top requested features
- survey engagement
- notification engagement

These analytics support:
- roadmap prioritization
- business decisions
- product decisions
- operational planning

---

## 15. Platform Feature Flags

The platform should support global and targeted feature flags.

Use cases:
- enable new module for selected workspaces
- beta release to selected industries
- hide unfinished feature
- controlled rollout
- rollback if needed

Feature flags should support:
- global on/off
- workspace allowlist
- plan-based enablement
- industry-based enablement
- role-based visibility if needed

---

## 16. Workspace Governance Actions

Platform owner/admin may need governance actions such as:
- suspend workspace
- reactivate workspace
- mark workspace for review
- restrict heavy AI usage
- inspect repeated abuse signals

Governance actions must be:
- auditable
- role-protected
- clearly labeled
- reversible where appropriate

---

## 17. Notification and Survey Relationship to Feature Requests

The platform admin system should connect these systems together.

Examples:
- send survey to workspaces that requested feature X
- notify workspaces when feature X is released
- ask for follow-up feedback after a release
- identify whether release solved the demand

This makes roadmap execution measurable.

---

## 18. Suggested Backend Services for Platform Layer

Recommended services:
- `platform_workspace_service`
- `platform_feature_request_service`
- `platform_broadcast_service`
- `platform_survey_service`
- `platform_event_service`
- `platform_ai_oversight_service`
- `platform_analytics_service`
- `platform_governance_service`

---

## 19. Suggested API Areas for Platform Layer

Platform APIs should be clearly separated from workspace APIs.

Suggested prefix:
- `/api/v1/platform/...`

Examples:
- `/api/v1/platform/workspaces`
- `/api/v1/platform/feature-requests`
- `/api/v1/platform/broadcasts`
- `/api/v1/platform/surveys`
- `/api/v1/platform/events`
- `/api/v1/platform/analytics`
- `/api/v1/platform/ai-oversight`

Platform endpoints must require platform-level roles.

---

## 20. Platform Security Rules

The platform admin system must enforce:
- platform-role authentication
- strict authorization by platform role
- strong auditing for platform actions
- separation from workspace RBAC
- no accidental tenant data mutation through support screens
- support access policies for sensitive data
- careful logging of governance actions

---

## 21. Auditing Requirements

The following platform actions must be audited:
- feature request status changed
- broadcast created
- broadcast sent
- survey created
- survey closed
- workspace suspended
- workspace reactivated
- global feature flag changed
- platform role changed
- AI policy changed later

Audit record should include:
- platform_actor_id
- action
- target_type
- target_id
- old_value
- new_value
- created_at

---

## 22. Non-Goals for Initial Platform Admin Version

The first platform admin version does not need:
- billing management
- advanced customer support ticketing
- full customer impersonation
- automated product roadmap scoring
- AI-generated release notes
- multi-region platform governance

These can be added later.

---

## 23. Definition of Done

The initial Platform Admin System is considered ready when:

- platform owner can see all workspaces
- platform owner can inspect feature requests
- unsupported AI feature requests are captured
- feature requests are aggregated by demand
- platform owner can send broadcasts
- platform owner can create surveys
- platform owner can inspect platform events
- platform owner can inspect AI usage summaries
- platform owner can inspect sync failure summaries
- platform actions are audited

---

## 24. Next Files That Depend on This Document

After this file, create:
1. `6_business_rules.md`
2. `8_ai_system_design.md`
3. `3_api_contracts.md`
4. `4_frontend_architecture.md`

These files must remain aligned with this platform admin system.

---

## 25. Country Pack Management [Core v1 framework]

Platform admins manage the global country pack catalog.

### 25.1 CRUD Operations

| Action | Permission | Notes |
|--------|-----------|-------|
| List all country packs | `platform.country_packs.view` | Includes installed count per pack |
| Create country pack | `platform.country_packs.manage` | Defines country, version, tax_config, payroll_config, invoice_format |
| Update country pack | `platform.country_packs.manage` | Version bump required — existing installs retain old version until manual upgrade |
| Deprecate country pack | `platform.country_packs.manage` | Sets `is_active = false` — no new installs, existing installs unaffected |

### 25.2 Pack Structure

Each country pack contains:
```
country_packs
├── country_code (ISO 3166-1 alpha-2)
├── name (display name, e.g. "Egypt Tax Pack")
├── version (semver, e.g. "1.2.0")
├── tax_config (JSONB)
│   ├── default_tax_rules: [{name, rate, type, applies_to}]
│   └── withholding_rules: [{threshold, rate}]
├── payroll_config (JSONB)
│   ├── statutory_deductions: [{name, rate, cap}]
│   └── employer_contributions: [{name, rate}]
├── invoice_format (JSONB)
│   ├── required_fields: [string]
│   └── sequence_format: string
├── constants (JSONB)
│   └── min_retention_years: {invoices: 7, payroll: 10, ...}
└── is_active: boolean
```

### 25.3 Version Management

- Major version changes (1.x → 2.x) notify all workspaces using the pack
- Minor/patch updates are available for opt-in upgrade
- Platform admin can force-upgrade all installs in critical compliance updates
- Upgrade preserves workspace overrides — only adds new defaults

### 25.4 Platform Dashboard View

Country Pack management page shows:
- Total packs: active vs deprecated
- Installation heatmap: packs ranked by install count
- Version distribution: how many workspaces use each pack version
- Recently updated packs

---

## 26. Integration Catalog Control [Core v1]

Platform admins manage the global integration provider catalog.

### 26.1 Provider Management

| Action | Permission | Notes |
|--------|-----------|-------|
| List providers | `platform.integrations.view` | Shows all providers with connection counts |
| Create provider | `platform.integrations.manage` | Defines type, config_schema, auth_type |
| Update provider | `platform.integrations.manage` | Schema changes do not break existing connections |
| Disable provider | `platform.integrations.manage` | Sets `is_active = false` — blocks new connections |
| View global health | `platform.integrations.view` | Aggregate failure rate across all workspaces |

### 26.2 Provider Definition

Each provider record contains:
```
integration_providers
├── name (e.g. "Stripe", "Twilio", "QuickBooks")
├── type (payment | email | sms | ecommerce | accounting | storage | custom)
├── auth_type (api_key | oauth2 | basic | custom)
├── config_schema (JSONB — JSON Schema for credential form generation)
├── webhook_config (JSONB — signature validation method, header names)
├── documentation_url (string)
├── logo_url (string)
└── is_active (boolean)
```

### 26.3 Platform Health Dashboard

Global integration health view:
- Provider availability: % of workspace connections in `active` state
- Failure rate: webhook delivery failures per provider (last 24h)
- Top errors: most common error messages per provider
- Alert: providers with >10% failure rate highlighted

---

## 27. Media Quota Management [Expansion Pack]

Platform admins control AI content generation quotas.

### 27.1 Quota Model

Quotas are configured at the subscription plan level:

| Plan | Daily AI Requests | Storage Limit | AI Content Generation |
|------|-------------------|--------------|----------------------|
| Free | 20 | 500 MB | Disabled |
| Starter | 100 | 5 GB | 10 requests/day |
| Business | 500 | 25 GB | 50 requests/day |
| Enterprise | Unlimited | 100 GB | 200 requests/day |

### 27.2 Platform Controls

| Action | Permission | Notes |
|--------|-----------|-------|
| View quota usage | `platform.quotas.view` | Per-workspace breakdown: AI requests, storage, generation |
| Override workspace quota | `platform.quotas.manage` | Temporary or permanent override for individual workspace |
| Set plan defaults | `platform.subscription_plans.manage` | Updates apply to new and renewing subscriptions |
| View abuse alerts | `platform.quotas.view` | Workspaces exceeding 90% of quota highlighted |

### 27.3 Monitoring

- Real-time quota consumption dashboard
- Daily usage trends (line chart per plan tier)
- Alert when any workspace hits quota ceiling
- Cost projection based on current AI provider token pricing

---

## 28. Expansion Module Gating per Subscription Plan [Core v1]

Platform admins control which expansion modules are available per subscription plan.

### 28.1 Module-Plan Matrix

| Module | Free | Starter | Business | Enterprise |
|--------|------|---------|----------|------------|
| Communications (basic) | ✓ | ✓ | ✓ | ✓ |
| Communication Automations | ✗ | ✗ | ✓ | ✓ |
| Marketing (segments, loyalty) | ✗ | ✓ | ✓ | ✓ |
| Marketing (campaigns, referrals) | ✗ | ✗ | ✓ | ✓ |
| Delivery (basic dispatch) | ✗ | ✓ | ✓ | ✓ |
| Delivery (live tracking, SLA) | ✗ | ✗ | ✗ | ✓ |
| Compliance (country packs) | ✓ | ✓ | ✓ | ✓ |
| Compliance (retention policies) | ✗ | ✗ | ✓ | ✓ |
| Media (asset library, brand kit) | ✓ | ✓ | ✓ | ✓ |
| Media (AI content generation) | ✗ | ✗ | ✓ | ✓ |
| Integrations (connect, import/export) | ✗ | ✓ | ✓ | ✓ |
| Integrations (webhooks, advanced sync) | ✗ | ✗ | ✓ | ✓ |

### 28.2 Implementation

Module gating is implemented through:
1. `subscription_plans.features` JSONB contains feature flag defaults per plan
2. On workspace login, backend resolves active plan → populates feature flags
3. Feature flags sent to frontend in workspace config response
4. Frontend hides nav items and pages based on flags (§26 frontend architecture)
5. Backend validates feature flag access on every API request (middleware)

### 28.3 Platform Admin Controls

| Action | Permission | Notes |
|--------|-----------|-------|
| View plan-module matrix | `platform.subscription_plans.view` | Read-only matrix view |
| Edit plan features | `platform.subscription_plans.manage` | Toggle modules per plan |
| Override workspace features | `platform.quotas.manage` | Enable/disable specific modules for a workspace regardless of plan |
| View feature adoption | `platform.analytics.view` | % of workspaces using each module, grouped by plan |

### 28.4 Upgrade Prompts

When a user accesses a gated feature:
- Frontend shows "Upgrade Required" modal with feature description and plan comparison
- CTA links to `/admin/subscription` for self-service upgrade
- Event logged for platform analytics (feature_gate_hit)

---

*End of expansion platform admin controls.*

---

## 29. Entitlement Override Management [Core v1]

Platform admins manage workspace-level entitlement overrides to handle exceptions to plan-based gating.

**Backend**: `EntitlementService` 4-layer resolution chain (§31 backend architecture)
**Business rule**: BR-SYS-006 (Layer 2 — workspace overrides take precedence over plan defaults)

### 29.1 Override CRUD

| Action | Permission | Notes |
|--------|-----------|-------|
| List workspace overrides | `platform.quotas.view` | Shows all active overrides for a workspace |
| Create override | `platform.quotas.manage` | Enable/disable specific feature for a workspace regardless of plan |
| Update override | `platform.quotas.manage` | Change expiry, reason, or enabled status |
| Delete override | `platform.quotas.manage` | Removes override — workspace falls back to plan defaults |

### 29.2 Override Types

| Type | Example | Use Case |
|------|---------|----------|
| Feature enable | `enable_campaigns = true` on Starter plan workspace | Customer negotiated enterprise feature at lower tier |
| Feature disable | `enable_delivery = false` on Enterprise workspace | Customer requested module removal (compliance) |
| Quota override | `max_ai_requests = 1000` (exceeds plan default of 500) | High-value customer needs temporary AI burst |
| Trial extension | `grace_ends_at = +30 days` | Sales team extending trial for prospect |

### 29.3 Override Record

```
workspace_feature_overrides (future migration)
├── workspace_id (FK → workspaces)
├── feature_key (string — maps to subscription_plans.features keys)
├── enabled (boolean)
├── expires_at (timestamp, nullable — null = permanent)
├── reason (text — required, for audit trail)
├── granted_by (FK → users, platform admin who created override)
├── created_at
└── updated_at
```

### 29.4 Audit Trail

- Every override creation/modification/deletion is logged in `platform_events`
- Event type: `platform.entitlement.override_created`, `platform.entitlement.override_revoked`
- Visible in workspace audit log for transparency

### 29.5 Analytics Dashboard

Platform admin dashboard shows:
- Total active overrides (grouped by feature key)
- Override distribution by plan tier (how many Starter workspaces have Business-tier features)
- Expiring overrides (next 7 days) — alert for follow-up
- Feature gate hit rate: how often users encounter 402 errors per feature (informs pricing decisions)

---

*End of platform admin system. Version 3.0 — 2026-04-10. Added §29 entitlement override management.*