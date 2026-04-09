-- ==========================================
-- SmartBiz AI — Migration 004: HR / Workforce
-- Batch D from SQL Patch Execution Pack
-- ==========================================
--
-- Purpose:
--   Close all HR schema gaps flagged in API contracts and business rules.
--   Creates: leave_types, leave_balances, leave_requests, payroll_runs,
--   payroll_lines, shift_assignments.
--   Alters: attendance (shift linkage, overtime), leaves (leave_type FK).
--
-- Prerequisites:
--   Base schema + 001_additive_foundation + 002_rbac_persistence + 003_financial_controls
--
-- Risk: MEDIUM — ALTERs attendance table (adds columns, no data loss).
--        ALTERs leaves table (adds leave_type_id FK alongside legacy leave_type VARCHAR).
--        Creates new tables only; non-destructive.
--
-- ==========================================
-- PAYROLL PERSISTENCE APPROACH
-- ==========================================
--
-- The base schema defines `payroll` as a per-employee, per-month record
-- with base_salary, bonuses, deductions, and a GENERATED net_salary column.
-- This migration introduces:
--
--   1. `payroll_runs` — a batch-level parent representing a single payroll
--      execution cycle (draft → calculated → approved → disbursed → locked).
--      This is the entity referenced by the API at `/api/v1/payroll-runs`.
--
--   2. `payroll_lines` — line-item detail for each employee's payslip,
--      storing individual salary components (base, allowance, deduction,
--      overtime, tax, insurance, loan_repayment, absence_deduction, etc.).
--      Each line belongs to a payroll record (the per-employee record) and
--      transitively to a payroll_run.
--
-- The existing `payroll` table is ALTERed to add a `payroll_run_id` FK,
-- linking individual employee records to their batch run.
--
-- This approach preserves backward compatibility with the existing payroll
-- table while adding the structured line-item detail required by BR-PRL-002
-- and the API payslip endpoint (27.6).
--
-- ==========================================
-- PAYROLL DEPENDENCIES ON ATTENDANCE & LEAVE
-- ==========================================
--
-- Payroll calculation (BR-PRL-001/002) depends on:
--
--   1. ATTENDANCE: the attendance table provides worked_hours, overtime_hours,
--      late_minutes, and absence status for each employee in the payroll period.
--      The payroll calculation service MUST query attendance records for the
--      payroll_run's (period_start, period_end) date range to compute:
--      - overtime pay → payroll_lines with line_type='overtime'
--      - absence deductions → payroll_lines with line_type='absence_deduction'
--      - late deductions → payroll_lines with line_type='late_deduction'
--      APP-ENFORCED: attendance period must be finalized (no pending adjustments)
--      before payroll can transition from draft to calculated.
--
--   2. LEAVE_REQUESTS: approved leave requests within the payroll period
--      determine paid vs unpaid leave days. The payroll service MUST query
--      leave_requests WHERE status IN ('approved','completed') AND date range
--      overlaps the payroll period, then JOIN to leave_types.is_paid to
--      determine if a deduction applies.
--      APP-ENFORCED: all leave requests for the period must be resolved
--      (approved or rejected) before calculate.
--
--   3. PRIOR PAYROLL RUN: the previous payroll_run (if any) must be in
--      'locked' status before a new run can be calculated. This prevents
--      double-counting and ensures sequential processing.
--      APP-ENFORCED: service layer checks for prior run status.
--
-- These dependencies are NOT enforced by FK constraints because they are
-- cross-row, time-range-based queries. They are enforced at the service
-- layer during the payroll calculate transition.
--
-- ==========================================
-- ARCHITECTURAL DECISIONS
-- ==========================================
--
-- D1. leave_types is a workspace-configurable lookup table.
--     The existing leaves.leave_type VARCHAR column is preserved for backward
--     compatibility. A new leave_type_id UUID FK is added to leaves and to
--     the new leave_requests table. Both old and new paths coexist.
--
-- D2. leave_requests is a NEW table separate from the legacy `leaves` table.
--     Rationale: the legacy `leaves` table lacks the full FSM
--     (draft→submitted→approved→rejected→cancelled→completed), half_day support,
--     approval audit, and leave_type_id FK. Rather than destructively ALTER the
--     legacy table, we create `leave_requests` with the full API contract and
--     leave the legacy `leaves` table for migration-safe coexistence.
--     Going forward, the application layer uses `leave_requests` exclusively.
--
-- D3. shift_assignments enables flexible shift scheduling per BR-ATT-002.
--     The base `users.shift_id` provides a default shift, but real scheduling
--     needs per-day or per-week assignments. shift_assignments provides this.
--
-- D4. attendance is ALTERed to add shift linkage and overtime tracking
--     per BR-ATT-002 and BR-ATT-003.
--
-- ==========================================


-- ==========================================
-- SECTION 1: Leave Types (NEW)
-- ==========================================
-- Implements BR-LVE-001: workspace-configurable leave types with
-- accrual policy, balance limits, carry-forward rules, and approval config.

