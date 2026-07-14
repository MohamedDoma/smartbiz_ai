<?php
/**
 * SmartBiz AI — Step 60 End-to-End Approval Engine Verification
 *
 * Exercises the full approval lifecycle against live database:
 *  1. Syncs demo workflow to canonical JSON conditions
 *  2. Creates test CommissionEntry (amount=750, currency=SAR)
 *  3. Evaluates trigger conditions via ApprovalTriggerEvaluator
 *  4. Submits approval request via ApprovalEngine
 *  5. Decides step 1 (Manager Review) → approved
 *  6. Decides step 2 (Finance Approval) → approved
 *  7. Verifies CommissionEntry.status transitioned to 'approved'
 *  8. Verifies audit trail integrity
 *  9. Tests negative case: amount=200 should NOT trigger
 * 10. Cleans up test data
 *
 * Usage:
 *   docker exec smartbiz_app php scripts/verify_step60_real_commission.php
 */

require_once __DIR__ . '/../vendor/autoload.php';

$app = require_once __DIR__ . '/../bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use App\Models\ApprovalRequest;
use App\Models\ApprovalWorkflow;
use App\Models\AuditLog;
use App\Models\CommissionEntry;
use App\Models\WorkspaceMembership;
use App\Services\ApprovalEngine;
use App\Services\ApprovalTriggerEvaluator;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

$workspaceId = 'dd000000-0000-0000-0000-000000000001';
$passed = 0;
$failed = 0;
$testEntityIds = []; // Track test data for cleanup

function pass(string $msg): void {
    global $passed;
    $passed++;
    echo "  ✅ PASS: {$msg}\n";
}

function fail(string $msg): void {
    global $failed;
    $failed++;
    echo "  ❌ FAIL: {$msg}\n";
}

echo "════════════════════════════════════════════════════\n";
echo "  SmartBiz AI — Step 60 E2E Verification\n";
echo "  Workspace: {$workspaceId}\n";
echo "════════════════════════════════════════════════════\n\n";

// ── Pre-flight: Ensure workspace and tables exist ──────────

$workspace = DB::table('workspaces')->where('id', $workspaceId)->first();
if (!$workspace) {
    echo "❌ FATAL: Demo workspace not found.\n";
    exit(1);
}

// ── 1. Verify workflow has canonical JSON conditions ───────

echo "── TEST 1: Workflow Condition Format ───────────────\n\n";

// Run sync script first to ensure canonical state
echo "  Running sync script...\n";
$syncOutput = [];
$syncReturn = 0;
exec('php ' . __DIR__ . '/sync_demo_approval_workflows.php 2>&1', $syncOutput, $syncReturn);
if ($syncReturn !== 0) {
    echo "  ⚠️ Sync script returned non-zero: {$syncReturn}\n";
    echo "  " . implode("\n  ", $syncOutput) . "\n";
}

$workflow = DB::table('approval_workflows')
    ->where('workspace_id', $workspaceId)
    ->where('workflow_key', 'high_commission_approval')
    ->first();

if (!$workflow) {
    echo "❌ FATAL: Workflow not found after sync.\n";
    exit(1);
}

$conditions = json_decode($workflow->trigger_conditions, true);

// T1a: Must have 'logic' key
if (isset($conditions['logic']) && $conditions['logic'] === 'and') {
    pass("trigger_conditions has 'logic': 'and'");
} else {
    fail("trigger_conditions missing 'logic' key or not 'and'. Got: " . json_encode($conditions));
}

// T1b: Must have 'conditions' array
if (isset($conditions['conditions']) && is_array($conditions['conditions']) && count($conditions['conditions']) === 2) {
    pass("trigger_conditions has 2 condition objects");
} else {
    fail("trigger_conditions 'conditions' array wrong shape. Got: " . json_encode($conditions));
}

// T1c: First condition must be {field: "amount", operator: "greater_than_or_equal", value: 500}
$c1 = $conditions['conditions'][0] ?? [];
if (($c1['field'] ?? '') === 'amount' && ($c1['operator'] ?? '') === 'greater_than_or_equal' && ($c1['value'] ?? 0) == 500) {
    pass("Condition 1: amount >= 500");
} else {
    fail("Condition 1 wrong. Got: " . json_encode($c1));
}

