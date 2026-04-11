# SmartBiz AI — App Flow

## 1. Purpose

This document defines the end-to-end user flows for SmartBiz AI across:

- workspace owners
- co-owners
- admins
- department heads
- employees
- platform owner
- AI-assisted flows
- ERP daily operation flows
- platform feature request flows

The goal is to make the product behavior clear before implementation in backend, frontend, and AI orchestration.

---

## 2. Main User Types

The application supports the following primary user types:

### Workspace-side users
- Owner
- Co-owner
- Admin
- Department Head
- HR
- Accountant
- Sales
- Warehouse Staff
- Cashier
- Employee
- Viewer

### Platform-side users
- Platform Owner
- Platform Admin
- Platform Support
- Platform Operations

---

## 3. Main Product Surfaces

SmartBiz AI includes multiple product surfaces:

### 3.1 Public Entry Surface
Used for:
- landing
- sign up
- sign in
- workspace join
- invite acceptance

### 3.2 Workspace Surface
Used for:
- ERP daily operations
- AI chat and AI suggestions
- workspace settings
- management dashboards
- approvals

### 3.3 Platform Admin Surface
Used for:
- tenant monitoring
- feature requests
- platform notifications
- surveys
- global analytics
- platform events

---

## 4. Core Navigation States

At a high level, a user can be in one of these states:

1. unauthenticated
2. authenticated without workspace
3. authenticated with workspace membership
4. authenticated with pending join request
5. authenticated in workspace operational mode
6. authenticated in platform admin mode

---

## 5. Authentication Flow

### 5.1 Sign Up Flow
A new user can sign up using:
- email + password
- phone + password

Later enhancements may include:
- email verification
- phone OTP verification
- 2FA

### 5.2 Sign In Flow
User enters:
- email or phone
- password

System:
1. validates credentials
2. returns user session
3. loads available workspaces for that user if any
4. routes user based on status

### 5.3 Forgot Password Flow
User:
1. requests password reset
2. receives reset token or OTP
3. sets new password
4. signs in again

---

## 6. Post-Login Routing Logic

After successful authentication:

### Case A — User has no workspace and no pending join requests
Route to:
- create workspace
- join existing workspace

### Case B — User has one workspace
Route to:
- that workspace directly
or
- workspace overview if configured

### Case C — User belongs to multiple workspaces
Route to:
- workspace switcher screen

### Case D — User has pending join request only
Route to:
- pending approval screen

### Case E — User is platform owner/admin
Route may include:
- workspace switcher
- platform admin panel access

---

## 7. Workspace Creation Flow

### 7.1 Start Workspace Creation
The owner chooses:
- create new workspace

System checks:
- anti-abuse rules
- plan limits
- number of allowed workspaces
- AI onboarding quota

### 7.2 Workspace Creation Basic Info
User enters:
- business name
- country
- business type
- preferred language
- preferred currency

System creates:
- workspace shell
- owner membership
- initial settings record
- onboarding session

### 7.3 AI Onboarding Interview
AI asks structured onboarding questions such as:
- what kind of business do you run
- do you sell products or services
- do you have branches
- do you have employees
- do you need inventory
- do you need POS
- do you need invoices
- do you need appointments
- do you need payroll
- do you need manufacturing

### 7.4 AI Generated Workspace Setup
AI generates structured configuration:
- enabled modules
- navigation groups
- dashboard widgets
- suggested roles
- default business flows
- branding suggestions
- default setup recommendations

### 7.5 Owner Review
Owner reviews:
- enabled modules
- dashboard setup
- navigation
- settings
- workflow suggestions

Owner may:
- accept
- modify
- regenerate within plan limits

### 7.6 Workspace Ready
System finalizes:
- workspace config
- initial roles
- initial pages
- starter settings
- default admin environment

Then route to:
- workspace home dashboard

---

## 8. Workspace Home Flow

Once inside a workspace, the user sees a personalized home based on role.

### Possible landing pages
- owner dashboard
- admin dashboard
- cashier POS view
- warehouse dashboard
- employee home
- accountant dashboard

