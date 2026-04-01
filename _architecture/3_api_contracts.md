# SmartBiz AI — API Contracts

## 1. Purpose

This document defines the **API contract layer** between:

- Flutter clients (Android / iOS / Web)
- Backend services (FastAPI)
- Platform administration layer
- AI orchestration services

It specifies:

- endpoint structure
- request format
- response format
- authentication rules
- pagination rules
- idempotency rules
- offline sync contracts

These contracts must remain stable and versioned.

> [!IMPORTANT]
> All field names, types, defaults, and constraints below are derived from `1_database_schema.sql` which is the **single source of truth**.

---

# 2. API Versioning

All APIs must be versioned.

Example base path:

```
/api/v1/
```

Future versions may introduce:

```
/api/v2/
```

Breaking changes must **never** occur inside the same version.

---

# 3. Authentication Model

Authentication is handled using:

- JWT Access Token
- Refresh Token

### Headers

```
Authorization: Bearer <access_token>
```

> [!NOTE]
> The `users` table uses `phone_number` (not email) as the login credential. There is no `email` column on `users`.

---

# 4. Standard Response Format

All API responses should follow a consistent shape when possible.

Example success response:

```json
{
  "success": true,
  "message": "optional message",
  "data": {},
  "meta": {}
}
```

Example error response:

```json
{
  "success": false,
  "error": {
    "code": "validation_error",
    "message": "Invalid input"
  }
}
```

---

# 5. Pagination Contract

All list endpoints must support pagination.

Query parameters:

```
?page=1
&page_size=25
&sort=created_at
&order=desc
```

Response example:

```json
{
  "success": true,
  "data": [],
  "meta": {
    "page": 1,
    "page_size": 25,
    "total": 100
  }
}
```

---

# 6. Workspace Context

All workspace APIs require workspace context.

Backend resolves workspace from:

- active workspace header
- or the user's own `workspace_id` (from the `users` table)

Example header:

```
X-Workspace-ID: <workspace_uuid>
```

Backend must validate:

- user belongs to workspace (`users.workspace_id`)
- user is approved (`users.approval_status = 'approved'`)
- role permissions (via `users.role_id` → `roles.permissions`)
- RLS constraints

> [!NOTE]
> There is no separate `workspace_memberships` table. Users belong to a workspace via `users.workspace_id`. Ownership is determined by who created the workspace (first user). Roles are managed through the `roles` table and `users.role_id`.

---

# 7. Auth Endpoints

## 7.1 Register

POST

```
/api/v1/auth/register
```

Request:

```json
{
  "phone_number": "+218912345678",
  "password": "securePassword123",
  "full_name": "User Name"
}
```

> [!NOTE]
> Schema fields: `phone_number VARCHAR(20) NOT NULL`, `full_name VARCHAR(255) NOT NULL`, `password_hash VARCHAR(255) NOT NULL`. No `email` column exists on `users`.

Response:

```json
{
  "success": true,
  "data": {
    "user_id": "uuid",
    "access_token": "...",
    "refresh_token": "..."
  }
}
```

---

## 7.2 Login

POST

```
/api/v1/auth/login
```

Request:

```json
{
  "phone_number": "+218912345678",
  "password": "securePassword123"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "access_token": "...",
    "refresh_token": "...",
    "user": {
      "id": "uuid",
      "full_name": "User Name",
      "phone_number": "+218912345678",
      "workspace_id": "uuid-or-null",
      "approval_status": "approved",
      "is_active": true
    }
  }
}
```

---

## 7.3 Refresh Token

POST

```
/api/v1/auth/refresh
```

Request:

```json
{
  "refresh_token": "..."
}
```

Response:

```json
{
  "success": true,
  "data": {
    "access_token": "..."
  }
}
```

---

# 8. Workspace Endpoints

## 8.1 Create Workspace

POST

```
/api/v1/workspaces
```

Request:

```json
{
  "name": "My Business",
  "industry_type": "retail",
  "business_size": "small"
}
```

> [!NOTE]
> Schema fields: `name VARCHAR(255) NOT NULL`, `industry_type VARCHAR(100)`, `business_size VARCHAR(50)` with values `micro|small|medium|enterprise`. The schema has no `country` or `currency` column on `workspaces`. Currency is set per-document (orders, invoices, price_lists) and defaults to `'LYD'`.

Optional fields: `onboarding_data` (JSONB), `ui_configuration` (JSONB).

Response:

```json
{
  "success": true,
  "data": {
    "workspace_id": "uuid",
    "name": "My Business",
    "industry_type": "retail",
    "business_size": "small",
    "subscription_status": "freemium",
    "invite_code": "ABC123",
    "max_users": 1,
    "is_active": true,
    "created_at": "2026-01-01T00:00:00Z"
  }
}
```

---

## 8.2 List User Workspaces

GET

```
/api/v1/workspaces
```

> [!NOTE]
> Since users belong to exactly one workspace via `users.workspace_id`, this returns the single workspace the authenticated user belongs to.

Response:

```json
{
  "success": true,
  "data": [
    {
      "workspace_id": "uuid",
      "name": "Business A",
      "industry_type": "retail",
      "business_size": "small",
      "subscription_status": "freemium",
      "is_active": true
    }
  ]
}
```

---

# 9. Workspace Join Endpoints

## 9.1 Join Workspace

POST

```
/api/v1/workspaces/join
```

> [!NOTE]
> The schema uses `workspaces.invite_code` (not a separate join code). Joining creates a new `users` row in the target workspace with `approval_status = 'pending'` and `is_active = FALSE`. The field name is `invite_code` on the schema.

Request:

```json
{
  "invite_code": "ABC123",
  "full_name": "Employee Name",
  "phone_number": "+218912345678",
  "password": "securePassword123"
}
```

Response:

```json
{
  "success": true,
  "message": "Join request submitted. Awaiting approval."
}
```

---

## 9.2 Approve Join Request

POST

```
/api/v1/workspaces/users/{user_id}/approve
```

> [!NOTE]
> This sets `users.approval_status` to `'approved'` and `users.is_active` to `TRUE`. The `user_id` refers to the pending user, not a separate approval request entity.

Response:

```json
{
  "success": true,
  "message": "User approved and activated."
}
```

---

# 10. User Endpoints

## 10.1 List Users

GET

```
/api/v1/users
```

Response:

```json
{
  "success": true,
  "data": [
    {
      "id": "uuid",
      "full_name": "User Name",
      "phone_number": "+218912345678",
      "role_id": "uuid-or-null",
      "department_id": "uuid-or-null",
      "branch_id": "uuid-or-null",
      "shift_id": "uuid-or-null",
      "manager_id": "uuid-or-null",
      "approval_status": "approved",
      "is_active": true,
      "hire_date": "2026-01-01",
      "base_salary": "0.00",
      "annual_leave_balance": 21,
      "created_at": "2026-01-01T00:00:00Z"
    }
  ],
  "meta": {
    "page": 1,
    "page_size": 25,
    "total": 10
  }
}
```

## 10.2 Update User Role

PATCH

```
/api/v1/users/{user_id}/role
```

> [!NOTE]
> This updates `users.role_id` (FK to `roles` table), not a string role name.

Request:

```json
{
  "role_id": "uuid"
}
```

---

# 11. Product Endpoints

## 11.1 Create Product

POST

```
/api/v1/products
```

Request:

```json
{
  "name": "Product A",
  "base_price": 20.00,
  "cost_price": 10.00,
  "sku": "SKU123",
  "type": "physical",
  "category_id": "uuid-or-null",
  "unit_id": "uuid-or-null",
  "tax_id": "uuid-or-null",
  "min_stock_alert": 5,
  "dynamic_attributes": {}
}
```

> [!NOTE]
> Schema field is `base_price DECIMAL(10,2) NOT NULL` (not `price`). `cost_price` defaults to `0.00`. `type` must be one of: `physical`, `service`, `digital`, `subscription`.

---

## 11.2 List Products

GET

```
/api/v1/products
```

---

## 11.3 Update Product

PATCH

```
/api/v1/products/{product_id}
```

> [!NOTE]
> Products use soft-delete via `is_deleted` column. Actual DELETE is not supported.

---

# 12. Inventory Endpoints

## 12.1 Adjust Inventory

POST

```
/api/v1/inventory/adjust
```

Request:

```json
{
  "product_id": "uuid",
  "warehouse_id": "uuid",
  "variant_id": "uuid-or-null",
  "change_type": "manual_adjustment",
  "quantity_changed": 10,
  "notes": "manual adjustment"
}
```

> [!NOTE]
> Schema `inventory_logs` uses `change_type VARCHAR(50)`, `quantity_changed DECIMAL(12,4)`, `new_quantity DECIMAL(12,4)`, `notes TEXT`. The field is `notes` not `reason`. Inventory levels are tracked in `inventory_levels` table per warehouse/product/variant.