// T1d: No legacy keys
if (!isset($conditions['min_commission_amount']) && !isset($conditions['commission_amount'])) {
    pass("No legacy min_commission_amount / commission_amount keys");
} else {
    fail("Legacy keys still present in trigger_conditions");
}

// T1e: Verify step permissions
$steps = DB::table('approval_workflow_steps')
    ->where('workflow_id', $workflow->id)
    ->orderBy('step_order')
    ->get();

if ($steps->count() === 2) {
    pass("Workflow has exactly 2 steps");
} else {
    fail("Expected 2 steps, got " . $steps->count());
}

$step1Key = $steps[0]->approver_permission_key ?? '';
$step2Key = $steps[1]->approver_permission_key ?? '';

if ($step1Key === 'commissions.approve') {
    pass("Step 1 uses commissions.approve");
} else {
    fail("Step 1 permission wrong: '{$step1Key}'");
}

if ($step2Key === 'approvals.decide') {
    pass("Step 2 uses approvals.decide");
} else {
    fail("Step 2 permission wrong: '{$step2Key}'");
}

echo "\n";

// ── 2. Resolve test actors ────────────────────────────────

echo "── TEST 2: Actor Resolution ───────────────────────\n\n";

// Find owner membership (has commissions.approve + approvals.decide)
$ownerRole = DB::table('roles')
    ->where('workspace_id', $workspaceId)
    ->where('role_key', 'owner')
    ->first();

if (!$ownerRole) {
    echo "❌ FATAL: Owner role not found.\n";
    exit(1);
}

$ownerPerms = json_decode($ownerRole->permissions, true) ?? [];
if (in_array('commissions.approve', $ownerPerms) && in_array('approvals.decide', $ownerPerms)) {
    pass("Owner role has commissions.approve + approvals.decide");
} else {
    fail("Owner role missing required permissions. Has: " . implode(', ', $ownerPerms));
}

// Find owner membership
$ownerMr = DB::table('membership_roles')
    ->where('workspace_id', $workspaceId)
    ->where('role_id', $ownerRole->id)
    ->first();

$ownerMembership = $ownerMr
    ? WorkspaceMembership::find($ownerMr->membership_id)
    : null;

if (!$ownerMembership) {
    echo "❌ FATAL: Owner membership not found.\n";
    exit(1);
}

// Find a different actor for step 2 (sales_manager with commissions.approve)
// If no different actor, we'll use owner for both (allow_self_approval is false,
// but the requester will be a sales_agent).
$agentRole = DB::table('roles')
    ->where('workspace_id', $workspaceId)
    ->where('role_key', 'sales_agent')
    ->first();

$agentMembership = null;
if ($agentRole) {
    $agentMr = DB::table('membership_roles')
        ->where('workspace_id', $workspaceId)
        ->where('role_id', $agentRole->id)
        ->first();
    if ($agentMr) {
        $agentMembership = WorkspaceMembership::find($agentMr->membership_id);
    }
}

// Find sales_manager for step 1
$mgrRole = DB::table('roles')
    ->where('workspace_id', $workspaceId)
    ->where('role_key', 'sales_manager')
    ->first();

$mgrMembership = null;
if ($mgrRole) {
    $mgrMr = DB::table('membership_roles')
        ->where('workspace_id', $workspaceId)
        ->where('role_id', $mgrRole->id)
        ->first();
    if ($mgrMr) {
        $mgrMembership = WorkspaceMembership::find($mgrMr->membership_id);
    }
}

// Determine who submits (requester) and who decides
// The requester should be someone who is NOT the approver (allow_self_approval=false)
$requester = $agentMembership ?? $mgrMembership ?? $ownerMembership;
$step1Approver = $mgrMembership ?? $ownerMembership;
$step2Approver = $ownerMembership;

// Ensure requester != step1Approver (self-approval check)
if ($requester->id === $step1Approver->id && $agentMembership) {
    $requester = $agentMembership;
}
// If we still can't avoid self-approval, we need to pick different actors
if ($requester->id === $step1Approver->id) {
    // Use owner as requester, manager as step1 approver
    if ($mgrMembership && $mgrMembership->id !== $ownerMembership->id) {
        $requester = $ownerMembership;
        $step1Approver = $mgrMembership;
    }
}

echo "  Requester: membership={$requester->id}\n";
echo "  Step 1 approver: membership={$step1Approver->id}\n";
echo "  Step 2 approver: membership={$step2Approver->id}\n";

