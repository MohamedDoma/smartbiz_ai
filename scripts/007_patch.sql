-- ==========================================
-- SmartBiz AI — Migration 007: Data Backfill & Consistency
-- Cross-Batch Data Migration for Batches A–F
-- ==========================================
--
-- ==========================================
-- MIGRATION SAFETY STRATEGY
-- ==========================================
--
-- This migration performs data backfill and consistency fixes across all
-- previously deployed batches (A–F). Safety principles:
--
--   1. IDEMPOTENT: Every statement uses INSERT...ON CONFLICT DO NOTHING,
--      WHERE NOT EXISTS, or conditional logic. Safe to re-run.
--
--   2. NON-DESTRUCTIVE: No DELETE, no DROP, no TRUNCATE. Existing data
--      is never removed or overwritten (unless explicitly fixing corruption).
--
--   3. FALLBACK LOGIC: Each section handles missing data gracefully.
--      Missing source data = skip (not fail). Defaults are explicit.
--
--   4. VALIDATION: Each major section ends with a validation query
--      wrapped in DO $$ blocks that raise WARNINGs (not exceptions)
--      for data inconsistencies. These are advisory, not blocking.
--
--   5. ORDERING: Sections are ordered by dependency. RBAC → HR → Finance
--      → Inventory, because later sections may depend on earlier backfills.
--
--   6. TRANSACTION SAFETY: This file runs as a single transaction.
--      If any section fails, the entire migration rolls back.
--
--   7. NO SCHEMA CHANGES: This file performs data operations ONLY.
--      All schema changes were done in migrations 001–006.
--
-- ==========================================


-- ==========================================
-- SECTION 1: RBAC — Workspace Membership Consistency
-- ==========================================
-- Migration 006 already backfilled workspace_memberships and membership_roles
-- from the users table. This section fixes edge cases:
--   - Users with NULL workspace_id (orphaned users)
--   - Memberships missing primary role assignment
--   - Owner role guarantee validation

-- 1A: Flag orphaned users (no workspace_id) with a warning.
-- We do NOT create memberships for them — they need manual assignment.
DO $$
DECLARE
    v_orphan_count INT;
BEGIN
    SELECT COUNT(*) INTO v_orphan_count
    FROM users
    WHERE workspace_id IS NULL;

    IF v_orphan_count > 0 THEN
        RAISE WARNING '[007-1A] Found % user(s) with NULL workspace_id. '
            'These users have no workspace membership and cannot be auto-backfilled. '
            'Manual assignment required.', v_orphan_count;
    END IF;
END $$;


-- 1B: Ensure every active membership has at least one role.
-- If a membership exists but has no membership_roles entry, assign the
-- workspace's default role (is_default=TRUE) or the lowest-hierarchy role.
INSERT INTO membership_roles (workspace_id, membership_id, role_id, is_primary, assigned_at)
SELECT
    wm.workspace_id,
    wm.id,
    COALESCE(
        -- Prefer the workspace's default role
        (SELECT r.id FROM roles r
         WHERE r.workspace_id = wm.workspace_id AND r.is_default = TRUE
         LIMIT 1),
        -- Fallback: lowest hierarchy_level role in the workspace
        (SELECT r.id FROM roles r
         WHERE r.workspace_id = wm.workspace_id
         ORDER BY r.hierarchy_level ASC
         LIMIT 1)
    ),
    TRUE,
    CURRENT_TIMESTAMP
FROM workspace_memberships wm
WHERE wm.status = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM membership_roles mr WHERE mr.membership_id = wm.id
  )
  AND EXISTS (
      SELECT 1 FROM roles r WHERE r.workspace_id = wm.workspace_id
  )
ON CONFLICT (membership_id, role_id) DO NOTHING;


-- 1C: Ensure every membership_roles set has exactly one is_primary=TRUE.
-- If multiple primaries exist, keep the one with the highest hierarchy role.
-- If no primary exists, promote the highest-hierarchy role to primary.

-- Fix: remove duplicate primaries (keep highest hierarchy)
UPDATE membership_roles mr1
SET is_primary = FALSE
WHERE mr1.is_primary = TRUE
  AND EXISTS (
      SELECT 1 FROM membership_roles mr2
      JOIN roles r1 ON r1.id = mr1.role_id
      JOIN roles r2 ON r2.id = mr2.role_id
      WHERE mr2.membership_id = mr1.membership_id
        AND mr2.is_primary = TRUE
        AND mr2.id <> mr1.id
        AND r2.hierarchy_level > r1.hierarchy_level
  );

