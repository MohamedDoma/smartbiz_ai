-- ==========================================
-- SmartBiz AI — Migration 001: Additive Foundation
-- Batch A from SQL Patch Execution Pack
-- ==========================================
--
-- Purpose:
--   Create standalone new tables with zero dependency on refactored entities.
--   Enrich existing org-structure tables (departments, shifts, branches).
--   Add audit enrichment columns.
--
-- Prerequisites: Base schema (1_database_schema.sql) must be applied.
-- Risk: LOW — pure additive, zero existing data affected.
--
-- Platform role persistence note:
--   Platform roles are enforced via platform_users.role CHECK enum.
--   The 33 platform permission keys are resolved at the application layer.
--   No schema change needed in Batch A for platform role persistence.
--
-- ==========================================


-- ==========================================
-- SECTION 1: Platform Billing Tables (NOT workspace-scoped)
-- ==========================================

-- Subscription plan catalogue (managed by platform admins)
CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL UNIQUE,
    tier VARCHAR(50) NOT NULL CHECK (tier IN ('freemium', 'starter', 'professional', 'enterprise')),
    price_monthly DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (price_monthly >= 0),
    price_annual DECIMAL(10, 2) NOT NULL DEFAULT 0.00 CHECK (price_annual >= 0),
    max_users INT CHECK (max_users IS NULL OR max_users > 0), -- NULL = unlimited
    max_ai_requests_daily INT CHECK (max_ai_requests_daily IS NULL OR max_ai_requests_daily > 0), -- NULL = unlimited
    features_enabled JSONB NOT NULL DEFAULT '{}'::jsonb, -- { "module_crm": true, "module_manufacturing": true, ... }
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE subscription_plans IS 'Platform-scoped catalogue of subscription tiers and their feature entitlements.';
COMMENT ON COLUMN subscription_plans.features_enabled IS 'JSON map of feature flags and module entitlements included with this plan.';

-- Workspace subscription binding.
-- Design: one row per workspace (UNIQUE on workspace_id). Plan changes UPDATE this row;
-- subscription history is tracked via billing_invoices + audit_logs, not via multiple rows.
CREATE TABLE workspace_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES subscription_plans(id) ON DELETE RESTRICT,
    status VARCHAR(50) NOT NULL DEFAULT 'trial' CHECK (status IN ('trial', 'active', 'past_due', 'suspended', 'cancelled')),
    current_period_start DATE,
    current_period_end DATE,
    trial_ends_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    -- Per-workspace overrides (NULL = use plan defaults)
    max_users_override INT CHECK (max_users_override IS NULL OR max_users_override > 0),
    max_ai_requests_override INT CHECK (max_ai_requests_override IS NULL OR max_ai_requests_override > 0),
    features_override JSONB, -- Additional feature flags beyond plan defaults
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id),
    CHECK (current_period_end IS NULL OR current_period_start IS NULL OR current_period_end > current_period_start)
);

COMMENT ON TABLE workspace_subscriptions IS 'Binds each workspace to exactly one subscription plan. Plan changes UPDATE this row; history is tracked via billing_invoices and audit_logs.';

-- Platform billing invoices (subscription charges to workspaces)
CREATE TABLE billing_invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    subscription_id UUID NOT NULL REFERENCES workspace_subscriptions(id) ON DELETE CASCADE,
    invoice_number VARCHAR(50),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount >= 0),
    currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'issued', 'paid', 'overdue', 'void')),
    issued_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(invoice_number),
    CHECK (period_end > period_start)
);

COMMENT ON TABLE billing_invoices IS 'Platform-generated billing invoices for workspace subscription charges.';

-- Platform billing payments (payments against billing invoices)
CREATE TABLE billing_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    billing_invoice_id UUID NOT NULL REFERENCES billing_invoices(id) ON DELETE CASCADE,
    amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    method VARCHAR(50) NOT NULL CHECK (method IN ('card', 'bank_transfer', 'paypal', 'wire', 'manual')),
    reference VARCHAR(255),
    paid_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE billing_payments IS 'Individual payment records against platform billing invoices. Carries workspace_id for direct tenant isolation.';


-- ==========================================
-- SECTION 2: Async Jobs (workspace-scoped, nullable for platform jobs)
-- ==========================================

CREATE TABLE async_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID REFERENCES workspaces(id) ON DELETE CASCADE, -- NULL for platform-level jobs
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    job_type VARCHAR(100) NOT NULL, -- e.g. 'report_export', 'payroll_calculation', 'bulk_import'
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled')),
    progress_pct INT NOT NULL DEFAULT 0 CHECK (progress_pct >= 0 AND progress_pct <= 100),
    result_url TEXT, -- URL or path to result artifact (e.g. exported CSV)
    error TEXT,
    metadata JSONB, -- Job-specific parameters (report config, import options, etc.)
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

