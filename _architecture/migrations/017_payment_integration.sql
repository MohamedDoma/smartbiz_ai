-- ============================================================
-- Migration 017: Payment Integration
-- ============================================================
-- Adds: payment_transactions, webhook_events
-- Alters: workspace_subscriptions (stripe columns)
-- ============================================================

-- ── 1. ALTER workspace_subscriptions ──────────────────────────
ALTER TABLE workspace_subscriptions ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(50);
ALTER TABLE workspace_subscriptions ADD COLUMN IF NOT EXISTS stripe_subscription_id VARCHAR(50);
ALTER TABLE workspace_subscriptions ADD COLUMN IF NOT EXISTS stripe_price_id VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_ws_sub_stripe_cust ON workspace_subscriptions(stripe_customer_id);
CREATE INDEX IF NOT EXISTS idx_ws_sub_stripe_sub ON workspace_subscriptions(stripe_subscription_id);

-- ── 2. Payment Transactions ──────────────────────────────────
CREATE TABLE IF NOT EXISTS payment_transactions (
    id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id               UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    stripe_payment_intent_id   VARCHAR(100) UNIQUE,
    stripe_invoice_id          VARCHAR(100),
    type                       VARCHAR(30) NOT NULL CHECK (type IN ('subscription','credit_purchase','one_time')),
    amount                     NUMERIC(15,2) NOT NULL DEFAULT 0,
    currency                   VARCHAR(3) NOT NULL DEFAULT 'usd',
    status                     VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('succeeded','failed','pending','refunded')),
    description                TEXT,
    metadata                   JSONB,
    created_at                 TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_payment_tx_ws ON payment_transactions(workspace_id);
CREATE INDEX idx_payment_tx_status ON payment_transactions(status);
CREATE INDEX idx_payment_tx_stripe ON payment_transactions(stripe_payment_intent_id);
CREATE INDEX idx_payment_tx_created ON payment_transactions(created_at);

-- ── 3. Webhook Events ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS webhook_events (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stripe_event_id  VARCHAR(100) NOT NULL UNIQUE,
    event_type       VARCHAR(100) NOT NULL,
    payload          JSONB NOT NULL,
    status           VARCHAR(20) NOT NULL DEFAULT 'received' CHECK (status IN ('received','processed','failed')),
    processed_at     TIMESTAMPTZ,
    error_message    TEXT,
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_webhook_events_stripe ON webhook_events(stripe_event_id);
CREATE INDEX idx_webhook_events_type ON webhook_events(event_type);
CREATE INDEX idx_webhook_events_status ON webhook_events(status);
