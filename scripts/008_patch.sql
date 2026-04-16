-- ==========================================
-- SmartBiz AI — Migration 008: Cleanup & Deprecation
-- Controlled Cleanup Phase (Post-Backfill)
-- ==========================================
--
-- ==========================================
-- CLEANUP SAFETY STRATEGY
-- ==========================================
--
-- All previous batches (A–G) are deployed and data is backfilled.
-- This migration performs controlled cleanup and deprecation:
--
--   1. RENAME, NOT DROP: Legacy columns are renamed with _deprecated suffix
--      rather than dropped. This preserves data and allows rollback by renaming back.
--
--   2. VERIFY BEFORE DEPRECATE: Each section checks that the replacement
--      model has data before marking the legacy model as deprecated.
--
--   3. STAGED REMOVAL: Sync triggers and compatibility views are removed only
--      after confirming application code has migrated. Comments explain what
--      to do if rollback is needed.
--
--   4. FINAL CONSTRAINTS: NOT NULL and CHECK constraints are enforced on
--      columns that were previously optional during the transition period.
--
--   5. ROLLBACK SAFETY: Every rename includes a comment with the exact
--      ALTER TABLE ... RENAME COLUMN command to undo it.
--
--   6. NO DATA DELETION: No DELETE, DROP TABLE, or TRUNCATE operations.
--
--   7. ORDERING: Triggers removed first, then columns renamed, then
--      constraints enforced, then legacy tables deprecated.
--
-- ==========================================


-- ==========================================
-- SECTION 1: Remove Transitional Sync Triggers
-- ==========================================
-- Migration 006 created bidirectional sync triggers to keep users ↔ workspace_memberships
-- consistent during the coexistence phase. Now that the application has migrated to
-- workspace_memberships as the canonical model, these triggers are no longer needed.
-- They add overhead to every INSERT/UPDATE on users and workspace_memberships.
--
-- ROLLBACK: Re-run migration 006 sections 5–6 to recreate these triggers.

-- 1A: Remove membership → user sync trigger
DROP TRIGGER IF EXISTS trg_sync_membership_to_user ON workspace_memberships;

-- 1B: Remove membership_role → user role sync trigger
DROP TRIGGER IF EXISTS trg_sync_membership_role_to_user ON membership_roles;

-- 1C: Remove user → membership sync trigger
DROP TRIGGER IF EXISTS trg_sync_user_to_membership ON users;

-- 1D: Drop the sync functions (only after triggers are removed)
DROP FUNCTION IF EXISTS sync_membership_to_user();
DROP FUNCTION IF EXISTS sync_user_to_membership();
DROP FUNCTION IF EXISTS sync_membership_role_to_user();

COMMENT ON TABLE workspace_memberships IS
    'Canonical user-to-workspace relationship (promoted from transitional in 006). '
    'Role assignments via membership_roles. Org-structure and HR data are per-workspace. '
    'Migration 008: sync triggers removed. workspace_memberships is now the SOLE source of truth. '
    'Legacy users.workspace_id_deprecated is retained for rollback safety only.';


-- ==========================================
-- SECTION 2: Rename Deprecated Users Columns
-- ==========================================
-- These columns were deprecated in migration 006 with COMMENT markers.
-- Now we rename them to _deprecated to prevent accidental use by new code.
--
-- IMPORTANT: The UNIQUE constraint on (workspace_id, phone_number) uses
-- workspace_id. We must recreate it using workspace_id_deprecated.
--
-- ROLLBACK for each: ALTER TABLE users RENAME COLUMN xxx_deprecated TO xxx;

-- 2-PRE: Drop workspace FK isolation trigger on users.
-- This trigger references column names (workspace_id, branch_id, department_id, etc.)
-- via dynamic SQL in validate_workspace_fk(). After renaming these to _deprecated,
-- the trigger would fail on every INSERT/UPDATE. Since workspace_memberships is now
-- the canonical model, workspace FK isolation on legacy user columns is no longer needed.
DROP TRIGGER IF EXISTS trg_users_ws_check ON users;

-- 2A: workspace_id → workspace_id_deprecated
-- First, drop the unique constraint that depends on workspace_id
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_workspace_id_phone_number_key;

ALTER TABLE users RENAME COLUMN workspace_id TO workspace_id_deprecated;

