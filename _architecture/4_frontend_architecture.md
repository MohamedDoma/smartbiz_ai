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

---

# 26. Expansion Module Feature Flags [Core v1 + Expansion Pack]

Expansion modules use a two-tier feature flag system:

### Module-level flags (server-driven)
| Flag | Default | Scope |
|------|---------|-------|
| `enable_communications` | true | Core v1 |
| `enable_marketing` | true | Core v1 (segments, loyalty) |
| `enable_delivery` | false | Core v1 |
| `enable_compliance` | true | Core v1 framework |
| `enable_media` | true | Core v1 basic |
| `enable_integrations` | true | Core v1 |

### Sub-feature flags (Expansion Pack gating)
| Flag | Default | Controls |
|------|---------|----------|
| `enable_campaigns` | false | Marketing campaigns UI |
| `enable_referrals` | false | Referral programs UI |
| `enable_nurturing` | false | Lead nurturing sequences UI |
| `enable_live_tracking` | false | GPS tracking map UI |
| `enable_ai_content_generation` | false | AI Content Studio |
| `enable_retention_policies` | false | Data retention management UI |

### Flag resolution:
1. Backend sends workspace-specific flags on login and workspace switch
2. Flutter UI hides/shows navigation items based on `module_flag` in UI schema
3. Sub-feature flags gate individual pages within an enabled module
4. Feature flag state is cached locally and refreshed every 5 minutes
5. Flags are NOT hardcoded — they flow from `subscription_plans` + `workspace` configuration

---

# 27. Driver App Screen Model [Core v1]

The driver role uses a simplified app shell with specialized screens:

### Screen inventory:
| Screen | Route | Permissions | Notes |
|--------|-------|------------|-------|
| Driver Dashboard | `/driver` | `delivery.assignments.view @ own` | Today's assignments, stats |
| Assignment Detail | `/driver/assignment/{id}` | `delivery.assignments.view @ own` | Order detail, map, actions |
| Proof of Delivery | `/driver/assignment/{id}/proof` | `delivery.proof.capture @ own` | Photo, signature, PIN |
| COD Entry | `/driver/assignment/{id}/cod` | `delivery.proof.capture @ own` | Amount entry |
| Delivery History | `/driver/history` | `delivery.assignments.view @ own` | Past deliveries |
| Status Toggle | — | N/A (always available) | Available/Offline switch in app bar |

### Architectural notes:
- **Navigation**: Bottom nav with 3 tabs: Active / History / Profile
- **Offline resilience**: Assignment data cached locally for offline pickup/delivery
- **Location service**: Background GPS service (when on assignment, with user consent)
- **Push notifications**: FCM channel for assignment notifications (accept/reject prompt)
- **Camera integration**: Native camera for proof-of-delivery photo capture
- **Signature pad**: Canvas-based signature widget (Flutter `CustomPainter`)
- **Profile view**: Driver sees own profile, vehicle info, zone assignments (read-only)

### State management:
```
DriverProvider
├── activeAssignment: DeliveryAssignment?
├── todayAssignments: List<DeliveryAssignment>
├── driverStatus: available | busy | offline
├── locationStream: Stream<LatLng> (when active)
└── codTotal: double (today's collected amount)
```

---

# 28. Real-Time Screens [Core v1 + Expansion Pack]

Two screens require real-time data delivery:

### 28.1 Dispatch Board [Core v1]
- **Route**: `/delivery/dispatch`
- **Technology**: Server-Sent Events (SSE) or WebSocket
- **Fallback**: HTTP polling every 15 seconds
- **Data model**: Kanban board with columns per status
- **Role restriction**: Dispatcher, branch_manager, admin, owner
- **Events listened**:
  - `assignment.created`
  - `assignment.status_changed`
  - `driver.status_changed`
- **Flutter implementation**:
  - `StreamBuilder` connected to SSE/WebSocket channel
  - `AnimatedList` for card transitions between columns
  - Branch-scoped filter: only show assignments for user's branch (if branch_manager)