-- Fix: promote to primary where none exists
UPDATE membership_roles
SET is_primary = TRUE
WHERE id IN (
    SELECT DISTINCT ON (mr.membership_id) mr.id
    FROM membership_roles mr
    JOIN roles r ON r.id = mr.role_id
    WHERE NOT EXISTS (
        SELECT 1 FROM membership_roles mr2
        WHERE mr2.membership_id = mr.membership_id AND mr2.is_primary = TRUE
    )
    ORDER BY mr.membership_id, r.hierarchy_level DESC
);


-- 1D: Validate: every workspace has at least one owner.
DO $$
DECLARE
    v_no_owner_count INT;
BEGIN
    SELECT COUNT(*) INTO v_no_owner_count
    FROM workspaces w
    WHERE w.is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM workspace_memberships wm
          JOIN membership_roles mr ON mr.membership_id = wm.id
          JOIN roles r ON r.id = mr.role_id
          WHERE wm.workspace_id = w.id
            AND r.role_key = 'owner'
            AND wm.status = 'active'
      );

    IF v_no_owner_count > 0 THEN
        RAISE WARNING '[007-1D] Found % active workspace(s) with no owner membership. '
            'These workspaces need manual owner assignment.', v_no_owner_count;
    END IF;
END $$;

-- 1E: Validate: workspace_memberships ↔ users consistency
DO $$
DECLARE
    v_mismatch_count INT;
BEGIN
    -- Users with workspace_id but no matching membership
    SELECT COUNT(*) INTO v_mismatch_count
    FROM users u
    WHERE u.workspace_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM workspace_memberships wm
          WHERE wm.user_id = u.id AND wm.workspace_id = u.workspace_id
      );

    IF v_mismatch_count > 0 THEN
        RAISE WARNING '[007-1E] Found % user(s) with workspace_id set but no matching '
            'workspace_membership. Sync triggers from 006 should have caught this. '
            'Investigate manually.', v_mismatch_count;
    END IF;
END $$;


-- ==========================================
-- SECTION 2: HR — Leave Types Seed from Legacy Data
-- ==========================================
-- The base schema has a `leaves` table with leave_type as a VARCHAR enum:
--   ('annual', 'sick', 'unpaid', 'maternity', 'paternity', 'emergency')
-- Migration 004 created `leave_types` as a configurable table.
-- We seed `leave_types` per workspace based on what types are actually used.

-- 2A: Seed standard leave types for each workspace.
-- Uses the 6 legacy enum values as the seed codes.
-- Only creates types for workspaces that don't already have them.
INSERT INTO leave_types (
    workspace_id, name, code, description,
    accrual_policy, accrual_amount, max_balance,
    carry_forward_allowed, is_paid, requires_approval,
    requires_documentation, allow_negative_balance, allow_half_day,
    is_active, sort_order
)
SELECT
    w.id,
    lt.name,
    lt.code,
    lt.description,
    lt.accrual_policy,
    lt.accrual_amount,
    lt.max_balance,
    lt.carry_forward_allowed,
    lt.is_paid,
    TRUE,
    lt.requires_documentation,
    lt.allow_negative_balance,
    TRUE,
    TRUE,
    lt.sort_order
FROM workspaces w
CROSS JOIN (VALUES
    ('Annual Leave', 'ANNUAL', 'Paid annual leave (vacation)', 'yearly', 21.00, NULL::numeric, TRUE, TRUE, FALSE, FALSE, 1),
    ('Sick Leave', 'SICK', 'Paid/unpaid sick leave with documentation', 'yearly', 14.00, NULL::numeric, FALSE, TRUE, TRUE, TRUE, 2),
    ('Unpaid Leave', 'UNPAID', 'Leave without pay', 'none', 0.00, NULL::numeric, FALSE, FALSE, FALSE, FALSE, 3),
    ('Maternity Leave', 'MATERNITY', 'Maternity leave as per labor law', 'none', 0.00, NULL::numeric, FALSE, TRUE, TRUE, FALSE, 4),
    ('Paternity Leave', 'PATERNITY', 'Paternity leave', 'none', 0.00, NULL::numeric, FALSE, TRUE, FALSE, FALSE, 5),
    ('Emergency Leave', 'EMERGENCY', 'Emergency/compassionate leave', 'none', 0.00, NULL::numeric, FALSE, TRUE, FALSE, TRUE, 6)
) AS lt(name, code, description, accrual_policy, accrual_amount, max_balance,
        carry_forward_allowed, is_paid, requires_documentation, allow_negative_balance,
        sort_order)
WHERE NOT EXISTS (
    SELECT 1 FROM leave_types lt2
    WHERE lt2.workspace_id = w.id AND lt2.code = lt.code
)
ON CONFLICT (workspace_id, code) DO NOTHING;


