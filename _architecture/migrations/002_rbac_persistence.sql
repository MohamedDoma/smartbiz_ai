-- ==========================================
-- SmartBiz AI — Migration 002: RBAC Persistence
-- Batch B from SQL Patch Execution Pack
-- ==========================================
--
-- Purpose:
--   Implement the workspace membership model and full RBAC persistence
--   aligned with the approved RBAC specification (7_roles_permissions_matrix.md).
--
-- Prerequisites:
--   Base schema (1_database_schema.sql) + 001_additive_foundation.sql
--
-- Risk: MEDIUM — backfill required for workspace_memberships from users table.
--
-- ==========================================
-- ARCHITECTURAL DECISIONS (documented per correction pass requirements)
-- ==========================================
--
-- D1. Role persistence model: JSONB (Option B)
--   The existing roles.permissions JSONB column is RETAINED as the canonical
--   role-permission persistence model. Reasons:
--   (a) The approved RBAC spec (§1.1) explicitly states: "roles.permissions JSONB
--       via workspace_memberships" as the workspace role storage model.
--   (b) roles.permissions stores [{key, scopes}] per role — this is already the
--       authoritative source for role-level permission resolution.
--   (c) A normalized workspace_role_permissions table is intentionally NOT created
--       because: the 209 permission keys × 17 template roles × N workspaces would
--       generate tens of thousands of rows for pure lookup data, while JSONB gives
--       O(1) role-permissions resolution per role load. The JSONB is validated at
--       the application layer against permission_definitions.
--   (d) Custom roles are created by cloning a template role's JSONB and modifying it.
--       This is simpler and faster than managing a join table.
--
-- D2. Single primary role + multi-role via junction table
--   workspace_memberships has NO role_id column. All role assignments go through
--   the membership_roles junction table. This supports:
--   (a) Single-role assignment (most common: one row in membership_roles).
--   (b) Multi-role assignment (RBAC spec §3.2 rule 4: "If a user has multiple
--       roles (custom configuration), the widest scope wins for each permission").
--   Permission resolution: UNION of all assigned roles' permissions JSONB,
--   widest scope wins per permission key.
--
-- D3. Tenant-safe actor references
--   manager_id and granted_by are stored as membership references, not user
--   references, to ensure workspace-safe FK validation without depending on
--   users.workspace_id (which is being deprecated).
--   - workspace_memberships.manager_membership_id → FK workspace_memberships(id)
--   - user_permission_overrides.granted_by_membership_id → FK workspace_memberships(id)
--   This guarantees the referenced actor is in the same workspace.
--
-- D4. Permission key referential integrity
--   user_permission_overrides.permission_key has a FK to permission_definitions.key.
--   permission_delegation_items.permission_key has a FK to permission_definitions.key.
--   This provides DB-level integrity, not just app-layer validation.
--
-- D5. Delegation permissions: normalized
--   permission_delegations.permission_keys JSONB is replaced by a normalized
--   permission_delegation_items child table. Each delegated key is a row with
--   FK to permission_definitions. This enables per-key querying, reporting,
--   and DB-level referential integrity.
--
-- D6. Platform RBAC boundary
--   Platform RBAC: persisted via platform_users.role CHECK enum.
--     - 5 platform roles, 33 platform permission keys.
--     - Role-to-permission mapping is resolved at the application layer using
--       the RBAC spec §6.2 matrix. No DB join table needed — the matrix is static.
--     - platform_users is NOT workspace-scoped (no RLS).
--   Workspace RBAC: persisted via roles.permissions JSONB + membership_roles +
--     user_permission_overrides + permission_delegations.
--     - Workspace-scoped via RLS on all RBAC tables.
--     - Permission resolution order: role permissions → user overrides →
--       active delegations. Deny overrides take precedence over grants.
--
-- D7. Transitional coexistence
--   users.workspace_id, users.role_id, users.department_id, etc. are NOT
--   removed. Batch F handles deprecation markers. Batch G handles renames.
--   New code MUST use workspace_memberships. Old code continues to work.
--
-- ==========================================


-- ==========================================
-- SECTION 1: Platform Role Fix
-- ==========================================
-- Platform RBAC: persisted via platform_users.role CHECK enum only.
-- The approved RBAC spec (§6.1) defines 5 platform roles.
-- The existing schema only has 4. Adding 'platform_engineer'.
-- Platform role-to-permission resolution remains app-layer (static matrix from §6.2).

ALTER TABLE platform_users
    DROP CONSTRAINT IF EXISTS platform_users_role_check;

ALTER TABLE platform_users
    ADD CONSTRAINT platform_users_role_check
    CHECK (role IN ('platform_owner', 'platform_admin', 'platform_support', 'platform_operations', 'platform_engineer'));


-- ==========================================
-- SECTION 2: Permission Definitions (Platform-scoped reference table)
-- ==========================================
-- Workspace RBAC: this table is the authoritative catalogue of all valid permission keys.
-- Used for: referential integrity on overrides and delegations (DB-level FK),
-- UI permission picker, and automated permission validation.
-- NOT workspace-scoped — this is a global platform reference.

CREATE TABLE permission_definitions (
    key VARCHAR(100) PRIMARY KEY,
    module VARCHAR(50) NOT NULL,
    entity VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    scope_type VARCHAR(20) NOT NULL DEFAULT 'workspace' CHECK (scope_type IN ('workspace', 'platform')),
    applicable_scopes VARCHAR(20)[] NOT NULL DEFAULT ARRAY['ws'],
        -- Which scope codes are valid for this permission (from §3.3)
        -- e.g. ARRAY['own','team','branch','ws'] for crm.*
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE permission_definitions IS 'Platform-scoped read-only catalogue of all 242 permission keys (209 workspace + 33 platform). Provides DB-level FK target for override and delegation integrity.';
COMMENT ON COLUMN permission_definitions.applicable_scopes IS 'Valid scope codes for this permission per RBAC spec §3.3. Application layer validates scope assignments against this array.';

CREATE INDEX idx_perm_defs_module ON permission_definitions(module);
CREATE INDEX idx_perm_defs_scope_type ON permission_definitions(scope_type);


-- ==========================================
-- SECTION 3: Roles Table Enhancement
-- ==========================================
-- Workspace RBAC: roles.permissions JSONB is the canonical role-permission store.
-- This is the authoritative persistence model (Decision D1 above).
-- Each role's permissions JSONB contains: [{"key": "...", "scope": "..."}]

ALTER TABLE roles
    ADD COLUMN IF NOT EXISTS role_key VARCHAR(50),
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS hierarchy_level INT NOT NULL DEFAULT 10
        CHECK (hierarchy_level >= 0 AND hierarchy_level <= 100),
    ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_default BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_deletable BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN roles.role_key IS 'Machine-readable identifier for template roles (e.g. owner, admin, employee). NULL for custom roles.';
COMMENT ON COLUMN roles.permissions IS 'JSONB array of {key, scope} objects. This is the canonical role-permission persistence model. Custom roles are created by cloning and modifying this JSONB.';
COMMENT ON COLUMN roles.hierarchy_level IS 'Role assignment authority: users can only assign roles with equal or lower level. Range: 0-100.';
COMMENT ON COLUMN roles.is_system IS 'System roles (owner, co_owner) cannot be deleted or have core permissions removed.';
COMMENT ON COLUMN roles.is_default IS 'New members auto-assigned this role when no explicit role is specified.';
COMMENT ON COLUMN roles.is_deletable IS 'FALSE = protected from deletion (e.g. owner, co_owner). TRUE = can be deleted by authorized users.';

CREATE UNIQUE INDEX uq_roles_role_key_per_workspace
    ON roles(workspace_id, role_key)
    WHERE role_key IS NOT NULL;


-- ==========================================
-- SECTION 4: Workspace Memberships
-- ==========================================
-- The central table binding users to workspaces. Replaces users.workspace_id
-- for multi-workspace support.
--
-- NOTE: No role_id column here (Decision D2). Role assignments go through
-- membership_roles junction table to support multi-role per membership.

CREATE TABLE workspace_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Org-structure placement (workspace-scoped FKs)
    department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
    branch_id UUID REFERENCES branches(id) ON DELETE SET NULL,
    shift_id UUID REFERENCES shifts(id) ON DELETE SET NULL,

    -- Manager: references another membership in the SAME workspace.
    -- Uses membership (not user) to ensure workspace-safe FK validation.
    manager_membership_id UUID REFERENCES workspace_memberships(id) ON DELETE SET NULL,

    -- Membership lifecycle (FSM: pending → active → suspended → removed)
    status VARCHAR(50) NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'suspended', 'removed')),

    -- HR-relevant data (per-workspace, not global)
    hire_date DATE,
    base_salary DECIMAL(10, 2) DEFAULT 0.00 CHECK (base_salary IS NULL OR base_salary >= 0),
    annual_leave_balance INT DEFAULT 21 CHECK (annual_leave_balance IS NULL OR annual_leave_balance >= 0),

    -- Warehouse assignments for 'wh' scope resolution
    assigned_warehouses JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Lifecycle timestamps
    joined_at TIMESTAMPTZ,
    suspended_at TIMESTAMPTZ,
    removed_at TIMESTAMPTZ,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    UNIQUE(workspace_id, user_id),
    CHECK (manager_membership_id IS NULL OR manager_membership_id <> id)
);

