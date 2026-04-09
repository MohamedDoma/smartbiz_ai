-- ==========================================
-- SmartBiz AI — Migration 006: Membership Refactor
-- Identity / Membership Transition Phase
-- ==========================================
--
-- ==========================================
-- MIGRATION STRATEGY: PHASED COEXISTENCE
-- ==========================================
--
-- This migration implements Phase 2 of the membership model transition,
-- bridging the gap between the legacy users table and the workspace_memberships
-- model created in Batch B (002_rbac_persistence.sql).
--
-- PHASE 1 (Batch B — DONE):
--   Created workspace_memberships, membership_roles, user_permission_overrides,
--   permission_delegations. Documented coexistence. No legacy columns removed.
--
-- PHASE 2 (THIS MIGRATION — 006):
--   a) Backfill workspace_memberships from existing users.workspace_id data
--   b) Backfill membership_roles from existing users.role_id data
--   c) Create bidirectional sync triggers to keep both models consistent
--   d) Create compatibility views for read-path migration
--   e) Add deprecation markers on legacy columns (comments only, no drops)
--   f) Ensure ownership guarantee (at least one owner per workspace)
--   g) Add email column to users for multi-workspace login identity
--
-- PHASE 3 (FUTURE — Batch G):
--   a) Application layer fully migrated to workspace_memberships
--   b) Verified zero production usage of users.workspace_id for role resolution
--   c) Drop sync triggers
--   d) Drop or rename legacy columns (users.workspace_id, users.role_id, etc.)
--
-- SAFETY GUARANTEES:
--   - NO legacy columns are dropped
--   - NO existing queries break
--   - Sync triggers ensure both models stay consistent during transition
--   - Backfill is idempotent (uses ON CONFLICT DO NOTHING)
--   - All changes are non-destructive and reversible
--
-- ==========================================


-- ==========================================
-- SECTION 1: Users Table — Multi-Workspace Identity Preparation
-- ==========================================
-- The current users table binds each user to exactly one workspace via
-- users.workspace_id. Multi-workspace support requires an identity column
-- (email) that exists at the user level, independent of workspace.
--
-- We add email to users as the cross-workspace login identifier.
-- The workspace_id + phone_number unique constraint stays for backward compat.
-- A global unique index on email provides the multi-workspace lookup path.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS email VARCHAR(255);

-- Unique email globally (across all workspaces) — this becomes the login identity
-- for multi-workspace users. NULL emails are allowed during transition.
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email
    ON users(email) WHERE email IS NOT NULL;

COMMENT ON COLUMN users.email IS
    'Global login identity for multi-workspace support. '
    'UNIQUE across all workspaces (NULL allowed during transition). '
    'When populated, users can log in via email and select workspace. '
    'The legacy workspace_id + phone_number path remains valid.';


-- ==========================================
-- SECTION 2: Backfill workspace_memberships from users
-- ==========================================
-- Idempotent: uses ON CONFLICT DO NOTHING to skip already-backfilled rows.
-- Copies users.workspace_id, department_id, branch_id, shift_id,
-- hire_date, base_salary, annual_leave_balance into workspace_memberships.
-- Sets status based on users.is_active and approval_status.

INSERT INTO workspace_memberships (
    workspace_id,
    user_id,
    department_id,
    branch_id,
    shift_id,
    status,
    hire_date,
    base_salary,
    annual_leave_balance,
    joined_at,
    created_at,
    updated_at
)
SELECT
    u.workspace_id,
    u.id,
    u.department_id,
    u.branch_id,
    u.shift_id,
    CASE
        WHEN u.is_active = TRUE AND u.approval_status = 'approved' THEN 'active'
        WHEN u.approval_status = 'pending' THEN 'pending'
        WHEN u.approval_status = 'rejected' THEN 'removed'
        WHEN u.is_active = FALSE THEN 'suspended'
        ELSE 'pending'
    END,
    u.hire_date,
    u.base_salary,
    u.annual_leave_balance,
    u.created_at,  -- joined_at = user creation time
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM users u
WHERE u.workspace_id IS NOT NULL
ON CONFLICT (workspace_id, user_id) DO NOTHING;

