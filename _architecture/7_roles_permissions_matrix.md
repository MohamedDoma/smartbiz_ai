# SmartBiz AI — Roles & Permissions Specification (v1.0)

---

## 1. Introduction & Design Principles

This document is the **authoritative RBAC specification** for SmartBiz AI. All backend permission enforcement, frontend access control, and role management must conform to this specification.

### 1.1 Two-Layer Model

| Layer | Scope | Storage | Isolation |
|-------|-------|---------|-----------|
| **Platform Roles** | Global — SmartBiz AI team only | `platform_users.role` | Not workspace-scoped |
| **Workspace Roles** | Per-tenant — inside a business ERP | `roles.permissions` JSONB via `workspace_memberships` | Workspace-scoped via RLS |

### 1.2 Core Principles

1. **Deny-by-default** — a user has zero permissions unless explicitly granted via role or user-level override.
2. **Additive model** — permissions are granted, never inherited implicitly. Each role has its full permission set listed explicitly.
3. **Scoped access** — every permission grant includes a scope that limits the visible data boundary.
4. **No hierarchy inheritance** — a Department Head does NOT inherit Employee permissions automatically. Each role is self-contained.
5. **Audit everything** — every role assignment, permission change, override, and delegation generates an audit log entry.
6. **Machine-readable** — this spec includes a JSON appendix that backend services consume directly to seed the permission system.

---

## 2. Permission Naming Convention

### 2.1 Format

```
{module}.{entity}.{action}
```

### 2.2 Namespace Levels

| Level | Rule | Examples |
|-------|------|---------|
| **Module** | Top-level business domain, lowercase snake_case | `admin`, `inventory`, `sales`, `finance`, `hr`, `crm`, `manufacturing`, `projects`, `purchasing`, `shared`, `ai`, `reports`, `platform` |
| **Entity** | Resource within the module, plural | `products`, `orders`, `invoices`, `employees`, `leads`, `workspace` |
| **Action** | Operation, from controlled verb list below | `view`, `create`, `update`, `delete` |

### 2.3 Controlled Verb Taxonomy

| Verb | Meaning |
|------|---------|
| `view` | Read/list records |
| `create` | Insert new records |
| `update` | Modify existing records |
| `delete` | Soft-delete or archive records |
| `approve` | Approve a pending request |
| `cancel` | Cancel an active record |
| `process` | Execute a batch/workflow action |
| `transfer` | Move between locations/owners |
| `export` | Export/download data (GDPR-sensitive) |
| `configure` | Change settings/configuration |
| `manage` | Shorthand for view+create+update+delete+configure (admin-level only) |
| `use` | Interact with a system (AI chat) |
| `open` | Start a session |
| `close` | End a session |
| `escalate` | Escalate a request to a higher authority |

No other verbs may be used in permission keys.

---

## 3. Scoped Access Model

### 3.1 Scope Definitions

| Scope Code | Meaning | Filter Logic |
|------------|---------|-------------|
| `ws` | Workspace-wide — all records in the tenant | `WHERE workspace_id = current_workspace` |
| `branch` | All records in the user's assigned branch | `WHERE branch_id = user.branch_id` |
| `dept` | All records in the user's department | `WHERE department_id = user.department_id` |
| `team` | Records of the user's direct reports | `WHERE user_id IN (SELECT id FROM users WHERE manager_id = current_user)` |
| `own` | Only the user's own records | `WHERE created_by = current_user OR assigned_to = current_user OR user_id = current_user` |
| `wh` | Records in the user's assigned warehouse(s) | `WHERE warehouse_id IN (user.warehouse_ids)` |

### 3.2 Scope Resolution Rules

1. If the matrix cell contains a scope code, that is the scope granted.
2. `-` means the permission is denied entirely for that role.
3. Scopes are not cumulative — a user gets exactly the scope their role specifies.
4. If a user has multiple roles (custom configuration), the widest scope wins for each permission.
5. User-level overrides can grant a wider scope than the role default.

### 3.3 Scope Applicability Per Module

| Module | Applicable Scopes |
|--------|-------------------|
| `admin.*` | `ws` only |
| `inventory.*` | `wh`, `branch`, `ws` |
| `sales.*` | `own`, `branch`, `ws` |
| `purchasing.*` | `own`, `ws` |
| `finance.*` | `ws` only |
| `hr.employees.*` | `own`, `dept`, `branch`, `ws` |
| `hr.attendance.*`, `hr.leaves.*` | `own`, `dept`, `branch`, `ws` |
| `hr.payroll.*` | `own`, `ws` |
| `hr.shifts.*` | `ws` only |
| `crm.*` | `own`, `team`, `branch`, `ws` |
| `manufacturing.*` | `ws` only |
| `projects.*` | `own`, `dept`, `ws` |
| `shared.*` | `own`, `ws` |
| `ai.*` | `ws` only |
| `reports.*` | `ws` only |

---

## 4. Permission Key Registry — Workspace Modules

### 4.1 Admin Module (28 keys)

```
admin.workspace.view
admin.workspace.update
admin.workspace.delete
admin.workspace.configure
admin.ownership.transfer
admin.ownership.delete
admin.subscription.view
admin.subscription.manage
admin.branches.view
admin.branches.create
admin.branches.update
admin.branches.delete
admin.departments.view
admin.departments.create
admin.departments.update
admin.departments.delete
admin.roles.view
admin.roles.create
admin.roles.update
admin.roles.delete
admin.roles.assign
admin.users.view
admin.users.create
admin.users.update
admin.users.delete
admin.users.approve
admin.sequences.view
admin.sequences.configure
```

### 4.2 Inventory Module (31 keys)

```
inventory.products.view
inventory.products.create
inventory.products.update
inventory.products.delete
inventory.products.export
inventory.categories.view
inventory.categories.create
inventory.categories.update
inventory.categories.delete
inventory.variants.view
inventory.variants.create
inventory.variants.update
inventory.variants.delete
inventory.warehouses.view
inventory.warehouses.create
inventory.warehouses.update
inventory.warehouses.delete
inventory.levels.view
inventory.levels.adjust
inventory.batches.view
inventory.batches.create
inventory.batches.update
inventory.units.view
inventory.units.create
inventory.units.update
inventory.units.delete
inventory.transfers.view
inventory.transfers.create
inventory.transfers.approve
inventory.logs.view
inventory.logs.export
```

### 4.3 Sales Module (28 keys)

```
sales.orders.view
sales.orders.create
sales.orders.update
sales.orders.cancel
sales.orders.export
sales.pos.view
sales.pos.configure
sales.pos_sessions.open
sales.pos_sessions.close
sales.pos_sessions.view
sales.dining.view
sales.dining.manage
sales.pricing.view
sales.pricing.create
sales.pricing.update
sales.pricing.delete
sales.promotions.view
sales.promotions.create
sales.promotions.update
sales.promotions.delete
sales.coupons.view
sales.coupons.create
sales.coupons.update
sales.coupons.delete
sales.bookings.view
sales.bookings.create
sales.bookings.update
sales.bookings.cancel
```

### 4.4 Purchasing Module (5 keys)

```
purchasing.orders.view
purchasing.orders.create
purchasing.orders.update
purchasing.orders.cancel
purchasing.orders.approve
```

### 4.5 Finance Module (36 keys)

```
finance.invoices.view
finance.invoices.create
finance.invoices.update
finance.invoices.cancel
finance.invoices.approve
finance.invoices.export
finance.payments.view
finance.payments.create
finance.payments.export
finance.transactions.view
finance.transactions.create
finance.transactions.update
finance.transactions.delete
finance.transactions.export
finance.accounts.view
finance.accounts.create
finance.accounts.update
finance.accounts.delete
finance.journal_entries.view
finance.journal_entries.create
finance.journal_entries.approve
finance.journal_entries.export
finance.taxes.view
finance.taxes.create
finance.taxes.update
finance.taxes.delete
finance.fixed_assets.view
finance.fixed_assets.create
finance.fixed_assets.update
finance.fixed_assets.delete
finance.recurring_expenses.view
finance.recurring_expenses.create
finance.recurring_expenses.update
finance.recurring_expenses.delete
finance.reports.view
finance.reports.export
```

### 4.6 HR Module (22 keys)

```
hr.employees.view
hr.employees.create
hr.employees.update
hr.employees.delete
hr.employees.export
hr.attendance.view
hr.attendance.create
hr.attendance.update
hr.attendance.export
hr.leaves.view
hr.leaves.create
hr.leaves.approve
hr.leaves.cancel
hr.leaves.export
hr.payroll.view
hr.payroll.process
hr.payroll.approve
hr.payroll.export
hr.shifts.view
hr.shifts.create
hr.shifts.update
hr.shifts.delete
```

### 4.7 CRM Module (16 keys)

```
crm.leads.view
crm.leads.create
crm.leads.update
crm.leads.delete
crm.leads.export
crm.opportunities.view
crm.opportunities.create
crm.opportunities.update
crm.opportunities.delete
crm.activities.view
crm.activities.create
crm.activities.update
crm.subscriptions.view
crm.subscriptions.create
crm.subscriptions.update
crm.subscriptions.cancel
```

### 4.8 Manufacturing Module (13 keys)

```
manufacturing.bom.view
manufacturing.bom.create
manufacturing.bom.update
manufacturing.bom.delete
manufacturing.production.view
manufacturing.production.create
manufacturing.production.update
manufacturing.production.approve
manufacturing.production.cancel
manufacturing.work_centers.view
manufacturing.work_centers.create
manufacturing.work_centers.update
manufacturing.work_centers.delete
```

### 4.9 Projects Module (8 keys)

```
projects.projects.view
projects.projects.create
projects.projects.update
projects.projects.delete
projects.tasks.view
projects.tasks.create
projects.tasks.update
projects.tasks.delete
```

### 4.10 Shared Module (21 keys)

```
shared.contacts.view
shared.contacts.create
shared.contacts.update
shared.contacts.delete
shared.contacts.export
shared.attachments.view
shared.attachments.create
shared.attachments.delete
shared.notifications.view
shared.notifications.manage
shared.approvals.view
shared.approvals.approve
shared.approvals.override
shared.approvals.manage
shared.approvals.escalate
shared.approvals.configure
shared.audit_logs.view
shared.audit_logs.export
shared.shipments.view
shared.shipments.create
shared.shipments.update
```

### 4.11 AI Module (3 keys)

```
ai.chat.use
ai.changes.request
ai.changes.approve
```

### 4.12 Reports Module (6 keys)

```
reports.operational.view
reports.operational.export
reports.financial.view
reports.financial.export
reports.executive.view
reports.executive.export
```

### 4.13 Communications Module (9 keys) [Core v1]

```
communications.templates.view
communications.templates.create
communications.templates.update
communications.templates.delete
communications.messages.view
communications.messages.send
communications.automations.view
communications.automations.manage
communications.logs.export
```

### 4.14 Marketing Module (14 keys) [Mixed]

```
marketing.campaigns.view              [Expansion Pack]
marketing.campaigns.create            [Expansion Pack]
marketing.campaigns.update            [Expansion Pack]
marketing.campaigns.delete            [Expansion Pack]
marketing.campaigns.launch            [Expansion Pack]
marketing.segments.view               [Core v1]
marketing.segments.manage             [Core v1]
marketing.loyalty.view                [Core v1]
marketing.loyalty.manage              [Core v1]
marketing.referrals.view              [Expansion Pack]
marketing.referrals.manage            [Expansion Pack]
marketing.nurturing.view              [Expansion Pack]
marketing.nurturing.manage            [Expansion Pack]
marketing.analytics.view              [Expansion Pack]
```

### 4.15 Delivery Module (12 keys) [Core v1]

```
delivery.drivers.view
delivery.drivers.manage
delivery.assignments.view
delivery.assignments.create
delivery.assignments.update
delivery.tracking.view
delivery.proof.view
delivery.proof.capture
delivery.cod.view
delivery.cod.reconcile
delivery.zones.manage
delivery.sla.view
```

### 4.16 Compliance Module (8 keys) [Core v1 framework]

```
compliance.packs.view
compliance.packs.install
compliance.tax_rules.view
compliance.tax_rules.manage
compliance.retention.view
compliance.retention.manage
compliance.exports.view
compliance.exports.generate
```

### 4.17 Media Module (7 keys) [Core v1 basic]

```
media.assets.view
media.assets.upload
media.assets.delete
media.generation.request
media.generation.approve
media.brand_kit.view
media.brand_kit.manage
```

### 4.18 Integration Module (10 keys) [Core v1]

```
integrations.providers.view
integrations.connections.manage
integrations.webhooks.view
integrations.webhooks.manage
integrations.import.manage
integrations.export.manage
integrations.sync.view
integrations.sync.trigger
integrations.health.view
integrations.credentials.manage
```

### 4.19 AI Knowledge Module (3 keys) [Expansion Pack]

```
ai.knowledge.view
ai.knowledge.upload
ai.knowledge.manage
```

**Total workspace permission keys: 280** (217 original + 60 expansion + 3 knowledge)