COMMENT ON TABLE workspace_memberships IS 'Binds users to workspaces. Role assignments via membership_roles. Org-structure and HR data are per-workspace. Replaces users.workspace_id for multi-workspace support.';
COMMENT ON COLUMN workspace_memberships.manager_membership_id IS 'Self-FK to another membership in the same workspace. Identifies direct manager for team scope resolution.';
COMMENT ON COLUMN workspace_memberships.assigned_warehouses IS 'JSONB array of warehouse UUIDs for wh scope resolution.';


-- ==========================================
-- SECTION 5: Membership Roles (Junction Table — Multi-Role Support)
-- ==========================================
-- Decision D2: Supports multi-role assignment per membership.
-- Permission resolution: UNION of all assigned roles permissions JSONB;
-- widest scope wins per permission key (RBAC spec §3.2 rule 4).
-- Most memberships will have exactly one row (single role).

CREATE TABLE membership_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    membership_id UUID NOT NULL REFERENCES workspace_memberships(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    is_primary BOOLEAN NOT NULL DEFAULT FALSE,
        -- Exactly one role per membership should be marked primary (for UI display).
        -- Enforced at application layer (partial unique index below as advisory).
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- One assignment per role per membership
    UNIQUE(membership_id, role_id)
);

COMMENT ON TABLE membership_roles IS 'Junction table: assigns one or more roles to a workspace membership. Permission resolution unions all role permissions; widest scope wins per key.';
COMMENT ON COLUMN membership_roles.is_primary IS 'UI display hint. Exactly one primary role per membership, enforced at application layer.';

-- Advisory index to help enforce single primary role per membership
CREATE UNIQUE INDEX uq_membership_roles_primary
    ON membership_roles(membership_id)
    WHERE is_primary = TRUE;


-- ==========================================
-- SECTION 6: User Permission Overrides
-- ==========================================
-- Per-user grant/deny of specific permissions beyond their role(s).
-- Implements RBAC spec §3.2 rule 5: "User-level overrides can grant a wider scope."
-- Also supports deny: explicitly block a permission even if the role grants it.
-- Resolution: deny overrides take precedence over grants.