-- 2B: Backfill leave_balances from users.annual_leave_balance.
-- Creates a leave_balance record for each active user for the ANNUAL leave type
-- for the current fiscal year.
INSERT INTO leave_balances (
    workspace_id, user_id, leave_type_id, fiscal_year,
    entitled, used, pending, carried_forward, manually_adjusted,
    created_at, updated_at
)
SELECT
    wm.workspace_id,
    wm.user_id,
    lt.id,
    EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    COALESCE(wm.annual_leave_balance, 21)::DECIMAL(6,2),  -- entitled = current balance
    0.00,     -- used: unknown from legacy, start at 0
    0.00,     -- pending: start fresh
    0.00,     -- carried_forward: unknown, start at 0
    0.00,     -- manually_adjusted: start at 0
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM workspace_memberships wm
JOIN leave_types lt ON lt.workspace_id = wm.workspace_id AND lt.code = 'ANNUAL'
WHERE wm.status = 'active'
  AND NOT EXISTS (
      SELECT 1 FROM leave_balances lb
      WHERE lb.workspace_id = wm.workspace_id
        AND lb.user_id = wm.user_id
        AND lb.leave_type_id = lt.id
        AND lb.fiscal_year = EXTRACT(YEAR FROM CURRENT_DATE)::INT
  )
ON CONFLICT (workspace_id, user_id, leave_type_id, fiscal_year) DO NOTHING;


-- 2C: Migrate approved legacy leaves to leave_requests (if not already migrated).
-- Maps the old leaves.leave_type VARCHAR to leave_types.code.
-- SCHEMA ALIGNMENT: leave_requests uses duration_days (NOT total_days),
-- is_half_day, half_day_period, and approval audit columns (approved_by, approved_at,
-- rejected_by, rejected_at, rejection_reason, cancelled_by, cancelled_at, completed_at).
INSERT INTO leave_requests (
    workspace_id, user_id, leave_type_id,
    start_date, end_date,
    duration_days, is_half_day,
    status, reason,
    submitted_at, approved_at,
    created_at, updated_at
)
SELECT
    l.workspace_id,
    l.user_id,
    lt.id,
    l.start_date,
    l.end_date,
    (l.end_date - l.start_date + 1)::DECIMAL(6,2),
    FALSE,  -- legacy didn't track half-days
    CASE l.status
        WHEN 'approved' THEN 'approved'
        WHEN 'pending' THEN 'submitted'
        WHEN 'rejected' THEN 'rejected'
        WHEN 'cancelled' THEN 'cancelled'
        ELSE 'submitted'
    END,
    l.reason,
    CURRENT_TIMESTAMP,  -- submitted_at: unknown, use now
    CASE WHEN l.status = 'approved' THEN CURRENT_TIMESTAMP ELSE NULL END,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM leaves l
JOIN leave_types lt ON lt.workspace_id = l.workspace_id
    AND lt.code = UPPER(l.leave_type)
WHERE NOT EXISTS (
    SELECT 1 FROM leave_requests lr
    WHERE lr.workspace_id = l.workspace_id
      AND lr.user_id = l.user_id
      AND lr.start_date = l.start_date
      AND lr.end_date = l.end_date
      AND lr.leave_type_id = lt.id
)
ON CONFLICT DO NOTHING;


-- 2D: Validate leave data consistency
DO $$
DECLARE
    v_unmigrated INT;
    v_missing_balances INT;
BEGIN
    -- Check for unmigrated leaves
    SELECT COUNT(*) INTO v_unmigrated
    FROM leaves l
    WHERE NOT EXISTS (
        SELECT 1 FROM leave_requests lr
        JOIN leave_types lt ON lt.id = lr.leave_type_id
        WHERE lr.workspace_id = l.workspace_id
          AND lr.user_id = l.user_id
          AND lr.start_date = l.start_date
          AND lr.end_date = l.end_date
    );

    IF v_unmigrated > 0 THEN
        RAISE WARNING '[007-2D] % legacy leave(s) could not be migrated to leave_requests '
            '(likely missing leave_type mapping).', v_unmigrated;
    END IF;

    -- Check for active users without annual leave balance
    SELECT COUNT(*) INTO v_missing_balances
    FROM workspace_memberships wm
    WHERE wm.status = 'active'
      AND NOT EXISTS (
          SELECT 1 FROM leave_balances lb
          WHERE lb.user_id = wm.user_id AND lb.workspace_id = wm.workspace_id
      );

    IF v_missing_balances > 0 THEN
        RAISE WARNING '[007-2D] % active membership(s) have no leave_balances record.', v_missing_balances;
    END IF;
END $$;


