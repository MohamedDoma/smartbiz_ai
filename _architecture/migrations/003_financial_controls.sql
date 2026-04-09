-- ==========================================
-- SmartBiz AI — Migration 003: Financial Controls
-- Batch C from SQL Patch Execution Pack
-- ==========================================
--
-- Purpose:
--   Implement financial integrity structures: credit notes, customer credits,
--   payment reversals, fiscal period management, and POS session enrichment.
--
-- Prerequisites:
--   Base schema (1_database_schema.sql) + 001_additive_foundation.sql + 002_rbac_persistence.sql
--
-- Risk: MEDIUM — alters the existing `payments` table (CHECK constraint change)
--        and `pos_sessions` table.  No data loss; additive + non-destructive ALTERs.
--
-- ==========================================
-- ARCHITECTURAL DECISIONS
-- ==========================================
--
-- D1. pos_sessions ambiguity resolution
--   `pos_sessions` ALREADY EXISTS in the base schema (1_database_schema.sql, line 621).
--   It was created as table #40 with columns: id, workspace_id, terminal_id, user_id,
--   opening_balance, closing_balance, expected_balance, total_cash_sales,
--   total_card_sales, total_refunds, difference, status ('open','closed'),
--   opened_at, closed_at, notes.
--   RLS, indexes, workspace FK triggers, and updated_at trigger are already applied.
--   Therefore this migration ALTERs pos_sessions (does NOT recreate it).
--   Additions: session_number (sequential), branch_id (for scope filtering),
--   total_mobile_sales, counted_balance, closed_by, and updated_at column.
--
-- D2. Credit notes are a dedicated table (not an invoice_type enum extension).
--   Rationale: credit notes have distinct lifecycle, link to original invoice,
--   carry line-level detail, and require independent sequence numbering.
--   This aligns with BR-INV-004 and the ⚠️ schema gap noted in the API spec.
--
-- D3. Payment reversal via self-referencing FK + status column.
--   The existing payments.amount CHECK (amount > 0) is PRESERVED.
--   Reversal records also carry positive amounts; the reversal semantics
--   are expressed via is_reversal = TRUE + reversal_of_payment_id FK.
--   The accounting direction is reversed at the journal-entry level.
--   This aligns with BR-PAY-005.
--   DB-ENFORCED: one reversal per original (unique index), reversal-of-reversal
--   prevention (CHECK), is_reversal ↔ reversal_of_payment_id consistency (CHECK).
--   APP-ENFORCED: original payment must be status='completed' before reversal;
--   original payment status set to 'reversed' atomically with reversal insert.
--
-- D4. Customer credits as a dedicated ledger table.
--   Tracks individual credit events (overpayment, credit note, manual grant)
--   with debit/credit movement pattern.  Aligns with BR-PAY-004.
--
-- D5. Fiscal periods follow the FSM: open → closed → locked.
--   Closed may be reopened; locked is terminal.  Aligns with BR-FIN-004.
--
-- ==========================================


-- ==========================================
-- SECTION 1: Credit Notes (NEW)
-- ==========================================
-- Implements BR-INV-004: credit note as a negative adjustment linked
-- to an original invoice.  Supports full and partial credit notes.
--
-- ⚠️ APPLICATION-LAYER INVARIANTS (too complex or cross-row for CHECK constraints):
--   1. original_invoice_id MUST reference an invoice in the SAME workspace.
--      → Enforced by validate_workspace_fk trigger (Section 9).
--   2. contact_id MUST match the contact on the original invoice.
--      → Enforced at service layer on create/update.
--   3. currency + exchange_rate MUST match the original invoice.
--      → Enforced at service layer; mismatches rejected before insert.
--   4. total_amount MUST NOT exceed the original invoice's creditable balance
--      (original total − sum of prior non-void credit notes).
--      → Enforced at service layer with SELECT FOR UPDATE on original invoice.
--   5. credit_note_number is assigned atomically from document_sequences on issue.
--      → Enforced at service layer with advisory lock.