CREATE TABLE user_permission_overrides (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    membership_id UUID NOT NULL REFERENCES workspace_memberships(id) ON DELETE CASCADE,
    -- DB-level FK ensures only valid permission keys can be overridden
    permission_key VARCHAR(100) NOT NULL REFERENCES permission_definitions(key) ON DELETE CASCADE,
    scope VARCHAR(20) NOT NULL CHECK (scope IN ('own', 'team', 'dept', 'branch', 'wh', 'ws')),
    override_type VARCHAR(10) NOT NULL CHECK (override_type IN ('grant', 'deny')),
    reason TEXT, -- Audit trail: why this override was applied
    -- Granter identified by their membership (workspace-safe, no users.workspace_id dependency)
    granted_by_membership_id UUID NOT NULL REFERENCES workspace_memberships(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ, -- NULL = permanent until manually revoked
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- One override per permission per membership
    UNIQUE(workspace_id, membership_id, permission_key)
);

COMMENT ON TABLE user_permission_overrides IS 'Per-user permission grants/denials that override role-level permissions. Deny takes precedence over grant in resolution.';
COMMENT ON COLUMN user_permission_overrides.override_type IS 'grant = add permission beyond role; deny = block even if role grants it.';
COMMENT ON COLUMN user_permission_overrides.granted_by_membership_id IS 'The membership of the user who applied this override. Workspace-safe FK (no dependency on users.workspace_id).';
COMMENT ON COLUMN user_permission_overrides.expires_at IS 'NULL = permanent. If set, override is inactive after this time; cleanup via scheduled job.';


-- ==========================================
-- SECTION 7: Permission Delegations (Header)
-- ==========================================
-- Temporary transfer of specific permissions from one member to another.
-- Bounded by mandatory time window + reason for audit compliance.

CREATE TABLE permission_delegations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id UUID NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
    delegator_membership_id UUID NOT NULL REFERENCES workspace_memberships(id) ON DELETE CASCADE,
    delegate_membership_id UUID NOT NULL REFERENCES workspace_memberships(id) ON DELETE CASCADE,

    -- Validity window (mandatory, bounded)
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    reason TEXT NOT NULL,

    -- Lifecycle
    status VARCHAR(50) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'expired', 'revoked')),
    revoked_at TIMESTAMPTZ,
    revoked_by UUID REFERENCES users(id) ON DELETE SET NULL,

    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
    CHECK (end_at > start_at),
    CHECK (delegator_membership_id <> delegate_membership_id),
    UNIQUE(workspace_id, delegator_membership_id, delegate_membership_id, start_at)
);

COMMENT ON TABLE permission_delegations IS 'Temporary permission transfers between workspace members. Bounded by time window. Individual permissions listed in permission_delegation_items.';
COMMENT ON COLUMN permission_delegations.status IS 'active = in effect; expired = past end_at; revoked = manually cancelled.';
COMMENT ON COLUMN permission_delegations.revoked_by IS 'User who revoked (kept as users FK — actor identity, not workspace binding). Application verifies revoker has membership.';


-- ==========================================
-- SECTION 8: Permission Delegation Items (Normalized — Decision D5)
-- ==========================================
-- Each delegated permission key is a separate row with DB-level FK
-- to permission_definitions. Replaces the JSONB array approach.

CREATE TABLE permission_delegation_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    delegation_id UUID NOT NULL REFERENCES permission_delegations(id) ON DELETE CASCADE,
    permission_key VARCHAR(100) NOT NULL REFERENCES permission_definitions(key) ON DELETE CASCADE,
    scope VARCHAR(20) NOT NULL CHECK (scope IN ('own', 'team', 'dept', 'branch', 'wh', 'ws')),

    -- One delegation per key per delegation record
    UNIQUE(delegation_id, permission_key)
);

COMMENT ON TABLE permission_delegation_items IS 'Normalized child table for permission_delegations. Each row = one delegated permission key with DB-level FK integrity.';
COMMENT ON COLUMN permission_delegation_items.scope IS 'The scope at which this permission is delegated. Cannot exceed the delegator''s own scope for this key (enforced at application layer).';


-- ==========================================
-- SECTION 9: updated_at Triggers
-- ==========================================

CREATE TRIGGER trg_workspace_memberships_updated
    BEFORE UPDATE ON workspace_memberships
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_user_permission_overrides_updated
    BEFORE UPDATE ON user_permission_overrides
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

CREATE TRIGGER trg_permission_delegations_updated
    BEFORE UPDATE ON permission_delegations
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();


-- ==========================================
-- SECTION 10: Indexes
-- ==========================================

-- Roles (new columns)
CREATE INDEX idx_roles_role_key ON roles(role_key) WHERE role_key IS NOT NULL;
CREATE INDEX idx_roles_hierarchy ON roles(hierarchy_level);
CREATE INDEX idx_roles_system ON roles(is_system) WHERE is_system = TRUE;

-- Workspace memberships
CREATE INDEX idx_memberships_workspace ON workspace_memberships(workspace_id);
CREATE INDEX idx_memberships_user ON workspace_memberships(user_id);
CREATE INDEX idx_memberships_department ON workspace_memberships(department_id);
CREATE INDEX idx_memberships_branch ON workspace_memberships(branch_id);
CREATE INDEX idx_memberships_shift ON workspace_memberships(shift_id);
CREATE INDEX idx_memberships_manager ON workspace_memberships(manager_membership_id);
CREATE INDEX idx_memberships_status ON workspace_memberships(status);
CREATE INDEX idx_memberships_ws_user ON workspace_memberships(workspace_id, user_id);
CREATE INDEX idx_memberships_ws_status ON workspace_memberships(workspace_id, status);
CREATE INDEX idx_memberships_ws_dept ON workspace_memberships(workspace_id, department_id);
CREATE INDEX idx_memberships_ws_branch ON workspace_memberships(workspace_id, branch_id);

-- Membership roles
CREATE INDEX idx_membership_roles_workspace ON membership_roles(workspace_id);
CREATE INDEX idx_membership_roles_membership ON membership_roles(membership_id);
CREATE INDEX idx_membership_roles_role ON membership_roles(role_id);
CREATE INDEX idx_membership_roles_ws_membership ON membership_roles(workspace_id, membership_id);

-- User permission overrides
CREATE INDEX idx_overrides_workspace ON user_permission_overrides(workspace_id);
CREATE INDEX idx_overrides_membership ON user_permission_overrides(membership_id);
CREATE INDEX idx_overrides_permission ON user_permission_overrides(permission_key);
CREATE INDEX idx_overrides_type ON user_permission_overrides(override_type);
CREATE INDEX idx_overrides_granted_by ON user_permission_overrides(granted_by_membership_id);
-- Active non-expired overrides (common query path)
CREATE INDEX idx_overrides_active ON user_permission_overrides(membership_id, permission_key)
    WHERE expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP;

-- Permission delegations
CREATE INDEX idx_delegations_workspace ON permission_delegations(workspace_id);
CREATE INDEX idx_delegations_delegator ON permission_delegations(delegator_membership_id);
CREATE INDEX idx_delegations_delegate ON permission_delegations(delegate_membership_id);
CREATE INDEX idx_delegations_status ON permission_delegations(status);
CREATE INDEX idx_delegations_active ON permission_delegations(delegate_membership_id, status)
    WHERE status = 'active';