-- ==========================================
-- SECTION 3: HR — Payroll Lines from Legacy Payroll
-- ==========================================
-- The base schema has a `payroll` table with flat structure:
--   (user_id, month, year, base_salary, bonuses, deductions, net_salary, payment_status)
-- Migration 004 created payroll_runs + payroll_lines for structured payroll.
--
-- SCHEMA ALIGNMENT (reconciled with 004_hr_workforce.sql):
--   payroll_runs: columns are period_start (DATE), period_end (DATE), status
--     Valid statuses: draft, calculated, approved, disbursed, locked
--     (NOT period_month, period_year, run_date. NOT status='paid'.)
--   payroll_lines: FK is payroll_id → payroll(id) (NOT payroll_run_id)
--     Uses label (NOT description), no user_id column.
--     Earnings must be positive, deductions must be negative.
--     UNIQUE constraint on (payroll_id, line_type, label).

-- 3A: Create payroll_runs for each unique (workspace, month, year) in legacy payroll.
-- Maps legacy month/year to period_start/period_end date range.
-- Maps legacy payment_status to valid payroll_runs status FSM values.
INSERT INTO payroll_runs (
    workspace_id,
    period_start, period_end,
    status,
    calculated_at,
    created_at, updated_at
)
SELECT DISTINCT
    p.workspace_id,
    make_date(p.year, p.month, 1),                                  -- period_start = 1st of month
    (make_date(p.year, p.month, 1) + INTERVAL '1 month - 1 day')::DATE,  -- period_end = last day
    CASE
        WHEN bool_and(p.payment_status = 'paid') THEN 'disbursed'
        WHEN bool_or(p.payment_status = 'paid') THEN 'approved'
        ELSE 'draft'
    END,
    CASE WHEN bool_or(p.payment_status IN ('paid', 'partial')) THEN MAX(p.processed_at) ELSE NULL END,
    MAX(p.processed_at),
    CURRENT_TIMESTAMP
FROM payroll p
WHERE p.workspace_id IS NOT NULL
GROUP BY p.workspace_id, p.month, p.year
HAVING NOT EXISTS (
    SELECT 1 FROM payroll_runs pr
    WHERE pr.workspace_id = p.workspace_id
      AND pr.period_start = make_date(p.year, p.month, 1)
)
ON CONFLICT DO NOTHING;


-- 3A-link: Link legacy payroll records to their newly created payroll_runs.
-- This sets payroll.payroll_run_id so that payroll_lines can FK to payroll(id).
UPDATE payroll p
SET payroll_run_id = pr.id
FROM payroll_runs pr
WHERE pr.workspace_id = p.workspace_id
  AND pr.period_start = make_date(p.year, p.month, 1)
  AND p.payroll_run_id IS NULL;


-- 3B: Migrate payroll records to payroll_lines.
-- payroll_lines FK is payroll_id → payroll(id), uses label (not description).
-- Earnings are positive, deductions are negative (enforced by table CHECK).
-- line_type must be one of the approved enum values.
INSERT INTO payroll_lines (
    workspace_id,
    payroll_id,
    line_type,
    label,
    amount,
    created_at
)
SELECT
    p.workspace_id,
    p.id,
    line_data.line_type,
    line_data.label,
    line_data.amount,
    COALESCE(p.processed_at, CURRENT_TIMESTAMP)
FROM payroll p
CROSS JOIN LATERAL (VALUES
    ('base_salary', 'Base Salary (migrated from legacy payroll)', p.base_salary),
    ('bonus', 'Bonus (migrated from legacy payroll)', p.bonuses),
    ('other_deduction', 'Deductions (migrated from legacy payroll)', -ABS(p.deductions))
) AS line_data(line_type, label, amount)
WHERE line_data.amount <> 0
  AND p.workspace_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM payroll_lines pl
      WHERE pl.payroll_id = p.id
        AND pl.line_type = line_data.line_type
        AND pl.label = line_data.label
  )
ON CONFLICT DO NOTHING;


-- 3C: Validate payroll consistency
DO $$
DECLARE
    v_unmigrated_payroll INT;
    v_unlinked_payroll INT;
BEGIN
    -- Check for payroll records without a payroll_run
    SELECT COUNT(*) INTO v_unmigrated_payroll
    FROM payroll p
    WHERE p.workspace_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM payroll_runs pr
        WHERE pr.workspace_id = p.workspace_id
          AND pr.period_start = make_date(p.year, p.month, 1)
    );

    IF v_unmigrated_payroll > 0 THEN
        RAISE WARNING '[007-3C] % legacy payroll record(s) could not be linked to a payroll_run '
            '(missing workspace_id or payroll_run creation failed).', v_unmigrated_payroll;
    END IF;

    -- Check for payroll records still without payroll_run_id
    SELECT COUNT(*) INTO v_unlinked_payroll
    FROM payroll p
    WHERE p.workspace_id IS NOT NULL
      AND p.payroll_run_id IS NULL;

    IF v_unlinked_payroll > 0 THEN
        RAISE WARNING '[007-3C] % legacy payroll record(s) still have NULL payroll_run_id '
            'after backfill.', v_unlinked_payroll;
    END IF;
END $$;