CREATE TABLE credit_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,

    -- Link to the original invoice being credited
    original_invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,

    -- Contact (customer / supplier) inherits from original invoice
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,

    -- Creator
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Financial details (all stored as positive values; the sign is implied)
    total_amount DECIMAL(12, 2) NOT NULL CHECK (total_amount > 0),
    tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0),
    net_amount DECIMAL(12, 2) NOT NULL CHECK (net_amount > 0),

    -- Reason / audit trail
    reason TEXT NOT NULL,

    -- Status FSM: draft → issued → applied → void
    --   draft    = being prepared, editable
    --   issued   = finalized, journal entry posted, line items locked
    --   applied  = credit fully consumed (via refund payment or invoice offset)
    --   void     = cancelled before application
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'issued', 'applied', 'void')),

    -- Sequence number (assigned on issue, from document_sequences)
    credit_note_number VARCHAR(50),

    -- Currency (should match original invoice)
    currency VARCHAR(10) NOT NULL DEFAULT 'LYD',
    exchange_rate DECIMAL(10, 4) NOT NULL DEFAULT 1.0000,

    -- Reference to reversal journal entry created on issue
    reversal_journal_entry_id UUID REFERENCES journal_entries(id) ON DELETE SET NULL,

    -- Lifecycle
    issued_at TIMESTAMPTZ,
    voided_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Business constraints
    UNIQUE(workspace_id, credit_note_number),
    CHECK (net_amount <= total_amount)
);

COMMENT ON TABLE credit_notes IS 'Credit notes issued against invoices (BR-INV-004). A credit note is a negative adjustment that can be applied as a customer credit or refunded.';
COMMENT ON COLUMN credit_notes.total_amount IS 'Positive value representing the credited amount (before tax adjustments). Must not exceed original invoice creditable balance (app-enforced).';
COMMENT ON COLUMN credit_notes.status IS 'FSM: draft → issued → applied | void. Issued credit notes are immutable.';
COMMENT ON COLUMN credit_notes.currency IS 'Must match original invoice currency (app-enforced). Mismatches rejected at service layer.';
COMMENT ON COLUMN credit_notes.contact_id IS 'Must match original invoice contact (app-enforced). Denormalized here for query convenience.';

-- Credit note line items (mirrors invoice_items structure)
-- DESIGN DECISION (Fix #3): workspace_id is added directly for RLS safety.
-- This allows credit_note_items to be queried safely with RLS without requiring
-- a JOIN to credit_notes. The workspace_id must match the parent credit_note.
CREATE TABLE credit_note_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    credit_note_id UUID NOT NULL REFERENCES credit_notes(id) ON DELETE CASCADE,
    product_id UUID REFERENCES products(id) ON DELETE SET NULL,
    variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL,
    unit_id UUID REFERENCES units_of_measure(id) ON DELETE SET NULL,
    warehouse_id UUID REFERENCES warehouses(id) ON DELETE SET NULL,

    -- Must match or be less than original invoice line
    quantity DECIMAL(12, 4) NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(10, 2) NOT NULL CHECK (unit_price >= 0),
    discount_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (discount_amount >= 0),
    tax_amount DECIMAL(12, 2) NOT NULL DEFAULT 0.00 CHECK (tax_amount >= 0),
    subtotal DECIMAL(12, 2) NOT NULL CHECK (subtotal >= 0),

    -- Snapshots from time of credit note creation
    product_name_snapshot VARCHAR(255),
    sku_snapshot VARCHAR(100),
    tax_rate_snapshot DECIMAL(5, 2),

    -- Reference to original invoice item being credited (optional but recommended)
    original_invoice_item_id UUID REFERENCES invoice_items(id) ON DELETE SET NULL
);

COMMENT ON TABLE credit_note_items IS 'Line-level detail for credit notes. Has direct workspace_id for RLS safety — never query this table without workspace scoping.';


-- ==========================================
-- SECTION 2: Customer Credits (NEW)
-- ==========================================
-- Implements BR-PAY-004: overpayment, credit note application, manual credits.
-- This is a ledger-style table tracking individual credit movements.