CREATE TABLE leave_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Type identification
    name VARCHAR(100) NOT NULL,
    code VARCHAR(50) NOT NULL,              -- short code e.g. 'ANNUAL', 'SICK'
    description TEXT,

    -- Accrual configuration
    accrual_policy VARCHAR(50) NOT NULL DEFAULT 'yearly'
        CHECK (accrual_policy IN ('monthly', 'yearly', 'none')),
    accrual_amount DECIMAL(6, 2) NOT NULL DEFAULT 0.00
        CHECK (accrual_amount >= 0),        -- days accrued per cycle
    max_balance DECIMAL(6, 2)
        CHECK (max_balance IS NULL OR max_balance > 0),  -- NULL = unlimited

    -- Carry-forward
    carry_forward_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    carry_forward_limit DECIMAL(6, 2) DEFAULT 0.00
        CHECK (carry_forward_limit IS NULL OR carry_forward_limit >= 0),
    carry_forward_expiry_months INT
        CHECK (carry_forward_expiry_months IS NULL OR carry_forward_expiry_months > 0),

    -- Behavioral flags
    is_paid BOOLEAN NOT NULL DEFAULT TRUE,
    requires_approval BOOLEAN NOT NULL DEFAULT TRUE,
    requires_documentation BOOLEAN NOT NULL DEFAULT FALSE,
    allow_negative_balance BOOLEAN NOT NULL DEFAULT FALSE,
    allow_half_day BOOLEAN NOT NULL DEFAULT TRUE,

    -- Display / ordering
    color VARCHAR(7),                       -- hex color for UI, e.g. '#4A90D9'
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- Lifecycle
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    UNIQUE(workspace_id, code),
    UNIQUE(workspace_id, name)
);

COMMENT ON TABLE leave_types IS 'Workspace-configurable leave types (BR-LVE-001). Defines accrual, carry-forward, and approval policies per type.';
COMMENT ON COLUMN leave_types.accrual_policy IS 'How leave days are accrued: monthly (days/month), yearly (days/year), none (manual grant only).';
COMMENT ON COLUMN leave_types.max_balance IS 'Maximum balance cap. NULL = no cap. Accrual stops when balance reaches this value.';
COMMENT ON COLUMN leave_types.allow_negative_balance IS 'If TRUE, leave requests are allowed even if they would cause a negative balance. Useful for sick leave.';


-- ==========================================
-- SECTION 2: Leave Balances (NEW)
-- ==========================================
-- Implements BR-LVE-002: per-user per-leave-type balance tracking.
-- APPLICATION-MAINTAINED: balance fields are managed by the service layer.
-- Accrual runs as a scheduled background job (monthly or yearly per leave_type config).

CREATE TABLE leave_balances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    leave_type_id UUID NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,

    -- Period tracking
    fiscal_year INT NOT NULL CHECK (fiscal_year >= 2000 AND fiscal_year <= 2100),

    -- Balance components (all in days, supporting half-days as 0.5)
    entitled DECIMAL(6, 2) NOT NULL DEFAULT 0.00 CHECK (entitled >= 0),
    used DECIMAL(6, 2) NOT NULL DEFAULT 0.00 CHECK (used >= 0),
    pending DECIMAL(6, 2) NOT NULL DEFAULT 0.00 CHECK (pending >= 0),
    carried_forward DECIMAL(6, 2) NOT NULL DEFAULT 0.00 CHECK (carried_forward >= 0),
    manually_adjusted DECIMAL(6, 2) NOT NULL DEFAULT 0.00,  -- can be negative (deductions)

    -- Computed remaining: entitled + carried_forward + manually_adjusted - used - pending
    -- APPLICATION-MAINTAINED: the service layer keeps this in sync.

    -- FIX #2: Balance integrity constraints
    -- used + pending cannot exceed total available (entitled + carried_forward + manually_adjusted)
    -- UNLESS leave_type.allow_negative_balance is TRUE (requires join — app-enforced).
    -- We add a basic sanity CHECK: used cannot exceed entitled + carried_forward + manually_adjusted
    -- for the common case. The allow_negative_balance exception is app-enforced.
    -- NOTE: This CHECK is a safety net. The app layer is the primary enforcement point
    -- because the allow_negative_balance flag lives on leave_types (cross-table).
    CHECK (
        used <= entitled + carried_forward + GREATEST(manually_adjusted, 0)
    ),

    -- Audit
    last_accrual_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints: one balance record per user per leave type per fiscal year
    UNIQUE(workspace_id, user_id, leave_type_id, fiscal_year)
);

COMMENT ON TABLE leave_balances IS
    'Per-user per-leave-type balance for each fiscal year (BR-LVE-002). '
    'All balance fields are APPLICATION-MAINTAINED by the service layer. '
    'Accrual is performed by a scheduled background job per leave_type.accrual_policy. '
    'remaining = entitled + carried_forward + manually_adjusted - used - pending. '
    'Negative balance prevention depends on leave_type.allow_negative_balance (app-enforced).';
COMMENT ON COLUMN leave_balances.entitled IS 'Total days entitled for this fiscal year (accrued or manually set).';
COMMENT ON COLUMN leave_balances.used IS 'Days actually taken (approved + completed leave requests).';
COMMENT ON COLUMN leave_balances.pending IS 'Days in submitted/approved-but-not-yet-taken requests. Released on cancel/reject.';
COMMENT ON COLUMN leave_balances.carried_forward IS 'Days carried over from previous fiscal year per carry-forward policy.';
COMMENT ON COLUMN leave_balances.manually_adjusted IS 'Manual adjustments by HR (positive = grant, negative = deduction).';