---

## 5. Permission Key Registry — Platform Modules

### 5.1 Workspace Administration (6 keys)

```
platform.workspaces.view
platform.workspaces.inspect
platform.workspaces.suspend
platform.workspaces.reactivate
platform.workspaces.delete
platform.workspaces.impersonate
```

### 5.2 Billing & Subscription (5 keys)

```
platform.billing.plans.view
platform.billing.plans.manage
platform.billing.subscriptions.view
platform.billing.subscriptions.manage
platform.billing.invoices.view
```

### 5.3 Platform User Management (3 keys)

```
platform.users.view
platform.users.manage
platform.users.roles.manage
```

### 5.4 Communication (6 keys)

```
platform.broadcasts.view
platform.broadcasts.create
platform.broadcasts.send
platform.surveys.view
platform.surveys.manage
platform.surveys.view_responses
```

### 5.5 Monitoring & Analytics (5 keys)

```
platform.events.view
platform.events.export
platform.analytics.view
platform.ai_logs.view
platform.ai_logs.export
```

### 5.6 Feature & Config Management (8 keys)

```
platform.feature_requests.view
platform.feature_requests.manage
platform.feature_requests.roadmap
platform.system.feature_flags
platform.system.health
platform.system.migrations
platform.system.jobs
platform.system.config
```

### 5.7 Expansion Domain Management (4 keys)

```
platform.integrations.catalog.manage
platform.country_packs.manage
platform.country_packs.publish
platform.media.quotas.manage
```

**Total platform permission keys: 37** (33 original + 4 expansion)

---

## 6. Platform Roles & Permission Mappings

### 6.1 Platform Role Definitions

| Role | Description | `hierarchy_level` |
|------|------------|-------------------|
| `platform_owner` | Super administrator of the entire SmartBiz AI platform | 100 |
| `platform_admin` | Operates the platform day-to-day: workspace management, broadcasts, surveys | 80 |
| `platform_support` | Customer support: inspect workspaces, debug issues, read-only | 60 |
| `platform_operations` | Monitors performance, analytics, system health | 50 |
| `platform_engineer` | Engineering team: feature flags, migrations, system config, job queues | 70 |

### 6.2 Platform Permissions Matrix

| Permission | P.Owner | P.Admin | P.Support | P.Ops | P.Eng |
|------------|---------|---------|-----------|-------|-------|
| platform.workspaces.view | ✅ | ✅ | ✅ | ✅ | ✅ |
| platform.workspaces.inspect | ✅ | ✅ | ✅ | - | ✅ |
| platform.workspaces.suspend | ✅ | ✅ | - | - | - |
| platform.workspaces.reactivate | ✅ | ✅ | - | - | - |
| platform.workspaces.delete | ✅ | - | - | - | - |
| platform.workspaces.impersonate | ✅ | - | ✅ | - | - |
| platform.billing.plans.view | ✅ | ✅ | - | - | - |
| platform.billing.plans.manage | ✅ | - | - | - | - |
| platform.billing.subscriptions.view | ✅ | ✅ | ✅ | - | - |
| platform.billing.subscriptions.manage | ✅ | - | - | - | - |
| platform.billing.invoices.view | ✅ | ✅ | - | - | - |
| platform.users.view | ✅ | ✅ | - | - | - |
| platform.users.manage | ✅ | - | - | - | - |
| platform.users.roles.manage | ✅ | - | - | - | - |
| platform.broadcasts.view | ✅ | ✅ | ✅ | - | - |
| platform.broadcasts.create | ✅ | ✅ | - | - | - |
| platform.broadcasts.send | ✅ | ✅ | - | - | - |
| platform.surveys.view | ✅ | ✅ | - | - | - |
| platform.surveys.manage | ✅ | ✅ | - | - | - |
| platform.surveys.view_responses | ✅ | ✅ | - | - | - |
| platform.events.view | ✅ | ✅ | ✅ | ✅ | ✅ |
| platform.events.export | ✅ | ✅ | - | ✅ | ✅ |
| platform.analytics.view | ✅ | ✅ | - | ✅ | ✅ |
| platform.ai_logs.view | ✅ | ✅ | - | ✅ | ✅ |
| platform.ai_logs.export | ✅ | - | - | ✅ | ✅ |
| platform.feature_requests.view | ✅ | ✅ | ✅ | - | - |
| platform.feature_requests.manage | ✅ | ✅ | - | - | - |
| platform.feature_requests.roadmap | ✅ | ✅ | - | - | - |
| platform.system.feature_flags | ✅ | - | - | - | ✅ |
| platform.system.health | ✅ | - | - | ✅ | ✅ |
| platform.system.migrations | ✅ | - | - | - | ✅ |
| platform.system.jobs | ✅ | - | - | ✅ | ✅ |
| platform.system.config | ✅ | - | - | - | ✅ |

---

## 7. Workspace Role Templates

### 7.1 Role Summary

| # | Role Key | Display Name | `hierarchy_level` | `is_system` | Deletable |
|---|----------|--------------|--------------------|-------------|-----------|
| 1 | `owner` | Owner | 100 | true | false |
| 2 | `co_owner` | Co-Owner | 90 | true | false |
| 3 | `admin` | Administrator | 80 | true | true |
| 4 | `branch_manager` | Branch Manager | 70 | false | true |
| 5 | `department_head` | Department Head | 65 | false | true |
| 6 | `hr_manager` | HR Manager | 60 | false | true |
| 7 | `accountant` | Accountant | 60 | false | true |
| 8 | `sales_manager` | Sales Manager | 55 | false | true |
| 9 | `purchasing_officer` | Purchasing Officer | 55 | false | true |
| 10 | `warehouse_manager` | Warehouse Manager | 55 | false | true |
| 11 | `production_manager` | Production Manager | 55 | false | true |
| 12 | `sales_rep` | Sales Representative | 40 | false | true |
| 13 | `warehouse_staff` | Warehouse Staff | 40 | false | true |
| 14 | `cashier` | Cashier | 40 | false | true |
| 15 | `employee` | Employee | 20 | false | true |
| 16 | `investor` | Investor / Executive | 15 | false | true |
| 17 | `viewer` | Viewer | 10 | false | true |
| 18 | `dispatcher` | Dispatcher | 45 | false | true |
| 19 | `driver` | Driver | 30 | false | true |

### 7.2 Role Assignment Rules

- A user can only assign roles with a `hierarchy_level` lower than or equal to their own.
- Every workspace must have at least one `owner`.
- `owner` and `co_owner` are system roles that cannot be deleted.
- Custom roles created by the workspace inherit `is_system = false` and `deletable = true`.
- Custom roles can be cloned from any template role and then modified.

---

## 8. Workspace Permissions Matrix

### Legend

- **Scope code** in cell = permission granted at that scope
- **-** = permission denied for this role
- Scope codes: `ws` (workspace), `branch`, `dept`, `team`, `own`, `wh` (warehouse)

**Role abbreviations used in column headers:**

| Abbr | Role |
|------|------|
| OWN | owner |
| COW | co_owner |
| ADM | admin |
| BRM | branch_manager |
| DH | department_head |
| HRM | hr_manager |
| ACC | accountant |
| SM | sales_manager |
| SR | sales_rep |
| PO | purchasing_officer |
| WHM | warehouse_manager |
| WHS | warehouse_staff |
| PRM | production_manager |
| CSH | cashier |
| EMP | employee |
| INV | investor |
| VW | viewer |
| DSP | dispatcher |
| DRV | driver |

---

### 8.1 Admin Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| admin.workspace.view | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws |
| admin.workspace.configure | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.ownership.transfer | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.ownership.delete | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.subscription.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | ws | - |
| admin.subscription.manage | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.branches.view | ws | ws | ws | ws | - | - | - | ws | - | - | ws | - | - | branch | - | - | ws |
| admin.branches.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.branches.update | ws | ws | ws | branch | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.branches.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.departments.view | ws | ws | ws | branch | dept | ws | - | - | - | - | - | - | - | - | - | - | ws |
| admin.departments.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.departments.update | ws | ws | ws | - | dept | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.departments.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.roles.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.roles.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.roles.update | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.roles.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.users.view | ws | ws | ws | branch | dept | ws | - | team | - | - | - | - | - | - | own | - | - |
| admin.users.create | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| admin.users.update | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | own | - | - |
| admin.users.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| admin.users.approve | ws | ws | ws | branch | dept | ws | - | - | - | - | - | - | - | - | - | - | - |
| admin.sequences.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| admin.sequences.configure | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.2 Inventory Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| inventory.products.view | ws | ws | ws | branch | - | - | ws | ws | ws | ws | ws | wh | ws | ws | - | - | ws |
| inventory.products.create | ws | ws | ws | - | - | - | - | - | - | ws | ws | - | ws | - | - | - | - |
| inventory.products.update | ws | ws | ws | - | - | - | - | - | - | ws | ws | - | ws | - | - | - | - |
| inventory.products.delete | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.products.export | ws | ws | ws | - | - | - | - | - | - | ws | ws | - | - | - | - | - | - |
| inventory.categories.view | ws | ws | ws | - | - | - | - | ws | ws | ws | ws | wh | ws | ws | - | - | ws |
| inventory.categories.create | ws | ws | ws | - | - | - | - | - | - | - | ws | - | ws | - | - | - | - |
| inventory.categories.update | ws | ws | ws | - | - | - | - | - | - | - | ws | - | ws | - | - | - | - |
| inventory.categories.delete | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.variants.view | ws | ws | ws | branch | - | - | - | ws | ws | ws | ws | wh | ws | ws | - | - | - |
| inventory.variants.create | ws | ws | ws | - | - | - | - | - | - | ws | ws | - | ws | - | - | - | - |
| inventory.variants.update | ws | ws | ws | - | - | - | - | - | - | ws | ws | - | ws | - | - | - | - |
| inventory.variants.delete | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.warehouses.view | ws | ws | ws | branch | - | - | - | - | - | ws | ws | wh | ws | - | - | - | ws |
| inventory.warehouses.create | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.warehouses.update | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.warehouses.delete | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.levels.view | ws | ws | ws | branch | - | - | ws | - | - | ws | ws | wh | ws | - | - | - | - |
| inventory.levels.adjust | ws | ws | ws | - | - | - | - | - | - | - | ws | wh | ws | - | - | - | - |
| inventory.batches.view | ws | ws | ws | branch | - | - | - | - | - | ws | ws | wh | ws | - | - | - | - |
| inventory.batches.create | ws | ws | ws | - | - | - | - | - | - | ws | ws | wh | ws | - | - | - | - |
| inventory.batches.update | ws | ws | ws | - | - | - | - | - | - | - | ws | wh | ws | - | - | - | - |
| inventory.units.view | ws | ws | ws | - | - | - | - | ws | ws | ws | ws | ws | ws | ws | - | - | - |
| inventory.units.create | ws | ws | ws | - | - | - | - | - | - | - | ws | - | ws | - | - | - | - |
| inventory.units.update | ws | ws | ws | - | - | - | - | - | - | - | ws | - | ws | - | - | - | - |
| inventory.units.delete | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.transfers.view | ws | ws | ws | branch | - | - | - | - | - | ws | ws | wh | ws | - | - | - | - |
| inventory.transfers.create | ws | ws | ws | - | - | - | - | - | - | ws | ws | wh | - | - | - | - | - |
| inventory.transfers.approve | ws | ws | ws | branch | - | - | - | - | - | - | ws | - | - | - | - | - | - |
| inventory.logs.view | ws | ws | ws | branch | - | - | ws | - | - | ws | ws | wh | ws | - | - | - | - |
| inventory.logs.export | ws | ws | ws | - | - | - | - | - | - | - | ws | - | - | - | - | - | - |

### 8.3 Sales Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sales.orders.view | ws | ws | ws | branch | - | - | ws | ws | own | - | - | - | - | branch | - | - | ws |
| sales.orders.create | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | branch | - | - | - |
| sales.orders.update | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| sales.orders.cancel | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.orders.export | ws | ws | ws | - | - | - | ws | ws | - | - | - | - | - | - | - | - | - |
| sales.pos.view | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | branch | - | - | - |
| sales.pos.configure | ws | ws | ws | branch | - | - | - | - | - | - | - | - | - | - | - | - | - |
| sales.pos_sessions.open | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | branch | - | - | - |
| sales.pos_sessions.close | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | branch | - | - | - |
| sales.pos_sessions.view | ws | ws | ws | branch | - | - | ws | ws | own | - | - | - | - | own | - | - | - |
| sales.dining.view | ws | ws | ws | branch | - | - | - | ws | ws | - | - | - | - | branch | - | - | - |
| sales.dining.manage | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.pricing.view | ws | ws | ws | branch | - | - | ws | ws | ws | ws | - | - | - | ws | - | - | - |
| sales.pricing.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.pricing.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.pricing.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.promotions.view | ws | ws | ws | branch | - | - | - | ws | ws | - | - | - | - | ws | - | - | - |
| sales.promotions.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.promotions.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.promotions.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.coupons.view | ws | ws | ws | branch | - | - | - | ws | ws | - | - | - | - | ws | - | - | - |
| sales.coupons.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.coupons.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.coupons.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| sales.bookings.view | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | branch | - | - | ws |
| sales.bookings.create | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | branch | - | - | - |
| sales.bookings.update | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| sales.bookings.cancel | ws | ws | ws | branch | - | - | - | ws | - | - | - | - | - | - | - | - | - |

