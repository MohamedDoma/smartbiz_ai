# SmartBiz AI — Billing / Voucher / AI Credits Strategy

> **Date:** 2026-07-05 | **Version:** 1.0  
> **Market:** Libya-first launch | **Currency:** LYD  
> **Payment methods:** Cash, local card (manual), prepaid voucher

---

## 1. Executive Summary

### Recommended Model
**Monthly subscription + setup fee + AI credits + voucher recharge.** No Stripe at launch. All payments processed manually via Super Admin or redeemed via voucher codes.

### Why Not Stripe at Launch
- Libya has no Stripe coverage
- Local card infrastructure is unreliable for recurring billing
- Business clients prefer cash/bank transfer receipts
- Manual payment with admin confirmation is the fastest path to revenue

### How SmartBiz Makes Money Quickly
1. One-time setup fee (immediate cash)
2. Monthly subscription (recurring)
3. AI credit recharge cards (upsell)
4. Training/migration services (premium service)

### Future-Ready
The backend already has `ManualPayment`, `WorkspaceSubscription`, `PlatformPlan`, `PlatformPlanPrice`, `AiCreditBalance`, and `AiCreditTransaction` models. When online payments become viable, a payment provider adapter layer is added — existing billing logic stays intact.

---

## 2. Recommended Pricing Model

> **Assumptions:** Libya business market. Target = real businesses with 3–50+ employees, not hobbyists. 1 USD ≈ 5 LYD (approximate). Prices must feel professional, not cheap.

### SmartBiz Business Plan

| Item | Price (LYD) | Notes |
|---|---|---|
| **One-time setup fee** | 500 LYD | Includes onboarding, template config, 1 hour training |
| **Monthly subscription** | 250 LYD/month | Core ERP + 5 included users |
| **Extra user** | 30 LYD/user/month | Per additional active user |
| **Extra branch** | 100 LYD/branch/month | Multi-location businesses |
| **Included AI credits** | 500 credits/month | Resets monthly with active subscription |
| **AI recharge card** | 50 LYD / 200 credits | One-time purchase, does not expire while subscribed |
| **Annual prepayment** | 2,500 LYD/year | = ~2 months free (10 × 250) |
| **Priority support** | 100 LYD/month add-on | Dedicated WhatsApp/phone support line |
| **Data migration** | 200–1,000 LYD | Depends on volume and source format |
| **Training session** | 150 LYD/hour | On-site or remote |

### Founding Customer Program (first 10 customers)
| Item | Price (LYD) | Notes |
|---|---|---|
| Setup fee | **Free** | Waived for founding customers |
| First 3 months | **150 LYD/month** | 40% discount |
| After 3 months | Standard 250 LYD/month | |
| AI credits | 1,000/month (double) | Founding bonus |

---

## 3. Subscription Lifecycle

```
Trial (14 days)
  → Active (paid)
    → Grace Period (7 days after expiry)
      → Read-Only (30 days)
        → Suspended (admin action)
          → Cancelled (data retained 90 days, then archived)
```

### State Definitions

| State | Access | Data | Billing |
|---|---|---|---|
| **Trial** | Full access, all modules | Writable | No payment required |
| **Active** | Full access, all modules | Writable | Current subscription valid |
| **Grace** | Full access, warning banners | Writable | Payment overdue ≤ 7 days |
| **Read-Only** | View data, export, no create/edit/delete | Read-only | Payment overdue 8–37 days |
| **Suspended** | Login blocked, admin contact only | Preserved | Admin manually suspended |
| **Cancelled** | No access | Retained 90 days, then cold archived | Customer requested cancellation |

### Critical Rules
- **Data is NEVER deleted automatically.** After 90 days of cancellation, data is archived (cold storage), not destroyed.
- **Customer can always export** their data in read-only mode.
- **Grace period = 7 days.** Business operations continue with a warning banner.
- **Read-only = 30 days.** Customer can view all data, download reports, export CSV. Cannot create invoices, products, etc.
- **Re-activation** at any time by paying — immediately returns to Active.

---

## 4. Manual Payment Flow

### Flow

```
1. Customer pays cash/card at SmartBiz office (or bank transfer)
2. SmartBiz staff opens Super Admin → Manual Payments
3. Creates payment record: workspace, amount, method, reference, plan, period
4. Payment status = "pending"
5. Senior admin reviews and confirms
6. Confirmation → subscription extended → receipt generated → audit log
```

