-- ============================================================
-- Migration 016: Platform Control + AI Billing + Super Admin
-- ============================================================
-- Adds: platform_settings, platform_plans, platform_plan_prices,
--        plan_features, workspace_subscriptions, ai_credit_balances,
--        ai_credit_transactions, ai_usage_logs, workspace_feature_flags,
--        billing_snapshots
-- Alters: users (add is_super_admin)
-- No RLS — super-admin reads across all workspaces.
-- ============================================================

BEGIN;

-- ── 1. Platform Settings ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS platform_settings (
    key          VARCHAR(100) PRIMARY KEY,
    value        TEXT NOT NULL,
    description  TEXT,
    updated_by   UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at   TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ── 2. Platform Plans ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS platform_plans (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name           VARCHAR(100) NOT NULL,
    slug           VARCHAR(100) NOT NULL UNIQUE,
    description    TEXT,
    max_employees  INTEGER NOT NULL DEFAULT 5,
    max_workspaces INTEGER NOT NULL DEFAULT 1,
    is_active      BOOLEAN NOT NULL DEFAULT true,
    sort_order     INTEGER NOT NULL DEFAULT 0,
    created_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_platform_plans_slug ON platform_plans(slug);
CREATE INDEX idx_platform_plans_active ON platform_plans(is_active);

-- ── 3. Platform Plan Prices ────────────────────────────────────
CREATE TABLE IF NOT EXISTS platform_plan_prices (
    id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id                     UUID NOT NULL REFERENCES platform_plans(id) ON DELETE CASCADE,
    billing_cycle               VARCHAR(20) NOT NULL CHECK (billing_cycle IN ('monthly','quarterly','semi_annual','annual','multi_year','custom')),
    base_price                  NUMERIC(15,2) NOT NULL DEFAULT 0,
    included_employees          INTEGER NOT NULL DEFAULT 1,
    price_per_employee          NUMERIC(10,2) NOT NULL DEFAULT 0,
    included_ai_credits         INTEGER NOT NULL DEFAULT 0,
    ai_overage_price_per_credit NUMERIC(10,4) NOT NULL DEFAULT 0,
    currency                    VARCHAR(3) NOT NULL DEFAULT 'USD',
    is_active                   BOOLEAN NOT NULL DEFAULT true,
    effective_from              DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_until             DATE,
    created_at                  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at                  TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(plan_id, billing_cycle, currency, effective_from)
);

CREATE INDEX idx_plan_prices_plan ON platform_plan_prices(plan_id);
CREATE INDEX idx_plan_prices_active ON platform_plan_prices(is_active);

-- ── 4. Plan Features ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS plan_features (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id     UUID NOT NULL REFERENCES platform_plans(id) ON DELETE CASCADE,
    feature_key VARCHAR(100) NOT NULL,
    is_enabled  BOOLEAN NOT NULL DEFAULT true,
    UNIQUE(plan_id, feature_key)
);

CREATE INDEX idx_plan_features_plan ON plan_features(plan_id);

-- ── 5. Workspace Subscriptions ────────────────────────────────
CREATE TABLE IF NOT EXISTS workspace_subscriptions (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id               UUID NOT NULL UNIQUE REFERENCES workspaces(id) ON DELETE CASCADE,
    plan_id                    UUID NOT NULL REFERENCES platform_plans(id),
    plan_price_id              UUID NOT NULL REFERENCES platform_plan_prices(id),
    status                     VARCHAR(20) NOT NULL DEFAULT 'trial' CHECK (status IN ('active','trial','past_due','suspended','cancelled')),
    billing_cycle              VARCHAR(20) NOT NULL,
    current_period_start       TIMESTAMPTZ NOT NULL,
    current_period_end         TIMESTAMPTZ NOT NULL,
    trial_ends_at              TIMESTAMPTZ,
    included_employees         INTEGER NOT NULL DEFAULT 1,
    current_employee_count     INTEGER NOT NULL DEFAULT 0,
    billable_employee_count    INTEGER NOT NULL DEFAULT 0,
    overage_employee_count     INTEGER NOT NULL DEFAULT 0,
    price_per_extra_employee   NUMERIC(10,2) NOT NULL DEFAULT 0,
    cancelled_at               TIMESTAMPTZ,
    created_at                 TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at                 TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ws_subscriptions_workspace ON workspace_subscriptions(workspace_id);
CREATE INDEX idx_ws_subscriptions_plan ON workspace_subscriptions(plan_id);
CREATE INDEX idx_ws_subscriptions_status ON workspace_subscriptions(status);

-- ── 6. AI Credit Balances ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_credit_balances (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id        UUID NOT NULL UNIQUE REFERENCES workspaces(id) ON DELETE CASCADE,
    included_credits    INTEGER NOT NULL DEFAULT 0,
    purchased_credits   INTEGER NOT NULL DEFAULT 0,
    bonus_credits       INTEGER NOT NULL DEFAULT 0,
    trial_credits       INTEGER NOT NULL DEFAULT 0,
    used_credits        INTEGER NOT NULL DEFAULT 0,
    hard_limit          BOOLEAN NOT NULL DEFAULT false,
    soft_limit_threshold INTEGER NOT NULL DEFAULT 0,
    period_start        TIMESTAMPTZ NOT NULL,
    period_end          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_credit_balances_ws ON ai_credit_balances(workspace_id);

-- ── 7. AI Credit Transactions ─────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_credit_transactions (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    transaction_type  VARCHAR(30) NOT NULL CHECK (transaction_type IN ('usage','purchase','refund','monthly_reset','admin_adjustment','bonus','trial_grant')),
    bucket            VARCHAR(20) NOT NULL CHECK (bucket IN ('included','purchased','bonus','trial')),
    credits           INTEGER NOT NULL,
    balance_after     INTEGER NOT NULL,
    description       TEXT,
    reference_type    VARCHAR(50),
    reference_id      UUID,
    actor_id          UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_credit_tx_ws ON ai_credit_transactions(workspace_id);
CREATE INDEX idx_ai_credit_tx_type ON ai_credit_transactions(transaction_type);
CREATE INDEX idx_ai_credit_tx_created ON ai_credit_transactions(created_at);

-- ── 8. AI Usage Logs ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_usage_logs (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id      UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action_type       VARCHAR(50) NOT NULL,
    credits_charged   INTEGER NOT NULL DEFAULT 0,
    request_metadata  JSONB,
    response_metadata JSONB,
    duration_ms       INTEGER,
    created_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ai_usage_ws ON ai_usage_logs(workspace_id);
CREATE INDEX idx_ai_usage_action ON ai_usage_logs(action_type);
CREATE INDEX idx_ai_usage_created ON ai_usage_logs(created_at);

-- ── 9. Workspace Feature Flags ────────────────────────────────
CREATE TABLE IF NOT EXISTS workspace_feature_flags (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    feature_key     VARCHAR(100) NOT NULL,
    is_enabled      BOOLEAN NOT NULL DEFAULT true,
    override_reason TEXT,
    set_by          UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workspace_id, feature_key)
);

CREATE INDEX idx_ws_feature_flags ON workspace_feature_flags(workspace_id);

-- ── 10. Billing Snapshots ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS billing_snapshots (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id            UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    period_start            TIMESTAMPTZ NOT NULL,
    period_end              TIMESTAMPTZ NOT NULL,
    plan_name               VARCHAR(100) NOT NULL,
    billing_cycle           VARCHAR(20) NOT NULL,
    base_price              NUMERIC(15,2) NOT NULL DEFAULT 0,
    employee_count          INTEGER NOT NULL DEFAULT 0,
    included_employees      INTEGER NOT NULL DEFAULT 0,
    overage_employees       INTEGER NOT NULL DEFAULT 0,
    employee_overage_charge NUMERIC(15,2) NOT NULL DEFAULT 0,
    ai_credits_included     INTEGER NOT NULL DEFAULT 0,
    ai_credits_used         INTEGER NOT NULL DEFAULT 0,
    ai_credits_overage      INTEGER NOT NULL DEFAULT 0,
    ai_overage_charge       NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_amount            NUMERIC(15,2) NOT NULL DEFAULT 0,
    status                  VARCHAR(20) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','finalized','paid','void')),
    created_at              TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_billing_snapshots_ws ON billing_snapshots(workspace_id);
CREATE INDEX idx_billing_snapshots_period ON billing_snapshots(period_start, period_end);
CREATE INDEX idx_billing_snapshots_status ON billing_snapshots(status);

-- ── 11. ALTER users — add super admin flag ────────────────────
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- ── Updated-at triggers ───────────────────────────────────────
CREATE TRIGGER trg_platform_plans_updated BEFORE UPDATE ON platform_plans FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_plan_prices_updated BEFORE UPDATE ON platform_plan_prices FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_ws_subscriptions_updated BEFORE UPDATE ON workspace_subscriptions FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_ai_credit_balances_updated BEFORE UPDATE ON ai_credit_balances FOR EACH ROW EXECUTE FUNCTION update_timestamp();
CREATE TRIGGER trg_ws_feature_flags_updated BEFORE UPDATE ON workspace_feature_flags FOR EACH ROW EXECUTE FUNCTION update_timestamp();

COMMIT;