-- ==========================================
-- SECTION 3: Leave Requests (NEW)
-- ==========================================
-- Implements BR-LVE-003, BR-LVE-004, BR-LVE-005.
-- Full leave request lifecycle with approval support.
-- This is the primary table for leave management going forward.
-- The legacy `leaves` table is preserved for backward compatibility.

CREATE TABLE leave_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    leave_type_id UUID NOT NULL REFERENCES leave_types(id) ON DELETE RESTRICT,

    -- Date range
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    -- Duration
    duration_days DECIMAL(6, 2) NOT NULL CHECK (duration_days > 0),
    is_half_day BOOLEAN NOT NULL DEFAULT FALSE,

    -- Half-day specification (only applicable when is_half_day = TRUE)
    half_day_period VARCHAR(20)
        CHECK (half_day_period IS NULL OR half_day_period IN ('morning', 'afternoon')),

    -- Reason and documentation
    reason TEXT,
    attachment_url TEXT,

    -- Status FSM: draft → submitted → approved → completed | cancelled
    --             draft → submitted → rejected
    --             draft → cancelled
    --             approved → cancelled (only future days, per BR-LVE-005)
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'cancelled', 'completed')),

    -- Approval audit
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES users(id) ON DELETE SET NULL,
    rejected_at TIMESTAMPTZ,
    rejection_reason TEXT,

    -- Cancellation audit
    cancelled_by UUID REFERENCES users(id) ON DELETE SET NULL,
    cancelled_at TIMESTAMPTZ,
    cancelled_days DECIMAL(6, 2)
        CHECK (cancelled_days IS NULL OR cancelled_days > 0),

    -- Lifecycle
    submitted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (end_date >= start_date),
    -- half_day consistency: if half_day, duration must be 0.5 and start_date = end_date
    CHECK (
        is_half_day = FALSE
        OR (duration_days = 0.5 AND start_date = end_date AND half_day_period IS NOT NULL)
    ),
    -- Approval audit consistency
    CHECK (status <> 'approved' OR approved_at IS NOT NULL),
    CHECK (status <> 'rejected' OR (rejected_at IS NOT NULL AND rejection_reason IS NOT NULL)),
    CHECK (status <> 'cancelled' OR cancelled_at IS NOT NULL)
);

-- FIX #1: Prevent overlapping leave requests for the same user.
-- Uses GiST exclusion constraint on (workspace_id, user_id, daterange).
-- Only applies to active requests (not rejected/cancelled).
-- btree_gist extension was already created in 003_financial_controls.sql.
ALTER TABLE leave_requests
    ADD CONSTRAINT excl_leave_requests_no_overlap
    EXCLUDE USING GIST (
        user_id WITH =,
        daterange(start_date, end_date, '[]') WITH &&
    )
    WHERE (status NOT IN ('rejected', 'cancelled'));

COMMENT ON CONSTRAINT excl_leave_requests_no_overlap ON leave_requests IS
    'Prevents overlapping leave requests for the same user. '
    'Only applies to active requests (status not in rejected, cancelled). '
    'Uses daterange with inclusive bounds [start_date, end_date].';

COMMENT ON TABLE leave_requests IS
    'Full leave request lifecycle (BR-LVE-003/004/005). '
    'FSM: draft → submitted → approved → completed | cancelled; submitted → rejected. '
    'Approval requires hr.leaves.approve @ team|dept scope. '
    'Maker-checker enforced at app layer: approved_by != user_id. '
    'On approval, leave_balances.used is incremented and pending decremented. '
    'On cancellation of approved leave, used is decremented (only future days).';
COMMENT ON COLUMN leave_requests.duration_days IS 'Total working days requested. Supports half-days (0.5). Excludes weekends/holidays (app-calculated).';
COMMENT ON COLUMN leave_requests.status IS
    'FSM states: draft, submitted, approved, rejected, cancelled, completed. '
    'FIX #6: FSM TRANSITIONS ARE APPLICATION-ENFORCED. The database only validates '
    'that status is one of the allowed values via CHECK constraint. '
    'The service layer enforces the valid transition graph: '
    'draft→submitted, draft→cancelled, submitted→approved, submitted→rejected, '
    'approved→completed, approved→cancelled. '
    'No direct transitions like draft→approved or rejected→approved are permitted. '
    'The application MUST validate the current status before applying a transition.';
COMMENT ON COLUMN leave_requests.cancelled_days IS 'Number of days actually cancelled (may be less than duration_days if leave partially taken, per BR-LVE-005).';

-- ⚠️ APPLICATION-LAYER INVARIANTS for leave_requests:
--   1. Overlapping date check: DB-ENFORCED via excl_leave_requests_no_overlap exclusion constraint.
--      The application should still check proactively for better error messages.
--   2. Balance sufficiency: on submit, check leave_balances.remaining >= duration_days
--      (unless leave_type.allow_negative_balance = TRUE). APP-ENFORCED at service layer.
--   3. Maker-checker: approved_by MUST NOT equal user_id. APP-ENFORCED at service layer.
--   4. Cancellation of approved leave: only future days may be cancelled (BR-LVE-005).
--      If leave has started, only remaining future days are cancellable. APP-ENFORCED.
--   5. FSM transitions: APP-ENFORCED (see status COMMENT above).