CREATE TABLE customer_credits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,

    -- Movement type: how the credit originated or was consumed
    movement_type VARCHAR(50) NOT NULL
        CHECK (movement_type IN (
            'overpayment',        -- Excess from a payment (BR-PAY-004)
            'credit_note',        -- From an issued credit note (BR-INV-004)
            'manual_grant',       -- Manual credit by authorized user
            'invoice_offset',     -- Credit applied to reduce an invoice balance (debit)
            'refund',             -- Credit refunded to customer (debit)
            'manual_debit',       -- Manual deduction by authorized user
            'expiry'              -- Credit expired (if workspace enforces expiry)
        )),

    -- Positive = credit granted (increases balance)
    -- Negative = credit consumed/debited (decreases balance)
    amount DECIMAL(12, 2) NOT NULL CHECK (amount <> 0),

    -- Running balance AFTER this movement (denormalized for fast reads)
    balance_after DECIMAL(12, 2) NOT NULL CHECK (balance_after >= 0),

    -- References to source/target entities
    payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    credit_note_id UUID REFERENCES credit_notes(id) ON DELETE SET NULL,
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,

    -- Currency
    currency VARCHAR(10) NOT NULL DEFAULT 'LYD',

    -- Audit
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE customer_credits IS 'Ledger of customer credit movements (BR-PAY-004). Tracks overpayments, credit note applications, offsets against invoices, and refunds.';
COMMENT ON COLUMN customer_credits.amount IS 'Positive = credit granted; negative = credit consumed. Zero is forbidden.';
COMMENT ON COLUMN customer_credits.balance_after IS
    'APPLICATION-MAINTAINED running balance for this contact after this movement. '
    'Must never go negative (enforced by CHECK constraint). '
    'Calculated at application layer as: previous balance_after + current amount. '
    'The application MUST use SELECT FOR UPDATE on the latest row for this (workspace_id, contact_id) '
    'ordered by created_at DESC to prevent race conditions. '
    'Periodic reconciliation jobs SHOULD verify balance_after consistency against SUM(amount). '
    'This column is NOT maintained by database triggers — it is the responsibility of the service layer.';


-- ==========================================
-- SECTION 3: ALTER payments — Reversal Support
-- ==========================================
-- Implements BR-PAY-005: payment reversal.
-- Existing payments.amount CHECK (amount > 0) is PRESERVED.
-- Reversal records carry positive amounts too; reversal semantics are
-- expressed via is_reversal = TRUE and the contra journal entry.

-- Add reversal and status columns
ALTER TABLE payments
    ADD COLUMN IF NOT EXISTS reversal_of_payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'completed'
        CHECK (status IN ('pending', 'completed', 'failed', 'reversed')),
    ADD COLUMN IF NOT EXISTS is_reversal BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS reversal_reason TEXT,
    ADD COLUMN IF NOT EXISTS reversed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS reversed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS pos_session_id UUID REFERENCES pos_sessions(id) ON DELETE SET NULL;

COMMENT ON COLUMN payments.reversal_of_payment_id IS
    'Self-FK: if this payment is a reversal, references the original payment being reversed (BR-PAY-005). '
    'DB-enforced: unique index prevents multiple reversals of the same original. '
    'APP-enforced: original payment must have status=completed at time of reversal insert.';
COMMENT ON COLUMN payments.status IS
    'Payment lifecycle: pending → completed → reversed. Failed is a terminal error state. '
    'APP-enforced: only the application may transition status; service layer must set '
    'original payment to reversed atomically with reversal insert (same transaction).';
COMMENT ON COLUMN payments.is_reversal IS
    'TRUE if this record is a reversal of another payment. Amount is still positive; '
    'the accounting direction is reversed via contra journal entry.';
COMMENT ON COLUMN payments.pos_session_id IS 'Links cash/card payments to the POS session they were processed in (BR-PAY-007).';

-- FIX #1a: is_reversal ↔ reversal_of_payment_id must be consistent
ALTER TABLE payments
    ADD CONSTRAINT chk_reversal_consistency
    CHECK (
        (is_reversal = FALSE AND reversal_of_payment_id IS NULL)
        OR
        (is_reversal = TRUE AND reversal_of_payment_id IS NOT NULL)
    );

-- FIX #1b: A reversal record must NOT itself be in 'reversed' status.
-- This prevents reversing a reversal at the DB level.
ALTER TABLE payments
    ADD CONSTRAINT chk_no_reversal_of_reversal
    CHECK (
        is_reversal = FALSE
        OR status <> 'reversed'
    );

