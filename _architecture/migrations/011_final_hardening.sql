-- ==========================================
-- Migration 011: Final Architecture Hardening
-- SmartBiz AI — Production Readiness Pass
-- ==========================================
--
-- Scope:
--   §1  Add email column to users table (B1 — auth blocker)
--   §2  Add status column to workspaces table (R4 — lifecycle FSM)
--   §3  Deprecation markers on users.workspace_id and users.role_id (R2, R8)
--   §4  Invite expiry support on workspaces table
--   §5  Child table RLS design documentation
--   §6  Indexes
--   §7  Verification checklist
--
-- Dependencies: migrations 001–010
-- Idempotency: all ALTER TABLE uses IF NOT EXISTS or safe guard patterns
-- Backward compatibility: NO columns dropped, NO constraints removed
--

-- ==========================================
-- §1. ADD EMAIL COLUMN TO USERS TABLE
-- ==========================================
-- Rationale (B1): Authentication requires email+password login per 9_app_flow.md §5.
-- Password reset, token management (BR-MBR-005), and notifications all need email.
-- Decision: globally unique — one email = one human across all workspaces.
-- Multi-workspace access is via workspace_memberships, not duplicate users rows.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'users' AND column_name = 'email'
    ) THEN
        ALTER TABLE users ADD COLUMN email VARCHAR(255);
    END IF;
END $$;

-- Global uniqueness: one email = one human identity.
-- workspace_memberships provides the per-workspace binding.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'uq_users_email'
    ) THEN
        CREATE UNIQUE INDEX uq_users_email ON users(email) WHERE email IS NOT NULL;
    END IF;
END $$;

-- Performance index for email-based login lookups
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'idx_users_email_login'
    ) THEN
        CREATE INDEX idx_users_email_login ON users(email) WHERE email IS NOT NULL AND is_active = TRUE;
    END IF;
END $$;

COMMENT ON COLUMN users.email IS
    'User login identifier. Globally unique across all workspaces (one email = one human). '
    'Multi-workspace access is managed via workspace_memberships, not duplicate user rows. '
    'Nullable during migration rollout — application MUST enforce NOT NULL for new registrations.';

-- ==========================================
-- §2. ADD STATUS COLUMN TO WORKSPACES TABLE
-- ==========================================
-- Rationale (R4): Business rules (BR-WKS-*) define a workspace lifecycle FSM:
--   active → suspended → pending_deletion → deleted
-- But the base schema only has is_active BOOLEAN + subscription_status.
-- These are two DIFFERENT lifecycles:
--   status = operational lifecycle (platform governance — active/suspended/pending_deletion/deleted)
--   subscription_status = billing lifecycle (freemium/trial/active/suspended/cancelled)
-- Both must coexist. Neither replaces the other.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'workspaces' AND column_name = 'status'
    ) THEN
        ALTER TABLE workspaces ADD COLUMN status VARCHAR(50) DEFAULT 'active';
    END IF;
END $$;

-- Add CHECK constraint safely
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_workspace_status'
    ) THEN
        ALTER TABLE workspaces ADD CONSTRAINT chk_workspace_status
            CHECK (status IN ('active', 'suspended', 'pending_deletion', 'deleted'));
    END IF;
END $$;

-- Backfill: derive status from existing state
-- Logic:
--   subscription_status = 'suspended' → status = 'suspended'
--   is_active = FALSE → status = 'suspended'
--   otherwise → status = 'active' (already set by DEFAULT)
UPDATE workspaces
SET status = CASE
    WHEN subscription_status = 'suspended' THEN 'suspended'
    WHEN is_active = FALSE THEN 'suspended'
    ELSE 'active'
END
WHERE status IS NULL OR status = 'active';
-- Note: only updates rows that haven't been explicitly set to a non-active status.
-- Safe for reruns: rows already in 'pending_deletion' or 'deleted' are untouched.

-- Index for status queries (workspace listing, admin dashboard)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'idx_workspaces_status'
    ) THEN
        CREATE INDEX idx_workspaces_status ON workspaces(status);
    END IF;
END $$;

COMMENT ON COLUMN workspaces.status IS
    'Operational lifecycle: active → suspended → pending_deletion → deleted. '
    'This is SEPARATE from subscription_status (billing lifecycle). '
    'A workspace can be status=active + subscription_status=cancelled (grace period), '
    'or status=suspended + subscription_status=active (policy violation). '
    'See BR-WKS-005, BR-PLT-001.';

COMMENT ON COLUMN workspaces.is_active IS
    'DEPRECATED — use workspaces.status for operational lifecycle management. '
    'Retained for backward compatibility. Application code should migrate to status column. '
    'is_active=TRUE ≈ status IN (active). is_active=FALSE ≈ status IN (suspended, pending_deletion, deleted).';