### 28.2 Live Tracking Map [Expansion Pack]
- **Route**: `/delivery/tracking`
- **Technology**: WebSocket for driver location updates
- **Map provider**: Google Maps or Mapbox (Flutter plugin)
- **Data model**: Map with driver markers + delivery destination pins
- **Events listened**:
  - `delivery_tracking.location_update` (lat, lng, driver_id)
  - `assignment.status_changed`
- **Flutter implementation**:
  - `GoogleMap` widget with custom markers
  - Driver location updated in real-time from WebSocket stream
  - ETA calculation displayed per active delivery
  - Cluster markers when zoom level is low

### Connection management:
- Reconnect with exponential backoff on disconnect
- Graceful degradation to polling if WebSocket unavailable
- Connection paused when screen not visible (lifecycle management)

---

# 29. POS Loyalty Widget [Core v1]

The POS terminal integrates a loyalty widget when `enable_marketing` is active:

### Widget placement:
- Embedded in the POS customer panel (right sidebar on tablet, bottom sheet on phone)
- Appears after customer is identified (phone/email lookup)

### Widget components:
```
LoyaltyWidget
├── CustomerBadge (tier name, tier icon, color)
├── PointsBalance (current balance, lifetime)
├── EarnPreview (points to be earned from current cart)
├── RedeemButton → opens RedeemSheet
│   ├── AvailableRewards (list with point cost)
│   ├── RedeemConfirmation (discount preview)
│   └── Success/Error feedback
└── TierProgressBar (progress to next tier)
```

### Data flow:
1. Customer identified → `GET /api/v1/marketing/loyalty/accounts/{contact_id}`
2. Cart updated → recalculate earn preview (client-side from earn_rules)
3. Redeem tapped → `POST /api/v1/marketing/loyalty/redeem`
4. Sale completed → points auto-earned via backend (order.confirmed event)

### UX constraints:
- Widget must load in < 500ms after customer identified
- Redeem confirmation shows exact discount before applying
- Insufficient points → button disabled with tooltip

---

# 30. Media & Integration UI Patterns [Core v1 + Expansion Pack]

### 30.1 Media Library (Asset Browser)
- **Layout**: Grid view with thumbnail previews + list view toggle
- **Search**: Full-text search + tag filter + folder filter + source filter
- **Upload**: Drag-and-drop zone + file picker (multi-select)
- **Approval workflow**: Draft assets show "Approve" action button for authorized users
- **Preview**: Lightbox modal with download link (pre-signed URL)
- **Folder structure**: Virtual folders (stored as `media_assets.folder` string)

### 30.2 Brand Kit Editor
- **Layout**: Single-page form (singleton per workspace)
- **Color pickers**: Visual hex color inputs with preview swatch
- **Logo upload**: Image crop/resize before saving
- **Tone description**: Text area with AI suggestion button
- **Live preview**: Side panel showing how brand elements look in email template context

### 30.3 Integration Provider Cards
- **Layout**: Card grid showing provider name, type badge, status indicator
- **Connect flow**: Stepper dialog with dynamic credential form
- **Credential form**: Generated from `integration_providers.config_schema` (JSON Schema → Flutter form)
- **Health indicator**: Green/yellow/red dot based on `workspace_integrations.status`
- **Error display**: Last error message shown inline on card

### 30.4 Import Wizard
- **Layout**: Multi-step wizard (5 steps)
- **File upload**: Drag-and-drop with format validation (CSV/XLSX only)
- **Column mapper**: Table UI with dropdown selectors for each source column
- **Validation results**: Collapsible error list grouped by error type
- **Progress**: Linear progress bar during validation and apply phases
- **History**: Table with past imports, filterable by entity type and status

---

*End of expansion domain frontend patterns.*

---

# 31. Task Feed Widget [Core v1]

**Route**: `/tasks/my`
**API**: `GET /api/v1/tasks/my` (§47 API contracts)
**Backend**: `TaskFeedService` read model (§33 backend architecture)
**Permission**: Implicit — filtered by user's existing RBAC keys per source entity

### Layout:
- Full-page card list with filter chips at top (All, Approvals, Deliveries, Leave, AI, Imports, Media)
- Each card: icon (per task_type), title, timestamp, urgency badge (high=red, medium=amber, low=grey)
- Action buttons inline on card (Approve/Reject, Accept/Deliver, etc.)
- Tapping card navigates to source entity detail page