Landing is determined by:
- role
- permissions
- preferred home screen
- platform configuration

---

## 9. Workspace Switch Flow

If user belongs to multiple workspaces:

1. open workspace switcher
2. choose active workspace
3. backend sets active workspace context
4. client reloads workspace-scoped navigation and dashboard

System must always clearly show:
- active workspace name
- current role
- current branch if relevant

---

## 10. Employee Join Flow

### 10.1 Join via Workspace Code
An employee chooses:
- join existing workspace

Then enters:
- workspace code
- personal information
- phone or email
- optional employee ID
- optional department preference

System creates:
- pending join request

### 10.2 Approval Path
Pending request is visible to:
- HR
- Admin
- Department Head
- Owner/Co-owner if needed

Approver can:
- approve
- reject
- request clarification

### 10.3 Approval Result
If approved:
- employee gets workspace membership
- role is assigned
- branch may be assigned
- department may be assigned
- shift may be assigned
- account becomes active in workspace

If rejected:
- employee sees rejection state
- may retry or contact workspace admin

---

## 11. Sensitive Role Invite Flow

For roles such as:
- HR
- Admin
- Accountant
- Department Head
- Co-owner

Workspace management can create:
- invite link
- private invite code

Flow:
1. inviter creates invite
2. invited person signs up or signs in
3. accepts invite
4. system assigns intended role after validation
5. optional owner approval if role is sensitive

### 11.1 Invite Expiry & Revocation

- Invite links and codes expire after **72 hours** (workspace-configurable, minimum: 1 hour, maximum: 30 days)
- Expired invites MUST be rejected at submission time with a clear message: "This invite has expired. Please request a new one."
- Workspace admins may revoke active invites at any time via workspace settings
- Revoked invites are immediately invalid — any in-progress signup using a revoked code MUST fail at the join-request step
- Schema: `workspaces.invite_expires_at` (migration 011)

---

## 12. Daily ERP Operation Flows

### 12.1 Product Management Flow
Used by:
- Owner
- Admin
- Sales
- Warehouse Staff
- Accountant (view mostly)

User can:
- create product
- update product
- assign category
- assign tax
- assign unit
- configure variants
- set prices
- define stock alerts

### 12.2 Inventory Flow
Used by:
- Warehouse Staff
- Admin
- Owner

Flow:
1. view stock
2. receive stock
3. adjust stock
4. move stock between warehouses
5. inspect inventory logs
6. inspect low stock alerts
7. inspect batches if enabled

### 12.3 Order Flow
Used by:
- Sales
- Admin
- Owner
- Cashier in some contexts

Flow:
1. create order
2. add items
3. assign customer
4. calculate totals
5. save as draft or confirm
6. convert to invoice if applicable

### 12.4 Invoice Flow
Used by:
- Sales
- Accountant
- Admin
- Owner
- Cashier for POS invoices

Flow:
1. create invoice
2. add line items
3. apply tax/discount
4. save
5. issue invoice number
6. mark payment state
7. post accounting entries if configured

### 12.5 Payment Flow
Used by:
- Cashier
- Accountant
- Admin
- Owner

Flow:
1. open invoice
2. record payment
3. choose method
4. create payment record
5. update payment status
6. create ledger posting if needed
7. generate receipt if applicable

---

## 13. POS Flow

### 13.1 Open POS Session
Used by:
- Cashier

Flow:
1. cashier logs in
2. chooses terminal
3. opens POS session
4. enters opening balance if required
5. starts sales

### 13.2 POS Sale Flow
1. search/select product
2. add items to cart
3. select customer optionally
4. calculate tax/discount
5. choose payment method
6. complete sale
7. generate invoice/receipt
8. update session totals

### 13.3 POS Offline Draft Flow
If device is offline:
1. products are read from local cache
2. cashier creates sale draft
3. sale is queued locally
4. once online, sync endpoint replays draft
5. backend confirms or rejects with reason

---

## 14. Employee Self-Service Flow

Used by:
- Employee
- Department Head
- HR

Employees can:
- view profile
- update limited profile data
- view assigned tasks
- view schedule
- submit leave request
- view leave balance
- receive notifications