### 8.4 Purchasing Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| purchasing.orders.view | ws | ws | ws | branch | - | - | ws | - | - | ws | ws | - | ws | - | - | - | - |
| purchasing.orders.create | ws | ws | ws | - | - | - | - | - | - | ws | - | - | ws | - | - | - | - |
| purchasing.orders.update | ws | ws | ws | - | - | - | - | - | - | ws | - | - | - | - | - | - | - |
| purchasing.orders.cancel | ws | ws | ws | - | - | - | - | - | - | ws | - | - | - | - | - | - | - |
| purchasing.orders.approve | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.5 Finance Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| finance.invoices.view | ws | ws | ws | branch | - | - | ws | ws | own | ws | - | - | - | - | - | ws | - |
| finance.invoices.create | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.invoices.update | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.invoices.cancel | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.invoices.approve | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.invoices.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.payments.view | ws | ws | ws | branch | - | - | ws | - | - | - | - | - | - | own | - | ws | - |
| finance.payments.create | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | branch | - | - | - |
| finance.payments.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.transactions.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.transactions.create | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.transactions.update | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.transactions.delete | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.transactions.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.accounts.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.accounts.create | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.accounts.update | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.accounts.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.journal_entries.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.journal_entries.create | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.journal_entries.approve | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.journal_entries.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.taxes.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.taxes.create | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.taxes.update | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.taxes.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.fixed_assets.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.fixed_assets.create | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.fixed_assets.update | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.fixed_assets.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.recurring_expenses.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.recurring_expenses.create | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.recurring_expenses.update | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| finance.recurring_expenses.delete | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| finance.reports.view | ws | ws | ws | branch | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| finance.reports.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |

### 8.6 HR Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| hr.employees.view | ws | ws | ws | branch | dept | ws | - | team | - | - | - | - | - | - | own | - | - |
| hr.employees.create | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.employees.update | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | own | - | - |
| hr.employees.delete | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.employees.export | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.attendance.view | ws | ws | ws | branch | dept | ws | - | team | - | - | - | - | - | - | own | - | - |
| hr.attendance.create | ws | ws | ws | branch | - | ws | - | - | - | - | - | - | - | - | own | - | - |
| hr.attendance.update | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.attendance.export | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.leaves.view | ws | ws | ws | branch | dept | ws | - | team | - | - | - | - | - | - | own | - | - |
| hr.leaves.create | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | own | - | - |
| hr.leaves.approve | ws | ws | ws | branch | dept | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.leaves.export | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.payroll.view | ws | ws | ws | - | - | ws | ws | - | - | - | - | - | - | - | own | - | - |
| hr.payroll.process | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.payroll.export | ws | ws | ws | - | - | ws | ws | - | - | - | - | - | - | - | - | - | - |
| hr.shifts.view | ws | ws | ws | branch | dept | ws | - | - | - | - | - | - | - | - | own | - | - |
| hr.shifts.create | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.shifts.update | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| hr.shifts.delete | ws | ws | ws | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |

### 8.7 CRM Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| crm.leads.view | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.leads.create | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.leads.update | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.leads.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| crm.leads.export | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| crm.opportunities.view | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.opportunities.create | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.opportunities.update | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.opportunities.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| crm.activities.view | ws | ws | ws | branch | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.activities.create | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.activities.update | ws | ws | ws | - | - | - | - | ws | own | - | - | - | - | - | - | - | - |
| crm.subscriptions.view | ws | ws | ws | branch | - | - | ws | ws | own | - | - | - | - | - | - | - | - |
| crm.subscriptions.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| crm.subscriptions.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| crm.subscriptions.cancel | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |

### 8.8 Manufacturing Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| manufacturing.bom.view | ws | ws | ws | - | - | - | ws | - | - | ws | ws | - | ws | - | - | - | - |
| manufacturing.bom.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.bom.update | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.bom.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.production.view | ws | ws | ws | - | - | - | ws | - | - | - | ws | - | ws | - | - | - | - |
| manufacturing.production.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.production.update | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.production.cancel | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.work_centers.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.work_centers.create | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.work_centers.update | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |
| manufacturing.work_centers.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | ws | - | - | - | - |

### 8.9 Projects Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| projects.projects.view | ws | ws | ws | branch | dept | - | - | ws | own | - | - | - | ws | - | own | - | ws |
| projects.projects.create | ws | ws | ws | branch | dept | - | - | ws | - | - | - | - | ws | - | - | - | - |
| projects.projects.update | ws | ws | ws | branch | dept | - | - | ws | - | - | - | - | ws | - | - | - | - |
| projects.projects.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| projects.tasks.view | ws | ws | ws | branch | dept | - | - | ws | own | - | - | - | ws | - | own | - | ws |
| projects.tasks.create | ws | ws | ws | branch | dept | - | - | ws | own | - | - | - | ws | - | - | - | - |
| projects.tasks.update | ws | ws | ws | branch | dept | - | - | ws | own | - | - | - | ws | - | own | - | - |
| projects.tasks.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | ws | - | - | - | - |

### 8.10 Shared Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| shared.contacts.view | ws | ws | ws | branch | - | - | ws | ws | own | ws | - | - | - | - | - | - | ws |
| shared.contacts.create | ws | ws | ws | branch | - | - | - | ws | own | ws | - | - | - | - | - | - | - |
| shared.contacts.update | ws | ws | ws | branch | - | - | - | ws | own | ws | - | - | - | - | - | - | - |
| shared.contacts.delete | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - |
| shared.contacts.export | ws | ws | ws | - | - | - | - | ws | - | ws | - | - | - | - | - | - | - |
| shared.attachments.view | ws | ws | ws | ws | ws | ws | ws | ws | own | ws | ws | wh | ws | - | own | - | - |
| shared.attachments.create | ws | ws | ws | ws | ws | ws | ws | ws | own | ws | ws | wh | ws | - | own | - | - |
| shared.attachments.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| shared.notifications.view | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | own | ws | ws |
| shared.notifications.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| shared.approvals.view | ws | ws | ws | branch | dept | ws | ws | ws | own | ws | ws | - | ws | - | own | - | - |
| shared.approvals.manage | ws | ws | ws | branch | dept | ws | ws | ws | - | ws | ws | - | ws | - | - | - | - |
| shared.approvals.escalate | ws | ws | ws | branch | dept | ws | ws | ws | - | ws | ws | - | ws | - | - | - | - |
| shared.approvals.configure | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| shared.audit_logs.view | ws | ws | ws | branch | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| shared.audit_logs.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - |
| shared.shipments.view | ws | ws | ws | branch | - | - | ws | ws | own | ws | ws | - | - | - | - | - | - |
| shared.shipments.create | ws | ws | ws | - | - | - | - | ws | - | ws | ws | - | - | - | - | - | - |
| shared.shipments.update | ws | ws | ws | - | - | - | - | ws | - | ws | ws | - | - | - | - | - | - |

### 8.11 AI Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ai.chat.use | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | ws | - | - |
| ai.changes.request | ws | ws | ws | ws | ws | ws | ws | ws | - | - | ws | - | ws | - | - | - | - |
| ai.changes.approve | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.12 Reports Module

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| reports.operational.view | ws | ws | ws | branch | dept | ws | - | ws | own | ws | ws | wh | ws | branch | - | - | ws |
| reports.operational.export | ws | ws | ws | branch | - | ws | - | ws | - | - | ws | - | ws | - | - | - | - |
| reports.financial.view | ws | ws | ws | branch | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| reports.financial.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| reports.executive.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - |
| reports.executive.export | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - | - | - |

### 8.13 Communications Module [Core v1]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| communications.templates.view | ws | ws | ws | ws | ws | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - |
| communications.templates.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| communications.templates.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| communications.templates.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| communications.messages.view | ws | ws | ws | branch | dept | ws | ws | ws | own | - | - | - | - | - | - | - | - | - | - |
| communications.messages.send | ws | ws | ws | branch | - | ws | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| communications.automations.view | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| communications.automations.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| communications.logs.export | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.14 Marketing Module [Mixed]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| marketing.campaigns.view | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.campaigns.create | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.campaigns.update | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.campaigns.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| marketing.campaigns.launch | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| marketing.segments.view | ws | ws | ws | branch | - | - | - | ws | ws | - | - | - | - | - | - | - | - | - | - |
| marketing.segments.manage | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.loyalty.view | ws | ws | ws | branch | - | - | - | ws | ws | - | - | - | - | ws | - | - | - | - | - |
| marketing.loyalty.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| marketing.referrals.view | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.referrals.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| marketing.nurturing.view | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| marketing.nurturing.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| marketing.analytics.view | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | ws | - | - | - |

### 8.15 Delivery Module [Core v1]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| delivery.drivers.view | ws | ws | ws | branch | - | - | - | - | - | - | ws | - | - | - | - | - | - | ws | own |
| delivery.drivers.manage | ws | ws | ws | branch | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| delivery.assignments.view | ws | ws | ws | branch | - | - | - | ws | - | - | ws | - | - | - | - | - | - | ws | own |
| delivery.assignments.create | ws | ws | ws | branch | - | - | - | ws | - | - | ws | - | - | - | - | - | - | ws | - |
| delivery.assignments.update | ws | ws | ws | branch | - | - | - | - | - | - | - | - | - | - | - | - | - | ws | own |
| delivery.tracking.view | ws | ws | ws | branch | - | - | - | ws | - | - | ws | - | - | - | - | - | - | ws | own |
| delivery.proof.view | ws | ws | ws | branch | - | - | - | ws | - | - | ws | - | - | - | - | - | - | ws | own |
| delivery.proof.capture | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | own |
| delivery.cod.view | ws | ws | ws | branch | - | - | ws | - | - | - | ws | - | - | - | - | - | - | ws | own |
| delivery.cod.reconcile | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - | - |
| delivery.zones.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| delivery.sla.view | ws | ws | ws | branch | - | - | - | ws | - | - | ws | - | - | - | - | - | - | ws | - |

### 8.16 Compliance Module [Core v1 framework]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| compliance.packs.view | ws | ws | ws | - | - | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - |
| compliance.packs.install | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| compliance.tax_rules.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | ws | - | - | - |
| compliance.tax_rules.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| compliance.retention.view | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - | - |
| compliance.retention.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| compliance.exports.view | ws | ws | ws | - | - | ws | ws | - | - | - | - | - | - | - | - | ws | - | - | - |
| compliance.exports.generate | ws | ws | ws | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.17 Media Module [Core v1 basic]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| media.assets.view | ws | ws | ws | ws | ws | ws | ws | ws | ws | - | - | - | - | - | - | - | - | - | - |
| media.assets.upload | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| media.assets.delete | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| media.generation.request | ws | ws | ws | - | - | - | - | ws | - | - | - | - | - | - | - | - | - | - | - |
| media.generation.approve | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| media.brand_kit.view | ws | ws | ws | ws | ws | ws | ws | ws | ws | - | - | - | - | - | - | - | - | - | - |
| media.brand_kit.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

### 8.18 Integration Module [Core v1]

| Permission | OWN | COW | ADM | BRM | DH | HRM | ACC | SM | SR | PO | WHM | WHS | PRM | CSH | EMP | INV | VW | DSP | DRV |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| integrations.providers.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.connections.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.webhooks.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.webhooks.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.import.manage | ws | ws | ws | - | - | - | ws | - | - | ws | ws | - | - | - | - | - | - | - | - |
| integrations.export.manage | ws | ws | ws | - | - | ws | ws | - | - | - | - | - | - | - | - | ws | - | - | - |
| integrations.sync.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.sync.trigger | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.health.view | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| integrations.credentials.manage | ws | ws | ws | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |

---

## 9. Custom Roles & User Overrides

### 9.1 Custom Workspace Roles

Workspace admins and owners may create custom roles beyond the 17 templates.

**Creation rules:**
1. Custom roles inherit `is_system = false` and `deletable = true`.
2. Custom roles must have a unique name within the workspace.
3. Custom roles can be cloned from any template role, then modified.
4. Custom roles must be assigned a `hierarchy_level` between 1 and 99.
5. Permissions are cherry-picked from the registry — only registered permission keys are valid.
6. SoD conflict checks (Section 11) apply to custom roles.

**Storage format (in `roles.permissions` JSONB):**

```json
{
  "inventory.products.view": { "scope": "ws" },
  "inventory.products.create": { "scope": "ws" },
  "sales.orders.view": { "scope": "branch" },
  "sales.orders.create": { "scope": "branch" },
  "finance.invoices.view": { "scope": "ws" }
}
```

### 9.2 User-Level Permission Overrides

Individual users can receive permission grants or denials that override their role.