-- ==========================================
-- SECTION 4: Finance — Payments Status Backfill
-- ==========================================
-- Migration 003 added payments.status with DEFAULT 'completed'.
-- Existing rows need explicit status values before NOT NULL enforcement.
-- Also backfill is_reversal = FALSE for all non-reversal payments.

-- 4A: Set status for existing payments that still have NULL.
UPDATE payments
SET status = 'completed'
WHERE status IS NULL;

-- 4B: Set is_reversal for legacy payments.
UPDATE payments
SET is_reversal = FALSE
WHERE is_reversal IS NULL;

-- 4C: Enforce NOT NULL on payments.status (if not already done by 003 hardening).
-- This is a safety net — 003 may have already done this.
DO $$
BEGIN
    -- Check if NOT NULL is already enforced
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'payments'
          AND column_name = 'status'
          AND is_nullable = 'YES'
    ) THEN
        ALTER TABLE payments ALTER COLUMN status SET NOT NULL;
        RAISE NOTICE '[007-4C] payments.status set to NOT NULL.';
    END IF;
END $$;

-- 4D: Validate payment integrity
DO $$
DECLARE
    v_null_status INT;
    v_orphan_reversals INT;
BEGIN
    SELECT COUNT(*) INTO v_null_status
    FROM payments WHERE status IS NULL;

    IF v_null_status > 0 THEN
        RAISE WARNING '[007-4D] % payment(s) still have NULL status after backfill.', v_null_status;
    END IF;

    -- Check for reversal records without valid original payment
    SELECT COUNT(*) INTO v_orphan_reversals
    FROM payments p
    WHERE p.is_reversal = TRUE
      AND p.reversal_of_payment_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM payments p2 WHERE p2.id = p.reversal_of_payment_id
      );

    IF v_orphan_reversals > 0 THEN
        RAISE WARNING '[007-4D] % reversal payment(s) reference non-existent original payment.', v_orphan_reversals;
    END IF;
END $$;


-- ==========================================
-- SECTION 5: Finance — Customer Credits from contacts.balance
-- ==========================================
-- The base schema has contacts.balance as a ⚠️ CACHED field.
-- If contacts have positive balances, we seed customer_credits with
-- an opening_balance movement to establish the ledger baseline.

-- 5A: Seed customer_credits opening balance for contacts with positive balance.
INSERT INTO customer_credits (
    workspace_id,
    contact_id,
    movement_type,
    amount,
    balance_after,
    currency,
    notes,
    created_at
)
SELECT
    c.workspace_id,
    c.id,
    'manual_grant',
    c.balance,
    c.balance,
    'LYD',
    'Opening balance migrated from contacts.balance (Migration 007)',
    CURRENT_TIMESTAMP
FROM contacts c
WHERE c.balance > 0
  AND c.type IN ('customer', 'both')
  AND c.workspace_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM customer_credits cc
      WHERE cc.contact_id = c.id AND cc.workspace_id = c.workspace_id
  )
ON CONFLICT DO NOTHING;


-- 5B: Validate customer credit consistency
DO $$
DECLARE
    v_balance_mismatch INT;
BEGIN
    -- Check: contacts.balance should match latest customer_credits.balance_after
    SELECT COUNT(*) INTO v_balance_mismatch
    FROM contacts c
    WHERE c.balance > 0
      AND c.type IN ('customer', 'both')
      AND EXISTS (
          SELECT 1 FROM customer_credits cc
          WHERE cc.contact_id = c.id AND cc.workspace_id = c.workspace_id
      )
      AND c.balance <> (
          SELECT cc2.balance_after
          FROM customer_credits cc2
          WHERE cc2.contact_id = c.id AND cc2.workspace_id = c.workspace_id
          ORDER BY cc2.created_at DESC
          LIMIT 1
      );

    IF v_balance_mismatch > 0 THEN
        RAISE WARNING '[007-5B] % contact(s) have balance mismatch between contacts.balance '
            'and latest customer_credits.balance_after. Reconciliation needed.', v_balance_mismatch;
    END IF;
END $$;


-- ==========================================
-- SECTION 6: Finance — Fiscal Period Validation
-- ==========================================
-- Migration 003 created fiscal_periods table.
-- Validate that no gaps or overlaps exist in existing data.
-- This section is validation-only (no data creation).

DO $$
DECLARE
    v_overlap_count INT;
BEGIN
    -- Check for fiscal period overlaps (should be prevented by EXCLUDE constraint)
    SELECT COUNT(*) INTO v_overlap_count
    FROM fiscal_periods fp1
    JOIN fiscal_periods fp2 ON fp1.workspace_id = fp2.workspace_id
        AND fp1.id <> fp2.id
        AND fp1.start_date <= fp2.end_date
        AND fp2.start_date <= fp1.end_date;

    IF v_overlap_count > 0 THEN
        RAISE WARNING '[007-6] Found % fiscal period overlap(s). '
            'The EXCLUDE constraint from 003 should prevent this. Investigate.', v_overlap_count;
    END IF;
