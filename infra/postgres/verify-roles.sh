#!/bin/sh
set -eu

DB_HOST_VALUE="${DB_OWNER_HOST:-${DB_HOST:-postgres}}"
DB_PORT_VALUE="${DB_OWNER_PORT:-${DB_PORT:-5432}}"
DB_NAME_VALUE="${DB_OWNER_DATABASE:-${DB_DATABASE:-smartbiz}}"
OWNER_USERNAME="${DB_OWNER_USERNAME:-}"
OWNER_PASSWORD="${DB_OWNER_PASSWORD:-}"
CONTROL_USERNAME="${DB_CONTROL_USERNAME:-${DB_USERNAME:-}}"
CONTROL_PASSWORD="${DB_CONTROL_PASSWORD:-${DB_PASSWORD:-}}"
RUNTIME_USERNAME="${DB_RUNTIME_USERNAME:-${DB_TENANT_USERNAME:-}}"
RUNTIME_PASSWORD="${DB_RUNTIME_PASSWORD:-${DB_TENANT_PASSWORD:-}}"
BACKUP_USERNAME="${DB_BACKUP_USERNAME:-}"
BACKUP_PASSWORD="${DB_BACKUP_PASSWORD:-}"

for value in "$OWNER_USERNAME" "$OWNER_PASSWORD" "$CONTROL_USERNAME" "$CONTROL_PASSWORD" "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" "$BACKUP_USERNAME" "$BACKUP_PASSWORD"; do
    [ -n "$value" ] || { echo "Missing database role verification credentials." >&2; exit 1; }
done

psql_role() {
    role="$1"
    password="$2"
    shift 2
    PGPASSWORD="$password" psql \
        --host="$DB_HOST_VALUE" \
        --port="$DB_PORT_VALUE" \
        --username="$role" \
        --dbname="$DB_NAME_VALUE" \
        --set=ON_ERROR_STOP=1 \
        "$@"
}

assert_equals() {
    actual="$1"
    expected="$2"
    message="$3"
    [ "$actual" = "$expected" ] || {
        echo "Verification failed: $message (expected $expected, got $actual)" >&2
        exit 1
    }
}

bad_roles="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=control_username="$CONTROL_USERNAME" \
    --set=runtime_username="$RUNTIME_USERNAME" <<'SQL'
SELECT count(*) FROM pg_roles
WHERE rolname IN (:'control_username', :'runtime_username')
  AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolreplication OR rolbypassrls);
SQL
)"
assert_equals "$bad_roles" "0" "application roles must not be elevated"

backup_role_flags="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=backup_username="$BACKUP_USERNAME" <<'SQL'
SELECT concat_ws(',', rolsuper::int, rolcreaterole::int, rolcreatedb::int, rolreplication::int, rolbypassrls::int)
FROM pg_roles
WHERE rolname = :'backup_username';
SQL
)"
assert_equals "$backup_role_flags" "0,0,0,0,1" "backup role must be read-only and BYPASSRLS-only"

owned_objects="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=control_username="$CONTROL_USERNAME" \
    --set=runtime_username="$RUNTIME_USERNAME" \
    --set=backup_username="$BACKUP_USERNAME" <<'SQL'
SELECT count(*)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'p', 'S', 'v', 'm')
  AND r.rolname IN (:'control_username', :'runtime_username', :'backup_username');
SQL
)"
assert_equals "$owned_objects" "0" "non-owner roles must not own database objects"

runtime_without_context="$(psql_role "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" -At \
    -c "SELECT count(*) FROM public.contacts;")"
assert_equals "$runtime_without_context" "0" "runtime must see no tenant rows without workspace context"

# The control role keeps an RLS-scoped compatibility path for safe code
# rollback, but it must expose no operational rows without workspace context.
control_without_context="$(psql_role "$CONTROL_USERNAME" "$CONTROL_PASSWORD" -At \
    -c "SELECT count(*) FROM public.contacts;")"
assert_equals "$control_without_context" "0" "control role must see no operational rows without workspace context"
control_contact_privilege="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=control_username="$CONTROL_USERNAME" <<'SQL'
SELECT has_table_privilege(:'control_username', 'public.contacts', 'SELECT')::int;
SQL
)"
assert_equals "$control_contact_privilege" "1" "control rollback compatibility must retain RLS-gated table access"

control_contact_policy="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=control_username="$CONTROL_USERNAME" <<'SQL'
SELECT count(*)
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'contacts'
  AND :'control_username' = ANY(roles);
