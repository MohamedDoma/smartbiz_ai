# SmartBiz AI — Operational Business Rules Specification (v1.0)

> **Authority**: This document is the authoritative source of truth for all business logic, entity lifecycles, financial controls, approval governance, and cross-module invariants in the SmartBiz AI platform.
>
> **Cross-references**:
> - Schema: `1_database_schema.sql`
> - RBAC: `7_roles_permissions_matrix.md`
>
> **Convention**: All permission checks reference the approved RBAC permission registry using `permission.key @ scope_code`. No hardcoded job titles are used anywhere.

---

## 1. Introduction & Design Standard

### 1.1 Purpose

This specification defines every operational business rule that governs SmartBiz AI system behavior. These rules ensure:

- ERP operations remain consistent and predictable
- Financial integrity is preserved across all transactions
- Tenant isolation is enforced at every layer
- Approval governance controls sensitive actions
- AI changes remain human-supervised
- Audit trails support compliance and forensics

### 1.2 Rule ID Format

```
BR-{MODULE}-{NNN}
```

| Component | Values |
|-----------|--------|
| `BR` | Business Rule prefix |
| `MODULE` | `SYS` (system), `WKS` (workspace), `MBR` (membership), `ROL` (role), `ORD` (order), `INV` (invoice), `PAY` (payment), `RFD` (refund/return), `PUR` (purchasing), `FIN` (finance), `STK` (inventory/stock), `SHP` (shipment), `HR` (human resources), `LVE` (leave), `ATT` (attendance), `PRL` (payroll), `APR` (approval), `AI` (AI governance), `NTF` (notification), `PLT` (platform), `XMD` (cross-module) |
| `NNN` | Sequential 3-digit number within module |

### 1.3 Rule Structure

Every rule follows this structure:

| Field | Description |
|-------|-------------|
| **Preconditions** | What must be true before the rule applies |
| **Permission** | RBAC permission key + scope required |
| **Logic** | The constraint or behavior enforced |
| **Side-effects** | Audit log, notification, accounting entry, status change |
| **Exceptions** | Override conditions or cases where rule does not apply |
| **Audit** | What must be logged |
| **Schema** | Tables/columns involved |

### 1.4 Conventions

- `MUST` / `MUST NOT` = mandatory constraint
- `WHEN` / `ONLY IF` = conditional trigger
- `UNLESS` = exception clause
- Permission format: `permission.key @ scope_code`
- Scope codes: `ws`, `branch`, `dept`, `team`, `own`, `wh`

---

## 2. Global System Principles

**BR-SYS-001**: Tenant Isolation
- Preconditions: Any data operation
- Permission: Enforced at infrastructure level
- Logic: Every tenant-scoped table MUST include `workspace_id`. RLS policies MUST enforce workspace isolation. Cross-workspace queries are forbidden. Workspace context MUST be set at database session level via `SET app.current_workspace_id`.
- Side-effects: None
- Exceptions: Platform-scoped tables (`platform_*`) are exempt
- Audit: Cross-workspace access attempts MUST generate `security_violation` event
- Schema: All workspace-scoped tables, RLS policies

**BR-SYS-002**: Source of Truth Doctrine
- Preconditions: Any read or calculation involving derived data
- Permission: N/A
- Logic: The following are authoritative sources. Cached/denormalized fields MUST be derived from these, never the reverse.
- Side-effects: Background jobs refresh cached balances

| Domain | Source of Truth | Cached fields |
|--------|----------------|---------------|
| Account balances | `journal_lines` | `accounts.balance` |
| Invoice financials | `invoices` + `invoice_items` | `invoices.total_amount` |
| Inventory quantities | `inventory_movements` | `inventory_levels.quantity` |
| Payment history | `payments` | `contacts.balance` |
| User permissions | `workspace_memberships` + `roles` + `user_permission_overrides` | Session cache |

- Exceptions: None
- Audit: Balance recalculation runs MUST log discrepancies
- Schema: All listed source tables

**BR-SYS-003**: Auditability Mandate
- Preconditions: Any sensitive operation
- Permission: N/A (system-enforced)
- Logic: Every operation in the following categories MUST produce an `audit_logs` entry with: `event_type`, `actor_id`, `workspace_id`, `entity_type`, `entity_id`, `old_value`, `new_value`, `timestamp`, `ip_address`.
- Categories: role changes, permission changes, invoice status changes, payment recording, inventory adjustments, AI configuration changes, workspace settings, approval decisions, user creation/removal, payroll processing, fiscal period lock/unlock
- Side-effects: `audit_logs` INSERT
- Exceptions: Read-only operations are exempt
- Audit: Self-referential — this rule IS the audit mandate
- Schema: `audit_logs`

**BR-SYS-004**: Predictability
- Logic: No hidden behavior. No implicit financial changes. All automatic operations (background jobs, triggers, scheduled tasks) MUST be traceable in audit logs with `actor_type = 'system'`.

**BR-SYS-005**: Soft Deletion Policy
- Logic: The following entities MUST NOT be hard-deleted: invoices, payments, journal entries, audit logs, inventory movements, payroll records, approval decisions. Instead, use `is_deleted = true` or `status = 'archived'`.
- Schema: Applicable tables need `is_deleted` or archival status

**BR-SYS-006**: Data Immutability
- Logic: After an entity enters a finalized state (`posted`, `paid`, `disbursed`, `locked`), its financial content (amounts, accounts, line items) MUST NOT be modified. Corrections MUST be made via reversal + new entry.

---

## 3. Workspace Lifecycle Rules

### 3.1 Workspace State Machine

```
[active] ──suspend──► [suspended] ──reactivate──► [active]
   │                       │
   └──request_delete──► [pending_deletion] ──purge──► [deleted]
                           │
                           └──cancel_delete──► [active]
```

| Transition | Guard | Permission |
|-----------|-------|------------|
| `→ active` (create) | Verified email; max workspace limit not exceeded | `platform.workspaces.view` (implicit on registration) |
| `active → suspended` | Platform action only | `platform.workspaces.suspend` |
| `suspended → active` | Platform action only | `platform.workspaces.reactivate` |
| `active → pending_deletion` | Owner confirmation + password verification | `admin.ownership.delete @ ws` |
| `pending_deletion → deleted` | 30-day cooldown elapsed | System job |
| `pending_deletion → active` | Owner cancels within cooldown | `admin.ownership.delete @ ws` |

**BR-WKS-001**: Workspace Creation Limits
- Logic: A user may create one workspace freely. Additional workspaces require: verified email, verified phone, and an active subscription plan on any existing workspace.
- Audit: `workspace_created` event

**BR-WKS-002**: Ownership Invariant
- Logic: Every workspace MUST have at least one user holding the `owner` role template at all times. The system MUST reject any operation that would leave a workspace with zero owners.
- Audit: `ownership_transfer` event on any owner change

**BR-WKS-003**: Ownership Transfer
- Logic: Transfer requires explicit action by current owner. Target user MUST be an active member of the workspace. Transfer MUST be confirmed with password.
- Permission: `admin.ownership.transfer @ ws`
- Audit: `ownership_transfer` with `old_owner_id`, `new_owner_id`

**BR-WKS-004**: Workspace Deletion
- Logic: Deletion marks workspace as `pending_deletion`. A 30-day cooldown applies. During cooldown, workspace is read-only. After cooldown, system job purges all workspace data. Owner may cancel deletion during cooldown.
- Permission: `admin.ownership.delete @ ws`
- Audit: `workspace_deletion_requested`, `workspace_deletion_cancelled`, `workspace_deleted`

**BR-WKS-005**: Subscription Seat Enforcement
- Logic: Before adding a new member to a workspace (inserting into `workspace_memberships` with status `pending` or `active`), the system MUST verify that the count of active members (status = `active`) is strictly less than the seat limit defined by the workspace's current subscription plan. If the seat limit is reached, the operation MUST be rejected with an informative error: "Seat limit reached. Upgrade your plan to add more members." Pending members count toward the seat limit to prevent approval-time overflows.
- Schema: `workspace_subscriptions` → `subscription_plans.max_members`, `workspace_memberships`
- Exceptions: Platform administrators may override seat limits via `platform.workspaces.manage` for support/debugging purposes. Override MUST generate `seat_limit_override` audit event.
- Audit: `seat_limit_reached` with `workspace_id`, `current_count`, `plan_limit`

**BR-WKS-006**: Subscription Renewal Failure
- Logic: When a subscription payment fails at renewal time, the system MUST follow this escalation sequence:
  1. **Grace period** (7 days, platform-configurable): workspace remains fully functional. Owner is notified daily.
  2. **Restricted mode** (days 8–14): workspace becomes read-only for non-owner members. Owner retains full access to update payment method. System sends escalated notification.
  3. **Suspension** (day 15+): workspace `status` transitions to `suspended` (BR-PLT-001 rules apply). Only data export by owner is permitted.
  4. If payment is recovered at any stage, workspace immediately returns to `active` status.
- Schema: `workspace_subscriptions.renewal_attempts`, `workspace_subscriptions.last_renewal_failure_at`
- Audit: `renewal_failed` with `workspace_id`, `attempt_number`, `failure_reason`; `renewal_recovered` on successful retry

---

## 4. Membership & Authentication Rules

### 4.1 Membership State Machine

```
[pending] ──approve──► [active] ──suspend──► [suspended] ──reactivate──► [active]
   │                      │
   └──reject──► [rejected]  └──remove──► [removed]
```

**BR-MBR-001**: Access Precondition
- Logic: Every workspace operation requires: (1) authenticated user, (2) active workspace membership (`status = 'active'`), (3) sufficient permission at applicable scope.
- Exceptions: Platform-level operations use platform roles, not workspace membership.