### Payment Record Fields
Uses existing `ManualPayment` model:
- `workspace_id`, `amount`, `currency` (LYD), `method` (cash/card/transfer)
- `reference` (receipt number, transfer ref)
- `status`: pending → confirmed / rejected
- `submitted_by`, `confirmed_by`, `confirmed_at`
- `plan_id`, `billing_cycle`
- `notes`, `rejected_reason`

### Business Rules
- Two-person rule: submitter ≠ confirmer (prevent fraud)
- Rejected payments require a reason
- Every action creates an audit log entry
- Confirmation triggers subscription period extension
- Receipt/invoice auto-generated on confirmation

---

## 5. Voucher / Recharge Card Flow

### Voucher Types

| Type | Value | Example |
|---|---|---|
| `subscription_month` | Extends subscription by N months | "1-Month SmartBiz" card |
| `ai_credits` | Adds N AI credits to balance | "200 AI Credits" card |
| `service_credit` | LYD balance for services (training, migration) | "500 LYD Service Credit" |

### Voucher Code Structure
```
Format: SMBZ-XXXX-XXXX-XXXX (16 chars, alphanumeric, grouped)
Example: SMBZ-A7K2-M9P4-R3X1

Prefix: SMBZ (brand)
Body: 12 random alphanumeric characters (uppercase + digits)
Uniqueness: globally unique, checked on generation
```

### Activation Flow

```
1. Customer opens Settings → Billing → Redeem Voucher
2. Enters voucher code
3. Backend validates: exists, not used, not expired, correct type
4. If subscription voucher → extends subscription period
5. If AI credits voucher → adds credits to balance
6. Voucher marked as redeemed (one-time use)
7. Audit log created
```

### Voucher Table (proposed: `vouchers`)

| Field | Type | Purpose |
|---|---|---|
| `id` | UUID | |
| `code` | string(19) | Unique formatted code |
| `type` | enum | subscription_month, ai_credits, service_credit |
| `value` | integer | Months, credits, or LYD cents |
| `batch_id` | string | Production batch reference |
| `generated_by` | UUID | Admin who generated |
| `redeemed_by_workspace` | UUID nullable | Workspace that used it |
| `redeemed_by_user` | UUID nullable | User who entered code |
| `redeemed_at` | timestamp nullable | |
| `expires_at` | timestamp | Card expiry date |
| `is_active` | boolean | Can be deactivated if fraud suspected |

### Fraud Prevention
- One-time use only — `redeemed_at` is set permanently
- Expiry date printed on physical card
- Batch tracking — if a batch is compromised, deactivate entire batch
- Rate limit: max 3 redemption attempts per workspace per hour
- Admin can deactivate individual codes
- All redemptions logged with IP/user/timestamp

---

## 6. AI Credits Model

### Why AI Is Not Unlimited
- AI API calls have real cost (per-token pricing from provider)
- Unlimited AI = unpredictable cost = business risk
- Credits create a measurable, sellable unit
- Credits encourage thoughtful AI usage, not spam

### Credit Consumption

| AI Action | Credits | Notes |
|---|---|---|
| AI Chat message (send + response) | 2 | Per conversation turn |
| Sales/business insight generation | 5 | Per insight |
| Monthly report generation | 10 | Per report |
| Blueprint generation (onboarding) | 20 | One-time during setup |
| Document summary | 3 | Per document |
| Advisor recommendation | 5 | Per recommendation |
| AI-suggested action (confirm) | 3 | Per confirmed action |
| Bulk analysis (e.g., customer segmentation) | 25 | Heavy computation |

### Monthly Cycle
- Active subscription: 500 included credits reset on billing period start
- Unused included credits **do not carry over** (use-it-or-lose-it)
- Purchased credits (via recharge/voucher) **do carry over** while subscription is active
- On subscription expiry → purchased credits frozen, not deleted → restored on reactivation

### When Credits Finish

| Component | Behavior |
|---|---|
| **Core ERP** (products, invoices, payments, inventory, customers, employees) | ✅ **Continues working normally** |
| **AI Chat** | ❌ Blocked — shows "Recharge AI credits" message |
| **AI Advisor** | ❌ Blocked — existing recommendations visible, no new analysis |
| **AI-generated reports** | ❌ Blocked — manual reports still work |
| **AI auto-suggestions** | ❌ Disabled |
| **Blueprint generation** | ❌ Blocked (rarely needed post-setup) |

**Core ERP never stops because of AI credits.**

---

## 7. AI Cost Protection

### Per-Workspace Limits
- **Soft limit:** Alert admin at 80% usage (e.g., 400/500 credits used)
- **Hard limit:** Block AI at 100% (0 remaining)
- Both limits exist in `AiCreditBalance` model (`soft_limit_threshold`, `hard_limit`)

