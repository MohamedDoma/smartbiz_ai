# SmartBiz AI — Roles & Permissions Matrix

## 1. Purpose

This document defines the **Role-Based Access Control (RBAC)** model for SmartBiz AI.

The system has **two permission layers**:

1. **Platform Roles**  
   Roles that operate at the **platform level** (SmartBiz AI itself).

2. **Workspace Roles**  
   Roles that operate **inside a business workspace (company ERP)**.

This separation allows:
- safe multi-tenant SaaS
- platform-wide monitoring
- controlled ERP operations
- secure AI approvals

---

# 2. Platform Roles (Global Level)

Platform roles are used by the **SmartBiz AI platform team**.

They are **not tied to a workspace**.

## 2.1 platform_owner

This is the **super administrator of the entire platform**.

Capabilities:

- view all workspaces
- monitor platform events
- send broadcast notifications
- create surveys
- review feature requests
- manage feature roadmap
- enable/disable features globally
- inspect AI usage
- inspect token consumption
- review failed sync events
- disable abusive workspaces
- view analytics
- impersonate workspace for support (optional later)

Owner can also:

- approve platform-level changes
- manage platform admins
- manage pricing plans (future)
- manage AI limits

---

## 2.2 platform_admin

Helps operate the platform.

Capabilities:

- view workspaces
- view platform events
- respond to feature requests
- send targeted notifications
- run surveys
- analyze platform usage

Cannot:

- delete platform
- change pricing plans
- remove platform owner

---

## 2.3 platform_support

Customer support role.

Capabilities:

- inspect workspace configuration
- inspect logs
- inspect feature requests
- help debug user issues

Cannot:

- modify workspace data
- access financial details without permission
- change workspace roles

---

## 2.4 platform_operations

Operations and analytics role.

Capabilities:

- analyze system usage
- analyze performance
- monitor AI usage
- monitor error rates
- view platform events

---

# 3. Workspace Roles (Tenant Level)

Workspace roles operate **inside a company ERP**.

Each workspace has its own roles and permissions.

A user may have **different roles in different workspaces**.

---

# 4. Workspace Role Hierarchy

Highest authority to lowest:

1. Owner
2. Co-owner
3. Admin
4. Department Head
5. HR
6. Accountant
7. Sales
8. Warehouse Staff
9. Cashier
10. Employee
11. Viewer

---

# 5. Owner

The **primary owner of a workspace (business)**.

Owner powers:

- transfer ownership
- delete workspace
- approve critical AI changes
- manage subscription
- manage co-owners
- manage admins
- manage all modules
- manage workspace settings
- approve sensitive approvals
- view all reports
- control AI configuration

Owner has **full access to all modules**.

---

# 6. Co-owner

Almost equal to owner but without final ownership privileges.

Co-owner can:

- manage admins
- manage departments
- manage users
- approve AI changes
- manage settings
- manage ERP modules
- approve operational actions

Co-owner cannot:

- delete workspace
- transfer ownership
- control subscription billing

---

# 7. Admin

Administrative manager role.

Capabilities:

- manage users
- manage roles
- manage branches
- manage departments
- approve join requests
- manage inventory
- manage orders
- manage invoices
- manage payments
- manage contacts

Admin cannot:

- delete workspace
- transfer ownership
- change subscription
- override owner decisions

---

# 8. Department Head

Manages a specific department.

Capabilities:

- approve employee join requests for their department
- manage team members
- assign tasks
- view department reports
- approve leave requests (optional)

Cannot:

- access full financial system
- modify global workspace settings

---

# 9. HR

Human resources role.

Capabilities:

- approve employee join requests
- manage employee profiles
- manage shifts
- manage attendance
- manage leave requests
- manage payroll records

Cannot:

- access accounting system
- manage inventory
- change financial records

---

# 10. Accountant

Handles financial operations.

Capabilities:

- view financial reports
- manage accounts
- create journal entries
- record payments
- manage expenses
- manage invoices
- manage taxes

Cannot:

- modify product inventory
- manage employees
- change workspace settings

---

# 11. Sales

Handles customers and orders.

Capabilities:

- manage contacts
- create orders
- create invoices
- view customer history
- view sales reports

Cannot:

- modify accounting rules
- adjust stock directly

---

# 12. Warehouse Staff

Manages stock operations.

Capabilities:

- view products
- update stock levels
- process stock transfers
- manage warehouse inventory
- view inventory logs

Cannot:

- access financial records
- approve transfers unless authorized

---

# 13. Cashier

Point-of-sale operator.

Capabilities:

- create POS sales
- process payments
- print receipts
- view product catalog
- view basic sales history

Cannot:

- modify product pricing
- manage inventory
- access accounting reports

---

# 14. Employee

Basic employee access.

Capabilities:

- view personal schedule
- submit leave requests
- update personal profile
- access assigned tasks

Cannot:

- view financial data
- manage inventory
- manage users

---

# 15. Viewer

Read-only access.

Capabilities:

- view dashboards
- view reports
- view analytics

Cannot:

- modify any data

---

# 16. Permission Keys

Permissions are capability-based.

Examples:

```

- users.view
- users.create
- users.update
- users.delete
- users.approve

- products.view
- products.create
- products.update
- products.delete

- inventory.view
- inventory.adjust
- inventory.transfer

- orders.view
- orders.create
- orders.update

- invoices.view
- invoices.create
- invoices.update
- invoices.cancel

- payments.view
- payments.record

- reports.view
- reports.export

- ai.chat
- ai.request_change
- ai.approve_change

- workspace.settings
- workspace.manage
- ownership.manage


Permissions can be assigned to:
- roles
- individual users
```

---

# 17. Permission Overrides

The system supports:

### Role-level permissions
Defined in roles table.

### User-level overrides
Specific permissions granted or denied to a user.

Example:
An accountant may temporarily gain `inventory.view`.

---

# 18. Approval Permissions

Certain actions require approval.

Examples:

| Action | Who Can Approve |
|------|------|
Employee join request | HR / Admin / Department Head |
AI system modification | Owner / Co-owner |
Stock transfer | Admin / Warehouse Manager |
Leave request | HR / Department Head |
Large financial transactions | Owner / Accountant |

---

# 19. AI Permissions

AI access must also follow RBAC.

### AI Capabilities

| Permission | Description |
|------|------|
ai.chat | use AI assistant |
ai.request_change | request system modification |
ai.approve_change | approve AI system changes |

Only:
- Owner
- Co-owner
- Admin (optional)

should be able to approve AI modifications.

---

# 20. Default Role Assignment

When a workspace is created:

Owner is assigned automatically.

Initial roles recommended:

- Owner
- Admin
- HR
- Accountant
- Cashier
- Warehouse Staff
- Sales
- Employee
- Viewer

Roles can be customized later.

---

# 21. Role Safety Rules

The system must enforce:

- Owner cannot be removed unless ownership transferred
- Workspace must always have at least one owner
- Dangerous permissions require confirmation
- Role changes must be audited
- Permission changes must be logged

---

# 22. Audit Requirements

Every role or permission change must generate audit logs:

Example events:

- role_assigned
- role_removed
- permission_granted
- permission_revoked
- ownership_transferred

Audit log fields:

- workspace_id
- user_id
- actor_id
- action
- old_value
- new_value
- timestamp

---

# 23. Future Extensions

Possible future improvements:

- custom roles per workspace
- role templates by industry
- temporary permissions
- approval policies per action
- dynamic AI permission governance

---