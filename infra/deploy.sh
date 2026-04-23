#!/bin/bash
##
## SmartBiz AI — Deployment Script
## Usage: ./deploy.sh [staging|production]
##

set -euo pipefail

ENV="${1:-production}"
COMPOSE_FILE="infra/docker-compose.prod.yml"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "══════════════════════════════════════════════════"
echo " SmartBiz AI — Deploying to: ${ENV}"
echo "══════════════════════════════════════════════════"

cd "$PROJECT_DIR"

# 1. Pull latest code (if using git)
if [ -d ".git" ]; then
    echo "→ Pulling latest code..."
    git pull origin main --ff-only
fi

# 2. Build containers
echo "→ Building containers..."
docker compose -f "$COMPOSE_FILE" build --no-cache

# 3. Start infrastructure (DB + Redis first)
echo "→ Starting infrastructure..."
docker compose -f "$COMPOSE_FILE" up -d postgres redis
sleep 5

# 4. Install dependencies
echo "→ Installing composer dependencies..."
docker compose -f "$COMPOSE_FILE" run --rm app composer install --no-dev --optimize-autoloader --no-interaction

# 5. Run migrations
echo "→ Running migrations..."
docker compose -f "$COMPOSE_FILE" run --rm app php artisan migrate --force --no-interaction

# 6. Cache configuration
echo "→ Caching configuration..."
docker compose -f "$COMPOSE_FILE" run --rm app php artisan config:cache
docker compose -f "$COMPOSE_FILE" run --rm app php artisan route:cache
docker compose -f "$COMPOSE_FILE" run --rm app php artisan view:cache
docker compose -f "$COMPOSE_FILE" run --rm app php artisan event:cache

# 7. Start all services
echo "→ Starting application..."
docker compose -f "$COMPOSE_FILE" up -d

# 8. Restart queue workers (pick up new code)
echo "→ Restarting queue workers..."
docker compose -f "$COMPOSE_FILE" exec -T app php artisan queue:restart

# 9. Health check
echo "→ Waiting for health check..."
sleep 5
HEALTH=$(curl -sf http://localhost:80/api/health || echo '{"status":"error"}')
echo "  Health: ${HEALTH}"

echo ""
echo "══════════════════════════════════════════════════"
echo " Deployment complete!"
echo "══════════════════════════════════════════════════"