CREATE INDEX idx_delegations_end_at ON permission_delegations(end_at)
    WHERE status = 'active';

-- Permission delegation items
CREATE INDEX idx_delegation_items_delegation ON permission_delegation_items(delegation_id);
CREATE INDEX idx_delegation_items_permission ON permission_delegation_items(permission_key);


-- ==========================================
-- SECTION 11: Composite Unique Constraints (workspace FK validation)
-- ==========================================

ALTER TABLE workspace_memberships ADD CONSTRAINT uq_memberships_ws_id UNIQUE (workspace_id, id);
ALTER TABLE membership_roles ADD CONSTRAINT uq_membership_roles_ws_id UNIQUE (workspace_id, id);


-- ==========================================
-- SECTION 12: Workspace FK Isolation Triggers
-- ==========================================
-- Decision D3: All workspace-scoped FK references validate via workspace-scoped
-- parent tables (departments, branches, shifts, workspace_memberships, roles).
-- No dependency on users.workspace_id for workspace FK isolation.

CREATE TRIGGER trg_memberships_ws_check
    BEFORE INSERT OR UPDATE ON workspace_memberships
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'department_id:departments,branch_id:branches,shift_id:shifts,manager_membership_id:workspace_memberships'
    );

CREATE TRIGGER trg_membership_roles_ws_check
    BEFORE INSERT OR UPDATE ON membership_roles
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'membership_id:workspace_memberships,role_id:roles'
    );

CREATE TRIGGER trg_overrides_ws_check
    BEFORE INSERT OR UPDATE ON user_permission_overrides
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'membership_id:workspace_memberships,granted_by_membership_id:workspace_memberships'
    );

CREATE TRIGGER trg_delegations_ws_check
    BEFORE INSERT OR UPDATE ON permission_delegations
    FOR EACH ROW EXECUTE FUNCTION validate_workspace_fk(
        'delegator_membership_id:workspace_memberships,delegate_membership_id:workspace_memberships'
    );


-- ==========================================
-- SECTION 13: Row Level Security (RLS)
-- ==========================================

-- Workspace RBAC tables: all workspace-scoped

ALTER TABLE workspace_memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_memberships ON workspace_memberships
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE membership_roles ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_membership_roles ON membership_roles
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE user_permission_overrides ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_overrides ON user_permission_overrides
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

ALTER TABLE permission_delegations ENABLE ROW LEVEL SECURITY;
CREATE POLICY ws_delegations ON permission_delegations
    USING (workspace_id = current_setting('app.workspace_id', true)::UUID)
    WITH CHECK (workspace_id = current_setting('app.workspace_id', true)::UUID);

-- permission_delegation_items: no direct workspace_id column.
-- Tenant isolation is enforced by the parent permission_delegations RLS.
-- Items are only accessible via JOIN on permission_delegations (which is RLS-protected).
-- No direct RLS needed; all access paths go through the parent.

-- permission_definitions: platform-scoped (read-only, no RLS).
-- Access control enforced at application layer via platform middleware.


-- ==========================================
-- SECTION 14: Transitional Coexistence
-- ==========================================
-- users.workspace_id, users.role_id, users.department_id, users.branch_id,
-- users.shift_id, users.manager_id, users.base_salary, users.hire_date,
-- users.annual_leave_balance, users.approval_status, users.permissions
-- are NOT removed in Batch B.
--
-- Migration path:
--   1. Batch B: workspace_memberships + membership_roles created, backfilled
--   2. Application layer migrates to read/write via memberships
--   3. Batch F: adds deprecation markers on users columns
--   4. Batch G: renames deprecated tables/columns after confirmed zero usage
--
-- During transition:
--   - Both users.workspace_id and workspace_memberships coexist
--   - New code MUST use workspace_memberships + membership_roles
--   - Old code continues via users.workspace_id (unchanged)
--   - Backfill ensures consistency (007_backfill_migrations.sql)


-- ==========================================
-- SECTION 15: Seed permission_definitions (209 workspace + 33 platform = 242 total)
-- ==========================================