---

## 15. Leave Approval Flow

1. employee submits leave request
2. request enters pending state
3. visible to HR and/or Department Head
4. approver approves or rejects
5. employee receives notification
6. system updates leave records and logs approval event

---

## 16. Payroll Flow

Used by:
- HR
- Accountant
- Owner

Flow:
1. payroll records prepared
2. bonuses/deductions reviewed
3. payroll finalized
4. payment state updated
5. optional accounting posting created

---

## 17. AI Chat Flow

### 17.1 AI Assistant Entry
User opens AI chat from inside workspace.

Possible actions:
- ask for report explanation
- ask for business advice
- request UI change
- request new workflow
- request a missing feature
- ask operational questions

### 17.2 AI Intent Classification
System classifies request into one of:
- advisory question
- data insight
- UI/config change request
- unsupported feature request
- help/documentation
- risky change request

### 17.3 Safe Response
AI must:
- answer safely
- stay within workspace scope
- not apply risky changes automatically
- generate structured actions only where supported

---

## 18. AI Change Request Flow

Used by:
- Owner
- Co-owner
- Admin if permitted

Example requests:
- add a page
- hide a page
- add a field
- change dashboard layout
- enable a supported module
- adjust workflow configuration

Flow:
1. user requests change in AI chat
2. AI interprets request
3. AI generates structured proposal
4. system classifies risk
5. user sees preview
6. if low-risk and allowed, may apply directly
7. if sensitive, approval request is created
8. once approved, system applies config
9. audit event recorded

---

## 19. Unsupported Feature Request Flow

If user requests something not currently supported by the platform:

AI must not pretend it can do it.

Correct flow:
1. AI explains that the feature is not currently available
2. AI informs user the request can be registered for platform review
3. system creates a feature request record
4. request is linked to:
   - workspace
   - user
   - requested feature category
   - request text
5. platform owner is notified
6. future release can notify all requesting workspaces

Suggested AI response style:
- polite
- clear
- non-committal on release date
- honest

Example behavior:
- "This feature is not currently available in the system. Your request has been recorded and shared with the platform team for review."

---

## 20. Feature Release Notification Flow

When the platform team builds a requested feature:

1. platform owner marks feature request as released
2. system identifies linked workspaces/users
3. notification broadcast is created
4. eligible users receive:
   - in-app notification
   - optional push notification
5. workspace can enable/use feature if applicable

---

## 21. Notifications Flow

Notifications may originate from:
- approvals
- employee join requests
- AI suggestions
- overdue invoices
- stock alerts
- payroll status
- feature releases
- platform broadcasts
- survey invitations

User flow:
1. receive notification badge
2. open notification center
3. view message
4. navigate to linked entity if applicable
5. mark as read

---

## 22. Survey Flow

Used by platform layer.

### 22.1 Survey Delivery
Platform can send surveys to:
- all workspaces
- specific industries
- specific plans
- users who requested a feature
- selected user groups

### 22.2 Survey Response Flow
1. user receives survey invitation
2. opens survey
3. submits answers
4. answers stored for platform analytics

---

## 23. Platform Admin Flow

### 23.1 Platform Owner Dashboard
Platform owner can:
- view workspaces
- view adoption metrics
- view AI usage
- view sync failures
- view feature requests
- send notifications
- create surveys
- review events
- review roadmap demand

### 23.2 Feature Request Review Flow
1. platform owner opens request board
2. groups similar requests
3. reviews demand by:
   - number of users
   - number of workspaces
   - business type
4. changes status:
   - new
   - under review
   - planned
   - in progress
   - released
   - rejected

### 23.3 Broadcast Notification Flow
1. platform owner creates message
2. selects audience
3. previews message
4. sends immediately or schedules
5. delivery event logged

---

## 24. Sync Conflict Flow

When offline-generated data conflicts with server state:

1. backend detects conflict
2. backend rejects or partially accepts operation
3. client receives conflict reason
4. user sees conflict resolution UI if needed
5. system keeps authoritative server record

---

## 25. Workspace Settings Flow

