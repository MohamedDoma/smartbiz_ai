#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
DATABASE_BACKUP="${2:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
APP_ENV_FILE="$PROJECT_DIR/backend/.env.${ENVIRONMENT}"
OWNER_ENV_FILE="$PROJECT_DIR/infra/.env.${ENVIRONMENT}.owner"
BACKUP_ENV_FILE="$PROJECT_DIR/infra/.env.${ENVIRONMENT}.backup"
STATE_DIR="${SMARTBIZ_DEPLOY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smartbiz}"
CURRENT_FILE="$STATE_DIR/current-release"

if [[ "$ENVIRONMENT" == "production" ]]; then
  APP_ENV_FILE="$PROJECT_DIR/backend/.env.production"
  OWNER_ENV_FILE="$PROJECT_DIR/infra/.env.production.owner"
  BACKUP_ENV_FILE="$PROJECT_DIR/infra/.env.production.backup"
fi

fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

[[ -n "$DATABASE_BACKUP" ]] || fail "Usage: infra/restore-drill.sh [environment] <database-backup.dump>"
[[ -f "$APP_ENV_FILE" ]] || fail "Missing $APP_ENV_FILE"
[[ -f "$OWNER_ENV_FILE" ]] || fail "Missing $OWNER_ENV_FILE"
[[ -f "$BACKUP_ENV_FILE" ]] || fail "Missing $BACKUP_ENV_FILE"

if [[ -f "$CURRENT_FILE" ]]; then
  export SMARTBIZ_IMAGE_TAG="$(cat "$CURRENT_FILE")"
fi

DRILL_DATABASE="smartbiz_restore_drill_$(date +%Y%m%d_%H%M%S)"
[[ "$DRILL_DATABASE" =~ ^[A-Za-z0-9_]+$ ]] || fail "Invalid restore-drill database name."

COMPOSE=(
  docker compose
  --env-file "$APP_ENV_FILE"
  --env-file "$OWNER_ENV_FILE"
  --env-file "$BACKUP_ENV_FILE"
  -f "$COMPOSE_FILE"
)
cd "$PROJECT_DIR"

cleanup() {
  "${COMPOSE[@]}" --profile operations run --rm \
    -e DRILL_DATABASE="$DRILL_DATABASE" \
    ops sh -lc 'PGPASSWORD="$DB_OWNER_PASSWORD" dropdb --if-exists --host="${DB_OWNER_HOST:-postgres}" --port="${DB_OWNER_PORT:-5432}" --username="$DB_OWNER_USERNAME" "$DRILL_DATABASE"' \
    >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan db:restore "$DATABASE_BACKUP" --verify-only --no-interaction

"${COMPOSE[@]}" --profile operations run --rm \
  -e DRILL_DATABASE="$DRILL_DATABASE" \
  ops sh -lc 'PGPASSWORD="$DB_OWNER_PASSWORD" createdb --host="${DB_OWNER_HOST:-postgres}" --port="${DB_OWNER_PORT:-5432}" --username="$DB_OWNER_USERNAME" "$DRILL_DATABASE"'

"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan db:restore "$DATABASE_BACKUP" \
  --database="$DRILL_DATABASE" \
  --confirm=RESTORE \
  --no-interaction

"${COMPOSE[@]}" --profile operations run --rm \
  -e DB_OWNER_DATABASE="$DRILL_DATABASE" \
  ops smartbiz-bootstrap-db-roles
"${COMPOSE[@]}" --profile operations run --rm \
  -e DB_OWNER_DATABASE="$DRILL_DATABASE" \
  ops smartbiz-verify-db-roles

MIGRATION_OUTPUT="$("${COMPOSE[@]}" --profile operations run --rm \
  -e DRILL_DATABASE="$DRILL_DATABASE" \
  ops sh -lc 'PGPASSWORD="$DB_OWNER_PASSWORD" psql --host="${DB_OWNER_HOST:-postgres}" --port="${DB_OWNER_PORT:-5432}" --username="$DB_OWNER_USERNAME" --dbname="$DRILL_DATABASE" -tAc "SELECT COUNT(*) FROM migrations;"')"
MIGRATION_COUNT="$(printf '%s\n' "$MIGRATION_OUTPUT" | grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' | tail -n1 | tr -d '[:space:]')"
[[ "$MIGRATION_COUNT" =~ ^[0-9]+$ ]] || fail "Restore drill failed: migrations table could not be read."

echo "✅ Restore drill passed with role separation in temporary database: $DRILL_DATABASE"
echo "Migrations found: $MIGRATION_COUNT"
