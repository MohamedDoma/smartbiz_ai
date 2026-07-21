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

[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }
[[ -f "$PREVIOUS_FILE" ]] || { echo "No previous release is recorded." >&2; exit 1; }

PREVIOUS_RELEASE="$(cat "$PREVIOUS_FILE")"
CURRENT_RELEASE=""
[[ -f "$CURRENT_FILE" ]] && CURRENT_RELEASE="$(cat "$CURRENT_FILE")"

export SMARTBIZ_IMAGE_TAG="$PREVIOUS_RELEASE"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE")

"${COMPOSE[@]}" config --quiet
"${COMPOSE[@]}" up -d --no-build app worker scheduler nginx
"${COMPOSE[@]}" exec -T app php artisan queue:restart

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
  "${COMPOSE[@]}" exec -T app php artisan ops:check --json >&2 || true
  echo "Rollback readiness check failed." >&2
  exit 1
fi

printf '%s\n' "$PREVIOUS_RELEASE" > "$CURRENT_FILE"
if [[ -n "$CURRENT_RELEASE" ]]; then
  printf '%s\n' "$CURRENT_RELEASE" > "$PREVIOUS_FILE"
fi

echo "Rollback complete: $PREVIOUS_RELEASE"
echo "Note: database migrations are not reversed automatically."