-- ==========================================
-- SECTION 4: Payroll Runs (NEW)
-- ==========================================
-- Implements BR-PRL-001/003/004: batch-level payroll execution.
-- FSM: draft → calculated → approved → disbursed → locked

CREATE TABLE payroll_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,

    -- Period
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,

    -- Scope (optional filters applied when this run was created)
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,

    -- Status FSM: draft → calculated → approved → disbursed → locked
    status VARCHAR(50) NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'calculated', 'approved', 'disbursed', 'locked')),

    -- Aggregates (populated on calculate, updated if recalculated)
    employee_count INT CHECK (employee_count IS NULL OR employee_count >= 0),
    total_gross DECIMAL(15, 2) CHECK (total_gross IS NULL OR total_gross >= 0),
    total_deductions DECIMAL(15, 2) CHECK (total_deductions IS NULL OR total_deductions >= 0),
    total_net DECIMAL(15, 2) CHECK (total_net IS NULL OR total_net >= 0),

    -- Lifecycle audit
    calculated_at TIMESTAMPTZ,
    calculated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    disbursed_at TIMESTAMPTZ,
    disbursed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    locked_at TIMESTAMPTZ,
    locked_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Journal entry posted on disbursement (DR salary expense, CR payable/cash)
    journal_entry_id UUID REFERENCES journal_entries(id) ON DELETE SET NULL,

    -- Notes
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (period_end > period_start),
    -- Calculated runs must have calculated_at
    CHECK (status NOT IN ('calculated', 'approved', 'disbursed', 'locked') OR calculated_at IS NOT NULL),
    -- Approved must have approved_at
    CHECK (status NOT IN ('approved', 'disbursed', 'locked') OR approved_at IS NOT NULL),
    -- Disbursed must have disbursed_at
    CHECK (status NOT IN ('disbursed', 'locked') OR disbursed_at IS NOT NULL),
    -- Locked must have locked_at
    CHECK (status <> 'locked' OR locked_at IS NOT NULL)
);

COMMENT ON TABLE payroll_runs IS
    'Batch-level payroll execution (BR-PRL-001/003/004). '
    'FSM: draft → calculated → approved → disbursed → locked. '
    'Approved → rejected returns to draft (recalculate). '
    'Locked is terminal — no modifications allowed (DB-ENFORCED by trigger). '
    'Maker-checker: calculated_by != approved_by (app-enforced per BR-PRL-003). '
    'FSM transitions are APP-ENFORCED; the DB only validates allowed status values. '
    'Dependencies on attendance and leave_requests are documented in the file header.';
COMMENT ON COLUMN payroll_runs.status IS
    'FSM: draft, calculated, approved, disbursed, locked. '
    'Transitions are APP-ENFORCED. Lock is terminal and DB-ENFORCED by trigger.';
COMMENT ON COLUMN payroll_runs.employee_count IS 'Number of employees included in this run. Set on calculate.';

-- FIX #7: Lock protection trigger — prevents modification of locked payroll runs.
-- Once a payroll_run reaches 'locked' status, no further changes are allowed.
CREATE OR REPLACE FUNCTION prevent_locked_payroll_run_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'locked' THEN
        RAISE EXCEPTION 'Cannot modify a locked payroll run (id: %). Locked payroll runs are permanently sealed.', OLD.id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_payroll_runs_lock_guard
    BEFORE UPDATE ON payroll_runs
    FOR EACH ROW EXECUTE FUNCTION prevent_locked_payroll_run_modification();

COMMENT ON FUNCTION prevent_locked_payroll_run_modification() IS
    'Prevents any modification to payroll_runs with status=locked. '
    'Locked is a terminal state (BR-PRL-004). This is a DB-level guard; '
    'the application layer should also prevent locked-run modifications.';

-- ⚠️ APPLICATION-LAYER INVARIANTS for payroll_runs:
--   1. Prerequisites (BR-PRL-001): before calculate, attendance period must be finalized,
--      leave requests resolved, deductions configured, prior run locked.
--      See PAYROLL DEPENDENCIES ON ATTENDANCE & LEAVE section in header.
--   2. Maker-checker (BR-PRL-003): calculated_by != approved_by.
--   3. SoD: the user who processes payroll (hr.payroll.process) must not be
--      the same as the user who created employee records (hr.employees.create).
--   4. FSM transitions: draft→calculated→approved→disbursed→locked.
--      Approved→rejected returns to draft. All transitions APP-ENFORCED.
--   5. Lock immutability: DB-ENFORCED by trg_payroll_runs_lock_guard trigger.


-- ==========================================
-- SECTION 5: ALTER payroll — Link to Payroll Runs
-- ==========================================
-- Links existing per-employee payroll records to their batch run.
-- Also adds status tracking for individual payslip lifecycle.