SQL
)"
assert_equals "$control_contact_policy" "1" "control rollback compatibility must be enforced by a contacts RLS policy"

# Backup can read all tenants but cannot write.
psql_role "$BACKUP_USERNAME" "$BACKUP_PASSWORD" -qAt \
    -c "SELECT count(*) FROM public.contacts;" >/dev/null
backup_write_privileges="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    --set=backup_username="$BACKUP_USERNAME" <<'SQL'
SELECT count(*)
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
SQL
)"
assert_equals "$backup_write_privileges" "0" "backup role must remain read-only"

workspace_ids="$(psql_role "$OWNER_USERNAME" "$OWNER_PASSWORD" -At \
    -c "SELECT id::text FROM public.workspaces ORDER BY id LIMIT 2;")"
workspace_a="$(printf '%s\n' "$workspace_ids" | sed -n '1p')"
workspace_b="$(printf '%s\n' "$workspace_ids" | sed -n '2p')"

if [ -n "$workspace_a" ]; then
    scoped_leaks="$(psql_role "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" -At \
        --set=workspace_a="$workspace_a" <<'SQL'
SELECT set_config('app.workspace_id', :'workspace_a', false);
SELECT
    (SELECT count(*) FROM public.contacts WHERE workspace_id::text <> :'workspace_a')
    +
    (SELECT count(*) FROM public.workspaces WHERE id::text <> :'workspace_a');
SQL
)"
    scoped_leaks="$(printf '%s\n' "$scoped_leaks" | tail -n1)"
    assert_equals "$scoped_leaks" "0" "runtime must not see rows from another workspace"

    control_scoped_leaks="$(psql_role "$CONTROL_USERNAME" "$CONTROL_PASSWORD" -At \
        --set=workspace_a="$workspace_a" <<'SQL'
SELECT set_config('app.workspace_id', :'workspace_a', false);
SELECT count(*) FROM public.contacts WHERE workspace_id::text <> :'workspace_a';
SQL
)"
    control_scoped_leaks="$(printf '%s\n' "$control_scoped_leaks" | tail -n1)"
    assert_equals "$control_scoped_leaks" "0" "control compatibility access must remain RLS-scoped"

    workspace_update_count="$(psql_role "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" -At \
        --set=workspace_a="$workspace_a" <<'SQL'
BEGIN;
SELECT set_config('app.workspace_id', :'workspace_a', false);
UPDATE public.workspaces SET updated_at = updated_at WHERE id = :'workspace_a'::uuid;
SELECT count(*) FROM public.workspaces WHERE id = :'workspace_a'::uuid;
ROLLBACK;
SQL
)"
    workspace_update_count="$(printf '%s\n' "$workspace_update_count" | grep -E '^[0-9]+$' | tail -n1)"
    assert_equals "$workspace_update_count" "1" "runtime must update only the active workspace"

    # No workspace context must also block writes to a valid workspace.
    if psql_role "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" -qAt \
        --set=workspace_a="$workspace_a" <<'SQL' >/dev/null 2>&1
BEGIN;
SELECT set_config('app.workspace_id', '', false);
INSERT INTO public.contacts (workspace_id, type, name)
VALUES (:'workspace_a'::uuid, 'customer', '__smartbiz_no_context_probe__');
ROLLBACK;
SQL
    then
        echo "Verification failed: runtime write succeeded without workspace context." >&2
        exit 1
    fi
fi

if [ -n "$workspace_a" ] && [ -n "$workspace_b" ]; then
    # WITH CHECK must reject a cross-workspace write. The transaction rolls back
    # even if a future policy regression unexpectedly allows it.
    if psql_role "$RUNTIME_USERNAME" "$RUNTIME_PASSWORD" -qAt \
        --set=workspace_a="$workspace_a" \
        --set=workspace_b="$workspace_b" <<'SQL' >/dev/null 2>&1
BEGIN;
SELECT set_config('app.workspace_id', :'workspace_a', false);
INSERT INTO public.contacts (workspace_id, type, name)
VALUES (:'workspace_b'::uuid, 'customer', '__smartbiz_cross_tenant_probe__');
ROLLBACK;
SQL
    then
        echo "Verification failed: runtime cross-workspace write succeeded." >&2
        exit 1
    fi
fi

echo "✅ PostgreSQL role separation and runtime RLS verification passed."