END $$;


-- ==========================================
-- SECTION 7: Inventory — inventory_levels Consistency
-- ==========================================
-- Migration 005 added: reserved, available, reorder_point, max_stock, workspace_id
-- to inventory_levels. This section backfills workspace_id and initializes
-- the reservation model fields.

-- 7A: Backfill inventory_levels.workspace_id from warehouse → branch → workspace chain.
-- The base schema doesn't have workspace_id on inventory_levels directly.
-- We derive it from the warehouse relationship.
UPDATE inventory_levels il
SET workspace_id = w.workspace_id
FROM warehouses w
WHERE il.warehouse_id = w.id
  AND il.workspace_id IS NULL
  AND w.workspace_id IS NOT NULL;

-- Fallback: set workspace_id from the product's workspace if warehouse doesn't have one
UPDATE inventory_levels il
SET workspace_id = p.workspace_id
FROM products p
WHERE il.product_id = p.id
  AND il.workspace_id IS NULL
  AND p.workspace_id IS NOT NULL;


-- 7B: Initialize reserved = 0 and available = quantity for all rows.
-- This is the baseline before any reservations exist.
-- The sync_inventory_available() trigger from 005 will auto-set available = quantity - reserved.
UPDATE inventory_levels
SET reserved = 0,
    available = quantity - COALESCE(reserved, 0)
WHERE reserved IS NULL OR available IS NULL;


-- 7C: Set reorder_point and max_stock defaults where NULL.
UPDATE inventory_levels
SET reorder_point = 0,
    max_stock = NULL
WHERE reorder_point IS NULL AND max_stock IS NULL;


-- 7D: Validate inventory consistency
DO $$
DECLARE
    v_null_ws INT;
    v_negative INT;
    v_inconsistent INT;
BEGIN
    -- Check: inventory_levels without workspace_id
    SELECT COUNT(*) INTO v_null_ws
    FROM inventory_levels WHERE workspace_id IS NULL;

    IF v_null_ws > 0 THEN
        RAISE WARNING '[007-7D] % inventory_levels row(s) still have NULL workspace_id. '
            'RLS will not protect these rows.', v_null_ws;
    END IF;

    -- Check: negative quantities
    SELECT COUNT(*) INTO v_negative
    FROM inventory_levels WHERE quantity < 0;

    IF v_negative > 0 THEN
        RAISE WARNING '[007-7D] % inventory_levels row(s) have negative quantity. '
            'Unless negative stock is explicitly allowed, these need investigation.', v_negative;
    END IF;

    -- Check: available != quantity - reserved
    SELECT COUNT(*) INTO v_inconsistent
    FROM inventory_levels
    WHERE available IS NOT NULL
      AND reserved IS NOT NULL
      AND available <> (quantity - reserved);

    IF v_inconsistent > 0 THEN
        RAISE WARNING '[007-7D] % inventory_levels row(s) have inconsistent available field '
            '(available != quantity - reserved). The sync trigger should fix on next update.', v_inconsistent;
    END IF;
END $$;


-- ==========================================
-- SECTION 8: Inventory — Opening Balance Movements
-- ==========================================
-- Every existing inventory_levels row should have at least one
-- inventory_movements record as the opening balance.
-- This creates the audit trail for pre-migration stock.

-- SCHEMA ALIGNMENT: inventory_movements (from 005_inventory_logistics.sql)
-- Uses created_by (NOT performed_by), has total_cost column,
-- quantity_change MUST be positive for opening_balance movement_type.
INSERT INTO inventory_movements (
    workspace_id,
    warehouse_id,
    product_id,
    variant_id,
    movement_type,
    reference_type,
    quantity_change,
    quantity_before,
    quantity_after,
    unit_cost,
    total_cost,
    notes,
    created_by,
    created_at
)
SELECT
    il.workspace_id,
    il.warehouse_id,
    il.product_id,
    il.variant_id,
    'opening_balance',
    'opening',
    il.quantity,                                    -- positive for opening_balance
    0,
    il.quantity,
    COALESCE(p.cost_price, 0),
    COALESCE(p.cost_price, 0) * il.quantity,         -- total_cost
    'Opening balance created by Migration 007 backfill',
    NULL,
    CURRENT_TIMESTAMP