Used by:
- Owner
- Co-owner
- Admin if allowed

Settings include:
- branding
- language
- currency
- branch setup
- shift setup
- module enablement
- notification preferences
- AI preferences
- join code management

Sensitive settings require:
- correct permission
- audit log
- sometimes approval

---

## 26. Role and Permission Management Flow

Used by:
- Owner
- Co-owner
- Admin if allowed

Flow:
1. open role management
2. assign role to user
3. optionally apply user permission override
4. save
5. audit event created
6. updated permissions reflected in UI immediately or on refresh

---

## 27. File Attachment Flow

Used by:
- Admin
- Accountant
- Sales
- HR
- Owner
- other roles depending on module

Flow:
1. upload file
2. backend validates file
3. store in object storage
4. attach to entity
5. save attachment metadata
6. entity shows linked files

---

## 28. Error and Empty-State Flows

System must gracefully handle:

- no workspace found
- no permissions
- pending approval
- offline mode active
- sync failed
- AI feature unsupported
- no data yet
- feature disabled
- module unavailable on plan

Every important flow must have:
- loading state
- empty state
- error state
- retry action where appropriate

---

## 29. Cross-Platform Experience Rules

Since the product runs on:
- Android
- iOS
- Web

The same flows must exist across platforms, but UX may differ.

### Mobile-first flows
Best for:
- employee self-service
- approvals
- basic sales
- POS
- notifications
- AI chat
- quick management tasks

### Web-first flows
Best for:
- full ERP management
- dashboards
- accounting
- reports
- inventory admin
- role management
- platform admin tools

---

## 30. Workspace Feature Availability Flow

Some features may be:
- globally available
- plan-restricted
- not yet built
- disabled by workspace configuration

Whenever a user tries to access a restricted feature:
1. system checks entitlement/config
2. show appropriate state:
   - enabled
   - locked by plan
   - unavailable
   - pending release
3. provide next action if applicable

---

## 31. Global Event Generation Rules

The following flows should generate platform or workspace events:
- workspace created
- join request submitted
- join request approved/rejected
- invoice created
- payment recorded
- inventory adjusted
- AI change requested
- AI change approved/applied
- unsupported feature requested
- survey answered
- broadcast delivered
- offline sync failed

These events support:
- analytics
- support
- audit
- roadmap prioritization

---

## 32. Definition of Done for App Flow Clarity

App flow is considered sufficiently defined when:
- owner onboarding is clear
- employee join flow is clear
- role-sensitive actions are clear
- AI-supported changes are clear
- unsupported feature flow is clear
- platform owner control flow is clear
- offline POS flow is clear
- approval-based behavior is clear
- workspace vs platform separation is clear

---

## 33. Next Files That Depend on This Document

After this file, create:
1. `11_platform_admin_system.md`
2. `6_business_rules.md`
3. `8_ai_system_design.md`
4. `3_api_contracts.md`

These documents must stay aligned with this app flow.

---

## 34. Communication Flow [Core v1]

```
Trigger: User navigates to Communications → Message Log / Templates
Precondition: User has communications.messages.send or communications.templates.view permission

1. User navigates to Communications  
2. System shows: Templates tab / Message Log tab / Analytics tab  
3. **Send Message flow:**  
   a. User clicks "Send Message"  
   b. System shows compose form:  
      - Channel selector (email / sms / whatsapp / push)  
      - Recipient: contact picker or manual address  
      - Template selector (optional) → auto-populates subject + body  
      - Body editor with {{variable}} interpolation preview  
   c. User submits  
   d. Backend validates (BR-COM-001, BR-COM-004):  
      - Channel provider exists and is active  
      - Recipient address is valid  
      - Body is not empty  
   e. Success → message queued → toast "Message queued"  
   f. Message appears in Message Log with status: queued → sending → sent/delivered/failed  
4. **Template CRUD flow:**  
   a. User opens Templates tab  
   b. List filtered by channel_type and locale  
   c. Create/Edit: name, channel, subject, body, variables, locale  
   d. Save → validation → success  
5. Retry: Failed messages show retry button if attempts < 3 (BR-COM-003)
```

