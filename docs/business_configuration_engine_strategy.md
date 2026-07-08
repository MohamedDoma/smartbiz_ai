# SmartBiz AI — Business Configuration Engine Strategy

> **Date:** 2026-07-05 | **Version:** 1.0  
> **Architecture:** SmartBiz Core + Configuration Engine + Industry Templates

---

## 1. Executive Summary

### Why a Configuration Engine

SmartBiz targets diverse industries — automotive dealers, restaurants, retail, services, manufacturing. Without a configuration layer, every new client type requires custom code: custom roles, custom forms, custom pipelines, custom rules. This does not scale.

### The Danger of Per-Client Custom Code
- Every customization becomes a maintenance liability
- Bug fixes must be applied across N branches
- Testing explodes combinatorially
- Onboarding new industries takes months instead of hours

### Recommended Architecture

```
┌─────────────────────────────────────────┐
│  SmartBiz Core (fixed)                  │
│  Auth, Modules, RBAC, Billing, AI       │
├─────────────────────────────────────────┤
│  Configuration Engine (per-workspace)   │
│  Departments, Roles, Pipelines, Fields, │
│  Documents, Commissions, Rules          │
├─────────────────────────────────────────┤
│  Industry Templates (seeded)            │
│  Automotive, Retail, Restaurant, etc.   │
│  Applied during onboarding              │
└─────────────────────────────────────────┘
```

Core code is shared. Configuration is data, not code. Templates are pre-built configurations that can be applied in one click during onboarding.

---

## 2. Core vs Configurable

### Fixed in Core (never per-client)

| Component | Reason |
|---|---|
| Auth/session/token management | Security-critical |
| Module registry (`ErpModuleRegistry`) | Defines available features |
| Permission system structure | RBAC enforcement |
| Multi-tenant isolation (RLS) | Data safety |
| Billing/subscription engine | Platform economics |
| AI safety (confirm/reject flow) | Legal liability |
| Audit logging | Compliance |
| API conventions (headers, errors) | Stability |

### Configurable Per Workspace

| Component | Example |
|---|---|
| **Enabled modules** | Retail enables POS; services company does not |
| **Departments** | "Vehicle Sales", "Parts", "Finance" |
| **Teams** | "North Region Sales", "Service Bay A" |
| **Roles** | "Sales Manager", "Parts Clerk", "Workshop Lead" |
| **Permissions per role** | Sales Manager: invoices.*, customers.*; Parts Clerk: products.view |
| **Pipelines** | "Vehicle Sale Pipeline", "Service Request Pipeline" |
| **Custom fields** | Product: "VIN", "Mileage"; Customer: "Company Registration" |
| **Document checklists** | Vehicle sale: ID copy, registration, insurance |
| **Ownership policies** | "Customer owned by creating salesperson" |
| **Duplicate rules** | "Same phone = duplicate within workspace" |
| **Commission rules** | "5% of invoice total for closing salesperson" |
| **Approval workflows** | "Invoices > 50k require manager approval" |
| **Report templates** | "Daily Sales by Salesperson", "Weekly Parts Movement" |
| **Notification rules** | "Alert manager when invoice overdue > 7 days" |
| **AI context rules** | "When advising, consider automotive inventory turn rates" |

---

## 3. Configuration Engine Concepts

