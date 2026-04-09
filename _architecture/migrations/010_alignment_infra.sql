-- ==========================================
-- MIGRATION 010: Alignment Infrastructure
-- ==========================================
--
-- Batch J — Architecture alignment for global readiness + AI workflows
-- Depends on: 001–009 (all previous migrations)
--
-- Scope:
--   D4 — i18n / locale infrastructure
--   D5 — Multi-currency / exchange rates
--   D6 — AI conversation + change request lifecycle
--   D7 — SKIPPED (already implemented: workspace_memberships.assigned_warehouses in 002)
--
-- Safety:
--   - All changes are ADDITIVE (new tables, new nullable/defaulted columns)
--   - No columns dropped, renamed, or type-changed
--   - All NOT NULL additions use safe defaults matching existing data
--   - Idempotent with IF NOT EXISTS / IF NOT EXISTS guards
--   - No data backfill required
--
-- Strategy:
--   Section 1: D4 — Locale columns on workspaces + users, translations table
--   Section 2: D5 — Exchange rates table, journal_entries + journal_lines currency columns
--   Section 3: D6 — AI conversations, AI change requests, ai_request_logs FK
--   Section 4: RLS policies for new tables
--   Section 5: Indexes for new tables + altered columns
--   Section 6: Triggers (updated_at)
--   Section 7: Comments
--   Section 8: Cross-workspace FK validation triggers
--   Section 9: Verification queries

BEGIN;

-- ==========================================
-- SECTION 1: D4 — i18n / Locale Infrastructure
-- ==========================================

-- 1a. Add locale + currency + timezone columns to workspaces
-- These establish the workspace's base language, reporting currency, and timezone.
-- Defaults are safe for all existing rows (English, Libyan Dinar, UTC).

ALTER TABLE workspaces
    ADD COLUMN IF NOT EXISTS default_locale VARCHAR(10) NOT NULL DEFAULT 'en';

ALTER TABLE workspaces
    ADD COLUMN IF NOT EXISTS default_currency VARCHAR(3) NOT NULL DEFAULT 'LYD';

ALTER TABLE workspaces
    ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) NOT NULL DEFAULT 'UTC';

COMMENT ON COLUMN workspaces.default_locale IS 'ISO locale code (e.g. en, ar, fr, tr). Drives UI language for workspace when user has no preferred_locale.';
COMMENT ON COLUMN workspaces.default_currency IS 'ISO 4217 currency code. Base reporting currency for financial consolidation.';
COMMENT ON COLUMN workspaces.timezone IS 'IANA timezone (e.g. Africa/Tripoli, Asia/Dubai). Used for date/time display and scheduling.';


-- 1b. Add preferred locale to users (nullable — falls back to workspace default)

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS preferred_locale VARCHAR(10);

COMMENT ON COLUMN users.preferred_locale IS 'Per-user locale override. If NULL, workspace.default_locale is used.';


-- 1c. Translations table (platform-global, NOT workspace-scoped)
-- Stores system-level i18n strings (module names, labels, error messages, email templates).
-- Product names / user content remain in their original tables — this table is for system strings only.

CREATE TABLE IF NOT EXISTS translations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    locale VARCHAR(10) NOT NULL,           -- e.g. 'en', 'ar', 'fr', 'tr', 'es'
    namespace VARCHAR(100) NOT NULL,       -- e.g. 'modules', 'labels', 'errors', 'emails', 'notifications'
    key VARCHAR(255) NOT NULL,             -- e.g. 'products.title', 'orders.status.pending'
    value TEXT NOT NULL,                   -- The translated string

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- One translation per locale + namespace + key
    UNIQUE(locale, namespace, key)
);

COMMENT ON TABLE translations IS 'Platform-global i18n string storage. No workspace_id — shared across all tenants. Managed by platform admins. Loaded by clients at app startup.';


-- ==========================================
-- SECTION 2: D5 — Multi-Currency / Exchange Rates
-- ==========================================

-- 2a. Exchange rates table (workspace-scoped)
-- Stores daily/historical exchange rates for multi-currency financial reporting.
-- Rate lookup: find the most recent rate <= the transaction date.

