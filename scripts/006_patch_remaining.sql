-- ==========================================
-- SmartBiz AI — Migration 006 Recovery Patch
-- ==========================================
--
-- PURPOSE:
--   Applies all remaining unapplied sections of 006_membership_refactor.sql.
--   Migration 006 partially failed because it references membership_roles.created_at,
--   but the actual table uses assigned_at (no created_at column exists).
--
-- ALREADY APPLIED (verified from live DB):
--   [x] S1:  users.email column + uq_users_email unique index
--   [x] S2:  workspace_memberships backfill (0 rows — no existing users, idempotent)
--   [x] S3:  membership_roles backfill (0 rows — no existing users, idempotent)
--   [x] S5a: sync_membership_to_user() function + trg_sync_membership_to_user trigger
--   [x] S5b: sync_membership_role_to_user() function + trg_sync_membership_role_to_user trigger
--
-- NOT YET APPLIED (this patch covers):
--   [ ] S5c: sync_user_to_membership() function + trg_sync_user_to_membership trigger
--   [ ] S6:  Recursion-guarded rewrites of all 3 sync functions (CREATE OR REPLACE)
--   [ ] S7:  v_user_workspace_context and v_workspace_members views
--   [ ] S8:  check_workspace_owner_exists() + check_owner_membership_active() functions + triggers
--   [ ] S9:  Deprecation comment markers on 11 legacy users columns
--   [ ] S10: 3 additional indexes for transition support
--
-- SCHEMA FIX:
--   All references to membership_roles.created_at changed to membership_roles.assigned_at
--   to match the ACTUAL table schema.
--
-- ACTUAL membership_roles columns (verified):
--   id, workspace_id, membership_id, role_id, is_primary, assigned_by, assigned_at
--
-- ==========================================


-- ==========================================
-- SECTION 5c: Forward sync trigger (user → membership)
-- ==========================================
-- When users table is updated (legacy code path), sync forward to membership.

CREATE OR REPLACE FUNCTION sync_user_to_membership()
RETURNS TRIGGER AS $$
BEGIN
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

        -- Sync role_id to membership_roles if changed
        IF NEW.role_id IS DISTINCT FROM OLD.role_id AND NEW.role_id IS NOT NULL THEN
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

                    -- Upsert new primary role (FIX: uses assigned_at, not created_at)
                    INSERT INTO membership_roles (workspace_id, membership_id, role_id,
                        is_primary, assigned_at)
                    VALUES (NEW.workspace_id, v_membership_id, NEW.role_id,
                        TRUE, CURRENT_TIMESTAMP)
                    ON CONFLICT (membership_id, role_id)
                    DO UPDATE SET is_primary = TRUE;
                END IF;
            END;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_user_to_membership ON users;

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


-- ==========================================
-- SECTION 6: Recursion-Guarded Rewrites of ALL 3 Sync Functions
-- ==========================================
-- Replaces the existing sync functions with recursion guards
-- using the app.sync_in_progress session variable.

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

        -- Sync role_id if changed (FIX: uses assigned_at, not created_at)
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
                        is_primary, assigned_at)
                    VALUES (NEW.workspace_id, v_membership_id, NEW.role_id,
                        TRUE, CURRENT_TIMESTAMP)
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
    'TRANSITIONAL: Will be renamed or removed in Phase 3.';


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
    'Admin view: all workspace members with aggregated roles array. '
    'Use for workspace admin panel, member listing, and role management UI.';


-- ==========================================
-- SECTION 8: Ownership Guarantee
-- ==========================================

CREATE OR REPLACE FUNCTION check_workspace_owner_exists()
RETURNS TRIGGER AS $$
DECLARE
    v_workspace_id UUID;
    v_owner_count INT;
    v_role_key VARCHAR;
BEGIN
    IF TG_OP = 'DELETE' THEN
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = OLD.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = OLD.membership_id;
    ELSE
        SELECT r.role_key INTO v_role_key FROM roles r WHERE r.id = NEW.role_id;
        SELECT wm.workspace_id INTO v_workspace_id
        FROM workspace_memberships wm WHERE wm.id = NEW.membership_id;
    END IF;

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

DROP TRIGGER IF EXISTS trg_check_workspace_owner_exists ON membership_roles;

CREATE TRIGGER trg_check_workspace_owner_exists
    BEFORE DELETE OR UPDATE ON membership_roles
    FOR EACH ROW EXECUTE FUNCTION check_workspace_owner_exists();

COMMENT ON FUNCTION check_workspace_owner_exists() IS
    'DB-ENFORCED: Prevents removing the last owner from a workspace. '
    'Implements RBAC §13.1 ownership rule.';


CREATE OR REPLACE FUNCTION check_owner_membership_active()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_count INT;
    v_has_owner_role BOOLEAN;
BEGIN
    IF NEW.status IN ('suspended', 'removed') AND OLD.status = 'active' THEN
        SELECT EXISTS(
            SELECT 1 FROM membership_roles mr
            JOIN roles r ON r.id = mr.role_id
            WHERE mr.membership_id = OLD.id AND r.role_key = 'owner'
        ) INTO v_has_owner_role;

        IF v_has_owner_role THEN
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

DROP TRIGGER IF EXISTS trg_check_owner_membership_active ON workspace_memberships;

CREATE TRIGGER trg_check_owner_membership_active
    BEFORE UPDATE ON workspace_memberships
    FOR EACH ROW EXECUTE FUNCTION check_owner_membership_active();

COMMENT ON FUNCTION check_owner_membership_active() IS
    'DB-ENFORCED: Prevents deactivating the last owner membership. '
    'Implements RBAC §13.1.';


-- ==========================================
-- SECTION 9: Deprecation Markers (Comments Only)
-- ==========================================

COMMENT ON COLUMN users.workspace_id IS
    '⚠️ DEPRECATED (Migration 006). Use workspace_memberships for the canonical '
    'user-to-workspace relationship. Synced via bidirectional triggers. '
    'Will be made NULLABLE in Phase 3 (Batch G). Do NOT use for new code.';

COMMENT ON COLUMN users.role_id IS
    '⚠️ DEPRECATED (Migration 006). Use membership_roles for role resolution. '
    'Synced via trg_sync_membership_role_to_user. '
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
    'NOT synced automatically — application must migrate to membership model.';

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

CREATE INDEX IF NOT EXISTS idx_memberships_status_active
    ON workspace_memberships(workspace_id, user_id)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_membership_roles_primary
    ON membership_roles(membership_id)
    WHERE is_primary = TRUE;

-- CREATE INDEX IF NOT EXISTS idx_membership_roles_owner
--     ON membership_roles(membership_id)
--     WHERE role_id IN (SELECT id FROM roles WHERE role_key = 'owner');


-- ==========================================
-- END OF 006 RECOVERY PATCH
-- ==========================================