### Per-User Rate Limits
- Max 30 AI chat messages per user per day
- Max 5 insight/report generations per user per day
- Backend already has `throttle:ai` middleware

### Admin Controls
- Usage dashboard in Super Admin (existing `high-usage` endpoint)
- Per-workspace credit adjustment (existing `adjustCredits` endpoint)
- AI action audit trail (`AiUsageLog`, `AiCreditTransaction` models exist)

### Safety
- AI never auto-executes financial actions (backend `confirmAction` flow)
- AI actions require explicit user confirmation
- AI respects RBAC — cannot suggest actions user cannot perform

---

## 8. Overload / Abuse Scenarios

| Scenario | System Behavior | Safeguard |
|---|---|---|
| **Excessive AI requests** | Rate limit per user + hard credit cap | `throttle:ai` middleware + `CheckAiCredits` |
| **Too many concurrent users** | Queue-based, not denial-based | Backend job queue for heavy AI tasks |
| **Expired customer operating** | Grace → read-only → blocked | Subscription state checked per request |
| **Customer with unpaid invoice** | Warning banner in grace; read-only after 7 days | Subscription lifecycle enforcement |
| **Voucher fraud (bulk guessing)** | Rate limit: 3 attempts/hour, log all attempts | Voucher redemption rate limiter |
| **Staff confirms wrong payment** | Requires confirmer ≠ submitter; audit trail | Two-person rule + audit log |
| **Customer disputes charge** | Admin can reverse payment → subscription adjusts | Manual payment reversal with reason |
| **Data held hostage fear** | Read-only mode allows full export | Export always available until archival |

---

## 9. Revenue Model

> **Assumptions:** Setup fee 500, monthly 250, avg 2 extra users × 30 = 60/mo extra. AI recharge ~1 per quarter. Founding customers at discounted rate for 3 months.

### Revenue Projections (LYD/month at steady state)

| Customers | Setup (one-time) | Monthly Recurring | AI Recharge (est.) | Total Monthly |
|---|---|---|---|---|
| 5 | 2,500 | 1,550 | 50 | **1,600** |
| 10 | 5,000 | 3,100 | 100 | **3,200** |
| 30 | 15,000 | 9,300 | 300 | **9,600** |
| 100 | 50,000 | 31,000 | 1,000 | **32,000** |

### Estimated Operating Cost Categories
| Category | Monthly Est. | Notes |
|---|---|---|
| Server hosting | 50–200 LYD | VPS or managed, depends on provider |
| Database hosting | Included or 50–100 LYD | Often bundled with server |
| AI API costs | 100–500 LYD | Depends on provider, model, token volume |
| Domain + SSL | ~10 LYD | Annual, amortized |
| Email service | 25–50 LYD | For invites, notifications |
| Support staff | Variable | Part-time initially |

> Exact vendor prices must be checked separately. Numbers above are estimates for planning.

### Gross Margin
At 10 customers: ~3,200 LYD revenue − ~500 LYD ops = **~2,700 LYD/month gross (~84%)**  
At 30 customers: ~9,600 LYD revenue − ~800 LYD ops = **~8,800 LYD/month gross (~92%)**

---

## 10. Fast Revenue Strategy

| # | Strategy | Revenue | Timeline |
|---|---|---|---|
| 1 | **Founding Customers Program** — first 10 at discounted rate, free setup | Builds pipeline, testimonials | Month 1–3 |
| 2 | **Setup fee from day 1** (except founding) | 500 LYD × N | Immediate on sign-up |
| 3 | **Direct onboarding** — personally onboard each customer | Ensures retention, reduces churn | Month 1–6 |
| 4 | **Training services** — sell on-site training | 150 LYD/hour | Ongoing |
| 5 | **Annual prepayment discount** — 2 months free | Upfront cash: 2,500 LYD | When offered |
| 6 | **Referral incentive** — 1 month free for referrer | Organic growth | After 10 customers |
| 7 | **Target real businesses** — car dealers, workshops, restaurants with 5+ employees | Higher ARPU, real pain | Always |

### Who NOT to Sell To
- Solo freelancers with no employees (too small, high support cost per LYD)
- Businesses that don't use computers at all (adoption risk)
- Price-only buyers who will churn at first invoice

---

## 11. Backend Data Model

### Already Existing ✅