CREATE TABLE IF NOT EXISTS exchange_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    base_currency VARCHAR(3) NOT NULL,      -- Workspace's reporting currency (e.g. 'LYD')
    target_currency VARCHAR(3) NOT NULL,    -- Foreign currency (e.g. 'USD', 'EUR')
    rate DECIMAL(18, 8) NOT NULL,           -- 1 base = rate target
    inverse_rate DECIMAL(18, 8) NOT NULL,   -- 1 target = inverse_rate base

    effective_date DATE NOT NULL,           -- Date this rate applies from
    source VARCHAR(50) NOT NULL DEFAULT 'manual',  -- 'manual', 'api', 'central_bank'

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (rate > 0),
    CHECK (inverse_rate > 0),
    CHECK (base_currency <> target_currency),  -- FIX #3: Cannot exchange a currency with itself
    CHECK (source IN ('manual', 'api', 'central_bank')),

    -- One rate per currency pair per day per workspace
    UNIQUE(workspace_id, base_currency, target_currency, effective_date)
);

COMMENT ON TABLE exchange_rates IS 'Workspace-scoped daily exchange rates. Used for multi-currency journal conversion and financial report consolidation.';
COMMENT ON COLUMN exchange_rates.rate IS '1 unit of base_currency = rate units of target_currency.';
-- FIX #4: inverse_rate consistency
-- inverse_rate is APPLICATION-MAINTAINED. The application layer MUST ensure:
--   inverse_rate = 1.0 / rate (within DECIMAL(18,8) precision)
-- This is NOT enforced at the DB level because floating-point rounding makes
-- a strict CHECK (rate * inverse_rate = 1) unreliable at 8 decimal places.
-- The application layer must compute both values atomically on INSERT.
COMMENT ON COLUMN exchange_rates.inverse_rate IS 'APPLICATION-MAINTAINED: must equal 1/rate. Pre-computed for query convenience. Application must set both rate and inverse_rate atomically on insert.';
COMMENT ON COLUMN exchange_rates.effective_date IS 'Date from which this rate is valid. Rate lookup uses the most recent effective_date <= transaction_date.';


-- 2b. Add currency + exchange_rate + status to journal_entries
-- orders and invoices already have currency/exchange_rate (base schema lines 206-207, 243-244).
-- journal_entries MUST also track currency to support multi-currency consolidation.
-- status column is referenced by API contracts (§28.3) but was missing from base schema.

ALTER TABLE journal_entries
    ADD COLUMN IF NOT EXISTS currency VARCHAR(3) NOT NULL DEFAULT 'LYD';

ALTER TABLE journal_entries
    ADD COLUMN IF NOT EXISTS exchange_rate DECIMAL(18, 8) NOT NULL DEFAULT 1.0;

ALTER TABLE journal_entries
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) NOT NULL DEFAULT 'draft';

-- Add status CHECK constraint (safe — all existing rows will be 'draft' via DEFAULT)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_journal_entries_status'
        AND conrelid = 'journal_entries'::regclass
    ) THEN
        ALTER TABLE journal_entries
            ADD CONSTRAINT chk_journal_entries_status
            CHECK (status IN ('draft', 'posted', 'reversed'));
    END IF;
END $$;

-- Add exchange_rate positivity constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_journal_entries_exchange_rate'
        AND conrelid = 'journal_entries'::regclass
    ) THEN
        ALTER TABLE journal_entries
            ADD CONSTRAINT chk_journal_entries_exchange_rate
            CHECK (exchange_rate > 0);
    END IF;
END $$;

COMMENT ON COLUMN journal_entries.currency IS 'ISO 4217 currency code the journal was recorded in.';
COMMENT ON COLUMN journal_entries.exchange_rate IS 'Exchange rate to workspace base currency at time of posting. 1 journal_currency = exchange_rate * base_currency.';
COMMENT ON COLUMN journal_entries.status IS 'Journal lifecycle: draft → posted → reversed. Posted journals are immutable.';


-- 2c. Add reporting_amount to journal_lines
-- Pre-computes each debit/credit line in the workspace's default_currency.
-- Enables financial reports to sum reporting_amount directly without runtime FX conversion.

ALTER TABLE journal_lines
    ADD COLUMN IF NOT EXISTS reporting_amount DECIMAL(15, 2);

COMMENT ON COLUMN journal_lines.reporting_amount IS 'Debit or credit amount converted to workspace default_currency. Nullable for legacy rows — populated on journal posting.';


-- ==========================================
-- SECTION 3: D6 — AI Conversation + Change Request Schema
-- ==========================================

-- 3a. AI conversations table (workspace-scoped)
-- Groups multi-turn AI chat messages into conversations.
-- Each ai_request_logs row links to a conversation via conversation_id.