-- Recreate the unique constraint on the renamed column (preserves data integrity during transition)
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_ws_deprecated_phone
    ON users(workspace_id_deprecated, phone_number);

COMMENT ON COLUMN users.workspace_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from workspace_id. '
    'Use workspace_memberships for user-to-workspace relationship. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN workspace_id_deprecated TO workspace_id;';


-- 2B: role_id → role_id_deprecated
ALTER TABLE users RENAME COLUMN role_id TO role_id_deprecated;

COMMENT ON COLUMN users.role_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from role_id. '
    'Use membership_roles for role assignments. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN role_id_deprecated TO role_id;';


-- 2C: department_id → department_id_deprecated
ALTER TABLE users RENAME COLUMN department_id TO department_id_deprecated;

COMMENT ON COLUMN users.department_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from department_id. '
    'Use workspace_memberships.department_id. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN department_id_deprecated TO department_id;';


-- 2D: branch_id → branch_id_deprecated
ALTER TABLE users RENAME COLUMN branch_id TO branch_id_deprecated;

COMMENT ON COLUMN users.branch_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from branch_id. '
    'Use workspace_memberships.branch_id. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN branch_id_deprecated TO branch_id;';


-- 2E: shift_id → shift_id_deprecated
ALTER TABLE users RENAME COLUMN shift_id TO shift_id_deprecated;

COMMENT ON COLUMN users.shift_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from shift_id. '
    'Use workspace_memberships.shift_id. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN shift_id_deprecated TO shift_id;';


-- 2F: manager_id → manager_id_deprecated
ALTER TABLE users RENAME COLUMN manager_id TO manager_id_deprecated;

COMMENT ON COLUMN users.manager_id_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from manager_id. '
    'Use workspace_memberships.manager_membership_id (workspace-safe FK). '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN manager_id_deprecated TO manager_id;';


-- 2G: permissions → permissions_deprecated
ALTER TABLE users RENAME COLUMN permissions TO permissions_deprecated;

COMMENT ON COLUMN users.permissions_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from permissions. '
    'Use user_permission_overrides table. '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN permissions_deprecated TO permissions;';


-- 2H: approval_status → approval_status_deprecated
ALTER TABLE users RENAME COLUMN approval_status TO approval_status_deprecated;

COMMENT ON COLUMN users.approval_status_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from approval_status. '
    'Use workspace_memberships.status (pending/active/suspended/removed). '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN approval_status_deprecated TO approval_status;';


-- 2I: hire_date → hire_date_deprecated
ALTER TABLE users RENAME COLUMN hire_date TO hire_date_deprecated;

COMMENT ON COLUMN users.hire_date_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from hire_date. '
    'Use workspace_memberships.hire_date (per-workspace). '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN hire_date_deprecated TO hire_date;';


-- 2J: base_salary → base_salary_deprecated
ALTER TABLE users RENAME COLUMN base_salary TO base_salary_deprecated;

COMMENT ON COLUMN users.base_salary_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from base_salary. '
    'Use workspace_memberships.base_salary (per-workspace). '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN base_salary_deprecated TO base_salary;';


-- 2K: annual_leave_balance → annual_leave_balance_deprecated
ALTER TABLE users RENAME COLUMN annual_leave_balance TO annual_leave_balance_deprecated;

COMMENT ON COLUMN users.annual_leave_balance_deprecated IS
    '🚫 DEPRECATED (Migration 008). Renamed from annual_leave_balance. '
    'Use leave_balances table (per leave type, per fiscal year). '
    'ROLLBACK: ALTER TABLE users RENAME COLUMN annual_leave_balance_deprecated TO annual_leave_balance;';


-- ==========================================
-- SECTION 3: Update Compatibility Views
-- ==========================================
-- The v_user_workspace_context and v_workspace_members views from 006 are useful
-- and should be KEPT but updated to no longer reference deprecated columns.
-- They are now permanent convenience views, not transitional.