ALTER TABLE payroll
    ADD COLUMN IF NOT EXISTS payroll_run_id UUID REFERENCES payroll_runs(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'draft'
        CHECK (status IS NULL OR status IN ('draft', 'calculated', 'approved', 'disbursed'));

COMMENT ON COLUMN payroll.payroll_run_id IS 'FK to the batch payroll_run this record belongs to.';
COMMENT ON COLUMN payroll.status IS 'Individual payslip status, mirrors the parent payroll_run status.';

-- Backfill existing records
UPDATE payroll SET status = 'draft' WHERE status IS NULL;


-- ==========================================
-- SECTION 6: Payroll Lines (NEW)
-- ==========================================
-- Implements BR-PRL-002: line-item detail for each employee's payslip.
-- Each line represents a single salary component (earning or deduction).

CREATE TABLE payroll_lines (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    payroll_id UUID NOT NULL REFERENCES payroll(id) ON DELETE CASCADE,

    -- Line type categorization
    line_type VARCHAR(50) NOT NULL
        CHECK (line_type IN (
            -- Earnings
            'base_salary',
            'allowance',
            'overtime',
            'bonus',
            'commission',
            'back_pay',
            -- Deductions
            'tax',
            'insurance',
            'loan_repayment',
            'absence_deduction',
            'late_deduction',
            'advance_recovery',
            'other_deduction'
        )),

    -- Human-readable label (e.g. "Housing Allowance", "Income Tax")
    label VARCHAR(255) NOT NULL,

    -- Amount: positive for earnings, negative for deductions
    amount DECIMAL(12, 2) NOT NULL CHECK (amount <> 0),

    -- Calculation metadata (for audit/transparency)
    quantity DECIMAL(10, 4),                -- e.g. overtime hours, absence days
    rate DECIMAL(10, 4),                    -- e.g. hourly rate, per-day deduction
    notes TEXT,

    -- Ordering within the payslip
    sort_order INT NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    -- Earnings must be positive, deductions must be negative
    CHECK (
        (line_type IN ('base_salary', 'allowance', 'overtime', 'bonus', 'commission', 'back_pay')
            AND amount > 0)
        OR
        (line_type IN ('tax', 'insurance', 'loan_repayment', 'absence_deduction',
                        'late_deduction', 'advance_recovery', 'other_deduction')
            AND amount < 0)
    )
);

-- FIX #3: Prevent duplicate logical payroll lines per payslip.
-- A given payroll record should not have two lines with the same (line_type, label).
-- For example, two separate 'allowance' / 'Housing Allowance' lines would be a bug.
ALTER TABLE payroll_lines
    ADD CONSTRAINT uq_payroll_lines_no_duplicates
    UNIQUE (payroll_id, line_type, label);

COMMENT ON CONSTRAINT uq_payroll_lines_no_duplicates ON payroll_lines IS
    'Prevents duplicate logical lines within the same payslip. '
    'A payroll record cannot have two lines with the same (line_type, label) combination.';

COMMENT ON TABLE payroll_lines IS
    'Line-item detail for employee payslips (BR-PRL-002). '
    'Each line represents a single salary component. '
    'Earnings are positive; deductions are negative. '
    'SUM(amount) over all lines for a payroll record should equal payroll.net_salary. '
    'Consistency between payroll_lines total and payroll.net_salary is APP-ENFORCED. '
    'Duplicate (payroll_id, line_type, label) combinations are DB-ENFORCED by unique constraint.';
COMMENT ON COLUMN payroll_lines.line_type IS 'Categorization of the salary component. Earnings are positive; deductions are negative.';
COMMENT ON COLUMN payroll_lines.quantity IS 'Optional: number of units (hours, days) used in calculation. For audit trail.';
COMMENT ON COLUMN payroll_lines.rate IS 'Optional: per-unit rate (hourly rate, daily deduction). For audit trail.';


-- ==========================================
-- SECTION 7: Shift Assignments (NEW)
-- ==========================================
-- Implements BR-ATT-002: per-user per-date shift scheduling.
-- users.shift_id provides the default; this table overrides it for specific dates/ranges.

CREATE TABLE shift_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shift_id UUID NOT NULL REFERENCES shifts(id) ON DELETE CASCADE,

    -- Assignment period
    effective_date DATE NOT NULL,
    end_date DATE,                          -- NULL = indefinite (until superseded)

    -- Who assigned
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Lifecycle
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (end_date IS NULL OR end_date >= effective_date)
);

-- FIX #5: Prevent overlapping shift assignments for the same user.
-- Uses GiST exclusion constraint. For open-ended assignments (end_date IS NULL),
-- we use 'infinity' as the upper bound so the exclusion constraint works correctly.
-- btree_gist extension was already created in 003_financial_controls.sql.
ALTER TABLE shift_assignments
    ADD CONSTRAINT excl_shift_assignments_no_overlap
    EXCLUDE USING GIST (
        user_id WITH =,
        daterange(effective_date, COALESCE(end_date, '9999-12-31'::DATE), '[]') WITH &&
    );

COMMENT ON CONSTRAINT excl_shift_assignments_no_overlap ON shift_assignments IS
    'Prevents overlapping shift assignments for the same user. '
    'Open-ended assignments (end_date IS NULL) use 9999-12-31 as effective upper bound. '
    'Uses daterange with inclusive bounds [effective_date, end_date].';

COMMENT ON TABLE shift_assignments IS
    'Per-user shift scheduling (BR-ATT-002). Overrides users.shift_id for specific date ranges. '
    'If a user has no assignment for a given date, the default users.shift_id applies. '
    'Overlapping assignments for the same user are DB-ENFORCED by exclusion constraint.';


