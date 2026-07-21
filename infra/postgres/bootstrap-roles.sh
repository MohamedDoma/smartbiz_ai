#!/bin/sh
set -eu

TARGET_DATABASE="${DB_OWNER_DATABASE:-${DB_DATABASE:-smartbiz}}"
OWNER_USERNAME="${DB_OWNER_USERNAME:-${POSTGRES_USER:-smartbiz}}"
OWNER_PASSWORD="${DB_OWNER_PASSWORD:-${POSTGRES_PASSWORD:-}}"
CONTROL_USERNAME="${DB_CONTROL_USERNAME:-${DB_USERNAME:-smartbiz_control}}"
CONTROL_PASSWORD="${DB_CONTROL_PASSWORD:-${DB_PASSWORD:-}}"
RUNTIME_USERNAME="${DB_RUNTIME_USERNAME:-${DB_TENANT_USERNAME:-smartbiz_runtime}}"
RUNTIME_PASSWORD="${DB_RUNTIME_PASSWORD:-${DB_TENANT_PASSWORD:-}}"
BACKUP_USERNAME="${DB_BACKUP_USERNAME:-smartbiz_backup}"
BACKUP_PASSWORD="${DB_BACKUP_PASSWORD:-}"
DB_HOST_VALUE="${DB_OWNER_HOST:-${DB_HOST:-postgres}}"
DB_PORT_VALUE="${DB_OWNER_PORT:-${DB_PORT:-5432}}"

valid_identifier() {
    case "$1" in
        ''|*[!A-Za-z0-9_]*) return 1 ;;
        *) return 0 ;;
    esac
}

for value in "$TARGET_DATABASE" "$OWNER_USERNAME" "$CONTROL_USERNAME" "$RUNTIME_USERNAME" "$BACKUP_USERNAME"; do
    valid_identifier "$value" || {
        echo "Invalid PostgreSQL identifier: $value" >&2
        exit 1
    }
done

[ -n "$OWNER_PASSWORD" ] || { echo "DB_OWNER_PASSWORD is required." >&2; exit 1; }
[ -n "$CONTROL_PASSWORD" ] || { echo "DB_PASSWORD is required for the control role." >&2; exit 1; }
[ -n "$RUNTIME_PASSWORD" ] || { echo "DB_TENANT_PASSWORD is required for the runtime role." >&2; exit 1; }
[ -n "$BACKUP_PASSWORD" ] || { echo "DB_BACKUP_PASSWORD is required." >&2; exit 1; }

[ "$OWNER_USERNAME" != "$CONTROL_USERNAME" ] || { echo "Owner and control roles must differ." >&2; exit 1; }
[ "$OWNER_USERNAME" != "$RUNTIME_USERNAME" ] || { echo "Owner and runtime roles must differ." >&2; exit 1; }
[ "$OWNER_USERNAME" != "$BACKUP_USERNAME" ] || { echo "Owner and backup roles must differ." >&2; exit 1; }
[ "$CONTROL_USERNAME" != "$RUNTIME_USERNAME" ] || { echo "Control and runtime roles must differ." >&2; exit 1; }
[ "$CONTROL_USERNAME" != "$BACKUP_USERNAME" ] || { echo "Control and backup roles must differ." >&2; exit 1; }
[ "$RUNTIME_USERNAME" != "$BACKUP_USERNAME" ] || { echo "Runtime and backup roles must differ." >&2; exit 1; }

export PGPASSWORD="$OWNER_PASSWORD"

psql \
    --host="$DB_HOST_VALUE" \
    --port="$DB_PORT_VALUE" \
    --username="$OWNER_USERNAME" \
    --dbname="$TARGET_DATABASE" \
    --single-transaction \
    --set=ON_ERROR_STOP=1 \
    --set=owner_username="$OWNER_USERNAME" \
    --set=control_username="$CONTROL_USERNAME" \
    --set=control_password="$CONTROL_PASSWORD" \
    --set=runtime_username="$RUNTIME_USERNAME" \
    --set=runtime_password="$RUNTIME_PASSWORD" \
    --set=backup_username="$BACKUP_USERNAME" \
    --set=backup_password="$BACKUP_PASSWORD" <<'SQL'
\set QUIET on