if ($requester->id !== $step1Approver->id) {
    pass("Requester differs from step 1 approver (no self-approval conflict)");
} else {
    fail("Requester = step 1 approver — self-approval will be rejected");
}

echo "\n";

// ── 3. Trigger Evaluator Test ─────────────────────────────

echo "── TEST 3: Trigger Evaluator ──────────────────────\n\n";

$evaluator = app(ApprovalTriggerEvaluator::class);

// T3a: amount=750, currency=SAR → SHOULD trigger
$triggerResult = $evaluator->evaluate('commission_entry', $workspaceId, [
    'amount'   => 750,
    'currency' => 'SAR',
]);
if ($triggerResult !== null) {
    pass("amount=750, currency=SAR triggers workflow");
} else {
    fail("amount=750, currency=SAR did NOT trigger workflow");
}

// T3b: amount=200, currency=SAR → should NOT trigger (below threshold)
$noTrigger = $evaluator->evaluate('commission_entry', $workspaceId, [
    'amount'   => 200,
    'currency' => 'SAR',
]);
if ($noTrigger === null) {
    pass("amount=200, currency=SAR does NOT trigger (below threshold)");
} else {
    fail("amount=200 incorrectly triggered workflow");
}

// T3c: amount=750, currency=USD → should NOT trigger (wrong currency)
$noTriggerCur = $evaluator->evaluate('commission_entry', $workspaceId, [
    'amount'   => 750,
    'currency' => 'USD',
]);
if ($noTriggerCur === null) {
    pass("amount=750, currency=USD does NOT trigger (wrong currency)");
} else {
    fail("currency=USD incorrectly triggered workflow");
}

// T3d: amount=500, currency=SAR → SHOULD trigger (exact threshold)
$exactTrigger = $evaluator->evaluate('commission_entry', $workspaceId, [
    'amount'   => 500,
    'currency' => 'SAR',
]);
if ($exactTrigger !== null) {
    pass("amount=500 (exact threshold) triggers workflow");
} else {
    fail("amount=500 (exact threshold) did NOT trigger");
}

echo "\n";

// ── 4. Full Lifecycle: Submit → Approve Step 1 → Approve Step 2 ──

echo "── TEST 4: Full Approval Lifecycle ────────────────\n\n";

// Create a test CommissionEntry
// Grab a valid pipeline_record_id from existing data
$samplePr = DB::table('pipeline_records')
    ->where('workspace_id', $workspaceId)
    ->value('id');

if (!$samplePr) {
    echo "❌ FATAL: No pipeline_records exist in demo workspace.\n";
    exit(1);
}

$testEntryId = Str::uuid()->toString();
$testEntityIds[] = $testEntryId;

DB::table('commission_entries')->insert([
    'id'                        => $testEntryId,
    'workspace_id'              => $workspaceId,
    'pipeline_record_id'        => $samplePr,
    'recipient_membership_id'   => $requester->id,
    'commission_amount'         => 750.00,
    'base_amount'               => 10000.00,
    'currency'                  => 'SAR',
    'calculation_type'          => 'percentage',
    'percentage_rate'           => 7.50,
    'status'                    => 'pending',
    'created_at'                => now(),
    'updated_at'                => now(),
]);

$entry = CommissionEntry::find($testEntryId);
if ($entry && $entry->status === 'pending') {
    pass("Test CommissionEntry created (id={$testEntryId}, amount=750)");
} else {
    fail("Failed to create test CommissionEntry");
    goto cleanup;
}

// Submit approval request
$engine = app(ApprovalEngine::class);

try {
    $request = $engine->submit(
        $workspaceId,
        'commission_entry',
        $testEntryId,
        $requester,
        [
            'amount'   => 750.00,
            'currency' => 'SAR',
        ],
        ['trigger' => 'test', 'workflow_key' => 'high_commission_approval'],
    );

    pass("Approval request submitted (id={$request->id})");
    $testEntityIds[] = 'ar:' . $request->id;
} catch (\Exception $e) {
    fail("Submit threw: " . $e->getMessage());
    goto cleanup;
}

// Verify request state
if ($request->status === 'pending') {
    pass("Request status is 'pending'");
} else {
    fail("Request status is '{$request->status}', expected 'pending'");
}

if ($request->current_step_order === 1) {
    pass("Current step order is 1");
} else {
    fail("Current step order is {$request->current_step_order}, expected 1");
}