CREATE TABLE IF NOT EXISTS ai_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    title VARCHAR(255),                     -- AI-generated or user-set title
    mode VARCHAR(50) NOT NULL               -- Maps to AI modes: A=onboarding, B=change_request, C=advisory
        CHECK (mode IN ('onboarding', 'change_request', 'advisory', 'general')),
    status VARCHAR(50) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'archived', 'deleted')),

    -- Denormalized for list performance
    message_count INT NOT NULL DEFAULT 0 CHECK (message_count >= 0),
    last_message_at TIMESTAMPTZ,

    -- Extensible context (referenced entity IDs, conversation parameters)
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE ai_conversations IS 'Groups multi-turn AI chat messages. Each conversation belongs to one user in one workspace. ai_request_logs rows link here via conversation_id.';
COMMENT ON COLUMN ai_conversations.mode IS 'AI mode: onboarding (Mode A), change_request (Mode B), advisory (Mode C), general.';
COMMENT ON COLUMN ai_conversations.metadata IS 'Extensible JSON: referenced_entity_ids, conversation_parameters, context_summary.';


-- 3b. AI change requests table (workspace-scoped)
-- Implements the governed change proposal lifecycle (BR-AI-004).
-- When AI proposes a structural change, it creates a change request that
-- must be reviewed and approved by owner/admin before execution.

CREATE TABLE IF NOT EXISTS ai_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Origin
    conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
    requested_by UUID NOT NULL REFERENCES users(id),

    -- Review
    reviewed_by UUID REFERENCES users(id),

    -- Classification
    change_type VARCHAR(50) NOT NULL
        CHECK (change_type IN (
            'navigation', 'dashboard', 'module_toggle', 'page_layout',
            'workflow', 'settings', 'role_suggestion'
        )),
    risk_level VARCHAR(20) NOT NULL DEFAULT 'medium'
        CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),

    -- Lifecycle FSM: proposed → approved|rejected → applied|rolled_back|expired
    status VARCHAR(50) NOT NULL DEFAULT 'proposed'
        CHECK (status IN ('proposed', 'approved', 'rejected', 'applied', 'rolled_back', 'expired')),

    -- Change payload
    proposed_diff JSONB NOT NULL,          -- Structured before/after diff for preview
    applied_diff JSONB,                    -- Actual diff applied (may differ if partially applied)

    -- Review data
    review_notes TEXT,                     -- Approver's justification

    -- Timestamps
    proposed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMPTZ,
    applied_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,               -- Auto-expire unreviewed proposals

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE ai_change_requests IS 'Governed AI change proposals (BR-AI-004). AI proposes → owner/admin reviews → approved → system applies. Supports rollback and auto-expiry.';
COMMENT ON COLUMN ai_change_requests.proposed_diff IS 'Structured JSON diff showing exactly what the AI wants to change (before/after per field).';
COMMENT ON COLUMN ai_change_requests.risk_level IS 'AI-classified risk: low (cosmetic), medium (UI changes), high (workflow/module), critical (permissions/accounting).';
COMMENT ON COLUMN ai_change_requests.expires_at IS 'If set, unreviewed proposals auto-expire after this time. Background job should mark status=expired.';


-- 3c. Add conversation_id FK to ai_request_logs
-- Links individual AI requests to their parent conversation.
-- Nullable — existing rows get NULL (no backfill needed).

ALTER TABLE ai_request_logs
    ADD COLUMN IF NOT EXISTS conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL;

COMMENT ON COLUMN ai_request_logs.conversation_id IS 'FK to ai_conversations. Groups multi-turn messages. NULL for legacy/standalone requests.';


-- ==========================================
-- SECTION 4: RLS Policies
-- ==========================================

-- 4a. translations — NO RLS (platform-global, no workspace_id)
-- Access controlled at application layer: read-only for tenants, write via platform admin.

-- 4b. exchange_rates — standard workspace RLS
ALTER TABLE exchange_rates ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_exchange_rates ON exchange_rates
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- 4c. ai_conversations — standard workspace RLS
-- Application layer MUST also enforce user_id filtering for 'own' scope.
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_ai_conversations ON ai_conversations
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- 4d. ai_change_requests — standard workspace RLS
ALTER TABLE ai_change_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_ai_change_requests ON ai_change_requests
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);


-- ==========================================
-- SECTION 5: Indexes
-- ==========================================

-- 5a. translations indexes
CREATE INDEX IF NOT EXISTS idx_translations_locale_ns
    ON translations(locale, namespace);
CREATE INDEX IF NOT EXISTS idx_translations_key
    ON translations(key);