**BR-MBR-002**: Pending Membership
- Logic: Users joining via workspace invitation code enter `pending` status. Pending users MUST NOT access any ERP data. Pending users may view workspace name and their own membership status only.
- Permission to approve: `admin.users.approve @ ws|branch|dept`

**BR-MBR-003**: Membership Removal
- Logic: Removing a member MUST: (1) revoke all role assignments, (2) invalidate all active sessions and refresh tokens, (3) remove user-level permission overrides, (4) generate audit log.
- Permission: `admin.users.delete @ ws`
- Exceptions: Cannot remove the last owner (BR-WKS-002)
- Audit: `member_removed` with `user_id`, `removed_by`, `roles_revoked[]`

**BR-MBR-004**: Password Policy
- Logic: Passwords MUST be hashed using bcrypt (cost ≥ 12) or argon2id. Minimum 8 characters. Never stored or logged in plaintext.

**BR-MBR-005**: Token Management
- Logic: JWT access tokens MUST expire within 15–60 minutes (workspace-configurable). Refresh tokens MUST support rotation: each use invalidates the previous token. Concurrent session limit: configurable, default 5.

**BR-MBR-006**: Rate Limiting
- Logic: Rate limits MUST apply to: login (5 attempts/min), registration (3/hour), AI endpoints (per plan quota), password reset (3/hour), API general (configurable per plan).

