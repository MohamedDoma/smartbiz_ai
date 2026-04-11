# SmartBiz AI — Backend Architecture

## 1. Goal

This document defines the backend architecture for SmartBiz AI as a production-grade, multi-tenant, AI-powered ERP SaaS platform.

The backend must support:

- multi-workspace SaaS isolation
- full ERP operations
- AI-driven workspace setup and modification
- approval-based AI changes
- Flutter clients for Android, iOS, and Web
- partial offline support for mobile and POS
- scalable APIs for thousands of workspaces
- secure role-based access control
- auditability for sensitive actions

---

## 2. Core Stack

### Backend Framework
- PHP 8.3+
- Laravel 11

### Database
- PostgreSQL

### ORM / DB Access
- Eloquent ORM
- Laravel Migrations

### Auth / Security
- Laravel Sanctum (API tokens for Flutter clients, SPA auth for web admin)
- refresh tokens (via Sanctum token rotation)
- password hashing with bcrypt (Laravel default)
- RBAC + workspace-scoped permissions
- PostgreSQL Row Level Security

### Background Jobs
- Laravel Queue (Redis driver)
- Laravel Horizon for queue monitoring
- Redis as broker / cache

### AI Layer
- OpenAI API (via Laravel HTTP client or dedicated AI microservice)
- structured JSON outputs only for all ERP generation / AI modifications

### Storage
- AWS S3 or compatible object storage (via Laravel Filesystem)

### Realtime / Notifications
- Laravel Broadcasting (Reverb, Pusher, or Ably driver) for websockets
- Laravel Notifications for push (FCM), email, and in-app channels
- Firebase Cloud Messaging for mobile push

### Infra
- Docker
- Nginx + PHP-FPM (or Laravel Octane with FrankenPHP for high-concurrency)
- AWS deployment target

---

## 3. Architectural Principles

### 3.1 Multi-tenant by design
Every business entity belongs to a workspace.

Rules:
- all workspace-scoped tables must contain `workspace_id` where appropriate
- all queries must be scoped by workspace
- PostgreSQL RLS must be enforced
- application layer must also validate workspace membership

### 3.2 AI is advisory + controlled
AI does not directly mutate critical business logic without approval.

AI can:
- propose ERP structure
- propose page changes
- propose workflow changes
- propose settings changes
- provide analysis and recommendations

AI cannot directly apply sensitive changes unless approved by owner or authorized co-owner/admin according to rules.

### 3.3 Stable core + dynamic customization
The backend is not code-generated per workspace.

The backend provides:
- stable ERP core
- modular features
- dynamic UI and workspace configuration
- AI-driven customization through config/state, not raw runtime code generation

### 3.4 API-first design
All clients use the same backend APIs:
- Flutter mobile
- Flutter web
- future admin tools
- internal services

### 3.5 Auditability
Critical actions must be traceable:
- approvals
- financial postings
- stock transfers
- role changes
- AI-applied changes
- workspace setting changes

---

## 4. High-Level Backend Layers

Backend should be organized into the following layers:

### 4.1 API Layer
Responsible for:
- request validation
- authentication
- response serialization
- endpoint routing

### 4.2 Application Layer
Responsible for:
- use cases
- orchestration
- business workflows
- approvals
- AI action coordination

### 4.3 Domain Layer
Responsible for:
- business rules
- invariants
- ERP logic
- accounting logic
- stock logic
- approval rules

### 4.4 Persistence Layer
Responsible for:
- repositories
- DB access
- transactional boundaries
- optimized queries

### 4.5 Infrastructure Layer
Responsible for:
- AI providers
- storage
- background jobs
- notifications
- cache
- external services

---

## 5. Suggested Folder Structure