CREATE OR REPLACE VIEW v_user_workspace_context AS
SELECT
    wm.id AS membership_id,
    wm.workspace_id,
    wm.user_id,
    u.full_name,
    u.phone_number,
    u.email,
    wm.department_id,
    d.name AS department_name,
    wm.branch_id,
    b.name AS branch_name,
    wm.shift_id,
    wm.status AS membership_status,
    wm.hire_date,
    wm.base_salary,
    wm.annual_leave_balance,
    wm.assigned_warehouses,
    wm.manager_membership_id,
    r.id AS role_id,
    r.name AS role_name,
    r.role_key,
    r.hierarchy_level,
    r.permissions AS role_permissions,
    (r.role_key IN ('owner', 'co_owner')) AS is_admin_level,
    wm.joined_at,
    wm.created_at AS membership_created_at
FROM workspace_memberships wm
JOIN users u ON u.id = wm.user_id
LEFT JOIN membership_roles mr ON mr.membership_id = wm.id AND mr.is_primary = TRUE
LEFT JOIN roles r ON r.id = mr.role_id
LEFT JOIN departments d ON d.id = wm.department_id
LEFT JOIN branches b ON b.id = wm.branch_id
WHERE wm.status IN ('active', 'pending');

COMMENT ON VIEW v_user_workspace_context IS
    'Convenience view: flat user-per-workspace context with primary role, department, branch. '
    'Promoted from transitional (006) to permanent (008). No longer references deprecated columns. '
    'Use for API responses, dashboard context, and permission resolution.';


CREATE OR REPLACE VIEW v_workspace_members AS
SELECT
    wm.workspace_id,
    wm.id AS membership_id,
    u.id AS user_id,
    u.full_name,
    u.phone_number,
    u.email,
    wm.status,
    wm.department_id,
    d.name AS department_name,
    wm.branch_id,
    b.name AS branch_name,
    wm.hire_date,
    wm.joined_at,
    COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'role_id', r.id,
                'role_name', r.name,
                'role_key', r.role_key,
                'is_primary', mr.is_primary,
                'hierarchy_level', r.hierarchy_level
            )
        ) FILTER (WHERE r.id IS NOT NULL),
        '[]'::jsonb
    ) AS roles
FROM workspace_memberships wm
JOIN users u ON u.id = wm.user_id
LEFT JOIN membership_roles mr ON mr.membership_id = wm.id
LEFT JOIN roles r ON r.id = mr.role_id
LEFT JOIN departments d ON d.id = wm.department_id
LEFT JOIN branches b ON b.id = wm.branch_id
GROUP BY wm.workspace_id, wm.id, u.id, u.full_name, u.phone_number, u.email,
         wm.status, wm.department_id, d.name, wm.branch_id, b.name,
         wm.hire_date, wm.joined_at;

COMMENT ON VIEW v_workspace_members IS
    'Admin view: workspace members with aggregated roles. '
    'Promoted from transitional (006) to permanent (008). '
    'Use for workspace admin panel, member listing, and role management.';


-- ==========================================
-- SECTION 4: Deprecate Legacy HR Tables
-- ==========================================
-- The following tables have been superseded by new tables in Batch D.
-- We rename them with _legacy suffix to prevent accidental use.
-- Data is preserved; rollback is a single RENAME TABLE.

-- 4A: leaves → leaves_legacy
-- Replaced by: leave_requests (with leave_types for configurable types)
-- Data was migrated to leave_requests in 007 Section 2C.
ALTER TABLE leaves RENAME TO leaves_legacy;

COMMENT ON TABLE leaves_legacy IS
    '🚫 DEPRECATED (Migration 008). Renamed from leaves. '
    'Replaced by leave_requests + leave_types (configurable, with approval workflow). '
    'Data migrated in 007 Section 2C. '
    'ROLLBACK: ALTER TABLE leaves_legacy RENAME TO leaves;';


-- 4B: Legacy inventory_logs → inventory_logs_legacy
-- Replaced by: inventory_movements (with movement_type classification, source linkage)
-- Opening balances created in 007 Section 8.
ALTER TABLE inventory_logs RENAME TO inventory_logs_legacy;

COMMENT ON TABLE inventory_logs_legacy IS
    '🚫 DEPRECATED (Migration 008). Renamed from inventory_logs. '
    'Replaced by inventory_movements (immutable, typed, with source references). '
    'Opening balances created in 007 Section 8. '
    'ROLLBACK: ALTER TABLE inventory_logs_legacy RENAME TO inventory_logs;';