| Concept | Definition |
|---|---|
| **Workspace** | A tenant. One company = one workspace. Isolated data. |
| **Department** | A business unit within a workspace (e.g., "Vehicle Sales"). Employees belong to ≥1 department. |
| **Team** | A group within a department (e.g., "North Sales Team"). Optional subdivision. |
| **Role** | A named permission set (e.g., "Sales Manager"). Workspace-scoped. |
| **Permission** | A granular action right (e.g., `invoices.create`). Defined in core, assigned via roles. |
| **User Assignment** | An employee's membership in a workspace with ≥1 role. |
| **Multi-role Employee** | One person can hold "Sales Rep" + "HR Coordinator" simultaneously. Permissions are merged. |
| **Manager Assignment** | A user designated as manager of a department/team. Gets escalation + reporting access. |
| **Effective-dated Org** | Org changes (promotions, transfers) stored with `effective_from` / `effective_until`. History preserved. |
| **Pipeline** | A sequence of stages for a business process (e.g., Lead → Quote → Negotiation → Closed Won). |
| **Pipeline Stage** | One step in a pipeline with rules (required fields, auto-actions). |
| **Custom Field** | A workspace-defined field on any entity (product, customer, invoice). Schema: name, type, required, options. |
| **Document Checklist** | A template listing required documents for a process (e.g., vehicle sale requires 5 documents). |
| **Ownership Policy** | Rules for who "owns" a record (e.g., customer belongs to creating user, or to assigned team). |
| **Duplicate Rule** | Matching criteria to detect duplicates (e.g., phone or email match within workspace). |
| **Commission Rule** | Calculation formula for sales commissions (percentage, tiered, per-product). |
| **Approval Workflow** | Conditions that trigger approval (amount thresholds, document count). |
| **Report Template** | Pre-defined report structure (dimensions, metrics, filters, schedule). |
| **Notification Rule** | Event → condition → action (e.g., invoice overdue 7d → notify manager). |
| **AI Context Rule** | Industry-specific context injected into AI prompts (vocabulary, KPIs, norms). |

---

## 4. Industry Templates

A template is a JSON/database seed that pre-populates configuration when applied during onboarding.

### Template Structure

```
Template:
  name: "Automotive Dealer"
  enabled_modules: [products, customers, invoices, payments, inventory, employees, ...]
  departments: [{ name: "Vehicle Sales" }, { name: "Spare Parts" }, { name: "Finance" }, ...]
  roles: [{ name: "Sales Manager", perms: [...] }, { name: "Parts Clerk", perms: [...] }, ...]
  pipelines: [{ name: "Vehicle Sale", stages: ["Lead", "Test Drive", "Negotiation", "Closed"] }]
  document_checklists: [{ name: "Vehicle Sale Docs", items: ["ID Copy", "Registration", ...] }]
  commission_rules: [{ name: "Vehicle Commission", type: "percentage", value: 2.5 }]
  report_templates: [{ name: "Daily Sales", dimensions: ["salesperson", "department"] }]
  custom_fields: [{ entity: "product", name: "VIN", type: "text" }, ...]
```

### Included Templates

#### Automotive Dealer
| Config | Values |
|---|---|
| Modules | products, customers, invoices, payments, inventory, employees, roles, departments, teams, accounting, reports |
| Departments | Vehicle Sales, Spare Parts, Service/Workshop, Finance, Marketing, HR |
| Roles | Sales Manager, Sales Rep, Parts Manager, Parts Clerk, Service Advisor, Workshop Tech, Finance Manager |
| Pipelines | Vehicle Sale (Lead → Test Drive → Negotiation → Finance Review → Delivery → Closed) |
| Custom fields | Product: VIN, Mileage, Year, Color; Customer: Driver License, Company Reg |
| Documents | Vehicle Sale: ID, License, Insurance, Registration, Financing Agreement |
| Commission | Vehicle: 2.5% of net; Parts: 1% of net |
| Reports | Daily Sales by Rep, Weekly Parts Movement, Monthly Revenue by Dept |

#### Retail / POS
| Config | Values |
|---|---|
| Modules | products, customers, invoices, payments, pos, inventory |
| Departments | Sales Floor, Warehouse, Management |
| Roles | Store Manager, Cashier, Stock Clerk |
| Pipelines | — (direct sales, no pipeline) |
| Custom fields | Product: Barcode, Shelf Location |
| Commission | Optional: per-shift target bonus |

