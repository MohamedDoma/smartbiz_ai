#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
DATABASE_BACKUP="${2:-}"
FILES_BACKUP="${3:-}"

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

[[ -n "$DATABASE_BACKUP" ]] || fail "Usage: infra/restore.sh [environment] <database-backup.dump> [files-backup.tar.gz]"
[[ -f "$APP_ENV_FILE" ]] || fail "Missing $APP_ENV_FILE"
[[ -f "$OWNER_ENV_FILE" ]] || fail "Missing $OWNER_ENV_FILE"
[[ -f "$BACKUP_ENV_FILE" ]] || fail "Missing $BACKUP_ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "Missing $COMPOSE_FILE"

if [[ -f "$CURRENT_FILE" ]]; then
  export SMARTBIZ_IMAGE_TAG="$(cat "$CURRENT_FILE")"
fi

COMPOSE=(
  docker compose
  --env-file "$APP_ENV_FILE"
  --env-file "$OWNER_ENV_FILE"
  --env-file "$BACKUP_ENV_FILE"
  -f "$COMPOSE_FILE"
)
cd "$PROJECT_DIR"

"${COMPOSE[@]}" config --quiet

# Verify archives before entering maintenance mode.
"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan db:restore "$DATABASE_BACKUP" --verify-only --no-interaction

if [[ -n "$FILES_BACKUP" ]]; then
  "${COMPOSE[@]}" --profile operations run --rm ops \
    php artisan files:restore "$FILES_BACKUP" --verify-only --no-interaction
else
  echo "→ No files archive supplied; creating a verified snapshot of current application files"
  "${COMPOSE[@]}" --profile operations run --rm ops \
    php artisan files:backup --no-interaction
fi

confirmation="${SMARTBIZ_RESTORE_CONFIRM:-}"
if [[ "$confirmation" != "RESTORE" ]]; then
  printf 'Type RESTORE to continue with the destructive restore: '
  read -r confirmation
fi
[[ "$confirmation" == "RESTORE" ]] || fail "Restore cancelled."

"${COMPOSE[@]}" exec -T app php artisan down --retry=60 --no-interaction
"${COMPOSE[@]}" stop app worker scheduler backup-scheduler

restore_failed=true
trap 'if [[ "$restore_failed" == "true" ]]; then echo "❌ Restore failed. Application remains in maintenance mode and application processes remain stopped." >&2; fi' EXIT

"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan db:restore "$DATABASE_BACKUP" --confirm=RESTORE --no-interaction

if [[ -n "$FILES_BACKUP" ]]; then
  "${COMPOSE[@]}" --profile operations run --rm ops \
    php artisan files:restore "$FILES_BACKUP" --confirm=RESTORE --no-interaction
fi

"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan migrate --database=pgsql_owner --force --no-interaction
"${COMPOSE[@]}" --profile operations run --rm ops smartbiz-bootstrap-db-roles
"${COMPOSE[@]}" --profile operations run --rm ops smartbiz-verify-db-roles

# Recreate PHP processes so no connection survives the destructive restore.
"${COMPOSE[@]}" up -d --force-recreate app
"${COMPOSE[@]}" exec -T app php artisan optimize:clear --no-interaction
"${COMPOSE[@]}" exec -T app php artisan up --no-interaction
"${COMPOSE[@]}" up -d --remove-orphans worker scheduler backup-scheduler nginx
"${COMPOSE[@]}" exec -T app php artisan queue:restart

for attempt in $(seq 1 40); do
  if "${COMPOSE[@]}" exec -T nginx wget -qO- http://127.0.0.1:8080/up >/dev/null 2>&1 \
    && "${COMPOSE[@]}" exec -T app php artisan ops:check --json --fail-on-warning >/dev/null 2>&1; then
    restore_failed=false
    trap - EXIT
    echo "✅ Restore completed, database roles reverified, and operational checks passed."
    exit 0
  fi
  sleep 3
done

"${COMPOSE[@]}" exec -T app php artisan ops:check --json >&2 || true
"${COMPOSE[@]}" logs --tail=150 app nginx worker scheduler backup-scheduler >&2 || true
exit 1
