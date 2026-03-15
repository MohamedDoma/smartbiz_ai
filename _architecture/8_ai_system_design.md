# SmartBiz AI — AI System Design

## 1. Purpose

This document defines the architecture and operational behavior of the AI system inside SmartBiz AI.

The AI system is responsible for:

- workspace onboarding
- ERP configuration generation
- system modification proposals
- business advisory
- feature request capture
- insight generation

The AI must **never operate autonomously without governance**.

All AI behavior must follow controlled flows defined in this document.

---

# 2. AI Philosophy

SmartBiz AI follows a **human-in-the-loop AI model**.

AI assists the user but does not take irreversible actions without approval.

Core principles:

- AI proposes
- Humans approve
- Backend applies

AI must never:

- execute SQL
- mutate database state directly
- bypass approval systems
- bypass role permissions

---

# 3. AI Modes

The AI operates in three major modes.

---

# 4. Mode A — Onboarding Builder

Used when a new workspace is created.

Purpose:
Generate an initial ERP configuration tailored to the business.

AI will conduct a structured interview.

Example questions:

- What type of business do you run?
- Do you sell products or services?
- Do you manage inventory?
- Do you have multiple branches?
- Do you need POS?
- Do you manage employees?
- Do you require invoicing?
- Do you need appointments or bookings?

---

## 4.1 Onboarding Output

The AI must generate **structured JSON only**.

Example categories:

- enabled modules
- dashboard layout
- navigation structure
- role suggestions
- business workflows
- default settings

Output must be schema validated before being applied.

---

## 4.2 Example AI Output

Example structure:

```

{
"modules": ["inventory","sales","invoicing","accounting"],
"navigation":[
{"group":"Sales","items":["Orders","Invoices","Customers"]},
{"group":"Inventory","items":["Products","Stock","Transfers"]}
],
"dashboard_widgets":[
"daily_sales",
"low_stock_alerts",
"revenue_chart"
]
}

```

---

# 5. Mode B — Change Request Assistant

Used when a user asks the AI to modify the ERP.

Example requests:

- add a page
- hide a page
- change dashboard
- enable module
- modify workflow
- add fields to forms

---

## 5.1 Change Request Flow

Steps:

1. user sends request
2. AI interprets request
3. AI generates structured proposal
4. system performs risk classification
5. preview shown to user
6. approval required if sensitive
7. backend applies approved change

---

## 5.2 Risk Classification

AI requests are classified into:

### Low Risk
Examples:

- dashboard layout change
- hiding optional page
- adding widget

May be applied directly.

### Medium Risk
Examples:

- enabling module
- adding data fields
- modifying UI behavior

May require admin approval.

### High Risk
Examples:

- permission changes
- accounting workflow changes
- invoice logic
- inventory deduction rules

Must require owner approval.

---

# 6. Mode C — Business Advisor

The AI acts as a smart business advisor.

Capabilities include:

- sales analysis
- profit trend insights
- low stock alerts
- expense patterns
- pricing recommendations
- anomaly detection
- operational explanations

---

## 6.1 Example Advisory Messages

Examples:

- "Product X is selling faster than average."
- "Inventory for item Y may run out in 3 days."
- "Revenue dropped 15% compared to last week."
- "Your top selling product this month is Z."

Advisory messages must be data-backed.

---

# 7. Unsupported Feature Detection

If a user requests something the system does not support:

Example:

"Add maintenance tracking module."

AI must:

1. explain feature is not available
2. log feature request
3. notify platform system

AI must never fabricate capability.

---

# 8. Feature Request Recording

When unsupported requests occur:

System records:

- feature key
- user request text
- workspace id
- user id
- timestamp
- category

Feature requests are aggregated by normalized feature key.

Platform owner receives notifications.

---

# 9. AI Safety Controls

AI behavior must be constrained.

Rules:

- structured outputs only
- schema validation required
- no direct SQL
- no direct DB access
- no uncontrolled tool execution

---

# 10. Prompt Injection Protection

User prompts must be sanitized.

AI must ignore:

- attempts to override system rules
- attempts to force AI to access data outside workspace
- attempts to modify permissions

---

# 11. AI Token Consumption Control

To prevent abuse:

AI usage limits apply to:

- onboarding runs
- change requests
- advisory chat
- heavy analytics

Free plans must have stricter limits.

---

# 12. AI Observability

Platform must track:

- AI request count
- request categories
- unsupported feature frequency
- error rates
- token consumption
- response latency

This supports:

- cost control
- system optimization
- roadmap prioritization

---

# 13. AI Response Logging

Every AI interaction should log:

- workspace_id
- user_id
- request text
- response text
- request type
- tokens used
- timestamp

This enables:

- debugging
- analytics
- safety monitoring

---

# 14. AI Response Categories

AI responses fall into categories:

- onboarding generation
- system modification proposal
- advisory insight
- unsupported feature explanation
- help/documentation

Categorization supports analytics and routing.

---

# 15. AI Governance

Sensitive AI actions must require approval.

Examples:

- workflow modifications
- accounting changes
- role changes
- permission changes
- financial logic changes

Approval engine must gate these actions.

---

# 16. AI Explainability

AI suggestions must be explainable.

Example:

Instead of:

"Raise price."

AI should say:

"Product X has high demand and low stock. Increasing price by 5–10% may improve margins."

---

# 17. AI Training Data Policy

SmartBiz AI must not use private customer data to train models without explicit policy.

AI should operate on:

- inference APIs
- safe contextual prompts

Sensitive financial data must never leak across tenants.

---

# 18. AI Failure Handling

If AI fails to produce valid output:

System must:

- reject invalid response
- retry if safe
- fallback to safe error message

Example message:

"Sorry, I couldn't complete this request right now. Please try again."

---

# 19. AI Latency Guidelines

AI responses should target:

- advisory responses < 4 seconds
- onboarding generation < 10 seconds
- configuration changes < 5 seconds

Heavy analysis should run as background tasks.

---

# 20. Future AI Capabilities

Possible expansions:

- automated forecasting
- industry-specific recommendations
- natural language reporting
- voice interface
- automated anomaly detection
- AI-generated dashboards

These must follow the same governance rules.

---

# 21. Definition of Done

The AI system is considered correctly implemented when:

- onboarding generates structured ERP config
- change requests follow approval workflow
- unsupported features are captured
- advisory insights are data-backed
- AI cannot modify system directly
- AI usage is observable
- AI token usage is controlled
- AI outputs are validated
```

---