#### Workshop / Service
| Config | Values |
|---|---|
| Modules | customers, invoices, payments, products, inventory, serviceJobs, employees |
| Departments | Reception, Workshop, Parts |
| Roles | Service Advisor, Lead Technician, Technician, Parts Clerk |
| Pipelines | Service Job (Intake → Diagnosis → Approval → In Progress → QC → Ready → Delivered) |
| Documents | Service: Vehicle Check-in Form, Customer Authorization |
| Reports | Daily Job Throughput, Technician Efficiency |

#### Restaurant / F&B
| Config | Values |
|---|---|
| Modules | products, menuManagement, ingredients, restaurantTables, restaurantOrders, kitchenDisplay, pos, payments, inventory |
| Departments | Front of House, Kitchen, Bar, Management |
| Roles | Floor Manager, Waiter, Head Chef, Line Cook, Bartender |
| Pipelines | — (order flow is managed by kitchen display) |
| Custom fields | Product: Allergens, Prep Time |

#### Professional Services
| Config | Values |
|---|---|
| Modules | customers, invoices, payments, projects, tasks, timesheets, employees, accounting, reports |
| Departments | Consulting, Legal, IT, Finance |
| Roles | Partner, Consultant, Associate, Admin |
| Pipelines | Engagement (Proposal → Contract → Active → Review → Closed) |
| Commission | Optional: project completion bonus |

---

## 5. Al Omma Cars Example

Al Omma Cars is an automotive dealer with departments, commissions, customer ownership, and document requirements. Here's how the configuration engine handles it **without custom code:**

### Org Structure
```
Al Omma Cars (Workspace)
├── Vehicle Sales Dept
│   ├── Sales Manager (role: sales_manager)
│   └── Sales Team
│       ├── Ahmed (role: sales_rep)
│       └── Sara (roles: sales_rep + hr_coordinator)  ← multi-role
├── Spare Parts Dept
│   ├── Parts Manager
│   └── Parts Clerk × 3
├── Marketing Dept
├── HR Dept
│   └── Sara (role: hr_coordinator)  ← same person, different dept
└── Finance Dept
    └── Finance Manager
```

**Config used:** `departments`, `teams`, `roles`, `user_assignments` (with multi-role support via `membership_roles`).

### Commission
- Ahmed sells a vehicle for 100,000 SAR → commission rule: 2.5% = 2,500 SAR
- Commission is tracked against invoice, linked to closing salesperson
- Parts sales: different rule (1%)

**Config used:** `commission_rules` with `department_id`, `product_category`, `percentage`.

### Customer Duplicate Protection
- Ahmed creates customer "Khalid bin Saeed" with phone +966-55-1234567
- Later, Sara tries to create "Khalid Saeed" with same phone
- System detects duplicate within workspace → blocks or warns

**Config used:** `duplicate_rules` with match fields = `[phone]`, scope = `workspace`.

- Same "Khalid bin Saeed" can exist in a **different** workspace (different company) — no cross-tenant duplicate check.

### Document Checklist
- Ahmed closes a vehicle sale → system shows required documents:
  - ☐ National ID copy
  - ☐ Driver's license
  - ☐ Insurance certificate
  - ☐ Vehicle registration transfer
  - ☐ Financing agreement (if financed)
- Sale cannot be marked "Delivered" until all documents uploaded

**Config used:** `document_templates` + `document_requirements` linked to pipeline stage "Delivery".

### Manager Reports
- Sales Manager gets daily report: "Ahmed: 1 sale, Sara: 0 sales, Total: 100k SAR"
- Weekly report aggregates by team
- Monthly report compares departments

**Config used:** `report_templates` with `schedule`, `group_by`, `department_scope`.

### Org Change Mid-Month
- New Sales Manager replaces existing one on July 15th
- Old manager's historical reports remain intact
- New manager sees data from July 15th onward

**Config used:** `org_assignments` with `effective_from = 2026-07-15`, `effective_until = null`. Previous assignment gets `effective_until = 2026-07-14`.

---

## 6. Data Model Proposal

All tables are workspace-scoped (tenant-isolated via `workspace_id`).