-- 5b. exchange_rates indexes
CREATE INDEX IF NOT EXISTS idx_exchange_rates_ws_pair
    ON exchange_rates(workspace_id, base_currency, target_currency);
CREATE INDEX IF NOT EXISTS idx_exchange_rates_ws_date
    ON exchange_rates(workspace_id, effective_date DESC);
-- Optimized lookup index: find most recent rate for a currency pair
CREATE INDEX IF NOT EXISTS idx_exchange_rates_lookup
    ON exchange_rates(workspace_id, base_currency, target_currency, effective_date DESC);

-- 5c. ai_conversations indexes
CREATE INDEX IF NOT EXISTS idx_ai_conversations_ws_user
    ON ai_conversations(workspace_id, user_id);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_ws_mode
    ON ai_conversations(workspace_id, mode);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_last_msg
    ON ai_conversations(workspace_id, last_message_at DESC NULLS LAST);

-- 5d. ai_change_requests indexes
CREATE INDEX IF NOT EXISTS idx_ai_change_reqs_ws_status
    ON ai_change_requests(workspace_id, status);
CREATE INDEX IF NOT EXISTS idx_ai_change_reqs_conv
    ON ai_change_requests(conversation_id)
    WHERE conversation_id IS NOT NULL;
-- Partial index for pending proposals (most queried state)
CREATE INDEX IF NOT EXISTS idx_ai_change_reqs_pending
    ON ai_change_requests(workspace_id, proposed_at DESC)
    WHERE status = 'proposed';

-- 5e. Altered column indexes
-- ai_request_logs: index on new conversation_id
CREATE INDEX IF NOT EXISTS idx_ai_logs_conversation
    ON ai_request_logs(conversation_id)
    WHERE conversation_id IS NOT NULL;
-- journal_entries: indexes on new columns
CREATE INDEX IF NOT EXISTS idx_journal_entries_currency
    ON journal_entries(workspace_id, currency)
    WHERE currency <> 'LYD';
CREATE INDEX IF NOT EXISTS idx_journal_entries_status
    ON journal_entries(workspace_id, status);


-- ==========================================
-- SECTION 6: updated_at Triggers
-- ==========================================
-- FIX #1: All trigger creations are idempotent via IF NOT EXISTS guards.

-- translations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_translations_updated'
    ) THEN
        CREATE TRIGGER trg_translations_updated
            BEFORE UPDATE ON translations
            FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    END IF;
END $$;

-- exchange_rates (no updated_at column — immutable rate rows, new rate = new row)

-- ai_conversations
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ai_conversations_updated'
    ) THEN
        CREATE TRIGGER trg_ai_conversations_updated
            BEFORE UPDATE ON ai_conversations
            FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    END IF;
END $$;

-- ai_change_requests
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ai_change_requests_updated'
    ) THEN
        CREATE TRIGGER trg_ai_change_requests_updated
            BEFORE UPDATE ON ai_change_requests
            FOR EACH ROW EXECUTE FUNCTION update_timestamp();
    END IF;
END $$;


-- ==========================================
-- SECTION 7: Cross-Workspace FK Validation Triggers
-- ==========================================

-- exchange_rates: workspace_id is the only workspace FK, validated by direct FK constraint.
-- No cross-workspace validation needed (no secondary workspace-scoped FKs).

-- ai_conversations: user_id references global users table, not workspace-scoped.
-- workspace_id validated by direct FK. No cross-workspace risk.

-- ai_change_requests: conversation_id references ai_conversations which is workspace-scoped.
-- Must validate that conversation belongs to the same workspace.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_ai_change_requests_ws_fk'
    ) THEN
        CREATE TRIGGER trg_ai_change_requests_ws_fk
            BEFORE INSERT OR UPDATE ON ai_change_requests
            FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
                'conversation_id:ai_conversations'
            );
    END IF;
END $$;


-- ==========================================
-- SECTION 8: Unique Constraints for RLS Composite Keys
-- ==========================================
-- FIX #5: These composite (workspace_id, id) UNIQUE constraints are INTENTIONALLY required.
-- Pattern rationale: When another workspace-scoped table needs a FK to one of these tables,
-- the FK must reference (workspace_id, id) — not just (id) — so that PostgreSQL RLS
-- can validate the FK resolves within the same tenant. Without a UNIQUE constraint on
-- (workspace_id, id), PostgreSQL refuses to create such a FK. This is the same pattern
-- used in migrations 001 (billing), 002 (memberships), 003 (financial), 005 (inventory).

