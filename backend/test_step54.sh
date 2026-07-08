#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 54 Commission Rules API Tests ==="

# 1. Register owner
echo -n "1. Register owner... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"CommTest\",\"email\":\"comm${U}@t.com\",\"phone_number\":\"+218${U}01\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"CommTest WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] && [ "$WSID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $(echo $REG | head -c 200)"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"; }

# Get owner membership id
echo -n "  (resolving membership)... "
MEMB=$(c "$API/workspaces/$WSID/memberships" | jq -r '.data[0].id // empty')
if [ -z "$MEMB" ]; then
  MEMB=$(c "$API/me" | jq -r '.data.active_workspace.membership_id // empty')
fi
if [ -z "$MEMB" ]; then
  # Fallback: query workspace memberships raw
  MEMB=$(docker exec smartbiz_app php artisan tinker --execute="echo \App\Models\WorkspaceMembership::where('workspace_id','$WSID')->first()?->id;" 2>/dev/null | tr -d '\r\n' || true)
fi
echo "membership=$MEMB"

# 2. Create pipeline
echo -n "2. Create pipeline... "
P=$(c "$API/pipelines" -X POST -d '{"name":"Vehicle Sales","entity_type":"sales"}')
PID=$(echo "$P" | jq -r '.data.id')
if [ "$PID" != "null" ] && [ -n "$PID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $P"; FAIL=$((FAIL+1)); fi

# 3. Create open stage
echo -n "3. Create open stage... "
S1=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Negotiation","status_type":"open","sort_order":10}')
S1ID=$(echo "$S1" | jq -r '.data.id')
if [ "$S1ID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S1"; FAIL=$((FAIL+1)); fi

# 4. Create won stage
echo -n "4. Create won stage... "
S2=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Closed Won","status_type":"won","sort_order":20}')
S2ID=$(echo "$S2" | jq -r '.data.id')
if [ "$S2ID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S2"; FAIL=$((FAIL+1)); fi

# 5. Create record with value AND assigned_membership_id
echo -n "5. Create record... "
R=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$S1ID\",\"title\":\"Toyota Camry\",\"value_amount\":100000,\"currency\":\"LYD\",\"assigned_membership_id\":\"$MEMB\"}")
RID=$(echo "$R" | jq -r '.data.id')
if [ "$RID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $R"; FAIL=$((FAIL+1)); fi

# 6. Move to won stage
echo -n "6. Move to won... "
MV=$(c "$API/pipeline-records/$RID/move" -X POST -d "{\"stage_id\":\"$S2ID\"}")
MVST=$(echo "$MV" | jq -r '.data.status')
if [ "$MVST" = "won" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($MVST): $MV"; FAIL=$((FAIL+1)); fi

# 7. Create commission plan
echo -n "7. Create plan... "
CP=$(c "$API/commission-plans" -X POST -d '{"name":"Vehicle Sales Commission","description":"Standard commission for sales"}')
CPID=$(echo "$CP" | jq -r '.data.id')
CPNAME=$(echo "$CP" | jq -r '.data.name')
if [ "$CPNAME" = "Vehicle Sales Commission" ]; then echo "PASS (id=$CPID)"; PASS=$((PASS+1)); else echo "FAIL: $CP"; FAIL=$((FAIL+1)); fi

# 8. Create percentage rule
echo -n "8. Create percentage rule... "
CR=$(c "$API/commission-rules" -X POST -d "{\"commission_plan_id\":\"$CPID\",\"pipeline_id\":\"$PID\",\"target_type\":\"assigned_employee\",\"calculation_type\":\"percentage\",\"percentage_rate\":1.5,\"trigger_status\":\"won\"}")
CRID=$(echo "$CR" | jq -r '.data.id')
CRRATE=$(echo "$CR" | jq -r '.data.percentage_rate')
if [ "$CRID" != "null" ]; then echo "PASS (rate=$CRRATE)"; PASS=$((PASS+1)); else echo "FAIL: $CR"; FAIL=$((FAIL+1)); fi

# 9. Calculate commissions
echo -n "9. Calculate commissions... "
CALC=$(c "$API/pipeline-records/$RID/calculate-commissions" -X POST)
CCOUNT=$(echo "$CALC" | jq '.data.created_count')
CAMOUNT=$(echo "$CALC" | jq -r '.data.entries[0].commission_amount // "0"')
if [ "$CCOUNT" -ge 1 ]; then echo "PASS (count=$CCOUNT, amount=$CAMOUNT)"; PASS=$((PASS+1)); else echo "FAIL: $CALC"; FAIL=$((FAIL+1)); fi

# 10. Calculate again = no duplicates
echo -n "10. No duplicates... "
CALC2=$(c "$API/pipeline-records/$RID/calculate-commissions" -X POST)
CCOUNT2=$(echo "$CALC2" | jq '.data.created_count')
if [ "$CCOUNT2" -eq 0 ]; then echo "PASS (0 new)"; PASS=$((PASS+1)); else echo "FAIL ($CCOUNT2 new): $CALC2"; FAIL=$((FAIL+1)); fi

# 11. List entries
echo -n "11. List entries... "
EL=$(c "$API/commission-entries")
ELC=$(echo "$EL" | jq '.data | length')
EID=$(echo "$EL" | jq -r '.data[0].id')
if [ "$ELC" -ge 1 ]; then echo "PASS (count=$ELC)"; PASS=$((PASS+1)); else echo "FAIL: $EL"; FAIL=$((FAIL+1)); fi

# 12. Mark approved
echo -n "12. Mark approved... "
MA=$(c "$API/commission-entries/$EID/mark-approved" -X POST)
MAST=$(echo "$MA" | jq -r '.data.status')
if [ "$MAST" = "approved" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($MAST): $MA"; FAIL=$((FAIL+1)); fi

# 13. Mark paid
echo -n "13. Mark paid... "
MP=$(c "$API/commission-entries/$EID/mark-paid" -X POST)
MPST=$(echo "$MP" | jq -r '.data.status')
if [ "$MPST" = "paid" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($MPST): $MP"; FAIL=$((FAIL+1)); fi

# 14. Cancel paid → 409
echo -n "14. Cancel paid → 409... "
CC=$(curl -s -o /dev/null -w '%{http_code}' "$API/commission-entries/$EID/cancel" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID")
if [ "$CC" = "409" ]; then echo "PASS (409)"; PASS=$((PASS+1)); else echo "FAIL ($CC)"; FAIL=$((FAIL+1)); fi

# 15. Create fixed amount rule
echo -n "15. Fixed amount rule... "
CR2=$(c "$API/commission-rules" -X POST -d "{\"commission_plan_id\":\"$CPID\",\"pipeline_id\":\"$PID\",\"target_type\":\"assigned_employee\",\"calculation_type\":\"fixed_amount\",\"fixed_amount\":500,\"trigger_status\":\"won\"}")
CR2ID=$(echo "$CR2" | jq -r '.data.id')
if [ "$CR2ID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $CR2"; FAIL=$((FAIL+1)); fi

# 16. Calculate with fixed rule
echo -n "16. Calculate fixed... "
CALC3=$(c "$API/pipeline-records/$RID/calculate-commissions" -X POST)
CCOUNT3=$(echo "$CALC3" | jq '.data.created_count')
FAMOUNT=$(echo "$CALC3" | jq -r '.data.entries[0].commission_amount // "0"')
if [ "$CCOUNT3" -ge 1 ]; then echo "PASS (fixed=$FAMOUNT)"; PASS=$((PASS+1)); else echo "FAIL: $CALC3"; FAIL=$((FAIL+1)); fi

# 17. Missing workspace → error
echo -n "17. Missing workspace → error... "
ERR1=$(curl -s -o /dev/null -w '%{http_code}' "$API/commission-plans" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR1" = "400" ] || [ "$ERR1" = "403" ] || [ "$ERR1" = "422" ]; then echo "PASS ($ERR1)"; PASS=$((PASS+1)); else echo "FAIL ($ERR1)"; FAIL=$((FAIL+1)); fi

# 18. Unauthenticated → 401
echo -n "18. Unauthenticated → 401... "
ERR2=$(curl -s -o /dev/null -w '%{http_code}' "$API/commission-plans" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR2" = "401" ]; then echo "PASS (401)"; PASS=$((PASS+1)); else echo "FAIL ($ERR2)"; FAIL=$((FAIL+1)); fi

# 19. Verify commission amount math (1.5% of 100000 = 1500)
echo -n "19. Verify math... "
EL2=$(c "$API/commission-entries?pipeline_record_id=$RID")
PCTAMT=$(echo "$EL2" | jq -r '[.data[] | select(.calculation_type=="percentage")][0].commission_amount // "0"')
# Should be 1500.00
if echo "$PCTAMT" | grep -q "1500"; then echo "PASS (1500)"; PASS=$((PASS+1)); else echo "FAIL ($PCTAMT)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 19 ==="