### Existing Backend Models (already built)
| Model | Purpose |
|---|---|
| `Workspace` | Tenant |
| `WorkspaceMembership` | User ↔ workspace link |
| `MembershipRole` | User ↔ role link (multi-role) |
| `Role` | Named permission set |
| `PermissionDefinition` | Available permissions |
| `WorkspaceConfiguration` | Workspace-level settings |
| `WorkspaceFeatureFlag` | Module toggle |

### New Tables Needed

| Table | Purpose | Key Fields |
|---|---|---|
| `business_templates` | Industry template definitions | `slug`, `name`, `config_json`, `is_active` |
| `departments` | Business units | `workspace_id`, `name`, `parent_id`, `manager_user_id` |
| `teams` | Groups within departments | `workspace_id`, `department_id`, `name`, `lead_user_id` |
| `org_assignments` | User ↔ dept/team with dates | `user_id`, `department_id`, `team_id`, `effective_from`, `effective_until` |
| `pipelines` | Process flows | `workspace_id`, `name`, `entity_type` (deal, service_job, etc.) |
| `pipeline_stages` | Steps in a pipeline | `pipeline_id`, `name`, `order`, `required_fields_json`, `auto_actions_json` |
| `custom_fields` | Dynamic fields | `workspace_id`, `entity_type`, `name`, `field_type`, `options_json`, `required` |
| `document_templates` | Checklist definitions | `workspace_id`, `name`, `pipeline_stage_id` |
| `document_requirements` | Items in a checklist | `template_id`, `name`, `required`, `file_types` |
| `ownership_policies` | Record ownership rules | `workspace_id`, `entity_type`, `policy_type` (creator, team, manual) |
| `duplicate_rules` | Dedup criteria | `workspace_id`, `entity_type`, `match_fields_json`, `action` (block, warn) |
| `commission_rules` | Sales commission formulas | `workspace_id`, `department_id`, `product_category_id`, `type`, `value`, `tiers_json` |
| `report_templates` | Saved report configs | `workspace_id`, `name`, `dimensions_json`, `metrics_json`, `schedule` |
| `approval_workflows` | Condition → approval chain | `workspace_id`, `entity_type`, `condition_json`, `approver_role_id` |
| `notification_rules` | Event-driven alerts | `workspace_id`, `event`, `condition_json`, `channel`, `recipient_type` |
| `ai_context_rules` | Industry AI context | `workspace_id`, `context_type`, `prompt_fragment`, `priority` |

---

## 7. Backend API Proposal

### Super Admin — Template Management

| Endpoint | Status | Purpose |
|---|---|---|
| `GET /admin/templates` | ⚠️ Proposed | List industry templates |
| `POST /admin/templates` | ⚠️ Proposed | Create template |
| `PUT /admin/templates/{id}` | ⚠️ Proposed | Update template |
| `POST /admin/templates/{id}/clone` | ⚠️ Proposed | Duplicate template |

### Workspace Configuration

| Endpoint | Status | Purpose |
|---|---|---|
| `GET /workspace/config` | ⚠️ Proposed | Full workspace config (departments, roles, pipelines, rules) |
| `POST /workspace/apply-template` | ⚠️ Proposed | Apply industry template to workspace |
| `PUT /workspace/config` | ⚠️ Proposed | Update workspace-level settings |

### Departments / Teams / Org

| Endpoint | Status |
|---|---|
| `GET/POST/PUT/DELETE /departments` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /teams` | ⚠️ Proposed |
| `GET/POST/PUT /org-assignments` | ⚠️ Proposed |

### Pipelines / Custom Fields / Documents

| Endpoint | Status |
|---|---|
| `GET/POST/PUT/DELETE /pipelines` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /pipeline-stages` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /custom-fields` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /document-templates` | ⚠️ Proposed |

### Rules

