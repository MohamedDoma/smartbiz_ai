#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/Desktop/final/smartbiz_ai}"
INFRA_DIR="$PROJECT_DIR/infra"
TEST_DB="${TEST_DB:-smartbiz_test}"
TEST_DB_PASSWORD="${DB_PASSWORD:-smartbiz_dev}"

cd "$INFRA_DIR"

echo "Starting PostgreSQL and application containers..."
docker compose up -d postgres app

echo "Rebuilding isolated PostgreSQL database: $TEST_DB"
docker compose exec -T postgres \
  psql -U smartbiz -d postgres -v ON_ERROR_STOP=1 <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '$TEST_DB'
  AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS $TEST_DB;
CREATE DATABASE $TEST_DB OWNER smartbiz;
SQL

artisan_test() {
  docker compose exec -T \
    -e APP_ENV=testing \
    -e DB_CONNECTION=pgsql \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_DATABASE="$TEST_DB" \
    -e DB_USERNAME=smartbiz \
    -e DB_PASSWORD="$TEST_DB_PASSWORD" \
    -e REDIS_HOST=redis \
    -e REDIS_PORT=6379 \
    app php artisan "$@"
}

echo "Loading the baseline schema and pending migrations..."
artisan_test config:clear
artisan_test migrate --force

echo "Seeding the complete deterministic backend test fixture..."
artisan_test db:seed --class='Database\Seeders\TestSuiteSeeder' --force

echo "Verifying required fixture records..."
docker compose exec -T postgres psql -U smartbiz -d "$TEST_DB" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'admin@smartbiz.test') THEN
        RAISE EXCEPTION 'Missing foundation test user';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM users WHERE email = 'readonly@cert.test') THEN
        RAISE EXCEPTION 'Missing certification RBAC users';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM platform_plans) THEN
        RAISE EXCEPTION 'Missing platform plans';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM warehouses WHERE id = 'c6000000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Missing certification warehouse';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = 'c7000000-0000-0000-0000-000000000001') THEN
        RAISE EXCEPTION 'Missing certification account';
    END IF;
END $$;
SQL

echo
echo "✅ Test database prepared successfully: $TEST_DB"
echo "✅ Foundation, platform, RBAC/isolation, and demo-parent fixtures loaded."
echo "✅ Development database smartbiz was not touched."
