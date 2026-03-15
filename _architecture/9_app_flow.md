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