---

## 35. Campaign Launch Flow [Expansion Pack]

```
Trigger: User navigates to Marketing → Campaigns
Precondition: marketing.campaigns.create permission

1. User clicks "Create Campaign"  
2. System shows campaign wizard:  
   Step 1: Name, type (email / sms / multi_channel)  
   Step 2: Select segment → preview contact count  
   Step 3: Select or create template → preview  
   Step 4: Set budget (optional), schedule (optional)  
   Step 5: Review summary  
3. User saves as draft  
4. **Launch flow:**  
   a. User opens draft campaign → clicks "Launch"  
   b. System validates (BR-MKT-003):  
      - Segment has contacts (contact_count > 0)  
      - Template is active and matches channel  
      - Status is draft or paused  
   c. Validation fails → inline error → no launch  
   d. Validation passes → confirmation dialog → launch  
   e. Status → active → messages begin queueing  
5. **Metrics view:**  
   a. Active/completed campaigns show real-time metrics  
   b. Sent, delivered, opened, clicked, converted, unsubscribed  
   c. Auto-refreshes every 60 seconds  
6. Pause: User can pause active campaign → no new messages queued
```

---

## 36. Loyalty Redemption Flow (POS) [Core v1]

```
Trigger: Cashier processing a POS sale with loyalty-enrolled customer
Precondition: marketing.loyalty.view + sales.pos.operate permissions

1. Cashier rings up items on POS terminal  
2. Cashier searches customer by phone/email/name  
3. System shows customer card with loyalty badge:  
   - Current tier  
   - Points balance  
   - Available rewards  
4. **Earn flow (automatic):**  
   a. On sale completion, system calculates points earned  
   b. Points auto-credited to loyalty_accounts (BR-MKT-001)  
   c. POS receipt shows "Points earned: +X | Balance: Y"  
5. **Redeem flow (manual):**  
   a. Cashier taps "Redeem Points"  
   b. System shows available rewards with point costs  
   c. Cashier selects reward → system validates balance ≥ cost  
   d. Insufficient balance → error "Not enough points"  
   e. Sufficient → discount applied to current sale  
   f. Points deducted (loyalty_transactions type=burn)  
   g. Receipt shows "Points redeemed: -X | Discount: $Y"  
6. Tier check: After each earn, system checks tier threshold (BR-MKT-002)  
   - Promotion: immediate → congratulations toast  
   - Demotion: cooldown period → no immediate change
```

---

## 37. Dispatch & Delivery Flow [Core v1]

```
Trigger: Order confirmed and ready for delivery
Precondition: delivery.assignments.create permission (dispatcher role)

1. Dispatcher opens Dispatch Board  
    - Real-time view, refreshes every 15 seconds  
    - Columns: Unassigned | Pending | In Transit | Delivered | Failed  
2. **Assign flow:**  
   a. Dispatcher picks unassigned order  
   b. System shows order details + delivery address  
   c. Dispatcher selects driver from available drivers list  
      - Filtered by: status=available, branch, zone  
   d. Dispatcher clicks "Assign"  
   e. Backend validates (BR-DEL-001):  
      - Driver status = available  
      - Order not already assigned  
   f. Success → assignment created (pending) → driver status → busy  
   g. Push notification sent to driver  
3. **Assignment lifecycle (dispatcher view):**  
   a. Card moves through columns as driver updates status  
   b. Rejected → returns to Unassigned column for re-dispatch  
   c. Failed → shows failure reason → option to re-assign  
4. **COD tracking:**  
   a. COD orders show expected collection amount  
   b. On delivery, collected amount displayed  
   c. Variance flagged if ≠ expected (BR-DEL-003)  
5. Dispatch Board respects branch scoping for branch_manager role
```

---

## 38. Driver App Flow [Core v1]