-- Create or rotate the three non-owner identities.
SELECT format(
    'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'control_username', :'control_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'control_username')
\gexec
SELECT format(
    'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'control_username', :'control_password'
)
\gexec

SELECT format(
    'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'runtime_username', :'runtime_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'runtime_username')
\gexec
SELECT format(
    'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'runtime_username', :'runtime_password'
)
\gexec

-- pg_dump needs a complete cross-tenant view. This identity is isolated to
-- backup containers and receives SELECT only.
SELECT format(
    'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION BYPASSRLS PASSWORD %L',
    :'backup_username', :'backup_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'backup_username')
\gexec
SELECT format(
    'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION BYPASSRLS PASSWORD %L',
    :'backup_username', :'backup_password'
)
\gexec

-- Remove any historical role memberships before applying grants.
SELECT format('REVOKE %I FROM %I', parent_role.rolname, member_role.rolname)
FROM pg_auth_members membership
JOIN pg_roles parent_role ON parent_role.oid = membership.roleid
JOIN pg_roles member_role ON member_role.oid = membership.member
WHERE member_role.rolname IN (:'control_username', :'runtime_username', :'backup_username')
\gexec

SELECT format('ALTER ROLE %I SET row_security = on', :'control_username') \gexec
SELECT format('ALTER ROLE %I SET row_security = on', :'runtime_username') \gexec
SELECT format('ALTER ROLE %I SET statement_timeout = %L', :'control_username', '30s') \gexec
SELECT format('ALTER ROLE %I SET statement_timeout = %L', :'runtime_username', '30s') \gexec
SELECT format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L', :'control_username', '30s') \gexec
SELECT format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L', :'runtime_username', '30s') \gexec

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'control_username') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'runtime_username') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', current_database(), :'backup_username') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'control_username') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'runtime_username') \gexec
SELECT format('GRANT USAGE ON SCHEMA public TO %I', :'backup_username') \gexec