| Model | Purpose | Key Fields |
|---|---|---|
| `PlatformPlan` | Plan definitions | `name`, `slug`, `max_employees`, `is_active` |
| `PlatformPlanPrice` | Price per billing cycle | `base_price`, `included_employees`, `price_per_employee`, `included_ai_credits`, `currency` |
| `WorkspaceSubscription` | Active subscription | `workspace_id`, `plan_id`, `status`, `current_period_start/end`, `trial_ends_at` |
| `ManualPayment` | Cash/card payment records | `workspace_id`, `amount`, `method`, `status`, `submitted_by`, `confirmed_by` |
| `AiCreditBalance` | Current credit balance | `workspace_id`, `included_credits`, `purchased_credits`, `used_credits`, `hard_limit` |
| `AiCreditTransaction` | Credit usage/purchase log | `workspace_id`, `transaction_type`, `credits`, `balance_after`, `actor_id` |
| `BillingSnapshot` | Period-end billing summary | `workspace_id`, `total_amount`, `ai_credits_used`, `overage_charges` |
| `AiUsageLog` | Per-request AI usage | (tracks each AI API call) |

### New Tables Needed

| Table | Purpose | Key Fields |
|---|---|---|
| `vouchers` | Prepaid recharge codes | `code`, `type`, `value`, `batch_id`, `redeemed_at`, `expires_at`, `is_active` |
| `voucher_redemptions` | Redemption audit trail | `voucher_id`, `workspace_id`, `user_id`, `redeemed_at`, `ip_address` |
| `billing_events` | All billing state changes | `workspace_id`, `event_type`, `old_state`, `new_state`, `actor_id`, `metadata_json` |

Only **3 new tables** needed — the backend already has the heavy billing infrastructure.

---

## 12. Backend API

### Already Existing ✅

| Endpoint | Purpose |
|---|---|
| `GET /admin/plans` | List plans |
| `POST /admin/plans` | Create plan |
| `PUT /admin/plans/{id}` | Update plan |
| `POST /admin/plans/{id}/prices` | Add pricing tier |
| `PUT /admin/workspaces/{id}/subscription` | Update subscription |
| `PUT /admin/workspaces/{id}/trial` | Extend trial |
| `POST /admin/workspaces/{id}/credits` | Adjust AI credits |
| `POST /billing/manual-payment` | Submit manual payment |
| `GET /admin/manual-payments` | List manual payments |
| `POST /admin/manual-payments/{id}/confirm` | Confirm payment |
| `POST /admin/manual-payments/{id}/reject` | Reject payment |
| `GET /admin/workspaces/{id}/payments` | Payment history |
| `GET /admin/high-usage` | AI usage monitoring |

### Proposed (new)

| Endpoint | Purpose |
|---|---|
| `POST /admin/vouchers/generate` | Generate batch of voucher codes |
| `GET /admin/vouchers` | List all vouchers with redemption status |
| `PUT /admin/vouchers/{id}/deactivate` | Kill compromised voucher |
| `POST /vouchers/redeem` | Customer redeems voucher code (workspace-scoped) |
| `GET /billing/status` | Customer-facing billing/subscription status |
| `GET /billing/ai-credits` | Customer-facing AI credit balance |
| `GET /billing/history` | Customer payment/voucher history |

Only **7 new endpoints** — existing SA billing API covers most needs.

---

## 13. Frontend Impact

### Customer-Facing Screens

| Screen | Purpose | Effort |
|---|---|---|
| Billing status card (Settings) | Show plan, period, status, days remaining | S |
| AI credits widget (sidebar/dashboard) | Show remaining credits, recharge link | S |
| Redeem voucher screen | Enter code, see result | S |
| Payment history | List past payments/vouchers | S |
| Read-only mode banner | Full-width warning when in read-only | S |
| Grace period banner | Warning during 7-day grace | XS |

### Super Admin Screens

| Screen | Purpose | Effort |
|---|---|---|
| Manual payment confirmation (exists in SA) | Already built in `SuperAdminPlansScreen` area | — |
| Voucher generator | Generate batch, print codes | M |
| Voucher list + status | View all codes, filter by status | M |
| AI usage dashboard (exists) | Already built in `SuperAdminUsageScreen` | — |

### Total New Frontend Effort: **M** (mostly small components)

---

## 14. Business Rules