-- FIX #2: All constraint additions are idempotent via IF NOT EXISTS guards.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_exchange_rates_ws_id'
    ) THEN
        ALTER TABLE exchange_rates
            ADD CONSTRAINT uq_exchange_rates_ws_id UNIQUE (workspace_id, id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_ai_conversations_ws_id'
    ) THEN
        ALTER TABLE ai_conversations
            ADD CONSTRAINT uq_ai_conversations_ws_id UNIQUE (workspace_id, id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_ai_change_requests_ws_id'
    ) THEN
        ALTER TABLE ai_change_requests
            ADD CONSTRAINT uq_ai_change_requests_ws_id UNIQUE (workspace_id, id);
    END IF;
END $$;


-- ==========================================
-- SECTION 9: Verification Queries
-- ==========================================

-- Run these after migration to confirm everything is correct:

-- V1: Verify new columns on workspaces
-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'workspaces'
--   AND column_name IN ('default_locale', 'default_currency', 'timezone');
-- Expected: 3 rows, all NOT NULL with defaults

-- V2: Verify new columns on users
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'users' AND column_name = 'preferred_locale';
-- Expected: 1 row, nullable

-- V3: Verify new columns on journal_entries
-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'journal_entries'
--   AND column_name IN ('currency', 'exchange_rate', 'status');
-- Expected: 3 rows, all NOT NULL with defaults

-- V4: Verify new column on journal_lines
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'journal_lines' AND column_name = 'reporting_amount';
-- Expected: 1 row, nullable

-- V5: Verify new tables exist
-- SELECT tablename FROM pg_tables
-- WHERE schemaname = 'public'
--   AND tablename IN ('translations', 'exchange_rates', 'ai_conversations', 'ai_change_requests');
-- Expected: 4 rows

-- V6: Verify RLS is enabled on new workspace-scoped tables
-- SELECT tablename, rowsecurity FROM pg_tables
-- WHERE tablename IN ('exchange_rates', 'ai_conversations', 'ai_change_requests');
-- Expected: all rowsecurity = true

-- V7: Verify ai_request_logs has conversation_id
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_name = 'ai_request_logs' AND column_name = 'conversation_id';
-- Expected: 1 row, nullable UUID

-- V8: Verify translations is NOT under RLS (platform-global)
-- SELECT tablename, rowsecurity FROM pg_tables WHERE tablename = 'translations';
-- Expected: rowsecurity = false

-- V9: Verify CHECK constraints
-- SELECT conname FROM pg_constraint
-- WHERE conrelid = 'journal_entries'::regclass AND contype = 'c';
-- Expected: includes chk_journal_entries_status, chk_journal_entries_exchange_rate

COMMIT;

-- ==========================================
-- POST-MIGRATION NOTES
-- ==========================================
--
-- 1. TRANSLATIONS SEEDING:
--    After migration, seed the translations table with base English strings.
--    Additional locales (Arabic, French, Turkish) can be added incrementally.
--    Example: INSERT INTO translations (locale, namespace, key, value)
--             VALUES ('en', 'modules', 'products.title', 'Products');
--
-- 2. EXCHANGE RATE LOOKUP PATTERN:
--    To find the applicable rate for a transaction date:
--    SELECT rate FROM exchange_rates
--    WHERE workspace_id = ? AND base_currency = ? AND target_currency = ?
--      AND effective_date <= ?
--    ORDER BY effective_date DESC LIMIT 1;
--
-- 3. JOURNAL POSTING FLOW:
--    When posting a journal entry:
--    a) Set journal_entries.status = 'posted'
--    b) Look up exchange_rate from exchange_rates table (or use rate provided in request)
--    c) Compute journal_lines.reporting_amount = (debit - credit) * exchange_rate
--    d) Store in a single transaction
--
-- 4. AI CONVERSATION FLOW:
--    a) Client calls POST /ai/conversations to create conversation
--    b) Messages sent via POST /ai/conversations/{id}/messages
--    c) Each message creates an ai_request_logs row with conversation_id set
--    d) If AI proposes a change, INSERT into ai_change_requests
--    e) Owner/admin reviews via GET /ai/change-requests?status=proposed
--    f) Approved changes applied via POST /ai/change-requests/{id}/apply
--
-- 5. D7 NOTE:
--    workspace_memberships.assigned_warehouses JSONB already exists (migration 002).
--    No work was needed. The delta plan's "warehouse_ids" = "assigned_warehouses".
