#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 57 Finance Integration API Tests ==="

# 1. Register
echo -n "1. Register... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"FinTest\",\"email\":\"fin${U}@t.com\",\"phone_number\":\"+218${U}07\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"FIN WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"; }

# 2. Bootstrap finance
echo -n "2. Bootstrap... "
BS=$(c "$API/finance/bootstrap" -X POST)
BS_MSG=$(echo "$BS" | jq -r '.message')
BS_COUNT=$(echo "$BS" | jq '.data | length')
if [ "$BS_COUNT" -ge 8 ]; then echo "PASS ($BS_COUNT accounts)"; PASS=$((PASS+1)); else echo "FAIL: $BS"; FAIL=$((FAIL+1)); fi

# 3. List accounts
echo -n "3. List accounts... "
ACCTS=$(c "$API/finance/accounts")
ACCT_C=$(echo "$ACCTS" | jq '.data | length')
if [ "$ACCT_C" -ge 8 ]; then echo "PASS ($ACCT_C)"; PASS=$((PASS+1)); else echo "FAIL: $ACCTS"; FAIL=$((FAIL+1)); fi

# Get account IDs for cash + general expense
CASH_ID=$(echo "$ACCTS" | jq -r '.data[] | select(.code=="1000") | .id')
EXPENSE_ID=$(echo "$ACCTS" | jq -r '.data[] | select(.code=="5000") | .id')
BANK_ID=$(echo "$ACCTS" | jq -r '.data[] | select(.code=="1010") | .id')