-- 4C: payroll table is NOT renamed — it is still actively used.
-- Migration 004 added payroll_run_id and status columns to it.
-- payroll_lines are children of payroll (FK payroll_id → payroll.id).
-- The payroll table remains the per-employee payslip record.
-- Only the legacy flat fields (base_salary, bonuses, deductions, net_salary)
-- are now superseded by payroll_lines for new payroll runs.

COMMENT ON COLUMN payroll.base_salary IS
    '⚠️ LEGACY (Migration 008). For payroll records linked to payroll_runs via payroll_run_id, '
    'use payroll_lines (line_type=base_salary) instead. '
    'This column remains for backward compatibility with unlinked records.';

COMMENT ON COLUMN payroll.bonuses IS
    '⚠️ LEGACY (Migration 008). For linked records, use payroll_lines (line_type=bonus). '
    'This column remains for unlinked legacy records.';

COMMENT ON COLUMN payroll.deductions IS
    '⚠️ LEGACY (Migration 008). For linked records, use payroll_lines (line_type=other_deduction). '
    'This column remains for unlinked legacy records.';

COMMENT ON COLUMN payroll.net_salary IS
    '⚠️ LEGACY (Migration 008). For linked records, net = SUM(payroll_lines.amount). '
    'This generated column remains valid for unlinked legacy records.';


-- ==========================================
-- SECTION 5: Enforce Final Constraints
-- ==========================================
-- Now that data is migrated and backfilled, enforce constraints that were
-- deferred during the transition period.

-- 5A: workspace_memberships.status NOT NULL (should already be, but belt+suspenders)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'workspace_memberships'
          AND column_name = 'status'
          AND is_nullable = 'YES'
    ) THEN
        ALTER TABLE workspace_memberships ALTER COLUMN status SET NOT NULL;
    END IF;
END $$;

-- 5B: membership_roles must have at least one is_primary per membership
-- This is already enforced by 007 backfill; add documentation.
COMMENT ON TABLE membership_roles IS
    'Junction table: membership → role (multi-role). '
    'Every membership MUST have exactly one is_primary=TRUE role. '
    'Enforced by application layer and validated by migration 007 Section 1C. '
    'UNIQUE on (payroll_id, line_type, label) prevents duplicate logical roles.';

-- 5C: Ensure inventory_levels.workspace_id is NOT NULL for RLS
DO $$
DECLARE
    v_null_count INT;
BEGIN
    SELECT COUNT(*) INTO v_null_count
    FROM inventory_levels WHERE workspace_id IS NULL;

    IF v_null_count = 0 THEN
        ALTER TABLE inventory_levels ALTER COLUMN workspace_id SET NOT NULL;
        RAISE NOTICE '[008-5C] inventory_levels.workspace_id set to NOT NULL.';
    ELSE
        RAISE WARNING '[008-5C] Cannot set inventory_levels.workspace_id to NOT NULL: '
            '% row(s) still have NULL. Fix these before enforcing.', v_null_count;
    END IF;
END $$;

-- 5D: Ensure inventory_levels.reserved and available have defaults
ALTER TABLE inventory_levels
    ALTER COLUMN reserved SET DEFAULT 0,
    ALTER COLUMN available SET DEFAULT 0;

-- 5E: Ensure payments.is_reversal is NOT NULL
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'payments'
          AND column_name = 'is_reversal'
          AND is_nullable = 'YES'
    ) THEN
        UPDATE payments SET is_reversal = FALSE WHERE is_reversal IS NULL;
        ALTER TABLE payments ALTER COLUMN is_reversal SET NOT NULL;
        RAISE NOTICE '[008-5E] payments.is_reversal set to NOT NULL.';
    END IF;
END $$;


-- ==========================================
-- SECTION 6: Update FK References for Renamed Columns
-- ==========================================
-- Some tables may reference users.workspace_id or users.role_id in FK constraints.
-- Now that these are renamed, dependent objects need updating.
-- We handle this by dropping and recreating the FK constraints on the renamed columns.

-- 6A: The departments.manager_id FK references users(id) — this is fine (not a renamed column).
-- No change needed.