-- Direct tenant tables contain a UUID workspace_id column.
CREATE TEMP TABLE smartbiz_direct_tenant_tables (table_name text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO smartbiz_direct_tenant_tables (table_name)
SELECT DISTINCT c.relname
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid
JOIN pg_type t ON t.oid = a.atttypid
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND a.attname = 'workspace_id'
  AND NOT a.attisdropped
  AND t.typname = 'uuid';

-- Child tables inherit workspace ownership through a parent foreign key.
CREATE TEMP TABLE smartbiz_derived_tenant_tables (
    table_name text PRIMARY KEY,
    predicate text NOT NULL
) ON COMMIT DROP;
INSERT INTO smartbiz_derived_tenant_tables (table_name, predicate) VALUES
('invoice_items', 'EXISTS (SELECT 1 FROM public.invoices p WHERE p.id = invoice_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('order_items', 'EXISTS (SELECT 1 FROM public.orders p WHERE p.id = order_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('journal_lines', 'EXISTS (SELECT 1 FROM public.journal_entries p WHERE p.id = entry_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('price_list_items', 'EXISTS (SELECT 1 FROM public.price_lists p WHERE p.id = price_list_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('product_variants', 'EXISTS (SELECT 1 FROM public.products p WHERE p.id = product_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('segment_contacts', 'EXISTS (SELECT 1 FROM public.segments p WHERE p.id = segment_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('stock_transfer_items', 'EXISTS (SELECT 1 FROM public.stock_transfers p WHERE p.id = transfer_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('workspace_invitation_roles', 'EXISTS (SELECT 1 FROM public.workspace_invitations p WHERE p.id = workspace_invitation_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('permission_delegation_items', 'EXISTS (SELECT 1 FROM public.permission_delegations p WHERE p.id = delegation_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('campaign_metrics', 'EXISTS (SELECT 1 FROM public.campaigns p WHERE p.id = campaign_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('delivery_proofs', 'EXISTS (SELECT 1 FROM public.delivery_assignments p WHERE p.id = assignment_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('delivery_tracking', 'EXISTS (SELECT 1 FROM public.delivery_assignments p WHERE p.id = assignment_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('delivery_sla_breaches', 'EXISTS (SELECT 1 FROM public.delivery_assignments p WHERE p.id = assignment_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('loyalty_transactions', 'EXISTS (SELECT 1 FROM public.loyalty_accounts p WHERE p.id = account_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('nurturing_enrollments', 'EXISTS (SELECT 1 FROM public.nurturing_sequences p WHERE p.id = sequence_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)'),
('webhook_deliveries', 'EXISTS (SELECT 1 FROM public.webhook_subscriptions p WHERE p.id = subscription_id AND p.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)')
ON CONFLICT (table_name) DO NOTHING;
DELETE FROM smartbiz_derived_tenant_tables d
WHERE to_regclass('public.' || d.table_name) IS NULL;

CREATE TEMP TABLE smartbiz_special_rls_tables (table_name text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO smartbiz_special_rls_tables VALUES ('workspaces'), ('users') ON CONFLICT DO NOTHING;
DELETE FROM smartbiz_special_rls_tables s
WHERE to_regclass('public.' || s.table_name) IS NULL;

-- Explicit global classification. New unclassified tables make this script
-- fail closed until their security model is reviewed.
CREATE TEMP TABLE smartbiz_global_tables (
    table_name text PRIMARY KEY,
    runtime_select boolean NOT NULL,
    control_write boolean NOT NULL
) ON COMMIT DROP;
INSERT INTO smartbiz_global_tables (table_name, runtime_select, control_write) VALUES
('_deprecation_registry', false, false),
('migrations', false, false),
('business_template_custom_fields', true, true),
('business_template_modules', true, true),
('business_template_roles', true, true),
('business_template_workflows', true, true),
('business_templates', true, true),
('country_packs', true, true),
('impersonation_sessions', false, true),
('integration_providers', true, true),
('invoice_format_rules', true, true),
('payroll_statutory_rules', true, true),
('permission_definitions', true, true),
('personal_access_tokens', false, true),
('plan_features', true, true),
('platform_activation_campaigns', false, true),
('platform_activation_codes', false, true),
('platform_broadcasts', false, true),
('platform_feature_requests', false, true),
('platform_plan_prices', true, true),
('platform_plans', true, true),
('platform_settings', true, true),
('platform_surveys', false, true),
('platform_users', false, true),
('subscription_plans', true, true),
('translations', true, true),
('webhook_events', true, true),
('failed_jobs', false, true)
ON CONFLICT (table_name) DO NOTHING;
DELETE FROM smartbiz_global_tables g
WHERE to_regclass('public.' || g.table_name) IS NULL;

-- Fail closed if a regular public table has no reviewed classification.
SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p')
  AND c.relname NOT IN (SELECT table_name FROM smartbiz_direct_tenant_tables)
  AND c.relname NOT IN (SELECT table_name FROM smartbiz_derived_tenant_tables)
  AND c.relname NOT IN (SELECT table_name FROM smartbiz_special_rls_tables)
  AND c.relname NOT IN (SELECT table_name FROM smartbiz_global_tables);

SELECT format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name)
FROM smartbiz_direct_tenant_tables
UNION ALL
SELECT format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name)
FROM smartbiz_derived_tenant_tables
UNION ALL
SELECT format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name)
FROM smartbiz_special_rls_tables
\gexec

-- Replace legacy/PUBLIC tenant policies with deterministic role-targeted ones.
SELECT format('DROP POLICY IF EXISTS %I ON %I.%I', p.polname, n.nspname, c.relname)
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN (
      SELECT table_name FROM smartbiz_direct_tenant_tables
      UNION SELECT table_name FROM smartbiz_derived_tenant_tables
      UNION SELECT table_name FROM smartbiz_special_rls_tables
  )
\gexec

SELECT format(
    'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %I USING (workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid) WITH CHECK (workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)',
    left(table_name, 38) || '_rt_' || substr(md5(table_name), 1, 8),
    table_name,
    :'runtime_username'
)
FROM smartbiz_direct_tenant_tables
\gexec

SELECT format(
    'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %I USING (%s) WITH CHECK (%s)',
    left(table_name, 38) || '_rt_' || substr(md5(table_name), 1, 8),
    table_name,
    :'runtime_username',
    predicate,
    predicate
)
FROM smartbiz_derived_tenant_tables
\gexec

-- Compatibility policy for controlled rollback to the immediately previous
-- application release. It remains RLS-scoped and exposes no rows without a
-- validated workspace context; the current application switches to the
-- dedicated runtime role for tenant operations.
SELECT format(
    'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %I USING (workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid) WITH CHECK (workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)',
    left(table_name, 38) || '_ctlrt_' || substr(md5(table_name), 1, 8),
    table_name,
    :'control_username'
)
FROM smartbiz_direct_tenant_tables
\gexec
SELECT format(
    'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %I USING (%s) WITH CHECK (%s)',
    left(table_name, 38) || '_ctlrt_' || substr(md5(table_name), 1, 8),
    table_name,
    :'control_username',
    predicate,
    predicate
)
FROM smartbiz_derived_tenant_tables
\gexec

SELECT format(
    'CREATE POLICY workspaces_runtime_select ON public.workspaces AS PERMISSIVE FOR SELECT TO %I USING (id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)',
    :'runtime_username'
)
WHERE to_regclass('public.workspaces') IS NOT NULL
\gexec
SELECT format(
    'CREATE POLICY workspaces_runtime_update ON public.workspaces AS PERMISSIVE FOR UPDATE TO %I USING (id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid) WITH CHECK (id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid)',
    :'runtime_username'
)
WHERE to_regclass('public.workspaces') IS NOT NULL
\gexec
SELECT format(
    'CREATE POLICY users_runtime_membership ON public.users AS PERMISSIVE FOR SELECT TO %I USING (EXISTS (SELECT 1 FROM public.workspace_memberships wm WHERE wm.user_id = users.id AND wm.workspace_id = NULLIF(current_setting(''app.workspace_id'', true), '''')::uuid))',
    :'runtime_username'
)
WHERE to_regclass('public.users') IS NOT NULL
\gexec

-- Control-plane access is explicit: identity/session/onboarding/platform/billing.
CREATE TEMP TABLE smartbiz_control_tenant_tables (table_name text PRIMARY KEY) ON COMMIT DROP;
INSERT INTO smartbiz_control_tenant_tables (table_name)
SELECT table_name
FROM smartbiz_direct_tenant_tables
WHERE table_name LIKE 'workspace\_%' ESCAPE '\'
   OR table_name LIKE 'platform\_%' ESCAPE '\'
   OR table_name LIKE 'provisioning\_%' ESCAPE '\'
   OR table_name LIKE 'billing\_%' ESCAPE '\'
   OR table_name IN (
       'roles', 'membership_roles', 'departments', 'teams', 'branches',
       'user_permission_overrides', 'permission_delegations',
       'manual_payments', 'payment_transactions',
       'ai_credit_balances', 'ai_credit_transactions',
       'ai_usage_logs', 'ai_workspace_settings'
   );
INSERT INTO smartbiz_control_tenant_tables (table_name)
SELECT table_name FROM smartbiz_derived_tenant_tables
WHERE table_name IN ('workspace_invitation_roles', 'permission_delegation_items')
ON CONFLICT DO NOTHING;

SELECT format(
    'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR ALL TO %I USING (true) WITH CHECK (true)',
    left(table_name, 38) || '_ctl_' || substr(md5(table_name), 1, 8),
    table_name,
    :'control_username'
)
FROM smartbiz_control_tenant_tables
\gexec
SELECT format('CREATE POLICY workspaces_control_access ON public.workspaces AS PERMISSIVE FOR ALL TO %I USING (true) WITH CHECK (true)', :'control_username')
WHERE to_regclass('public.workspaces') IS NOT NULL
\gexec
SELECT format('CREATE POLICY users_control_access ON public.users AS PERMISSIVE FOR ALL TO %I USING (true) WITH CHECK (true)', :'control_username')
WHERE to_regclass('public.users') IS NOT NULL
\gexec

-- Revoke first so repeated runs remove obsolete grants.
SELECT format('REVOKE ALL PRIVILEGES ON TABLE %I.%I FROM %I, %I, %I', n.nspname, c.relname, :'control_username', :'runtime_username', :'backup_username')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
\gexec
SELECT format('REVOKE ALL PRIVILEGES ON SEQUENCE %I.%I FROM %I, %I, %I', n.nspname, c.relname, :'control_username', :'runtime_username', :'backup_username')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'S'
\gexec

-- Tenant runtime: DML only where RLS is mandatory, plus reviewed references.
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'runtime_username')
FROM smartbiz_direct_tenant_tables
UNION ALL
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'runtime_username')
FROM smartbiz_derived_tenant_tables
\gexec
SELECT format('GRANT SELECT ON TABLE public.%I TO %I', table_name, :'runtime_username')
FROM smartbiz_special_rls_tables
UNION ALL
SELECT format('GRANT SELECT ON TABLE public.%I TO %I', table_name, :'runtime_username')
FROM smartbiz_global_tables
WHERE runtime_select
\gexec
SELECT format('GRANT UPDATE ON TABLE public.workspaces TO %I', :'runtime_username')
WHERE to_regclass('public.workspaces') IS NOT NULL
\gexec

-- Control plane: tenant-table privileges remain RLS-scoped as a safe
-- rollback compatibility path. Cross-tenant access is granted only to the
-- explicit control-plane allow-list through the permissive policies above.
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'control_username')
FROM smartbiz_direct_tenant_tables
UNION ALL
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'control_username')
FROM smartbiz_derived_tenant_tables
UNION ALL
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'control_username')
FROM smartbiz_special_rls_tables
UNION ALL
SELECT format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO %I', table_name, :'control_username')
FROM smartbiz_global_tables
WHERE control_write
\gexec

-- Dedicated backup identity: complete read-only snapshot.
SELECT format('GRANT SELECT ON TABLE %I.%I TO %I', n.nspname, c.relname, :'backup_username')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p', 'v', 'm')
\gexec

-- Sequence access does not grant table writes; table privileges still gate DML.
SELECT format('GRANT USAGE, SELECT ON SEQUENCE %I.%I TO %I, %I', n.nspname, c.relname, :'control_username', :'runtime_username')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'S'
\gexec
SELECT format('GRANT SELECT ON SEQUENCE %I.%I TO %I', n.nspname, c.relname, :'backup_username')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'S'
\gexec

-- New owner-created objects stay inaccessible to application roles until the
-- post-migration bootstrap classifies them. Backup receives read-only defaults.
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM %I', :'owner_username', :'runtime_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM %I', :'owner_username', :'control_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON TABLES FROM %I', :'owner_username', :'backup_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT SELECT ON TABLES TO %I', :'owner_username', :'backup_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', :'owner_username', :'runtime_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', :'owner_username', :'control_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public REVOKE ALL ON SEQUENCES FROM %I', :'owner_username', :'backup_username') \gexec
SELECT format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public GRANT SELECT ON SEQUENCES TO %I', :'owner_username', :'backup_username') \gexec

-- Hard assertions.
SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM pg_roles
WHERE rolname IN (:'control_username', :'runtime_username')
  AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls);

SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'S', 'v', 'm')
  AND r.rolname IN (:'control_username', :'runtime_username', :'backup_username');

SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM (
    SELECT table_name FROM smartbiz_direct_tenant_tables
    UNION SELECT table_name FROM smartbiz_derived_tenant_tables
    UNION SELECT table_name FROM smartbiz_special_rls_tables
) protected
JOIN pg_class c ON c.relname = protected.table_name
JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
WHERE NOT c.relrowsecurity;

SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM smartbiz_global_tables g
WHERE NOT g.runtime_select
  AND has_table_privilege(:'runtime_username', format('public.%I', g.table_name), 'SELECT');

SELECT 1 / CASE WHEN count(*) = 0 THEN 1 ELSE 0 END
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'v', 'm')
  AND (
      has_table_privilege(:'backup_username', c.oid, 'INSERT')
      OR has_table_privilege(:'backup_username', c.oid, 'UPDATE')
      OR has_table_privilege(:'backup_username', c.oid, 'DELETE')
      OR has_table_privilege(:'backup_username', c.oid, 'TRUNCATE')
      OR has_table_privilege(:'backup_username', c.oid, 'REFERENCES')
      OR has_table_privilege(:'backup_username', c.oid, 'TRIGGER')
  );

\set QUIET off
SQL

unset PGPASSWORD

echo "PostgreSQL owner/control/runtime/backup separation is ready for: $TARGET_DATABASE"