**BR-MBR-007**: Session Invalidation on Role Change
- Logic: WHEN a user's role assignment or permissions change, all active sessions for that user MUST be invalidated within 60 seconds. User must re-authenticate to receive updated permission set.
- Schema: `workspace_memberships`, session store
- ⚠️ Schema dependency: requires `workspace_memberships` table (RBAC §14 change #1)

---

## 5. Role & Permission Enforcement Rules

**BR-ROL-001**: Runtime Permission Check
- Logic: Every backend endpoint MUST verify: (1) user has active membership, (2) user holds the required permission key, (3) permission scope is satisfied against the requested resource. Frontend checks are supplementary only — NEVER authoritative.
- Permission: Endpoint-specific from RBAC registry

**BR-ROL-002**: Scope Enforcement
- Logic: When a permission is granted with a scope code, the backend MUST apply the corresponding filter:

| Scope | Filter |
|-------|--------|
| `ws` | `WHERE workspace_id = current_workspace` |
| `branch` | `WHERE branch_id = user.branch_id` |
| `dept` | `WHERE department_id = user.department_id` |
| `team` | `WHERE user_id IN (SELECT id FROM users WHERE manager_id = current_user)` |
| `own` | `WHERE created_by = current_user OR assigned_to = current_user OR user_id = current_user` |
| `wh` | `WHERE warehouse_id IN (user.warehouse_ids)` |

**BR-ROL-003**: Hierarchy Guard for Role Assignment
- Logic: A user can only assign, modify, or revoke roles with a `hierarchy_level` strictly lower than their own. Cannot self-elevate.
- Permission: `admin.roles.create @ ws` or `admin.roles.update @ ws`
- Audit: `role_assigned` / `role_revoked` with actor, target, role_id

**BR-ROL-004**: SoD Enforcement
- Logic: When assigning permissions (via role or user override), the system MUST check against the 8 SoD conflict pairs defined in RBAC §11. CRITICAL conflicts MUST block the assignment. HIGH conflicts MUST warn and require explicit owner-level override.
- Audit: `sod_override` with conflict_pair, override_reason, approver_id

**BR-ROL-005**: Custom Role Validation
- Logic: Custom workspace roles MUST: (1) have a unique name within the workspace, (2) have `hierarchy_level` between 1 and 99, (3) only include permission keys from the approved registry, (4) pass SoD conflict check. Custom roles inherit `is_system = false`, `deletable = true`.
- Permission: `admin.roles.create @ ws`

**BR-ROL-006**: User-Level Override Resolution
- Logic: Permission resolution order: (1) check role permissions, (2) apply user-level grants (additive), (3) apply user-level denials (override grants). Denial always wins over grant for the same permission key.

**BR-ROL-007**: Temporary Delegation
- Logic: A user may delegate specific permissions to another user for a defined time window. Delegation MUST specify: permission keys, scope, start_time, end_time, delegate_user_id. Delegated permissions expire automatically. Delegator MUST hold the permission being delegated.
- Permission: User must hold the delegated permission at equal or wider scope
- Audit: `permission_delegated`, `delegation_expired`
- ⚠️ Schema dependency: requires `permission_delegations` table (RBAC §14 change #5)

---

## 6. Order Lifecycle Rules

### 6.1 Sales Order State Machine

```
[draft] ──confirm──► [confirmed] ──fulfill──► [partially_fulfilled] ──fulfill──► [fulfilled]
   │                      │                                                          │
   └──cancel──► [cancelled] └──cancel──► [cancelled]                    close──► [closed]
```

| Transition | Guard | Permission | Side-effects |
|-----------|-------|------------|-------------|
| `→ draft` | Customer or internal reference | `sales.orders.create @ scope` | None |
| `draft → confirmed` | At least 1 line item; quantities > 0 | `sales.orders.update @ scope` | Stock reservation created (BR-STK-001) |
| `confirmed → partially_fulfilled` | At least 1 shipment created | `sales.orders.update @ scope` | Per-shipment stock deduction |
| `partially_fulfilled → fulfilled` | All lines fully shipped | System auto-transition | — |
| `fulfilled → closed` | All lines invoiced and paid | System auto-transition | — |
| `draft → cancelled` | Always allowed | `sales.orders.cancel @ scope` | None |
| `confirmed → cancelled` | No shipments created | `sales.orders.cancel @ scope` | Stock reservation released (BR-STK-002) |

**BR-ORD-001**: Order Content
- Logic: An order MUST contain at least one line item. Each line MUST reference a valid product, specify quantity > 0, and have a unit price.

**BR-ORD-002**: Order Does Not Affect Accounting
- Logic: Orders do NOT create journal entries. Accounting impact begins only at invoice creation.

**BR-ORD-003**: Order-to-Invoice Conversion
- Logic: An order (or subset of order lines) may be converted to an invoice. The invoice MUST reference the originating order. Partial invoicing is allowed.

**BR-ORD-004**: Price Snapshot
- Logic: At the time of order confirmation, unit prices MUST be snapshotted onto order lines. Subsequent product price changes MUST NOT affect existing orders.

**BR-ORD-005**: Cancellation Guard
- Logic: A confirmed order MUST NOT be cancelled if any shipment has been created against it. Only unfulfilled lines may be cancelled on a partially fulfilled order.
- Audit: `order_cancelled` with `order_id`, `reason`, `cancelled_lines[]`

**BR-ORD-006**: Stock Reservation on Confirmation
- Logic: WHEN an order transitions to `confirmed`, the system MUST create stock reservations for each line item, reducing available (unreserved) stock. Reserved stock is not available for other orders.
- Schema: `inventory_levels` (available vs reserved columns needed)

**BR-ORD-007**: Service Product Stock Bypass
- Logic: If a product is flagged as a service product (`products.product_type = 'service'`), the system MUST skip all stock-related operations for that line item: no stock reservation (BR-ORD-006), no inventory movement on fulfillment (BR-STK-003), no low-stock alerts. Service products are tracked by revenue only, not by quantity. Orders containing a mix of physical and service products MUST process stock operations only for physical items.
- Schema: `products.product_type` (expected values: `goods`, `service`)
- Exceptions: None — service products MUST NEVER trigger inventory operations.

### 6.2 CRM / Lead & Opportunity Lifecycle

#### Lead State Machine

```
[new] ──contact──► [contacted] ──qualify──► [qualified] ──convert──► [converted]
  │                    │                        │
  └──disqualify──► [lost]  └──disqualify──► [lost]  └──(terminal: becomes contact + opportunity)
```

#### Opportunity State Machine

```
[open] ──advance──► [negotiation] ──win──► [won]
  │                      │
  └──lose──► [lost]      └──lose──► [lost]
```

**BR-CRM-001**: Lead Creation
- Logic: A lead MUST contain at minimum: name (person or company), source (manual, web form, AI import, referral), and workspace assignment. Duplicate detection MUST run on creation: if a matching contact already exists (by email or phone), the system warns and allows linking or merging.
- Permission: `crm.leads.create @ scope`
- Audit: `lead_created` with `lead_id`, `source`
- Schema: `leads`

**BR-CRM-002**: Lead Qualification
- Logic: A lead transitions to `qualified` when it meets workspace-defined qualification criteria (e.g., confirmed budget, decision-maker identified, timeline established). Qualification MUST be an explicit user action, not automatic.
- Permission: `crm.leads.update @ scope`
- Side-effects: Notification to assigned sales user
- Audit: `lead_qualified` with `lead_id`, `qualification_criteria_met`

**BR-CRM-003**: Lead Conversion
- Logic: A `qualified` lead may be converted. Conversion MUST: (1) create a new contact record (if one does not exist), (2) create an opportunity linked to the new contact, (3) optionally create a draft sales order. The lead record is marked `converted` and retains its history. Conversion is irreversible.
- Permission: `crm.leads.update @ scope`
- Side-effects: Contact created, opportunity created, lead marked `converted`
- Audit: `lead_converted` with `lead_id`, `contact_id`, `opportunity_id`

**BR-CRM-004**: Opportunity Stage Progression
- Logic: Opportunity stages are workspace-configurable (default: `open`, `negotiation`, `proposal_sent`, `won`, `lost`). Each stage change MUST be an explicit user action. Stage changes MUST be forward-only — reverting to a prior stage requires reason and generates audit log.
- Permission: `crm.opportunities.update @ scope`
- Audit: `opportunity_stage_changed` with `opportunity_id`, `old_stage`, `new_stage`, `reason`

**BR-CRM-005**: Opportunity Closure
- Logic: An opportunity is closed as `won` or `lost`. Closing as `won` MUST link to a confirmed sales order and is irreversible. Closing as `lost` MUST record a loss reason code (workspace-configurable list). Lost opportunities may be reopened within 30 days with manager-level approval.
- Permission: `crm.opportunities.update @ scope`
- Exceptions: Reopen requires user holding `crm.opportunities.update @ ws` (wider scope than original owner)
- Audit: `opportunity_won` / `opportunity_lost` with `opportunity_id`, `reason`, `order_id` (if won)

**BR-CRM-006**: CRM Activity Logging
- Logic: All interactions with a lead or opportunity (calls, emails, meetings, notes) MUST be logged as activities with: `activity_type`, `timestamp`, `user_id`, `entity_type` (lead/opportunity), `entity_id`, `summary`. Activities are append-only and cannot be deleted.
- Permission: `crm.activities.create @ scope`
- Schema: `crm_activities`

---

## 7. Invoice Lifecycle Rules

### 7.1 Invoice State Machine

```
[draft] ──issue──► [issued] ──pay──► [partially_paid] ──pay──► [paid]
   │                  │                                           │
   └──delete──► (removed)  └──cancel──► [cancelled]              (terminal)
                      │
                      └──overdue_check──► [overdue] ──pay──► [paid]
```

| Transition | Guard | Permission | Side-effects |
|-----------|-------|------------|-------------|
| `→ draft` | Valid customer/contact, ≥1 line item | `finance.invoices.create @ scope` | None |
| `draft → issued` | All line items valid; total > 0; tax calculated | `finance.invoices.update @ scope` | Journal entry posted (BR-FIN-001); sequence number assigned |
| `issued → partially_paid` | Payment received < total | System auto-transition | Payment journal entry (BR-PAY-002) |
| `partially_paid → paid` | Sum of payments ≥ invoice total | System auto-transition | — |
| `issued → paid` | Full payment received | System auto-transition | Payment journal entry |
| `issued → overdue` | Due date passed, balance > 0 | Background job | Notification to invoice owner |
| `overdue → paid` | Full payment received | System auto-transition | — |
| `issued → cancelled` | ONLY IF zero payments received | `finance.invoices.cancel @ scope` + approval | Reversal journal entry (BR-FIN-006) |
| `draft → (removed)` | Draft only | `finance.invoices.update @ scope` | Soft-delete |

**BR-INV-001**: Invoice Content
- Logic: An invoice MUST contain at least one line item. Each line MUST reference a product or description, quantity > 0, unit price ≥ 0, and applicable tax. Invoice total MUST be calculated as sum of (line_qty × line_price) + taxes.
- Schema: `invoices`, `invoice_items`

**BR-INV-002**: Invoice Immutability After Issue
- Logic: Once an invoice transitions to `issued`, its line items, amounts, tax, and customer reference MUST NOT be modified. Corrections require cancellation (if unpaid) or credit note (if partially/fully paid).

**BR-INV-003**: Invoice Cancellation
- Preconditions: Invoice status is `issued` or `overdue` AND zero payments recorded
- Permission: `finance.invoices.cancel @ scope`
- Logic: Cancellation MUST: (1) set status to `cancelled`, (2) create reversal journal entry (contra to original posting), (3) release any stock reservation if order-linked.
- Exceptions: Invoices with any payment MUST NOT be cancelled — issue a credit note instead (BR-RFD-001).
- Audit: `invoice_cancelled` with `invoice_id`, `reason`, `reversal_journal_id`

**BR-INV-004**: Credit Note
- Logic: A credit note is a negative invoice linked to the original invoice. It MUST: (1) reference the original invoice, (2) have negative line amounts, (3) create reversal journal entries, (4) generate customer credit or trigger refund.
- Permission: `finance.invoices.create @ scope`
- Audit: `credit_note_created` with `original_invoice_id`, `credit_note_id`
- ⚠️ Schema dependency: may require `credit_notes` table or `invoice_type` enum

**BR-INV-005**: Sequence Number
- Logic: When an invoice transitions to `issued`, it MUST be assigned a sequential, non-reusable invoice number from the workspace's configured sequence. Gaps in sequence are allowed (cancelled invoices retain their number).
- Schema: `sequences`

**BR-INV-006**: Multi-Currency Invoice
- Logic: Invoice currency MUST be a workspace-enabled currency. If invoice currency differs from workspace base currency, exchange rate MUST be recorded at time of issue. All journal entries post in both invoice currency and base currency.
- Schema: `invoices.currency`, `invoices.exchange_rate`

**BR-INV-007**: Tax Calculation
- Logic: Tax MUST be calculated per line item based on the product's tax configuration and the workspace's tax rules. Tax may be inclusive (price includes tax) or exclusive (tax added on top) — configurable per workspace. Multiple tax rates per line are supported (compound taxes calculated sequentially).
- Schema: `tax_rates`, `invoice_items.tax_amount`

**BR-INV-008**: Due Date
- Logic: Every issued invoice MUST have a due date. Default: workspace-configured payment terms (e.g., Net 30). Overdue detection runs as a background job daily.

**BR-INV-009**: Invoice Export
- Permission: `finance.invoices.export @ scope`
- Logic: Export generates PDF or CSV. Export MUST include invoice number, date, customer, lines, tax, total, payment status.

**BR-INV-010**: Discount Application
- Logic: Discounts may be applied per line item (percentage or fixed amount) or at invoice level. Discount MUST be applied before tax calculation. Promotional/coupon discounts MUST reference the source promotion and be validated for eligibility.
- Schema: `invoice_items.discount_amount`, `invoices.discount_total`

---

## 8. Payment Lifecycle Rules

### 8.1 Payment State Machine

```
[pending] ──complete──► [completed] ──reverse──► [reversed]
   │
   └──fail──► [failed]
```

| Transition | Guard | Permission | Side-effects |
|-----------|-------|------------|-------------|
| `→ pending` | Valid invoice or customer reference | `finance.payments.create @ scope` | — |
| `pending → completed` | Payment method validated, amount > 0 | `finance.payments.create @ scope` | Journal entry posted; invoice status updated |
| `pending → failed` | Payment method rejected or timeout | System | Notification to creator |
| `completed → reversed` | Approval required | `finance.payments.create @ scope` + approval | Reversal journal entry; invoice status reverted |

**BR-PAY-001**: Payment Reference
- Logic: Every payment MUST reference either: (1) a specific invoice (or set of invoices), or (2) a customer/contact for unallocated payment. Payment amount MUST be > 0.
- Schema: `payments`, `payment_allocations` (if multi-invoice)

**BR-PAY-002**: Payment Journal Entry
- Logic: On `completed`, the system MUST create a journal entry: debit cash/bank account, credit accounts receivable (or applicable account). Amount in both transaction currency and base currency.
- Schema: `journal_entries`, `journal_lines`

**BR-PAY-003**: Partial Payment Allocation
- Logic: When payment amount < invoice total, the payment is allocated to the invoice and invoice status transitions to `partially_paid`. Remaining balance is tracked. Multiple partial payments are allowed until total is covered.

**BR-PAY-004**: Overpayment Handling
- Logic: When payment amount > invoice total, excess MUST be recorded as customer credit. Credit is stored as a positive balance on the customer's account. Credit may be: (1) manually applied to a future invoice, (2) refunded via BR-RFD-003.
- Schema: `contacts.credit_balance` or `customer_credits` table
- ⚠️ Schema dependency: requires credit tracking mechanism

**BR-PAY-005**: Payment Reversal
- Logic: Reversal creates a new payment record with `is_reversal = true` linking to original. Reversal MUST: (1) create contra journal entry, (2) revert invoice status (paid → issued, partially_paid → issued if remaining = total), (3) require approval.
- Approval: Requires user holding `finance.payments.create @ scope` + separate approver holding `shared.approvals.manage @ scope` (maker-checker)
- Audit: `payment_reversed` with `original_payment_id`, `reason`
- ⚠️ Schema dependency: `payments.reversal_of`, `payments.is_reversal`

**BR-PAY-006**: Payment Methods
- Logic: Supported payment methods are workspace-configurable (cash, bank transfer, credit card, mobile payment, cheque, etc.). Each payment MUST record the method used.
- Schema: `payments.payment_method`

**BR-PAY-007**: Cash Payment POS Rules
- Logic: Cash payments within POS session MUST be linked to the active POS session. Cash received and change given MUST be recorded. Cash variance at session close MUST be tracked (BR-FIN-010).

**BR-PAY-008**: Payment Receipt
- Logic: Every completed payment MUST be capable of generating a receipt (printable/PDF) with: payment reference, amount, method, date, invoice reference(s), customer name.

**BR-PAY-009**: Payment Idempotency
- Logic: All payment creation endpoints MUST require an `Idempotency-Key` header (UUID or client-generated string, max 255 chars). The server MUST: (1) store the key in `idempotency_keys` table with the response payload, (2) if the same key is received within 24 hours, return the stored response without re-executing, (3) reject requests without the header with HTTP 400. This prevents double-posting of journal entries from network retries or client-side bugs.
- Schema: `idempotency_keys` (migration 001)
- Scope: `POST /api/v1/payments`, `POST /api/v1/refunds`, `POST /api/v1/pos/sessions/{id}/payments`

---

## 9. Refund & Return Rules

### 9.1 Return State Machine

```
[requested] ──approve──► [approved] ──receive──► [received] ──inspect──► [inspected]
     │                       │                                    │
     └──reject──► [rejected]  └──cancel──► [cancelled]           ├──restock──► [restocked]
                                                                  └──dispose──► [disposed]
```

### 9.2 Refund State Machine

```
[requested] ──approve──► [approved] ──process──► [processed]
     │
     └──reject──► [rejected]
```

**BR-RFD-001**: Credit Note for Paid Invoice
- Preconditions: Original invoice has status `paid` or `partially_paid`
- Logic: To reverse a paid invoice (fully or partially), a credit note MUST be issued (BR-INV-004). Direct cancellation of paid invoices is forbidden. Credit note amount ≤ original invoice amount.
- Permission: `finance.invoices.create @ scope`

**BR-RFD-002**: Return Request
- Logic: A return request MUST reference the original invoice and specify the line items and quantities being returned. Return qty ≤ originally invoiced qty per line. Reason code is required.
- Permission: `sales.orders.update @ scope` (or dedicated return permission if added)
- Audit: `return_requested` with `invoice_id`, `lines[]`, `reason`

**BR-RFD-003**: Return Approval
- Logic: Return requests MUST be approved before goods are accepted back. Approval evaluates return policy, product condition, and financial impact.
- Permission: Approver must hold `shared.approvals.manage @ scope`
- Audit: `return_approved` / `return_rejected`

**BR-RFD-004**: Return Inspection & Restocking
- Logic: After goods are physically received, inspection determines disposition:
  - `restocked`: Item is in sellable condition → create positive `inventory_movement` with type `return_restock`
  - `disposed`: Item is damaged/unsellable → create `inventory_movement` with type `return_dispose`, write-off accounting entry
- Permission: `inventory.levels.adjust @ scope`
- Schema: `inventory_movements`

**BR-RFD-005**: Refund Generation
- Logic: After credit note is issued, a refund payment MUST be created if the customer does not want credit. Refund payment MUST: (1) debit accounts receivable / credit cash, (2) reference the credit note, (3) require approval if amount exceeds workspace-configured threshold.
- Permission: `finance.payments.create @ scope`
- Audit: `refund_processed` with `credit_note_id`, `refund_amount`, `method`

**BR-RFD-006**: Refund Approval Threshold
- Logic: Refund amounts ≤ workspace threshold (default: 1000 base currency units): single approval. Refund amounts > threshold: requires second-level approval by user holding `shared.approvals.manage @ ws`.
- Audit: `refund_approval` with `amount`, `approver_id`, `level`

**BR-RFD-007**: Supplier Return
- Logic: Returns to supplier MUST: (1) reference the original purchase order, (2) create negative `inventory_movement` with type `supplier_return`, (3) generate a debit note to the supplier, (4) adjust supplier balance.
- Permission: `purchasing.orders.update @ scope`
- Schema: `inventory_movements`, `contacts.balance`

**BR-RFD-008**: No Self-Approval of Refunds
- Logic: The user who initiates the refund request MUST NOT be the same user who approves it. This enforces maker-checker per RBAC SoD conflict pair: `finance.invoices.create` vs `finance.payments.create`.

---

## 10. Purchasing Lifecycle Rules

### 10.1 Purchase Order State Machine

```
[draft] ──submit──► [submitted] ──approve──► [approved] ──receive──► [partially_received]
   │                    │                        │                          │
   └──cancel──►[cancelled] └──reject──►[rejected] └──cancel──►[cancelled]  receive──► [received]
                                                                                        │
                                                                              invoice──► [invoiced] ──close──► [closed]
```

| Transition | Guard | Permission | Side-effects |
|-----------|-------|------------|-------------|
| `→ draft` | Valid supplier contact | `purchasing.orders.create @ scope` | None |
| `draft → submitted` | ≥1 line item, quantities > 0 | `purchasing.orders.update @ scope` | Approval request created |
| `submitted → approved` | Approval received per threshold | `purchasing.orders.approve @ scope` | Notification to creator |
| `submitted → rejected` | Approver rejects | `purchasing.orders.approve @ scope` | Notification to creator |
| `approved → partially_received` | GRN created for subset of lines | `purchasing.orders.update @ scope` | Stock increased per GRN lines |
| `partially_received → received` | All lines fully received | System auto-transition | — |
| `received → invoiced` | Supplier invoice matched | `finance.invoices.create @ scope` | Journal entry posted |
| `invoiced → closed` | Supplier invoice fully paid | System auto-transition | — |
| Any pre-receipt → cancelled | No GRN exists | `purchasing.orders.cancel @ scope` | — |

**BR-PUR-001**: PO Content
- Logic: A PO MUST contain at least one line item, each referencing a valid product, quantity > 0, and agreed unit cost. Supplier contact MUST be active.
- Schema: `purchase_orders`, `purchase_order_items`, `contacts`

**BR-PUR-002**: PO Approval Thresholds
- Logic: PO approval follows amount-based tiers aligned with RBAC §12 approval_rules:
  - Amount ≤ 5000 (workspace base currency): single approval by user holding `purchasing.orders.approve @ scope`
  - Amount > 5000: two-step approval — step 1: `purchasing.orders.approve @ scope`, step 2: user holding `shared.approvals.manage @ ws`
- Audit: `po_approved` with `po_id`, `amount`, `approver_id`, `approval_level`

**BR-PUR-003**: Goods Received Note (GRN)
- Logic: When goods arrive, a GRN record MUST be created linking to the PO. GRN MUST specify: received quantity per line (≤ ordered quantity), condition, and receiving warehouse. GRN triggers positive `inventory_movement` with type `purchase_receipt`.
- Permission: `inventory.levels.adjust @ scope`
- Schema: `inventory_movements`
- ⚠️ Schema dependency: requires `goods_received_notes` table

**BR-PUR-004**: Over-Receipt Prevention
- Logic: Received quantity per PO line MUST NOT exceed ordered quantity by more than a workspace-configurable tolerance (default: 0%). Over-receipt beyond tolerance MUST be rejected.

**BR-PUR-005**: Supplier Invoice Matching
- Logic: Supplier invoices MUST be matched against PO + GRN (3-way match):
  - PO amount vs supplier invoice amount (tolerance: workspace-configurable, default ±2%)
  - GRN quantity vs supplier invoice quantity (must match exactly)
  - Mismatches MUST flag for manual review and approval
- Permission: `finance.invoices.create @ scope` (for recording supplier invoice)

**BR-PUR-006**: PO Cancellation
- Logic: A PO may be cancelled ONLY IF no GRN has been recorded. Partially received POs MUST NOT be cancelled — remaining unreceived lines may be individually cancelled.
- Permission: `purchasing.orders.cancel @ scope`
- Audit: `po_cancelled` with `po_id`, `reason`, `cancelled_lines[]`

**BR-PUR-007**: Supplier Payment Dependency
- Logic: Payment to supplier MUST be against a matched supplier invoice, NEVER directly against a PO. This ensures 3-way matching is complete before cash outflow.
- SoD: User creating PO MUST NOT be the same user approving supplier payment (RBAC SoD: `purchasing.orders.create` vs `finance.payments.create`)

**BR-PUR-008**: Price Snapshot on PO
- Logic: Unit costs MUST be locked on PO line items at time of submission. Subsequent supplier price changes MUST NOT affect existing POs.

**BR-PUR-009**: Multi-Currency PO
- Logic: PO currency may differ from workspace base currency. Exchange rate MUST be recorded. Cost variance on final invoice (exchange rate difference) MUST be posted to a gain/loss account.

**BR-PUR-010**: PO Export
- Permission: `purchasing.orders.view @ scope`
- Logic: Export generates PDF or CSV with PO number, supplier, lines, amounts, status, receipt status.

---

## 11. Financial Integrity Rules

**BR-FIN-001**: Journal Entry Balance Invariant
- Logic: Every journal entry MUST satisfy `total_debits == total_credits`. The system MUST reject any journal entry where this invariant is violated. No partial or unbalanced entries are permitted.
- Schema: `journal_entries`, `journal_lines`

**BR-FIN-002**: Journal Entry Immutability
- Logic: Once a journal entry status is `posted`, its lines (accounts, amounts) MUST NOT be modified. Corrections MUST be made by posting a reversal entry (BR-FIN-006) followed by a corrected new entry.

**BR-FIN-003**: Journal Entry Approval
- Logic: Journal entries created manually MUST be approved before posting. Auto-generated journal entries (from invoice, payment, payroll) are auto-posted.
- Permission to create: `finance.journal_entries.create @ scope`
- Permission to approve: `finance.journal_entries.approve @ scope`
- SoD: Creator MUST NOT be approver (RBAC SoD: `finance.journal_entries.create` vs `finance.accounts.create`)
- Audit: `journal_posted` with `journal_id`, `total_amount`, `approver_id`

**BR-FIN-004**: Fiscal Period Management
- Logic: Financial transactions MUST be posted to an open fiscal period. Fiscal periods have statuses: `open`, `closed`, `locked`. `closed` periods may be reopened by authorized user. `locked` periods MUST NOT be reopened.
- Transitions: `open → closed` (end-of-period), `closed → open` (reopen), `closed → locked` (permanent)
- Permission to close: `admin.sequences.configure @ ws`
- Permission to lock: `admin.workspace.configure @ ws`
- Audit: `period_closed`, `period_locked`, `period_reopened`
- ⚠️ Schema dependency: requires `fiscal_periods` table with `status`, `start_date`, `end_date`

**BR-FIN-005**: Retroactive Posting Prevention
- Logic: Posting a journal entry to a `closed` or `locked` fiscal period MUST be rejected. If period is `closed` and user has reopen authority, they must reopen first.

**BR-FIN-006**: Reversal Entry
- Logic: A reversal creates a new journal entry with all debit/credit lines swapped, linked to the original via `reversal_of` reference. The original entry remains unchanged (immutability). Both entries retain their posted status.
- Schema: `journal_entries.reversal_of`

**BR-FIN-007**: Rounding Rules
- Logic: All monetary calculations MUST round to the workspace currency's decimal precision (default: 2 decimal places). Rounding differences MUST be posted to a configured rounding gain/loss account. Rounding is applied per line item, then verified at document total level.

**BR-FIN-008**: Write-Off / Bad Debt
- Logic: Unpaid invoices past a workspace-configurable aging threshold may be written off. Write-off MUST: (1) create journal entry debiting bad-debt expense and crediting accounts receivable, (2) set invoice status to `written_off`, (3) require approval.
- Permission: `finance.transactions.create @ scope`
- Approval: Amount ≤ 5000: single approval. Amount > 5000: two-step.
- Audit: `invoice_written_off` with `invoice_id`, `amount`, `approver_id`

**BR-FIN-009**: Account Types
- Logic: Chart of accounts MUST enforce account types: `asset`, `liability`, `equity`, `revenue`, `expense`. Journal lines MUST reference valid accounts. Account deletion is forbidden if the account has any posted journal lines.
- Schema: `accounts.account_type`

**BR-FIN-010**: POS Cash Session Controls
- Logic: A POS session MUST be opened before processing POS transactions. At session close: expected cash = opening balance + cash sales − cash refunds. Actual cash MUST be counted and recorded. Variance (actual − expected) MUST be logged. Variance above workspace threshold triggers notification.
- Permission to open: `sales.pos_sessions.open @ scope`
- Permission to close: `sales.pos_sessions.close @ scope`
- Schema: `pos_sessions`
- Audit: `pos_session_closed` with `session_id`, `expected`, `actual`, `variance`

**BR-FIN-011**: Expense Recording
- Logic: Expenses MUST create journal entries debiting the expense account and crediting cash/bank/payable. Recurring expenses MUST auto-generate entries per schedule.
- Schema: `expenses`, `recurring_expenses`

**BR-FIN-012**: Financial Report Period Binding
- Logic: Financial reports (P&L, balance sheet, trial balance) MUST be generated for a specific fiscal period or date range. Reports MUST use journal_lines as source of truth, not cached balances.
- Permission: `finance.reports.view @ scope`

**BR-FIN-013**: Exchange Rate Lookup Fallback
- Logic: When a financial operation requires a currency conversion (e.g., multi-currency invoice per BR-INV-006), the system MUST look up the exchange rate using the following priority:
  1. Exact-date rate: `exchange_rates` row matching `(workspace_id, base_currency, target_currency, effective_date = operation_date)`
  2. Most-recent prior rate: closest `effective_date < operation_date` for the same currency pair
  3. If NO rate exists for the currency pair at all, the operation MUST be blocked with error: "Exchange rate not configured for {base} → {target}. Please add an exchange rate before proceeding."
- Schema: `exchange_rates` (migration 010)
- Audit: `exchange_rate_fallback_used` with `expected_date`, `actual_rate_date`, `currency_pair` — logged whenever fallback to a prior date is used
- Exceptions: Transactions in the workspace's `default_currency` do not require exchange rate lookup.

---

## 12. Inventory & Fulfillment Rules

### 12.1 Shipment State Machine

```
[pending] ──pick──► [picking] ──pack──► [packed] ──ship──► [shipped] ──deliver──► [delivered]
    │                                                          │
    └──cancel──► [cancelled]                                   └──(terminal)
```

### 12.2 Stock Transfer State Machine

```
[draft] ──submit──► [pending_approval] ──approve──► [approved] ──dispatch──► [in_transit] ──receive──► [received]
   │                      │                              │
   └──cancel──►[cancelled] └──reject──►[rejected]       └──cancel──►[cancelled]
```

**BR-STK-001**: Stock Reservation
- Logic: When an order transitions to `confirmed` (BR-ORD-006), available stock for each line item is reduced by the reserved quantity. Reserved stock is held until fulfillment or cancellation. Reservation does NOT create an `inventory_movement` — it adjusts `available_quantity` only.
- Schema: `inventory_levels.available_quantity`, `inventory_levels.reserved_quantity`

**BR-STK-002**: Stock Reservation Release
- Logic: When an order is cancelled or a line item is removed from a confirmed order, the reservation MUST be released: `available_quantity` increases, `reserved_quantity` decreases.

**BR-STK-003**: Stock Deduction Timing
- Logic: Stock is deducted from physical quantity ONLY when a shipment transitions to `shipped`. Deduction MUST create an `inventory_movement` with type `sale_shipment`, referencing the shipment and order.
- Schema: `inventory_movements`

**BR-STK-004**: Negative Stock Enforcement
- Logic: Default behavior: the system MUST reject any operation that would cause `quantity` in `inventory_levels` to fall below zero. This includes: sales shipment, adjustment, transfer dispatch.
- Exceptions: Workspace-configurable override allows negative stock. Override MUST: (1) be enabled via workspace settings, (2) be limited to users holding `inventory.levels.adjust @ scope`, (3) generate `negative_stock_override` audit event.
- Audit: `negative_stock_override` with `product_id`, `warehouse_id`, `resulting_quantity`

**BR-STK-005**: Inventory Movement Mandate
- Logic: All stock quantity changes MUST create an `inventory_movement` record. Movement types: `purchase_receipt`, `sale_shipment`, `return_restock`, `return_dispose`, `supplier_return`, `adjustment_increase`, `adjustment_decrease`, `transfer_out`, `transfer_in`, `production_consume`, `production_output`, `opening_balance`.
- Schema: `inventory_movements.movement_type`

**BR-STK-006**: Inventory Adjustment
- Logic: Manual adjustments MUST specify: product, warehouse, quantity change (+ or −), reason code (workspace-configurable list), and reference notes. Adjustments above workspace-configured threshold (qty or value) MUST require approval.
- Permission: `inventory.levels.adjust @ scope`
- Approval: Requires user holding `shared.approvals.manage @ scope` for above-threshold adjustments
- Audit: `stock_adjusted` with `product_id`, `warehouse_id`, `qty_change`, `reason`

**BR-STK-007**: Batch / Lot Tracking
- Logic: Products with batch tracking enabled MUST record batch/lot number on every movement. Stock deduction follows workspace-configured strategy: FIFO (first in, first out) or FEFO (first expiry, first out). Expired batches MUST be flagged and quarantined from available stock.
- Schema: `inventory_batches`

**BR-STK-008**: Stock Transfer Rules
- Logic: Transfer follows the FSM above. Source deduction creates `transfer_out` movement on `approved`. Destination increase creates `transfer_in` movement on `received`. The operation MUST be atomic at the business level (compensation on failure). Source and destination MUST be different warehouses within the same workspace.
- Permission: `inventory.transfers.create @ scope`
- Approval: `inventory.transfers.approve @ scope`

**BR-STK-009**: Shipment Rules
- Logic: A shipment MUST reference a confirmed order. Partial shipment is allowed (creates back-order for remaining lines). Each shipment line specifies product, quantity, and source warehouse. Stock is deducted per shipment line on `shipped` (BR-STK-003).
- Permission: `shared.shipments.create @ scope`

**BR-STK-010**: Cancellation Edge Cases
- Logic: An order MUST NOT be fully cancelled after any shipment is `shipped` or `delivered`. For partially fulfilled orders, only unfulfilled lines may be cancelled. Cancellation of unfulfilled lines MUST release reservations (BR-STK-002).

**BR-STK-011**: Warehouse Scope Enforcement
- Logic: Users with `wh` scope MUST only see stock data for their assigned warehouse(s). Users with `ws` scope see all warehouses. Warehouse assignment is stored on user profile.
- Schema: `users.warehouse_ids` or `user_warehouse_assignments`

**BR-STK-012**: Low-Stock / Reorder Point
- Logic: Each product+warehouse may have a configurable `reorder_point`. When `available_quantity` drops to or below `reorder_point`, a `low_stock_alert` notification is generated. Optional: auto-generate draft PO suggestion.
- Schema: `inventory_levels.reorder_point`

**BR-STK-013**: Damage / Shrinkage
- Logic: Damage and shrinkage MUST be recorded as negative adjustments with specific reason codes (`damage`, `shrinkage`, `expired`). These create `adjustment_decrease` movements and corresponding write-off journal entries.

**BR-STK-014**: Opening Balance
- Logic: When a workspace is initialized or a new product+warehouse is added, opening stock balance MUST be recorded as an `inventory_movement` with type `opening_balance`. This sets the baseline for all subsequent tracking.

### 12.3 Production Order State Machine

```
[draft] ──confirm──► [confirmed] ──release──► [released] ──start──► [in_progress]
   │                      │                       │                     │
   └──cancel──►[cancelled] └──cancel──►[cancelled] └──cancel──►[cancelled] └──complete──► [completed] ──close──► [closed]
                                                                         └──cancel──►[cancelled]
```

| Transition | Guard | Permission | Side-effects |
|-----------|-------|------------|-------------|
| `→ draft` | Valid BOM referenced | `manufacturing.production.create @ scope` | None |
| `draft → confirmed` | All BOM materials available or reservable | `manufacturing.production.update @ scope` | Raw material reservation |
| `confirmed → released` | Approval received (BR-APR-001) | `manufacturing.production.update @ scope` + approval | Work center scheduled |
| `released → in_progress` | Work center available, materials issued | `manufacturing.production.update @ scope` | Raw material consumed (inventory_movement `production_consume`) |
| `in_progress → completed` | Output quantity recorded | `manufacturing.production.update @ scope` | Finished goods received (inventory_movement `production_output`) |
| `completed → closed` | Variance reviewed, no pending adjustments | `manufacturing.production.update @ scope` | Cost variance posted to journal |
| Any pre-start → cancelled | No materials consumed | `manufacturing.production.cancel @ scope` | Reservations released |

**BR-MFG-001**: Production Order Creation
- Preconditions: A valid BOM (Bill of Materials) exists for the target product
- Logic: A production order MUST reference: target product, BOM version, planned quantity, planned start date, target completion date, and work center. Planned raw material requirements are auto-calculated from BOM × planned quantity.
- Permission: `manufacturing.production.create @ scope`
- Schema: `production_orders`, `bom`, `bom_lines`

**BR-MFG-002**: BOM Validation
- Logic: Before confirming a production order, the system MUST validate: (1) all BOM component products exist and are active, (2) component quantities are > 0, (3) total raw material is available or reservable in the source warehouse. If material is insufficient, the order remains in `draft` with a shortage report.
- Permission: `manufacturing.bom.view @ scope`
- Schema: `bom`, `bom_lines`, `inventory_levels`

**BR-MFG-003**: Material Consumption
- Logic: When production transitions to `in_progress`, raw materials listed in the BOM MUST be issued from inventory. Each material line creates an `inventory_movement` with type `production_consume`, referencing the production order. Actual consumed quantities may differ from planned (tracked as variance).
- Permission: `inventory.levels.adjust @ scope`
- Side-effects: `inventory_movement` per BOM line, reservation released
- Schema: `inventory_movements`

**BR-MFG-004**: Finished Goods Output
- Logic: On completion, the produced output quantity MUST be recorded. Output creates an `inventory_movement` with type `production_output` into the target warehouse. Output quantity may differ from planned quantity (over/under production tracked as variance).
- Permission: `manufacturing.production.update @ scope`
- Side-effects: Finished goods stock increased
- Schema: `inventory_movements`, `inventory_levels`

**BR-MFG-005**: Scrap / Waste Recording
- Logic: Scrap and waste during production MUST be recorded with: quantity, reason code (`defective`, `spoilage`, `material_loss`), and production order reference. Scrap creates an `inventory_movement` with type `production_scrap`. Scrap cost is posted to a configured manufacturing overhead/loss account.
- Permission: `manufacturing.production.update @ scope`
- Side-effects: `inventory_movement`, journal entry for scrap cost
- Audit: `production_scrap_recorded` with `production_order_id`, `product_id`, `scrap_qty`, `reason`

**BR-MFG-006**: Production Cost Variance
- Logic: On production order closure (`completed → closed`), the system MUST calculate variance: actual material cost vs standard BOM cost. Variance MUST be classified as: `favorable` (actual < planned) or `unfavorable` (actual > planned). Variance MUST be posted to a dedicated manufacturing variance account via journal entry.
- Permission: `manufacturing.production.update @ scope`
- Side-effects: Journal entry for cost variance
- Audit: `production_variance_posted` with `production_order_id`, `planned_cost`, `actual_cost`, `variance`

**BR-MFG-007**: Production Cancellation
- Logic: A production order may be cancelled ONLY IF no materials have been consumed (`in_progress` has not been reached). If materials are already consumed, the order MUST be completed (even with zero output) and scrap/variance recorded. Cancellation releases all material reservations.
- Permission: `manufacturing.production.cancel @ scope`
- Audit: `production_cancelled` with `production_order_id`, `reason`

---

## 13. HR & Workforce Rules

### 13.1 Attendance State Machine

```
[clocked_in] ──clock_out──► [clocked_out] ──adjust──► [manually_adjusted] ──approve──► [approved]
                                  │
                                  └──approve──► [approved]
```

### 13.2 Leave Request State Machine

```
[draft] ──submit──► [submitted] ──approve──► [approved] ──(taken)──► [completed]
   │                     │                       │
   └──cancel──►[cancelled] └──reject──►[rejected] └──cancel──►[cancelled]
```

### 13.3 Payroll Run State Machine

```
[draft] ──calculate──► [calculated] ──approve──► [approved] ──disburse──► [disbursed] ──lock──► [locked]
                            │                       │
                            └──recalculate──►[draft] └──reject──►[draft]
```

**BR-ATT-001**: Clock-In / Clock-Out
- Logic: Attendance MUST record: user_id, clock_in timestamp, clock_out timestamp, source (manual, biometric, GPS, web). Clock-out MUST be after clock-in. A user MUST NOT have overlapping attendance records for the same date.
- Permission: `hr.attendance.create @ own`
- Schema: `attendance_records`

**BR-ATT-002**: Shift Matching
- Logic: If shift schedules are configured, attendance MUST be linked to the user's assigned shift. Early arrival (before shift start) and late departure (after shift end) are recorded but only shift-window hours count as regular hours. Late arrival tolerance: workspace-configurable (default: 15 minutes).
- Schema: `shifts`, `attendance_records.shift_id`

**BR-ATT-003**: Overtime
- Logic: Hours exceeding the shift duration or daily maximum (workspace-configurable, default: 8 hours) are classified as overtime. Overtime rate multiplier is workspace-configurable (default: 1.5x). Overtime above a workspace-configurable monthly cap requires approval.
- Permission to approve overtime: `hr.attendance.approve @ dept|team`
- Schema: `attendance_records.overtime_hours`

**BR-ATT-004**: Absence Detection
- Logic: A background job runs daily: if a user has no attendance record for a date they were scheduled to work (per shift) and no approved leave, an absence is auto-created. Manager is notified. Absence directly affects payroll (unpaid unless workspace policy overrides).
- Schema: `attendance_records.status = 'absent'`

**BR-ATT-005**: Manual Adjustment
- Logic: Manual corrections to attendance records (changing clock-in/out times, adding missed entries) MUST be flagged as `manually_adjusted` and require manager approval before payroll considers them.
- Permission to adjust: `hr.attendance.create @ own` (for self-correction request)
- Permission to approve: `hr.attendance.approve @ team|dept`
- Audit: `attendance_adjusted` with `record_id`, `old_values`, `new_values`, `reason`

**BR-LVE-001**: Leave Types
- Logic: Leave types are workspace-configurable (annual, sick, unpaid, maternity, paternity, compassionate, etc.). Each type MUST define: accrual policy (monthly/yearly/none), maximum balance, carry-forward limit, carry-forward expiry, whether approval required, whether documentation required.
- Schema: `leave_types`
- ⚠️ Schema dependency: requires `leave_types` table

**BR-LVE-002**: Leave Balance
- Logic: Leave balances are tracked per user per leave type. Accrual runs as scheduled background job (monthly or yearly). Balance = accrued − taken − expired carry-forward. A leave request MUST be rejected if it would cause the balance to go below zero, UNLESS the leave type allows negative balance (configurable).
- Schema: `leave_balances`
- ⚠️ Schema dependency: requires `leave_balances` table

**BR-LVE-003**: Leave Request Submission
- Logic: A leave request MUST specify: leave type, start date, end date, duration (days/half-days), reason. System MUST check for conflicting requests (overlapping dates for same user) and reject duplicates.
- Permission: `hr.leaves.create @ own`
- Schema: `leave_requests`
- ⚠️ Schema dependency: requires `leave_requests` table

**BR-LVE-004**: Leave Approval
- Logic: Leave approval requires user holding `hr.leaves.approve @ team|dept`. Escalation to `hr.leaves.approve @ ws` after 48 hours. Approver MUST NOT be the requestor (maker-checker). On approval: leave balance is decremented.
- Audit: `leave_approved` / `leave_rejected` with `request_id`, `approver_id`, `reason`

**BR-LVE-005**: Leave Cancellation
- Logic: An approved leave may be cancelled ONLY IF the leave start date has not passed. If leave has already started, only the remaining future days may be cancelled. Cancelled days are credited back to balance.

**BR-PRL-001**: Payroll Prerequisites
- Logic: Before a payroll run can transition to `calculated`, ALL of the following MUST be true for the payroll period: (1) attendance period is finalized (no pending adjustments), (2) leave requests for the period are resolved (approved or rejected), (3) all deductions and allowances are configured, (4) prior payroll run (if any) is in `locked` status.
- Schema: `payrolls`

**BR-PRL-002**: Payroll Calculation
- Logic: Payroll calculation MUST compute per employee: base salary + allowances + overtime pay − deductions (tax, insurance, loan repayments, absence deductions, etc.) = net pay. Calculation formula is workspace-configurable. Each component MUST be stored as a payroll line item.
- Schema: `payrolls`, `payroll_lines`
- ⚠️ Schema dependency: requires `payroll_lines` table

**BR-PRL-003**: Payroll Approval
- Logic: Calculated payroll MUST be approved before disbursement. Approval requires user holding `hr.payroll.approve @ ws`. Approver MUST NOT be the same user who ran the calculation (RBAC SoD: `hr.payroll.process` vs `hr.employees.create`).
- Audit: `payroll_approved` with `payroll_id`, `period`, `total_amount`, `employee_count`, `approver_id`

**BR-PRL-004**: Payroll Disbursement & Lock
- Logic: On disbursement: (1) journal entry is posted (debit salary expense accounts, credit cash/bank), (2) payslips are generated per employee, (3) payroll status transitions to `disbursed`. After disbursement, workspace admin may lock the payroll period (→ `locked`), preventing any modification.
- Permission to disburse: `hr.payroll.process @ ws`
- Permission to lock: `admin.workspace.configure @ ws`

**BR-HR-001**: Onboarding
- Logic: When membership transitions from `pending → active`, the system MUST: (1) assign default role template (workspace-configurable, default: `employee`), (2) create employee profile record, (3) assign to department/branch, (4) initialize leave balances for applicable leave types.

**BR-HR-002**: Offboarding
- Logic: When membership transitions to `removed`: (1) all active sessions are invalidated (BR-MBR-003), (2) final payroll is calculated for remaining days, (3) leave balance is settled (unused entitled leave may be paid out per workspace policy), (4) user loses all workspace data access, (5) employee profile is soft-deleted.
- Audit: `employee_offboarded` with `user_id`, `final_settlement_amount`, `effective_date`

### 13.4 Employee Self-Service Boundaries

The following rules define what employees may do for themselves using `@ own` scope permissions.

**BR-HR-003**: Self-Service — Viewable Data
- Logic: An employee (`hr.employees.view @ own`) MAY view their own: profile (name, contact info, department, branch, role), attendance records, leave balances and requests, payslips, assigned shifts, task assignments, and notifications. Employees MUST NOT view other employees' payroll, leave balances, or attendance unless they hold `@ team`, `@ dept`, or `@ ws` scope.

**BR-HR-004**: Self-Service — Editable Fields
- Logic: An employee (`hr.employees.update @ own`, `admin.users.update @ own`) MAY update the following personal fields: phone number, emergency contact, profile photo, preferred language, notification preferences. The following fields are HR/manager-controlled and MUST NOT be self-editable: name (legal), salary, department assignment, branch assignment, role, bank account details (requires approval), job title. Changes to HR-controlled fields require a change request approved by user holding `hr.employees.update @ dept|ws`.
- Audit: `profile_self_updated` with `user_id`, `fields_changed[]`

**BR-HR-005**: Self-Service — Creatable Actions
- Logic: An employee MAY create the following on their own behalf:

| Action | Permission | Post-creation behavior |
|--------|-----------|------------------------|
| Attendance clock-in/out | `hr.attendance.create @ own` | Immediate; linked to shift |
| Leave request | `hr.leaves.create @ own` | Requires approval (BR-LVE-004) |
| Attendance correction request | `hr.attendance.create @ own` | Flagged as `manually_adjusted`; requires approval (BR-ATT-005) |
| Expense claim (if enabled) | `finance.transactions.create @ own` | Requires approval |
| Task updates | `projects.tasks.update @ own` | Immediate for assigned tasks |
| AI chat | `ai.chat.use @ ws` | Immediate |

- Restrictions: Once submitted, leave requests and attendance corrections MUST NOT be modified by the employee — only cancelled (if still pending) or amended via a new request. Payroll objections must be raised through a formal process (notification to user holding `hr.payroll.view @ ws`).
- Audit: All self-service creations logged with `actor_id = user_id`

---

## 14. Approval & Governance Rules

### 14.1 Approval Request State Machine

```
[pending] ──approve──► [approved] ──► (triggers business action)
    │          │
    │          └──(step2)──► [pending_step2] ──approve──► [approved]
    │
    ├──reject──► [rejected]
    └──(timeout)──► [escalated] ──approve──► [approved]
                        │
                        └──reject──► [rejected]
```

**BR-APR-001**: Approval Trigger Table
- Logic: The following actions MUST create approval requests before execution:

| Trigger | Condition | Step 1 Permission | Step 2 Permission | Escalation |
|---------|-----------|-------------------|-------------------|------------|
| Leave request | Any | `hr.leaves.approve @ team\|dept` | `hr.leaves.approve @ ws` | 48h |
| Stock transfer | Any | `inventory.transfers.approve @ scope` | `shared.approvals.manage @ ws` | 24h |
| Purchase order (≤5000) | Amount ≤ 5000 | `purchasing.orders.approve @ scope` | — | — |
| Purchase order (>5000) | Amount > 5000 | `purchasing.orders.approve @ scope` | `shared.approvals.manage @ ws` | 48h |
| Invoice cancellation | Any | `finance.invoices.cancel @ scope` | `shared.approvals.manage @ ws` | 24h |
| Payment (≤10000) | Amount ≤ 10000 | `finance.payments.create @ scope` | — | — |
| Payment (>10000) | Amount > 10000 | `finance.payments.create @ scope` | `shared.approvals.manage @ ws` | 24h |
| Journal entry (manual) | Any | `finance.journal_entries.approve @ scope` | — | — |
| Employee join | Any | `admin.users.approve @ scope` | `shared.approvals.manage @ ws` | 72h |
| AI system change | Any | `admin.workspace.configure @ ws` | — | — |
| Production order | Any | `manufacturing.production.create @ scope` | `shared.approvals.manage @ ws` | 48h |
| Refund (>threshold) | Amount > workspace threshold | `shared.approvals.manage @ scope` | `shared.approvals.manage @ ws` | 24h |
| Inventory adjustment (>threshold) | Qty/value > threshold | `shared.approvals.manage @ scope` | — | — |
| Role creation/modification | Any | `admin.roles.create @ ws` | — | — |

**BR-APR-002**: Approval Record
- Logic: Every approval decision MUST record: `approver_id`, `decision` (approve/reject), `timestamp`, `reason` (mandatory on reject, optional on approve), `step_number`, `ip_address`.
- Schema: `approval_requests`

**BR-APR-003**: Escalation
- Logic: If an approval request remains `pending` beyond the escalation window (defined per trigger type), it MUST auto-escalate. Escalation notifies the next-level permission holder. If no next-level exists, it notifies workspace admin. Escalated requests retain original context.
- Audit: `approval_escalated` with `request_id`, `original_approver`, `escalated_to`, `hours_elapsed`

**BR-APR-004**: Maker-Checker Enforcement
- Logic: For all finance-sensitive approvals, the user who created the entity MUST NOT be the same user who approves it. System MUST validate `creator_id != approver_id` at approval time.

**BR-APR-005**: SoD at Approval Time
- Logic: At approval time, system MUST verify that the approver does not hold a conflicting permission per RBAC SoD rules. If a CRITICAL SoD conflict exists, approval MUST be blocked. If a HIGH conflict exists, a warning is logged and a higher-authority override is required.

**BR-APR-006**: Break-Glass / Emergency Override
- Logic: In emergency situations, a user holding `admin.workspace.configure @ ws` may force-approve a pending request. Override MUST: (1) require written reason (minimum 20 characters), (2) generate `emergency_override` audit event with full context, (3) generate notification to all workspace owners, (4) be included in the workspace's monthly override report.
- Audit: `emergency_override` with `request_id`, `overrider_id`, `reason`, `original_action`

**BR-APR-007**: Approval Expiry
- Logic: Approval requests that remain unresolved for 30 days (workspace-configurable) are auto-expired with status `expired`. The original action is NOT executed. Creator is notified.

**BR-APR-008**: Batch Approval
- Logic: A user with approval authority may approve multiple pending requests in a single action, provided each request passes individual validation (maker-checker, SoD, scope). Each approval is logged individually.

**BR-APR-009**: Delegation During Absence
- Logic: If an approver is on leave, their approval permissions may be delegated per BR-ROL-007. The delegate receives the approval notifications and can approve within the delegated scope. Both delegator and delegate are recorded in the approval log.

**BR-APR-010**: Approval Audit Trail
- Logic: The complete approval chain (all steps, decisions, timestamps, delegations, escalations, overrides) MUST be queryable per entity. This trail MUST be immutable and non-deletable.

---

## 15. AI Governance Rules

**BR-AI-001**: AI Cannot Modify System Directly
- Logic: AI MUST NOT execute any create, update, or delete operation on system data directly. AI MUST: (1) propose a structured change request, (2) submit for human approval, (3) wait for approval before execution.
- Audit: `ai_change_proposed` with `proposal_type`, `payload`, `ai_session_id`

**BR-AI-002**: Structured Output Only
- Logic: AI outputs that affect system configuration or data MUST be: (1) JSON structured, (2) validated against a predefined schema, (3) logged before execution. Free-text AI responses are allowed for chat/advisory interactions only.

**BR-AI-003**: AI Cannot Generate or Execute SQL
- Logic: AI MUST NEVER generate raw SQL for execution. All data operations MUST go through backend API services, respecting RLS, permissions, and business rules.

**BR-AI-004**: AI Change Approval
- Logic: AI-proposed changes MUST be approved by user holding `admin.workspace.configure @ ws` before execution. Approval creates an audit trail linking AI proposal → human decision → system action.
- Schema: `ai_change_requests`

**BR-AI-005**: AI Token Quotas
- Logic: AI usage MUST be metered per workspace. Quota limits are defined by subscription plan. When quota is exhausted: (1) AI chat returns informative message, (2) AI automation stops proposing changes, (3) workspace admin is notified. Quota resets per billing cycle.
- Schema: `workspaces.ai_tokens_used`, `workspaces.ai_tokens_limit`

**BR-AI-006**: Unsupported Feature Response
- Logic: When a user requests a feature that is not implemented, AI MUST: (1) respond honestly that the feature is not yet available, (2) log the request as a feature request (BR-AI-008), (3) inform the user that the request has been recorded. AI MUST NOT fake functionality or promise dates.

**BR-AI-007**: AI Conversation Logging
- Logic: All AI interactions MUST be logged with: `user_id`, `workspace_id`, `session_id`, `prompt`, `response`, `model_used`, `tokens_consumed`, `timestamp`. Logs are retained per workspace data retention policy.
- Schema: `ai_request_logs`

**BR-AI-008**: Feature Request Aggregation
- Logic: Feature requests (from AI or direct user submission) MUST be: (1) normalized by key/topic, (2) aggregated by workspace count and user count, (3) available to platform team for review and prioritization. Platform team can update status: `logged`, `planned`, `in_progress`, `released`, `rejected`.
- Schema: `feature_requests`

---

## 16. Notification & Communication Rules

**BR-NTF-001**: Notification Persistence
- Logic: All notifications MUST be stored persistently in the database. Notifications are NOT ephemeral — they survive session restarts and are permanently queryable.
- Schema: `notifications`

**BR-NTF-002**: Notification Categories
- Logic: Notifications MUST be categorized into: `approval_request`, `approval_decision`, `ai_suggestion`, `erp_alert` (low stock, overdue invoice, absence), `feature_release`, `platform_broadcast`, `system_warning`. Category MUST be stored on each notification record.

**BR-NTF-003**: Notification Read State
- Logic: Each notification MUST track a per-user read state (`read` / `unread`). Marking as read MUST be explicit (user action). Batch mark-as-read is allowed.
- Permission: `shared.notifications.view @ own|ws`

**BR-NTF-004**: Entity Linking
- Logic: Notifications MUST link to the originating entity via `entity_type` and `entity_id`. Clicking a notification MUST navigate to the relevant entity. If the user lacks permission to view the entity, the notification is shown but the link is disabled.

**BR-NTF-005**: Platform Broadcasts
- Logic: Platform-level broadcasts are sent by platform administrators to all users or targeted workspaces. Broadcasts MUST be stored in a platform-scoped table. Workspace users see platform broadcasts in their notification feed.
- Permission to send: `platform.broadcasts.send`
- Schema: `platform_broadcasts`

**BR-NTF-006**: Notification Delivery Timing
- Logic: Approval-related notifications MUST be delivered in real-time (within 5 seconds). ERP alerts (low stock, overdue) are generated by background jobs and delivered on next user session or push. Batch notification fanout is handled asynchronously.

---

## 17. Platform Governance & Security Rules

**BR-PLT-001**: Workspace Suspension
- Logic: Platform administrators may suspend a workspace for policy violations, unpaid subscriptions, or abuse. Suspension MUST: (1) set workspace status to `suspended`, (2) block all workspace operations except read-only data export by owner, (3) generate notification to workspace owner, (4) create audit log.
- Permission: `platform.workspaces.suspend`
- Audit: `workspace_suspended` with `workspace_id`, `reason`, `admin_id`

**BR-PLT-002**: AI Usage Limits
- Logic: Platform MUST enforce per-workspace AI quotas based on subscription plan. Quota includes: requests per hour, requests per day, tokens per billing cycle. Exceeding quota returns HTTP 429 with informative message.

**BR-PLT-003**: Platform Impersonation
- Logic: Platform owner may impersonate a workspace user for debugging/support. Impersonation MUST: (1) be time-limited (max 1 hour per session), (2) generate `impersonation_started` and `impersonation_ended` audit events, (3) be visible in the workspace's audit log with the impersonator's platform identity.
- Permission: `platform.workspaces.impersonate`

**BR-PLT-004**: Security — Authentication
- Logic: JWT access tokens MUST have configurable expiry (default: 30 min). Refresh token rotation is mandatory. Tokens MUST include: `user_id`, `workspace_id`, `role_id`, `issued_at`, `expires_at`. Tokens MUST be validated on every request.

**BR-PLT-005**: Security — Rate Limiting
- Logic: Rate limits MUST be enforced at API gateway level. Limits apply per user, per IP, and per endpoint category. Exceeded limits return HTTP 429. Rate limit configuration:

| Endpoint category | Limit |
|-------------------|-------|
| Login | 5/min per IP |
| Registration | 3/hour per IP |
| AI chat | Per plan quota |
| Password reset | 3/hour per email |
| File upload | 10/min per user |
| General API | 100/min per user (configurable) |

**BR-PLT-006**: Security — Error Handling
- Logic: Errors MUST be structured and safe. Error response format: `{ "error_type", "message", "details" }`. Supported error types: `validation_error`, `auth_error`, `permission_error`, `conflict_error`, `not_found`, `rate_limit`, `ai_error`, `internal_error`. Internal stack traces, SQL errors, and infrastructure details MUST NEVER be exposed.

**BR-PLT-007**: File Upload Validation
- Logic: File uploads MUST enforce: (1) allowlist of file types (workspace-configurable, default: jpg, png, pdf, xlsx, csv, docx), (2) maximum file size (workspace-configurable, default: 10 MB), (3) files stored in object storage (not database), (4) file references stored in `attachments` table with entity linkage.
- Schema: `attachments`

**BR-PLT-008**: Data Retention
- Logic: Financial records (invoices, payments, journal entries), audit logs, and payroll records MUST be retained for a minimum of 7 years or per applicable regulatory requirement. Deletion of these records is forbidden. Archival to cold storage is permitted after the retention period if the workspace owner requests.

**BR-PLT-009**: Offline Sync
- Logic: Offline mode supports limited operations: POS drafts, sales drafts, product browsing, customer selection. Offline operations MUST include `operation_id`, `timestamp`, `device_id`. On sync: backend validates idempotency (rejects duplicate `operation_id`), applies conflict resolution (last-write-wins with audit), and confirms sync status to device.
- NOT allowed offline: accounting, AI chat, payroll, approvals, role management.

**BR-PLT-010**: Performance
- Logic: All list endpoints MUST support pagination (default: 50 items, max: 200). Queries MUST use indexed columns. Export operations above 10,000 records MUST be executed as background jobs with result delivery via notification.

**BR-PLT-011**: Background Jobs
- Logic: Background workers handle: AI analytics, cached balance refresh, low-stock detection, overdue invoice detection, absence detection, notification fanout, scheduled recurring expenses, leave accrual, approval escalation timeout checks. All job executions MUST be logged with `actor_type = 'system'`.

**BR-PLT-012**: Compliance Readiness
- Logic: System MUST maintain: (1) traceable financial records with immutable audit trail, (2) immutable ledger behavior (no retroactive modification of posted entries), (3) exportable audit logs in standard format, (4) configurable tax rules per workspace jurisdiction, (5) fiscal period management.

---

## 18. Cross-Module Integrity Rules

**BR-XMD-001**: Sales → Fulfillment → Finance Chain
- Logic: The complete sales chain MUST maintain consistency:
  1. `order(confirmed)` → stock reservation created (BR-STK-001)
  2. `shipment(shipped)` → stock deducted (BR-STK-003)
  3. `invoice(issued)` → journal entry posted (BR-FIN-001)
  4. `payment(completed)` → journal entry posted (BR-PAY-002), invoice status updated
- Failure at any step MUST NOT leave the system in an inconsistent state. If shipment fails, reservation remains. If invoice posting fails, shipment is not rolled back — invoice remains in `draft`.

**BR-XMD-002**: Purchasing → Receiving → Finance Chain
- Logic: The complete procurement chain MUST maintain consistency:
  1. `purchase_order(approved)` → available for receiving
  2. `grn(received)` → stock increased (BR-PUR-003)
  3. `supplier_invoice(matched)` → journal entry posted
  4. `payment(completed)` → supplier balance updated, journal entry posted
- PO MUST NOT be closed until all lines are received, invoiced, and paid.

**BR-XMD-003**: Return → Credit → Refund Chain
- Logic:
  1. `return(approved)` → goods received and inspected
  2. `return(restocked|disposed)` → inventory movement created (BR-RFD-004)
  3. `credit_note(issued)` → reversal journal entry posted (BR-INV-004)
  4. `refund(processed)` → payment out, journal entry posted (BR-RFD-005)
- If goods are not returned (service refund), steps 1-2 are skipped.

**BR-XMD-004**: Attendance → Leave → Payroll Chain
- Logic:
  1. Attendance records finalized for period (BR-ATT-001 through BR-ATT-005)
  2. Leave requests resolved for period (BR-LVE-004)
  3. Payroll calculated from finalized attendance + leave (BR-PRL-001, BR-PRL-002)
  4. Payroll approved and disbursed (BR-PRL-003, BR-PRL-004)
  5. Journal entry posted for salary expense
  6. Payroll period locked
- Payroll MUST NOT be calculated until steps 1-2 are complete for the period.

**BR-XMD-005**: Approval → Action Execution Chain
- Logic:
  1. Business action triggers approval request (BR-APR-001)
  2. Approval request is resolved (approved, rejected, escalated, expired)
  3. On `approved`: business action is executed with the original context
  4. On `rejected` or `expired`: business action is NOT executed, creator is notified
  5. Audit trail records the complete chain
- The business action MUST NOT execute before approval is received, except for actions that do not require approval per BR-APR-001.

**BR-XMD-006**: AI → Governance → Execution Chain
- Logic:
  1. AI proposes a structured change (BR-AI-001)
  2. Change request awaits human approval (BR-AI-004)
  3. On approval: system executes the change via standard API (respecting permissions, business rules, and schema constraints)
  4. Execution result is logged and surfaced to user
- AI changes MUST go through the same business rules as human-initiated actions.

**BR-XMD-007**: Order Cancellation Cascade
- Logic: When an order is cancelled:
  1. Stock reservations released (BR-STK-002)
  2. Unfulfilled shipments cancelled
  3. Draft invoices linked to the order are deleted
  4. Issued invoices are NOT auto-cancelled (require separate cancellation per BR-INV-003)
  5. Payments already received are NOT auto-reversed (handled via refund flow)

**BR-XMD-008**: Product Deletion Cascade
- Logic: A product MUST NOT be hard-deleted if it is referenced by any: invoice line, order line, PO line, inventory movement, or active inventory level. Soft-deletion (`is_active = false`) hides the product from new transactions but preserves historical references.
- Permission: `inventory.products.delete @ scope`
- Schema: `products.is_active`

---

*End of specification. Version 1.1 — 2026-04-09. Added BR-WKS-005, BR-WKS-006, BR-ORD-007, BR-PAY-009, BR-FIN-013 (final hardening pass).*