**Grant structure (stored in user-level `permissions` JSONB):**

```json
{
  "grants": {
    "inventory.levels.view": { "scope": "ws", "reason": "Temporary audit access", "granted_by": "uuid", "granted_at": "2026-04-01T00:00:00Z" }
  },
  "denials": {
    "finance.payments.create": { "reason": "SoD restriction", "denied_by": "uuid", "denied_at": "2026-04-01T00:00:00Z" }
  }
}
```

**Resolution order:**
1. Check user-level denials first — if denied, permission is blocked regardless of role.
2. Check user-level grants — if granted, permission is allowed at the specified scope.
3. Check role permissions — if present, permission is allowed at the role-specified scope.
4. Otherwise, deny (deny-by-default).

---

## 10. Temporary Permissions & Delegation

### 10.1 Temporary Permission Grants

Stored in `temporary_permission_grants` table.

| Field | Type | Description |
|-------|------|------------|
| `id` | UUID | Primary key |
| `workspace_id` | UUID | Workspace |
| `user_id` | UUID | Recipient |
| `permission` | VARCHAR | Permission key |
| `scope` | VARCHAR | Scope code |
| `granted_by` | UUID | Who granted |
| `reason` | TEXT | Justification |
| `valid_from` | TIMESTAMPTZ | Start |
| `valid_until` | TIMESTAMPTZ | Expiry |
| `created_at` | TIMESTAMPTZ | Created |

**Rules:**
1. Backend checks `valid_until` on every permission evaluation.
2. A background job revokes expired grants and logs the revocation.
3. All grants are audit-logged on creation, use, and expiry.
4. Only users with `admin.roles.update` can create temporary grants.
5. Temporary grants cannot exceed the grantor's own scope.

### 10.2 Permission Delegation

Stored in `permission_delegations` table.