### State management:
```
TaskFeedProvider
├── tasks: List<TaskItem>
├── activeFilter: String? (type filter)
├── isLoading: bool
├── isEmpty: bool
└── pendingCount: int (for badge on nav item)
```

### Refresh strategy:
- Initial load on page mount
- Pull-to-refresh on mobile
- Auto-refresh every 60 seconds (configurable)
- Push notification receipt triggers immediate refresh
- Badge on "My Tasks" nav item shows `pendingCount` (updated via same polling)

### Empty state:
- Checkmark illustration + "All caught up! No pending tasks."

---

# 32. Knowledge Base Page [Expansion Pack]

**Route**: `/ai/knowledge`
**API**: §48 API contracts
**Permission**: `ai.knowledge.view @ ws` (list), `ai.knowledge.upload @ ws` (upload), `ai.knowledge.manage @ ws` (delete)
**Feature flag**: `enable_knowledge` — gated by EntitlementMiddleware (§31 backend architecture)
**Entitlement**: Plan-gated (Business+ plan) — 402 triggers upgrade modal (§33 below)

### Layout:
- Document list page with search bar (SearchService via `?q=`), content type filter, status filter
- Table columns: title, type badge (text/PDF/URL), status badge (processing/ready/failed), chunks, date
- Upload button (top-right) opens upload dialog
- Row click opens document detail with chunk list

### Upload dialog:
```
KnowledgeUploadDialog
├── TitleInput (required)
├── ContentTypeSelector (text | PDF | URL)
├── ContentInput
│   ├── TextArea (if text)
│   ├── FilePicker (if PDF, max 10MB)
│   └── URLInput (if URL)
├── SubmitButton → POST /api/v1/knowledge/documents
└── ProgressIndicator (after submit, polling until status != processing)
```

### Processing states:
| Status | UI | Behavior |
|--------|-----|----------|
| `processing` | Spinner + "Processing..." badge | Poll every 5 seconds until ready/failed |
| `ready` | Green "Ready" badge | Chunks visible in detail view |
| `failed` | Red "Failed" badge + error message | Retry option (re-upload) |

### RAG context indicator:
- In AI Chat page, when knowledge chunks are used in a response, show subtle indicator: "📚 Used knowledge from: [document title]"
- This helps users understand when AI is grounding answers in their documents

---

# 33. Entitlement Gate Components [Core v1]

**Backend**: `EntitlementMiddleware` + `EntitlementService` (§31 backend architecture)
**Business rule**: BR-SYS-006 (entitlement resolution precedence)

### 33.1 Upgrade Required Modal

Triggered by: 402 `entitlement_required` API response

```
UpgradeRequiredModal
├── FeatureIcon + FeatureName (from error response)
├── FeatureDescription (localized)
├── PlanComparisonTable
│   ├── CurrentPlan (highlighted, features listed)
│   └── RequiredPlan (highlighted, missing features shown)
├── UpgradeButton → navigates to /admin/subscription
└── DismissButton
```

### 33.2 Quota Exceeded Widget

Triggered by: 429 `quota_exceeded` API response

```
QuotaExceededWidget
├── QuotaType (e.g., "AI Requests")
├── Usage bar (current/max, e.g., "50/50")
├── Reset countdown (e.g., "Resets in 4h 23m")
└── UpgradeLink (if higher plan has higher quota)
```

### 33.3 Permission Denied Snackbar

Triggered by: 403 `permission_error` API response

- Simple snackbar/toast: "You don't have permission for this action. Contact your workspace admin."
- Auto-dismiss after 5 seconds

### 33.4 Grace Period Banner

Displayed when: workspace has `grace_ends_at` set and grace period is active

- Top-of-page banner: "Your plan was downgraded. You have {N} days left to access {feature}. Export your data or upgrade."
- Dismiss-able but reappears daily
- Links to: Export page, Upgrade page

---

*End of frontend architecture specification. Version 3.0 — 2026-04-10. Added §31–§33: task feed, knowledge base, entitlement gate components.*