-- ==========================================
-- SECTION 8: ALTER attendance — Shift & Overtime Linkage
-- ==========================================
-- Implements BR-ATT-002 (shift matching) and BR-ATT-003 (overtime tracking).

ALTER TABLE attendance
    ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS shift_assignment_id UUID REFERENCES shift_assignments(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS worked_hours DECIMAL(6, 2)
        CHECK (worked_hours IS NULL OR worked_hours >= 0),
    ADD COLUMN IF NOT EXISTS overtime_hours DECIMAL(6, 2) DEFAULT 0.00
        CHECK (overtime_hours IS NULL OR overtime_hours >= 0),
    ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0
        CHECK (late_minutes IS NULL OR late_minutes >= 0),
    ADD COLUMN IF NOT EXISTS early_departure_minutes INT DEFAULT 0
        CHECK (early_departure_minutes IS NULL OR early_departure_minutes >= 0),
    ADD COLUMN IF NOT EXISTS source VARCHAR(50) DEFAULT 'manual'
        CHECK (source IS NULL OR source IN ('manual', 'biometric', 'gps', 'web', 'mobile')),
    ADD COLUMN IF NOT EXISTS is_manually_adjusted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS adjustment_approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

-- FIX #4: Explicit documentation of attendance computed field maintenance.
COMMENT ON COLUMN attendance.shift_id IS
    'APPLICATION-MAINTAINED. Shift that was active for this attendance record. '
    'Resolved by the service layer from shift_assignments (if exists for user+date) '
    'or falling back to users.shift_id. Set on clock-in or attendance creation.';
COMMENT ON COLUMN attendance.worked_hours IS
    'APPLICATION-MAINTAINED. Total hours worked = clock_out - clock_in (excluding breaks). '
    'Calculated by the service layer on clock-out or when attendance is finalized. '
    'NOT a DB-generated column. The application MUST update this on any clock time change.';
COMMENT ON COLUMN attendance.overtime_hours IS
    'APPLICATION-MAINTAINED. Hours exceeding shift duration or daily max (BR-ATT-003). '
    'Calculated as: worked_hours - shift.regular_hours (if shift linked), '
    'or worked_hours - workspace.daily_max_hours. '
    'Overtime rate multiplier is workspace-configurable (default 1.5x). '
    'NOT a DB-generated column. Set by the service layer during attendance finalization.';
COMMENT ON COLUMN attendance.late_minutes IS
    'APPLICATION-MAINTAINED. Minutes late from shift start time, after subtracting '
    'the shift grace_period_minutes. Zero if not late or no shift linked. '
    'Calculated as: MAX(0, clock_in_time - shift.start_time - grace_period). '
    'NOT a DB-generated column. Set by the service layer on clock-in.';
COMMENT ON COLUMN attendance.early_departure_minutes IS
    'APPLICATION-MAINTAINED. Minutes departed before shift end time. '
    'Calculated as: MAX(0, shift.end_time - clock_out_time). '
    'NOT a DB-generated column. Set by the service layer on clock-out.';
COMMENT ON COLUMN attendance.source IS 'How check-in was recorded: manual, biometric, gps, web, mobile (BR-ATT-001). Set at creation time.';
COMMENT ON COLUMN attendance.is_manually_adjusted IS
    'TRUE if record was manually corrected (BR-ATT-005). '
    'Requires manager approval (adjustment_approved_by). '
    'Manually adjusted records are flagged for payroll review.';

-- Backfill updated_at for existing attendance records
UPDATE attendance SET updated_at = COALESCE(check_in, CURRENT_TIMESTAMP) WHERE updated_at IS NULL;
ALTER TABLE attendance ALTER COLUMN updated_at SET NOT NULL;


-- ==========================================
-- SECTION 9: ALTER leaves — Leave Type FK
-- ==========================================
-- Adds a leave_type_id FK to the legacy leaves table for forward compatibility.
-- The VARCHAR leave_type column is preserved; both coexist.

ALTER TABLE leaves
    ADD COLUMN IF NOT EXISTS leave_type_id UUID REFERENCES leave_types(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

COMMENT ON COLUMN leaves.leave_type_id IS 'FK to leave_types. Coexists with legacy leave_type VARCHAR for backward compatibility.';

-- Backfill updated_at
UPDATE leaves SET updated_at = CURRENT_TIMESTAMP WHERE updated_at IS NULL;
ALTER TABLE leaves ALTER COLUMN updated_at SET NOT NULL;


-- ==========================================
-- SECTION 10: updated_at Triggers
-- ==========================================
-- Reuses existing update_timestamp() function from base schema.

CREATE TRIGGER trg_leave_types_updated
    BEFORE UPDATE ON leave_types
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_leave_balances_updated
    BEFORE UPDATE ON leave_balances
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_leave_requests_updated
    BEFORE UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_payroll_runs_updated
    BEFORE UPDATE ON payroll_runs
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_shift_assignments_updated
    BEFORE UPDATE ON shift_assignments
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- attendance: add updated_at trigger (base schema lacked updated_at column)
CREATE TRIGGER trg_attendance_updated
    BEFORE UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- leaves: add updated_at trigger (base schema lacked updated_at column)
CREATE TRIGGER trg_leaves_updated
    BEFORE UPDATE ON leaves
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 11: Indexes
-- ==========================================

-- Leave types
CREATE INDEX idx_leave_types_workspace ON leave_types(workspace_id);
CREATE INDEX idx_leave_types_active ON leave_types(workspace_id)
    WHERE is_active = TRUE;

-- Leave balances
CREATE INDEX idx_leave_balances_workspace ON leave_balances(workspace_id);
CREATE INDEX idx_leave_balances_user ON leave_balances(user_id);
CREATE INDEX idx_leave_balances_type ON leave_balances(leave_type_id);
-- Hot path: get all balances for a user in a fiscal year
CREATE INDEX idx_leave_balances_user_year ON leave_balances(workspace_id, user_id, fiscal_year);

-- Leave requests
CREATE INDEX idx_leave_requests_workspace ON leave_requests(workspace_id);
CREATE INDEX idx_leave_requests_user ON leave_requests(user_id);
CREATE INDEX idx_leave_requests_type ON leave_requests(leave_type_id);
CREATE INDEX idx_leave_requests_status ON leave_requests(status);
CREATE INDEX idx_leave_requests_dates ON leave_requests(start_date, end_date);
-- Hot path: pending requests for approval
CREATE INDEX idx_leave_requests_pending ON leave_requests(workspace_id, status)
    WHERE status IN ('submitted');
-- Hot path: detect overlapping requests for same user
CREATE INDEX idx_leave_requests_overlap ON leave_requests(workspace_id, user_id, start_date, end_date)
    WHERE status NOT IN ('rejected', 'cancelled');
CREATE INDEX idx_leave_requests_approved_by ON leave_requests(approved_by)
    WHERE approved_by IS NOT NULL;

-- Payroll runs
CREATE INDEX idx_payroll_runs_workspace ON payroll_runs(workspace_id);
CREATE INDEX idx_payroll_runs_status ON payroll_runs(status);
CREATE INDEX idx_payroll_runs_period ON payroll_runs(workspace_id, period_start, period_end);
-- Hot path: find the latest run
CREATE INDEX idx_payroll_runs_latest ON payroll_runs(workspace_id, created_at DESC);

-- Payroll (existing table, new column)
CREATE INDEX idx_payroll_run_id ON payroll(payroll_run_id)
    WHERE payroll_run_id IS NOT NULL;

-- Payroll lines
CREATE INDEX idx_payroll_lines_workspace ON payroll_lines(workspace_id);
CREATE INDEX idx_payroll_lines_payroll ON payroll_lines(payroll_id);
CREATE INDEX idx_payroll_lines_type ON payroll_lines(line_type);

-- Shift assignments
CREATE INDEX idx_shift_assignments_workspace ON shift_assignments(workspace_id);
CREATE INDEX idx_shift_assignments_user ON shift_assignments(user_id);
CREATE INDEX idx_shift_assignments_shift ON shift_assignments(shift_id);
CREATE INDEX idx_shift_assignments_dates ON shift_assignments(effective_date, end_date);
-- Hot path: find active assignment for a user on a specific date
CREATE INDEX idx_shift_assignments_active ON shift_assignments(workspace_id, user_id, effective_date)
    WHERE end_date IS NULL;

-- Attendance (new columns)
CREATE INDEX idx_attendance_shift ON attendance(shift_id)
    WHERE shift_id IS NOT NULL;
CREATE INDEX idx_attendance_overtime ON attendance(workspace_id, user_id, date)
    WHERE overtime_hours > 0;
CREATE INDEX idx_attendance_adjusted ON attendance(workspace_id)
    WHERE is_manually_adjusted = TRUE;

-- Leaves (new column)
CREATE INDEX idx_leaves_type_id ON leaves(leave_type_id)
    WHERE leave_type_id IS NOT NULL;


-- ==========================================
-- SECTION 12: Composite Unique Constraints (workspace FK validation)
-- ==========================================

ALTER TABLE leave_types ADD CONSTRAINT uq_leave_types_ws_id UNIQUE (workspace_id, id);
ALTER TABLE leave_balances ADD CONSTRAINT uq_leave_balances_ws_id UNIQUE (workspace_id, id);
ALTER TABLE leave_requests ADD CONSTRAINT uq_leave_requests_ws_id UNIQUE (workspace_id, id);
ALTER TABLE payroll_runs ADD CONSTRAINT uq_payroll_runs_ws_id UNIQUE (workspace_id, id);
ALTER TABLE payroll_lines ADD CONSTRAINT uq_payroll_lines_ws_id UNIQUE (workspace_id, id);
ALTER TABLE shift_assignments ADD CONSTRAINT uq_shift_assignments_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 13: Workspace FK Isolation Triggers
-- ==========================================
-- Ensures child records cannot cross workspace boundaries.

CREATE TRIGGER trg_leave_types_ws_check
    BEFORE INSERT OR UPDATE ON leave_types
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk();

CREATE TRIGGER trg_leave_balances_ws_check
    BEFORE INSERT OR UPDATE ON leave_balances
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,leave_type_id:leave_types'
    );

CREATE TRIGGER trg_leave_requests_ws_check
    BEFORE INSERT OR UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,leave_type_id:leave_types,approved_by:users,rejected_by:users,cancelled_by:users'
    );

