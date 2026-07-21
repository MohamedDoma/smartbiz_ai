#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
APP_ENV_FILE="$PROJECT_DIR/backend/.env.${ENVIRONMENT}"
OWNER_ENV_FILE="$PROJECT_DIR/infra/.env.${ENVIRONMENT}.owner"
BACKUP_ENV_FILE="$PROJECT_DIR/infra/.env.${ENVIRONMENT}.backup"
STATE_DIR="${SMARTBIZ_DEPLOY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smartbiz}"
CURRENT_FILE="$STATE_DIR/current-release"
PREVIOUS_FILE="$STATE_DIR/previous-release"
mkdir -p "$STATE_DIR"

if [[ "$ENVIRONMENT" == "production" ]]; then
  APP_ENV_FILE="$PROJECT_DIR/backend/.env.production"
  OWNER_ENV_FILE="$PROJECT_DIR/infra/.env.production.owner"
  BACKUP_ENV_FILE="$PROJECT_DIR/infra/.env.production.backup"
fi

log() { printf '→ %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }
env_value() {
  local file="$1" key="$2"
  grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- || true
}

command -v docker >/dev/null 2>&1 || fail "Docker is required."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required."
[[ -f "$APP_ENV_FILE" ]] || fail "Missing application environment file: $APP_ENV_FILE"
[[ -f "$OWNER_ENV_FILE" ]] || fail "Missing owner environment file: $OWNER_ENV_FILE"
[[ -f "$BACKUP_ENV_FILE" ]] || fail "Missing backup environment file: $BACKUP_ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "Missing compose file: $COMPOSE_FILE"

for key in APP_KEY APP_URL FRONTEND_URL DB_DATABASE DB_USERNAME DB_PASSWORD DB_TENANT_DATABASE DB_TENANT_USERNAME DB_TENANT_PASSWORD REDIS_PASSWORD; do
  [[ -n "$(env_value "$APP_ENV_FILE" "$key")" ]] || fail "$key must be set in $APP_ENV_FILE"
done
for key in DB_OWNER_DATABASE DB_OWNER_USERNAME DB_OWNER_PASSWORD; do
  [[ -n "$(env_value "$OWNER_ENV_FILE" "$key")" ]] || fail "$key must be set in $OWNER_ENV_FILE"
done
for key in DB_BACKUP_DATABASE DB_BACKUP_USERNAME DB_BACKUP_PASSWORD; do
  [[ -n "$(env_value "$BACKUP_ENV_FILE" "$key")" ]] || fail "$key must be set in $BACKUP_ENV_FILE"
done

grep -Eq '^APP_ENV=production$' "$APP_ENV_FILE" || fail "APP_ENV must be production."
grep -Eq '^APP_DEBUG=(false|0)$' "$APP_ENV_FILE" || fail "APP_DEBUG must be false."
trusted_proxies="$(env_value "$APP_ENV_FILE" TRUSTED_PROXIES)"
[[ "$trusted_proxies" != "*" ]] || fail "TRUSTED_PROXIES=* is unsafe."

control_user="$(env_value "$APP_ENV_FILE" DB_USERNAME)"
runtime_user="$(env_value "$APP_ENV_FILE" DB_TENANT_USERNAME)"
owner_user="$(env_value "$OWNER_ENV_FILE" DB_OWNER_USERNAME)"
backup_user="$(env_value "$BACKUP_ENV_FILE" DB_BACKUP_USERNAME)"
[[ "$control_user" != "$runtime_user" ]] || fail "Control and runtime database users must differ."
[[ "$control_user" != "$owner_user" && "$control_user" != "$backup_user" ]] || fail "Control user must differ from owner/backup."
[[ "$runtime_user" != "$owner_user" && "$runtime_user" != "$backup_user" ]] || fail "Runtime user must differ from owner/backup."
[[ "$owner_user" != "$backup_user" ]] || fail "Owner and backup users must differ."

app_db="$(env_value "$APP_ENV_FILE" DB_DATABASE)"
runtime_db="$(env_value "$APP_ENV_FILE" DB_TENANT_DATABASE)"
owner_db="$(env_value "$OWNER_ENV_FILE" DB_OWNER_DATABASE)"
backup_db="$(env_value "$BACKUP_ENV_FILE" DB_BACKUP_DATABASE)"
[[ "$app_db" == "$runtime_db" && "$app_db" == "$owner_db" && "$app_db" == "$backup_db" ]] \
  || fail "All database identities must target the same database."

[[ -z "$(env_value "$APP_ENV_FILE" DB_OWNER_PASSWORD)" ]] || fail "Owner credentials must not be stored in the application env file."
[[ -z "$(env_value "$APP_ENV_FILE" DB_BACKUP_PASSWORD)" ]] || fail "Backup credentials must not be stored in the application env file."

chmod 600 "$APP_ENV_FILE" "$OWNER_ENV_FILE" "$BACKUP_ENV_FILE" || true
cd "$PROJECT_DIR"

if [[ "${DEPLOY_PULL:-false}" == "true" ]]; then
  log "Pulling the configured deployment branch"
  git pull --ff-only
fi

NEW_RELEASE="${SMARTBIZ_IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
OLD_RELEASE=""
[[ -f "$CURRENT_FILE" ]] && OLD_RELEASE="$(cat "$CURRENT_FILE")"

export SMARTBIZ_IMAGE_TAG="$NEW_RELEASE"
COMPOSE=(
  docker compose
  --env-file "$APP_ENV_FILE"
  --env-file "$OWNER_ENV_FILE"
  --env-file "$BACKUP_ENV_FILE"
  -f "$COMPOSE_FILE"
)

log "Validating production configuration"
"${COMPOSE[@]}" config --quiet

log "Building immutable release images: $NEW_RELEASE"
"${COMPOSE[@]}" build --pull app nginx

log "Starting PostgreSQL and Redis"
"${COMPOSE[@]}" up -d postgres redis

log "Creating/rotating non-owner database roles on the existing schema"
"${COMPOSE[@]}" --profile operations run --rm ops smartbiz-bootstrap-db-roles

backup_before_migrate="$(env_value "$APP_ENV_FILE" DEPLOY_BACKUP_BEFORE_MIGRATE)"
if [[ "${backup_before_migrate:-true}" =~ ^(true|1|yes)$ ]]; then
  log "Creating a verified pre-migration database backup with the read-only backup role"
  "${COMPOSE[@]}" --profile operations run --rm ops php artisan db:backup --no-interaction
fi

log "Running migrations with the database owner identity"
"${COMPOSE[@]}" --profile operations run --rm ops \
  php artisan migrate --database=pgsql_owner --force --no-interaction

log "Reapplying fail-closed RLS policies and least-privilege grants"
"${COMPOSE[@]}" --profile operations run --rm ops smartbiz-bootstrap-db-roles

log "Verifying database role separation and tenant isolation"
"${COMPOSE[@]}" --profile operations run --rm ops smartbiz-verify-db-roles

log "Starting application, worker, schedulers and Nginx"
"${COMPOSE[@]}" up -d --remove-orphans app worker scheduler backup-scheduler nginx

files_backup_before_readiness="$(env_value "$APP_ENV_FILE" DEPLOY_FILES_BACKUP_BEFORE_READINESS)"
if [[ "${files_backup_before_readiness:-true}" =~ ^(true|1|yes)$ ]]; then
  log "Creating a verified application-files backup before readiness"
  "${COMPOSE[@]}" exec -T backup-scheduler php artisan files:backup --no-interaction
fi

log "Restarting queue workers gracefully"
"${COMPOSE[@]}" exec -T app php artisan queue:restart

log "Waiting for liveness and deep operational readiness"
healthy=false
for attempt in $(seq 1 40); do
  if "${COMPOSE[@]}" exec -T nginx wget -qO- http://127.0.0.1:8080/up >/dev/null 2>&1 \
    && "${COMPOSE[@]}" exec -T app php artisan ops:check --json --fail-on-warning >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep 3
done

if [[ "$healthy" != "true" ]]; then
  "${COMPOSE[@]}" ps
  "${COMPOSE[@]}" exec -T app php artisan ops:check --json >&2 || true
  "${COMPOSE[@]}" logs --tail=150 app nginx worker scheduler backup-scheduler >&2 || true

  if [[ -n "$OLD_RELEASE" ]]; then
    printf '❌ Readiness check failed. Run: infra/rollback.sh %q\n' "$ENVIRONMENT" >&2
  fi
  exit 1
fi

if [[ -n "$OLD_RELEASE" && "$OLD_RELEASE" != "$NEW_RELEASE" ]]; then
  printf '%s\n' "$OLD_RELEASE" > "$PREVIOUS_FILE"
fi
printf '%s\n' "$NEW_RELEASE" > "$CURRENT_FILE"

log "Deployment complete: $NEW_RELEASE"
"${COMPOSE[@]}" ps