| Endpoint | Status |
|---|---|
| `GET/POST/PUT/DELETE /commission-rules` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /duplicate-rules` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /approval-workflows` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /notification-rules` | ⚠️ Proposed |
| `GET/POST/PUT/DELETE /report-templates` | ⚠️ Proposed |
| `GET/POST/PUT /ai-context-rules` | ⚠️ Proposed |

---

## 8. Frontend Impact

### Needed for MVP

| UI | Purpose | Effort |
|---|---|---|
| Template selection (during onboarding) | Choose industry during registration/onboarding | S — already partially exists in blueprint flow |
| Department list/create | Workspace settings sub-screen | M |
| Role editor with permission checkboxes | Already partially built in `roles_state.dart` | M |
| Employee department/role assignment | Assignment screen exists as route | M |

### Needed Later (post-MVP)

| UI | Purpose | Effort |
|---|---|---|
| Pipeline builder | Drag-and-drop stage editor | L |
| Custom field manager | Add/edit dynamic fields per entity | L |
| Document checklist builder | Template + items editor | M |
| Commission rule editor | Formula builder UI | M |
| Approval workflow builder | Condition + approver chain | L |
| Report template designer | Dimension/metric picker | L |
| AI context rule editor | Prompt fragment management | M |
| Super Admin template builder | Full template editor | XL |

### What Can Stay Local
- Navigation mode (basic/advanced) — already works via SharedPreferences
- Dashboard layout preferences — client-side
- Filter/search state — ephemeral

---

## 9. AI Integration

### How AI Uses Configuration

1. **Template awareness** — AI knows workspace is "Automotive Dealer" and adjusts vocabulary (says "vehicle" not "product")
2. **Department context** — AI suggests actions relevant to user's department
3. **Pipeline awareness** — AI can suggest moving a deal to the next stage
4. **Custom field awareness** — AI includes custom fields in analysis
5. **Commission awareness** — AI can calculate expected commission
6. **Permission respect** — AI never suggests actions the user cannot perform

### AI Context Injection
```
System prompt += ai_context_rules.where(workspace_id = current)
  .orderBy(priority)
  .map(r => r.prompt_fragment)
  .join('\n')