CREATE TRIGGER trg_payroll_runs_ws_check
    BEFORE INSERT OR UPDATE ON payroll_runs
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'department_id:departments,branch_id:branches,calculated_by:users,approved_by:users,disbursed_by:users,locked_by:users,journal_entry_id:journal_entries'
    );

CREATE TRIGGER trg_payroll_lines_ws_check
    BEFORE INSERT OR UPDATE ON payroll_lines
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'payroll_id:payroll'
    );

CREATE TRIGGER trg_shift_assignments_ws_check
    BEFORE INSERT OR UPDATE ON shift_assignments
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,shift_id:shifts,assigned_by:users'
    );

-- Update existing attendance workspace check to include new FK columns
DROP TRIGGER IF EXISTS trg_attendance_ws_check ON attendance;
CREATE TRIGGER trg_attendance_ws_check
    BEFORE INSERT OR UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,shift_id:shifts,shift_assignment_id:shift_assignments,adjustment_approved_by:users'
    );

-- Update existing leaves workspace check to include leave_type_id
DROP TRIGGER IF EXISTS trg_leaves_ws_check ON leaves;
CREATE TRIGGER trg_leaves_ws_check
    BEFORE INSERT OR UPDATE ON leaves
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,leave_type_id:leave_types'
    );

-- Update existing payroll workspace check to include payroll_run_id
DROP TRIGGER IF EXISTS trg_payroll_ws_check ON payroll;
CREATE TRIGGER trg_payroll_ws_check
    BEFORE INSERT OR UPDATE ON payroll
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'user_id:users,payroll_run_id:payroll_runs'
    );