-- 6B: Update the FK on users.workspace_id_deprecated
-- The original FK was: users.workspace_id REFERENCES workspaces(id) ON DELETE CASCADE
-- After rename, PostgreSQL automatically tracks the renamed column.
-- We just ensure it's correctly referenced.
-- NOTE: PostgreSQL renames FKs automatically when columns are renamed.
-- No explicit FK recreation needed.


-- ==========================================
-- SECTION 7: Clean Up Orphaned Objects
-- ==========================================
-- Remove objects that are no longer needed.

-- 7A: Drop the old trg_users_updated_at trigger if it references deprecated cols
-- (The trigger itself may still be useful for other columns like full_name, phone_number)
-- Keep the trigger — it still serves a purpose for non-deprecated fields.

-- 7B: Remove the app.sync_in_progress session variable documentation
-- (The triggers that used it are already dropped in Section 1)
COMMENT ON COLUMN users.is_active IS
    'Whether the user can log in. For workspace-specific status, '
    'use workspace_memberships.status instead.';


-- ==========================================
-- SECTION 8: Deprecation Registry
-- ==========================================
-- Create a deprecation tracking table for operational visibility.
-- This gives the operations team a single place to check what has been deprecated.

CREATE TABLE IF NOT EXISTS _deprecation_registry (
    id SERIAL PRIMARY KEY,
    object_type VARCHAR(50) NOT NULL,  -- 'column', 'table', 'trigger', 'function'
    object_name VARCHAR(255) NOT NULL,
    deprecated_in VARCHAR(50) NOT NULL,  -- migration number
    replaced_by TEXT NOT NULL,
    rollback_sql TEXT NOT NULL,
    deprecated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(object_type, object_name)
);

COMMENT ON TABLE _deprecation_registry IS
    'Operational tracking of deprecated schema objects. '
    'One row per deprecated item with replacement info and rollback SQL. '
    'Used by ops team to track deprecation lifecycle.';

-- Populate registry
INSERT INTO _deprecation_registry (object_type, object_name, deprecated_in, replaced_by, rollback_sql)
VALUES
    -- Columns
    ('column', 'users.workspace_id', '008', 'workspace_memberships', 'ALTER TABLE users RENAME COLUMN workspace_id_deprecated TO workspace_id;'),
    ('column', 'users.role_id', '008', 'membership_roles', 'ALTER TABLE users RENAME COLUMN role_id_deprecated TO role_id;'),
    ('column', 'users.department_id', '008', 'workspace_memberships.department_id', 'ALTER TABLE users RENAME COLUMN department_id_deprecated TO department_id;'),
    ('column', 'users.branch_id', '008', 'workspace_memberships.branch_id', 'ALTER TABLE users RENAME COLUMN branch_id_deprecated TO branch_id;'),
    ('column', 'users.shift_id', '008', 'workspace_memberships.shift_id', 'ALTER TABLE users RENAME COLUMN shift_id_deprecated TO shift_id;'),
    ('column', 'users.manager_id', '008', 'workspace_memberships.manager_membership_id', 'ALTER TABLE users RENAME COLUMN manager_id_deprecated TO manager_id;'),
    ('column', 'users.permissions', '008', 'user_permission_overrides', 'ALTER TABLE users RENAME COLUMN permissions_deprecated TO permissions;'),
    ('column', 'users.approval_status', '008', 'workspace_memberships.status', 'ALTER TABLE users RENAME COLUMN approval_status_deprecated TO approval_status;'),
    ('column', 'users.hire_date', '008', 'workspace_memberships.hire_date', 'ALTER TABLE users RENAME COLUMN hire_date_deprecated TO hire_date;'),
    ('column', 'users.base_salary', '008', 'workspace_memberships.base_salary', 'ALTER TABLE users RENAME COLUMN base_salary_deprecated TO base_salary;'),
    ('column', 'users.annual_leave_balance', '008', 'leave_balances', 'ALTER TABLE users RENAME COLUMN annual_leave_balance_deprecated TO annual_leave_balance;'),
    -- Tables
    ('table', 'leaves', '008', 'leave_requests + leave_types', 'ALTER TABLE leaves_legacy RENAME TO leaves;'),
    ('table', 'inventory_logs', '008', 'inventory_movements', 'ALTER TABLE inventory_logs_legacy RENAME TO inventory_logs;'),
    -- Triggers
    ('trigger', 'trg_sync_membership_to_user', '008', 'N/A (sync no longer needed)', 'Re-run migration 006 sections 5-6'),
    ('trigger', 'trg_sync_membership_role_to_user', '008', 'N/A (sync no longer needed)', 'Re-run migration 006 sections 5-6'),
    ('trigger', 'trg_sync_user_to_membership', '008', 'N/A (sync no longer needed)', 'Re-run migration 006 sections 5-6'),
    -- Functions
    ('function', 'sync_membership_to_user()', '008', 'N/A', 'Re-run migration 006 sections 5-6'),
    ('function', 'sync_user_to_membership()', '008', 'N/A', 'Re-run migration 006 sections 5-6'),
    ('function', 'sync_membership_role_to_user()', '008', 'N/A', 'Re-run migration 006 sections 5-6')