---

## 12.2 Transfer Inventory

POST

```
/api/v1/inventory/transfer
```

> [!NOTE]
> Inventory transfers are managed through the `stock_transfers` and `stock_transfer_items` tables. Stock transfers have statuses: `draft`, `pending_approval`, `approved`, `in_transit`, `received`, `cancelled`.

Request:

```json
{
  "from_warehouse_id": "uuid",
  "to_warehouse_id": "uuid",
  "items": [
    {
      "product_id": "uuid",
      "variant_id": "uuid-or-null",
      "quantity": 10
    }
  ],
  "notes": "optional notes"
}
```

---

# 13. Order Endpoints

## 13.1 Create Order

POST

```
/api/v1/orders
```

Request:

```json
{
  "branch_id": "uuid-or-null",
  "contact_id": "uuid-or-null",
  "dining_table_id": "uuid-or-null",
  "order_type": "sale_order",
  "currency": "LYD",
  "exchange_rate": 1.0000,
  "total_amount": 100.00,
  "valid_until": "2026-12-31",
  "notes": "optional",
  "items": [
    {
      "product_id": "uuid",
      "variant_id": "uuid-or-null",
      "unit_id": "uuid-or-null",
      "quantity": 2,
      "unit_price": 50.00,
      "subtotal": 100.00
    }
  ]
}
```

> [!NOTE]
> `order_type` must be one of: `quote`, `sale_order`, `purchase_order`, `dine_in`, `takeaway`. Default currency is `'LYD'`. Status values: `draft`, `confirmed`, `processing`, `completed`, `cancelled`. `order_number` is auto-generated from `document_sequences`.

---

## 13.2 List Orders

GET

```
/api/v1/orders
```

---

# 14. Invoice Endpoints

## 14.1 Create Invoice

POST

```
/api/v1/invoices
```

Request:

```json
{
  "branch_id": "uuid-or-null",
  "contact_id": "uuid-or-null",
  "order_id": "uuid-or-null",
  "parent_invoice_id": "uuid-or-null",
  "invoice_type": "sale",
  "currency": "LYD",
  "exchange_rate": 1.0000,
  "total_amount": 120.00,
  "discount_amount": 0.00,
  "net_amount": 120.00,
  "tax_amount": 0.00,
  "due_date": "2026-02-01",
  "return_reason": null,
  "items": [
    {
      "product_id": "uuid",
      "variant_id": "uuid-or-null",
      "unit_id": "uuid-or-null",
      "warehouse_id": "uuid-or-null",
      "quantity": 2,
      "unit_price": 60.00,
      "discount_amount": 0.00,
      "tax_amount": 0.00,
      "subtotal": 120.00
    }
  ]
}
```

> [!NOTE]
> `invoice_type` must be one of: `sale`, `purchase`, `return`, `refund`. Default currency is `'LYD'`. `payment_status` values: `unpaid`, `partial`, `paid`, `overdue`, `refunded`. `invoice_number` is auto-generated from `document_sequences`. Snapshots (`product_name_snapshot`, `sku_snapshot`, `tax_rate_snapshot`) are captured server-side.

---

## 14.2 Get Invoice

GET

```
/api/v1/invoices/{invoice_id}
```

---

# 15. Payment Endpoints

## 15.1 Record Payment

POST

```
/api/v1/payments
```

Request:

```json
{
  "invoice_id": "uuid",
  "account_id": "uuid-or-null",
  "amount": 100.00,
  "payment_method": "cash",
  "reference_number": "optional",
  "payment_date": "2026-01-15"
}
```

> [!NOTE]
> Schema field is `payment_method` (not `method`). Valid values: `cash`, `bank_transfer`, `check`, `card`, `mobile_payment`. `payment_number` is auto-generated from `document_sequences`. `amount` must be > 0.

---

# 16. Accounting Endpoints

## 16.1 List Accounts

GET

```
/api/v1/accounts
```

> [!NOTE]
> Accounts have: `code VARCHAR(50)`, `name VARCHAR(255)`, `type` one of (`asset`, `liability`, `equity`, `revenue`, `expense`), `parent_id` (self-FK for tree structure), `balance` (cached, source of truth is `SUM from journal_lines`).

---

## 16.2 Create Journal Entry

POST

```
/api/v1/journals
```

Request:

```json
{
  "reference": "JE-001",
  "description": "Monthly rent expense",
  "date": "2026-01-31",
  "lines": [
    {"account_id": "uuid", "debit": 100.00, "credit": 0.00, "description": "Rent expense"},
    {"account_id": "uuid", "debit": 0.00, "credit": 100.00, "description": "Cash payment"}
  ]
}
```

> [!NOTE]
> `description TEXT NOT NULL` and `date DATE NOT NULL` are required on `journal_entries`. Each journal line must have either debit > 0 or credit > 0 (not both). Total debit must equal total credit (enforced by DB trigger).

---

# 17. AI Endpoints

## 17.1 AI Chat

POST

```
/api/v1/ai/chat
```

Request:

```json
{
  "message": "Show me sales trend"
}
```

Response:

```json
{
  "success": true,
  "data": {
    "reply": "Sales increased 10% this week."
  }
}
```

> [!NOTE]
> AI requests are logged in `ai_request_logs` with fields: `request_type` (one of: `onboarding`, `change_request`, `advisory`, `analytics`, `unsupported`), `ai_model`, `tokens_used`, `latency_ms`, `status`.

---

## 17.2 AI Change Request

POST

```
/api/v1/ai/change-request
```

---

# 18. Approval Endpoints

## 18.1 List Approvals

GET

```
/api/v1/approvals
```

> [!NOTE]
> Uses `approval_requests` table. Fields: `entity_type` (e.g., invoice, order, payment, leave, stock_transfer, production_order), `entity_id`, `requested_by`, `assigned_to`, `status` (one of: `pending`, `approved`, `rejected`, `escalated`), `priority` (one of: `low`, `normal`, `high`, `urgent`), `decision_note`.

---

## 18.2 Approve Action

POST

```
/api/v1/approvals/{approval_id}/approve
```

---

# 19. Notification Endpoints

## 19.1 List Notifications

GET

```
/api/v1/notifications
```

> [!NOTE]
> Schema fields: `title VARCHAR(255)`, `message TEXT`, `type` (one of: `info`, `warning`, `alert`, `success`), `is_read BOOLEAN`, `link_url TEXT`. Notifications are scoped to `workspace_id` and `user_id`.

---

## 19.2 Mark Read

POST

```
/api/v1/notifications/{id}/read
```

---

# 20. Offline Sync Endpoints

## 20.1 Sync Operations

POST

```
/api/v1/sync
```

Request:

```json
{
  "device_id": "...",
  "operations": []
}
```

Backend must:

- validate operations
- replay safely
- reject duplicates

---

# 21. Platform Admin APIs

Platform APIs must use separate namespace.

Example:

```
/api/v1/platform/
```

> [!NOTE]
> Platform admin tables use `platform_users` for authentication (with `email` + `password_hash`, unlike workspace users who use `phone_number`). Platform roles: `platform_owner`, `platform_admin`, `platform_support`, `platform_operations`.

Examples:

```
/api/v1/platform/workspaces
/api/v1/platform/feature-requests
/api/v1/platform/broadcasts
/api/v1/platform/surveys
/api/v1/platform/events
/api/v1/platform/analytics
/api/v1/platform/ai-logs
```

---

# 22. Idempotency

Critical endpoints must support idempotency.

Examples:

- payments
- POS sales
- offline sync
- invoice creation

Header example:

```
Idempotency-Key: <uuid>
```

---

# 23. Transaction Requirements

Critical workflows must run inside DB transactions.

Examples:

- invoice creation
- payment posting
- inventory transfer (stock_transfers)
- approval processing
- journal entry creation (debit/credit balance enforced by trigger)

---

# 24. Error Codes

Standardized error codes include:

```
validation_error
auth_error
permission_error
workspace_error
approval_required
conflict_error
ai_error
internal_error
```

---

# 25. Rate Limiting

Endpoints requiring limits:

- login
- AI chat
- AI onboarding
- AI change requests

Limits should depend on subscription plan.

---

# 26. Currency Default

> [!IMPORTANT]
> The default currency across all financial documents (orders, invoices, price_lists) is `'LYD'` (Libyan Dinar). There is **no** workspace-level currency field. Currency is set **per document**.

---

# 27. Definition of Done

API layer is considered complete when:

- authentication endpoints work (phone_number + password)
- workspace isolation enforced (users.workspace_id + RLS)
- user approval flow works (approval_status lifecycle)
- ERP endpoints operational
- approval endpoints functional
- AI endpoints safe
- offline sync endpoints implemented
- platform endpoints separated (platform_users auth)

---