```

### Safety Rules (fixed in Core)
- AI never auto-executes financial actions
- AI never deletes records without confirmation
- AI never overrides permissions
- AI never accesses other tenants' data
- Confirm/reject flow is mandatory for all mutations

---

## 10. Implementation Priority

| # | Item | Phase | Effort | Depends On |
|---|---|---|---|---|
| 1 | `business_templates` table + seed data | Config foundation | M | — |
| 2 | `departments` + `teams` tables | Config foundation | M | — |
| 3 | `GET /workspace/config` endpoint | Config read | S | #1, #2 |
| 4 | `POST /workspace/apply-template` | Template application | M | #1 |
| 5 | Connect onboarding blueprint → template | Onboarding | M | #4 |
| 6 | Dynamic roles/permissions (already has `Role`, `MembershipRole`) | RBAC | S | — |
| 7 | `pipelines` + `pipeline_stages` tables | Pipelines | M | — |
| 8 | `custom_fields` table + dynamic form rendering | Custom fields | L | — |
| 9 | `document_templates` + `document_requirements` | Documents | M | #7 |
| 10 | `duplicate_rules` + validation middleware | Dedup | M | — |
| 11 | `ownership_policies` + query scoping | Ownership | M | — |
| 12 | `commission_rules` + calculation service | Commissions | L | #2 |
| 13 | `report_templates` + report generation | Reports | L | — |
| 14 | `approval_workflows` + approval service | Approvals | L | #6 |
| 15 | `notification_rules` + event dispatcher | Notifications | M | — |
| 16 | `ai_context_rules` + prompt injection | AI context | M | — |

---

## 11. Updated Product Roadmap

| Step | Name | Category | Effort |
|---|---|---|---|
| **37** | Billing / Voucher / AI Credits Strategy | Strategy doc | S |
| **38** | Backend Verification (health, CORS, Sanctum) | Backend | S |
| **39** | ApiClient + Token Storage Foundation | Frontend | M |
| **40** | Auth Integration (login, logout, /auth/me) | Frontend + Backend | M |
| **41** | Session Restore in Splash | Frontend | S |
| **42** | POST /auth/register Backend Endpoint | Backend | M |
| **43** | Register Screen Integration | Frontend | S |
| **44** | Business Config Foundation (templates table, seed) | Backend | M |
| **45** | Onboarding → Template Application | Frontend + Backend | M |
| **46** | Products Real Integration (first CRUD) | Frontend + Backend | M |
| **47** | Contacts / Customers Integration | Frontend + Backend | M |
| **48** | Invoices + Payments Integration | Frontend + Backend | L |
| **49** | Inventory Integration | Frontend + Backend | M |
| **50** | Employee Invite Backend + Integration | Backend + Frontend | L |
| **51** | Departments / Teams / Org Structure | Backend + Frontend | L |
| **52** | Pipelines + Custom Fields | Backend + Frontend | L |
| **53** | Document Checklists | Backend + Frontend | M |
| **54** | Commission Rules | Backend + Frontend | L |
| **55** | Duplicate / Ownership Rules | Backend + Frontend | M |
| **56** | Report Templates | Backend + Frontend | L |
| **57** | Finance Integration (accounts, journal entries) | Frontend + Backend | L |
| **58** | Super Admin Integration | Frontend + Backend | L |
| **59** | AI Chat + Advisor Integration | Frontend + Backend | M |
| **60** | Approval Workflows | Backend + Frontend | L |
| **61** | Notification Rules Engine | Backend + Frontend | M |
| **62** | AI Context Rules | Backend + Frontend | M |
| **63** | Hardening / QA / Performance | Full stack | L |
| **64** | Launch Preparation | Full stack | M |

---

## 12. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **Overbuilding config too early** — building pipeline/commission/approval before basic CRUD works | Wasted effort, delayed launch | Stick to roadmap order; auth + CRUD first |
| 2 | **Making every client "special"** — custom code despite engine | Defeats purpose | All customization must be data, not code |
| 3 | **Weak permission enforcement** — roles bypass each other | Security breach, data leak | Test RBAC with real multi-role scenarios |
| 4 | **Incorrect duplicate matching** — false positives block real records | User frustration | Make duplicate rules configurable (warn vs block) |
| 5 | **Commission disputes** — wrong calculation or attribution | Financial + trust damage | Commission = immutable audit trail, never editable after close |
| 6 | **Report data mismatch** — report shows different numbers than screen | Trust damage | Reports and screens use same query layer |
| 7 | **AI using wrong context** — automotive AI advice shown to restaurant | Irrelevant suggestions | `ai_context_rules` scoped to workspace, refreshed on template change |
| 8 | **Template rigidity** — template applies but can't be modified afterward | Frustrated admin | Templates are starting points; all config is editable post-apply |

---

## 13. Final Recommendation

### Should SmartBiz become configurable?

**Yes, but incrementally.** The configuration engine should be built in layers:

1. **Now (Steps 37–49):** Auth + CRUD integration using existing backend. No config engine yet.
2. **Soon (Steps 50–55):** Departments, teams, roles, pipelines, custom fields, documents. This is where the config engine starts.
3. **Later (Steps 56–62):** Commission rules, approval workflows, report templates, AI context. Advanced configuration.

### What Should Be Implemented First
- Backend verification + ApiClient + real auth (Steps 38–41)
- Products as first real CRUD module (Step 46)
- Template seed data + onboarding template application (Steps 44–45)

### What Should Wait
- Pipeline builder UI (complex, post-MVP)
- Commission calculation engine (needs real sales data first)
- AI context rules (needs AI provider integration first)
- Approval workflows (needs real multi-user testing)

### How This Affects Customers
- **First customer (e.g., Al Omma Cars):** Use the Automotive Dealer template. Configure departments and roles manually via config endpoints. Custom fields and document checklists added as they're built.
- **Future customers:** Select template during onboarding. Get pre-configured workspace in seconds. Customize as needed via settings.

> **The configuration engine is the difference between "one product, many clients" and "many products, one client each."**