# 4. Create balanced transaction
echo -n "4. Balanced txn... "
TXN=$(c "$API/finance/transactions" -X POST -d "{\"transaction_date\":\"2026-07-08\",\"description\":\"Test transfer\",\"lines\":[{\"finance_account_id\":\"$CASH_ID\",\"debit_amount\":500,\"credit_amount\":0},{\"finance_account_id\":\"$BANK_ID\",\"debit_amount\":0,\"credit_amount\":500}]}")
TXN_ID=$(echo "$TXN" | jq -r '.data.id')
if [ "$TXN_ID" != "null" ] && [ -n "$TXN_ID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $TXN"; FAIL=$((FAIL+1)); fi

# 5. Reject unbalanced
echo -n "5. Unbalanced → 422... "
ERR=$(curl -s -o /dev/null -w '%{http_code}' "$API/finance/transactions" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d "{\"transaction_date\":\"2026-07-08\",\"lines\":[{\"finance_account_id\":\"$CASH_ID\",\"debit_amount\":100,\"credit_amount\":0},{\"finance_account_id\":\"$BANK_ID\",\"debit_amount\":0,\"credit_amount\":50}]}")
if [ "$ERR" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR)"; FAIL=$((FAIL+1)); fi

# 6. Create expense
echo -n "6. Create expense... "
EXP=$(c "$API/finance/expenses" -X POST -d '{"expense_date":"2026-07-08","category":"Rent","description":"Office rent","amount":1000,"currency":"LYD","payment_method":"cash"}')
EXP_ID=$(echo "$EXP" | jq -r '.data.id')
EXP_TXN=$(echo "$EXP" | jq -r '.data.finance_transaction_id')
if [ "$EXP_ID" != "null" ] && [ "$EXP_TXN" != "null" ]; then echo "PASS (txn=$EXP_TXN)"; PASS=$((PASS+1)); else echo "FAIL: $EXP"; FAIL=$((FAIL+1)); fi

# 7. List expenses
echo -n "7. List expenses... "
EXPS=$(c "$API/finance/expenses")
EXP_C=$(echo "$EXPS" | jq '.data | length')
if [ "$EXP_C" -ge 1 ]; then echo "PASS ($EXP_C)"; PASS=$((PASS+1)); else echo "FAIL: $EXPS"; FAIL=$((FAIL+1)); fi

# 8. Get summary
echo -n "8. Summary... "
SUM=$(c "$API/finance/summary")
NET=$(echo "$SUM" | jq -r '.data.net_profit')
CASH_BAL=$(echo "$SUM" | jq -r '.data.cash_balance')
echo "PASS (net=$NET cash=$CASH_BAL)"; PASS=$((PASS+1))

# 9. Get profit/loss
echo -n "9. Profit/loss... "
PL=$(c "$API/finance/profit-loss")
PL_EXP=$(echo "$PL" | jq -r '.data.expenses')
if [ -n "$PL_EXP" ]; then echo "PASS (expenses=$PL_EXP)"; PASS=$((PASS+1)); else echo "FAIL: $PL"; FAIL=$((FAIL+1)); fi

# 10. Get account balances
echo -n "10. Account balances... "
AB=$(c "$API/finance/account-balances")
AB_C=$(echo "$AB" | jq '.data | length')
if [ "$AB_C" -ge 8 ]; then echo "PASS ($AB_C accounts)"; PASS=$((PASS+1)); else echo "FAIL: $AB"; FAIL=$((FAIL+1)); fi

# 11. Void transaction
echo -n "11. Void txn... "
VD=$(c "$API/finance/transactions/$TXN_ID/void" -X POST)
VD_ST=$(echo "$VD" | jq -r '.data.status')
if [ "$VD_ST" = "void" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $VD"; FAIL=$((FAIL+1)); fi

# 12. Void same → error
echo -n "12. Void again → 422... "
VD2=$(curl -s -o /dev/null -w '%{http_code}' "$API/finance/transactions/$TXN_ID/void" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID")
if [ "$VD2" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($VD2)"; FAIL=$((FAIL+1)); fi

# 13. Commission posting: create pipeline record + commission entry via tinker
echo -n "13. Commission entry... "
MEMB=$(docker exec smartbiz_app php artisan tinker --execute="echo \App\Models\WorkspaceMembership::where('workspace_id','$WSID')->first()?->id;" 2>/dev/null | tr -d '\r\n')
P=$(c "$API/pipelines" -X POST -d '{"name":"Sales","entity_type":"sales"}')
PID=$(echo "$P" | jq -r '.data.id')
S=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Won","status_type":"won","sort_order":1}')
SID=$(echo "$S" | jq -r '.data.id')
R=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$SID\",\"title\":\"Deal A\",\"value_amount\":50000,\"currency\":\"LYD\",\"assigned_membership_id\":\"$MEMB\"}")
RID=$(echo "$R" | jq -r '.data.id')
CE_ID=$(docker exec smartbiz_app php artisan tinker --execute="
\$e = \App\Models\CommissionEntry::create([
  'workspace_id' => '$WSID',
  'pipeline_record_id' => '$RID',
  'recipient_membership_id' => '$MEMB',
  'base_amount' => 50000,
  'commission_amount' => 5000,
  'currency' => 'LYD',
  'calculation_type' => 'percentage',
  'percentage_rate' => 10,
  'status' => 'pending',
  'calculated_at' => now(),
]);
echo \$e->id;
" 2>/dev/null | tr -d '\r\n')
if [ -n "$CE_ID" ] && [ "$CE_ID" != "null" ]; then echo "PASS (entry=$CE_ID)"; PASS=$((PASS+1)); else echo "FAIL ($CE_ID)"; FAIL=$((FAIL+1)); fi

# 14. Post commission to finance
echo -n "14. Post commission... "
if [ -n "$CE_ID" ] && [ "$CE_ID" != "null" ]; then
  PC=$(c "$API/commission-entries/$CE_ID/post-to-finance" -X POST)
  PC_ID=$(echo "$PC" | jq -r '.data.id')
  if [ "$PC_ID" != "null" ] && [ -n "$PC_ID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $PC"; FAIL=$((FAIL+1)); fi
else
  echo "SKIP (no commission)"; FAIL=$((FAIL+1))
fi

# 15. Duplicate commission post → 409
echo -n "15. Dup commission → 409... "
if [ -n "$CE_ID" ] && [ "$CE_ID" != "null" ]; then
  DPC=$(curl -s -o /dev/null -w '%{http_code}' "$API/commission-entries/$CE_ID/post-to-finance" -X POST \
    -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID")
  if [ "$DPC" = "409" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($DPC)"; FAIL=$((FAIL+1)); fi
else
  echo "SKIP"; FAIL=$((FAIL+1))
fi

# 16. Report catalog includes finance
echo -n "16. Catalog + finance... "
CAT=$(c "$API/report-catalog")
CAT_C=$(echo "$CAT" | jq '.data | length')
if [ "$CAT_C" -ge 11 ]; then echo "PASS ($CAT_C sources)"; PASS=$((PASS+1)); else echo "FAIL ($CAT_C): $CAT"; FAIL=$((FAIL+1)); fi

# 17. Missing workspace → error
echo -n "17. Missing WS → error... "
ERR4=$(curl -s -o /dev/null -w '%{http_code}' "$API/finance/accounts" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR4" = "400" ] || [ "$ERR4" = "403" ] || [ "$ERR4" = "422" ]; then echo "PASS ($ERR4)"; PASS=$((PASS+1)); else echo "FAIL ($ERR4)"; FAIL=$((FAIL+1)); fi

# 18. Unauthenticated → 401
echo -n "18. Unauth → 401... "
ERR5=$(curl -s -o /dev/null -w '%{http_code}' "$API/finance/accounts" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR5" = "401" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR5)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 18 ==="