```text
backend/
├── app/
│   ├── Http/
│   │   ├── Controllers/
│   │   │   └── Api/V1/
│   │   │       ├── AuthController.php
│   │   │       ├── WorkspaceController.php
│   │   │       ├── UserController.php
│   │   │       ├── RoleController.php
│   │   │       ├── BranchController.php
│   │   │       ├── DepartmentController.php
│   │   │       ├── ProductController.php
│   │   │       ├── InventoryController.php
│   │   │       ├── ContactController.php
│   │   │       ├── OrderController.php
│   │   │       ├── InvoiceController.php
│   │   │       ├── PaymentController.php
│   │   │       ├── TransactionController.php
│   │   │       ├── DashboardController.php
│   │   │       ├── NotificationController.php
│   │   │       ├── ApprovalController.php
│   │   │       ├── AiController.php
│   │   │       ├── SyncController.php
│   │   │       └── FileController.php
│   │   │
│   │   ├── Middleware/
│   │   │   ├── WorkspaceContext.php
│   │   │   ├── PermissionGate.php
│   │   │   ├── RequestId.php
│   │   │   └── ActivityLogger.php
│   │   │
│   │   ├── Requests/              # Form Request validation classes
│   │   │   ├── Auth/
│   │   │   ├── Workspace/
│   │   │   ├── Product/
│   │   │   ├── Order/
│   │   │   ├── Invoice/
│   │   │   ├── Payment/
│   │   │   └── Ai/
│   │   │
│   │   └── Resources/             # API Resource serializers
│   │       ├── WorkspaceResource.php
│   │       ├── UserResource.php
│   │       ├── ProductResource.php
│   │       ├── OrderResource.php
│   │       ├── InvoiceResource.php
│   │       ├── PaymentResource.php
│   │       ├── AiResource.php
│   │       └── CommonResource.php
│   │
│   ├── Models/
│   │   ├── Workspace.php
│   │   ├── User.php
│   │   ├── Role.php
│   │   ├── Product.php
│   │   ├── InventoryLevel.php
│   │   ├── Order.php
│   │   ├── Invoice.php
│   │   ├── Payment.php
│   │   ├── Account.php
│   │   ├── JournalEntry.php
│   │   ├── ApprovalRequest.php
│   │   ├── AiRequestLog.php
│   │   ├── AuditLog.php
│   │   └── ...                    # One model per DB table
│   │
│   ├── Services/
│   │   ├── AuthService.php
│   │   ├── WorkspaceService.php
│   │   ├── UserService.php
│   │   ├── JoinService.php
│   │   ├── ProductService.php
│   │   ├── InventoryService.php
│   │   ├── OrderService.php
│   │   ├── InvoiceService.php
│   │   ├── PaymentService.php
│   │   ├── AccountingService.php
│   │   ├── DashboardService.php
│   │   ├── NotificationService.php
│   │   ├── ApprovalService.php
│   │   ├── AiOnboardingService.php
│   │   ├── AiChangeService.php
│   │   ├── AiAdvisorService.php
│   │   ├── UiConfigService.php
│   │   ├── OfflineSyncService.php
│   │   └── FileService.php
│   │
│   ├── Repositories/              # Optional repository pattern
│   │   ├── WorkspaceRepository.php
│   │   ├── UserRepository.php
│   │   ├── ProductRepository.php
│   │   ├── InventoryRepository.php
│   │   ├── OrderRepository.php
│   │   ├── InvoiceRepository.php
│   │   ├── PaymentRepository.php
│   │   ├── ApprovalRepository.php
│   │   └── AiRepository.php
│   │
│   ├── AI/
│   │   ├── Client.php
│   │   ├── Prompts/
│   │   ├── Parsers/
│   │   ├── Validators/
│   │   ├── Policies.php
│   │   └── Tools.php
│   │
│   ├── Jobs/
│   │   ├── RefreshBalances.php
│   │   ├── SendNotification.php
│   │   ├── ProcessAiRequest.php
│   │   ├── ProcessSync.php
│   │   ├── RunAnalytics.php
│   │   └── RefreshCache.php
│   │
│   ├── Policies/                  # Laravel authorization policies
│   ├── Providers/
│   ├── Exceptions/
│   │   └── Handler.php
│   └── Console/
│       └── Commands/
│
├── config/
├── database/
│   ├── migrations/
│   ├── seeders/
│   └── factories/
├── routes/
│   ├── api.php
│   └── channels.php
├── tests/
│   ├── Unit/
│   └── Feature/
├── composer.json
├── Dockerfile
└── .env.example
```

## 6. Core Backend Domains

### 6.1 Identity and Access
Responsible for:
- account registration
- login
- refresh tokens
- password reset
- workspace membership
- role assignment
- permission checks
- join code flow
- invite flow
- approval of employee requests

### 6.2 Workspace Management
Responsible for:
- workspace creation
- branding
- workspace settings
- branch setup
- department setup
- shift setup
- subscription state
- AI onboarding state

### 6.3 ERP Operations
Responsible for:
- products
- categories
- units
- contacts
- warehouses
- inventory
- orders
- invoices
- payments
- transactions
- reports
- dashboards

### 6.4 Accounting
Responsible for:
- accounts
- journal entries
- journal lines
- payment postings
- invoice postings
- balance validation
- cached balance refresh jobs

### 6.5 Approval Engine
Responsible for:
- employee approval
- AI change approval
- stock transfer approval
- document approval
- role-sensitive actions

### 6.6 AI System
Responsible for:
- onboarding generation
- workspace configuration suggestions
- dashboard suggestions
- page and field suggestions
- advisory chat
- analytics insights
- structured change requests

### 6.7 Offline Sync
Responsible for:
- pending sales drafts
- sync queue ingestion
- conflict handling
- replaying offline operations safely

---

## 7. Auth Model

### 7.1 Login Strategy
Primary login supports:
- email + password
- phone + password

Later additions:
- phone OTP verification
- email verification
- 2FA for sensitive roles

### 7.2 Account Model
A user account may:
- belong to multiple workspaces
- own multiple workspaces
- hold different roles in different workspaces

### 7.3 Workspace Ownership Rules

#### Owner
Can:
- transfer ownership
- delete workspace
- approve critical AI changes
- manage subscription/billing
- manage co-owners
- access all workspace modules

#### Co-owner
Can:
- manage most operational settings
- manage admins and department heads
- review AI changes
- approve many changes if allowed by policy

Cannot:
- transfer ownership
- delete workspace
- control final billing ownership decisions unless explicitly allowed

#### Admin
Can:
- manage users
- manage approvals
- manage operations
- manage settings allowed by owner

#### Other roles
Controlled through permissions matrix.

---

## 8. Employee Join Flow

### 8.1 Join Code Model
Two mechanisms:

#### Public Workspace Join Code
For normal employees:
- employee enters workspace code
- submits registration request
- request remains pending
- HR / Admin / Department Head approves or rejects

#### Private Invite Code / Link
For sensitive roles:
- HR
- Admin
- Department Head
- Accountant
- Co-owner

Invite flow is safer and role-specific.

### 8.2 Join Request Process
1. employee enters workspace code
2. fills required data
3. request created with pending status
4. approver reviews request
5. if approved:
   - assign role
   - assign branch
   - assign department
   - assign shift if needed
6. user becomes active in workspace

---

## 9. Tenancy Strategy

### 9.1 Database-Level Isolation
Use:
- workspace_id on tenant-scoped tables
- RLS policies
- trigger validation for cross-workspace FK protection
- app-level workspace context

### 9.2 Connection-Level Workspace Context
For every request after authentication:
- determine active workspace
- set DB session variable:
  - `SET app.workspace_id = '<workspace_uuid>'`

### 9.3 Application Enforcement
Every protected endpoint must:
- ensure user is member of workspace
- ensure role/permission allows action
- ensure selected workspace is active

