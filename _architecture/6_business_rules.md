اكتب الملف ده في:
`_architecture/6_business_rules.md`

```md
# SmartBiz AI — Business Rules

## 1. Purpose

This document defines the **core business rules that govern system behavior** across SmartBiz AI.

These rules ensure that:

- ERP operations remain consistent
- financial integrity is preserved
- tenant isolation is enforced
- AI changes remain controlled
- system behavior is predictable
- abuse is prevented
- operational safety is guaranteed

These rules apply to:

- backend services
- AI orchestration
- ERP workflows
- platform governance
- workspace operations

---

# 2. Global System Principles

SmartBiz AI follows these fundamental principles:

### 2.1 Tenant Isolation
All workspace data must remain isolated.

Rules:
- every tenant-scoped table must include `workspace_id`
- RLS policies must enforce workspace isolation
- cross-workspace queries are forbidden
- workspace context must be enforced at session level

### 2.2 Source of Truth
Certain tables are authoritative sources.

Examples:

| Domain | Source of Truth |
|------|------|
Accounting balances | journal_lines |
Invoice financial data | invoices + invoice_items |
Inventory movement | inventory_movements |
Payment history | payments |
User roles | workspace_memberships |

Cached fields must always be derived.

### 2.3 Auditability
Every sensitive operation must produce an audit log.

Examples:
- role changes
- permission changes
- invoice status changes
- payment recording
- inventory adjustments
- AI configuration changes
- workspace settings changes

### 2.4 Predictability
System actions must behave consistently.

Rules:
- no hidden behavior
- no implicit financial changes
- all automatic operations must be traceable

---

# 3. Workspace Rules

### 3.1 Workspace Creation

Rules:

- a user may create **one workspace freely**
- additional workspace creation may require:
  - verified email
  - verified phone
  - cooldown period
  - active subscription plan

Purpose:
prevent AI token abuse and system spam.

### 3.2 Workspace Ownership

Rules:

- every workspace must always have **at least one owner**
- ownership transfer must be explicit
- owner cannot be removed without transfer

### 3.3 Workspace Deletion

Rules:

Workspace deletion requires:

- owner confirmation
- password confirmation
- optional cooldown
- irreversible confirmation

Deletion should mark workspace as:

`pending_deletion`

before final purge.

---

# 4. User Membership Rules

### 4.1 Membership Requirement

Every workspace operation requires:

- authenticated user
- active workspace membership
- sufficient permissions

### 4.2 Pending Membership

Users joining via workspace code remain:

`pending`

until approval.

Pending users cannot access ERP data.

### 4.3 Membership Removal

Removing a user must:

- revoke permissions
- invalidate sessions
- generate audit log

---

# 5. Role Rules

### 5.1 Owner Protection

Rules:

- owner role cannot be deleted
- workspace must always have owner
- ownership transfer must be audited

### 5.2 Role Assignment

Only users with appropriate permission can:

- assign roles
- change roles
- revoke roles

### 5.3 Permission Enforcement

Every backend endpoint must verify:

- membership
- role
- permission capability

Never rely on frontend checks.

---

# 6. ERP Operational Rules

ERP operations must follow strict consistency rules.

---

# 7. Product Rules

### Product Creation

Rules:

- product name required
- product SKU optional but recommended
- unit must exist
- product category optional

### Product Updates

Rules:

- price changes must not affect historical invoices
- product deletion should be soft-deletion

---

# 8. Inventory Rules

### 8.1 Inventory Integrity

Inventory cannot be silently modified.

All stock changes must create:

`inventory_movement`

records.

### 8.2 Negative Inventory

System may allow or prevent negative stock depending on workspace configuration.

Default rule:

negative stock **not allowed**.

### 8.3 Stock Transfer

Stock transfer must:

- reduce source warehouse
- increase destination warehouse
- generate transfer log

Atomic operation required.

---

# 9. Order Rules

Orders represent intent to sell.

Rules:

- orders may remain drafts
- orders may convert to invoices
- orders do not affect accounting until invoiced

---

# 10. Invoice Rules

Invoices represent financial commitment.

### Invoice Creation

Rules:

- invoice must contain at least one item
- invoice currency must match workspace currency
- invoice total must be calculated from items

### Invoice Status

Typical statuses:

- draft
- issued
- partially_paid
- paid
- cancelled

### Invoice Cancellation

Rules:

- cancelled invoices must remain in history
- cancellation must produce audit log

---

# 11. Payment Rules

### Payment Creation

Payments must:

- reference invoice or customer
- record payment method
- record payment amount

### Overpayment

System may allow overpayment.

Excess amount becomes customer credit.

### Payment Reversal

Reversal must create:

- reversal record
- accounting adjustment

---

# 12. Accounting Rules

Accounting system must guarantee ledger integrity.

### 12.1 Journal Entry Balance

Every journal entry must satisfy:

```