$requestSteps = $request->requestSteps;
if ($requestSteps->count() === 2) {
    pass("Request has 2 steps");
} else {
    fail("Request has {$requestSteps->count()} steps, expected 2");
}

// Decide step 1: approved by step1Approver
echo "\n  ── Step 1 Decision (Manager Review) ──\n\n";

try {
    $afterStep1 = $engine->decide(
        $request->id,
        $step1Approver,
        'approved',
        'Test: Manager approves high commission',
    );

    pass("Step 1 decided: approved");
} catch (\Exception $e) {
    fail("Step 1 decision threw: " . $e->getMessage());
    goto cleanup;
}

// After step 1, request should still be pending (waiting for step 2)
$afterStep1Fresh = $afterStep1->fresh();
if ($afterStep1Fresh->status === 'pending') {
    pass("Request still 'pending' after step 1 (more steps remain)");
} else {
    fail("Request status is '{$afterStep1Fresh->status}' after step 1, expected 'pending'");
}

if ($afterStep1Fresh->current_step_order === 2) {
    pass("Current step advanced to 2");
} else {
    fail("Current step is {$afterStep1Fresh->current_step_order}, expected 2");
}

// Verify step 1 request step is 'approved'
$step1ReqStep = $afterStep1->requestSteps->where('step_order', 1)->first();
if ($step1ReqStep && $step1ReqStep->status === 'approved') {
    pass("Request step 1 status = 'approved'");
} else {
    fail("Request step 1 status wrong");
}

// Verify decision record was created
$step1Decision = DB::table('approval_decisions')
    ->where('approval_request_id', $request->id)
    ->where('decision', 'approved')
    ->first();

if ($step1Decision) {
    pass("Decision record exists for step 1");
    $snapshot = json_decode($step1Decision->actor_snapshot, true);
    if (isset($snapshot['membership_id'])) {
        pass("Decision has actor_snapshot with membership_id");
    } else {
        fail("Decision actor_snapshot missing membership_id");
    }
} else {
    fail("No decision record found for step 1");
}

// Decide step 2: approved by step2Approver
echo "\n  ── Step 2 Decision (Finance Approval) ──\n\n";

try {
    $afterStep2 = $engine->decide(
        $request->id,
        $step2Approver,
        'approved',
        'Test: Finance approves',
    );

    pass("Step 2 decided: approved");
} catch (\Exception $e) {
    fail("Step 2 decision threw: " . $e->getMessage());
    goto cleanup;
}

// After step 2, request should be 'approved' (all steps done)
$afterStep2Fresh = $afterStep2->fresh();
if ($afterStep2Fresh->status === 'approved') {
    pass("Request status is 'approved' (all steps complete)");
} else {
    fail("Request status is '{$afterStep2Fresh->status}', expected 'approved'");
}

if ($afterStep2Fresh->resolved_at !== null) {
    pass("resolved_at is set");
} else {
    fail("resolved_at is null");
}

echo "\n";

// ── 5. Finalization: CommissionEntry status transition ─────

echo "── TEST 5: Finalization Side-Effects ──────────────\n\n";

$finalEntry = CommissionEntry::find($testEntryId);
if ($finalEntry->status === 'approved') {
    pass("CommissionEntry.status transitioned to 'approved'");
} else {
    fail("CommissionEntry.status is '{$finalEntry->status}', expected 'approved'");
}

if ($finalEntry->approved_at !== null) {
    pass("CommissionEntry.approved_at is set");
} else {
    fail("CommissionEntry.approved_at is null");
}

echo "\n";

// ── 6. Audit Trail Integrity ──────────────────────────────

echo "── TEST 6: Audit Trail ──────────────────────────\n\n";

$auditCreated = AuditLog::where('workspace_id', $workspaceId)
    ->where('entity_type', 'approval_request')
    ->where('entity_id', $request->id)
    ->where('action', 'approval_request.created')
    ->first();

if ($auditCreated) {
    pass("Audit: approval_request.created exists");
} else {
    fail("Audit: approval_request.created missing");
}

$auditApproved = AuditLog::where('workspace_id', $workspaceId)
    ->where('entity_type', 'approval_request')
    ->where('entity_id', $request->id)
    ->where('action', 'approval_request.approved')
    ->count();

if ($auditApproved >= 1) {
    pass("Audit: approval_request.approved exists ({$auditApproved} records)");
} else {
    fail("Audit: approval_request.approved missing");
}

