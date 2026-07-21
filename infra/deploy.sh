#!/usr/bin/env bash
set -Eeuo pipefail

ENVIRONMENT="${1:-production}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$PROJECT_DIR/infra/docker-compose.prod.yml"
ENV_FILE="$PROJECT_DIR/backend/.env.${ENVIRONMENT}"
STATE_DIR="${SMARTBIZ_DEPLOY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/smartbiz}"
CURRENT_FILE="$STATE_DIR/current-release"
PREVIOUS_FILE="$STATE_DIR/previous-release"
mkdir -p "$STATE_DIR"

if [[ "$ENVIRONMENT" == "production" ]]; then
  ENV_FILE="$PROJECT_DIR/backend/.env.production"
fi

log() { printf '→ %s\n' "$*"; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "Docker is required."
docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 is required."
[[ -f "$ENV_FILE" ]] || fail "Missing environment file: $ENV_FILE"
[[ -f "$COMPOSE_FILE" ]] || fail "Missing compose file: $COMPOSE_FILE"

required_keys=(APP_KEY APP_URL FRONTEND_URL DB_PASSWORD REDIS_PASSWORD)
for key in "${required_keys[@]}"; do
  value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
  [[ -n "$value" ]] || fail "$key must be set in $ENV_FILE"
done

grep -Eq '^APP_ENV=production$' "$ENV_FILE" || fail "APP_ENV must be production."
grep -Eq '^APP_DEBUG=(false|0)$' "$ENV_FILE" || fail "APP_DEBUG must be false."
trusted_proxies="$(grep -E '^TRUSTED_PROXIES=' "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
[[ "$trusted_proxies" != "*" ]] || fail "TRUSTED_PROXIES=* is unsafe; configure explicit proxy IPs/CIDRs or leave it empty."

chmod 600 "$ENV_FILE" || true
cd "$PROJECT_DIR"

if [[ "${DEPLOY_PULL:-false}" == "true" ]]; then
  log "Pulling the configured deployment branch"
  git pull --ff-only
fi

NEW_RELEASE="${SMARTBIZ_IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
OLD_RELEASE=""
[[ -f "$CURRENT_FILE" ]] && OLD_RELEASE="$(cat "$CURRENT_FILE")"

export SMARTBIZ_IMAGE_TAG="$NEW_RELEASE"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

log "Validating production configuration"
"${COMPOSE[@]}" config --quiet

log "Building immutable release images: $NEW_RELEASE"
"${COMPOSE[@]}" build --pull app nginx

log "Starting PostgreSQL and Redis"
"${COMPOSE[@]}" up -d postgres redis

backup_before_migrate="$(grep -E '^DEPLOY_BACKUP_BEFORE_MIGRATE=' "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
if [[ "${backup_before_migrate:-true}" =~ ^(true|1|yes)$ ]]; then
  log "Creating a verified pre-migration database backup"
  "${COMPOSE[@]}" run --rm app php artisan db:backup --no-interaction
fi

log "Running database migrations"
"${COMPOSE[@]}" run --rm app php artisan migrate --force --no-interaction

log "Starting application, worker, scheduler and Nginx"
"${COMPOSE[@]}" up -d --remove-orphans app worker scheduler nginx

files_backup_before_readiness="$(grep -E '^DEPLOY_FILES_BACKUP_BEFORE_READINESS=' "$ENV_FILE" | tail -n1 | cut -d= -f2- || true)"
if [[ "${files_backup_before_readiness:-true}" =~ ^(true|1|yes)$ ]]; then
  log "Creating a verified application-files backup before readiness"
  "${COMPOSE[@]}" exec -T app php artisan files:backup --no-interaction
fi

log "Restarting queue workers gracefully"
"${COMPOSE[@]}" exec -T app php artisan queue:restart

log "Waiting for application liveness and deep operational readiness"
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
  "${COMPOSE[@]}" logs --tail=150 app nginx worker scheduler >&2 || true

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