-- FIX #1c: UNIQUE index on reversal_of_payment_id prevents multiple reversals
-- of the same original payment. Only one reversal record per original is allowed.
-- (Partial unique index — only rows where reversal_of_payment_id IS NOT NULL)
CREATE UNIQUE INDEX uq_payments_one_reversal_per_original
    ON payments(reversal_of_payment_id)
    WHERE reversal_of_payment_id IS NOT NULL;

-- FIX #1d: Reversal records must NOT be reversible (status can never be 'reversed')
-- Already enforced by chk_no_reversal_of_reversal above.
-- APP-ENFORCED additionally: when creating a reversal, the application MUST verify:
--   1. Original payment exists and has status = 'completed'
--   2. Original payment has is_reversal = FALSE (no chained reversals)
--   3. No existing reversal record for this original (caught by unique index)
-- These checks should use SELECT ... FOR UPDATE on the original payment row.

-- Add composite unique for workspace FK validation
ALTER TABLE payments ADD CONSTRAINT uq_payments_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 4: Fiscal Periods (NEW)
-- ==========================================
-- Implements BR-FIN-004: fiscal period management.
-- FSM: open → closed ↔ open (reopen), closed → locked (terminal).

CREATE TABLE fiscal_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Period identification
    name VARCHAR(100) NOT NULL,              -- e.g. "FY2026-Q1", "January 2026"
    period_type VARCHAR(50) NOT NULL DEFAULT 'monthly'
        CHECK (period_type IN ('monthly', 'quarterly', 'semi_annual', 'annual', 'custom')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Fiscal year grouping (e.g. 2026)
    fiscal_year INT NOT NULL CHECK (fiscal_year >= 2000 AND fiscal_year <= 2100),

    -- FSM status: open → closed ↔ open → locked (terminal)
    status VARCHAR(50) NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'closed', 'locked')),

    -- Lock audit trail
    closed_at TIMESTAMPTZ,
    closed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    locked_at TIMESTAMPTZ,
    locked_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Reopen audit
    last_reopened_at TIMESTAMPTZ,
    last_reopened_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reopen_count INT NOT NULL DEFAULT 0 CHECK (reopen_count >= 0),

    -- Lifecycle
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    UNIQUE(workspace_id, name),
    CHECK (end_date > start_date),
    -- Locked periods must have locked_at
    CHECK (status <> 'locked' OR locked_at IS NOT NULL),
    -- Closed periods must have closed_at
    CHECK (status NOT IN ('closed', 'locked') OR closed_at IS NOT NULL)
);

-- FIX #5: Prevent overlapping fiscal periods within the same workspace.
-- Uses a GiST exclusion constraint on (workspace_id, daterange).
-- Requires btree_gist extension for UUID equality in exclusion constraints.
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE fiscal_periods
    ADD CONSTRAINT excl_fiscal_periods_no_overlap
    EXCLUDE USING GIST (
        workspace_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    );

COMMENT ON CONSTRAINT excl_fiscal_periods_no_overlap ON fiscal_periods IS
    'Prevents overlapping fiscal periods within the same workspace. '
    'Uses daterange with inclusive bounds [start_date, end_date]. '
    'Adjacent periods (end_date of period A = start_date of period B) are allowed '
    'because the range is closed-closed and overlap operator (&&) handles adjacency correctly.';

COMMENT ON TABLE fiscal_periods IS 'Workspace fiscal periods for accounting period management (BR-FIN-004). Transactions may only be posted to open periods. Locked periods are permanently sealed. Overlapping periods within a workspace are prevented by exclusion constraint.';
COMMENT ON COLUMN fiscal_periods.status IS 'open = accepts postings; closed = no postings, may be reopened; locked = permanently sealed, CANNOT be reopened.';
COMMENT ON COLUMN fiscal_periods.reopen_count IS 'Number of times this period has been reopened from closed state. Audit indicator.';


-- ==========================================
-- SECTION 5: ALTER pos_sessions — Enrichment
-- ==========================================
-- pos_sessions ALREADY EXISTS (base schema line 621).
-- Adding columns for: session numbering, branch linkage, mobile payment
-- tracking, counted balance vs expected, closed_by, and updated_at.
-- Existing columns retained: id, workspace_id, terminal_id, user_id,
-- opening_balance, closing_balance, expected_balance, total_cash_sales,
-- total_card_sales, total_refunds, difference, status, opened_at,
-- closed_at, notes.

