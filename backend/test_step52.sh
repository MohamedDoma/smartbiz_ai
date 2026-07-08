#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 52 Pipeline/Custom Fields API Tests ==="

# 1. Register owner
echo -n "1. Register owner... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"PipeTest\",\"email\":\"pipe${U}@t.com\",\"phone_number\":\"+2189${U}001\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"PipeTest WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] && [ "$WSID" != "null" ] && [ -n "$WSID" ]; then echo "PASS (ws=$WSID)"; PASS=$((PASS+1)); else echo "FAIL: $(echo $REG | head -c 300)"; FAIL=$((FAIL+1)); exit 1; fi

c() {
  curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"
}

# 2. Create pipeline
echo -n "2. Create pipeline... "
P=$(c "$API/pipelines" -X POST -d '{"name":"Vehicle Sales","description":"Car sales workflow","entity_type":"sales","sort_order":10}')
PID=$(echo "$P" | jq -r '.data.id')
PNAME=$(echo "$P" | jq -r '.data.name')
if [ "$PNAME" = "Vehicle Sales" ]; then echo "PASS (id=$PID)"; PASS=$((PASS+1)); else echo "FAIL: $P"; FAIL=$((FAIL+1)); fi

# 3. Create stage 'Lead'
echo -n "3. Create stage Lead... "
S1=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Lead","status_type":"open","sort_order":10}')
S1ID=$(echo "$S1" | jq -r '.data.id')
if [ "$(echo "$S1" | jq -r '.data.name')" = "Lead" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S1"; FAIL=$((FAIL+1)); fi

# 4. Create stage 'Negotiation'
echo -n "4. Create stage Negotiation... "
S2=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Negotiation","status_type":"open","sort_order":20}')
S2ID=$(echo "$S2" | jq -r '.data.id')
if [ "$(echo "$S2" | jq -r '.data.name')" = "Negotiation" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S2"; FAIL=$((FAIL+1)); fi

# 5. Create stage 'Won'
echo -n "5. Create stage Won... "
S3=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Won","status_type":"won","sort_order":30}')
S3ID=$(echo "$S3" | jq -r '.data.id')
if [ "$(echo "$S3" | jq -r '.data.status_type')" = "won" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S3"; FAIL=$((FAIL+1)); fi

# 6. Create text custom field (required)
echo -n "6. Create text custom field... "
CF1=$(c "$API/custom-fields" -X POST -d "{\"pipeline_id\":\"$PID\",\"label\":\"Car Model\",\"field_type\":\"text\",\"is_required\":true}")
CF1KEY=$(echo "$CF1" | jq -r '.data.field_key')
if [ "$CF1KEY" = "car-model" ] || [ "$CF1KEY" = "car_model" ]; then echo "PASS (key=$CF1KEY)"; PASS=$((PASS+1)); else echo "FAIL: $CF1"; FAIL=$((FAIL+1)); fi

# 7. Create select custom field
echo -n "7. Create select custom field... "
CF2=$(c "$API/custom-fields" -X POST -d "{\"pipeline_id\":\"$PID\",\"label\":\"Color\",\"field_type\":\"select\",\"options\":[\"Red\",\"Blue\",\"White\"]}")
CF2KEY=$(echo "$CF2" | jq -r '.data.field_key')
if [ -n "$CF2KEY" ] && [ "$CF2KEY" != "null" ]; then echo "PASS (key=$CF2KEY)"; PASS=$((PASS+1)); else echo "FAIL: $CF2"; FAIL=$((FAIL+1)); fi

# 8. Create record with custom values
echo -n "8. Create record... "
REC=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$S1ID\",\"title\":\"Toyota Camry deal\",\"value_amount\":30000,\"currency\":\"LYD\",\"custom_values\":{\"$CF1KEY\":\"Toyota Camry\",\"$CF2KEY\":\"White\"}}")
RECID=$(echo "$REC" | jq -r '.data.id')
RECTITLE=$(echo "$REC" | jq -r '.data.title')
if [ "$RECTITLE" = "Toyota Camry deal" ]; then echo "PASS (id=$RECID)"; PASS=$((PASS+1)); else echo "FAIL: $REC"; FAIL=$((FAIL+1)); fi

# 9. List records
echo -n "9. List records... "
LIST=$(c "$API/pipeline-records?pipeline_id=$PID")
COUNT=$(echo "$LIST" | jq '.data | length')
if [ "$COUNT" -ge 1 ]; then echo "PASS (count=$COUNT)"; PASS=$((PASS+1)); else echo "FAIL: $LIST"; FAIL=$((FAIL+1)); fi

# 10. Move record to Negotiation
echo -n "10. Move to Negotiation... "
MV=$(c "$API/pipeline-records/$RECID/move" -X POST -d "{\"stage_id\":\"$S2ID\"}")
MVSTAGE=$(echo "$MV" | jq -r '.data.stage.name')
MVSTATUS=$(echo "$MV" | jq -r '.data.status')
if [ "$MVSTAGE" = "Negotiation" ] && [ "$MVSTATUS" = "open" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $MV"; FAIL=$((FAIL+1)); fi

# 11. Move to Won (auto-close)
echo -n "11. Move to Won (auto-close)... "
MW=$(c "$API/pipeline-records/$RECID/move" -X POST -d "{\"stage_id\":\"$S3ID\"}")
MWSTATUS=$(echo "$MW" | jq -r '.data.status')
MWCLOSED=$(echo "$MW" | jq -r '.data.closed_at')
if [ "$MWSTATUS" = "won" ] && [ "$MWCLOSED" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $MW"; FAIL=$((FAIL+1)); fi

# 12. Show record with custom values
echo -n "12. Show with custom values... "
SHOW=$(c "$API/pipeline-records/$RECID")
CV=$(echo "$SHOW" | jq -r ".data.custom_values[\"$CF1KEY\"].value")
if [ "$CV" = "Toyota Camry" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $(echo $SHOW | head -c 200)"; FAIL=$((FAIL+1)); fi

# 13. Update record custom values
echo -n "13. Update custom values... "
UPD=$(c "$API/pipeline-records/$RECID" -X PUT -d "{\"custom_values\":{\"$CF1KEY\":\"Honda Civic\"}}")
UCV=$(echo "$UPD" | jq -r ".data.custom_values[\"$CF1KEY\"].value")
if [ "$UCV" = "Honda Civic" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $(echo $UPD | head -c 200)"; FAIL=$((FAIL+1)); fi

# 14. Required field missing → 422
echo -n "14. Required field missing → 422... "
ERR=$(curl -s -o /dev/null -w '%{http_code}' "$API/pipeline-records" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$S1ID\",\"title\":\"No car model\",\"custom_values\":{}}")
if [ "$ERR" = "422" ]; then echo "PASS (422)"; PASS=$((PASS+1)); else echo "FAIL ($ERR)"; FAIL=$((FAIL+1)); fi

# 15. Stage mismatch → 422
echo -n "15. Stage mismatch → 422... "
ERR2=$(curl -s -o /dev/null -w '%{http_code}' "$API/pipeline-records" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"00000000-0000-0000-0000-000000000000\",\"title\":\"Bad\",\"custom_values\":{\"$CF1KEY\":\"x\"}}")
if [ "$ERR2" = "422" ]; then echo "PASS (422)"; PASS=$((PASS+1)); else echo "FAIL ($ERR2)"; FAIL=$((FAIL+1)); fi

# 16. Missing workspace → error
echo -n "16. Missing workspace → error... "
ERR3=$(curl -s -o /dev/null -w '%{http_code}' "$API/pipelines" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR3" = "400" ] || [ "$ERR3" = "403" ] || [ "$ERR3" = "422" ]; then echo "PASS ($ERR3)"; PASS=$((PASS+1)); else echo "FAIL ($ERR3)"; FAIL=$((FAIL+1)); fi

# 17. Unauthenticated → 401
echo -n "17. Unauthenticated → 401... "
ERR4=$(curl -s -o /dev/null -w '%{http_code}' "$API/pipelines" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR4" = "401" ]; then echo "PASS (401)"; PASS=$((PASS+1)); else echo "FAIL ($ERR4)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 17 ==="
