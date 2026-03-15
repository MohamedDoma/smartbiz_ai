# SmartBiz AI — Frontend Architecture

## 1. Purpose

This document defines the **frontend architecture** for SmartBiz AI.

The frontend is responsible for:

- rendering the ERP UI
- managing user sessions
- handling navigation
- interacting with backend APIs
- handling offline support
- rendering AI-driven UI configuration
- supporting dynamic workspace configuration

The frontend must be designed to support:

- Android
- iOS
- Web

using a single codebase.

---

# 2. Technology Stack

Frontend is built using:

### Framework
Flutter

Reasons:
- single codebase
- high performance
- mobile + web support
- strong UI flexibility
- excellent developer ecosystem

### State Management
Recommended options:

- Riverpod
or
- Bloc

State management must support:

- reactive updates
- workspace switching
- API-driven UI updates

### Networking
Dio or http client

Responsibilities:
- authentication headers
- workspace headers
- retry logic
- error mapping

---

# 3. Application Structure

Recommended folder structure:

```

frontend/
lib/
core/
services/
models/
providers/
features/
widgets/
screens/
routing/

```

Explanation:

core → app-level utilities  
services → API integrations  
models → data models  
providers → state management  
features → ERP modules  
widgets → reusable UI components  
screens → main screens  
routing → navigation logic

---

# 4. App Entry Flow

Application startup must follow this sequence:

1. App launch
2. Load persisted session
3. Validate access token
4. Refresh token if necessary
5. Fetch user profile
6. Fetch workspace memberships
7. Route user accordingly

Possible states:

- unauthenticated
- authenticated without workspace
- authenticated with workspace
- pending join approval

---

# 5. Navigation Model

Navigation must support:

- mobile bottom navigation
- web sidebar navigation
- role-based navigation
- AI-configured navigation

Navigation items come from:

```

workspace_ui_config

```

provided by backend.

Example structure:

```

Sales
├ Orders
├ Invoices
└ Customers

Inventory
├ Products
├ Stock
└ Transfers

```

Frontend must dynamically render navigation.

---

# 6. Role-Based UI Rendering

UI elements must be controlled by:

- role permissions
- workspace configuration
- feature flags

Frontend must never show UI elements the user cannot access.

Permission checks may occur:

- locally using cached permissions
- confirmed by backend responses

---

# 7. Workspace Switching

If user belongs to multiple workspaces:

Frontend must provide workspace switcher.

Flow:

1. user selects workspace
2. active workspace stored locally
3. header updated

```

X-Workspace-ID

```

4. UI configuration reloaded
5. navigation rebuilt

---

# 8. Dynamic UI Configuration

SmartBiz AI uses **server-driven UI**.

Backend sends UI configuration including:

- enabled modules
- navigation groups
- dashboard widgets
- page schemas
- form schemas
- table schemas
- feature flags

Frontend must render UI from these schemas.

Example structure:

```

{
"navigation": [],
"dashboard_widgets": [],
"pages": [],
"forms": []
}

```

This enables AI-generated UI changes.

---

# 9. Screen Categories

Frontend screens fall into categories.

### Public Screens

- login
- register
- forgot password

### Workspace Screens

- dashboard
- products
- inventory
- orders
- invoices
- payments
- accounting
- reports
- approvals
- settings

### Platform Admin Screens

- workspace directory
- feature requests
- broadcasts
- surveys
- platform analytics

---

# 10. Feature Modules

Each ERP module should be isolated.

Example modules:

- inventory
- sales
- invoicing
- accounting
- HR
- payroll
- reporting

Each module includes:

```

screens
providers
services
models
widgets

```

Modules must remain loosely coupled.

---

# 11. Data Models

Frontend models should mirror backend schemas.

Examples:

User  
Workspace  
Product  
Invoice  
Payment  
InventoryMovement  
Notification  
ApprovalRequest

Models must support JSON serialization.

---

# 12. API Service Layer

API services handle backend communication.

Example services:

- AuthService
- WorkspaceService
- ProductService
- InventoryService
- InvoiceService
- PaymentService
- ApprovalService
- AIService
- NotificationService

Responsibilities:

- API requests
- response parsing
- error handling

---

# 13. Error Handling

Frontend must handle errors gracefully.

Common error states:

- network failure
- unauthorized
- permission denied
- workspace not found
- validation errors
- server error

Each screen must support:

- loading state
- empty state
- error state
- retry action

---

# 14. Offline Support

Offline support is partial.

Supported offline flows:

- POS product browsing
- POS sale draft creation
- cached product catalog
- cached customer lookup
- queue offline operations

Offline data stored locally.

---

# 15. Offline Sync Queue

When device reconnects:

Frontend sends queued operations.

Example payload:

```

{
"device_id": "...",
"operations": [...]
}

```

Backend processes operations sequentially.

Frontend must:

- retry failed sync
- show conflict UI when necessary

---

# 16. Notifications

Notifications are retrieved via API.

Features:

- notification center
- unread count
- navigation to entity

Types include:

- approvals
- stock alerts
- AI suggestions
- broadcasts
- feature releases

Push notifications may also be supported.

---

# 17. AI Chat Interface

AI chat must support:

- conversational UI
- markdown rendering
- structured action previews
- suggestion cards
- approval prompts

AI responses may include:

- advice
- proposed UI changes
- alerts
- explanations

---

# 18. Dashboard Rendering

Dashboard widgets are configured via backend.

Widgets may include:

- revenue chart
- sales summary
- inventory alerts
- overdue invoices
- top products
- KPI tiles

Frontend renders widgets dynamically.

---

# 19. Theming

Workspace branding may include:

- primary color
- accent color
- logo
- dark/light preference

Theme configuration delivered from backend.

Frontend must apply theme dynamically.

---

# 20. Performance Optimization

Frontend must optimize:

- list rendering
- image loading
- pagination
- caching

Use lazy loading for large lists.

---

# 21. Security Practices

Frontend must:

- store tokens securely
- never expose secrets
- validate file uploads
- sanitize user input

Sensitive actions should require confirmation.

---

# 22. Logging and Debugging

Frontend should log:

- API errors
- sync failures
- unexpected states

Logs help debugging issues.

---

# 23. Web vs Mobile Behavior

Some UX differences exist.

Mobile optimized for:

- quick operations
- approvals
- notifications
- POS

Web optimized for:

- dashboards
- data-heavy screens
- reports
- accounting workflows

---

# 24. Feature Flag Handling

Frontend must respect feature flags.

Flags may control:

- beta modules
- UI experiments
- plan-based restrictions

Flags provided by backend configuration.

---

# 25. Definition of Done

Frontend architecture is considered ready when:

- authentication flows implemented
- workspace switching works
- role-based navigation works
- API integration layer works
- server-driven UI supported
- offline POS flow implemented
- AI chat interface implemented
- dynamic dashboards supported
- notifications integrated
```