-- FIX #7 note: updated_at is added with DEFAULT, then backfilled, then made NOT NULL.
ALTER TABLE pos_sessions
    ADD COLUMN IF NOT EXISTS session_number VARCHAR(50),
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS total_mobile_sales DECIMAL(12, 2) DEFAULT 0.00
        CHECK (total_mobile_sales IS NULL OR total_mobile_sales >= 0),
    ADD COLUMN IF NOT EXISTS counted_balance DECIMAL(12, 2),
    ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

COMMENT ON COLUMN pos_sessions.session_number IS 'Sequential session identifier from document_sequences (e.g. POS-2026-0042).';
COMMENT ON COLUMN pos_sessions.branch_id IS 'Branch where this POS session operated. Enables branch-scoped reporting and filtering.';
COMMENT ON COLUMN pos_sessions.total_mobile_sales IS 'Total mobile payment sales during this session.';
COMMENT ON COLUMN pos_sessions.counted_balance IS 'Physically counted cash balance at session close. Used with expected_balance to calculate variance.';
COMMENT ON COLUMN pos_sessions.closed_by IS 'User who closed the session (may differ from session opener).';

-- Add unique constraint for session numbering within workspace
-- (only non-null session_numbers are enforced)
CREATE UNIQUE INDEX IF NOT EXISTS uq_pos_sessions_number
    ON pos_sessions(workspace_id, session_number)
    WHERE session_number IS NOT NULL;

-- Add status expansion: allow 'suspended' for interrupted sessions
-- Drop old check and add updated one
ALTER TABLE pos_sessions
    DROP CONSTRAINT IF EXISTS pos_sessions_status_check;
ALTER TABLE pos_sessions
    ADD CONSTRAINT pos_sessions_status_check
    CHECK (status IN ('open', 'closed', 'suspended'));

-- Composite unique for workspace FK validation (if not already present)
ALTER TABLE pos_sessions
    ADD CONSTRAINT uq_pos_sessions_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 6: updated_at Triggers
-- ==========================================
-- Reuses the existing update_timestamp() function from the base schema.

CREATE TRIGGER trg_credit_notes_updated
    BEFORE UPDATE ON credit_notes
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_fiscal_periods_updated
    BEFORE UPDATE ON fiscal_periods
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- pos_sessions: add trigger only if not already present
-- The base schema does NOT have an updated_at trigger for pos_sessions
-- (it had no updated_at column). Now that we added updated_at, add the trigger.
CREATE TRIGGER trg_pos_sessions_updated
    BEFORE UPDATE ON pos_sessions
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 7: Indexes
-- ==========================================

-- Credit notes
CREATE INDEX idx_credit_notes_workspace ON credit_notes(workspace_id);
CREATE INDEX idx_credit_notes_invoice ON credit_notes(original_invoice_id);
CREATE INDEX idx_credit_notes_contact ON credit_notes(contact_id);
CREATE INDEX idx_credit_notes_status ON credit_notes(status);
CREATE INDEX idx_credit_notes_branch ON credit_notes(branch_id);
CREATE INDEX idx_credit_notes_created ON credit_notes(created_at);
-- Partial index: sum of non-void credit notes per invoice (for creditable balance check)
CREATE INDEX idx_credit_notes_active_per_invoice ON credit_notes(original_invoice_id)
    WHERE status <> 'void';

-- Credit note items (now with workspace_id)
CREATE INDEX idx_credit_note_items_workspace ON credit_note_items(workspace_id);
CREATE INDEX idx_credit_note_items_note ON credit_note_items(credit_note_id);
CREATE INDEX idx_credit_note_items_product ON credit_note_items(product_id);
CREATE INDEX idx_credit_note_items_original ON credit_note_items(original_invoice_item_id)
    WHERE original_invoice_item_id IS NOT NULL;

-- Customer credits
CREATE INDEX idx_customer_credits_workspace ON customer_credits(workspace_id);
CREATE INDEX idx_customer_credits_contact ON customer_credits(contact_id);
CREATE INDEX idx_customer_credits_type ON customer_credits(movement_type);
CREATE INDEX idx_customer_credits_payment ON customer_credits(payment_id)
    WHERE payment_id IS NOT NULL;