COMMENT ON TABLE workspace_memberships IS
    'Binds users to workspaces. Role assignments via membership_roles. '
    'Org-structure and HR data are per-workspace. Replaces users.workspace_id '
    'for multi-workspace support. '
    'MIGRATION 006: backfilled from users table. Sync triggers keep both models '
    'consistent during transition phase.';


-- ==========================================
-- SECTION 3: Backfill membership_roles from users.role_id
-- ==========================================
-- For each user that has a role_id, create a membership_role entry.
-- This ensures the new RBAC resolution path (membership → membership_roles → role)
-- has the same data as the legacy path (users.role_id → role).

INSERT INTO membership_roles (
    workspace_id,
    membership_id,
    role_id,
    is_primary,
    assigned_at,
    created_at
)
SELECT
    wm.workspace_id,
    wm.id,
    u.role_id,
    TRUE,   -- The legacy single-role is the primary role
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP
FROM users u
JOIN workspace_memberships wm
    ON wm.workspace_id = u.workspace_id
    AND wm.user_id = u.id
WHERE u.role_id IS NOT NULL
ON CONFLICT (membership_id, role_id) DO NOTHING;


-- ==========================================
-- SECTION 4: Backfill user_permission_overrides from users.permissions
-- ==========================================
-- The legacy users.permissions JSONB contains {grants: {...}, denials: {...}}.
-- This is complex to backfill generically, so we document the approach
-- and provide a manual backfill template.

-- ⚠️ MANUAL BACKFILL REQUIRED for users.permissions JSONB
-- The legacy users.permissions column contains per-user grant/deny overrides.
-- Because the JSONB structure is freeform, automated backfill requires application
-- logic to parse and validate each entry.
--
-- Template for manual backfill (run per-workspace):
--
--   INSERT INTO user_permission_overrides (workspace_id, membership_id, permission_key,
--       override_type, scope, reason, granted_by_membership_id, created_at)
--   SELECT wm.workspace_id, wm.id,
--       key,
--       'grant',
--       value->>'scope',
--       value->>'reason',
--       <admin_membership_id>,
--       COALESCE((value->>'granted_at')::timestamptz, CURRENT_TIMESTAMP)
--   FROM users u
--   JOIN workspace_memberships wm ON wm.user_id = u.id AND wm.workspace_id = u.workspace_id
--   CROSS JOIN LATERAL jsonb_each(u.permissions->'grants') AS perms(key, value)
--   WHERE u.permissions IS NOT NULL AND u.permissions->'grants' IS NOT NULL;
--
-- A similar query handles denials with override_type = 'deny'.
-- This step MUST be run by the application deployment pipeline after this migration.


-- ==========================================
-- SECTION 5: Bidirectional Sync Triggers
-- ==========================================
-- These triggers keep users and workspace_memberships in sync during the
-- transitional coexistence phase. They will be removed in Phase 3 (Batch G).

-- 5A: When a membership is created or updated, sync back to users table.
-- This ensures legacy code reading users.department_id, etc. sees current data.

CREATE OR REPLACE FUNCTION sync_membership_to_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Only sync if the user still has this workspace_id as their primary
    -- (or has no workspace_id set yet)
    UPDATE users SET
        workspace_id = COALESCE(users.workspace_id, NEW.workspace_id),
        department_id = NEW.department_id,
        branch_id = NEW.branch_id,
        shift_id = NEW.shift_id,
        hire_date = NEW.hire_date,
        base_salary = NEW.base_salary,
        annual_leave_balance = NEW.annual_leave_balance,
        is_active = CASE
            WHEN NEW.status = 'active' THEN TRUE
            WHEN NEW.status IN ('suspended', 'removed') THEN FALSE
            ELSE users.is_active
        END,
        approval_status = CASE
            WHEN NEW.status = 'active' THEN 'approved'
            WHEN NEW.status = 'pending' THEN 'pending'
            WHEN NEW.status = 'removed' THEN 'rejected'
            ELSE users.approval_status
        END,
        updated_at = CURRENT_TIMESTAMP
    WHERE users.id = NEW.user_id
      AND (users.workspace_id = NEW.workspace_id OR users.workspace_id IS NULL);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_membership_to_user
    AFTER INSERT OR UPDATE ON workspace_memberships
    FOR EACH ROW EXECUTE FUNCTION sync_membership_to_user();