$auditFinalized = AuditLog::where('workspace_id', $workspaceId)
    ->where('entity_type', 'commission_entry')
    ->where('entity_id', $testEntryId)
    ->where('action', 'commission_entry.approved_via_workflow')
    ->first();

if ($auditFinalized) {
    pass("Audit: commission_entry.approved_via_workflow exists");
    $newValues = $auditFinalized->new_values ?? [];
    if (isset($newValues['approval_request_id']) && $newValues['approval_request_id'] === $request->id) {
        pass("Audit: finalization links to correct approval_request_id");
    } else {
        fail("Audit: finalization approval_request_id mismatch");
    }
} else {
    fail("Audit: commission_entry.approved_via_workflow missing");
}

echo "\n";

// ── 7. Negative: Duplicate submission guard ───────────────

echo "── TEST 7: Guard Rails ──────────────────────────\n\n";

// T7a: Cannot submit duplicate approval for same entity
$testEntryId2 = Str::uuid()->toString();
$testEntityIds[] = $testEntryId2;

DB::table('commission_entries')->insert([
    'id'                        => $testEntryId2,
    'workspace_id'              => $workspaceId,
    'pipeline_record_id'        => $samplePr,
    'recipient_membership_id'   => $requester->id,
    'commission_amount'         => 600.00,
    'base_amount'               => 8000.00,
    'currency'                  => 'SAR',
    'calculation_type'          => 'percentage',
    'percentage_rate'           => 7.50,
    'status'                    => 'pending',
    'created_at'                => now(),
    'updated_at'                => now(),
]);

try {
    $req2 = $engine->submit(
        $workspaceId, 'commission_entry', $testEntryId2,
        $requester, ['amount' => 600], ['trigger' => 'test'],
    );
    $testEntityIds[] = 'ar:' . $req2->id;

    // Try duplicate
    try {
        $engine->submit(
            $workspaceId, 'commission_entry', $testEntryId2,
            $requester, ['amount' => 600], ['trigger' => 'test_dup'],
        );
        fail("Duplicate submission did NOT throw");
    } catch (\RuntimeException $e) {
        if (str_contains($e->getMessage(), 'pending approval request already exists')) {
            pass("Duplicate submission blocked: " . $e->getMessage());
        } else {
            pass("Duplicate submission blocked with: " . $e->getMessage());
        }
    }
} catch (\Exception $e) {
    fail("Setup for duplicate test failed: " . $e->getMessage());
}

// T7b: Cannot decide on non-pending request
try {
    $engine->decide($request->id, $step1Approver, 'approved', 'test');
    fail("Deciding on already-approved request did NOT throw");
} catch (\RuntimeException $e) {
    pass("Cannot decide on resolved request: " . $e->getMessage());
}

echo "\n";

// ── Cleanup ───────────────────────────────────────────────

cleanup:

echo "── CLEANUP ──────────────────────────────────────\n\n";

$cleanedAr = 0;
$cleanedCe = 0;

foreach ($testEntityIds as $id) {
    if (str_starts_with($id, 'ar:')) {
        $arId = substr($id, 3);
        DB::table('approval_decisions')->where('approval_request_id', $arId)->delete();
        DB::table('approval_request_steps')->where('approval_request_id', $arId)->delete();
        DB::table('approval_requests')->where('id', $arId)->delete();
        // Clean audit logs for this request
        DB::table('audit_logs')
            ->where('entity_type', 'approval_request')
            ->where('entity_id', $arId)
            ->delete();
        $cleanedAr++;
    } else {
        // Clean audit logs for commission entry
        DB::table('audit_logs')
            ->where('entity_type', 'commission_entry')
            ->where('entity_id', $id)
            ->delete();
        DB::table('commission_entries')->where('id', $id)->delete();
        $cleanedCe++;
    }
}

echo "  Cleaned: {$cleanedAr} approval requests, {$cleanedCe} commission entries\n\n";

// ── Summary ───────────────────────────────────────────────

echo "════════════════════════════════════════════════════\n";
echo "  RESULTS: {$passed} passed, {$failed} failed\n";
echo "════════════════════════════════════════════════════\n\n";

if ($failed > 0) {
    echo "❌ VERIFICATION FAILED — {$failed} test(s) need attention.\n";
    exit(1);
} else {
    echo "✅ ALL TESTS PASSED — Approval engine verified end-to-end.\n";
    exit(0);
}