-- -----------------------------------------------
-- Admin Module (25 keys) — applicable scopes: ws only
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('admin.workspace.view', 'admin', 'workspace', 'view', 'workspace', ARRAY['ws']),
    ('admin.workspace.configure', 'admin', 'workspace', 'configure', 'workspace', ARRAY['ws']),
    ('admin.ownership.transfer', 'admin', 'ownership', 'transfer', 'workspace', ARRAY['ws']),
    ('admin.ownership.delete', 'admin', 'ownership', 'delete', 'workspace', ARRAY['ws']),
    ('admin.subscription.view', 'admin', 'subscription', 'view', 'workspace', ARRAY['ws']),
    ('admin.subscription.manage', 'admin', 'subscription', 'manage', 'workspace', ARRAY['ws']),
    ('admin.branches.view', 'admin', 'branches', 'view', 'workspace', ARRAY['ws','branch']),
    ('admin.branches.create', 'admin', 'branches', 'create', 'workspace', ARRAY['ws']),
    ('admin.branches.update', 'admin', 'branches', 'update', 'workspace', ARRAY['ws','branch']),
    ('admin.branches.delete', 'admin', 'branches', 'delete', 'workspace', ARRAY['ws']),
    ('admin.departments.view', 'admin', 'departments', 'view', 'workspace', ARRAY['ws','branch','dept']),
    ('admin.departments.create', 'admin', 'departments', 'create', 'workspace', ARRAY['ws']),
    ('admin.departments.update', 'admin', 'departments', 'update', 'workspace', ARRAY['ws','dept']),
    ('admin.departments.delete', 'admin', 'departments', 'delete', 'workspace', ARRAY['ws']),
    ('admin.roles.view', 'admin', 'roles', 'view', 'workspace', ARRAY['ws']),
    ('admin.roles.create', 'admin', 'roles', 'create', 'workspace', ARRAY['ws']),
    ('admin.roles.update', 'admin', 'roles', 'update', 'workspace', ARRAY['ws']),
    ('admin.roles.delete', 'admin', 'roles', 'delete', 'workspace', ARRAY['ws']),
    ('admin.users.view', 'admin', 'users', 'view', 'workspace', ARRAY['ws','branch','dept','team','own']),
    ('admin.users.create', 'admin', 'users', 'create', 'workspace', ARRAY['ws']),
    ('admin.users.update', 'admin', 'users', 'update', 'workspace', ARRAY['ws','own']),
    ('admin.users.delete', 'admin', 'users', 'delete', 'workspace', ARRAY['ws']),
    ('admin.users.approve', 'admin', 'users', 'approve', 'workspace', ARRAY['ws','branch','dept']),
    ('admin.sequences.view', 'admin', 'sequences', 'view', 'workspace', ARRAY['ws']),
    ('admin.sequences.configure', 'admin', 'sequences', 'configure', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Inventory Module (31 keys) — applicable scopes: wh, branch, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('inventory.products.view', 'inventory', 'products', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.products.create', 'inventory', 'products', 'create', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.products.update', 'inventory', 'products', 'update', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.products.delete', 'inventory', 'products', 'delete', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.products.export', 'inventory', 'products', 'export', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.categories.view', 'inventory', 'categories', 'view', 'workspace', ARRAY['ws']),
    ('inventory.categories.create', 'inventory', 'categories', 'create', 'workspace', ARRAY['ws']),
    ('inventory.categories.update', 'inventory', 'categories', 'update', 'workspace', ARRAY['ws']),
    ('inventory.categories.delete', 'inventory', 'categories', 'delete', 'workspace', ARRAY['ws']),
    ('inventory.variants.view', 'inventory', 'variants', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.variants.create', 'inventory', 'variants', 'create', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.variants.update', 'inventory', 'variants', 'update', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.variants.delete', 'inventory', 'variants', 'delete', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.warehouses.view', 'inventory', 'warehouses', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.warehouses.create', 'inventory', 'warehouses', 'create', 'workspace', ARRAY['ws']),
    ('inventory.warehouses.update', 'inventory', 'warehouses', 'update', 'workspace', ARRAY['wh','ws']),
    ('inventory.warehouses.delete', 'inventory', 'warehouses', 'delete', 'workspace', ARRAY['ws']),
    ('inventory.levels.view', 'inventory', 'levels', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.levels.adjust', 'inventory', 'levels', 'adjust', 'workspace', ARRAY['wh','ws']),
    ('inventory.batches.view', 'inventory', 'batches', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.batches.create', 'inventory', 'batches', 'create', 'workspace', ARRAY['wh','ws']),
    ('inventory.batches.update', 'inventory', 'batches', 'update', 'workspace', ARRAY['wh','ws']),
    ('inventory.units.view', 'inventory', 'units', 'view', 'workspace', ARRAY['ws']),
    ('inventory.units.create', 'inventory', 'units', 'create', 'workspace', ARRAY['ws']),
    ('inventory.units.update', 'inventory', 'units', 'update', 'workspace', ARRAY['ws']),
    ('inventory.units.delete', 'inventory', 'units', 'delete', 'workspace', ARRAY['ws']),
    ('inventory.transfers.view', 'inventory', 'transfers', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.transfers.create', 'inventory', 'transfers', 'create', 'workspace', ARRAY['wh','ws']),
    ('inventory.transfers.approve', 'inventory', 'transfers', 'approve', 'workspace', ARRAY['ws']),
    ('inventory.logs.view', 'inventory', 'logs', 'view', 'workspace', ARRAY['wh','branch','ws']),
    ('inventory.logs.export', 'inventory', 'logs', 'export', 'workspace', ARRAY['wh','branch','ws']);

-- -----------------------------------------------
-- Sales Module (28 keys) — applicable scopes: own, branch, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('sales.orders.view', 'sales', 'orders', 'view', 'workspace', ARRAY['own','branch','ws']),
    ('sales.orders.create', 'sales', 'orders', 'create', 'workspace', ARRAY['own','branch','ws']),
    ('sales.orders.update', 'sales', 'orders', 'update', 'workspace', ARRAY['own','branch','ws']),
    ('sales.orders.cancel', 'sales', 'orders', 'cancel', 'workspace', ARRAY['own','branch','ws']),
    ('sales.orders.export', 'sales', 'orders', 'export', 'workspace', ARRAY['own','branch','ws']),
    ('sales.pos.view', 'sales', 'pos', 'view', 'workspace', ARRAY['branch','ws']),
    ('sales.pos.configure', 'sales', 'pos', 'configure', 'workspace', ARRAY['ws']),
    ('sales.pos_sessions.open', 'sales', 'pos_sessions', 'open', 'workspace', ARRAY['own','branch','ws']),
    ('sales.pos_sessions.close', 'sales', 'pos_sessions', 'close', 'workspace', ARRAY['own','branch','ws']),
    ('sales.pos_sessions.view', 'sales', 'pos_sessions', 'view', 'workspace', ARRAY['own','branch','ws']),
    ('sales.dining.view', 'sales', 'dining', 'view', 'workspace', ARRAY['branch','ws']),
    ('sales.dining.manage', 'sales', 'dining', 'manage', 'workspace', ARRAY['branch','ws']),
    ('sales.pricing.view', 'sales', 'pricing', 'view', 'workspace', ARRAY['ws']),
    ('sales.pricing.create', 'sales', 'pricing', 'create', 'workspace', ARRAY['ws']),
    ('sales.pricing.update', 'sales', 'pricing', 'update', 'workspace', ARRAY['ws']),
    ('sales.pricing.delete', 'sales', 'pricing', 'delete', 'workspace', ARRAY['ws']),
    ('sales.promotions.view', 'sales', 'promotions', 'view', 'workspace', ARRAY['ws']),
    ('sales.promotions.create', 'sales', 'promotions', 'create', 'workspace', ARRAY['ws']),
    ('sales.promotions.update', 'sales', 'promotions', 'update', 'workspace', ARRAY['ws']),
    ('sales.promotions.delete', 'sales', 'promotions', 'delete', 'workspace', ARRAY['ws']),
    ('sales.coupons.view', 'sales', 'coupons', 'view', 'workspace', ARRAY['ws']),
    ('sales.coupons.create', 'sales', 'coupons', 'create', 'workspace', ARRAY['ws']),
    ('sales.coupons.update', 'sales', 'coupons', 'update', 'workspace', ARRAY['ws']),
    ('sales.coupons.delete', 'sales', 'coupons', 'delete', 'workspace', ARRAY['ws']),
    ('sales.bookings.view', 'sales', 'bookings', 'view', 'workspace', ARRAY['own','branch','ws']),
    ('sales.bookings.create', 'sales', 'bookings', 'create', 'workspace', ARRAY['own','branch','ws']),
    ('sales.bookings.update', 'sales', 'bookings', 'update', 'workspace', ARRAY['own','branch','ws']),
    ('sales.bookings.cancel', 'sales', 'bookings', 'cancel', 'workspace', ARRAY['own','branch','ws']);

-- -----------------------------------------------
-- Purchasing Module (5 keys) — applicable scopes: own, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('purchasing.orders.view', 'purchasing', 'orders', 'view', 'workspace', ARRAY['own','ws']),
    ('purchasing.orders.create', 'purchasing', 'orders', 'create', 'workspace', ARRAY['own','ws']),
    ('purchasing.orders.update', 'purchasing', 'orders', 'update', 'workspace', ARRAY['own','ws']),
    ('purchasing.orders.cancel', 'purchasing', 'orders', 'cancel', 'workspace', ARRAY['own','ws']),
    ('purchasing.orders.approve', 'purchasing', 'orders', 'approve', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Finance Module (36 keys) — applicable scopes: ws only
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('finance.invoices.view', 'finance', 'invoices', 'view', 'workspace', ARRAY['ws']),
    ('finance.invoices.create', 'finance', 'invoices', 'create', 'workspace', ARRAY['ws']),
    ('finance.invoices.update', 'finance', 'invoices', 'update', 'workspace', ARRAY['ws']),
    ('finance.invoices.cancel', 'finance', 'invoices', 'cancel', 'workspace', ARRAY['ws']),
    ('finance.invoices.approve', 'finance', 'invoices', 'approve', 'workspace', ARRAY['ws']),
    ('finance.invoices.export', 'finance', 'invoices', 'export', 'workspace', ARRAY['ws']),
    ('finance.payments.view', 'finance', 'payments', 'view', 'workspace', ARRAY['ws']),
    ('finance.payments.create', 'finance', 'payments', 'create', 'workspace', ARRAY['ws']),
    ('finance.payments.export', 'finance', 'payments', 'export', 'workspace', ARRAY['ws']),
    ('finance.transactions.view', 'finance', 'transactions', 'view', 'workspace', ARRAY['ws']),
    ('finance.transactions.create', 'finance', 'transactions', 'create', 'workspace', ARRAY['ws']),
    ('finance.transactions.update', 'finance', 'transactions', 'update', 'workspace', ARRAY['ws']),
    ('finance.transactions.delete', 'finance', 'transactions', 'delete', 'workspace', ARRAY['ws']),
    ('finance.transactions.export', 'finance', 'transactions', 'export', 'workspace', ARRAY['ws']),
    ('finance.accounts.view', 'finance', 'accounts', 'view', 'workspace', ARRAY['ws']),
    ('finance.accounts.create', 'finance', 'accounts', 'create', 'workspace', ARRAY['ws']),
    ('finance.accounts.update', 'finance', 'accounts', 'update', 'workspace', ARRAY['ws']),
    ('finance.accounts.delete', 'finance', 'accounts', 'delete', 'workspace', ARRAY['ws']),
    ('finance.journal_entries.view', 'finance', 'journal_entries', 'view', 'workspace', ARRAY['ws']),
    ('finance.journal_entries.create', 'finance', 'journal_entries', 'create', 'workspace', ARRAY['ws']),
    ('finance.journal_entries.approve', 'finance', 'journal_entries', 'approve', 'workspace', ARRAY['ws']),
    ('finance.journal_entries.export', 'finance', 'journal_entries', 'export', 'workspace', ARRAY['ws']),
    ('finance.taxes.view', 'finance', 'taxes', 'view', 'workspace', ARRAY['ws']),
    ('finance.taxes.create', 'finance', 'taxes', 'create', 'workspace', ARRAY['ws']),
    ('finance.taxes.update', 'finance', 'taxes', 'update', 'workspace', ARRAY['ws']),
    ('finance.taxes.delete', 'finance', 'taxes', 'delete', 'workspace', ARRAY['ws']),
    ('finance.fixed_assets.view', 'finance', 'fixed_assets', 'view', 'workspace', ARRAY['ws']),
    ('finance.fixed_assets.create', 'finance', 'fixed_assets', 'create', 'workspace', ARRAY['ws']),
    ('finance.fixed_assets.update', 'finance', 'fixed_assets', 'update', 'workspace', ARRAY['ws']),
    ('finance.fixed_assets.delete', 'finance', 'fixed_assets', 'delete', 'workspace', ARRAY['ws']),
    ('finance.recurring_expenses.view', 'finance', 'recurring_expenses', 'view', 'workspace', ARRAY['ws']),
    ('finance.recurring_expenses.create', 'finance', 'recurring_expenses', 'create', 'workspace', ARRAY['ws']),
    ('finance.recurring_expenses.update', 'finance', 'recurring_expenses', 'update', 'workspace', ARRAY['ws']),
    ('finance.recurring_expenses.delete', 'finance', 'recurring_expenses', 'delete', 'workspace', ARRAY['ws']),
    ('finance.reports.view', 'finance', 'reports', 'view', 'workspace', ARRAY['ws']),
    ('finance.reports.export', 'finance', 'reports', 'export', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- HR Module (20 keys) — mixed scopes per §3.3
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('hr.employees.view', 'hr', 'employees', 'view', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.employees.create', 'hr', 'employees', 'create', 'workspace', ARRAY['ws']),
    ('hr.employees.update', 'hr', 'employees', 'update', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.employees.delete', 'hr', 'employees', 'delete', 'workspace', ARRAY['ws']),
    ('hr.employees.export', 'hr', 'employees', 'export', 'workspace', ARRAY['dept','branch','ws']),
    ('hr.attendance.view', 'hr', 'attendance', 'view', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.attendance.create', 'hr', 'attendance', 'create', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.attendance.update', 'hr', 'attendance', 'update', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.attendance.export', 'hr', 'attendance', 'export', 'workspace', ARRAY['dept','branch','ws']),
    ('hr.leaves.view', 'hr', 'leaves', 'view', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.leaves.create', 'hr', 'leaves', 'create', 'workspace', ARRAY['own','dept','branch','ws']),
    ('hr.leaves.approve', 'hr', 'leaves', 'approve', 'workspace', ARRAY['dept','branch','ws']),
    ('hr.leaves.export', 'hr', 'leaves', 'export', 'workspace', ARRAY['dept','branch','ws']),
    ('hr.payroll.view', 'hr', 'payroll', 'view', 'workspace', ARRAY['own','ws']),
    ('hr.payroll.process', 'hr', 'payroll', 'process', 'workspace', ARRAY['ws']),
    ('hr.payroll.export', 'hr', 'payroll', 'export', 'workspace', ARRAY['ws']),
    ('hr.shifts.view', 'hr', 'shifts', 'view', 'workspace', ARRAY['ws']),
    ('hr.shifts.create', 'hr', 'shifts', 'create', 'workspace', ARRAY['ws']),
    ('hr.shifts.update', 'hr', 'shifts', 'update', 'workspace', ARRAY['ws']),
    ('hr.shifts.delete', 'hr', 'shifts', 'delete', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- CRM Module (16 keys) — applicable scopes: own, team, branch, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('crm.leads.view', 'crm', 'leads', 'view', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.leads.create', 'crm', 'leads', 'create', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.leads.update', 'crm', 'leads', 'update', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.leads.delete', 'crm', 'leads', 'delete', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.leads.export', 'crm', 'leads', 'export', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.opportunities.view', 'crm', 'opportunities', 'view', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.opportunities.create', 'crm', 'opportunities', 'create', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.opportunities.update', 'crm', 'opportunities', 'update', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.opportunities.delete', 'crm', 'opportunities', 'delete', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.activities.view', 'crm', 'activities', 'view', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.activities.create', 'crm', 'activities', 'create', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.activities.update', 'crm', 'activities', 'update', 'workspace', ARRAY['own','team','branch','ws']),
    ('crm.subscriptions.view', 'crm', 'subscriptions', 'view', 'workspace', ARRAY['ws']),
    ('crm.subscriptions.create', 'crm', 'subscriptions', 'create', 'workspace', ARRAY['ws']),
    ('crm.subscriptions.update', 'crm', 'subscriptions', 'update', 'workspace', ARRAY['ws']),
    ('crm.subscriptions.cancel', 'crm', 'subscriptions', 'cancel', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Manufacturing Module (12 keys) — applicable scopes: ws only
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('manufacturing.bom.view', 'manufacturing', 'bom', 'view', 'workspace', ARRAY['ws']),
    ('manufacturing.bom.create', 'manufacturing', 'bom', 'create', 'workspace', ARRAY['ws']),
    ('manufacturing.bom.update', 'manufacturing', 'bom', 'update', 'workspace', ARRAY['ws']),
    ('manufacturing.bom.delete', 'manufacturing', 'bom', 'delete', 'workspace', ARRAY['ws']),
    ('manufacturing.production.view', 'manufacturing', 'production', 'view', 'workspace', ARRAY['ws']),
    ('manufacturing.production.create', 'manufacturing', 'production', 'create', 'workspace', ARRAY['ws']),
    ('manufacturing.production.update', 'manufacturing', 'production', 'update', 'workspace', ARRAY['ws']),
    ('manufacturing.production.cancel', 'manufacturing', 'production', 'cancel', 'workspace', ARRAY['ws']),
    ('manufacturing.work_centers.view', 'manufacturing', 'work_centers', 'view', 'workspace', ARRAY['ws']),
    ('manufacturing.work_centers.create', 'manufacturing', 'work_centers', 'create', 'workspace', ARRAY['ws']),
    ('manufacturing.work_centers.update', 'manufacturing', 'work_centers', 'update', 'workspace', ARRAY['ws']),
    ('manufacturing.work_centers.delete', 'manufacturing', 'work_centers', 'delete', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Projects Module (8 keys) — applicable scopes: own, dept, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('projects.projects.view', 'projects', 'projects', 'view', 'workspace', ARRAY['own','dept','ws']),
    ('projects.projects.create', 'projects', 'projects', 'create', 'workspace', ARRAY['own','dept','ws']),
    ('projects.projects.update', 'projects', 'projects', 'update', 'workspace', ARRAY['own','dept','ws']),
    ('projects.projects.delete', 'projects', 'projects', 'delete', 'workspace', ARRAY['ws']),
    ('projects.tasks.view', 'projects', 'tasks', 'view', 'workspace', ARRAY['own','dept','ws']),
    ('projects.tasks.create', 'projects', 'tasks', 'create', 'workspace', ARRAY['own','dept','ws']),
    ('projects.tasks.update', 'projects', 'tasks', 'update', 'workspace', ARRAY['own','dept','ws']),
    ('projects.tasks.delete', 'projects', 'tasks', 'delete', 'workspace', ARRAY['own','dept','ws']);

-- -----------------------------------------------
-- Shared Module (19 keys) — applicable scopes: own, ws
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('shared.contacts.view', 'shared', 'contacts', 'view', 'workspace', ARRAY['own','ws']),
    ('shared.contacts.create', 'shared', 'contacts', 'create', 'workspace', ARRAY['own','ws']),
    ('shared.contacts.update', 'shared', 'contacts', 'update', 'workspace', ARRAY['own','ws']),
    ('shared.contacts.delete', 'shared', 'contacts', 'delete', 'workspace', ARRAY['ws']),
    ('shared.contacts.export', 'shared', 'contacts', 'export', 'workspace', ARRAY['own','ws']),
    ('shared.attachments.view', 'shared', 'attachments', 'view', 'workspace', ARRAY['own','ws']),
    ('shared.attachments.create', 'shared', 'attachments', 'create', 'workspace', ARRAY['own','ws']),
    ('shared.attachments.delete', 'shared', 'attachments', 'delete', 'workspace', ARRAY['own','ws']),
    ('shared.notifications.view', 'shared', 'notifications', 'view', 'workspace', ARRAY['own','ws']),
    ('shared.notifications.manage', 'shared', 'notifications', 'manage', 'workspace', ARRAY['own','ws']),
    ('shared.approvals.view', 'shared', 'approvals', 'view', 'workspace', ARRAY['own','ws']),
    ('shared.approvals.manage', 'shared', 'approvals', 'manage', 'workspace', ARRAY['own','ws']),
    ('shared.approvals.escalate', 'shared', 'approvals', 'escalate', 'workspace', ARRAY['own','ws']),
    ('shared.approvals.configure', 'shared', 'approvals', 'configure', 'workspace', ARRAY['ws']),
    ('shared.audit_logs.view', 'shared', 'audit_logs', 'view', 'workspace', ARRAY['ws']),
    ('shared.audit_logs.export', 'shared', 'audit_logs', 'export', 'workspace', ARRAY['ws']),
    ('shared.shipments.view', 'shared', 'shipments', 'view', 'workspace', ARRAY['own','ws']),
    ('shared.shipments.create', 'shared', 'shipments', 'create', 'workspace', ARRAY['own','ws']),
    ('shared.shipments.update', 'shared', 'shipments', 'update', 'workspace', ARRAY['own','ws']);

-- -----------------------------------------------
-- AI Module (3 keys) — applicable scopes: ws only
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('ai.chat.use', 'ai', 'chat', 'use', 'workspace', ARRAY['ws']),
    ('ai.changes.request', 'ai', 'changes', 'request', 'workspace', ARRAY['ws']),
    ('ai.changes.approve', 'ai', 'changes', 'approve', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Reports Module (6 keys) — applicable scopes: ws only
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('reports.operational.view', 'reports', 'operational', 'view', 'workspace', ARRAY['ws']),
    ('reports.operational.export', 'reports', 'operational', 'export', 'workspace', ARRAY['ws']),
    ('reports.financial.view', 'reports', 'financial', 'view', 'workspace', ARRAY['ws']),
    ('reports.financial.export', 'reports', 'financial', 'export', 'workspace', ARRAY['ws']),
    ('reports.executive.view', 'reports', 'executive', 'view', 'workspace', ARRAY['ws']),
    ('reports.executive.export', 'reports', 'executive', 'export', 'workspace', ARRAY['ws']);

-- -----------------------------------------------
-- Platform Module (33 keys) — scope_type = platform
-- Platform RBAC: role-to-permission mapping resolved at application layer
-- from RBAC spec §6.2 static matrix. No DB join table needed.
-- -----------------------------------------------
INSERT INTO permission_definitions (key, module, entity, action, scope_type, applicable_scopes) VALUES
    ('platform.workspaces.view', 'platform', 'workspaces', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.workspaces.inspect', 'platform', 'workspaces', 'inspect', 'platform', ARRAY[]::varchar[]),
    ('platform.workspaces.suspend', 'platform', 'workspaces', 'suspend', 'platform', ARRAY[]::varchar[]),
    ('platform.workspaces.reactivate', 'platform', 'workspaces', 'reactivate', 'platform', ARRAY[]::varchar[]),
    ('platform.workspaces.delete', 'platform', 'workspaces', 'delete', 'platform', ARRAY[]::varchar[]),
    ('platform.workspaces.impersonate', 'platform', 'workspaces', 'impersonate', 'platform', ARRAY[]::varchar[]),
    ('platform.billing.plans.view', 'platform', 'billing', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.billing.plans.manage', 'platform', 'billing', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.billing.subscriptions.view', 'platform', 'billing', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.billing.subscriptions.manage', 'platform', 'billing', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.billing.invoices.view', 'platform', 'billing', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.users.view', 'platform', 'users', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.users.manage', 'platform', 'users', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.users.roles.manage', 'platform', 'users', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.broadcasts.view', 'platform', 'broadcasts', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.broadcasts.create', 'platform', 'broadcasts', 'create', 'platform', ARRAY[]::varchar[]),
    ('platform.broadcasts.send', 'platform', 'broadcasts', 'send', 'platform', ARRAY[]::varchar[]),
    ('platform.surveys.view', 'platform', 'surveys', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.surveys.manage', 'platform', 'surveys', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.surveys.view_responses', 'platform', 'surveys', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.events.view', 'platform', 'events', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.events.export', 'platform', 'events', 'export', 'platform', ARRAY[]::varchar[]),
    ('platform.analytics.view', 'platform', 'analytics', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.ai_logs.view', 'platform', 'ai_logs', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.ai_logs.export', 'platform', 'ai_logs', 'export', 'platform', ARRAY[]::varchar[]),
    ('platform.feature_requests.view', 'platform', 'feature_requests', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.feature_requests.manage', 'platform', 'feature_requests', 'manage', 'platform', ARRAY[]::varchar[]),
    ('platform.feature_requests.roadmap', 'platform', 'feature_requests', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.system.feature_flags', 'platform', 'system', 'configure', 'platform', ARRAY[]::varchar[]),
    ('platform.system.health', 'platform', 'system', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.system.migrations', 'platform', 'system', 'process', 'platform', ARRAY[]::varchar[]),
    ('platform.system.jobs', 'platform', 'system', 'view', 'platform', ARRAY[]::varchar[]),
    ('platform.system.config', 'platform', 'system', 'configure', 'platform', ARRAY[]::varchar[]);


-- ==========================================
-- END OF MIGRATION 002
-- ==========================================
-- Validation checklist:
--   [ ] platform_users.role CHECK includes 'platform_engineer' (5 platform roles)
--   [ ] permission_definitions has exactly 242 rows (209 workspace + 33 platform)
--   [ ] permission_definitions.applicable_scopes populated per RBAC spec §3.3
--   [ ] roles has: role_key, description, hierarchy_level, is_system, is_default, is_deletable
--   [ ] workspace_memberships exists with FSM status CHECK
--   [ ] workspace_memberships has NO role_id column (roles via membership_roles)
--   [ ] workspace_memberships.manager_membership_id self-FK (not users FK)
--   [ ] membership_roles junction: UNIQUE(membership_id, role_id), advisory unique on primary
--   [ ] user_permission_overrides.permission_key FK → permission_definitions.key
--   [ ] user_permission_overrides.granted_by_membership_id FK → workspace_memberships
--   [ ] permission_delegations prevents self-delegation
--   [ ] permission_delegation_items.permission_key FK → permission_definitions.key
--   [ ] All workspace FK triggers use membership-based references (no users.workspace_id)
--   [ ] RLS enabled on: workspace_memberships, membership_roles, user_permission_overrides, permission_delegations
--   [ ] users.workspace_id and related columns untouched (transitional coexistence)
-- ==========================================
