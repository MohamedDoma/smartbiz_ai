#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 53 Document Checklists API Tests ==="

# 1. Register owner
echo -n "1. Register owner... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"DocTest\",\"email\":\"doc${U}@t.com\",\"phone_number\":\"+2189${U}01\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"DocTest WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ] && [ "$WSID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $(echo $REG | head -c 200)"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"; }

# 2. Create pipeline
echo -n "2. Create pipeline... "
P=$(c "$API/pipelines" -X POST -d '{"name":"Sales","entity_type":"sales"}')
PID=$(echo "$P" | jq -r '.data.id')
if [ "$PID" != "null" ] && [ -n "$PID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $P"; FAIL=$((FAIL+1)); fi

# 3. Create stage
echo -n "3. Create stage... "
S=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Payment","status_type":"open","sort_order":10}')
SID=$(echo "$S" | jq -r '.data.id')
if [ "$SID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $S"; FAIL=$((FAIL+1)); fi

# 4. Create pipeline record
echo -n "4. Create record... "
R=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$SID\",\"title\":\"Deal ABC\"}")
RID=$(echo "$R" | jq -r '.data.id')
if [ "$RID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $R"; FAIL=$((FAIL+1)); fi

# 5. Create checklist linked to pipeline+stage
echo -n "5. Create checklist... "
CL=$(c "$API/document-checklists" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$SID\",\"name\":\"Payment Documents\",\"description\":\"Docs for payment stage\"}")
CLID=$(echo "$CL" | jq -r '.data.id')
CLNAME=$(echo "$CL" | jq -r '.data.name')
if [ "$CLNAME" = "Payment Documents" ]; then echo "PASS (id=$CLID)"; PASS=$((PASS+1)); else echo "FAIL: $CL"; FAIL=$((FAIL+1)); fi

# 6. Create required checklist item
echo -n "6. Create required item... "
I1=$(c "$API/document-checklists/$CLID/items" -X POST -d '{"title":"Payment Proof","is_required":true,"accepted_file_types":["pdf","jpg","png"],"max_file_size_mb":5}')
I1ID=$(echo "$I1" | jq -r '.data.id')
I1REQ=$(echo "$I1" | jq -r '.data.is_required')
if [ "$I1REQ" = "true" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $I1"; FAIL=$((FAIL+1)); fi

# 7. Create optional checklist item
echo -n "7. Create optional item... "
I2=$(c "$API/document-checklists/$CLID/items" -X POST -d '{"title":"Additional Notes","is_required":false}')
I2ID=$(echo "$I2" | jq -r '.data.id')
I2REQ=$(echo "$I2" | jq -r '.data.is_required')
if [ "$I2REQ" = "false" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $I2"; FAIL=$((FAIL+1)); fi

# 8. Document status before upload → missing_count > 0
echo -n "8. Status before → missing... "
ST1=$(c "$API/pipeline-records/$RID/document-status")
MC1=$(echo "$ST1" | jq '.data.missing_count')
RC1=$(echo "$ST1" | jq '.data.required_count')
if [ "$MC1" -ge 1 ] && [ "$RC1" -ge 1 ]; then echo "PASS (missing=$MC1, required=$RC1)"; PASS=$((PASS+1)); else echo "FAIL: $ST1"; FAIL=$((FAIL+1)); fi

# 9. Provide manual document for required item
echo -n "9. Provide manual document... "
D1=$(c "$API/pipeline-records/$RID/documents" -X POST -d "{\"document_checklist_item_id\":\"$I1ID\",\"title\":\"Payment Proof\",\"status\":\"provided\",\"external_reference\":\"Cash receipt #456\",\"notes\":\"Physical copy stored\"}")
D1ID=$(echo "$D1" | jq -r '.data.id')
D1STATUS=$(echo "$D1" | jq -r '.data.status')
if [ "$D1STATUS" = "provided" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $D1"; FAIL=$((FAIL+1)); fi

# 10. Document status after provide → missing_count decreases
echo -n "10. Status after → missing decreased... "
ST2=$(c "$API/pipeline-records/$RID/document-status")
MC2=$(echo "$ST2" | jq '.data.missing_count')
CC2=$(echo "$ST2" | jq '.data.completed_count')
if [ "$MC2" -lt "$MC1" ] && [ "$CC2" -ge 1 ]; then echo "PASS (missing=$MC2, completed=$CC2)"; PASS=$((PASS+1)); else echo "FAIL: $ST2"; FAIL=$((FAIL+1)); fi

# 11. List record documents
echo -n "11. List record documents... "
DL=$(c "$API/pipeline-records/$RID/documents")
DC=$(echo "$DL" | jq '.data | length')
if [ "$DC" -ge 1 ]; then echo "PASS (count=$DC)"; PASS=$((PASS+1)); else echo "FAIL: $DL"; FAIL=$((FAIL+1)); fi

# 12. Upload small text file
echo -n "12. Upload file... "
TMPF=$(mktemp /tmp/doctest_XXXX.txt)
echo "Test document content" > "$TMPF"
D2=$(curl -s "$API/pipeline-records/$RID/documents" -X POST \
  -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" -H 'Accept: application/json' \
  -F "document_checklist_item_id=$I2ID" -F "title=Test Note" -F "file=@$TMPF")
D2STATUS=$(echo "$D2" | jq -r '.data.status')
D2NAME=$(echo "$D2" | jq -r '.data.original_filename')
rm -f "$TMPF"
if [ "$D2STATUS" = "uploaded" ]; then echo "PASS (file=$D2NAME)"; PASS=$((PASS+1)); else echo "FAIL: $D2"; FAIL=$((FAIL+1)); fi

# 13. Invalid file type returns 422
echo -n "13. Invalid file type → 422... "
TMPF2=$(mktemp /tmp/doctest_XXXX.exe)
echo "fake exe" > "$TMPF2"
ERR1=$(curl -s -o /dev/null -w '%{http_code}' "$API/pipeline-records/$RID/documents" -X POST \
  -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" -H 'Accept: application/json' \
  -F "document_checklist_item_id=$I1ID" -F "title=Bad file" -F "file=@$TMPF2")
rm -f "$TMPF2"
if [ "$ERR1" = "422" ]; then echo "PASS (422)"; PASS=$((PASS+1)); else echo "FAIL ($ERR1)"; FAIL=$((FAIL+1)); fi

# 14. Missing workspace → error
echo -n "14. Missing workspace → error... "
ERR2=$(curl -s -o /dev/null -w '%{http_code}' "$API/document-checklists" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR2" = "400" ] || [ "$ERR2" = "403" ] || [ "$ERR2" = "422" ]; then echo "PASS ($ERR2)"; PASS=$((PASS+1)); else echo "FAIL ($ERR2)"; FAIL=$((FAIL+1)); fi

# 15. Unauthenticated → 401
echo -n "15. Unauthenticated → 401... "
ERR3=$(curl -s -o /dev/null -w '%{http_code}' "$API/document-checklists" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR3" = "401" ]; then echo "PASS (401)"; PASS=$((PASS+1)); else echo "FAIL ($ERR3)"; FAIL=$((FAIL+1)); fi

# 16. List checklists
echo -n "16. List checklists... "
LC=$(c "$API/document-checklists")
LCC=$(echo "$LC" | jq '.data | length')
if [ "$LCC" -ge 1 ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $LC"; FAIL=$((FAIL+1)); fi

# 17. Show checklist with items
echo -n "17. Show checklist detail... "
SC=$(c "$API/document-checklists/$CLID")
SCI=$(echo "$SC" | jq '.data.items | length')
if [ "$SCI" -ge 2 ]; then echo "PASS (items=$SCI)"; PASS=$((PASS+1)); else echo "FAIL: $SC"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 17 ==="