```
Trigger: Driver opens app after login
Precondition: User has driver role with delivery.assignments.view (own) permission

1. Driver sees personal dashboard:  
   - Today's assigned deliveries  
   - Active delivery (if any)  
   - Completed count / Failed count  
   - COD total collected today  
2. **New assignment notification:**  
   a. Push notification: "New delivery assigned"  
   b. Driver opens assignment detail:  
      - Customer name, address, phone  
      - Order items summary  
      - Payment method (prepaid / COD)  
      - COD amount if applicable  
   c. Driver taps "Accept" or "Reject"  
   d. Accept → status = accepted (BR-DEL-002)  
   e. Reject → status = rejected → reason required → driver back to available  
3. **Delivery execution:**  
   a. Driver taps "Pick Up" at restaurant/store → status = picked_up  
   b. Navigation opens to delivery address  
   c. [Expansion Pack] GPS location broadcast every 10 seconds  
   d. Driver arrives → taps "Deliver"  
4. **Proof of delivery (BR-DEL-004):**  
   a. For COD: enter amount collected (required)  
   b. Capture proof: photo upload, signature pad, or PIN entry  
   c. At least one proof method required for COD  
   d. Submit → status = delivered → driver back to available  
5. **Failure flow:**  
   a. Driver taps "Report Failed"  
   b. Reason required (text)  
   c. Status → failed → driver back to available  
6. Driver status toggle: Available / Offline (manual control)
```

---

## 39. Country Pack Installation Flow [Core v1 framework]

```
Trigger: Admin navigates to Compliance → Country Packs
Precondition: compliance.packs.install permission (admin/owner only)

1. System shows two sections:  
   - Installed Packs (with version, install date)  
   - Available Packs (from platform catalog)  
2. **Install flow:**  
   a. Admin browses available packs → views pack detail:  
      - Country, version, included: tax rules, payroll rules, invoice format  
   b. Admin clicks "Install"  
   c. System shows configuration override form (optional):  
      - Override default tax rates  
      - Override payroll parameters  
   d. Admin confirms  
   e. Backend validates (BR-CMP-001):  
      - Pack not already installed → 409 if duplicate  
   f. Success → creates workspace_country_packs + seeds tax_rules  
   g. Toast: "Country pack installed. Tax rules seeded."  
3. **Post-install:**  
   a. Tax Rules page now shows country-specific rules  
   b. Payroll calculations use statutory rules from pack  
   c. Invoice formats comply with country requirements  
4. **Configuration:**  
   a. Admin can override specific rules via Tax Rules page  
   b. Overrides do not delete pack defaults — they supersede  
   c. BR-CMP-002: old rules are end-dated, not deleted
```

---

## 40. AI Content Generation Flow [Expansion Pack]

```
Trigger: User navigates to Media → AI Content Studio
Precondition: media.generation.request permission

1. User opens AI Content Studio  
2. System shows:  
   - Prompt input (text area)  
   - Brand kit auto-linked (if configured)  
   - Model selector (if multiple models available)  
   - Generation history with statuses  
3. **Generate flow:**  
   a. User enters prompt, clicks "Generate"  
   b. Backend validates (BR-MDA-003):  
      - Daily AI quota not exhausted  
      - If exhausted → 429 error → "Quota exceeded. Resets at [time]"  
   c. Request queued → status: pending → processing  
   d. User sees spinner / progress indicator  
   e. Completion:  
      - Success → generated asset appears as preview  
      - Failure → error message shown  
4. **Approval flow (BR-MDA-001):**  
   a. Generated asset has status = draft  
   b. User with media.generation.approve permission reviews  
   c. "Approve" → status = approved → asset moves to library  
   d. "Reject" → asset archived  
5. Brand kit context: AI uses workspace brand colors/fonts/tone for generation (BR-MDA-002)
```

---

## 41. Integration Setup Flow [Core v1]