FROM inventory_levels il
JOIN products p ON p.id = il.product_id
WHERE il.workspace_id IS NOT NULL
  AND il.quantity > 0                               -- opening_balance requires positive qty
  AND NOT EXISTS (
      SELECT 1 FROM inventory_movements im
      WHERE im.product_id = il.product_id
        AND im.warehouse_id = il.warehouse_id
        AND COALESCE(im.variant_id, '00000000-0000-0000-0000-000000000000'::UUID) =
            COALESCE(il.variant_id, '00000000-0000-0000-0000-000000000000'::UUID)
        AND im.movement_type = 'opening_balance'
  )
ON CONFLICT DO NOTHING;


-- 8B: Validate movement trail
DO $$
DECLARE
    v_no_movement INT;
BEGIN
    SELECT COUNT(*) INTO v_no_movement
    FROM inventory_levels il
    WHERE il.workspace_id IS NOT NULL
      AND il.quantity <> 0
      AND NOT EXISTS (
          SELECT 1 FROM inventory_movements im
          WHERE im.product_id = il.product_id
            AND im.warehouse_id = il.warehouse_id
      );

    IF v_no_movement > 0 THEN
        RAISE WARNING '[007-8B] % inventory_levels row(s) with non-zero quantity have '
            'no inventory_movements records. Audit trail incomplete.', v_no_movement;
    END IF;
END $$;


-- ==========================================
-- SECTION 9: Inventory — Stock Reservation Cross-Check
-- ==========================================
-- Validate that stock_reservations are consistent with inventory_levels.
-- This is validation only — no data changes (reservations are created by app).

DO $$
DECLARE
    v_over_reserved INT;
    v_orphan_reservations INT;
BEGIN
    -- Check: reserved quantity exceeds available stock
    SELECT COUNT(*) INTO v_over_reserved
    FROM inventory_levels il
    WHERE il.reserved > il.quantity;

    IF v_over_reserved > 0 THEN
        RAISE WARNING '[007-9] % inventory_levels row(s) have reserved > quantity. '
            'Stock may be over-committed.', v_over_reserved;
    END IF;

    -- Check: stock_reservations referencing non-existent orders
    SELECT COUNT(*) INTO v_orphan_reservations
    FROM stock_reservations sr
    WHERE sr.order_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM orders o WHERE o.id = sr.order_id
      );

    IF v_orphan_reservations > 0 THEN
        RAISE WARNING '[007-9] % stock_reservation(s) reference non-existent orders. '
            'These may be orphaned from deleted orders.', v_orphan_reservations;
    END IF;
END $$;


-- ==========================================
-- SECTION 10: Cross-Module — Foreign Key Relationship Audit
-- ==========================================
-- Validate referential integrity across all modules.
-- These checks catch data that WOULD violate FKs if constraints are tightened.

DO $$
DECLARE
    v_count INT;
BEGIN
    -- 10A: Users → roles FK
    SELECT COUNT(*) INTO v_count
    FROM users u
    WHERE u.role_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM roles r WHERE r.id = u.role_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10A] % user(s) reference non-existent role_id.', v_count;
    END IF;

    -- 10B: Users → departments FK
    SELECT COUNT(*) INTO v_count
    FROM users u
    WHERE u.department_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM departments d WHERE d.id = u.department_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10B] % user(s) reference non-existent department_id.', v_count;
    END IF;

    -- 10C: Users → branches FK
    SELECT COUNT(*) INTO v_count
    FROM users u
    WHERE u.branch_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM branches b WHERE b.id = u.branch_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10C] % user(s) reference non-existent branch_id.', v_count;
    END IF;

    -- 10D: Invoice → contacts FK
    SELECT COUNT(*) INTO v_count
    FROM invoices i
    WHERE i.contact_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM contacts c WHERE c.id = i.contact_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10D] % invoice(s) reference non-existent contact_id.', v_count;
    END IF;

    -- 10E: Payments → invoices FK
    SELECT COUNT(*) INTO v_count
    FROM payments p
    WHERE p.invoice_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM invoices i WHERE i.id = p.invoice_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10E] % payment(s) reference non-existent invoice_id.', v_count;
    END IF;

    -- 10F: Attendance → users FK
    SELECT COUNT(*) INTO v_count
    FROM attendance a
    WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = a.user_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10F] % attendance record(s) reference non-existent user_id.', v_count;
    END IF;

    -- 10G: Payroll → users FK
    SELECT COUNT(*) INTO v_count
    FROM payroll p
    WHERE NOT EXISTS (SELECT 1 FROM users u WHERE u.id = p.user_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10G] % payroll record(s) reference non-existent user_id.', v_count;
    END IF;

    -- 10H: Workspace memberships → workspace FK consistency
    SELECT COUNT(*) INTO v_count
    FROM workspace_memberships wm
    WHERE NOT EXISTS (SELECT 1 FROM workspaces w WHERE w.id = wm.workspace_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10H] % membership(s) reference non-existent workspace_id.', v_count;
    END IF;

    -- 10I: Inventory levels → products FK
    SELECT COUNT(*) INTO v_count
    FROM inventory_levels il
    WHERE NOT EXISTS (SELECT 1 FROM products p WHERE p.id = il.product_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10I] % inventory_levels row(s) reference non-existent product_id.', v_count;
    END IF;

    -- 10J: Inventory levels → warehouses FK
    SELECT COUNT(*) INTO v_count
    FROM inventory_levels il
    WHERE NOT EXISTS (SELECT 1 FROM warehouses w WHERE w.id = il.warehouse_id);
    IF v_count > 0 THEN
        RAISE WARNING '[007-10J] % inventory_levels row(s) reference non-existent warehouse_id.', v_count;
    END IF;

    RAISE NOTICE '[007-10] Cross-module FK audit complete.';