-- ==========================================
-- §3. DEPRECATION MARKERS
-- ==========================================
-- Rationale (R2, R8): Base schema has users.workspace_id (single workspace) and
-- users.role_id (single role). Migration 002 introduced workspace_memberships
-- (multi-workspace) and membership_roles (multi-role). Both models coexist.
-- We deprecate the old columns via comments — NOT by dropping them.

COMMENT ON COLUMN users.workspace_id IS
    'DEPRECATED — DO NOT USE for workspace association in new code. '
    'Use workspace_memberships table (migration 002) instead. '
    'This column exists for backward compatibility only. '
    'A user may belong to multiple workspaces via workspace_memberships. '
    'This FK will be dropped in a future migration once all application code is migrated.';

COMMENT ON COLUMN users.role_id IS
    'DEPRECATED — DO NOT USE for role assignment in new code. '
    'Use membership_roles table (migration 002) instead. '
    'This column exists for backward compatibility only. '
    'A user may hold multiple roles per workspace via membership_roles. '
    'This FK will be dropped in a future migration once all application code is migrated.';

COMMENT ON COLUMN users.permissions IS
    'DEPRECATED — DO NOT USE for permission overrides in new code. '
    'Use user_permission_overrides table (migration 002) instead. '
    'This JSONB column is superseded by the normalized permission system.';

-- ==========================================
-- §4. INVITE EXPIRY SUPPORT
-- ==========================================
-- Rationale: 9_app_flow.md §11 defines invite flow but no expiry policy.
-- Leaked invite codes grant permanent access. Add expiry infra.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'workspaces' AND column_name = 'invite_expires_at'
    ) THEN
        ALTER TABLE workspaces ADD COLUMN invite_expires_at TIMESTAMPTZ;
    END IF;
END $$;

COMMENT ON COLUMN workspaces.invite_expires_at IS
    'Expiry timestamp for the current invite_code. Null = no active invite. '
    'Application MUST reject invite_code if NOW() > invite_expires_at. '
    'Default invite validity: 72 hours (workspace-configurable). '
    'Workspace admins may revoke invites by setting this to NOW().';

-- ==========================================
-- §5. CHILD TABLE RLS DESIGN DOCUMENTATION
-- ==========================================
-- The following workspace-scoped child tables do NOT have their own workspace_id
-- column and therefore do not have independent RLS policies:
--   order_items, invoice_items, journal_lines, product_variants,
--   price_list_items, shipment_items (migration 005), return_items (migration 005),
--   grn_items (migration 005), purchase_order_items (migration 005),
--   credit_note_items (migration 003), bom_lines (base schema as part of bill_of_materials)
--
-- This is BY DESIGN. These child tables:
--   1. Are always accessed via JOIN with their RLS-protected parent table
--   2. Have ON DELETE CASCADE from the workspace-scoped parent
--   3. Cannot be queried independently in any API endpoint
--   4. Inherit tenant isolation from the parent's RLS policy
--
-- If any future feature requires direct child-table queries (e.g., "all order items
-- across orders for reporting"), the child table MUST be given its own workspace_id
-- column and RLS policy at that time.
--
-- This comment serves as the architectural decision record for child-table RLS.

-- ==========================================
-- §6. ADDITIONAL INDEXES
-- ==========================================

-- Composite index for workspace status + subscription queries (admin panels)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_indexes
        WHERE indexname = 'idx_workspaces_status_subscription'
    ) THEN
        CREATE INDEX idx_workspaces_status_subscription
            ON workspaces(status, subscription_status);
    END IF;
END $$;

-- ==========================================
-- §7. VERIFICATION CHECKLIST
-- ==========================================
-- After running this migration, verify:
--
--   [ ] users.email column exists and is VARCHAR(255)
--   [ ] uq_users_email unique index exists (partial — WHERE email IS NOT NULL)
--   [ ] idx_users_email_login index exists (partial — WHERE email IS NOT NULL AND is_active = TRUE)
--   [ ] workspaces.status column exists with CHECK constraint
--   [ ] workspaces.status backfilled from subscription_status / is_active
--   [ ] idx_workspaces_status index exists
--   [ ] idx_workspaces_status_subscription composite index exists
--   [ ] workspaces.invite_expires_at column exists
--   [ ] COMMENT ON users.workspace_id contains 'DEPRECATED'
--   [ ] COMMENT ON users.role_id contains 'DEPRECATED'
--   [ ] COMMENT ON users.permissions contains 'DEPRECATED'
--   [ ] COMMENT ON workspaces.is_active contains 'DEPRECATED'
--   [ ] No existing data is lost or altered (except status backfill)
--   [ ] All ALTER TABLE operations are idempotent (safe for rerun)
--
-- Estimated execution time: < 1 second on empty schema, < 5 seconds on production data.
