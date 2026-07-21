#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
DATABASE_BACKUP="${2:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="$PROJECT_DIR/backend/.env.${ENVIRONMENT}"
STATE_DIR="${SMARTBIZ_DEPLOY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smartbiz}"
CURRENT_FILE="$STATE_DIR/current-release"

if [[ "$ENVIRONMENT" == "production" ]]; then
  ENV_FILE="$PROJECT_DIR/backend/.env.production"
fi

[[ -n "$DATABASE_BACKUP" ]] || {
  echo "Usage: infra/restore-drill.sh [environment] <database-backup.dump>" >&2
  exit 1
}
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }

if [[ -f "$CURRENT_FILE" ]]; then
  export SMARTBIZ_IMAGE_TAG="$(cat "$CURRENT_FILE")"
fi

DB_USERNAME="$(grep -E '^DB_USERNAME=' "$ENV_FILE" | tail -n1 | cut -d= -f2-)"
[[ "$DB_USERNAME" =~ ^[A-Za-z0-9_]+$ ]] || { echo "Invalid DB_USERNAME." >&2; exit 1; }

DRILL_DATABASE="smartbiz_restore_drill_$(date +%Y%m%d_%H%M%S)"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
cd "$PROJECT_DIR"

cleanup() {
  "${COMPOSE[@]}" exec -T postgres dropdb --if-exists -U "$DB_USERNAME" "$DRILL_DATABASE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" exec -T app php artisan db:restore "$DATABASE_BACKUP" --verify-only --no-interaction
"${COMPOSE[@]}" exec -T postgres createdb -U "$DB_USERNAME" "$DRILL_DATABASE"
"${COMPOSE[@]}" exec -T app php artisan db:restore "$DATABASE_BACKUP" \
  --database="$DRILL_DATABASE" \
  --confirm=RESTORE \
  --no-interaction

MIGRATION_COUNT="$("${COMPOSE[@]}" exec -T postgres psql -U "$DB_USERNAME" -d "$DRILL_DATABASE" -tAc 'SELECT COUNT(*) FROM migrations;')"
[[ "$MIGRATION_COUNT" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]] || {
  echo "Restore drill failed: migrations table could not be read." >&2
  exit 1
}

echo "✅ Restore drill passed in temporary database: $DRILL_DATABASE"
echo "Migrations found: $MIGRATION_COUNT"
