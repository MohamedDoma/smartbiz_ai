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

---

# 4. Standard Response Format

All API responses should follow a consistent shape when possible.

Example success response:

```

{
"success": true,
"message": "optional message",
"data": {},
"meta": {}
}

```

Example error response:

```

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

```

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
- or token membership

Example header:

```

X-Workspace-ID: <workspace_uuid>

```

Backend must validate:

- user membership
- role permissions
- RLS constraints

---

# 7. Auth Endpoints

## 7.1 Register

POST

```

/api/v1/auth/register

```

Request:

```

{
"email": "[user@email.com](mailto:user@email.com)",
"password": "password",
"name": "User Name"
}

```

Response:

```

{
"success": true,
"data": {
"user_id": "...",
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

```

{
"email": "[user@email.com](mailto:user@email.com)",
"password": "password"
}

```

Response:

```

{
"success": true,
"data": {
"access_token": "...",
"refresh_token": "...",
"user": {}
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

```

{
"refresh_token": "..."
}

```

Response:

```

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

```

{
"name": "My Business",
"country": "Malaysia",
"currency": "MYR"
}

```

Response:

```

{
"success": true,
"data": {
"workspace_id": "..."
}
}

```

---

## 8.2 List User Workspaces

GET

```

/api/v1/workspaces

```

Response:

```

{
"success": true,
"data": [
{
"workspace_id": "...",
"name": "Business A",
"role": "owner"
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

Request:

```

{
"workspace_code": "ABC123",
"name": "Employee Name"
}

```

Response:

```

{
"success": true,
"message": "Join request submitted"
}

```

---

## 9.2 Approve Join Request

POST

```

/api/v1/workspaces/join/{request_id}/approve

```

---

# 10. User Endpoints

## 10.1 List Users

GET

```

/api/v1/users

```

## 10.2 Update User Role

PATCH

```

/api/v1/users/{user_id}/role

```

---

# 11. Product Endpoints

## 11.1 Create Product

POST

```

/api/v1/products

```

Request:

```

{
"name": "Product A",
"price": 20,
"sku": "SKU123"
}

```

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

---

# 12. Inventory Endpoints

## 12.1 Adjust Inventory

POST

```

/api/v1/inventory/adjust

```

Request:

```

{
"product_id": "...",
"warehouse_id": "...",
"quantity": 10,
"reason": "manual adjustment"
}

```

---

## 12.2 Transfer Inventory

POST

```

/api/v1/inventory/transfer

```

---

# 13. Order Endpoints

## 13.1 Create Order

POST

```

/api/v1/orders

```

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

```

{
"invoice_id": "...",
"amount": 100,
"method": "cash"
}

```

---

# 16. Accounting Endpoints

## 16.1 List Accounts

GET

```

/api/v1/accounts

```

---

## 16.2 Create Journal Entry

POST

```

/api/v1/journals

```

Request:

```

{
"lines":[
{"account_id":"...","debit":100},
{"account_id":"...","credit":100}
]
}

```

---

# 17. AI Endpoints

## 17.1 AI Chat

POST

```

/api/v1/ai/chat

```

Request:

```

{
"message": "Show me sales trend"
}

```

Response:

```

{
"success": true,
"data": {
"reply": "Sales increased 10% this week."
}
}

```

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

```

{
"device_id": "...",
"operations":[]
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

Examples:

```

/api/v1/platform/workspaces
/api/v1/platform/feature-requests
/api/v1/platform/broadcasts
/api/v1/platform/surveys
/api/v1/platform/events
/api/v1/platform/analytics

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
- inventory transfer
- approval processing

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

# 26. Definition of Done

API layer is considered complete when:

- authentication endpoints work
- workspace isolation enforced
- ERP endpoints operational
- approval endpoints functional
- AI endpoints safe
- offline sync endpoints implemented
- platform endpoints separated
```

---