COMMENT ON TABLE async_jobs IS 'Tracks long-running asynchronous operations (report exports, bulk imports, payroll calculations). Platform-level jobs (workspace_id IS NULL) are invisible to workspace RLS sessions.';


-- ==========================================
-- SECTION 3: Idempotency Keys (workspace-scoped)
-- ==========================================

CREATE TABLE idempotency_keys (
    key VARCHAR(255) NOT NULL,
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    response_status INT, -- HTTP status code of original response
    response_body JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (CURRENT_TIMESTAMP + INTERVAL '24 hours'),
    PRIMARY KEY (workspace_id, key)
);

COMMENT ON TABLE idempotency_keys IS 'Stores idempotency key → response mappings to ensure financial write operations are safe to retry.';
COMMENT ON COLUMN idempotency_keys.expires_at IS 'Keys expire after 24 hours by default; cleanup via scheduled job.';


-- ==========================================
-- SECTION 4: Org Structure Enrichment (ALTER existing tables)
-- ==========================================

-- 4a. departments: add hierarchy support + metadata
ALTER TABLE departments
    ADD COLUMN IF NOT EXISTS parent_department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

COMMENT ON COLUMN departments.parent_department_id IS 'Self-referencing FK for department hierarchy (NULL = top-level).';

-- 4b. shifts: add overnight flag, active flag, updated_at
ALTER TABLE shifts
    ADD COLUMN IF NOT EXISTS is_overnight BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

COMMENT ON COLUMN shifts.is_overnight IS 'TRUE when shift crosses midnight (e.g. 22:00–06:00).';

-- 4c. branches: add phone
ALTER TABLE branches
    ADD COLUMN IF NOT EXISTS phone VARCHAR(50);


-- ==========================================
-- SECTION 5: Audit Log Enrichment (ALTER existing table)
-- ==========================================

ALTER TABLE audit_logs
    ADD COLUMN IF NOT EXISTS ip_address INET,
    ADD COLUMN IF NOT EXISTS user_agent TEXT;

COMMENT ON COLUMN audit_logs.ip_address IS 'Client IP address at time of action (for security auditing).';
COMMENT ON COLUMN audit_logs.user_agent IS 'Client user-agent string at time of action.';


-- ==========================================
-- SECTION 6: updated_at Triggers
-- ==========================================
-- Reuses the existing update_timestamp() function from the base schema.

-- New tables with updated_at
CREATE TRIGGER trg_subscription_plans_updated
    BEFORE UPDATE ON subscription_plans
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_workspace_subscriptions_updated
    BEFORE UPDATE ON workspace_subscriptions
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_billing_invoices_updated
    BEFORE UPDATE ON billing_invoices
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- Altered tables that now have updated_at
CREATE TRIGGER trg_departments_updated
    BEFORE UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_shifts_updated
    BEFORE UPDATE ON shifts
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 7: Indexes
-- ==========================================

-- Subscription plans (platform-scoped — no workspace_id index needed)
CREATE INDEX idx_subscription_plans_tier ON subscription_plans(tier);
CREATE INDEX idx_subscription_plans_active ON subscription_plans(is_active) WHERE is_active = TRUE;

-- Workspace subscriptions
CREATE INDEX idx_workspace_subscriptions_workspace ON workspace_subscriptions(workspace_id);
CREATE INDEX idx_workspace_subscriptions_plan ON workspace_subscriptions(plan_id);
CREATE INDEX idx_workspace_subscriptions_status ON workspace_subscriptions(status);

-- Billing invoices
CREATE INDEX idx_billing_invoices_workspace ON billing_invoices(workspace_id);
CREATE INDEX idx_billing_invoices_subscription ON billing_invoices(subscription_id);
CREATE INDEX idx_billing_invoices_status ON billing_invoices(status);
CREATE INDEX idx_billing_invoices_period ON billing_invoices(period_start, period_end);

-- Billing payments
CREATE INDEX idx_billing_payments_workspace ON billing_payments(workspace_id);
CREATE INDEX idx_billing_payments_invoice ON billing_payments(billing_invoice_id);
CREATE INDEX idx_billing_payments_paid_at ON billing_payments(paid_at);

-- Async jobs
CREATE INDEX idx_async_jobs_workspace ON async_jobs(workspace_id);
CREATE INDEX idx_async_jobs_user ON async_jobs(user_id);
CREATE INDEX idx_async_jobs_status ON async_jobs(status);
CREATE INDEX idx_async_jobs_type ON async_jobs(job_type);
CREATE INDEX idx_async_jobs_created ON async_jobs(created_at);

-- Idempotency keys (PK already covers workspace_id + key)
CREATE INDEX idx_idempotency_keys_expires ON idempotency_keys(expires_at);

