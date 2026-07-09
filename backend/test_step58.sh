#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 58 Platform Admin + Activation Codes Tests ==="

# 1. Register normal user
echo -n "1. Register normal... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"PlatTest\",\"email\":\"plat${U}@t.com\",\"phone_number\":\"+218${U}01\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"Plat WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
USERID=$(echo "$REG" | jq -r '.user.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $REG"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN"; }

# 2. Normal user CANNOT access platform dashboard
echo -n "2. Normal user → 403... "
PD_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$API/platform/dashboard" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$PD_CODE" = "403" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($PD_CODE)"; FAIL=$((FAIL+1)); fi

# 3. Promote to platform admin
echo -n "3. Promote to SA... "
docker exec smartbiz_app php artisan tinker --execute="\$u = \App\Models\User::find('$USERID'); \$u->is_super_admin = true; \$u->save(); echo 'ok';" 2>/dev/null | tr -d '\r\n' | grep -q 'ok'
if [ $? -eq 0 ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; FAIL=$((FAIL+1)); fi

# 4. Platform dashboard accessible
echo -n "4. SA dashboard... "
PD=$(c "$API/platform/dashboard")
TOTAL_WS=$(echo "$PD" | jq -r '.data.workspaces.total')
if [ "$TOTAL_WS" != "null" ] && [ -n "$TOTAL_WS" ]; then echo "PASS (ws=$TOTAL_WS)"; PASS=$((PASS+1)); else echo "FAIL: $PD"; FAIL=$((FAIL+1)); fi

# 5. List platform workspaces
echo -n "5. List workspaces... "
PWS=$(c "$API/platform/workspaces")
WS_COUNT=$(echo "$PWS" | jq '.data | length')
if [ "$WS_COUNT" -ge 1 ]; then echo "PASS ($WS_COUNT)"; PASS=$((PASS+1)); else echo "FAIL: $PWS"; FAIL=$((FAIL+1)); fi

# 6. List users
echo -n "6. List users... "
PU=$(c "$API/platform/users")
U_COUNT=$(echo "$PU" | jq '.data | length')
if [ "$U_COUNT" -ge 1 ]; then echo "PASS ($U_COUNT)"; PASS=$((PASS+1)); else echo "FAIL: $PU"; FAIL=$((FAIL+1)); fi

# 7. Create activation campaign
echo -n "7. Create campaign... "
CAMP=$(c "$API/platform/activation-campaigns" -X POST -d '{"name":"Test July","description":"Test cards","target_market":"Tripoli shops","default_plan_key":"starter","trial_days":14,"status":"active"}')
CAMP_ID=$(echo "$CAMP" | jq -r '.data.id')
if [ "$CAMP_ID" != "null" ] && [ -n "$CAMP_ID" ]; then echo "PASS (id=$CAMP_ID)"; PASS=$((PASS+1)); else echo "FAIL: $CAMP"; FAIL=$((FAIL+1)); fi

# 8. Generate 3 codes
echo -n "8. Generate 3 codes... "
GEN=$(c "$API/platform/activation-campaigns/$CAMP_ID/codes/generate" -X POST -d '{"count":3,"assigned_to_name":"Sales A"}')
GEN_COUNT=$(echo "$GEN" | jq -r '.data.generated_count')
CODE1=$(echo "$GEN" | jq -r '.data.codes[0].code')
CODE2=$(echo "$GEN" | jq -r '.data.codes[1].code')
CODE3=$(echo "$GEN" | jq -r '.data.codes[2].code')
if [ "$GEN_COUNT" = "3" ]; then echo "PASS ($CODE1, $CODE2, $CODE3)"; PASS=$((PASS+1)); else echo "FAIL: $GEN"; FAIL=$((FAIL+1)); fi

# 9. List codes
echo -n "9. List codes... "
CODES=$(c "$API/platform/activation-codes")
C_COUNT=$(echo "$CODES" | jq '.data | length')
if [ "$C_COUNT" -ge 3 ]; then echo "PASS ($C_COUNT)"; PASS=$((PASS+1)); else echo "FAIL: $CODES"; FAIL=$((FAIL+1)); fi

# 10. Public validate code (no auth)
echo -n "10. Public validate... "
PV=$(curl -s "$API/activation-codes/$CODE1" -H 'Accept: application/json')
PV_VALID=$(echo "$PV" | jq -r '.valid')
PV_PLAN=$(echo "$PV" | jq -r '.plan_key')
if [ "$PV_VALID" = "true" ]; then echo "PASS (plan=$PV_PLAN)"; PASS=$((PASS+1)); else echo "FAIL: $PV"; FAIL=$((FAIL+1)); fi

# 11. Register with activation code
echo -n "11. Register + code... "
U2=$((RANDOM+10000))
REG2=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"CodeUser\",\"email\":\"code${U2}@t.com\",\"phone_number\":\"+218${U2}02\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"Code WS\",\"activation_code\":\"$CODE1\"}")
TOKEN2=$(echo "$REG2" | jq -r '.token')
WSID2=$(echo "$REG2" | jq -r '.active_workspace.id')
if [ "$TOKEN2" != "null" ] && [ -n "$TOKEN2" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $REG2"; FAIL=$((FAIL+1)); fi

# 12. Code status becomes used
echo -n "12. Code now used... "
CV=$(curl -s "$API/activation-codes/$CODE1" -H 'Accept: application/json')
CV_VALID=$(echo "$CV" | jq -r '.valid')
if [ "$CV_VALID" = "false" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $CV"; FAIL=$((FAIL+1)); fi

# 13. Used code cannot be reused
echo -n "13. Reuse → 422... "
U3=$((RANDOM+20000))
REG3=$(curl -s -o /dev/null -w '%{http_code}' "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"Reuse\",\"email\":\"reuse${U3}@t.com\",\"phone_number\":\"+218${U3}03\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"Reuse WS\",\"activation_code\":\"$CODE1\"}")
if [ "$REG3" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($REG3)"; FAIL=$((FAIL+1)); fi

# 14. Disable a code
echo -n "14. Disable code... "
CODE2_ID=$(echo "$GEN" | jq -r '.data.codes[1].id')
DC=$(c "$API/platform/activation-codes/$CODE2_ID/status" -X PUT -d '{"status":"disabled"}')
DC_ST=$(echo "$DC" | jq -r '.data.status')
if [ "$DC_ST" = "disabled" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DC"; FAIL=$((FAIL+1)); fi

# 15. Disabled code cannot be used
echo -n "15. Disabled → invalid... "
DV=$(curl -s "$API/activation-codes/$CODE2" -H 'Accept: application/json')
DV_VALID=$(echo "$DV" | jq -r '.valid')
if [ "$DV_VALID" = "false" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DV"; FAIL=$((FAIL+1)); fi

# 16. Update workspace status
echo -n "16. Update WS status... "
US=$(c "$API/platform/workspaces/$WSID/status" -X PUT -d '{"status":"suspended"}')
US_ST=$(echo "$US" | jq -r '.data.status')
if [ "$US_ST" = "suspended" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $US"; FAIL=$((FAIL+1)); fi

# 17. Update workspace subscription
echo -n "17. Update subscription... "
UB=$(c "$API/platform/workspaces/$WSID/subscription" -X PUT -d '{"subscription_status":"active"}')
UB_ST=$(echo "$UB" | jq -r '.data.subscription_status')
if [ "$UB_ST" = "active" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $UB"; FAIL=$((FAIL+1)); fi

# 18. Dashboard counts updated
echo -n "18. Dashboard update... "
PD2=$(c "$API/platform/dashboard")
SUSP=$(echo "$PD2" | jq -r '.data.workspaces.suspended')
USED=$(echo "$PD2" | jq -r '.data.codes.used')
if [ "$SUSP" -ge 1 ] && [ "$USED" -ge 1 ]; then echo "PASS (susp=$SUSP used=$USED)"; PASS=$((PASS+1)); else echo "FAIL: $PD2"; FAIL=$((FAIL+1)); fi

# 19. Unauthenticated → 401
echo -n "19. No auth → 401... "
NA=$(curl -s -o /dev/null -w '%{http_code}' "$API/platform/dashboard" -H 'Accept: application/json')
if [ "$NA" = "401" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($NA)"; FAIL=$((FAIL+1)); fi

# 20. Register normal user verifies 403
echo -n "20. New user → 403... "
U4=$((RANDOM+30000))
REG4=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"Normal\",\"email\":\"norm${U4}@t.com\",\"phone_number\":\"+218${U4}04\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"Normal WS\"}")
TK4=$(echo "$REG4" | jq -r '.token')
N_CODE=$(curl -s -o /dev/null -w '%{http_code}' "$API/platform/dashboard" -H "Authorization: Bearer $TK4" -H 'Accept: application/json')
if [ "$N_CODE" = "403" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($N_CODE)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 20 ==="