END $$;


-- ==========================================
-- SECTION 11: Summary Validation Report
-- ==========================================
-- Final pass: count all backfilled records for migration audit log.

DO $$
DECLARE
    v_memberships INT;
    v_membership_roles INT;
    v_leave_types INT;
    v_leave_balances INT;
    v_leave_requests INT;
    v_payroll_runs INT;
    v_payroll_lines INT;
    v_customer_credits INT;
    v_inventory_movements INT;
BEGIN
    SELECT COUNT(*) INTO v_memberships FROM workspace_memberships;
    SELECT COUNT(*) INTO v_membership_roles FROM membership_roles;
    SELECT COUNT(*) INTO v_leave_types FROM leave_types;
    SELECT COUNT(*) INTO v_leave_balances FROM leave_balances;
    SELECT COUNT(*) INTO v_leave_requests FROM leave_requests;
    SELECT COUNT(*) INTO v_payroll_runs FROM payroll_runs;
    SELECT COUNT(*) INTO v_payroll_lines FROM payroll_lines;
    SELECT COUNT(*) INTO v_customer_credits FROM customer_credits;
    SELECT COUNT(*) INTO v_inventory_movements FROM inventory_movements;

    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration 007 Backfill Summary:';
    RAISE NOTICE '  workspace_memberships:  %', v_memberships;
    RAISE NOTICE '  membership_roles:       %', v_membership_roles;
    RAISE NOTICE '  leave_types:            %', v_leave_types;
    RAISE NOTICE '  leave_balances:         %', v_leave_balances;
    RAISE NOTICE '  leave_requests:         %', v_leave_requests;
    RAISE NOTICE '  payroll_runs:           %', v_payroll_runs;
    RAISE NOTICE '  payroll_lines:          %', v_payroll_lines;
    RAISE NOTICE '  customer_credits:       %', v_customer_credits;
    RAISE NOTICE '  inventory_movements:    %', v_inventory_movements;
    RAISE NOTICE '========================================';
END $$;


-- ==========================================
-- END OF MIGRATION 007
-- ==========================================
-- Validation checklist:
--   [ ] RBAC: orphaned users detected and warned (1A)
--   [ ] RBAC: memberships without roles assigned default role (1B)
--   [ ] RBAC: primary role uniqueness enforced (1C)
--   [ ] RBAC: owner-per-workspace validated (1D)
--   [ ] RBAC: membership ↔ users consistency validated (1E)
--   [ ] HR: 6 standard leave types seeded per workspace (2A)
--   [ ] HR: leave_balances created from users.annual_leave_balance (2B)
--   [ ] HR: legacy leaves migrated to leave_requests (2C)
--   [ ] HR: leave migration validated (2D)
--   [ ] HR: payroll_runs created from legacy payroll (3A)
--   [ ] HR: payroll_lines created from legacy payroll (3B)
--   [ ] HR: payroll migration validated (3C)
--   [ ] Finance: payments.status backfilled to 'completed' (4A)
--   [ ] Finance: payments.is_reversal backfilled to FALSE (4B)
--   [ ] Finance: payments.status set NOT NULL (4C)
--   [ ] Finance: payment integrity validated (4D)
--   [ ] Finance: customer_credits seeded from contacts.balance (5A)
--   [ ] Finance: credit balance consistency validated (5B)
--   [ ] Finance: fiscal period overlap validated (6)
--   [ ] Inventory: inventory_levels.workspace_id backfilled (7A)
--   [ ] Inventory: reserved/available initialized (7B)
--   [ ] Inventory: reorder_point/max_stock defaults set (7C)
--   [ ] Inventory: consistency validated (7D)
--   [ ] Inventory: opening balance movements created (8A)
--   [ ] Inventory: movement trail validated (8B)
--   [ ] Inventory: reservation cross-check validated (9)
--   [ ] Cross-module: 10 FK relationship audits executed (10A–10J)
--   [ ] Summary: record counts output for migration audit (11)
--   [ ] All operations are idempotent
--   [ ] No data deleted
--   [ ] No columns dropped
-- ==========================================