```
Trigger: Admin navigates to Integrations → Providers
Precondition: integrations.connections.manage permission

1. System shows available providers from platform catalog:  
   - Type badges: Payment, Email, SMS, eCommerce, Accounting, Storage  
   - Status: Not Connected / Connected / Error  
2. **Connect flow:**  
   a. Admin clicks "Connect" on a provider  
   b. System shows credential form based on provider's config_schema:  
      - e.g. Stripe: API Key, Webhook Signing Secret  
      - e.g. Twilio: Account SID, Auth Token  
   c. Admin fills credentials → "Connect"  
   d. Backend validates format against config_schema (BR-INT-003)  
   e. Connection test triggered automatically  
   f. Pending → test result in 5–15 seconds  
   g. Success: status = active → green badge  
   h. Failure: status = error → error message shown  
3. **Re-test / Disconnect:**  
   a. Admin can re-test any time  
   b. Disconnect: sets status = disconnected (BR-INT-004)  
      - Preserves sync history  
      - Cannot be undone via UI (must reconnect fresh)  
4. **Health Dashboard:**  
   a. Shows all connected integrations  
   b. Last sync time, error count, status  
   c. Failing integrations highlighted in red  
5. Webhook setup: Admin configures outbound webhooks separately (§46.6 API)
```

---

## 42. Import Flow [Core v1]

```
Trigger: User navigates to Integrations → Import / Export → Import Tab
Precondition: integrations.import.manage permission

1. User clicks "Start Import"  
2. Step 1 — Select entity type:  
   - Products, Contacts, Chart of Accounts, Inventory Adjustments  
3. Step 2 — Upload file:  
   - Supported formats: CSV, XLSX  
   - Max file size: 10MB  
   - Upload → status: uploaded  
4. Step 3 — Column mapping:  
   a. System auto-detects headers  
   b. User maps source columns → system fields  
   c. Required fields highlighted  
   d. Preview of first 5 rows with mapped values  
5. Step 4 — Validation (BR-INT-002):  
   a. Job transitions: uploaded → validating → preview  
   b. System validates:  
      - Data types (dates, numbers, required fields)  
      - Foreign key existence (categories, warehouses)  
      - Duplicate detection (exact + fuzzy match on name/SKU)  
   c. Validation results shown:  
      - Total rows / Valid / Errors  
      - Error detail: row number, column, message  
   d. User can fix source file and re-upload, or proceed  
6. Step 5 — Apply:  
   a. User clicks "Apply Import"  
   b. Confirmation dialog: "Import {N} valid rows?"  
   c. Job → applying (background)  
   d. Progress indicator (if possible)  
   e. Completion → success/failed notification  
7. Import history: list of past imports with status, counts, date
```

---

*End of expansion domain flows.*

---

## 43. Task Feed Flow [Core v1]

**Navigation**: `/tasks/my` (tasks_group in UI schema)
**Permission**: Implicit — TaskFeedService filters results by user's existing RBAC permissions per source entity
**Feature flag**: None — always available for authenticated users
**Backend**: `TaskFeedService` read model (§33 backend architecture)
**API**: `GET /api/v1/tasks/my` (§47 API contracts)

```
Flow:
1. User clicks "My Tasks" in sidebar navigation
2. Frontend calls GET /api/v1/tasks/my?status=pending
3. TaskFeedService queries 6 source tables in parallel:
   - approval_requests (pending, where user is approver)
   - delivery_assignments (pending/accepted, where user is assigned driver)
   - leave_requests (pending, where user is reporting manager)
   - ai_change_requests (pending, where user is admin/owner)
   - import_jobs (preview state, where user is the uploader)
   - media_assets (draft + ai_generated, where user has media.generation.approve)
4. Results merged and sorted by urgency DESC, created_at DESC
5. Task feed displayed as card list:
   - Each card shows: task_type icon, title, created_at, urgency badge
   - Action button(s) per task type (Approve/Reject, Accept/Deliver, Apply/Cancel)
6. User clicks action → navigated to source entity's detail page for decision
7. On completion → task disappears from feed (source entity status changed)

Push notifications:
- New approval request → push to approver's device
- New delivery assignment → push to driver's device
- New leave request → push to manager's device
- Deep link in notification opens the relevant task detail

Empty state:
- "All caught up! No pending tasks." with checkmark illustration
```

---

## 44. Knowledge Document Upload Flow [Expansion Pack]