---

## 10. Permission Model

Permissions should be capability-based, not just role-name based.

Examples:
- `users.view`
- `users.create`
- `users.approve`
- `products.manage`
- `inventory.adjust`
- `orders.create`
- `invoices.create`
- `payments.record`
- `reports.view`
- `ai.chat`
- `ai.request_change`
- `ai.approve_change`
- `settings.manage`
- `workspace.manage`
- `ownership.manage`

Role names map to permission bundles.

Also support:
- role-level permissions
- user-level permission overrides

---

## 11. AI Architecture

### 11.1 AI Modes

#### Mode A — Onboarding Builder
Used when owner first creates workspace.

AI does:
- understand business type
- identify relevant modules
- generate workspace setup config
- generate default dashboard config
- generate navigation config
- suggest roles and workflows

Output must be structured JSON only.

#### Mode B — Change Request Assistant
Used when owner says:
- add a page
- hide a page
- add fields
- change layout
- change workflow
- enable module

AI does:
- interpret request
- propose structured change
- classify risk
- generate preview
- submit approval record if needed

#### Mode C — Business Advisor
Used for:
- recommendations
- stock alerts
- pricing suggestions
- expense trends
- anomaly detection
- report explanations

### 11.2 AI Approval Rule
AI changes must not directly apply if they affect:
- permissions
- accounting behavior
- workflow rules
- invoices
- stock deduction rules
- workspace settings
- navigation visibility for critical modules

Such changes must be:
- proposed
- reviewed
- approved
- then applied

### 11.3 AI Output Rules
All AI outputs that drive system behavior must be:
- schema-validated
- risk-classified
- auditable
- stored with request/response metadata
- never blindly executed

---

## 12. UI Configuration Strategy

Backend must store workspace-driven UI configuration.

This includes:
- theme colors
- logo
- enabled modules
- navigation structure
- dashboard widgets
- form schemas
- table schemas
- visibility rules
- feature flags

This config is delivered by API to Flutter clients.

Backend remains source of truth for UI config.

---

## 13. API Design Rules

### 13.1 Versioning
Use:
- `/api/v1/...`

### 13.2 Response Shape
Use consistent response structure where practical:

```json
{
  "success": true,
  "message": "optional",
  "data": {},
  "meta": {}
}
```

### 13.3 Pagination

All list endpoints must support:

* page
* page_size
* sort
* filters
* search

### 13.4 Idempotency

Critical write endpoints should support idempotency where appropriate:

* payments
* offline sync
* invoice creation from POS
* stock transfer confirmation

### 13.5 Transactions

Critical workflows must run in DB transactions:

* invoice + items + payment + journal posting
* stock transfer + inventory movement
* approval action + entity state update
* employee approval + role/branch assignment

---

## 14. Core Backend Services

### 14.1 auth_service

Handles:

* register
* login
* refresh
* reset password
* workspace membership lookup

### 14.2 workspace_service

Handles:

* create workspace
* update branding
* workspace settings
* module enablement
* subscription limits

### 14.3 join_service

Handles:

* join code validation
* employee join requests
* approval/rejection
* invite code flows

### 14.4 inventory_service

Handles:

* stock levels
* stock adjustments
* stock logs
* stock transfers
* batch tracking

### 14.5 invoice_service

Handles:

* invoice creation
* invoice items
* status changes
* returns/refunds
* invoice numbering

### 14.6 payment_service

Handles:

* payment creation
* payment allocation
* payment numbering
* payment posting hooks

### 14.7 accounting_service

Handles:

* journal creation
* journal balance validation
* account balance refresh
* posting logic from ERP actions

### 14.8 approval_service

Handles:

* create approval request
* approve
* reject
* escalation
* approval policy enforcement

### 14.9 ai_onboarding_service

Handles:

* business interview
* business profile extraction
* initial ERP config generation

### 14.10 ai_change_service

Handles:

* interpret requested change
* generate structured diff
* risk analysis
* approval submission
* apply approved config changes

### 14.11 ai_advisor_service

Handles:

* business insights
* anomaly explanations
* KPI summaries
* recommendation generation

### 14.12 offline_sync_service

Handles:

* ingestion of offline events
* deduplication
* reconciliation
* conflict resolution

---

## 15. Offline Support Strategy

Offline support is partial and limited to mobile/POS flows.

### 15.1 Supported Offline Use Cases

* cached product catalog
* cached customer basics if needed
* create cart draft
* create sale draft
* queue pending sync operations
* local receipt draft or pending marker

### 15.2 Not Supported Offline

* AI chat
* deep accounting reports
* payroll processing
* approvals
* admin settings
* critical cross-entity edits
* full CRM management

### 15.3 Sync Model

Client sends:

* `device_id`
* `session_id`
* `operation_id`
* `local_timestamp`
* `payload`
* `last_sync_token`

Backend must:

* validate duplicates
* replay operations safely
* reject conflicts with reason
* return authoritative state

---

## 16. Notification Architecture

Notification types:

* system notifications
* approval notifications
* employee join approval notifications
* stock alerts
* overdue invoice alerts
* AI suggestion notifications
* sync conflict notifications

Delivery methods:

* in-app notifications
* push notifications
* email later

All notifications should be persisted in DB.

---

## 17. Background Jobs

Use background workers for:

* cached balance refresh
* AI analytics
* low-stock scan
* recurring expense reminders
* subscription renewal reminders
* notification fanout
* async file processing
* data cleanup / archival jobs

Avoid heavy synchronous AI calls in user-critical operational endpoints.

---

## 18. Accounting Posting Strategy

ERP actions that should generate accounting entries:

* invoice posting
* payment recording
* refunds
* expense transactions
* asset purchase if enabled
* inventory valuation rules later if applicable

Journal posting must be service-driven and transactional.

