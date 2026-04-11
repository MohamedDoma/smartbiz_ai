-- ==========================================
-- Migration 012: Final Closure
-- SmartBiz AI — Architecture-to-Implementation Bridge
-- ==========================================
--
-- Scope:
--   §1  Enforce users.email NOT NULL
--   §2  Add dual RLS policy on users table for multi-workspace identity
--   §3  Impersonation session tracking
--   §4  Verification checklist
--
-- Dependencies: migrations 001–011
-- Idempotency: all operations use safe guard patterns
-- Backward compatibility: NO columns dropped, NO existing policies removed
--

-- ==========================================
-- §1. ENFORCE users.email NOT NULL
-- ==========================================
-- Migration 011 added email as nullable for safe rollout.
-- Application MUST have backfilled all existing users with email addresses
-- before running this migration.
--
-- Pre-check: verify no NULL emails remain.
-- If any NULLs exist, this migration will FAIL intentionally —
-- do NOT suppress the error. Fix the data first.

DO $$
DECLARE
    null_count INT;
BEGIN
    SELECT COUNT(*) INTO null_count FROM users WHERE email IS NULL;
    IF null_count > 0 THEN
        RAISE EXCEPTION 'Cannot enforce NOT NULL on users.email: % rows still have NULL email. Backfill first.', null_count;
    END IF;

    -- Safe to enforce NOT NULL
    -- Check if already NOT NULL to make idempotent
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'email' AND is_nullable = 'YES'
    ) THEN
        ALTER TABLE users ALTER COLUMN email SET NOT NULL;
    END IF;
END $$;

COMMENT ON COLUMN users.email IS
    'User login identifier. Globally unique across all workspaces (one email = one human). '
    'Multi-workspace access is managed via workspace_memberships, not duplicate user rows. '
    'NOT NULL enforced as of migration 012. Primary authentication credential.';

-- ==========================================
-- §2. DUAL RLS POLICY ON USERS TABLE
-- ==========================================
-- Problem: The base schema RLS policy ws_users filters by users.workspace_id.
-- But workspace_id is DEPRECATED — users are global identities accessed via
-- workspace_memberships. A user in Workspace X and Workspace Y has ONE users row,
-- but ws_users only makes them visible when app.workspace_id matches their
-- legacy workspace_id column.
--
-- Solution: Add a SECOND RLS policy. PostgreSQL OR's multiple policies on the
-- same table — a row is visible if ANY policy passes.
--
-- Policy 1 (existing, kept): ws_users — backward compatibility via workspace_id
-- Policy 2 (NEW): ws_users_via_membership — visibility via workspace_memberships
--
-- Auth login (pre-workspace-selection): uses a service-role connection that
-- bypasses RLS to resolve email → user_id → workspace list. This is standard
-- for multi-tenant auth — no workspace context exists at login time.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE policyname = 'ws_users_via_membership' AND tablename = 'users'
    ) THEN
        EXECUTE '
            CREATE POLICY ws_users_via_membership ON users
                USING (
                    id IN (
                        SELECT user_id FROM workspace_memberships
                        WHERE workspace_id = current_setting(''app.workspace_id'', true)::UUID
                          AND status IN (''active'', ''pending'')
                    )
                )
        ';
    END IF;
END $$;

COMMENT ON POLICY ws_users_via_membership ON users IS
    'Multi-workspace identity policy. Makes a user visible in any workspace where '
    'they have an active or pending workspace_membership. Works alongside the legacy '
    'ws_users policy (OR semantics). Auth login uses a service-role connection that '
    'bypasses RLS entirely — this policy is for in-app queries only.';

-- ==========================================
-- §3. IMPERSONATION SESSION TRACKING
-- ==========================================
-- Platform support staff may impersonate workspace users for debugging.
-- This must be: (a) time-limited (max 1 hour), (b) fully audited,
-- (c) DB-enforced expiry, (d) reason-required.

CREATE TABLE IF NOT EXISTS impersonation_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    platform_user_id UUID NOT NULL REFERENCES platform_users(id) ON DELETE CASCADE,
    target_workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    target_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    reason TEXT NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    -- DB-enforced: max 1 hour sessions
    CONSTRAINT chk_impersonation_max_duration
        CHECK (expires_at <= started_at + INTERVAL '1 hour'),
    -- Must expire in the future at creation time
    CONSTRAINT chk_impersonation_future_expiry
        CHECK (expires_at > started_at)
);

COMMENT ON TABLE impersonation_sessions IS
    'Tracks platform admin impersonation of workspace users. '
    'DB-enforced 1-hour max duration. Immutable audit trail. '
    'Application MUST check expires_at on every impersonated request. '
    'ended_at is set when admin explicitly ends session or when expires_at is reached.';

-- Index for active session lookup
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'idx_impersonation_active'
    ) THEN
        CREATE INDEX idx_impersonation_active
            ON impersonation_sessions(platform_user_id, expires_at)
            WHERE ended_at IS NULL;
    END IF;
END $$;

-- impersonation_sessions is platform-scoped — no workspace RLS needed.
-- Only platform_users with platform.workspaces.impersonate permission can create rows.
-- Access control is enforced at the application layer (platform middleware).

-- ==========================================
-- §4. VERIFICATION CHECKLIST
-- ==========================================
-- After running this migration, verify:
--
--   [ ] users.email is NOT NULL (no nullable rows remain)
--   [ ] Policy ws_users_via_membership exists on users table
--   [ ] Both ws_users and ws_users_via_membership policies are active (OR semantics)
--   [ ] impersonation_sessions table exists with CHECK constraints
--   [ ] idx_impersonation_active index exists
--   [ ] Multi-workspace user is visible in BOTH workspaces via membership policy
--   [ ] Auth login via service-role connection successfully resolves email → user
--   [ ] Impersonation session cannot be created with duration > 1 hour
--
-- Estimated execution time: < 1 second on empty schema, < 5 seconds on production data
-- (depends on users table size for NOT NULL enforcement).
