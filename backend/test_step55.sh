#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 55 Duplicate/Ownership API Tests ==="

# 1. Register owner
echo -n "1. Register... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"OwnerTest\",\"email\":\"own${U}@t.com\",\"phone_number\":\"+218${U}02\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"OwnTest WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"; }

# Get membership
MEMB=$(c "$API/workspaces/$WSID/memberships" | jq -r '.data[0].id // empty')
if [ -z "$MEMB" ]; then
  MEMB=$(docker exec smartbiz_app php artisan tinker --execute="echo \App\Models\WorkspaceMembership::where('workspace_id','$WSID')->first()?->id;" 2>/dev/null | tr -d '\r\n' || true)
fi
echo "  membership=$MEMB"

# 2. Create contact
echo -n "2. Create contact... "
CT=$(c "$API/contacts" -X POST -d "{\"name\":\"Ahmed Ali\",\"phone\":\"+218 91 123 4567\",\"email\":\"ahmed${U}@example.com\",\"type\":\"customer\"}")
CTID=$(echo "$CT" | jq -r '.data.id')
if [ "$CTID" != "null" ] && [ -n "$CTID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $CT"; FAIL=$((FAIL+1)); fi

# 3. Create duplicate rule for phone
echo -n "3. Create dup rule (phone)... "
DR=$(c "$API/duplicate-rules" -X POST -d '{"name":"Dup phone","entity_type":"contact","match_fields":["phone"],"action":"warn"}')
DRID=$(echo "$DR" | jq -r '.data.id')
if [ "$DRID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DR"; FAIL=$((FAIL+1)); fi

# 4. Check duplicate with same phone
echo -n "4. Dup check same phone... "
DC=$(c "$API/duplicates/check" -X POST -d "{\"entity_type\":\"contact\",\"payload\":{\"phone\":\"+21891 123 4567\"}}")
DC_MATCH=$(echo "$DC" | jq '.data.matches | length')
if [ "$DC_MATCH" -ge 1 ]; then echo "PASS (matches=$DC_MATCH)"; PASS=$((PASS+1)); else echo "FAIL: $DC"; FAIL=$((FAIL+1)); fi

# 4b. Create second contact with same phone to generate match records
echo -n "4b. Second contact... "
CT2=$(c "$API/contacts" -X POST -d "{\"name\":\"Ahmed Duplicate\",\"phone\":\"+218 91 123 4567\",\"email\":\"ahmed2_${U}@example.com\",\"type\":\"customer\"}")
CT2ID=$(echo "$CT2" | jq -r '.data.id')
if [ "$CT2ID" != "null" ] && [ -n "$CT2ID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $CT2"; FAIL=$((FAIL+1)); fi

# 4c. Check dup with exclude_entity_id to create match records
echo -n "4c. Dup check with exclude... "
DC_E=$(c "$API/duplicates/check" -X POST -d "{\"entity_type\":\"contact\",\"payload\":{\"phone\":\"+218 91 123 4567\"},\"exclude_entity_id\":\"$CT2ID\"}")
DC_E_MATCH=$(echo "$DC_E" | jq '.data.matches | length')
if [ "$DC_E_MATCH" -ge 1 ]; then echo "PASS ($DC_E_MATCH)"; PASS=$((PASS+1)); else echo "FAIL: $DC_E"; FAIL=$((FAIL+1)); fi

# 5. Check duplicate with different phone
echo -n "5. Dup check diff phone... "
DC2=$(c "$API/duplicates/check" -X POST -d '{"entity_type":"contact","payload":{"phone":"+218999999"}}')
DC2_MATCH=$(echo "$DC2" | jq '.data.matches | length')
if [ "$DC2_MATCH" -eq 0 ]; then echo "PASS (0 matches)"; PASS=$((PASS+1)); else echo "FAIL: $DC2"; FAIL=$((FAIL+1)); fi

# 6. Create ownership for contact
echo -n "6. Assign owner... "
OA=$(c "$API/ownership-assignments" -X POST -d "{\"entity_type\":\"contact\",\"entity_id\":\"$CTID\",\"owner_membership_id\":\"$MEMB\",\"source\":\"manual\"}")
OAID=$(echo "$OA" | jq -r '.data.id')
if [ "$OAID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $OA"; FAIL=$((FAIL+1)); fi

# 7. Duplicate assign → 409
echo -n "7. Dup assign → 409... "
OA2=$(curl -s -o /dev/null -w '%{http_code}' "$API/ownership-assignments" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d "{\"entity_type\":\"contact\",\"entity_id\":\"$CTID\",\"owner_membership_id\":\"$MEMB\"}")
if [ "$OA2" = "409" ]; then echo "PASS (409)"; PASS=$((PASS+1)); else echo "FAIL ($OA2)"; FAIL=$((FAIL+1)); fi

# 8. Resolve ownership for contact
echo -n "8. Resolve owner... "
RO=$(c "$API/ownership/resolve?entity_type=contact&entity_id=$CTID")
ROSRC=$(echo "$RO" | jq -r '.data.source')
if [ "$ROSRC" = "ownership_assignment" ]; then echo "PASS ($ROSRC)"; PASS=$((PASS+1)); else echo "FAIL: $RO"; FAIL=$((FAIL+1)); fi

# 9. Create pipeline + record for ownership fallback
echo -n "9. Pipeline + record... "
P=$(c "$API/pipelines" -X POST -d '{"name":"Sales","entity_type":"sales"}')
PID=$(echo "$P" | jq -r '.data.id')
S=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Open","status_type":"open","sort_order":1}')
SID=$(echo "$S" | jq -r '.data.id')
R=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$SID\",\"title\":\"Lead A\",\"value_amount\":50000,\"assigned_membership_id\":\"$MEMB\"}")
RID=$(echo "$R" | jq -r '.data.id')
if [ "$RID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; FAIL=$((FAIL+1)); fi

# 10. Resolve ownership fallback for pipeline_record
echo -n "10. Fallback owner... "
RO2=$(c "$API/ownership/resolve?entity_type=pipeline_record&entity_id=$RID")
RO2SRC=$(echo "$RO2" | jq -r '.data.source')
if [ "$RO2SRC" = "assigned_membership_fallback" ]; then echo "PASS ($RO2SRC)"; PASS=$((PASS+1)); else echo "FAIL: $RO2"; FAIL=$((FAIL+1)); fi

# 11. Create dup rule for pipeline_record title
echo -n "11. Dup rule (title)... "
DR2=$(c "$API/duplicate-rules" -X POST -d '{"name":"Dup title","entity_type":"pipeline_record","match_fields":["title"],"action":"warn"}')
DR2ID=$(echo "$DR2" | jq -r '.data.id')
if [ "$DR2ID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DR2"; FAIL=$((FAIL+1)); fi

# 12. Check dup pipeline record
echo -n "12. Dup check record... "
DC3=$(c "$API/duplicates/check" -X POST -d '{"entity_type":"pipeline_record","payload":{"title":"Lead A"}}')
DC3_MATCH=$(echo "$DC3" | jq '.data.matches | length')
if [ "$DC3_MATCH" -ge 1 ]; then echo "PASS ($DC3_MATCH)"; PASS=$((PASS+1)); else echo "FAIL: $DC3"; FAIL=$((FAIL+1)); fi

# 13. List duplicate matches
echo -n "13. List matches... "
DML=$(c "$API/duplicate-matches")
DML_C=$(echo "$DML" | jq '.data | length')
DMID=$(echo "$DML" | jq -r '.data[0].id // empty')
if [ "$DML_C" -ge 1 ]; then echo "PASS (count=$DML_C)"; PASS=$((PASS+1)); else echo "FAIL: $DML"; FAIL=$((FAIL+1)); fi

# 14. Resolve match
echo -n "14. Resolve match... "
if [ -n "$DMID" ]; then
  RM=$(c "$API/duplicate-matches/$DMID/resolve" -X POST -d '{"resolution":"keep_separate"}')
  RMST=$(echo "$RM" | jq -r '.data.status')
  if [ "$RMST" = "resolved" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $RM"; FAIL=$((FAIL+1)); fi
else echo "SKIP (no match id)"; FAIL=$((FAIL+1)); fi

# 15. List rules
echo -n "15. List rules... "
DRL=$(c "$API/duplicate-rules")
DRL_C=$(echo "$DRL" | jq '.data | length')
if [ "$DRL_C" -ge 2 ]; then echo "PASS ($DRL_C)"; PASS=$((PASS+1)); else echo "FAIL: $DRL"; FAIL=$((FAIL+1)); fi

# 16. Delete rule (deactivate)
echo -n "16. Delete rule... "
DD=$(c "$API/duplicate-rules/$DRID" -X DELETE)
DDM=$(echo "$DD" | jq -r '.message')
if echo "$DDM" | grep -qi "deactivated"; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DD"; FAIL=$((FAIL+1)); fi

# 17. Missing workspace → error
echo -n "17. Missing WS → error... "
ERR1=$(curl -s -o /dev/null -w '%{http_code}' "$API/ownership-assignments" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR1" = "400" ] || [ "$ERR1" = "403" ] || [ "$ERR1" = "422" ]; then echo "PASS ($ERR1)"; PASS=$((PASS+1)); else echo "FAIL ($ERR1)"; FAIL=$((FAIL+1)); fi

# 18. Unauthenticated → 401
echo -n "18. Unauth → 401... "
ERR2=$(curl -s -o /dev/null -w '%{http_code}' "$API/ownership-assignments" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR2" = "401" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR2)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 20 ==="
