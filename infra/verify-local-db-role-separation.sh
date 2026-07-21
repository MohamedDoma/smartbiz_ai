#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POSTGRES_CONTAINER="${SMARTBIZ_POSTGRES_CONTAINER:-smartbiz_postgres}"
TEST_DATABASE="${SMARTBIZ_TEST_DATABASE:-smartbiz_test}"
OWNER_USERNAME="${SMARTBIZ_TEST_DB_OWNER_USERNAME:-smartbiz}"
OWNER_PASSWORD="${SMARTBIZ_TEST_DB_OWNER_PASSWORD:-smartbiz_dev}"
CONTROL_USERNAME="${SMARTBIZ_TEST_CONTROL_USERNAME:-smartbiz_test_control}"
RUNTIME_USERNAME="${SMARTBIZ_TEST_RUNTIME_USERNAME:-smartbiz_test_runtime}"
BACKUP_USERNAME="${SMARTBIZ_TEST_BACKUP_USERNAME:-smartbiz_test_backup}"

command -v docker >/dev/null 2>&1 || { echo "Docker is required." >&2; exit 1; }
docker inspect "$POSTGRES_CONTAINER" >/dev/null 2>&1 || {
  echo "PostgreSQL container is not running: $POSTGRES_CONTAINER" >&2
  exit 1
}

random_secret() {
  python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(36))
PY
}

CONTROL_PASSWORD="$(random_secret)"
RUNTIME_PASSWORD="$(random_secret)"
BACKUP_PASSWORD="$(random_secret)"

common_env=(
  -e DB_OWNER_HOST=127.0.0.1
  -e DB_OWNER_PORT=5432
  -e DB_OWNER_DATABASE="$TEST_DATABASE"
  -e DB_OWNER_USERNAME="$OWNER_USERNAME"
  -e DB_OWNER_PASSWORD="$OWNER_PASSWORD"
  -e DB_USERNAME="$CONTROL_USERNAME"
  -e DB_PASSWORD="$CONTROL_PASSWORD"
  -e DB_TENANT_USERNAME="$RUNTIME_USERNAME"
  -e DB_TENANT_PASSWORD="$RUNTIME_PASSWORD"
  -e DB_BACKUP_USERNAME="$BACKUP_USERNAME"
  -e DB_BACKUP_PASSWORD="$BACKUP_PASSWORD"
)

# The scripts execute inside the PostgreSQL container so no host psql package is required.
docker exec -i "${common_env[@]}" "$POSTGRES_CONTAINER" sh -s \
  < "$PROJECT_DIR/infra/postgres/bootstrap-roles.sh"

docker exec -i "${common_env[@]}" "$POSTGRES_CONTAINER" sh -s \
  < "$PROJECT_DIR/infra/postgres/verify-roles.sh"

unset CONTROL_PASSWORD RUNTIME_PASSWORD BACKUP_PASSWORD

echo "✅ Local smartbiz_test role separation and PostgreSQL RLS proof passed."