**Navigation**: `/ai/knowledge` (knowledge_documents_page in AI group)
**Permission**: `ai.knowledge.upload @ ws` for upload, `ai.knowledge.view @ ws` for list
**Feature flag**: `enable_knowledge` (sub-feature of AI module, requires Business+ plan)
**Entitlement**: Plan-gated via EntitlementMiddleware (§31 backend architecture)
**Backend**: Knowledge documents + pgvector RAG
**API**: §48 API contracts
**Event bus**: Dispatches `ai.knowledge.uploaded` event (§29 backend architecture)

```
Flow:
1. User navigates to AI → Knowledge Base
2. If enable_knowledge == false → show "Upgrade Required" modal (§28.4 platform admin)
   - Modal: feature description + plan comparison + CTA to /admin/subscription
   - Event logged: entitlement.access.denied (task feed analytics)
3. Knowledge Base page shows existing documents list:
   - Columns: title, content_type, status (processing/ready/failed), chunks, uploaded_by, date
   - Search bar uses SearchService (§28) against knowledge_documents.title
   - Filter by content_type and status
4. Upload flow — User clicks "Upload Document":
   a. Upload dialog: title (required), content type selector (text/PDF/URL)
   b. If text: text area for direct input
   c. If PDF: file picker (10MB max, validated server-side — 413 on exceed)
   d. If URL: URL input (backend fetches and processes content)
   e. Submit → POST /api/v1/knowledge/documents → 201 with status: processing
5. Processing (background):
   a. Queue job chunks the content into ~500-token segments
   b. Each chunk gets an embedding via AI provider (OpenAI, etc.)
   c. Embeddings stored in knowledge_chunks.embedding (pgvector)
   d. On completion: status → ready, dispatches ai.knowledge.uploaded event
   e. On failure: status → failed, user notified
6. Document detail view:
   - Shows chunk list with content previews
   - Delete action requires ai.knowledge.manage permission
   - Delete removes document + all chunks (cascading)
7. RAG integration (transparent to user):
   - When user chats with AI, system auto-retrieves relevant chunks
   - Chunks injected into AI context as "Business Knowledge" section
   - User sees better, business-specific AI responses — no manual action needed
```

---

## 45. Entitlement Gate Flow [Core v1]

**Navigation**: Any gated page/endpoint
**Permission**: Resolved by 4-layer entitlement chain (§31 backend architecture, BR-SYS-006)
**Feature flag**: Per-module and per-sub-feature flags
**Backend**: `EntitlementMiddleware` + `EntitlementService`

```
Flow:
1. User clicks a navigation item for a gated feature (e.g., Marketing → Campaigns)
2. Frontend checks local feature flag cache:
   a. If module flag (enable_marketing) == false → hide nav item entirely (user never sees it)
   b. If sub-feature flag (enable_campaigns) == false → show nav item but Page shows "Upgrade Required"
3. If page loads → frontend calls API endpoint
4. Backend EntitlementMiddleware resolves 4 layers:
   Layer 1 — Plan: subscription_plans.features[feature]
     → If false → 402 {error_code: "entitlement_required", required_plan: "Business", upgrade_url: "/admin/subscription"}
   Layer 2 — Workspace override: workspace_feature_overrides[feature]
     → If override exists, use override value (skip plan check)
   Layer 3 — Role permission: user's RBAC permission for the action
     → If missing → 403 {error_code: "permission_error"}
   Layer 4 — Usage quota: daily/monthly consumption check
     → If exhausted → 429 {error_code: "quota_exceeded", resets_at: "ISO8601"}
5. Frontend handles denial responses:
   - 402 → "Upgrade Required" modal with plan comparison + upgrade CTA
   - 403 → "Permission Denied" message (contact your admin)
   - 429 → "Quota Exceeded" message with reset countdown
6. Grace period handling:
   - Downgraded workspace within 7-day grace → features still accessible
   - After grace expires → 402 response + "Export Your Data" helper link

Event tracking:
- All 402 denials logged as entitlement.access.denied events
- Platform analytics dashboard shows feature gate hit frequency per plan
- Data informs pricing decisions and plan tier design
```

---

*End of app flow specification. Version 3.0 — 2026-04-10. Added §43 Task Feed, §44 Knowledge Upload, §45 Entitlement Gate flows.*