-- ==========================================
-- SECTION 14: Row Level Security (RLS)
-- ==========================================

-- leave_types: workspace-scoped
ALTER TABLE leave_types ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_leave_types ON leave_types
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- leave_balances: workspace-scoped
ALTER TABLE leave_balances ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_leave_balances ON leave_balances
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- leave_requests: workspace-scoped
ALTER TABLE leave_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_leave_requests ON leave_requests
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- payroll_runs: workspace-scoped
ALTER TABLE payroll_runs ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_payroll_runs ON payroll_runs
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- payroll_lines: workspace-scoped
ALTER TABLE payroll_lines ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_payroll_lines ON payroll_lines
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- shift_assignments: workspace-scoped
ALTER TABLE shift_assignments ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_shift_assignments ON shift_assignments
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- attendance, leaves, payroll: RLS already enabled in base schema.
-- No changes needed.


-- ==========================================
-- END OF MIGRATION 004
-- ==========================================
-- Validation checklist:
--   [ ] leave_types table exists with accrual/carry-forward/approval config
--   [ ] leave_types has UNIQUE(workspace_id, code) and UNIQUE(workspace_id, name)
--   [ ] leave_balances table exists with per-user per-type per-year tracking
--   [ ] leave_balances has UNIQUE(workspace_id, user_id, leave_type_id, fiscal_year)
--   [ ] leave_balances has CHECK: used <= entitled + carried_forward + GREATEST(manually_adjusted, 0)
--   [ ] leave_requests table exists with full FSM (draft→submitted→approved→rejected→cancelled→completed)
--   [ ] leave_requests has half-day consistency CHECK
--   [ ] leave_requests has approval/rejection/cancellation audit columns
--   [ ] leave_requests has excl_leave_requests_no_overlap exclusion constraint (FIX #1)
--   [ ] leave_requests FSM transitions documented as APP-ENFORCED (FIX #6)
--   [ ] payroll_runs table exists with FSM (draft→calculated→approved→disbursed→locked)
--   [ ] payroll_runs has prerequisite/approval audit CHECK constraints
--   [ ] payroll_runs has trg_payroll_runs_lock_guard trigger preventing locked-run modification (FIX #7)
--   [ ] payroll_runs FSM transitions and dependencies documented
--   [ ] payroll table ALTERed with payroll_run_id FK and status column
--   [ ] payroll_lines table exists with line_type CHECK and sign enforcement
--   [ ] payroll_lines sign convention: earnings > 0, deductions < 0
--   [ ] payroll_lines has uq_payroll_lines_no_duplicates UNIQUE (payroll_id, line_type, label) (FIX #3)
--   [ ] shift_assignments table exists with effective_date/end_date range
--   [ ] shift_assignments has excl_shift_assignments_no_overlap exclusion constraint (FIX #5)
--   [ ] attendance ALTERed with shift_id, overtime_hours, late_minutes, source, is_manually_adjusted
--   [ ] attendance computed fields documented as APPLICATION-MAINTAINED (FIX #4)
--   [ ] attendance.updated_at backfilled and set NOT NULL
--   [ ] leaves ALTERed with leave_type_id FK and updated_at (NOT NULL after backfill)
--   [ ] All new updated_at triggers fire correctly
--   [ ] All new indexes exist (including partial indexes for hot paths)
--   [ ] Composite unique constraints on all new tables
--   [ ] Workspace FK isolation triggers on all new tables
--   [ ] Existing attendance/leaves/payroll WS triggers updated with new FK columns
--   [ ] RLS enabled on leave_types, leave_balances, leave_requests, payroll_runs, payroll_lines, shift_assignments
--   [ ] Application-layer invariants documented: balance checks, overlap prevention, maker-checker, FSM
--   [ ] Payroll persistence approach and attendance/leave dependencies documented in header
--   [ ] prevent_locked_payroll_run_modification() function exists
-- ==========================================