Source of truth:

* ledger tables
* not cached balances

Cached balances are convenience fields only.

---

## 19. Audit Logging Rules

Audit logs must be written for:

* login-sensitive events
* role changes
* permission changes
* approvals
* inventory adjustments
* stock transfers
* invoice status changes
* payment recording
* AI-proposed changes
* AI-applied changes
* workspace settings changes

Audit records should capture:

* `workspace_id`
* actor `user_id`
* `action`
* `entity_type`
* `entity_id`
* `old_values`
* `new_values`
* timestamp

---

## 20. Workspace Creation Controls

To prevent abuse and unnecessary AI token consumption:

### Rules

* a new user may create one workspace directly
* additional workspace creation may require:

  * verified email
  * verified phone
  * active plan
  * cooldown
  * internal anti-abuse rule

### AI Consumption Limits

Free plan should limit:

* onboarding attempts
* major AI rebuilds
* heavy advisor usage
* advanced modifications

This must be enforced at backend level.

---

## 21. Error Handling Principles

Backend errors must be:

* predictable
* structured
* safe for client consumption
* logged internally

Categories:

* validation errors
* auth errors
* permission errors
* workspace access errors
* approval required errors
* conflict errors
* AI parsing errors
* sync errors
* internal server errors

Never expose sensitive internal details to clients.

---

## 22. Security Requirements

### 22.1 Core Security

* hashed passwords only
* JWT expiry + refresh rotation
* rate limiting on auth and AI endpoints
* device/session tracking for sensitive roles
* audit logs for critical actions
* file upload validation
* strict permission enforcement

### 22.2 Tenant Security

* workspace membership validation
* RLS enforcement
* DB session workspace binding
* no unscoped queries in repositories

### 22.3 AI Security

* validate all structured outputs
* no blind execution
* approval gate for risky changes
* prompt injection resistance through controlled tool context
* no direct SQL generation from user prompts in production flow

---

## 23. Performance Requirements

System should be designed to scale for:

* many workspaces
* many users per workspace
* growing invoices/orders/payments
* large inventory logs
* many AI requests

Backend performance strategy:

* indexed queries
* pagination
* background jobs
* cached dashboard aggregates where needed
* bounded list endpoints
* selective eager loading
* async endpoints where useful
* separate analytics jobs for heavy calculations

---

## 24. Deployment Boundaries

Single deployable backend service initially is acceptable.

Recommended production components:

* Laravel app container (Nginx + PHP-FPM, or Laravel Octane with FrankenPHP)
* Laravel Queue Worker container (with Horizon dashboard)
* PostgreSQL
* Redis
* object storage (S3)
* monitoring/logging

Later optional separation:

* AI service (may remain a separate Python/Node microservice if beneficial)
* analytics service
* notification service

But not required for v1.

---

## 25. Non-Goals for Initial Backend Version

The initial backend version should not attempt:

* runtime arbitrary code generation
* full offline ERP for all modules
* multi-region infrastructure
* event sourcing everywhere
* microservices from day one
* unlimited AI autonomy

---

## 26. Definition of Done for Backend Foundation

Backend foundation is considered ready when:

* auth works with workspace membership
* workspace creation works
* join code and approval flow work
* RLS and workspace isolation are enforced
* products, inventory, contacts, orders, invoices, payments are operational
* accounting posting basics are operational
* AI onboarding returns structured workspace config
* AI change requests create approval records
* notifications are persisted and deliverable
* offline sync endpoints exist for POS/mobile draft flows
* audit logs exist for sensitive actions

---

## 25. Rate Limiting Policy

All API endpoints must be protected by rate limiting via Laravel `ThrottleRequests` middleware with Redis backend.

### 25.1 Throttle Tiers

| Scope | Limit | Window | Key |
|-------|-------|--------|-----|
| Auth endpoints (`/auth/*`) | 10 requests | per minute | per IP |
| Password reset (`/auth/forgot-password`) | 3 requests | per hour | per email |
| General API (authenticated) | 120 requests | per minute | per user × workspace |
| Heavy operations (reports, exports) | 5 requests | per minute | per user |
| AI chat (`/ai/*`) | Per plan AI quota | daily | per workspace |
| Sync endpoint (`/sync`) | 10 requests | per minute | per device token |
| Payment endpoints (`/payments/*`) | 20 requests | per minute | per workspace |
| Bulk operations | 2 requests | per minute | per user |

### 25.2 Response Headers

All responses include:

```
X-RateLimit-Limit: <max_requests>
X-RateLimit-Remaining: <remaining_requests>
X-RateLimit-Reset: <unix_timestamp>
```

Exceeded limit returns `429 Too Many Requests` with `Retry-After` header.

### 25.3 Implementation

* Use Laravel's built-in `throttle` middleware with named rate limiters
* Store counters in Redis (`cache` connection)
* AI quota uses `subscription_plans.max_ai_requests_daily` (migration 001) as the limit source
* Platform admin endpoints exempt from workspace-level limits (separate tier)

---

## 26. File Storage Strategy

### 26.1 Backend

