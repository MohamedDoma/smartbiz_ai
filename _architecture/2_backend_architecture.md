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

## 27. Immediate Next Files That Depend on This Document

After this file, create:

1. `3_api_contracts.md`
2. `7_roles_permissions_matrix.md`
3. `8_ai_system_design.md`
4. `9_app_flow.md`
5. `6_business_rules.md`

These files must stay aligned with this backend architecture.