COMMENT ON FUNCTION sync_membership_to_user() IS
    'TRANSITIONAL: Syncs workspace_memberships changes back to the legacy users table. '
    'Only syncs if users.workspace_id matches the membership workspace (primary workspace). '
    'Will be removed in Phase 3 (Batch G) after application migration is complete.';


-- 5B: When a membership_role is created or removed, sync primary role to users.role_id

CREATE OR REPLACE FUNCTION sync_membership_role_to_user()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_workspace_id UUID;
    v_primary_role_id UUID;
BEGIN
    -- Determine membership context
    IF TG_OP = 'DELETE' THEN
        SELECT wm.user_id, wm.workspace_id INTO v_user_id, v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = OLD.membership_id;
    ELSE
        SELECT wm.user_id, wm.workspace_id INTO v_user_id, v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = NEW.membership_id;
    END IF;

    -- Find the primary role for this membership
    SELECT mr.role_id INTO v_primary_role_id
    FROM membership_roles mr
    JOIN workspace_memberships wm ON wm.id = mr.membership_id
    WHERE wm.user_id = v_user_id
      AND wm.workspace_id = v_workspace_id
      AND mr.is_primary = TRUE
    LIMIT 1;

    -- Sync to users.role_id (only if this is the user's primary workspace)
    UPDATE users SET
        role_id = v_primary_role_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE users.id = v_user_id
      AND users.workspace_id = v_workspace_id;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_membership_role_to_user
    AFTER INSERT OR UPDATE OR DELETE ON membership_roles
    FOR EACH ROW EXECUTE FUNCTION sync_membership_role_to_user();

COMMENT ON FUNCTION sync_membership_role_to_user() IS
    'TRANSITIONAL: Syncs the primary membership_role back to users.role_id. '
    'Only syncs if users.workspace_id matches the membership workspace. '
    'Will be removed in Phase 3 (Batch G).';


-- 5C: When users table is updated (legacy code path), sync forward to membership.
-- This ensures membership data stays current even if old code updates users directly.

CREATE OR REPLACE FUNCTION sync_user_to_membership()
RETURNS TRIGGER AS $$
BEGIN
    -- Only sync if there's a workspace_id to target
    IF NEW.workspace_id IS NOT NULL THEN
        -- Use upsert to handle both existing and new memberships
        INSERT INTO workspace_memberships (
            workspace_id, user_id, department_id, branch_id, shift_id,
            status, hire_date, base_salary, annual_leave_balance,
            joined_at, created_at, updated_at
        ) VALUES (
            NEW.workspace_id, NEW.id, NEW.department_id, NEW.branch_id, NEW.shift_id,
            CASE
                WHEN NEW.is_active = TRUE AND NEW.approval_status = 'approved' THEN 'active'
                WHEN NEW.approval_status = 'pending' THEN 'pending'
                WHEN NEW.approval_status = 'rejected' THEN 'removed'
                WHEN NEW.is_active = FALSE THEN 'suspended'
                ELSE 'pending'
            END,
            NEW.hire_date, NEW.base_salary, NEW.annual_leave_balance,
            COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ON CONFLICT (workspace_id, user_id)
        DO UPDATE SET
            department_id = EXCLUDED.department_id,
            branch_id = EXCLUDED.branch_id,
            shift_id = EXCLUDED.shift_id,
            status = EXCLUDED.status,
            hire_date = EXCLUDED.hire_date,
            base_salary = EXCLUDED.base_salary,
            annual_leave_balance = EXCLUDED.annual_leave_balance,
            updated_at = CURRENT_TIMESTAMP;

        -- Sync role_id to membership_roles if changed
        IF NEW.role_id IS DISTINCT FROM OLD.role_id AND NEW.role_id IS NOT NULL THEN
            -- Get or create membership
            DECLARE
                v_membership_id UUID;
            BEGIN
                SELECT id INTO v_membership_id
                FROM workspace_memberships
                WHERE workspace_id = NEW.workspace_id AND user_id = NEW.id;

                IF v_membership_id IS NOT NULL THEN
                    -- Remove old primary role
                    UPDATE membership_roles SET is_primary = FALSE
                    WHERE membership_id = v_membership_id AND is_primary = TRUE
                      AND role_id <> NEW.role_id;

                    -- Upsert new primary role
                    INSERT INTO membership_roles (workspace_id, membership_id, role_id,
                        is_primary, assigned_at, created_at)
                    VALUES (NEW.workspace_id, v_membership_id, NEW.role_id,
                        TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    ON CONFLICT (membership_id, role_id)
                    DO UPDATE SET is_primary = TRUE;
                END IF;
            END;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_sync_user_to_membership
    AFTER UPDATE ON users
    FOR EACH ROW
    WHEN (
        OLD.department_id IS DISTINCT FROM NEW.department_id
        OR OLD.branch_id IS DISTINCT FROM NEW.branch_id
        OR OLD.shift_id IS DISTINCT FROM NEW.shift_id
        OR OLD.role_id IS DISTINCT FROM NEW.role_id
        OR OLD.is_active IS DISTINCT FROM NEW.is_active
        OR OLD.approval_status IS DISTINCT FROM NEW.approval_status
        OR OLD.hire_date IS DISTINCT FROM NEW.hire_date
        OR OLD.base_salary IS DISTINCT FROM NEW.base_salary
        OR OLD.annual_leave_balance IS DISTINCT FROM NEW.annual_leave_balance
    )
    EXECUTE FUNCTION sync_user_to_membership();

COMMENT ON FUNCTION sync_user_to_membership() IS
    'TRANSITIONAL: Forward-syncs legacy users table updates to workspace_memberships. '
    'Handles org-structure, status, HR data, and role_id changes. '
    'Only fires when relevant columns change (optimized WHEN clause). '
    'Will be removed in Phase 3 (Batch G).';


-- ==========================================
-- SECTION 6: Infinite Recursion Prevention
-- ==========================================
-- The bidirectional sync triggers could cause infinite loops:
--   membership update → sync_to_user → user trigger → sync_to_membership → ...
--
-- We prevent this using a session variable flag.

CREATE OR REPLACE FUNCTION sync_membership_to_user()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent infinite recursion
    IF current_setting('app.sync_in_progress', true) = 'true' THEN
        RETURN NEW;
    END IF;

    PERFORM set_config('app.sync_in_progress', 'true', true);

    UPDATE users SET
        workspace_id = COALESCE(users.workspace_id, NEW.workspace_id),
        department_id = NEW.department_id,
        branch_id = NEW.branch_id,
        shift_id = NEW.shift_id,
        hire_date = NEW.hire_date,
        base_salary = NEW.base_salary,
        annual_leave_balance = NEW.annual_leave_balance,
        is_active = CASE
            WHEN NEW.status = 'active' THEN TRUE
            WHEN NEW.status IN ('suspended', 'removed') THEN FALSE
            ELSE users.is_active
        END,
        approval_status = CASE
            WHEN NEW.status = 'active' THEN 'approved'
            WHEN NEW.status = 'pending' THEN 'pending'
            WHEN NEW.status = 'removed' THEN 'rejected'
            ELSE users.approval_status
        END,
        updated_at = CURRENT_TIMESTAMP
    WHERE users.id = NEW.user_id
      AND (users.workspace_id = NEW.workspace_id OR users.workspace_id IS NULL);

    PERFORM set_config('app.sync_in_progress', 'false', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_user_to_membership()
RETURNS TRIGGER AS $$
BEGIN
    -- Prevent infinite recursion
    IF current_setting('app.sync_in_progress', true) = 'true' THEN
        RETURN NEW;
    END IF;

    PERFORM set_config('app.sync_in_progress', 'true', true);

    IF NEW.workspace_id IS NOT NULL THEN
        INSERT INTO workspace_memberships (
            workspace_id, user_id, department_id, branch_id, shift_id,
            status, hire_date, base_salary, annual_leave_balance,
            joined_at, created_at, updated_at
        ) VALUES (
            NEW.workspace_id, NEW.id, NEW.department_id, NEW.branch_id, NEW.shift_id,
            CASE
                WHEN NEW.is_active = TRUE AND NEW.approval_status = 'approved' THEN 'active'
                WHEN NEW.approval_status = 'pending' THEN 'pending'
                WHEN NEW.approval_status = 'rejected' THEN 'removed'
                WHEN NEW.is_active = FALSE THEN 'suspended'
                ELSE 'pending'
            END,
            NEW.hire_date, NEW.base_salary, NEW.annual_leave_balance,
            COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
            CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
        ON CONFLICT (workspace_id, user_id)
        DO UPDATE SET
            department_id = EXCLUDED.department_id,
            branch_id = EXCLUDED.branch_id,
            shift_id = EXCLUDED.shift_id,
            status = EXCLUDED.status,
            hire_date = EXCLUDED.hire_date,
            base_salary = EXCLUDED.base_salary,
            annual_leave_balance = EXCLUDED.annual_leave_balance,
            updated_at = CURRENT_TIMESTAMP;

        -- Sync role_id if changed
        IF NEW.role_id IS DISTINCT FROM OLD.role_id AND NEW.role_id IS NOT NULL THEN
            DECLARE
                v_membership_id UUID;
            BEGIN
                SELECT id INTO v_membership_id
                FROM workspace_memberships
                WHERE workspace_id = NEW.workspace_id AND user_id = NEW.id;

                IF v_membership_id IS NOT NULL THEN
                    UPDATE membership_roles SET is_primary = FALSE
                    WHERE membership_id = v_membership_id AND is_primary = TRUE
                      AND role_id <> NEW.role_id;

                    INSERT INTO membership_roles (workspace_id, membership_id, role_id,
                        is_primary, assigned_at, created_at)
                    VALUES (NEW.workspace_id, v_membership_id, NEW.role_id,
                        TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                    ON CONFLICT (membership_id, role_id)
                    DO UPDATE SET is_primary = TRUE;
                END IF;
            END;
        END IF;
    END IF;

    PERFORM set_config('app.sync_in_progress', 'false', true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_membership_role_to_user()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_workspace_id UUID;
    v_primary_role_id UUID;
BEGIN
    -- Prevent infinite recursion
    IF current_setting('app.sync_in_progress', true) = 'true' THEN
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
    END IF;

    PERFORM set_config('app.sync_in_progress', 'true', true);

    IF TG_OP = 'DELETE' THEN
        SELECT wm.user_id, wm.workspace_id INTO v_user_id, v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = OLD.membership_id;
    ELSE
        SELECT wm.user_id, wm.workspace_id INTO v_user_id, v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = NEW.membership_id;
    END IF;

    SELECT mr.role_id INTO v_primary_role_id
    FROM membership_roles mr
    JOIN workspace_memberships wm ON wm.id = mr.membership_id
    WHERE wm.user_id = v_user_id
      AND wm.workspace_id = v_workspace_id
      AND mr.is_primary = TRUE
    LIMIT 1;

    UPDATE users SET
        role_id = v_primary_role_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE users.id = v_user_id
      AND users.workspace_id = v_workspace_id;

    PERFORM set_config('app.sync_in_progress', 'false', true);

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION sync_membership_to_user() IS
    'TRANSITIONAL: Membership→User sync with recursion guard via app.sync_in_progress. '
    'Removed in Phase 3 (Batch G).';
COMMENT ON FUNCTION sync_user_to_membership() IS
    'TRANSITIONAL: User→Membership sync with recursion guard via app.sync_in_progress. '
    'Removed in Phase 3 (Batch G).';
COMMENT ON FUNCTION sync_membership_role_to_user() IS
    'TRANSITIONAL: MembershipRole→User role sync with recursion guard. '
    'Removed in Phase 3 (Batch G).';


-- ==========================================
-- SECTION 7: Compatibility Views
-- ==========================================
-- Read-only views that present the new membership model through the familiar
-- "user-per-workspace" lens. Application code can migrate reads to these views
-- as an intermediate step before fully adopting the membership model.

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
    -- Primary role info
    r.id AS role_id,
    r.name AS role_name,
    r.role_key,
    r.hierarchy_level,
    r.permissions AS role_permissions,
    -- Computed
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
    'Compatibility view: presents the membership model in a flat user-per-workspace format. '
    'Includes primary role, department, branch, and computed admin flag. '
    'Use this view to migrate read paths before fully adopting the membership model. '
    'TRANSITIONAL: Will be renamed or removed in Phase 3.';


-- View: workspace members with their roles (for admin UI)
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
    -- Aggregate all roles into a JSON array
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
    'Admin view: all workspace members with aggregated roles array. '
    'Use for workspace admin panel, member listing, and role management UI.';


-- ==========================================
-- SECTION 8: Ownership Guarantee
-- ==========================================
-- Every workspace MUST have at least one owner membership.
-- We enforce this with a trigger on membership_roles DELETE/UPDATE.

CREATE OR REPLACE FUNCTION check_workspace_owner_exists()
RETURNS TRIGGER AS $$
DECLARE
    v_workspace_id UUID;
    v_owner_count INT;
    v_role_key VARCHAR;
BEGIN
    -- Get the role_key being affected
    IF TG_OP = 'DELETE' THEN
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = OLD.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = OLD.membership_id;
    ELSE
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = NEW.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = NEW.membership_id;
    END IF;

    -- Only check when removing/changing an owner role
    IF v_role_key = 'owner' AND (TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.role_id <> NEW.role_id)) THEN
        SELECT COUNT(*) INTO v_owner_count
        FROM membership_roles mr
        JOIN roles r ON r.id = mr.role_id
        JOIN workspace_memberships wm ON wm.id = mr.membership_id
        WHERE wm.workspace_id = v_workspace_id
          AND r.role_key = 'owner'
          AND wm.status = 'active'
          AND mr.id <> COALESCE(OLD.id, '00000000-0000-0000-0000-000000000000'::UUID);

        IF v_owner_count < 1 THEN
            RAISE EXCEPTION 'Cannot remove the last owner from workspace %. '
                'Every workspace must have at least one active owner (RBAC §13.1).',
                v_workspace_id
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_workspace_owner_exists
    BEFORE DELETE OR UPDATE ON membership_roles
    FOR EACH ROW EXECUTE FUNCTION check_workspace_owner_exists();

COMMENT ON FUNCTION check_workspace_owner_exists() IS
    'DB-ENFORCED: Prevents removing the last owner from a workspace. '
    'Every workspace must have at least one active member with role_key=owner. '
    'Implements RBAC §13.1 ownership rule.';


-- Also prevent deactivating the last owner membership
CREATE OR REPLACE FUNCTION check_owner_membership_active()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_count INT;
    v_has_owner_role BOOLEAN;
BEGIN
    -- Only check when deactivating (status change to suspended/removed)
    IF NEW.status IN ('suspended', 'removed') AND OLD.status = 'active' THEN
        -- Check if this membership has an owner role
        SELECT EXISTS(
            SELECT 1 FROM membership_roles mr
            JOIN roles r ON r.id = mr.role_id
            WHERE mr.membership_id = OLD.id AND r.role_key = 'owner'
        ) INTO v_has_owner_role;

        IF v_has_owner_role THEN
            -- Count remaining active owners
            SELECT COUNT(*) INTO v_owner_count
            FROM membership_roles mr
            JOIN roles r ON r.id = mr.role_id
            JOIN workspace_memberships wm ON wm.id = mr.membership_id
            WHERE wm.workspace_id = OLD.workspace_id
              AND r.role_key = 'owner'
              AND wm.status = 'active'
              AND wm.id <> OLD.id;

            IF v_owner_count < 1 THEN
                RAISE EXCEPTION 'Cannot deactivate the last owner membership in workspace %. '
                    'Transfer ownership first (RBAC §13.1).',
                    OLD.workspace_id
                    USING ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_owner_membership_active
    BEFORE UPDATE ON workspace_memberships
    FOR EACH ROW EXECUTE FUNCTION check_owner_membership_active();

COMMENT ON FUNCTION check_owner_membership_active() IS
    'DB-ENFORCED: Prevents deactivating the last owner membership. '
    'If a membership with owner role is being suspended/removed, ensure '
    'at least one other active owner remains. Implements RBAC §13.1.';


-- ==========================================
-- SECTION 9: Deprecation Markers (Comments Only)
-- ==========================================
-- Mark legacy columns with deprecation notices.
-- NO COLUMNS ARE DROPPED. This is documentation only.

COMMENT ON COLUMN users.workspace_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships for the canonical '
    'user-to-workspace relationship. This column is kept for backward compatibility '
    'and synced via trg_sync_user_to_membership / trg_sync_membership_to_user. '
    'Will be made NULLABLE in Phase 3 (Batch G). Do NOT use for new code.';

COMMENT ON COLUMN users.role_id IS
    '⚠️ DEPRECATED (Migration 006). Use membership_roles for role resolution. '
    'This column is synced via trg_sync_membership_role_to_user. '
    'Will be removed in Phase 3 (Batch G). Do NOT use for new code.';

COMMENT ON COLUMN users.department_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.department_id instead. '
    'Synced bidirectionally during transition.';

COMMENT ON COLUMN users.branch_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.branch_id instead. '
    'Synced bidirectionally during transition.';

COMMENT ON COLUMN users.shift_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.shift_id instead. '
    'Synced bidirectionally during transition.';

COMMENT ON COLUMN users.manager_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.manager_membership_id instead. '
    'manager_id references users(id); manager_membership_id references workspace_memberships(id) '
    'which is workspace-safe. NOT synced automatically — application must migrate to membership model.';

COMMENT ON COLUMN users.permissions IS
    '⚠️ DEPRECATED (Migration 006). Use user_permission_overrides table instead. '
    'Manual backfill required (see Section 4 template). NOT synced automatically.';

COMMENT ON COLUMN users.approval_status IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.status instead. '
    'Mapping: pending=pending, approved=active, rejected=removed. Synced bidirectionally.';

COMMENT ON COLUMN users.hire_date IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.hire_date instead. '
    'Per-workspace data; synced bidirectionally during transition.';

COMMENT ON COLUMN users.base_salary IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.base_salary instead. '
    'Per-workspace data; synced bidirectionally during transition.';

COMMENT ON COLUMN users.annual_leave_balance IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships.annual_leave_balance instead. '
    'Per-workspace data; synced bidirectionally during transition.';


-- ==========================================
-- SECTION 10: Additional Indexes for Transition Support
-- ==========================================

-- Fast lookup: email-based login for multi-workspace
-- (duplicate of uq_users_email above, but ensures coverage)

-- Membership lookup by status (for sync)
CREATE INDEX IF NOT EXISTS idx_memberships_status_active
    ON workspace_memberships(workspace_id, user_id)
    WHERE status = 'active';

-- Primary role resolution
CREATE INDEX IF NOT EXISTS idx_membership_roles_primary
    ON membership_roles(membership_id)
    WHERE is_primary = TRUE;

-- Ownership queries
CREATE INDEX IF NOT EXISTS idx_membership_roles_owner
    ON membership_roles(membership_id)
    WHERE role_id IN (SELECT id FROM roles WHERE role_key = 'owner');


-- ==========================================
-- SECTION 11: APPLICATION-LAYER MIGRATION GUIDE
-- ==========================================

-- ⚠️ APPLICATION MIGRATION GUIDE:
--
-- This section documents the required application-layer changes to complete
-- the membership model transition. These must be done by the development team
-- AFTER this migration runs, but BEFORE Phase 3 (Batch G).
--
--   1. AUTH ENDPOINTS (register, login):
--      OLD: Create user with workspace_id, role_id
--      NEW: Create user (workspace-independent), create workspace_membership,
--           create membership_role. The sync triggers handle backward compat.
--
--   2. PERMISSION RESOLUTION:
--      OLD: user.role_id → roles.permissions
--      NEW: membership → membership_roles → roles.permissions
--           → user_permission_overrides → permission_delegations
--      See RBAC §14.2 pseudocode for resolution order.
--
--   3. USER LISTING / ADMIN PANEL:
--      OLD: SELECT * FROM users WHERE workspace_id = ?
--      NEW: SELECT * FROM v_workspace_members WHERE workspace_id = ?
--           (or direct JOIN on workspace_memberships)
--
--   4. ORG-STRUCTURE QUERIES (department, branch):
--      OLD: users.department_id, users.branch_id
--      NEW: workspace_memberships.department_id, workspace_memberships.branch_id
--           (sync triggers keep these consistent during transition)
--
--   5. MULTI-WORKSPACE LOGIN:
--      When users.email is populated:
--        a. Login by email → return list of workspace_memberships
--        b. User selects workspace → set app.workspace_id session var
--        c. All subsequent queries use RLS-filtered membership
--
--   6. RLS CONTEXT:
--      No change needed. app.workspace_id session variable continues to be the
--      RLS filter for all workspace-scoped tables.
--
--   7. WORKSPACE CREATION:
--      When creating a new workspace:
--        a. Create workspace
--        b. Create workspace_membership for creator (status='active')
--        c. Create owner role (or use template)
--        d. Create membership_role linking membership to owner role
--        e. Sync trigger updates users.workspace_id if this is first workspace
--
--   8. TESTING:
--      After deploying this migration:
--        a. Verify all existing users have workspace_memberships rows
--        b. Verify all users with role_id have membership_roles rows
--        c. Verify sync triggers work: update user → check membership, and vice versa
--        d. Verify v_user_workspace_context returns correct data
--        e. Verify ownership guard: try removing last owner role → expect error


-- ==========================================
-- END OF MIGRATION 006
-- ==========================================
-- Validation checklist:
--   [ ] users.email column added with global unique index
--   [ ] workspace_memberships backfilled from users (idempotent)
--   [ ] membership_roles backfilled from users.role_id (idempotent)
--   [ ] user_permission_overrides backfill documented (manual step)
--   [ ] sync_membership_to_user() trigger created (membership→user)
--   [ ] sync_membership_role_to_user() trigger created (role→user)
--   [ ] sync_user_to_membership() trigger created (user→membership)
--   [ ] All sync triggers have recursion guard (app.sync_in_progress)
--   [ ] v_user_workspace_context view created
--   [ ] v_workspace_members view created
--   [ ] check_workspace_owner_exists() trigger on membership_roles
--   [ ] check_owner_membership_active() trigger on workspace_memberships
--   [ ] All deprecated columns marked with COMMENT (11 columns)
--   [ ] No columns dropped
--   [ ] No existing queries broken
--   [ ] Migration strategy documented (phased coexistence)
--   [ ] Application migration guide documented (8 steps)
--   [ ] Additional indexes for transition support
-- ==========================================
