#!/usr/bin/env bash
##
## SmartBiz AI — Database Bootstrap Script
## Loads base schema + 13 additive migrations in order.
##
## Usage (from project root):
##   docker compose -f infra/docker-compose.yml exec postgres sh /architecture/../../scripts/bootstrap-db.sh
##
## Or run directly inside the postgres container:
##   sh /scripts/bootstrap-db.sh
##
## Prerequisites: PostgreSQL must be running and the smartbiz database must exist.
##

set -euo pipefail

PSQL="psql -U smartbiz -d smartbiz -v ON_ERROR_STOP=1"
ARCH_DIR="/architecture"

echo "============================================"
echo " SmartBiz AI — Database Bootstrap"
echo "============================================"
echo ""

# --- Step 1: Load base schema ---
echo "[1/14] Loading base schema: 1_database_schema.sql"
$PSQL -f "$ARCH_DIR/1_database_schema.sql"
echo "       ✓ Base schema loaded"
echo ""

# --- Step 2: Run additive migrations 001–013 ---
MIGRATIONS=(
  "001_additive_foundation.sql"
  "002_rbac_persistence.sql"
  "003_financial_controls.sql"
  "004_hr_workforce.sql"
  "005_inventory_logistics.sql"
  "006_membership_refactor.sql"
  "007_backfill_migrations.sql"
  "008_cleanup_deprecation.sql"
  "009_optimization_hardening.sql"
  "010_alignment_infra.sql"
  "011_final_hardening.sql"
  "012_closure.sql"
  "013_expansion_domains.sql"
)

STEP=2
for migration in "${MIGRATIONS[@]}"; do
  echo "[${STEP}/14] Running migration: ${migration}"
  $PSQL -f "$ARCH_DIR/migrations/${migration}"
  echo "       ✓ ${migration} applied"
  echo ""
  STEP=$((STEP + 1))
done

# --- Step 3: Verify ---
echo "============================================"
echo " Verification"
echo "============================================"

TABLE_COUNT=$($PSQL -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';")
echo "  Tables created: $(echo $TABLE_COUNT | xargs)"

EXTENSION_OK=$($PSQL -t -c "SELECT count(*) FROM pg_extension WHERE extname = 'pgcrypto';")
echo "  pgcrypto extension: $([ $(echo $EXTENSION_OK | xargs) -eq 1 ] && echo '✓ installed' || echo '✗ MISSING')"

UUID_TEST=$($PSQL -t -c "SELECT gen_random_uuid();" 2>/dev/null && echo "✓ working" || echo "✗ FAILED")
echo "  gen_random_uuid(): ${UUID_TEST}"

echo ""
echo "============================================"
echo " Database bootstrap complete."
echo "============================================"