-- Department hierarchy
CREATE INDEX idx_departments_parent ON departments(parent_department_id);

-- Audit log enrichment
CREATE INDEX idx_audit_logs_ip ON audit_logs(ip_address) WHERE ip_address IS NOT NULL;


-- ==========================================
-- SECTION 8: Composite Unique Constraints (for workspace isolation FK validation)
-- ==========================================
-- Required for validate_workspace_fk() trigger pattern on child tables.
-- subscription_plans is platform-scoped — no workspace composite needed; PK is sufficient.

ALTER TABLE workspace_subscriptions ADD CONSTRAINT uq_workspace_subs_ws_id UNIQUE (workspace_id, id);
ALTER TABLE billing_invoices ADD CONSTRAINT uq_billing_invoices_ws_id UNIQUE (workspace_id, id);
ALTER TABLE billing_payments ADD CONSTRAINT uq_billing_payments_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 9: Workspace FK Isolation Triggers
-- ==========================================
-- Ensures child records cannot cross workspace boundaries.
-- Uses the existing validate_workspace_fk() function from the base schema.
-- workspace_subscriptions has no workspace-scoped FKs to validate (plan_id is platform-scoped) — no trigger needed.

CREATE TRIGGER trg_billing_invoices_ws_check
    BEFORE INSERT OR UPDATE ON billing_invoices
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('subscription_id:workspace_subscriptions');

CREATE TRIGGER trg_billing_payments_ws_check
    BEFORE INSERT OR UPDATE ON billing_payments
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('billing_invoice_id:billing_invoices');

CREATE TRIGGER trg_async_jobs_ws_check
    BEFORE INSERT OR UPDATE ON async_jobs
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users');

CREATE TRIGGER trg_idempotency_keys_ws_check
    BEFORE INSERT OR UPDATE ON idempotency_keys
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk('user_id:users');


-- ==========================================
-- SECTION 10: Row Level Security (RLS)
-- ==========================================

-- workspace_subscriptions: workspace-scoped
ALTER TABLE workspace_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_workspace_subscriptions ON workspace_subscriptions
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- billing_invoices: workspace-scoped
ALTER TABLE billing_invoices ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_billing_invoices ON billing_invoices
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- billing_payments: workspace-scoped (workspace_id added for direct tenant isolation)
ALTER TABLE billing_payments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_billing_payments ON billing_payments
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- async_jobs: workspace-scoped.
-- Platform-level jobs (workspace_id IS NULL) are EXCLUDED from workspace RLS sessions.
-- Platform admins access them via a separate connection that bypasses RLS or uses a platform policy.
ALTER TABLE async_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_async_jobs ON async_jobs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- idempotency_keys: workspace-scoped
ALTER TABLE idempotency_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_idempotency_keys ON idempotency_keys
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- subscription_plans: platform-scoped (readable by all, writable by platform admins only)
-- No RLS needed — platform tables are not workspace-isolated.
-- Access control is enforced at the application layer via platform middleware.


-- ==========================================
-- SECTION 11: Backfill defaults for altered columns
-- ==========================================
-- Ensures existing rows have sensible values for new columns.

-- departments.updated_at: backfill from created_at
UPDATE departments SET updated_at = created_at WHERE updated_at IS NULL;

-- shifts.updated_at: backfill from created_at
UPDATE shifts SET updated_at = created_at WHERE updated_at IS NULL;

-- shifts.is_overnight: detect from time range
UPDATE shifts SET is_overnight = (end_time < start_time) WHERE is_overnight IS NULL;

-- shifts.is_active: default all existing shifts to active
UPDATE shifts SET is_active = TRUE WHERE is_active IS NULL;


-- ==========================================
-- END OF MIGRATION 001
-- ==========================================
-- Validation checklist:
--   [ ] subscription_plans table exists with CHECK constraints
--   [ ] workspace_subscriptions table exists with UNIQUE(workspace_id)
--   [ ] billing_invoices table exists with period CHECK
--   [ ] billing_payments table exists with workspace_id
--   [ ] async_jobs table exists with status CHECK
--   [ ] idempotency_keys table exists with PK(workspace_id, key)
--   [ ] departments has parent_department_id, description, updated_at
--   [ ] shifts has is_overnight, is_active, updated_at
--   [ ] branches has phone
--   [ ] audit_logs has ip_address, user_agent
--   [ ] All new updated_at triggers fire correctly
--   [ ] All new indexes exist
--   [ ] RLS enabled on workspace_subscriptions, billing_invoices, billing_payments, async_jobs, idempotency_keys
--   [ ] async_jobs RLS excludes workspace_id IS NULL rows from workspace sessions
--   [ ] Workspace FK isolation triggers active
--   [ ] Existing data not affected (pure additive)
-- ==========================================