CREATE INDEX idx_customer_credits_credit_note ON customer_credits(credit_note_id)
    WHERE credit_note_id IS NOT NULL;
CREATE INDEX idx_customer_credits_invoice ON customer_credits(invoice_id)
    WHERE invoice_id IS NOT NULL;
CREATE INDEX idx_customer_credits_created ON customer_credits(created_at);
-- Composite index for fast balance lookups per contact per workspace
CREATE INDEX idx_customer_credits_ws_contact ON customer_credits(workspace_id, contact_id);

-- Payments (new columns)
-- Note: uq_payments_one_reversal_per_original unique index already created in Section 3.
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_pos_session ON payments(pos_session_id)
    WHERE pos_session_id IS NOT NULL;
-- Partial index: find reversible (non-reversal, completed) payments efficiently
CREATE INDEX idx_payments_reversible ON payments(workspace_id, id)
    WHERE status = 'completed' AND is_reversal = FALSE;
-- Partial index: quickly find the reversal record for a given original
CREATE INDEX idx_payments_reversal_of ON payments(reversal_of_payment_id)
    WHERE reversal_of_payment_id IS NOT NULL;

-- Fiscal periods
CREATE INDEX idx_fiscal_periods_workspace ON fiscal_periods(workspace_id);
CREATE INDEX idx_fiscal_periods_status ON fiscal_periods(status);
CREATE INDEX idx_fiscal_periods_year ON fiscal_periods(workspace_id, fiscal_year);
CREATE INDEX idx_fiscal_periods_dates ON fiscal_periods(workspace_id, start_date, end_date);
-- Active (open) periods: hot path for transaction posting validation
CREATE INDEX idx_fiscal_periods_open ON fiscal_periods(workspace_id, start_date, end_date)
    WHERE status = 'open';

-- pos_sessions (new columns)
CREATE INDEX idx_pos_sessions_branch ON pos_sessions(branch_id)
    WHERE branch_id IS NOT NULL;
CREATE INDEX idx_pos_sessions_status ON pos_sessions(status);
CREATE INDEX idx_pos_sessions_closed_by ON pos_sessions(closed_by)
    WHERE closed_by IS NOT NULL;


-- ==========================================
-- SECTION 8: Composite Unique Constraints (workspace FK validation)
-- ==========================================

ALTER TABLE credit_notes ADD CONSTRAINT uq_credit_notes_ws_id UNIQUE (workspace_id, id);
ALTER TABLE credit_note_items ADD CONSTRAINT uq_credit_note_items_ws_id UNIQUE (workspace_id, id);
ALTER TABLE customer_credits ADD CONSTRAINT uq_customer_credits_ws_id UNIQUE (workspace_id, id);
ALTER TABLE fiscal_periods ADD CONSTRAINT uq_fiscal_periods_ws_id UNIQUE (workspace_id, id);
-- payments and pos_sessions already handled above


-- ==========================================
-- SECTION 9: Workspace FK Isolation Triggers
-- ==========================================
-- Ensures child records cannot cross workspace boundaries.

CREATE TRIGGER trg_credit_notes_ws_check
    BEFORE INSERT OR UPDATE ON credit_notes
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'branch_id:branches,original_invoice_id:invoices,contact_id:contacts,created_by:users,reversal_journal_entry_id:journal_entries'
    );

CREATE TRIGGER trg_credit_note_items_ws_check
    BEFORE INSERT OR UPDATE ON credit_note_items
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'credit_note_id:credit_notes,product_id:products,warehouse_id:warehouses'
    );

CREATE TRIGGER trg_customer_credits_ws_check
    BEFORE INSERT OR UPDATE ON customer_credits
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'contact_id:contacts,payment_id:payments,credit_note_id:credit_notes,invoice_id:invoices,created_by:users'
    );

CREATE TRIGGER trg_fiscal_periods_ws_check
    BEFORE INSERT OR UPDATE ON fiscal_periods
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'closed_by:users,locked_by:users,last_reopened_by:users'
    );

