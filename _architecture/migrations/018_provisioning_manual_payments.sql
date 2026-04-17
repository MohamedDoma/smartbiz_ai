-- ============================================================
-- Migration 018: ERP Provisioning + Manual Payments
-- ============================================================

-- ── 1. Provisioning Runs ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS provisioning_runs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id     UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    blueprint_id     UUID NOT NULL REFERENCES discovery_blueprints(id) ON DELETE CASCADE,
    status           VARCHAR(20) NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','applied','rolled_back','failed')),
    config           JSONB NOT NULL DEFAULT '{}',
    applied_by       UUID REFERENCES users(id) ON DELETE SET NULL,
    applied_at       TIMESTAMPTZ,
    version          INTEGER NOT NULL DEFAULT 1,
    rollback_config  JSONB,
    error_message    TEXT,
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_prov_runs_ws ON provisioning_runs(workspace_id);
CREATE INDEX idx_prov_runs_status ON provisioning_runs(status);

-- ── 2. Workspace Configurations ──────────────────────────────
CREATE TABLE IF NOT EXISTS workspace_configurations (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id          UUID NOT NULL UNIQUE REFERENCES workspaces(id) ON DELETE CASCADE,
    enabled_modules       JSONB NOT NULL DEFAULT '[]',
    role_configs          JSONB NOT NULL DEFAULT '{}',
    pages                 JSONB NOT NULL DEFAULT '[]',
    workflows             JSONB NOT NULL DEFAULT '[]',
    automations           JSONB NOT NULL DEFAULT '[]',
    provisioning_run_id   UUID REFERENCES provisioning_runs(id) ON DELETE SET NULL,
    created_at            TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ws_config_ws ON workspace_configurations(workspace_id);

-- ── 3. Manual Payments ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS manual_payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id    UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    amount          NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency        VARCHAR(3) NOT NULL DEFAULT 'usd',
    method          VARCHAR(30) NOT NULL CHECK (method IN ('manual_cash','bank_transfer','cheque','enterprise_manual')),
    reference       VARCHAR(100),
    status          VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','rejected')),
    plan_id         UUID REFERENCES platform_plans(id) ON DELETE SET NULL,
    billing_cycle   VARCHAR(20),
    notes           TEXT,
    submitted_by    UUID REFERENCES users(id) ON DELETE SET NULL,
    confirmed_by    UUID REFERENCES users(id) ON DELETE SET NULL,
    confirmed_at    TIMESTAMPTZ,
    rejected_reason TEXT,
    created_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_manual_pay_ws ON manual_payments(workspace_id);
CREATE INDEX idx_manual_pay_status ON manual_payments(status);
