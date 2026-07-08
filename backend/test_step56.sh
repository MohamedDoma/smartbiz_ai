#!/usr/bin/env bash
set -euo pipefail
API="http://localhost:8080/api"
U=$RANDOM
PASS=0; FAIL=0

echo "=== Step 56 Report Templates API Tests ==="

# 1. Register
echo -n "1. Register... "
REG=$(curl -s "$API/auth/register" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -d "{\"full_name\":\"ReportTest\",\"email\":\"rpt${U}@t.com\",\"phone_number\":\"+218${U}03\",\"password\":\"Secret123!\",\"password_confirmation\":\"Secret123!\",\"workspace_name\":\"RPT WS\"}")
TOKEN=$(echo "$REG" | jq -r '.token')
WSID=$(echo "$REG" | jq -r '.active_workspace.id')
if [ "$TOKEN" != "null" ] && [ -n "$TOKEN" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; exit 1; fi

c() { curl -s "$@" -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID"; }

# 2. Create contact
echo -n "2. Create contact... "
CT=$(c "$API/contacts" -X POST -d "{\"name\":\"Salim Ali\",\"phone\":\"+218912345\",\"email\":\"s${U}@x.com\",\"type\":\"customer\"}")
CTID=$(echo "$CT" | jq -r '.data.id')
if [ "$CTID" != "null" ] && [ -n "$CTID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $CT"; FAIL=$((FAIL+1)); fi

# 3. Create pipeline + record
echo -n "3. Pipeline+record... "
P=$(c "$API/pipelines" -X POST -d '{"name":"Sales","entity_type":"sales"}')
PID=$(echo "$P" | jq -r '.data.id')
S=$(c "$API/pipelines/$PID/stages" -X POST -d '{"name":"Won","status_type":"won","sort_order":1}')
SID=$(echo "$S" | jq -r '.data.id')
MEMB=$(docker exec smartbiz_app php artisan tinker --execute="echo \App\Models\WorkspaceMembership::where('workspace_id','$WSID')->first()?->id;" 2>/dev/null | tr -d '\r\n' || true)
if [ -z "$MEMB" ]; then
  MEMB=$(c "$API/workspaces/$WSID/memberships" | jq -r '.data[0].id // empty')
fi
R=$(c "$API/pipeline-records" -X POST -d "{\"pipeline_id\":\"$PID\",\"stage_id\":\"$SID\",\"title\":\"Big Deal\",\"value_amount\":75000,\"currency\":\"LYD\",\"assigned_membership_id\":\"$MEMB\"}")
RID=$(echo "$R" | jq -r '.data.id')
if [ "$RID" != "null" ] && [ -n "$RID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL"; FAIL=$((FAIL+1)); fi

# 4. Get report catalog
echo -n "4. Get catalog... "
CAT=$(c "$API/report-catalog")
CAT_C=$(echo "$CAT" | jq '.data | length')
if [ "$CAT_C" -ge 8 ]; then echo "PASS ($CAT_C sources)"; PASS=$((PASS+1)); else echo "FAIL: $CAT"; FAIL=$((FAIL+1)); fi

# 5. Get catalog for pipeline_records
echo -n "5. Catalog detail... "
CDS=$(c "$API/report-catalog/pipeline_records")
CDS_COLS=$(echo "$CDS" | jq '.data.columns | length')
if [ "$CDS_COLS" -ge 5 ]; then echo "PASS ($CDS_COLS cols)"; PASS=$((PASS+1)); else echo "FAIL: $CDS"; FAIL=$((FAIL+1)); fi

# 6. Create pipeline_records report template
echo -n "6. Create template... "
TPL=$(c "$API/report-templates" -X POST -d '{"name":"Pipeline Summary","description":"All pipeline records","data_source":"pipeline_records","columns":["title","status","value_amount","currency"],"filters":[],"sort_by":[{"field":"value_amount","direction":"desc"}],"visibility":"workspace"}')
TPLID=$(echo "$TPL" | jq -r '.data.id')
if [ "$TPLID" != "null" ] && [ -n "$TPLID" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $TPL"; FAIL=$((FAIL+1)); fi

# 7. Run template
echo -n "7. Run template... "
RUN=$(c "$API/report-templates/$TPLID/run" -X POST -d '{"parameters":{"limit":50}}')
RUN_RC=$(echo "$RUN" | jq '.data.summary.row_count')
RUN_TOTAL=$(echo "$RUN" | jq -r '.data.summary.totals.value_amount // empty')
if [ "$RUN_RC" -ge 1 ]; then echo "PASS (rows=$RUN_RC total=$RUN_TOTAL)"; PASS=$((PASS+1)); else echo "FAIL: $RUN"; FAIL=$((FAIL+1)); fi

# 8. List report runs
echo -n "8. List runs... "
RUNS=$(c "$API/report-runs")
RUNS_C=$(echo "$RUNS" | jq '.data | length')
if [ "$RUNS_C" -ge 1 ]; then echo "PASS ($RUNS_C)"; PASS=$((PASS+1)); else echo "FAIL: $RUNS"; FAIL=$((FAIL+1)); fi

# 9. Create contacts report template
echo -n "9. Contacts template... "
TPL2=$(c "$API/report-templates" -X POST -d '{"name":"Contact List","data_source":"contacts","columns":["name","type","phone","email"],"visibility":"workspace"}')
TPL2ID=$(echo "$TPL2" | jq -r '.data.id')
if [ "$TPL2ID" != "null" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $TPL2"; FAIL=$((FAIL+1)); fi

# 10. Run contacts report
echo -n "10. Run contacts... "
RUN2=$(c "$API/report-templates/$TPL2ID/run" -X POST -d '{}')
RUN2_RC=$(echo "$RUN2" | jq '.data.summary.row_count')
if [ "$RUN2_RC" -ge 1 ]; then echo "PASS (rows=$RUN2_RC)"; PASS=$((PASS+1)); else echo "FAIL: $RUN2"; FAIL=$((FAIL+1)); fi

# 11. Ad-hoc report
echo -n "11. Ad-hoc report... "
AH=$(c "$API/reports/run" -X POST -d '{"data_source":"contacts","columns":["name","type","balance"],"filters":[{"field":"type","operator":"equals","value":"customer"}]}')
AH_RC=$(echo "$AH" | jq '.data.summary.row_count')
if [ "$AH_RC" -ge 1 ]; then echo "PASS (rows=$AH_RC)"; PASS=$((PASS+1)); else echo "FAIL: $AH"; FAIL=$((FAIL+1)); fi

# 12. Invalid data source → 422
echo -n "12. Invalid source → 422... "
ERR=$(curl -s -o /dev/null -w '%{http_code}' "$API/report-templates" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d '{"name":"Bad","data_source":"nonexistent","columns":["x"]}')
if [ "$ERR" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR)"; FAIL=$((FAIL+1)); fi

# 13. Invalid column → 422
echo -n "13. Invalid column → 422... "
ERR2=$(curl -s -o /dev/null -w '%{http_code}' "$API/report-templates" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d '{"name":"Bad2","data_source":"contacts","columns":["nonexistent_col"]}')
if [ "$ERR2" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR2)"; FAIL=$((FAIL+1)); fi

# 14. Invalid filter field → 422
echo -n "14. Invalid filter → 422... "
ERR3=$(curl -s -o /dev/null -w '%{http_code}' "$API/reports/run" -X POST \
  -H 'Content-Type: application/json' -H 'Accept: application/json' -H "Authorization: Bearer $TOKEN" -H "X-Workspace-Id: $WSID" \
  -d '{"data_source":"contacts","columns":["name"],"filters":[{"field":"password_hash","operator":"equals","value":"x"}]}')
if [ "$ERR3" = "422" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR3)"; FAIL=$((FAIL+1)); fi

# 15. Delete template (deactivate)
echo -n "15. Delete template... "
DD=$(c "$API/report-templates/$TPL2ID" -X DELETE)
DDM=$(echo "$DD" | jq -r '.message')
if echo "$DDM" | grep -qi "deactivated"; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL: $DD"; FAIL=$((FAIL+1)); fi

# 16. List templates (deleted should be gone)
echo -n "16. List templates... "
TL=$(c "$API/report-templates")
TL_C=$(echo "$TL" | jq '.data | length')
if [ "$TL_C" -ge 1 ]; then echo "PASS ($TL_C active)"; PASS=$((PASS+1)); else echo "FAIL: $TL"; FAIL=$((FAIL+1)); fi

# 17. Missing workspace → error
echo -n "17. Missing WS → error... "
ERR4=$(curl -s -o /dev/null -w '%{http_code}' "$API/report-catalog" -H "Authorization: Bearer $TOKEN" -H 'Accept: application/json')
if [ "$ERR4" = "400" ] || [ "$ERR4" = "403" ] || [ "$ERR4" = "422" ]; then echo "PASS ($ERR4)"; PASS=$((PASS+1)); else echo "FAIL ($ERR4)"; FAIL=$((FAIL+1)); fi

# 18. Unauthenticated → 401
echo -n "18. Unauth → 401... "
ERR5=$(curl -s -o /dev/null -w '%{http_code}' "$API/report-catalog" -H 'Accept: application/json' -H "X-Workspace-Id: $WSID")
if [ "$ERR5" = "401" ]; then echo "PASS"; PASS=$((PASS+1)); else echo "FAIL ($ERR5)"; FAIL=$((FAIL+1)); fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed out of 18 ==="