| # | Rule |
|---|---|
| 1 | Core ERP (products, invoices, payments, inventory, customers, employees) **continues** if AI credits finish |
| 2 | Expired subscription → 7-day grace (full access + warning) → 30-day read-only → suspended |
| 3 | Data is **never deleted automatically**. Archived after 90 days of cancellation. |
| 4 | Invoices/payments cannot be edited after accounting lock date unless admin override |
| 5 | AI included credits reset monthly for active subscriptions only |
| 6 | Purchased/recharge credits **carry over** while subscription is active |
| 7 | On subscription expiry, purchased credits are frozen, not deleted |
| 8 | Manual payments require two-person confirmation (submitter ≠ confirmer) |
| 9 | Every billing action (payment, voucher, status change, credit adjustment) creates audit log |
| 10 | Voucher codes are one-time use, globally unique, expirable |
| 11 | Customer can always export data in read-only mode |
| 12 | Re-activation is instant upon payment — no re-onboarding required |

---

## 15. Future Online Payments

### Design for Abstraction

```
PaymentProvider (interface)
├── ManualPaymentProvider (current — admin confirmation)
├── VoucherPaymentProvider (current — code redemption)
├── StripeProvider (future — if expanding to Stripe-supported regions)
├── LocalGatewayProvider (future — Libya/regional card processor)
└── BankTransferProvider (future — automated bank reconciliation)
```

### Rules
- `ManualPayment` and `Voucher` flows stay permanently — they serve offline markets
- `payment_method` field on subscription uses enum: `manual`, `voucher`, `stripe`, `local_gateway`
- No Stripe-specific concepts leak into core billing logic
- `WorkspaceSubscription` already has `stripe_*` fields — these remain nullable until needed

---

## 16. Implementation Priority

| # | Item | Phase | Effort | Backend Status |
|---|---|---|---|---|
| 1 | Subscription states + lifecycle enforcement | Billing foundation | M | Models exist, need state machine |
| 2 | Manual payment flow (submit → confirm → extend) | Payment | S | Endpoints + model exist |
| 3 | Voucher generation + redemption | Voucher | M | New table + 4 endpoints |
| 4 | AI credit balance read/check | AI credits | S | Model + endpoint exist |
| 5 | AI usage tracking per action type | AI credits | M | `AiCreditTransaction` exists |
| 6 | Read-only mode enforcement middleware | Access control | M | New middleware |
| 7 | Grace period + warning banners | Frontend | S | New components |
| 8 | SA voucher management screens | Frontend | M | New screens |
| 9 | Customer billing status screens | Frontend | S | New components |
| 10 | Future payment provider abstraction | Future | L | When needed |

---

## 17. Risks

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | **Pricing too low** — attracts wrong customers, thin margins | Revenue | Start at 250 LYD, test market response, adjust |
| 2 | **AI cost overrun** — heavy AI users consume expensive API tokens | Profitability | Hard credit limits, per-user rate limits, monitor usage |
| 3 | **Manual payment mistakes** — wrong amount, wrong workspace | Billing errors | Two-person confirmation, audit trail, reconciliation |
| 4 | **Customers afraid of data loss** — hesitate to subscribe | Adoption | Clear data retention policy, read-only mode, export always available |
| 5 | **Voucher fraud** — leaked codes, batch compromise | Revenue leakage | One-time use, batch deactivation, rate limiting |
| 6 | **Weak audit logs** — disputes without evidence | Legal risk | Log every billing event with actor, timestamp, IP |
| 7 | **Support burden** — manual payment requires human processing | Ops cost | Train staff, standard process, eventually automate |
| 8 | **Wrong customer segment** — selling to tiny shops that can't pay 250/mo | Churn | Target businesses with 5+ employees, real operations |

---

## 18. Final Recommendation

### Starting Price
**250 LYD/month** for up to 5 users, 500 AI credits included. Setup fee 500 LYD. Founding customers: 3 months at 150 LYD, free setup.

### Payment Approach
**Manual (cash/transfer) + voucher codes.** No online payment processor at launch. Admin confirms all payments via Super Admin.

### Build First (Steps 37–39 in roadmap)
1. Subscription state enforcement (grace → read-only logic)
2. Manual payment confirmation flow (mostly exists)
3. Voucher table + generate/redeem endpoints
4. AI credit balance check + enforcement in middleware
5. Customer-facing billing status + grace/read-only banners

### Delay
- Stripe/online payment integration (until market demands it)
- Automated billing invoice generation (manual receipts are fine initially)
- Complex tiered pricing (one plan is enough for launch)

### Roadmap Impact
This strategy **does not change the technical roadmap order.** Steps 38–49 (backend verification → auth → register → CRUD modules) proceed as planned. Billing enforcement is added as middleware alongside read-only mode — it does not block module integration work.

> **Revenue starts the moment the first customer pays the setup fee and subscribes. The billing engine is a revenue accelerator, not a launch blocker.**