| Field | Type | Description |
|-------|------|------------|
| `id` | UUID | Primary key |
| `workspace_id` | UUID | Workspace |
| `delegator_id` | UUID | Who delegates |
| `delegate_id` | UUID | Who receives |
| `permissions` | JSONB | Array of permission keys |
| `scope` | VARCHAR | Max scope (cannot exceed delegator's scope) |
| `valid_from` | TIMESTAMPTZ | Start |
| `valid_until` | TIMESTAMPTZ | Expiry |
| `reason` | TEXT | Justification |
| `created_at` | TIMESTAMPTZ | Created |

**Rules:**
1. A user can only delegate permissions they themselves hold.
2. Delegated scope cannot exceed the delegator's scope.
3. Delegations auto-expire at `valid_until`.
4. The delegator can revoke at any time.
5. All delegations are audit-logged.
6. Common use case: department head delegates `hr.leaves.approve` to a senior team member during vacation.

---

## 11. Separation of Duties Rules

### 11.1 Forbidden Permission Combinations

| # | Permission A | Permission B | Severity | Rationale |
|---|-------------|-------------|----------|-----------|
| 1 | `finance.invoices.create` | `finance.payments.create` | CRITICAL | Create fake invoice and self-pay |
| 2 | `admin.users.create` | `admin.users.approve` | CRITICAL | Create ghost employees and self-approve |
| 3 | `finance.journal_entries.create` | `finance.accounts.create` | HIGH | Create fake accounts and post fraudulent entries |
| 4 | `inventory.levels.adjust` | `inventory.products.delete` | HIGH | Adjust stock then delete the product to hide theft |
| 5 | `finance.invoices.create` | `finance.invoices.approve` | HIGH | Self-approve own invoices |
| 6 | `admin.roles.create` | `admin.roles.update` + any CRITICAL permission | HIGH | Create a new role with elevated permissions for self |
| 7 | `hr.payroll.process` | `hr.employees.create` | HIGH | Create phantom employee and process salary |
| 8 | `purchasing.orders.create` | `finance.payments.create` | HIGH | Create PO for phantom supplier and self-pay |

### 11.2 Enforcement Mechanism

| Severity | Behavior |
|----------|----------|
| **CRITICAL** | Block role save. Only the workspace owner can override with documented reason. Override is audit-logged with `action = 'sod_override'`. |
| **HIGH** | Warn admin on role save. Allow save if admin acknowledges the risk. Acknowledgment is audit-logged with `action = 'sod_acknowledge'`. |

### 11.3 Audit Log Entry for SoD

```json
{
  "action": "sod_override",
  "entity_type": "role",
  "entity_id": "role-uuid",
  "old_values": null,
  "new_values": {
    "conflict": ["finance.invoices.create", "finance.payments.create"],
    "severity": "CRITICAL",
    "override_reason": "Small business with single accountant",
    "overridden_by": "owner-uuid"
  }
}
```

---

## 12. Approval & Escalation Permissions

### 12.1 Approval Rules

| Entity Type | Condition | Step 1 Approver Role | Step 2 Approver Role | Auto-escalate After |
|-------------|-----------|---------------------|---------------------|---------------------|
| `leave` | any | `department_head` OR `hr_manager` | `admin` | 48 hours |
| `stock_transfer` | any | `warehouse_manager` | `admin` | 24 hours |
| `purchase_order` | amount ≤ 5000 | `purchasing_officer` | — | — |
| `purchase_order` | amount > 5000 | `purchasing_officer` | `admin` OR `owner` | 48 hours |
| `invoice_cancel` | any | `accountant` | `owner` | 24 hours |
| `payment` | amount ≤ 10000 | `accountant` | — | — |
| `payment` | amount > 10000 | `accountant` | `owner` | 24 hours |
| `journal_entry` | any | `accountant` (must not be creator) | — | — |
| `user_join` | any | `hr_manager` OR `admin` | `owner` | 72 hours |
| `ai_system_change` | any | `owner` OR `co_owner` | — | — |
| `production_order` | any | `production_manager` | `admin` | 48 hours |

### 12.2 Approval Permission Keys

| Permission | Who Gets It |
|------------|------------|
| `shared.approvals.view` | All roles except EMP (own only), INV, VW, WHS, CSH |
| `shared.approvals.manage` | OWN, COW, ADM, BRM, DH, HRM, ACC, SM, PO, WHM, PRM |
| `shared.approvals.escalate` | OWN, COW, ADM, BRM, DH, HRM, ACC, SM, PO, WHM, PRM |
| `shared.approvals.configure` | OWN, COW only |

### 12.3 Escalation Rules

1. If Step 1 approver does not act within the time window, the system automatically escalates to Step 2.
2. If no Step 2 is defined, the system notifies the workspace `owner`.
3. Escalation notifications go to the next approver AND all workspace `admin` users.
4. All escalations are audit-logged with `action = 'approval_escalated'`.
5. The auto-escalate time window is configurable per workspace via workspace settings. The values in this table are defaults.
6. Amount thresholds are configurable per workspace via workspace settings.

---

## 13. Role Lifecycle & Safety Rules

### 13.1 Ownership Rules

1. Every workspace must have at least one user with the `owner` role at all times.
2. Ownership transfer requires the current owner to explicitly invoke `admin.ownership.transfer`.
3. Ownership transfer is a two-step operation: initiate → confirm.
4. If the sole owner is incapacitated, `platform_support` can initiate an emergency ownership transfer with `platform_owner` approval. This is audit-logged with `action = 'emergency_ownership_transfer'`.
5. The `owner` role cannot be deleted from the workspace role templates.

### 13.2 Role Assignment Auditing

Every role change generates an audit log entry:

| Event | Fields Logged |
|-------|--------------|
| `role_assigned` | workspace_id, user_id, role_id, actor_id, timestamp |
| `role_removed` | workspace_id, user_id, role_id, actor_id, timestamp |
| `role_created` | workspace_id, role_id, actor_id, permissions, timestamp |
| `role_updated` | workspace_id, role_id, actor_id, old_permissions, new_permissions, timestamp |
| `role_deleted` | workspace_id, role_id, actor_id, timestamp |
| `permission_granted` | workspace_id, user_id, permission, scope, actor_id, reason, timestamp |
| `permission_revoked` | workspace_id, user_id, permission, actor_id, reason, timestamp |
| `ownership_transferred` | workspace_id, old_owner_id, new_owner_id, actor_id, timestamp |
| `delegation_created` | workspace_id, delegator_id, delegate_id, permissions, valid_until, timestamp |
| `delegation_revoked` | workspace_id, delegator_id, delegate_id, actor_id, timestamp |
| `temp_grant_created` | workspace_id, user_id, permission, scope, valid_until, actor_id, timestamp |
| `temp_grant_expired` | workspace_id, user_id, permission, timestamp |

### 13.3 Session Safety

1. When a user's role is changed, all active sessions for that user in the affected workspace must be invalidated.
2. When a permission is revoked (role or user-level), the change takes effect on the next API request (no cached permissions beyond current request).
3. Dangerous permissions (`admin.ownership.*`, `admin.users.delete`, `finance.accounts.delete`) require re-authentication confirmation.

---

## 14. Schema Alignment Notes

### 14.1 Required Schema Changes

| # | Change | Table | Details | Priority |
|---|--------|-------|---------|----------|
| 1 | Add `workspace_memberships` table | NEW | `id UUID PK`, `user_id UUID FK`, `workspace_id UUID FK`, `role_id UUID FK`, `is_owner BOOLEAN`, `branch_id UUID FK NULL`, `department_id UUID FK NULL`, `warehouse_ids JSONB DEFAULT '[]'`, `joined_at TIMESTAMPTZ`, `is_active BOOLEAN DEFAULT true`. RLS: `workspace_id = current_setting('app.workspace_id')`. This replaces `users.workspace_id` and `users.role_id` for role resolution. | CRITICAL |
| 2 | Add `hierarchy_level INT DEFAULT 10` to `roles` | MODIFY `roles` | Enables role assignment restriction (can only assign roles at or below own level). | IMPORTANT |
| 3 | Add `is_system BOOLEAN DEFAULT false` to `roles` | MODIFY `roles` | Protects `owner` and `co_owner` template roles from deletion. | IMPORTANT |
| 4 | Add `permission_delegations` table | NEW | Schema defined in Section 10.2. RLS: `workspace_id`. | IMPORTANT |
| 5 | Add `temporary_permission_grants` table | NEW | Schema defined in Section 10.1. RLS: `workspace_id`. | IMPORTANT |
| 6 | Add `platform_engineer` to `platform_users.role` CHECK | MODIFY `platform_users` | Add to: `CHECK (role IN ('platform_owner', 'platform_admin', 'platform_support', 'platform_operations', 'platform_engineer'))` | IMPORTANT |

### 14.2 Permission Storage Format

Permissions are stored in `roles.permissions` JSONB with this schema:

```json
{
  "admin.workspace.view": { "scope": "ws" },
  "inventory.products.view": { "scope": "branch" },
  "hr.leaves.approve": { "scope": "dept" }
}
```

Backend permission check pseudocode:

```
function has_permission(user, permission_key, resource):
  # 1. Check user-level denials
  if user.permissions.denials[permission_key] exists:
    return DENIED

  # 2. Check temporary grants (not expired)
  temp = get_active_temp_grant(user, permission_key)
  if temp exists:
    return ALLOWED with temp.scope

  # 3. Check delegations (not expired)  
  delegation = get_active_delegation(user, permission_key)
  if delegation exists:
    return ALLOWED with delegation.scope

  # 4. Check user-level grants
  if user.permissions.grants[permission_key] exists:
    return ALLOWED with grant.scope

  # 5. Check role permissions
  membership = get_membership(user, current_workspace)
  role = get_role(membership.role_id)
  if role.permissions[permission_key] exists:
    return ALLOWED with role.permissions[permission_key].scope

  # 6. Deny by default
  return DENIED
```

### 14.3 External Stakeholder Note

External stakeholder access (supplier portals, customer portals) is out of scope for this specification. External access will use a separate authentication path and permission model, defined in a future extension document. This specification covers internal platform users and workspace members only.

---

## 15. JSON Appendix — Machine-Readable Permission Model

This appendix is the authoritative, machine-consumable representation of the permission model. Backend services use this to seed the database on workspace creation. Every workspace role template includes its complete permission set — no external cross-referencing is required.

```json
{
  "version": "1.0",
  "platform_roles": {
    "platform_owner": {
      "hierarchy_level": 100,
      "permissions": [
        "platform.workspaces.view", "platform.workspaces.inspect", "platform.workspaces.suspend",
        "platform.workspaces.reactivate", "platform.workspaces.delete", "platform.workspaces.impersonate",
        "platform.billing.plans.view", "platform.billing.plans.manage",
        "platform.billing.subscriptions.view", "platform.billing.subscriptions.manage",
        "platform.billing.invoices.view",
        "platform.users.view", "platform.users.manage", "platform.users.roles.manage",
        "platform.broadcasts.view", "platform.broadcasts.create", "platform.broadcasts.send",
        "platform.surveys.view", "platform.surveys.manage", "platform.surveys.view_responses",
        "platform.events.view", "platform.events.export",
        "platform.analytics.view", "platform.ai_logs.view", "platform.ai_logs.export",
        "platform.feature_requests.view", "platform.feature_requests.manage", "platform.feature_requests.roadmap",
        "platform.system.feature_flags", "platform.system.health",
        "platform.system.migrations", "platform.system.jobs", "platform.system.config"
      ]
    },
    "platform_admin": {
      "hierarchy_level": 80,
      "permissions": [
        "platform.workspaces.view", "platform.workspaces.inspect", "platform.workspaces.suspend",
        "platform.workspaces.reactivate",
        "platform.billing.plans.view", "platform.billing.subscriptions.view", "platform.billing.invoices.view",
        "platform.users.view",
        "platform.broadcasts.view", "platform.broadcasts.create", "platform.broadcasts.send",
        "platform.surveys.view", "platform.surveys.manage", "platform.surveys.view_responses",
        "platform.events.view", "platform.events.export",
        "platform.analytics.view", "platform.ai_logs.view",
        "platform.feature_requests.view", "platform.feature_requests.manage", "platform.feature_requests.roadmap"
      ]
    },
    "platform_engineer": {
      "hierarchy_level": 70,
      "permissions": [
        "platform.workspaces.view", "platform.workspaces.inspect",
        "platform.events.view", "platform.events.export",
        "platform.analytics.view", "platform.ai_logs.view", "platform.ai_logs.export",
        "platform.system.feature_flags", "platform.system.health",
        "platform.system.migrations", "platform.system.jobs", "platform.system.config"
      ]
    },
    "platform_support": {
      "hierarchy_level": 60,
      "permissions": [
        "platform.workspaces.view", "platform.workspaces.inspect", "platform.workspaces.impersonate",
        "platform.billing.subscriptions.view",
        "platform.broadcasts.view",
        "platform.events.view",
        "platform.feature_requests.view"
      ]
    },
    "platform_operations": {
      "hierarchy_level": 50,
      "permissions": [
        "platform.workspaces.view",
        "platform.events.view", "platform.events.export",
        "platform.analytics.view", "platform.ai_logs.view", "platform.ai_logs.export",
        "platform.system.health", "platform.system.jobs"
      ]
    }
  },
  "workspace_role_templates": {
    "owner": {
      "hierarchy_level": 100, "is_system": true, "deletable": false,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.workspace.configure": {"scope":"ws"},
        "admin.ownership.transfer": {"scope":"ws"}, "admin.ownership.delete": {"scope":"ws"},
        "admin.subscription.view": {"scope":"ws"}, "admin.subscription.manage": {"scope":"ws"},
        "admin.branches.view": {"scope":"ws"}, "admin.branches.create": {"scope":"ws"}, "admin.branches.update": {"scope":"ws"}, "admin.branches.delete": {"scope":"ws"},
        "admin.departments.view": {"scope":"ws"}, "admin.departments.create": {"scope":"ws"}, "admin.departments.update": {"scope":"ws"}, "admin.departments.delete": {"scope":"ws"},
        "admin.roles.view": {"scope":"ws"}, "admin.roles.create": {"scope":"ws"}, "admin.roles.update": {"scope":"ws"}, "admin.roles.delete": {"scope":"ws"},
        "admin.users.view": {"scope":"ws"}, "admin.users.create": {"scope":"ws"}, "admin.users.update": {"scope":"ws"}, "admin.users.delete": {"scope":"ws"}, "admin.users.approve": {"scope":"ws"},
        "admin.sequences.view": {"scope":"ws"}, "admin.sequences.configure": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"}, "inventory.products.delete": {"scope":"ws"}, "inventory.products.export": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.categories.create": {"scope":"ws"}, "inventory.categories.update": {"scope":"ws"}, "inventory.categories.delete": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"}, "inventory.variants.delete": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"}, "inventory.warehouses.create": {"scope":"ws"}, "inventory.warehouses.update": {"scope":"ws"}, "inventory.warehouses.delete": {"scope":"ws"},
        "inventory.levels.view": {"scope":"ws"}, "inventory.levels.adjust": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"}, "inventory.batches.update": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.units.create": {"scope":"ws"}, "inventory.units.update": {"scope":"ws"}, "inventory.units.delete": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"ws"}, "inventory.transfers.create": {"scope":"ws"}, "inventory.transfers.approve": {"scope":"ws"},
        "inventory.logs.view": {"scope":"ws"}, "inventory.logs.export": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.orders.create": {"scope":"ws"}, "sales.orders.update": {"scope":"ws"}, "sales.orders.cancel": {"scope":"ws"}, "sales.orders.export": {"scope":"ws"},
        "sales.pos.view": {"scope":"ws"}, "sales.pos.configure": {"scope":"ws"},
        "sales.pos_sessions.open": {"scope":"ws"}, "sales.pos_sessions.close": {"scope":"ws"}, "sales.pos_sessions.view": {"scope":"ws"},
        "sales.dining.view": {"scope":"ws"}, "sales.dining.manage": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"}, "sales.pricing.create": {"scope":"ws"}, "sales.pricing.update": {"scope":"ws"}, "sales.pricing.delete": {"scope":"ws"},
        "sales.promotions.view": {"scope":"ws"}, "sales.promotions.create": {"scope":"ws"}, "sales.promotions.update": {"scope":"ws"}, "sales.promotions.delete": {"scope":"ws"},
        "sales.coupons.view": {"scope":"ws"}, "sales.coupons.create": {"scope":"ws"}, "sales.coupons.update": {"scope":"ws"}, "sales.coupons.delete": {"scope":"ws"},
        "sales.bookings.view": {"scope":"ws"}, "sales.bookings.create": {"scope":"ws"}, "sales.bookings.update": {"scope":"ws"}, "sales.bookings.cancel": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"}, "purchasing.orders.create": {"scope":"ws"}, "purchasing.orders.update": {"scope":"ws"}, "purchasing.orders.cancel": {"scope":"ws"}, "purchasing.orders.approve": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"}, "finance.invoices.create": {"scope":"ws"}, "finance.invoices.update": {"scope":"ws"}, "finance.invoices.cancel": {"scope":"ws"}, "finance.invoices.approve": {"scope":"ws"}, "finance.invoices.export": {"scope":"ws"},
        "finance.payments.view": {"scope":"ws"}, "finance.payments.create": {"scope":"ws"}, "finance.payments.export": {"scope":"ws"},
        "finance.transactions.view": {"scope":"ws"}, "finance.transactions.create": {"scope":"ws"}, "finance.transactions.update": {"scope":"ws"}, "finance.transactions.delete": {"scope":"ws"}, "finance.transactions.export": {"scope":"ws"},
        "finance.accounts.view": {"scope":"ws"}, "finance.accounts.create": {"scope":"ws"}, "finance.accounts.update": {"scope":"ws"}, "finance.accounts.delete": {"scope":"ws"},
        "finance.journal_entries.view": {"scope":"ws"}, "finance.journal_entries.create": {"scope":"ws"}, "finance.journal_entries.approve": {"scope":"ws"}, "finance.journal_entries.export": {"scope":"ws"},
        "finance.taxes.view": {"scope":"ws"}, "finance.taxes.create": {"scope":"ws"}, "finance.taxes.update": {"scope":"ws"}, "finance.taxes.delete": {"scope":"ws"},
        "finance.fixed_assets.view": {"scope":"ws"}, "finance.fixed_assets.create": {"scope":"ws"}, "finance.fixed_assets.update": {"scope":"ws"}, "finance.fixed_assets.delete": {"scope":"ws"},
        "finance.recurring_expenses.view": {"scope":"ws"}, "finance.recurring_expenses.create": {"scope":"ws"}, "finance.recurring_expenses.update": {"scope":"ws"}, "finance.recurring_expenses.delete": {"scope":"ws"},
        "finance.reports.view": {"scope":"ws"}, "finance.reports.export": {"scope":"ws"},
        "hr.employees.view": {"scope":"ws"}, "hr.employees.create": {"scope":"ws"}, "hr.employees.update": {"scope":"ws"}, "hr.employees.delete": {"scope":"ws"}, "hr.employees.export": {"scope":"ws"},
        "hr.attendance.view": {"scope":"ws"}, "hr.attendance.create": {"scope":"ws"}, "hr.attendance.update": {"scope":"ws"}, "hr.attendance.export": {"scope":"ws"},
        "hr.leaves.view": {"scope":"ws"}, "hr.leaves.create": {"scope":"ws"}, "hr.leaves.approve": {"scope":"ws"}, "hr.leaves.export": {"scope":"ws"},
        "hr.payroll.view": {"scope":"ws"}, "hr.payroll.process": {"scope":"ws"}, "hr.payroll.export": {"scope":"ws"},
        "hr.shifts.view": {"scope":"ws"}, "hr.shifts.create": {"scope":"ws"}, "hr.shifts.update": {"scope":"ws"}, "hr.shifts.delete": {"scope":"ws"},
        "crm.leads.view": {"scope":"ws"}, "crm.leads.create": {"scope":"ws"}, "crm.leads.update": {"scope":"ws"}, "crm.leads.delete": {"scope":"ws"}, "crm.leads.export": {"scope":"ws"},
        "crm.opportunities.view": {"scope":"ws"}, "crm.opportunities.create": {"scope":"ws"}, "crm.opportunities.update": {"scope":"ws"}, "crm.opportunities.delete": {"scope":"ws"},
        "crm.activities.view": {"scope":"ws"}, "crm.activities.create": {"scope":"ws"}, "crm.activities.update": {"scope":"ws"},
        "crm.subscriptions.view": {"scope":"ws"}, "crm.subscriptions.create": {"scope":"ws"}, "crm.subscriptions.update": {"scope":"ws"}, "crm.subscriptions.cancel": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.bom.create": {"scope":"ws"}, "manufacturing.bom.update": {"scope":"ws"}, "manufacturing.bom.delete": {"scope":"ws"},
        "manufacturing.production.view": {"scope":"ws"}, "manufacturing.production.create": {"scope":"ws"}, "manufacturing.production.update": {"scope":"ws"}, "manufacturing.production.cancel": {"scope":"ws"},
        "manufacturing.work_centers.view": {"scope":"ws"}, "manufacturing.work_centers.create": {"scope":"ws"}, "manufacturing.work_centers.update": {"scope":"ws"}, "manufacturing.work_centers.delete": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.projects.create": {"scope":"ws"}, "projects.projects.update": {"scope":"ws"}, "projects.projects.delete": {"scope":"ws"},
        "projects.tasks.view": {"scope":"ws"}, "projects.tasks.create": {"scope":"ws"}, "projects.tasks.update": {"scope":"ws"}, "projects.tasks.delete": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.contacts.create": {"scope":"ws"}, "shared.contacts.update": {"scope":"ws"}, "shared.contacts.delete": {"scope":"ws"}, "shared.contacts.export": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"}, "shared.attachments.delete": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"}, "shared.notifications.manage": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"}, "shared.approvals.configure": {"scope":"ws"},
        "shared.audit_logs.view": {"scope":"ws"}, "shared.audit_logs.export": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"}, "ai.changes.approve": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"},
        "reports.financial.view": {"scope":"ws"}, "reports.financial.export": {"scope":"ws"},
        "reports.executive.view": {"scope":"ws"}, "reports.executive.export": {"scope":"ws"}
      }
    },
    "co_owner": {
      "hierarchy_level": 90, "is_system": true, "deletable": false,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.workspace.configure": {"scope":"ws"},
        "admin.subscription.view": {"scope":"ws"},
        "admin.branches.view": {"scope":"ws"}, "admin.branches.create": {"scope":"ws"}, "admin.branches.update": {"scope":"ws"}, "admin.branches.delete": {"scope":"ws"},
        "admin.departments.view": {"scope":"ws"}, "admin.departments.create": {"scope":"ws"}, "admin.departments.update": {"scope":"ws"}, "admin.departments.delete": {"scope":"ws"},
        "admin.roles.view": {"scope":"ws"}, "admin.roles.create": {"scope":"ws"}, "admin.roles.update": {"scope":"ws"}, "admin.roles.delete": {"scope":"ws"},
        "admin.users.view": {"scope":"ws"}, "admin.users.create": {"scope":"ws"}, "admin.users.update": {"scope":"ws"}, "admin.users.delete": {"scope":"ws"}, "admin.users.approve": {"scope":"ws"},
        "admin.sequences.view": {"scope":"ws"}, "admin.sequences.configure": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"}, "inventory.products.delete": {"scope":"ws"}, "inventory.products.export": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.categories.create": {"scope":"ws"}, "inventory.categories.update": {"scope":"ws"}, "inventory.categories.delete": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"}, "inventory.variants.delete": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"}, "inventory.warehouses.create": {"scope":"ws"}, "inventory.warehouses.update": {"scope":"ws"}, "inventory.warehouses.delete": {"scope":"ws"},
        "inventory.levels.view": {"scope":"ws"}, "inventory.levels.adjust": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"}, "inventory.batches.update": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.units.create": {"scope":"ws"}, "inventory.units.update": {"scope":"ws"}, "inventory.units.delete": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"ws"}, "inventory.transfers.create": {"scope":"ws"}, "inventory.transfers.approve": {"scope":"ws"},
        "inventory.logs.view": {"scope":"ws"}, "inventory.logs.export": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.orders.create": {"scope":"ws"}, "sales.orders.update": {"scope":"ws"}, "sales.orders.cancel": {"scope":"ws"}, "sales.orders.export": {"scope":"ws"},
        "sales.pos.view": {"scope":"ws"}, "sales.pos.configure": {"scope":"ws"},
        "sales.pos_sessions.open": {"scope":"ws"}, "sales.pos_sessions.close": {"scope":"ws"}, "sales.pos_sessions.view": {"scope":"ws"},
        "sales.dining.view": {"scope":"ws"}, "sales.dining.manage": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"}, "sales.pricing.create": {"scope":"ws"}, "sales.pricing.update": {"scope":"ws"}, "sales.pricing.delete": {"scope":"ws"},
        "sales.promotions.view": {"scope":"ws"}, "sales.promotions.create": {"scope":"ws"}, "sales.promotions.update": {"scope":"ws"}, "sales.promotions.delete": {"scope":"ws"},
        "sales.coupons.view": {"scope":"ws"}, "sales.coupons.create": {"scope":"ws"}, "sales.coupons.update": {"scope":"ws"}, "sales.coupons.delete": {"scope":"ws"},
        "sales.bookings.view": {"scope":"ws"}, "sales.bookings.create": {"scope":"ws"}, "sales.bookings.update": {"scope":"ws"}, "sales.bookings.cancel": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"}, "purchasing.orders.create": {"scope":"ws"}, "purchasing.orders.update": {"scope":"ws"}, "purchasing.orders.cancel": {"scope":"ws"}, "purchasing.orders.approve": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"}, "finance.invoices.create": {"scope":"ws"}, "finance.invoices.update": {"scope":"ws"}, "finance.invoices.cancel": {"scope":"ws"}, "finance.invoices.approve": {"scope":"ws"}, "finance.invoices.export": {"scope":"ws"},
        "finance.payments.view": {"scope":"ws"}, "finance.payments.create": {"scope":"ws"}, "finance.payments.export": {"scope":"ws"},
        "finance.transactions.view": {"scope":"ws"}, "finance.transactions.create": {"scope":"ws"}, "finance.transactions.update": {"scope":"ws"}, "finance.transactions.delete": {"scope":"ws"}, "finance.transactions.export": {"scope":"ws"},
        "finance.accounts.view": {"scope":"ws"}, "finance.accounts.create": {"scope":"ws"}, "finance.accounts.update": {"scope":"ws"}, "finance.accounts.delete": {"scope":"ws"},
        "finance.journal_entries.view": {"scope":"ws"}, "finance.journal_entries.create": {"scope":"ws"}, "finance.journal_entries.approve": {"scope":"ws"}, "finance.journal_entries.export": {"scope":"ws"},
        "finance.taxes.view": {"scope":"ws"}, "finance.taxes.create": {"scope":"ws"}, "finance.taxes.update": {"scope":"ws"}, "finance.taxes.delete": {"scope":"ws"},
        "finance.fixed_assets.view": {"scope":"ws"}, "finance.fixed_assets.create": {"scope":"ws"}, "finance.fixed_assets.update": {"scope":"ws"}, "finance.fixed_assets.delete": {"scope":"ws"},
        "finance.recurring_expenses.view": {"scope":"ws"}, "finance.recurring_expenses.create": {"scope":"ws"}, "finance.recurring_expenses.update": {"scope":"ws"}, "finance.recurring_expenses.delete": {"scope":"ws"},
        "finance.reports.view": {"scope":"ws"}, "finance.reports.export": {"scope":"ws"},
        "hr.employees.view": {"scope":"ws"}, "hr.employees.create": {"scope":"ws"}, "hr.employees.update": {"scope":"ws"}, "hr.employees.delete": {"scope":"ws"}, "hr.employees.export": {"scope":"ws"},
        "hr.attendance.view": {"scope":"ws"}, "hr.attendance.create": {"scope":"ws"}, "hr.attendance.update": {"scope":"ws"}, "hr.attendance.export": {"scope":"ws"},
        "hr.leaves.view": {"scope":"ws"}, "hr.leaves.create": {"scope":"ws"}, "hr.leaves.approve": {"scope":"ws"}, "hr.leaves.export": {"scope":"ws"},
        "hr.payroll.view": {"scope":"ws"}, "hr.payroll.process": {"scope":"ws"}, "hr.payroll.export": {"scope":"ws"},
        "hr.shifts.view": {"scope":"ws"}, "hr.shifts.create": {"scope":"ws"}, "hr.shifts.update": {"scope":"ws"}, "hr.shifts.delete": {"scope":"ws"},
        "crm.leads.view": {"scope":"ws"}, "crm.leads.create": {"scope":"ws"}, "crm.leads.update": {"scope":"ws"}, "crm.leads.delete": {"scope":"ws"}, "crm.leads.export": {"scope":"ws"},
        "crm.opportunities.view": {"scope":"ws"}, "crm.opportunities.create": {"scope":"ws"}, "crm.opportunities.update": {"scope":"ws"}, "crm.opportunities.delete": {"scope":"ws"},
        "crm.activities.view": {"scope":"ws"}, "crm.activities.create": {"scope":"ws"}, "crm.activities.update": {"scope":"ws"},
        "crm.subscriptions.view": {"scope":"ws"}, "crm.subscriptions.create": {"scope":"ws"}, "crm.subscriptions.update": {"scope":"ws"}, "crm.subscriptions.cancel": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.bom.create": {"scope":"ws"}, "manufacturing.bom.update": {"scope":"ws"}, "manufacturing.bom.delete": {"scope":"ws"},
        "manufacturing.production.view": {"scope":"ws"}, "manufacturing.production.create": {"scope":"ws"}, "manufacturing.production.update": {"scope":"ws"}, "manufacturing.production.cancel": {"scope":"ws"},
        "manufacturing.work_centers.view": {"scope":"ws"}, "manufacturing.work_centers.create": {"scope":"ws"}, "manufacturing.work_centers.update": {"scope":"ws"}, "manufacturing.work_centers.delete": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.projects.create": {"scope":"ws"}, "projects.projects.update": {"scope":"ws"}, "projects.projects.delete": {"scope":"ws"},
        "projects.tasks.view": {"scope":"ws"}, "projects.tasks.create": {"scope":"ws"}, "projects.tasks.update": {"scope":"ws"}, "projects.tasks.delete": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.contacts.create": {"scope":"ws"}, "shared.contacts.update": {"scope":"ws"}, "shared.contacts.delete": {"scope":"ws"}, "shared.contacts.export": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"}, "shared.attachments.delete": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"}, "shared.notifications.manage": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"}, "shared.approvals.configure": {"scope":"ws"},
        "shared.audit_logs.view": {"scope":"ws"}, "shared.audit_logs.export": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"}, "ai.changes.approve": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"},
        "reports.financial.view": {"scope":"ws"}, "reports.financial.export": {"scope":"ws"},
        "reports.executive.view": {"scope":"ws"}, "reports.executive.export": {"scope":"ws"}
      }
    },
    "admin": {
      "hierarchy_level": 80, "is_system": true, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.subscription.view": {"scope":"ws"},
        "admin.branches.view": {"scope":"ws"}, "admin.branches.create": {"scope":"ws"}, "admin.branches.update": {"scope":"ws"},
        "admin.departments.view": {"scope":"ws"}, "admin.departments.create": {"scope":"ws"}, "admin.departments.update": {"scope":"ws"}, "admin.departments.delete": {"scope":"ws"},
        "admin.roles.view": {"scope":"ws"}, "admin.roles.create": {"scope":"ws"}, "admin.roles.update": {"scope":"ws"},
        "admin.users.view": {"scope":"ws"}, "admin.users.create": {"scope":"ws"}, "admin.users.update": {"scope":"ws"}, "admin.users.delete": {"scope":"ws"}, "admin.users.approve": {"scope":"ws"},
        "admin.sequences.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"}, "inventory.products.delete": {"scope":"ws"}, "inventory.products.export": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.categories.create": {"scope":"ws"}, "inventory.categories.update": {"scope":"ws"}, "inventory.categories.delete": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"}, "inventory.variants.delete": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"}, "inventory.warehouses.create": {"scope":"ws"}, "inventory.warehouses.update": {"scope":"ws"}, "inventory.warehouses.delete": {"scope":"ws"},
        "inventory.levels.view": {"scope":"ws"}, "inventory.levels.adjust": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"}, "inventory.batches.update": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.units.create": {"scope":"ws"}, "inventory.units.update": {"scope":"ws"}, "inventory.units.delete": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"ws"}, "inventory.transfers.create": {"scope":"ws"}, "inventory.transfers.approve": {"scope":"ws"},
        "inventory.logs.view": {"scope":"ws"}, "inventory.logs.export": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.orders.create": {"scope":"ws"}, "sales.orders.update": {"scope":"ws"}, "sales.orders.cancel": {"scope":"ws"}, "sales.orders.export": {"scope":"ws"},
        "sales.pos.view": {"scope":"ws"}, "sales.pos.configure": {"scope":"ws"},
        "sales.pos_sessions.open": {"scope":"ws"}, "sales.pos_sessions.close": {"scope":"ws"}, "sales.pos_sessions.view": {"scope":"ws"},
        "sales.dining.view": {"scope":"ws"}, "sales.dining.manage": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"}, "sales.pricing.create": {"scope":"ws"}, "sales.pricing.update": {"scope":"ws"}, "sales.pricing.delete": {"scope":"ws"},
        "sales.promotions.view": {"scope":"ws"}, "sales.promotions.create": {"scope":"ws"}, "sales.promotions.update": {"scope":"ws"}, "sales.promotions.delete": {"scope":"ws"},
        "sales.coupons.view": {"scope":"ws"}, "sales.coupons.create": {"scope":"ws"}, "sales.coupons.update": {"scope":"ws"}, "sales.coupons.delete": {"scope":"ws"},
        "sales.bookings.view": {"scope":"ws"}, "sales.bookings.create": {"scope":"ws"}, "sales.bookings.update": {"scope":"ws"}, "sales.bookings.cancel": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"}, "purchasing.orders.create": {"scope":"ws"}, "purchasing.orders.update": {"scope":"ws"}, "purchasing.orders.cancel": {"scope":"ws"}, "purchasing.orders.approve": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"}, "finance.invoices.create": {"scope":"ws"}, "finance.invoices.update": {"scope":"ws"}, "finance.invoices.approve": {"scope":"ws"}, "finance.invoices.export": {"scope":"ws"},
        "finance.payments.view": {"scope":"ws"}, "finance.payments.create": {"scope":"ws"}, "finance.payments.export": {"scope":"ws"},
        "finance.transactions.view": {"scope":"ws"}, "finance.transactions.create": {"scope":"ws"}, "finance.transactions.update": {"scope":"ws"}, "finance.transactions.export": {"scope":"ws"},
        "finance.accounts.view": {"scope":"ws"},
        "finance.journal_entries.view": {"scope":"ws"}, "finance.journal_entries.approve": {"scope":"ws"}, "finance.journal_entries.export": {"scope":"ws"},
        "finance.taxes.view": {"scope":"ws"},
        "finance.fixed_assets.view": {"scope":"ws"},
        "finance.recurring_expenses.view": {"scope":"ws"},
        "finance.reports.view": {"scope":"ws"}, "finance.reports.export": {"scope":"ws"},
        "hr.employees.view": {"scope":"ws"}, "hr.employees.create": {"scope":"ws"}, "hr.employees.update": {"scope":"ws"}, "hr.employees.delete": {"scope":"ws"}, "hr.employees.export": {"scope":"ws"},
        "hr.attendance.view": {"scope":"ws"}, "hr.attendance.create": {"scope":"ws"}, "hr.attendance.update": {"scope":"ws"}, "hr.attendance.export": {"scope":"ws"},
        "hr.leaves.view": {"scope":"ws"}, "hr.leaves.create": {"scope":"ws"}, "hr.leaves.approve": {"scope":"ws"}, "hr.leaves.export": {"scope":"ws"},
        "hr.payroll.view": {"scope":"ws"}, "hr.payroll.export": {"scope":"ws"},
        "hr.shifts.view": {"scope":"ws"}, "hr.shifts.create": {"scope":"ws"}, "hr.shifts.update": {"scope":"ws"}, "hr.shifts.delete": {"scope":"ws"},
        "crm.leads.view": {"scope":"ws"}, "crm.leads.create": {"scope":"ws"}, "crm.leads.update": {"scope":"ws"}, "crm.leads.delete": {"scope":"ws"}, "crm.leads.export": {"scope":"ws"},
        "crm.opportunities.view": {"scope":"ws"}, "crm.opportunities.create": {"scope":"ws"}, "crm.opportunities.update": {"scope":"ws"}, "crm.opportunities.delete": {"scope":"ws"},
        "crm.activities.view": {"scope":"ws"}, "crm.activities.create": {"scope":"ws"}, "crm.activities.update": {"scope":"ws"},
        "crm.subscriptions.view": {"scope":"ws"}, "crm.subscriptions.create": {"scope":"ws"}, "crm.subscriptions.update": {"scope":"ws"}, "crm.subscriptions.cancel": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.bom.create": {"scope":"ws"}, "manufacturing.bom.update": {"scope":"ws"}, "manufacturing.bom.delete": {"scope":"ws"},
        "manufacturing.production.view": {"scope":"ws"}, "manufacturing.production.create": {"scope":"ws"}, "manufacturing.production.update": {"scope":"ws"}, "manufacturing.production.cancel": {"scope":"ws"},
        "manufacturing.work_centers.view": {"scope":"ws"}, "manufacturing.work_centers.create": {"scope":"ws"}, "manufacturing.work_centers.update": {"scope":"ws"}, "manufacturing.work_centers.delete": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.projects.create": {"scope":"ws"}, "projects.projects.update": {"scope":"ws"}, "projects.projects.delete": {"scope":"ws"},
        "projects.tasks.view": {"scope":"ws"}, "projects.tasks.create": {"scope":"ws"}, "projects.tasks.update": {"scope":"ws"}, "projects.tasks.delete": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.contacts.create": {"scope":"ws"}, "shared.contacts.update": {"scope":"ws"}, "shared.contacts.delete": {"scope":"ws"}, "shared.contacts.export": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"}, "shared.attachments.delete": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"}, "shared.notifications.manage": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "shared.audit_logs.view": {"scope":"ws"}, "shared.audit_logs.export": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"}, "ai.changes.approve": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"},
        "reports.financial.view": {"scope":"ws"}, "reports.financial.export": {"scope":"ws"},
        "reports.executive.view": {"scope":"ws"}, "reports.executive.export": {"scope":"ws"}
      }
    },
    "branch_manager": {
      "hierarchy_level": 70, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.branches.view": {"scope":"ws"}, "admin.branches.update": {"scope":"branch"},
        "admin.departments.view": {"scope":"branch"}, "admin.users.view": {"scope":"branch"}, "admin.users.approve": {"scope":"branch"},
        "inventory.products.view": {"scope":"branch"}, "inventory.variants.view": {"scope":"branch"},
        "inventory.warehouses.view": {"scope":"branch"}, "inventory.levels.view": {"scope":"branch"},
        "inventory.batches.view": {"scope":"branch"}, "inventory.transfers.view": {"scope":"branch"}, "inventory.transfers.approve": {"scope":"branch"},
        "inventory.logs.view": {"scope":"branch"},
        "sales.orders.view": {"scope":"branch"}, "sales.orders.create": {"scope":"branch"}, "sales.orders.update": {"scope":"branch"}, "sales.orders.cancel": {"scope":"branch"},
        "sales.pos.view": {"scope":"branch"}, "sales.pos.configure": {"scope":"branch"},
        "sales.pos_sessions.open": {"scope":"branch"}, "sales.pos_sessions.close": {"scope":"branch"}, "sales.pos_sessions.view": {"scope":"branch"},
        "sales.dining.view": {"scope":"branch"}, "sales.dining.manage": {"scope":"branch"},
        "sales.pricing.view": {"scope":"branch"}, "sales.promotions.view": {"scope":"branch"}, "sales.coupons.view": {"scope":"branch"},
        "sales.bookings.view": {"scope":"branch"}, "sales.bookings.create": {"scope":"branch"}, "sales.bookings.update": {"scope":"branch"}, "sales.bookings.cancel": {"scope":"branch"},
        "purchasing.orders.view": {"scope":"branch"},
        "finance.invoices.view": {"scope":"branch"}, "finance.payments.view": {"scope":"branch"}, "finance.reports.view": {"scope":"branch"},
        "hr.employees.view": {"scope":"branch"}, "hr.attendance.view": {"scope":"branch"}, "hr.attendance.create": {"scope":"branch"},
        "hr.leaves.view": {"scope":"branch"}, "hr.leaves.approve": {"scope":"branch"}, "hr.shifts.view": {"scope":"branch"},
        "crm.leads.view": {"scope":"branch"}, "crm.opportunities.view": {"scope":"branch"}, "crm.activities.view": {"scope":"branch"}, "crm.subscriptions.view": {"scope":"branch"},
        "projects.projects.view": {"scope":"branch"}, "projects.projects.create": {"scope":"branch"}, "projects.projects.update": {"scope":"branch"},
        "projects.tasks.view": {"scope":"branch"}, "projects.tasks.create": {"scope":"branch"}, "projects.tasks.update": {"scope":"branch"},
        "shared.contacts.view": {"scope":"branch"}, "shared.contacts.create": {"scope":"branch"}, "shared.contacts.update": {"scope":"branch"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"branch"}, "shared.approvals.manage": {"scope":"branch"}, "shared.approvals.escalate": {"scope":"branch"},
        "shared.audit_logs.view": {"scope":"branch"}, "shared.shipments.view": {"scope":"branch"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"branch"}, "reports.operational.export": {"scope":"branch"},
        "reports.financial.view": {"scope":"branch"}
      }
    },
    "department_head": {
      "hierarchy_level": 65, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.departments.view": {"scope":"dept"}, "admin.departments.update": {"scope":"dept"},
        "admin.users.view": {"scope":"dept"}, "admin.users.approve": {"scope":"dept"},
        "hr.employees.view": {"scope":"dept"}, "hr.attendance.view": {"scope":"dept"}, "hr.leaves.view": {"scope":"dept"}, "hr.leaves.approve": {"scope":"dept"}, "hr.shifts.view": {"scope":"dept"},
        "projects.projects.view": {"scope":"dept"}, "projects.projects.create": {"scope":"dept"}, "projects.projects.update": {"scope":"dept"},
        "projects.tasks.view": {"scope":"dept"}, "projects.tasks.create": {"scope":"dept"}, "projects.tasks.update": {"scope":"dept"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"dept"}, "shared.approvals.manage": {"scope":"dept"}, "shared.approvals.escalate": {"scope":"dept"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"dept"}
      }
    },
    "hr_manager": {
      "hierarchy_level": 60, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.departments.view": {"scope":"ws"},
        "admin.users.view": {"scope":"ws"}, "admin.users.create": {"scope":"ws"}, "admin.users.update": {"scope":"ws"}, "admin.users.approve": {"scope":"ws"},
        "hr.employees.view": {"scope":"ws"}, "hr.employees.create": {"scope":"ws"}, "hr.employees.update": {"scope":"ws"}, "hr.employees.delete": {"scope":"ws"}, "hr.employees.export": {"scope":"ws"},
        "hr.attendance.view": {"scope":"ws"}, "hr.attendance.create": {"scope":"ws"}, "hr.attendance.update": {"scope":"ws"}, "hr.attendance.export": {"scope":"ws"},
        "hr.leaves.view": {"scope":"ws"}, "hr.leaves.create": {"scope":"ws"}, "hr.leaves.approve": {"scope":"ws"}, "hr.leaves.export": {"scope":"ws"},
        "hr.payroll.view": {"scope":"ws"}, "hr.payroll.process": {"scope":"ws"}, "hr.payroll.export": {"scope":"ws"},
        "hr.shifts.view": {"scope":"ws"}, "hr.shifts.create": {"scope":"ws"}, "hr.shifts.update": {"scope":"ws"}, "hr.shifts.delete": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"}
      }
    },
    "accountant": {
      "hierarchy_level": 60, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.sequences.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.levels.view": {"scope":"ws"}, "inventory.logs.view": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.orders.export": {"scope":"ws"}, "sales.pos_sessions.view": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"}, "finance.invoices.create": {"scope":"ws"}, "finance.invoices.update": {"scope":"ws"}, "finance.invoices.cancel": {"scope":"ws"}, "finance.invoices.export": {"scope":"ws"},
        "finance.payments.view": {"scope":"ws"}, "finance.payments.create": {"scope":"ws"}, "finance.payments.export": {"scope":"ws"},
        "finance.transactions.view": {"scope":"ws"}, "finance.transactions.create": {"scope":"ws"}, "finance.transactions.update": {"scope":"ws"}, "finance.transactions.delete": {"scope":"ws"}, "finance.transactions.export": {"scope":"ws"},
        "finance.accounts.view": {"scope":"ws"}, "finance.accounts.create": {"scope":"ws"}, "finance.accounts.update": {"scope":"ws"},
        "finance.journal_entries.view": {"scope":"ws"}, "finance.journal_entries.create": {"scope":"ws"}, "finance.journal_entries.export": {"scope":"ws"},
        "finance.taxes.view": {"scope":"ws"}, "finance.taxes.create": {"scope":"ws"}, "finance.taxes.update": {"scope":"ws"},
        "finance.fixed_assets.view": {"scope":"ws"}, "finance.fixed_assets.create": {"scope":"ws"}, "finance.fixed_assets.update": {"scope":"ws"},
        "finance.recurring_expenses.view": {"scope":"ws"}, "finance.recurring_expenses.create": {"scope":"ws"}, "finance.recurring_expenses.update": {"scope":"ws"},
        "finance.reports.view": {"scope":"ws"}, "finance.reports.export": {"scope":"ws"},
        "hr.payroll.view": {"scope":"ws"}, "hr.payroll.export": {"scope":"ws"},
        "crm.subscriptions.view": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.production.view": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "shared.audit_logs.view": {"scope":"ws"}, "shared.audit_logs.export": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.financial.view": {"scope":"ws"}, "reports.financial.export": {"scope":"ws"},
        "reports.executive.view": {"scope":"ws"}, "reports.executive.export": {"scope":"ws"}
      }
    },
    "sales_manager": {
      "hierarchy_level": 55, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.branches.view": {"scope":"ws"},
        "admin.users.view": {"scope":"team"}, "admin.departments.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.categories.view": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.units.view": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.orders.create": {"scope":"ws"}, "sales.orders.update": {"scope":"ws"}, "sales.orders.cancel": {"scope":"ws"}, "sales.orders.export": {"scope":"ws"},
        "sales.pos.view": {"scope":"ws"},
        "sales.pos_sessions.open": {"scope":"ws"}, "sales.pos_sessions.close": {"scope":"ws"}, "sales.pos_sessions.view": {"scope":"ws"},
        "sales.dining.view": {"scope":"ws"}, "sales.dining.manage": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"}, "sales.pricing.create": {"scope":"ws"}, "sales.pricing.update": {"scope":"ws"}, "sales.pricing.delete": {"scope":"ws"},
        "sales.promotions.view": {"scope":"ws"}, "sales.promotions.create": {"scope":"ws"}, "sales.promotions.update": {"scope":"ws"}, "sales.promotions.delete": {"scope":"ws"},
        "sales.coupons.view": {"scope":"ws"}, "sales.coupons.create": {"scope":"ws"}, "sales.coupons.update": {"scope":"ws"}, "sales.coupons.delete": {"scope":"ws"},
        "sales.bookings.view": {"scope":"ws"}, "sales.bookings.create": {"scope":"ws"}, "sales.bookings.update": {"scope":"ws"}, "sales.bookings.cancel": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"},
        "crm.leads.view": {"scope":"ws"}, "crm.leads.create": {"scope":"ws"}, "crm.leads.update": {"scope":"ws"}, "crm.leads.delete": {"scope":"ws"}, "crm.leads.export": {"scope":"ws"},
        "crm.opportunities.view": {"scope":"ws"}, "crm.opportunities.create": {"scope":"ws"}, "crm.opportunities.update": {"scope":"ws"}, "crm.opportunities.delete": {"scope":"ws"},
        "crm.activities.view": {"scope":"ws"}, "crm.activities.create": {"scope":"ws"}, "crm.activities.update": {"scope":"ws"},
        "crm.subscriptions.view": {"scope":"ws"}, "crm.subscriptions.create": {"scope":"ws"}, "crm.subscriptions.update": {"scope":"ws"}, "crm.subscriptions.cancel": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.projects.create": {"scope":"ws"}, "projects.projects.update": {"scope":"ws"},
        "projects.tasks.view": {"scope":"ws"}, "projects.tasks.create": {"scope":"ws"}, "projects.tasks.update": {"scope":"ws"}, "projects.tasks.delete": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.contacts.create": {"scope":"ws"}, "shared.contacts.update": {"scope":"ws"}, "shared.contacts.delete": {"scope":"ws"}, "shared.contacts.export": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"}
      }
    },
    "sales_rep": {
      "hierarchy_level": 40, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.categories.view": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.units.view": {"scope":"ws"},
        "sales.orders.view": {"scope":"own"}, "sales.orders.create": {"scope":"own"}, "sales.orders.update": {"scope":"own"},
        "sales.pos_sessions.view": {"scope":"own"},
        "sales.dining.view": {"scope":"ws"}, "sales.pricing.view": {"scope":"ws"},
        "sales.promotions.view": {"scope":"ws"}, "sales.coupons.view": {"scope":"ws"},
        "sales.bookings.view": {"scope":"own"}, "sales.bookings.create": {"scope":"own"}, "sales.bookings.update": {"scope":"own"},
        "finance.invoices.view": {"scope":"own"},
        "crm.leads.view": {"scope":"own"}, "crm.leads.create": {"scope":"own"}, "crm.leads.update": {"scope":"own"},
        "crm.opportunities.view": {"scope":"own"}, "crm.opportunities.create": {"scope":"own"}, "crm.opportunities.update": {"scope":"own"},
        "crm.activities.view": {"scope":"own"}, "crm.activities.create": {"scope":"own"}, "crm.activities.update": {"scope":"own"},
        "crm.subscriptions.view": {"scope":"own"},
        "projects.projects.view": {"scope":"own"}, "projects.tasks.view": {"scope":"own"}, "projects.tasks.create": {"scope":"own"}, "projects.tasks.update": {"scope":"own"},
        "shared.contacts.view": {"scope":"own"}, "shared.contacts.create": {"scope":"own"}, "shared.contacts.update": {"scope":"own"},
        "shared.attachments.view": {"scope":"own"}, "shared.attachments.create": {"scope":"own"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"own"}, "shared.shipments.view": {"scope":"own"},
        "ai.chat.use": {"scope":"ws"},
        "reports.operational.view": {"scope":"own"}
      }
    },
    "purchasing_officer": {
      "hierarchy_level": 55, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"}, "inventory.products.export": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"}, "inventory.levels.view": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.transfers.view": {"scope":"ws"}, "inventory.transfers.create": {"scope":"ws"},
        "inventory.logs.view": {"scope":"ws"},
        "sales.pricing.view": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"}, "purchasing.orders.create": {"scope":"ws"}, "purchasing.orders.update": {"scope":"ws"}, "purchasing.orders.cancel": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"}, "shared.contacts.create": {"scope":"ws"}, "shared.contacts.update": {"scope":"ws"}, "shared.contacts.export": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}
      }
    },
    "warehouse_manager": {
      "hierarchy_level": 55, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.branches.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"}, "inventory.products.delete": {"scope":"ws"}, "inventory.products.export": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.categories.create": {"scope":"ws"}, "inventory.categories.update": {"scope":"ws"}, "inventory.categories.delete": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"}, "inventory.variants.delete": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"}, "inventory.warehouses.create": {"scope":"ws"}, "inventory.warehouses.update": {"scope":"ws"}, "inventory.warehouses.delete": {"scope":"ws"},
        "inventory.levels.view": {"scope":"ws"}, "inventory.levels.adjust": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"}, "inventory.batches.update": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.units.create": {"scope":"ws"}, "inventory.units.update": {"scope":"ws"}, "inventory.units.delete": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"ws"}, "inventory.transfers.create": {"scope":"ws"}, "inventory.transfers.approve": {"scope":"ws"},
        "inventory.logs.view": {"scope":"ws"}, "inventory.logs.export": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.production.view": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "shared.shipments.view": {"scope":"ws"}, "shared.shipments.create": {"scope":"ws"}, "shared.shipments.update": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"}
      }
    },
    "warehouse_staff": {
      "hierarchy_level": 40, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"wh"}, "inventory.categories.view": {"scope":"wh"},
        "inventory.variants.view": {"scope":"wh"}, "inventory.warehouses.view": {"scope":"wh"},
        "inventory.levels.view": {"scope":"wh"}, "inventory.levels.adjust": {"scope":"wh"},
        "inventory.batches.view": {"scope":"wh"}, "inventory.batches.create": {"scope":"wh"}, "inventory.batches.update": {"scope":"wh"},
        "inventory.units.view": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"wh"}, "inventory.transfers.create": {"scope":"wh"},
        "inventory.logs.view": {"scope":"wh"},
        "shared.attachments.view": {"scope":"wh"}, "shared.attachments.create": {"scope":"wh"},
        "shared.notifications.view": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"},
        "reports.operational.view": {"scope":"wh"}
      }
    },
    "production_manager": {
      "hierarchy_level": 55, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.products.create": {"scope":"ws"}, "inventory.products.update": {"scope":"ws"},
        "inventory.categories.view": {"scope":"ws"}, "inventory.categories.create": {"scope":"ws"}, "inventory.categories.update": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.variants.create": {"scope":"ws"}, "inventory.variants.update": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"},
        "inventory.levels.view": {"scope":"ws"}, "inventory.levels.adjust": {"scope":"ws"},
        "inventory.batches.view": {"scope":"ws"}, "inventory.batches.create": {"scope":"ws"}, "inventory.batches.update": {"scope":"ws"},
        "inventory.units.view": {"scope":"ws"}, "inventory.units.create": {"scope":"ws"}, "inventory.units.update": {"scope":"ws"},
        "inventory.transfers.view": {"scope":"ws"}, "inventory.logs.view": {"scope":"ws"},
        "purchasing.orders.view": {"scope":"ws"}, "purchasing.orders.create": {"scope":"ws"},
        "manufacturing.bom.view": {"scope":"ws"}, "manufacturing.bom.create": {"scope":"ws"}, "manufacturing.bom.update": {"scope":"ws"}, "manufacturing.bom.delete": {"scope":"ws"},
        "manufacturing.production.view": {"scope":"ws"}, "manufacturing.production.create": {"scope":"ws"}, "manufacturing.production.update": {"scope":"ws"}, "manufacturing.production.cancel": {"scope":"ws"},
        "manufacturing.work_centers.view": {"scope":"ws"}, "manufacturing.work_centers.create": {"scope":"ws"}, "manufacturing.work_centers.update": {"scope":"ws"}, "manufacturing.work_centers.delete": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.projects.create": {"scope":"ws"}, "projects.projects.update": {"scope":"ws"},
        "projects.tasks.view": {"scope":"ws"}, "projects.tasks.create": {"scope":"ws"}, "projects.tasks.update": {"scope":"ws"}, "projects.tasks.delete": {"scope":"ws"},
        "shared.attachments.view": {"scope":"ws"}, "shared.attachments.create": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "shared.approvals.view": {"scope":"ws"}, "shared.approvals.manage": {"scope":"ws"}, "shared.approvals.escalate": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"}, "ai.changes.request": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}, "reports.operational.export": {"scope":"ws"}
      }
    },
    "cashier": {
      "hierarchy_level": 40, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.branches.view": {"scope":"branch"},
        "inventory.products.view": {"scope":"ws"}, "inventory.categories.view": {"scope":"ws"},
        "inventory.variants.view": {"scope":"ws"}, "inventory.units.view": {"scope":"ws"},
        "sales.orders.view": {"scope":"branch"}, "sales.orders.create": {"scope":"branch"},
        "sales.pos.view": {"scope":"branch"},
        "sales.pos_sessions.open": {"scope":"branch"}, "sales.pos_sessions.close": {"scope":"branch"}, "sales.pos_sessions.view": {"scope":"own"},
        "sales.dining.view": {"scope":"branch"},
        "sales.pricing.view": {"scope":"ws"}, "sales.promotions.view": {"scope":"ws"}, "sales.coupons.view": {"scope":"ws"},
        "sales.bookings.view": {"scope":"branch"}, "sales.bookings.create": {"scope":"branch"},
        "finance.payments.view": {"scope":"own"}, "finance.payments.create": {"scope":"branch"},
        "shared.notifications.view": {"scope":"ws"},
        "ai.chat.use": {"scope":"ws"},
        "reports.operational.view": {"scope":"branch"}
      }
    },
    "employee": {
      "hierarchy_level": 20, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "admin.users.view": {"scope":"own"}, "admin.users.update": {"scope":"own"},
        "hr.employees.view": {"scope":"own"}, "hr.employees.update": {"scope":"own"},
        "hr.attendance.view": {"scope":"own"}, "hr.attendance.create": {"scope":"own"},
        "hr.leaves.view": {"scope":"own"}, "hr.leaves.create": {"scope":"own"},
        "hr.payroll.view": {"scope":"own"}, "hr.shifts.view": {"scope":"own"},
        "projects.projects.view": {"scope":"own"},
        "projects.tasks.view": {"scope":"own"}, "projects.tasks.update": {"scope":"own"},
        "shared.attachments.view": {"scope":"own"}, "shared.attachments.create": {"scope":"own"},
        "shared.notifications.view": {"scope":"own"},
        "shared.approvals.view": {"scope":"own"},
        "ai.chat.use": {"scope":"ws"}
      }
    },
    "investor": {
      "hierarchy_level": 15, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"}, "admin.subscription.view": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "finance.invoices.view": {"scope":"ws"}, "finance.invoices.export": {"scope":"ws"},
        "finance.payments.view": {"scope":"ws"},
        "finance.transactions.view": {"scope":"ws"},
        "finance.accounts.view": {"scope":"ws"},
        "finance.journal_entries.view": {"scope":"ws"}, "finance.journal_entries.export": {"scope":"ws"},
        "finance.fixed_assets.view": {"scope":"ws"},
        "finance.recurring_expenses.view": {"scope":"ws"},
        "finance.reports.view": {"scope":"ws"}, "finance.reports.export": {"scope":"ws"},
        "reports.financial.view": {"scope":"ws"}, "reports.financial.export": {"scope":"ws"},
        "reports.executive.view": {"scope":"ws"}, "reports.executive.export": {"scope":"ws"}
      }
    },
    "viewer": {
      "hierarchy_level": 10, "is_system": false, "deletable": true,
      "permissions": {
        "admin.workspace.view": {"scope":"ws"},
        "admin.branches.view": {"scope":"ws"}, "admin.departments.view": {"scope":"ws"},
        "shared.notifications.view": {"scope":"ws"},
        "inventory.products.view": {"scope":"ws"}, "inventory.categories.view": {"scope":"ws"},
        "inventory.warehouses.view": {"scope":"ws"},
        "sales.orders.view": {"scope":"ws"}, "sales.bookings.view": {"scope":"ws"},
        "shared.contacts.view": {"scope":"ws"},
        "projects.projects.view": {"scope":"ws"}, "projects.tasks.view": {"scope":"ws"},
        "reports.operational.view": {"scope":"ws"}
      }
    }
  },
  "sod_conflicts": [
    {"a": "finance.invoices.create", "b": "finance.payments.create", "severity": "CRITICAL", "rationale": "Create fake invoice and self-pay"},
    {"a": "admin.users.create", "b": "admin.users.approve", "severity": "CRITICAL", "rationale": "Create ghost employees and self-approve"},
    {"a": "finance.journal_entries.create", "b": "finance.accounts.create", "severity": "HIGH", "rationale": "Create fake accounts and post fraudulent entries"},
    {"a": "inventory.levels.adjust", "b": "inventory.products.delete", "severity": "HIGH", "rationale": "Adjust stock then delete product to hide theft"},
    {"a": "finance.invoices.create", "b": "finance.invoices.approve", "severity": "HIGH", "rationale": "Self-approve own invoices"},
    {"a": "hr.payroll.process", "b": "hr.employees.create", "severity": "HIGH", "rationale": "Create phantom employee and process salary"},
    {"a": "purchasing.orders.create", "b": "finance.payments.create", "severity": "HIGH", "rationale": "Create PO for phantom supplier and self-pay"},
    {"a": "admin.roles.create", "b": "admin.roles.update", "severity": "HIGH", "rationale": "Create a new role with elevated permissions for self"}
  ],
  "approval_rules": [
    {"entity": "leave", "condition": "any", "step1": ["department_head", "hr_manager"], "step2": ["admin"], "escalate_hours": 48},
    {"entity": "stock_transfer", "condition": "any", "step1": ["warehouse_manager"], "step2": ["admin"], "escalate_hours": 24},
    {"entity": "purchase_order", "condition": "amount <= 5000", "step1": ["purchasing_officer"], "step2": null, "escalate_hours": null},
    {"entity": "purchase_order", "condition": "amount > 5000", "step1": ["purchasing_officer"], "step2": ["admin", "owner"], "escalate_hours": 48},
    {"entity": "invoice_cancel", "condition": "any", "step1": ["accountant"], "step2": ["owner"], "escalate_hours": 24},
    {"entity": "payment", "condition": "amount <= 10000", "step1": ["accountant"], "step2": null, "escalate_hours": null},
    {"entity": "payment", "condition": "amount > 10000", "step1": ["accountant"], "step2": ["owner"], "escalate_hours": 24},
    {"entity": "journal_entry", "condition": "any", "step1": ["accountant"], "step2": null, "escalate_hours": null},
    {"entity": "user_join", "condition": "any", "step1": ["hr_manager", "admin"], "step2": ["owner"], "escalate_hours": 72},
    {"entity": "ai_system_change", "condition": "any", "step1": ["owner", "co_owner"], "step2": null, "escalate_hours": null},
    {"entity": "production_order", "condition": "any", "step1": ["production_manager"], "step2": ["admin"], "escalate_hours": 48}
  ]
}
```

---

*End of specification. Version 1.0 — 2026-04-01.*