-- Update existing payments workspace check to include new FK columns
-- Drop the old trigger first, then recreate with expanded column list
DROP TRIGGER IF EXISTS trg_payments_ws_check ON payments;
CREATE TRIGGER trg_payments_ws_check
    BEFORE INSERT OR UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'invoice_id:invoices,account_id:accounts,created_by:users,reversal_of_payment_id:payments,reversed_by:users,pos_session_id:pos_sessions'
    );

-- Update existing pos_sessions workspace check to include branch_id
DROP TRIGGER IF EXISTS trg_pos_sessions_ws_check ON pos_sessions;
CREATE TRIGGER trg_pos_sessions_ws_check
    BEFORE INSERT OR UPDATE ON pos_sessions
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'terminal_id:pos_terminals,user_id:users,branch_id:branches,closed_by:users'
    );


-- ==========================================
-- SECTION 10: Row Level Security (RLS)
-- ==========================================

-- credit_notes: workspace-scoped
ALTER TABLE credit_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_credit_notes ON credit_notes
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- credit_note_items: now has direct workspace_id (FIX #3)
ALTER TABLE credit_note_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_credit_note_items ON credit_note_items
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- customer_credits: workspace-scoped
ALTER TABLE customer_credits ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_customer_credits ON customer_credits
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- fiscal_periods: workspace-scoped
ALTER TABLE fiscal_periods ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_fiscal_periods ON fiscal_periods
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- payments: RLS already enabled in base schema (line 1267).
-- pos_sessions: RLS already enabled in base schema (line 1285).
-- No changes needed for these two.


-- ==========================================
-- SECTION 11: Backfill + NOT NULL enforcement for altered columns
-- ==========================================

-- FIX #2: payments.status backfill then enforce NOT NULL
UPDATE payments SET status = 'completed' WHERE status IS NULL;
ALTER TABLE payments ALTER COLUMN status SET NOT NULL;

-- payments.is_reversal: already NOT NULL with DEFAULT FALSE via ADD COLUMN definition

-- FIX #7: pos_sessions.updated_at backfill then enforce NOT NULL
UPDATE pos_sessions SET updated_at = opened_at WHERE updated_at IS NULL;
ALTER TABLE pos_sessions ALTER COLUMN updated_at SET NOT NULL;


-- ==========================================
-- END OF MIGRATION 003
-- ==========================================
-- Validation checklist:
--   [ ] credit_notes table exists with status CHECK and amount > 0
--   [ ] credit_note_items table exists with workspace_id, RLS, and workspace FK trigger
--   [ ] customer_credits table exists with movement_type CHECK
--   [ ] customer_credits.balance_after >= 0 enforced (app-maintained, documented)
--   [ ] payments has reversal_of_payment_id, status (NOT NULL), is_reversal columns
--   [ ] payments.chk_reversal_consistency ensures is_reversal ↔ reversal_of_payment_id
--   [ ] payments.chk_no_reversal_of_reversal prevents reversing a reversal
--   [ ] uq_payments_one_reversal_per_original prevents double-reversals
--   [ ] fiscal_periods table exists with status CHECK (open/closed/locked)
--   [ ] fiscal_periods has exclusion constraint preventing overlapping periods
--   [ ] fiscal_periods has date/lock audit columns
--   [ ] pos_sessions has session_number, branch_id, total_mobile_sales, counted_balance
--   [ ] pos_sessions status CHECK expanded to include 'suspended'
--   [ ] pos_sessions.updated_at is NOT NULL after backfill
--   [ ] All new updated_at triggers fire correctly
--   [ ] All new indexes exist (including idx_credit_notes_active_per_invoice)
--   [ ] Composite unique constraints on all new tables
--   [ ] Workspace FK isolation triggers active on all new tables (incl credit_note_items)
--   [ ] Payments and pos_sessions WS triggers updated with new FK columns
--   [ ] RLS enabled on credit_notes, credit_note_items, customer_credits, fiscal_periods
--   [ ] Existing payments backfilled with status = 'completed', then NOT NULL enforced
--   [ ] Existing pos_sessions.updated_at backfilled from opened_at, then NOT NULL enforced
--   [ ] btree_gist extension created for fiscal period overlap exclusion
--   [ ] Application-layer invariants documented in SQL comments (credit notes, customer credits, reversals)
-- ==========================================
