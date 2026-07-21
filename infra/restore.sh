#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
DATABASE_BACKUP="${2:-}"
FILES_BACKUP="${3:-}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="$PROJECT_DIR/backend/.env.${ENVIRONMENT}"
STATE_DIR="${SMARTBIZ_DEPLOY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smartbiz}"
CURRENT_FILE="$STATE_DIR/current-release"

if [[ "$ENVIRONMENT" == "production" ]]; then
  ENV_FILE="$PROJECT_DIR/backend/.env.production"
fi

[[ -n "$DATABASE_BACKUP" ]] || {
  echo "Usage: infra/restore.sh [environment] <database-backup.dump> [files-backup.tar.gz]" >&2
  exit 1
}
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }

if [[ -f "$CURRENT_FILE" ]]; then
  export SMARTBIZ_IMAGE_TAG="$(cat "$CURRENT_FILE")"
fi

COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")
cd "$PROJECT_DIR"

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" exec -T app php artisan db:restore "$DATABASE_BACKUP" --verify-only --no-interaction

if [[ -n "$FILES_BACKUP" ]]; then
  "${COMPOSE[@]}" exec -T app php artisan files:restore "$FILES_BACKUP" --verify-only --no-interaction
fi

confirmation="${SMARTBIZ_RESTORE_CONFIRM:-}"
if [[ "$confirmation" != "RESTORE" ]]; then
  printf 'Type RESTORE to continue with the destructive restore: '
  read -r confirmation
fi
[[ "$confirmation" == "RESTORE" ]] || { echo "Restore cancelled." >&2; exit 1; }

"${COMPOSE[@]}" exec -T app php artisan down --retry=60 --no-interaction
"${COMPOSE[@]}" stop worker scheduler

restore_failed=true
trap 'if [[ "$restore_failed" == "true" ]]; then echo "❌ Restore failed. Application remains in maintenance mode and workers remain stopped." >&2; fi' EXIT

"${COMPOSE[@]}" exec -T app php artisan db:restore "$DATABASE_BACKUP" --confirm=RESTORE --no-interaction

if [[ -n "$FILES_BACKUP" ]]; then
  "${COMPOSE[@]}" exec -T app php artisan files:restore "$FILES_BACKUP" --confirm=RESTORE --no-interaction
else
  echo "→ No files archive supplied; creating a verified backup of the current application files"
  "${COMPOSE[@]}" exec -T app php artisan files:backup --no-interaction
fi

"${COMPOSE[@]}" exec -T app php artisan migrate --force --no-interaction
"${COMPOSE[@]}" exec -T app php artisan optimize:clear --no-interaction
"${COMPOSE[@]}" exec -T app php artisan up --no-interaction
"${COMPOSE[@]}" up -d worker scheduler
"${COMPOSE[@]}" exec -T app php artisan queue:restart

for attempt in $(seq 1 40); do
  if "${COMPOSE[@]}" exec -T nginx wget -qO- http://127.0.0.1:8080/up >/dev/null 2>&1 \
    && "${COMPOSE[@]}" exec -T app php artisan ops:check --json --fail-on-warning >/dev/null 2>&1; then
    restore_failed=false
    trap - EXIT
    echo "✅ Restore completed and operational checks passed."
    exit 0
  fi
  sleep 3
done

"${COMPOSE[@]}" exec -T app php artisan ops:check --json >&2 || true
exit 1