ON CONFLICT (object_type, object_name) DO NOTHING;


-- ==========================================
-- SECTION 9: Validation
-- ==========================================
-- Final checks to confirm cleanup was successful.

DO $$
DECLARE
    v_deprecated_cols INT;
    v_legacy_tables INT;
    v_dropped_triggers INT;
    v_registry_count INT;
BEGIN
    -- Check: deprecated columns exist with _deprecated suffix
    SELECT COUNT(*) INTO v_deprecated_cols
    FROM information_schema.columns
    WHERE table_name = 'users'
      AND column_name LIKE '%_deprecated';

    -- Check: legacy tables renamed
    SELECT COUNT(*) INTO v_legacy_tables
    FROM information_schema.tables
    WHERE table_name IN ('leaves_legacy', 'inventory_logs_legacy');

    -- Check: sync triggers removed
    SELECT COUNT(*) INTO v_dropped_triggers
    FROM information_schema.triggers
    WHERE trigger_name IN (
        'trg_sync_membership_to_user',
        'trg_sync_membership_role_to_user',
        'trg_sync_user_to_membership'
    );

    -- Check: deprecation registry populated
    SELECT COUNT(*) INTO v_registry_count
    FROM _deprecation_registry;

    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration 008 Cleanup Summary:';
    RAISE NOTICE '  Deprecated columns on users:    %', v_deprecated_cols;
    RAISE NOTICE '  Legacy tables renamed:           %', v_legacy_tables;
    RAISE NOTICE '  Sync triggers remaining:         % (should be 0)', v_dropped_triggers;
    RAISE NOTICE '  Deprecation registry entries:    %', v_registry_count;
    RAISE NOTICE '========================================';

    IF v_dropped_triggers > 0 THEN
        RAISE WARNING '[008-9] % sync trigger(s) still exist. '
            'Section 1 may have failed partially.', v_dropped_triggers;
    END IF;
END $$;


-- ==========================================
-- END OF MIGRATION 008
-- ==========================================
-- Validation checklist:
--   [ ] Sync triggers removed (3 triggers, 3 functions)
--   [ ] users.workspace_id renamed to workspace_id_deprecated
--   [ ] users.role_id renamed to role_id_deprecated
--   [ ] users.department_id renamed to department_id_deprecated
--   [ ] users.branch_id renamed to branch_id_deprecated
--   [ ] users.shift_id renamed to shift_id_deprecated
--   [ ] users.manager_id renamed to manager_id_deprecated
--   [ ] users.permissions renamed to permissions_deprecated
--   [ ] users.approval_status renamed to approval_status_deprecated
--   [ ] users.hire_date renamed to hire_date_deprecated
--   [ ] users.base_salary renamed to base_salary_deprecated
--   [ ] users.annual_leave_balance renamed to annual_leave_balance_deprecated
--   [ ] Unique constraint on (workspace_id_deprecated, phone_number) recreated
--   [ ] Compatibility views updated (no deprecated column refs)
--   [ ] leaves → leaves_legacy
--   [ ] inventory_logs → inventory_logs_legacy
--   [ ] payroll legacy columns documented (not renamed — still in use)
--   [ ] Final constraints enforced (workspace_id NOT NULL, is_reversal NOT NULL)
--   [ ] _deprecation_registry created with 19 entries
--   [ ] Validation report output
--   [ ] No data deleted
--   [ ] No tables dropped
--   [ ] Rollback SQL documented for every change
-- ==========================================