* **Provider**: S3-compatible object storage (AWS S3, DigitalOcean Spaces, MinIO for self-hosted/dev)
* **Integration**: Laravel Filesystem abstraction (`Storage` facade, `s3` driver)
* **Configuration**: via `.env` (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BUCKET`, `AWS_REGION`)

### 26.2 Path Convention

```
{workspace_id}/{entity_type}/{entity_id}/{uuid}_{original_filename}
```

Example: `a1b2c3d4/invoices/e5f6g7h8/9i0j_receipt.pdf`

### 26.3 Access Control

* **No direct public access** — all files served via pre-signed URLs
* **Pre-signed URL expiry**: 15 minutes (configurable per workspace)
* **Permission check**: user must have view permission on the parent entity to access its attachments
* **Upload validation**: server-side MIME type verification (do not trust client file extension)

### 26.4 Constraints

| Constraint | Value |
|-----------|-------|
| Max file size | 25 MB (configurable per plan via `subscription_plans.features_enabled`) |
| Allowed MIME types | `application/pdf`, `image/png`, `image/jpeg`, `image/webp`, `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, `text/csv`, `application/msword`, `application/vnd.openxmlformats-officedocument.wordprocessingml.document` |
| Max attachments per entity | 10 (configurable) |
| Virus scanning | Optional async queue job (recommended for production) |

### 26.5 Schema Reference

* `attachments` table (base schema) stores: `entity_type`, `entity_id`, `file_name`, `file_path`, `file_size`, `mime_type`
* Files are workspace-scoped via `workspace_id` on the `attachments` table
* RLS policy enforces tenant isolation on attachment metadata

---

## 27. Immediate Next Files That Depend on This Document

After this file, create:

1. `3_api_contracts.md`
2. `7_roles_permissions_matrix.md`
3. `8_ai_system_design.md`
4. `9_app_flow.md`
5. `6_business_rules.md`

These files must stay aligned with this backend architecture.

---

## 28. Search Architecture [Core v1]

### 28.1 Strategy

SmartBiz AI uses a two-phase search strategy:

| Phase | Engine | When |
|-------|--------|------|
| v1 (launch) | PostgreSQL full-text search (`tsvector` + GIN indexes) | Core v1 |
| v2 (scale) | Meilisearch (via Laravel Scout) | Expansion Pack |

### 28.2 SearchService Interface

All search queries MUST go through `App\Services\Search\SearchService`.

```
SearchService
├── PostgresSearchDriver (v1 default)
└── MeilisearchSearchDriver (v2 swap-in)
```

No controller or service may use raw `LIKE '%term%'` or `ILIKE` queries directly. All text search MUST route through the SearchService abstraction.

### 28.3 Indexed Entities (v1)

| Entity | Search Fields | Index Type | Priority |
|--------|--------------|------------|----------|
| `products` | name, sku, description, barcode | GIN tsvector | Critical (POS) |
| `contacts` | name, email, phone, company_name | GIN tsvector | Critical (CRM) |
| `media_assets` | name, tags, description | GIN tsvector | High |
| `orders` | order_number, customer_name | B-tree + partial | High |
| `invoices` | invoice_number | B-tree | Medium |
| `employees` | full_name, employee_number, email | GIN tsvector | Medium |
| `audit_logs` | entity_type, event_type | B-tree composite | Medium |
| `outbound_messages` | recipient_address, subject | GIN tsvector | Medium |

### 28.4 Meilisearch Migration Path

When search volume exceeds PostgreSQL performance targets (>500ms p95 for product search):
1. Deploy Meilisearch instance
2. Register `MeilisearchSearchDriver` in service container
3. Run initial index sync (queue job per entity type)
4. Swap driver via environment variable: `SEARCH_DRIVER=meilisearch`
5. Enable incremental sync via domain event listeners

No application code changes required — only driver swap + index population.

---

## 29. Domain Event Bus [Core v1]

### 29.1 Architecture

SmartBiz AI uses Laravel's native event system with Redis-backed queues as the canonical event bus.

```
Service Layer → dispatch(DomainEvent) → Laravel Event Dispatcher
    ├── Sync Listeners (audit log, validation)
    └── Queued Listeners (notifications, webhooks, automations, sync)
            └── Redis Queue (Laravel Horizon)
                 ├── default queue
                 ├── notifications queue
                 ├── webhooks queue
                 └── integrations queue
```

### 29.2 Canonical Event Envelope

Every domain event MUST conform to this envelope:

```json
{
  "event_id": "uuid",
  "event_type": "domain.entity.action",
  "workspace_id": "uuid",
  "actor_id": "uuid | null",
  "entity_type": "string",
  "entity_id": "uuid",
  "payload": {},
  "occurred_at": "ISO8601",
  "metadata": {
    "source": "api | system | ai | import",
    "correlation_id": "uuid",
    "idempotency_key": "string | null"
  }
}
```

### 29.3 Event Naming Convention

Format: `{domain}.{entity}.{past_tense_verb}`

| Domain | Example Events |
|--------|---------------|
| auth | `auth.user.registered`, `auth.user.logged_in`, `auth.password.reset` |
| workspace | `workspace.workspace.created`, `workspace.membership.approved`, `workspace.membership.removed` |
| sales | `sales.order.confirmed`, `sales.order.cancelled`, `sales.invoice.issued`, `sales.payment.recorded` |
| inventory | `inventory.stock.adjusted`, `inventory.transfer.completed`, `inventory.reorder.triggered` |
| hr | `hr.leave.approved`, `hr.leave.rejected`, `hr.payroll.locked`, `hr.attendance.recorded` |
| finance | `finance.journal.posted`, `finance.period.locked`, `finance.refund.issued` |
| delivery | `delivery.assignment.created`, `delivery.assignment.delivered`, `delivery.assignment.failed` |
| communications | `communications.message.sent`, `communications.message.failed`, `communications.message.delivered` |
| marketing | `marketing.loyalty.points_earned`, `marketing.loyalty.points_redeemed`, `marketing.campaign.launched` |
| compliance | `compliance.pack.installed`, `compliance.tax_rule.created` |
| media | `media.asset.uploaded`, `media.asset.approved`, `media.generation.completed` |
| integrations | `integrations.sync.completed`, `integrations.sync.failed`, `integrations.webhook.delivered` |
| ai | `ai.change.requested`, `ai.change.approved`, `ai.feature_request.captured` |

### 29.4 Reliability Rules

1. Events MUST be dispatched AFTER the DB transaction commits (use Laravel's `afterCommit` trait on queued listeners)
2. Queued listeners MUST implement retry with 3 attempts and exponential backoff
3. Failed events go to `failed_jobs` table with full payload for replay
4. Dead-letter events older than 72 hours generate a platform alert
5. Event dispatch is fire-and-forget from the publisher's perspective — the publisher never waits for listener completion
6. Idempotency: listeners MUST handle duplicate events gracefully (use `event_id` for deduplication where needed)

### 29.5 Subscriber Registry

| Subscriber | Listens To | Queue | Scope |
|------------|-----------|-------|-------|
| AuditLogger | All events in audit categories | sync | Core v1 |
| PlatformEventLogger | All events → `platform_events` table | default | Core v1 |
| NotificationDispatcher | Events with notification rules | notifications | Core v1 |
| WebhookDispatcher | Events matching `webhook_subscriptions.events` | webhooks | Core v1 |
| CommunicationAutomation | Events matching `communication_automations.trigger_event` | default | Expansion Pack |
| IntegrationSync | Events matching sync mapping rules | integrations | Core v1 |
| AIContextCollector | Selected events for advisory enrichment | default | Core v1 |
| SearchIndexer | CUD events on searchable entities | default | Core v1 |

---

## 30. Analytics & Reporting Data Boundary [Core v1 framework]

### 30.1 Connection Strategy

| Query Type | Connection | Latency Target | Examples |
|------------|-----------|----------------|----------|
| Transactional reads | Primary DB | < 50ms | Single order lookup, POS product search |
| List/filter/search | Primary DB | < 200ms | Order list, contact list, message log |
| Dashboard KPIs | Read replica + materialized views | < 500ms | Sales today, pending deliveries, quota usage |
| Operational reports | Read replica | < 5s | Sales summary, inventory report, COD reconciliation |
| Executive analytics | Read replica | < 30s | Revenue trends, churn analysis, campaign metrics |
| Data exports | Read replica (async job) | Background | CSV/XLSX export, regulatory exports |
| AI context queries | Read replica | < 2s | Aggregated summaries for AI advisory |

### 30.2 Laravel Configuration

```php
// config/database.php
'pgsql' => [
    'read' => ['host' => env('DB_READ_HOST', env('DB_HOST'))],
    'write' => ['host' => env('DB_HOST')],
    // ... shared config
],
```

Report services MUST explicitly use `DB::connection('pgsql')->useReadPdo()` or the `readOnly()` scope.

### 30.3 Materialized Views

| View | Refresh Frequency | Source Tables |
|------|-------------------|--------------|
| `mv_daily_sales_summary` | Every 5 minutes | `orders`, `order_items` |
| `mv_inventory_alerts` | Every 15 minutes | `inventory_levels`, `products` |
| `mv_delivery_daily_stats` | Every 5 minutes | `delivery_assignments`, `cod_collections` |
| `mv_loyalty_daily_summary` | Every 30 minutes | `loyalty_transactions` |
| `mv_workspace_usage_stats` | Hourly | `ai_requests`, `outbound_messages`, `media_assets` |

Materialized view refresh is managed by Laravel's task scheduler (`schedule:run`). Refresh commands run on the read replica connection.

### 30.4 Data Warehouse Readiness

Data warehouse (BigQuery/Redshift) is NOT built in v1. Architecture readiness means:
- All domain events follow a canonical envelope (§29) that can feed a CDC pipeline
- All tables have `created_at` / `updated_at` timestamps for incremental extract
- No business logic lives in materialized views — they are performance caches only

---

## 31. Entitlement Resolution Chain [Core v1]

### 31.1 Four-Layer Model

Entitlements are resolved in strict order:

```
Layer 1: Plan Entitlements — what the subscription plan grants
    ↓
Layer 2: Workspace Overrides — platform admin manual overrides
    ↓
Layer 3: Role Permissions — RBAC permission check
    ↓
Layer 4: Usage Quotas — rate limits and consumption caps
```

### 31.2 Resolution Logic

```
can_access(user, feature):
  1. plan = workspace.active_subscription.plan
  2. IF plan.features[feature] == false → 402 (upgrade required)
  3. IF workspace_feature_overrides[feature] exists → use override
  4. IF user lacks RBAC permission for feature → 403 (forbidden)
  5. IF feature has usage quota AND quota exhausted → 429 (quota exceeded)
  6. → ALLOW
```

### 31.3 Entitlement Types

| Type | Source | Denial Code | Example |
|------|--------|-------------|---------|
| Plan entitlement | `subscription_plans.features` | 402 | "Campaigns module requires Business plan" |
| Workspace override | `workspace_feature_overrides` table (future migration) | N/A (override) | "Campaigns enabled for workspace despite Starter plan" |
| Role permission | `roles.permissions` + `user_permission_overrides` | 403 | "You don't have marketing.campaigns.create" |
| Usage quota | `subscription_plans.max_*` + daily counters | 429 | "Daily AI quota exhausted — resets at 00:00 UTC" |

### 31.4 Grace Period Rule

When a workspace downgrades:
- Gated features remain accessible for **7 days** (configurable)
- After grace period, features are locked but data is NOT deleted
- Grace period is tracked via `workspace_subscriptions.grace_ends_at` (existing field)

### 31.5 Trial Rule

- Trial workspaces receive **Business-tier** entitlements for trial duration
- On trial expiry without payment → downgrade to Free-tier entitlements with 7-day grace
- Trial status tracked via `workspace_subscriptions.status = 'trialing'`

### 31.6 Implementation

Entitlement resolution is implemented as a single Laravel middleware: `EntitlementMiddleware`.

```
Route::middleware(['auth', 'workspace', 'entitlement:marketing.campaigns'])
    ->get('/api/v1/marketing/campaigns', ...);
```

The middleware calls `EntitlementService::check($user, $featureKey)` which resolves all 4 layers.

---

## 32. Extension Policy [Core v1 policy]

### 32.1 Closed-Core Architecture

SmartBiz AI follows a **closed-core** extension model. No PHP code may be loaded dynamically at runtime.

### 32.2 Extension Types

| Extension Type | Allowed | Mechanism | Who Builds |
|----------------|---------|-----------|------------|
| Core modules | ✓ | Direct codebase (Laravel modules) | SmartBiz AI team only |
| Expansion Packs | ✓ | Feature-flagged modules in same codebase | SmartBiz AI team only |
| Integration connectors | ✓ | `integration_providers` + `workspace_integrations` | SmartBiz AI team + approved partners |
| Webhook consumers | ✓ | `webhook_subscriptions` (outbound events) | Any workspace admin |
| Inbound API integrations | ✓ | Standard REST API with API keys | Any authorized developer |
| Custom UI plugins | ✗ | Not supported | — |
| Server-side plugins | ✗ | Not supported | — |
| Direct DB access | ✗ (forbidden) | — | — |

### 32.3 Marketplace Readiness

Architecture supports future marketplace without core changes:
- `integration_providers` already has `config_schema` for dynamic credential forms
- Future additions: `provider_type = 'marketplace'`, `published_by`, `marketplace_listings` table
- Future: OAuth2 app authorization for third-party scoped data access

### 32.4 Non-Negotiable Rules

1. No runtime code injection — all extensions are data-driven or API-driven
2. No direct database access for external systems — API only
3. All integration credentials encrypted at rest (BR-INT-003)
4. Webhook payloads follow the canonical event envelope (§29.2)
5. Third-party connectors run in the SmartBiz AI process — there is no plugin sandbox in v1

---

## 33. Task Feed Service [Core v1]

### 33.1 Purpose

A unified "My Tasks" feed that aggregates actionable items from all modules into one view.

### 33.2 Architecture

The task feed is a **read model** — it queries existing source tables, not a separate task entity.

```
TaskFeedService
├── queries approval_requests (pending, for current user)
├── queries delivery_assignments (pending/accepted, for current driver)
├── queries leave_requests (pending, for current manager)
├── queries ai_change_requests (pending, for current admin/owner)
├── queries import_jobs (preview state, for current user)
├── queries media_assets (draft + ai_generated, for approvers)
└── merges + sorts by urgency → created_at DESC
```

### 33.3 Source Entities

| Source Entity | Task Type | Actor | Action |
|---------------|-----------|-------|--------|
| `approval_requests` (pending) | `approval` | Approver | Approve/Reject |
| `delivery_assignments` (pending/accepted) | `delivery` | Driver | Accept/Deliver |
| `leave_requests` (pending) | `leave_review` | Manager | Approve/Reject |
| `ai_change_requests` (pending) | `ai_change` | Admin/Owner | Approve/Reject |
| `import_jobs` (preview) | `import_review` | Importer | Apply/Cancel |
| `media_assets` (draft, ai_generated) | `media_approval` | Approver | Approve/Reject |

### 33.4 API

```
GET /api/v1/tasks/my
  → query: ?type=approval,delivery&status=pending&page=1&page_size=25
  → response: paginated list of task items
  → each item: { task_type, entity_type, entity_id, title, created_at, urgency, action_url }
  → permission: implicit (each source query filters by user's permissions)
```

### 33.5 Performance

- Each source query is independent and runs in parallel (async gather)
- Results are merged and sorted in-memory
- If performance degrades (> 500ms), add `mv_task_feed` materialized view per user

---

*End of infrastructure architecture.*

---

## 34. Advanced Rate Limiting Strategy [Core v1]

> Complements §25 (Rate Limiting Policy) with burst/sustained modeling, per-scope tiers, and abuse detection.

### 34.1 Burst vs Sustained Windows

Each rate limit has two enforcement windows:

| Scope | Burst Window | Burst Limit | Sustained Window | Sustained Limit |
|-------|-------------|-------------|-----------------|-----------------|
| Per-user (general API) | 5 seconds | 20 requests | 1 minute | 120 requests |
| Per-workspace (aggregate) | 5 seconds | 100 requests | 1 minute | 500 requests |
| Per-endpoint (auth) | 10 seconds | 5 requests | 1 hour | 30 requests |
| AI chat (per-workspace) | N/A | N/A | 24 hours | Plan-based quota |
| Webhooks (outbound delivery) | 1 second | 10 deliveries | 1 minute | 100 deliveries |

**Logic**: A request is allowed only if BOTH burst AND sustained windows have remaining capacity. Burst prevents sudden spikes. Sustained prevents gradual abuse.

### 34.2 Redis Sliding Window Implementation

```
Algorithm: Redis sliding window log (ZSET)
Key pattern: ratelimit:{scope}:{identifier}:{window}
  - scope: user, workspace, endpoint, ai
  - identifier: user_id, workspace_id, IP, etc.
  - window: burst, sustained

Operations:
1. ZADD key <timestamp> <request_id>
2. ZREMRANGEBYSCORE key 0 <window_start>
3. ZCARD key → current count
4. IF count >= limit → reject with 429
```

**Why sliding window (not fixed window)**: Fixed windows allow double the limit at window boundaries. Sliding window provides smooth, accurate throttling.

### 34.3 Per-Plan Rate Limit Tiers

| Plan | General API/min | AI Requests/day | Webhook Deliveries/min | Export Jobs/hour |
|------|----------------|-----------------|----------------------|-----------------|
| Free | 60 | 20 | 10 | 2 |
| Starter | 120 | 100 | 50 | 5 |
| Business | 300 | 500 | 200 | 20 |
| Enterprise | 600 | Unlimited | 500 | Unlimited |

Rate limit tiers are derived from `subscription_plans.features` JSONB. The `EntitlementService` (§31) resolves the active plan, and the throttle middleware reads limits from the plan.

### 34.4 Abuse Detection

Beyond per-request throttling, the system monitors for abuse patterns:

| Pattern | Detection | Response |
|---------|-----------|----------|
| Sustained 429 responses (>50 in 10 min) | Redis counter on 429 events | Temporary IP block (15 min), platform alert |
| Credential stuffing (>20 failed logins) | Redis counter per email/IP | CAPTCHA requirement, account lock after 5 more |
| Scraping (sequential resource enumeration) | Request pattern analysis (async job) | 403 + platform alert |
| Webhook flood (receiver returning errors) | Circuit breaker on delivery failures | Pause webhook subscription, notify admin |

### 34.5 Response on Limit Exceeded

```
HTTP/1.1 429 Too Many Requests
Content-Type: application/json
Retry-After: 12
X-RateLimit-Limit: 120
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1712714400

{
  "error_code": "rate_limit",
  "message": "Too many requests. Please retry after 12 seconds.",
  "retry_after_seconds": 12
}
```

For AI quota exhaustion (daily limit), the response uses `quota_exceeded` error code with `resets_at` timestamp (§6 API contracts, §31.3 entitlement types).

---

## 35. Backup & Disaster Recovery Strategy [Core v1]

### 35.1 Backup Frequency

| Component | Method | Frequency | Retention |
|-----------|--------|-----------|-----------|
| PostgreSQL (primary) | Continuous WAL archival (point-in-time recovery) | Continuous | 7 days of WAL segments |
| PostgreSQL (full snapshot) | `pg_basebackup` to object storage | Daily at 02:00 UTC | 30 days |
| PostgreSQL (logical dump) | `pg_dump` per-database | Weekly (Sunday 03:00 UTC) | 90 days |
| Redis | RDB snapshot + AOF | Hourly RDB, continuous AOF | 24 hours (ephemeral cache — loss is acceptable) |
| Object storage (S3/Spaces) | Provider-managed replication | Continuous (provider SLA) | Indefinite |
| Application config / secrets | Encrypted backup to separate vault | On every change (CI/CD triggered) | 365 days |

### 35.2 Retention Policy

| Data Class | Minimum Retention | Rationale |
|------------|-------------------|-----------|
| Full database backup | 30 days | Covers monthly billing cycles and audit windows |
| WAL segments (PITR) | 7 days | Allows point-in-time recovery within a week |
| Logical dumps | 90 days | Quarterly compliance review support |
| Audit logs (in-database) | Per compliance pack (min 7 years) | Regulatory requirement (BR-CMP-003) |
| Media assets (object storage) | Indefinite (until workspace deletion) | Customer data retention |

### 35.3 Restore SLA

| Scenario | Target RTO | Target RPO | Procedure |
|----------|-----------|-----------|-----------|
| Single table corruption | < 1 hour | < 5 minutes (PITR) | Restore table from PITR to staging → verify → swap |
| Full database loss (single region) | < 4 hours | < 5 minutes (PITR) | Provision new instance → restore from WAL → validate → DNS switch |
| Regional outage | < 8 hours | < 1 hour | Promote read replica in secondary region → update DNS |
| Accidental data deletion (user error) | < 2 hours | < 5 minutes (PITR) | PITR restore of affected tables to point before deletion |
| Complete infrastructure failure | < 12 hours | < 1 hour | Full rebuild from latest full backup + WAL replay |

> **RTO** = Recovery Time Objective (maximum downtime). **RPO** = Recovery Point Objective (maximum data loss).

### 35.4 Failover Approach

```
Primary (Region A)
    ├── PostgreSQL primary (writes + reads)
    ├── Redis primary (queues + cache)
    └── Laravel app servers (active)
         ↓ streaming replication
Standby (Region B)
    ├── PostgreSQL read replica (hot standby)
    ├── Redis replica (read-only)
    └── Laravel app servers (warm standby — deployed but not receiving traffic)
```

**Failover trigger conditions**:
1. Primary database unreachable for > 60 seconds (health check failure)
2. Primary region network outage confirmed by cloud provider status
3. Manual failover initiated by platform operator

**Failover procedure**:
1. Promote PostgreSQL read replica to primary (`pg_ctl promote`)
2. Update application `DB_HOST` to point to promoted instance (via DNS/load balancer)
3. Restart Redis with empty cache (cache miss is acceptable — will repopulate)
4. Route traffic to Region B app servers (DNS failover or load balancer weight shift)
5. Verify application health checks pass
6. Notify platform team + broadcast status update

**Failback**: After Region A recovery, establish new replication from B → A, then planned switchover during maintenance window.

### 35.5 Multi-Region Readiness

Multi-region active-active is NOT built in v1. Architecture readiness means:

| Capability | v1 Status | Future-Ready |
|------------|-----------|-------------|
| Read replica in secondary region | ✅ Configured | Serves as failover target |
| Object storage replication | ✅ Provider-managed (S3 cross-region) | Automatic |
| Application statelessness | ✅ No server-side sessions (JWT + Redis) | Can run in any region |
| Database write isolation | Single primary | Future: geo-routing via `workspace.region` field |
| Queue isolation | Single Redis | Future: per-region Redis with cross-region event sync |

### 35.6 Backup Validation

- **Weekly**: Automated restore test to ephemeral environment — verify row counts, run smoke tests
- **Monthly**: Full disaster recovery drill — simulate primary failure, measure actual RTO/RPO
- **Quarterly**: Backup integrity audit — verify encryption, retention compliance, access controls

---

*End of backend architecture. Version 3.1 — 2026-04-10. Added §34 advanced rate limiting, §35 backup & disaster recovery.*