total_debits == total_credits

```
```

Unbalanced entries must be rejected.

### 12.2 Posting Rules

ERP actions that may trigger accounting entries:

- invoice posting
- payment recording
- refunds
- expense recording

### 12.3 Cached Balances

Fields such as:

- account.balance
- contact.balance

are **cached values only**.

Source of truth remains:

ledger tables.

---

# 13. Approval Rules

Some operations require approval.

Examples:

| Action | Approval Required |
|------|------|
employee join | HR/Admin |
stock transfer | Admin/Warehouse manager |
AI config change | Owner/Co-owner |
leave request | HR/Department head |

Approvals must record:

- approver
- decision
- timestamp
- reason

---

# 14. AI System Rules

AI must operate under strict governance.

### 14.1 AI Cannot Modify System Directly

AI must:

- propose change
- generate structured request
- wait for approval

### 14.2 Structured Output Only

AI outputs that affect system configuration must be:

- JSON structured
- schema validated

### 14.3 AI Cannot Generate SQL

AI must never execute direct SQL operations.

All actions go through backend services.

---

# 15. Unsupported Feature Rules

If user requests unsupported feature:

AI must:

- respond honestly
- log feature request
- inform user request recorded

AI must not:

- fake feature support
- promise release date

---

# 16. Feature Request Rules

Feature requests must:

- be aggregated by normalized key
- track number of workspaces requesting
- track number of users requesting

Platform team can:

- review
- prioritize
- release feature

---

# 17. Notification Rules

Notifications must be stored persistently.

Notification categories:

- approvals
- AI suggestions
- ERP alerts
- feature releases
- platform broadcasts

Notifications must support:

- read state
- link to entity

---

# 18. Offline Sync Rules

Offline mode supports only limited operations.

Allowed offline:

- POS drafts
- sales drafts
- product browsing
- customer selection

Not allowed offline:

- accounting reports
- AI chat
- payroll processing
- approvals

### Sync Replay

Offline operations must include:

- operation_id
- timestamp
- device_id

Backend must reject duplicate operations.

---

# 19. File Upload Rules

Files must pass validation.

Rules:

- allowed file types only
- size limits enforced
- virus scanning optional later
- object storage used

---

# 20. Security Rules

Security is mandatory.

### Password Rules

- passwords hashed
- never stored in plaintext

### Authentication Rules

JWT tokens must:

- expire
- support refresh rotation

### Rate Limiting

Must apply to:

- login endpoints
- AI endpoints
- sensitive operations

---

# 21. Tenant Security Rules

Every request must enforce:

- workspace membership
- role permission
- workspace scope

Cross-tenant data access is forbidden.

---

# 22. Error Handling Rules

Errors must be:

- structured
- predictable
- safe

Error categories:

- validation_error
- auth_error
- permission_error
- conflict_error
- ai_error
- internal_error

Sensitive internal details must never be exposed.

---

# 23. Performance Rules

Backend must enforce:

- pagination
- indexed queries
- bounded list sizes
- background jobs for heavy operations

Large operations must be asynchronous.

---

# 24. Background Job Rules

Background workers should handle:

- AI analytics
- cached balance refresh
- low stock detection
- notification fanout
- scheduled reminders

---

# 25. Platform Governance Rules

Platform owner may:

- suspend abusive workspace
- limit AI usage
- review suspicious behavior

All actions must be audited.

---

# 26. Logging Rules

Important events must be logged.

Examples:

- login success/failure
- invoice creation
- payment recording
- AI change proposal
- approval decision
- workspace configuration change

Logs support:

- debugging
- compliance
- analytics

---

# 27. Data Retention Rules

Certain records must not be deleted.

Examples:

- invoices
- payments
- journal entries
- audit logs

Instead use:

soft deletion or archival.

---

# 28. Compliance Rules

System must maintain:

- traceable financial records
- immutable ledger behavior
- audit trails

Future compliance may include:

- VAT rules
- regional accounting standards
- audit exports

---

# 29. Platform Resource Protection

System must protect:

- AI tokens
- infrastructure resources

Mechanisms include:

- rate limits
- plan limits
- AI quotas
- workspace creation restrictions

---

# 30. Definition of Done

Business rule implementation is considered correct when:

- tenant isolation is guaranteed
- financial integrity cannot be violated
- role permissions enforce behavior
- approvals govern sensitive actions
- AI cannot bypass governance
- unsupported feature requests are captured
- offline sync cannot corrupt state
- platform governance is enforceable
```
