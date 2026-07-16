<?php

namespace Tests\Feature;

use App\Exceptions\NoMatchingApprovalWorkflowException;
use App\Models\ApprovalRequest;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\CommissionEntry;
use App\Models\Pipeline;
use App\Models\PipelineRecord;
use App\Models\PipelineStage;
use App\Services\ApprovalEngine;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;

/**
 * Database-backed integration tests for the Commission × Approval workflow.
 *
 * Covers the full lifecycle:
 *  - Direct approval when no workflow exists
 *  - Workflow submission when an active workflow matches
 *  - Approval decision and CommissionEntry finalization
 *  - Rejection decision and CommissionEntry cancellation
 *  - Idempotent re-submission guards
 *  - NoMatchingApprovalWorkflowException type-safety
 *
 * All tests run against the live PostgreSQL database using the seeded
 * admin user from FoundationSeeder. Data inserted by tests is cleaned up
 * in tearDown to avoid side effects.
 */
class CommissionApprovalApiTest extends SmartBizTestCase
{
    // ── Test-scoped data to clean up ────────────────────────────
    private array $cleanUpIds = [];

    // ── Pipeline infrastructure (created once per test) ─────────
    private string $pipelineId;
    private string $stageId;

    /** Fixed pipeline name used by every test in this class. */
    private const PIPELINE_NAME = 'Test Pipeline (CommissionApprovalApiTest)';

    /** Prefix used by createTestWorkflow() for workflow_key values. */
    private const WORKFLOW_KEY_PREFIX = 'test_commission_approval_';

    protected function setUp(): void
    {
        parent::setUp();

        // ── Defensive cleanup of stale data from interrupted prior runs ──
        // The pipelines table has UNIQUE(workspace_id, name). If a previous
        // run leaked a record with PIPELINE_NAME, a new insert with a
        // different UUID would fail or (with insertOrIgnore) silently no-op,
        // leaving $this->pipelineId pointing to a non-existent row and
        // causing FK violations on pipeline_stages.
        $stalePipeline = DB::table('pipelines')
            ->where('workspace_id', $this->workspaceId)
            ->where('name', self::PIPELINE_NAME)
            ->first();

        if ($stalePipeline) {
            DB::table('pipeline_stages')
                ->where('pipeline_id', $stalePipeline->id)
                ->delete();
            DB::table('pipelines')
                ->where('id', $stalePipeline->id)
                ->delete();
        }

        // Purge any leaked approval workflows from a prior interrupted run.
        // Only targets records whose workflow_key starts with the test prefix.
        $staleWorkflowIds = DB::table('approval_workflows')
            ->where('workspace_id', $this->workspaceId)
            ->where('workflow_key', 'like', self::WORKFLOW_KEY_PREFIX . '%')
            ->pluck('id');

        if ($staleWorkflowIds->isNotEmpty()) {
            DB::table('approval_decisions')
                ->whereIn('approval_request_id', function ($q) use ($staleWorkflowIds) {
                    $q->select('id')->from('approval_requests')
                      ->whereIn('workflow_id', $staleWorkflowIds);
                })->delete();
            DB::table('approval_request_steps')
                ->whereIn('approval_request_id', function ($q) use ($staleWorkflowIds) {
                    $q->select('id')->from('approval_requests')
                      ->whereIn('workflow_id', $staleWorkflowIds);
                })->delete();
            DB::table('approval_requests')
                ->whereIn('workflow_id', $staleWorkflowIds)->delete();
            DB::table('approval_workflow_steps')
                ->whereIn('workflow_id', $staleWorkflowIds)->delete();
            DB::table('approval_workflows')
                ->whereIn('id', $staleWorkflowIds)->delete();
        }

        // Create a minimal pipeline + stage for PipelineRecord FK references
        $this->pipelineId = (string) \Illuminate\Support\Str::uuid();
        $this->stageId    = (string) \Illuminate\Support\Str::uuid();

        DB::table('pipelines')->insert([
            'id'           => $this->pipelineId,
            'workspace_id' => $this->workspaceId,
            'pipeline_key' => 'test_deals_' . substr($this->pipelineId, 0, 8),
            'name'         => self::PIPELINE_NAME,
            'entity_type'  => 'deals',
            'is_active'    => true,
            'sort_order'   => 0,
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);

        DB::table('pipeline_stages')->insert([
            'id'           => $this->stageId,
            'workspace_id' => $this->workspaceId,
            'pipeline_id'  => $this->pipelineId,
            'stage_key'    => 'won',
            'name'         => 'Won',
            'status_type'  => 'won',
            'sort_order'   => 1,
            'is_active'    => true,
            'created_at'   => now(),
            'updated_at'   => now(),
        ]);
    }

    protected function tearDown(): void
    {
        // Clean up test data in reverse-dependency order
        if (!empty($this->cleanUpIds['approval_decisions'])) {
            DB::table('approval_decisions')->whereIn('id', $this->cleanUpIds['approval_decisions'])->delete();
        }
        if (!empty($this->cleanUpIds['approval_request_steps'])) {
            DB::table('approval_request_steps')->whereIn('id', $this->cleanUpIds['approval_request_steps'])->delete();
        }
        if (!empty($this->cleanUpIds['approval_requests'])) {
            DB::table('approval_requests')->whereIn('id', $this->cleanUpIds['approval_requests'])->delete();
        }
        if (!empty($this->cleanUpIds['approval_workflow_steps'])) {
            DB::table('approval_workflow_steps')->whereIn('id', $this->cleanUpIds['approval_workflow_steps'])->delete();
        }
        if (!empty($this->cleanUpIds['approval_workflows'])) {
            DB::table('approval_workflows')->whereIn('id', $this->cleanUpIds['approval_workflows'])->delete();
        }
        if (!empty($this->cleanUpIds['commission_entries'])) {
            DB::table('commission_entries')->whereIn('id', $this->cleanUpIds['commission_entries'])->delete();
        }
        if (!empty($this->cleanUpIds['pipeline_records'])) {
            DB::table('pipeline_records')->whereIn('id', $this->cleanUpIds['pipeline_records'])->delete();
        }
        if (!empty($this->cleanUpIds['audit_logs'])) {
            DB::table('audit_logs')->whereIn('id', $this->cleanUpIds['audit_logs'])->delete();
        }

        // Clean up pipeline infrastructure
        DB::table('pipeline_stages')->where('id', $this->stageId)->delete();
        DB::table('pipelines')->where('id', $this->pipelineId)->delete();

        parent::tearDown();
    }

    // ═══════════════════════════════════════════════════════════
    //  1. Direct Approval — No Workflow Configured
    // ═══════════════════════════════════════════════════════════

    public function test_mark_approved_directly_when_no_workflow_exists(): void
    {
        // Ensure no approval workflow exists for commission_entry in this workspace
        DB::table('approval_workflows')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'commission_entry')
            ->where('is_active', true)
            ->update(['is_active' => false]);

        $entry = $this->createTestCommissionEntry();

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");

        $response->assertOk();
        $data = $response->json();

        $this->assertFalse($data['approval_required'], 'Should not require approval when no workflow exists.');
        $this->assertEquals('approved', $data['data']['status']);
        $this->assertNotNull($data['data']['approved_at']);

        // Verify in DB
        $entry->refresh();
        $this->assertEquals('approved', $entry->status);
        $this->assertNotNull($entry->approved_at);

        // Restore workflows
        DB::table('approval_workflows')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'commission_entry')
            ->update(['is_active' => true]);
    }

    // ═══════════════════════════════════════════════════════════
    //  2. Workflow Submission — Active Workflow Exists
    // ═══════════════════════════════════════════════════════════

    public function test_mark_approved_submits_to_workflow_when_active(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id);

        $entry = $this->createTestCommissionEntry();

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");

        $response->assertStatus(201);
        $data = $response->json();

        $this->assertTrue($data['approval_required'], 'Should require approval when workflow is active.');
        $this->assertNotEmpty($data['approval_request_id']);

        // Verify the approval request was created in DB
        $approvalRequest = ApprovalRequest::find($data['approval_request_id']);
        $this->assertNotNull($approvalRequest);
        $this->assertEquals('pending', $approvalRequest->status);
        $this->assertEquals('commission_entry', $approvalRequest->entity_type);
        $this->assertEquals($entry->id, $approvalRequest->entity_id);
        $this->assertEquals($workflow->id, $approvalRequest->workflow_id);

        // Commission stays pending
        $entry->refresh();
        $this->assertEquals('pending', $entry->status);

        // Track for cleanup
        $this->trackApprovalRequest($approvalRequest);
    }

    // ═══════════════════════════════════════════════════════════
    //  3. Idempotent Re-submission Guard
    // ═══════════════════════════════════════════════════════════

    public function test_mark_approved_idempotent_when_pending_request_exists(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id);

        $entry = $this->createTestCommissionEntry();

        // First call: creates the approval request
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Second call: should reuse existing pending request (idempotent)
        $r2 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r2->assertOk();
        $this->assertTrue($r2->json('approval_required'));
        $this->assertEquals($requestId, $r2->json('approval_request_id'),
            'Should return the same approval request ID on re-submission.');

        // Verify no duplicate was created
        $count = ApprovalRequest::where('entity_type', 'commission_entry')
            ->where('entity_id', $entry->id)
            ->where('status', 'pending')
            ->count();
        $this->assertEquals(1, $count, 'Should have exactly one pending approval request.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  4. Full Approval Lifecycle — Engine Approve → Commission Approved
    // ═══════════════════════════════════════════════════════════

    public function test_approval_decision_finalizes_commission_to_approved(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Approve via the approvals endpoint
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
            'notes'    => 'Integration test approval',
        ]);
        $r2->assertOk();
        $this->assertEquals('approved', $r2->json('data.status'));

        // Verify CommissionEntry was finalized
        $entry->refresh();
        $this->assertEquals('approved', $entry->status,
            'Commission entry should be approved after workflow approval.');
        $this->assertNotNull($entry->approved_at);

        // Verify audit log was created
        $auditExists = DB::table('audit_logs')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'commission_entry')
            ->where('entity_id', $entry->id)
            ->where('action', 'commission_entry.approved_via_workflow')
            ->exists();
        $this->assertTrue($auditExists, 'Finalization audit log should exist.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  5. Full Rejection Lifecycle — Engine Reject → Commission Cancelled
    // ═══════════════════════════════════════════════════════════

    public function test_rejection_decision_finalizes_commission_to_cancelled(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Reject via the approvals endpoint
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'rejected',
            'notes'    => 'Commission amount too high',
        ]);
        $r2->assertOk();
        $this->assertEquals('rejected', $r2->json('data.status'));

        // Verify rejected_at_step is present in the response
        $this->assertNotNull($r2->json('data.rejected_at_step'),
            'Response should include rejected_at_step for rejected requests.');

        // Verify CommissionEntry was cancelled
        $entry->refresh();
        $this->assertEquals('cancelled', $entry->status,
            'Commission entry should be cancelled after workflow rejection.');
        $this->assertStringContainsString('Rejected via approval workflow', $entry->notes);

        // Verify rejection audit log
        $auditExists = DB::table('audit_logs')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'commission_entry')
            ->where('entity_id', $entry->id)
            ->where('action', 'commission_entry.rejected_via_workflow')
            ->exists();
        $this->assertTrue($auditExists, 'Rejection audit log should exist.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  5b. Rejection Without Notes — Validation Error
    // ═══════════════════════════════════════════════════════════

    public function test_rejection_without_notes_returns_validation_error(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Attempt to reject without providing notes
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'rejected',
        ]);
        $r2->assertStatus(422);
        $r2->assertJsonValidationErrors(['notes']);

        // Verify request is still pending (not rejected)
        $request = ApprovalRequest::find($requestId);
        $this->assertEquals('pending', $request->status,
            'Request should remain pending when rejection notes are missing.');

        $this->trackApprovalRequest($request);
    }

    // ═══════════════════════════════════════════════════════════
    //  5c. Rejection With Whitespace-Only Notes — Validation Error
    // ═══════════════════════════════════════════════════════════

    public function test_rejection_with_whitespace_notes_returns_validation_error(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Attempt to reject with whitespace-only notes
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'rejected',
            'notes'    => '   ',
        ]);
        $r2->assertStatus(422);
        $r2->assertJsonValidationErrors(['notes']);

        // Verify request is still pending
        $request = ApprovalRequest::find($requestId);
        $this->assertEquals('pending', $request->status,
            'Request should remain pending when rejection notes are only whitespace.');

        $this->trackApprovalRequest($request);
    }

    // ═══════════════════════════════════════════════════════════
    //  5d. Approval Without Notes — Still Succeeds
    // ═══════════════════════════════════════════════════════════

    public function test_approval_without_notes_still_succeeds(): void
    {
        $workflow = $this->createTestWorkflow();
        $step     = $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Approve without notes — should succeed (notes are optional for approval)
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
        ]);
        $r2->assertOk();
        $this->assertEquals('approved', $r2->json('data.status'));

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  6. Already-Approved Commission → Idempotent Return
    // ═══════════════════════════════════════════════════════════

    public function test_mark_approved_returns_idempotently_for_approved_entry(): void
    {
        $entry = $this->createTestCommissionEntry(['status' => 'approved', 'approved_at' => now()]);

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");

        $response->assertOk();
        $data = $response->json();

        $this->assertFalse($data['approval_required']);
        $this->assertEquals('approved', $data['data']['status']);
    }

    // ═══════════════════════════════════════════════════════════
    //  7. NoMatchingApprovalWorkflowException — Type-Safety
    // ═══════════════════════════════════════════════════════════

    public function test_approval_engine_throws_typed_exception_for_no_workflow(): void
    {
        // Ensure no active workflows exist for a test entity type
        $engine = app(ApprovalEngine::class);
        $membership = \App\Models\WorkspaceMembership::find(FoundationSeeder::MEMBERSHIP_ID);

        $this->expectException(NoMatchingApprovalWorkflowException::class);

        $engine->submit(
            $this->workspaceId,
            'nonexistent_entity_type',
            'fake-entity-id',
            $membership,
        );
    }

    public function test_no_matching_workflow_exception_carries_context(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('invoice', 'ws-test-123');

        $this->assertEquals('invoice', $exception->entityType);
        $this->assertEquals('ws-test-123', $exception->workspaceId);
        $this->assertStringContainsString('invoice', $exception->getMessage());
        $this->assertStringContainsString('ws-test-123', $exception->getMessage());
    }

    public function test_no_matching_workflow_exception_is_runtime_exception(): void
    {
        $exception = new NoMatchingApprovalWorkflowException('test', 'ws-1');

        // It extends RuntimeException so that old catch blocks that haven't
        // been updated yet still catch it — but new code should catch the specific type.
        $this->assertInstanceOf(\RuntimeException::class, $exception);
    }

    // ═══════════════════════════════════════════════════════════
    //  8. Commission Lifecycle Guards
    // ═══════════════════════════════════════════════════════════

    public function test_cannot_pay_cancelled_commission(): void
    {
        $entry = $this->createTestCommissionEntry(['status' => 'cancelled']);

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/mark-paid");
        $response->assertStatus(409);
    }

    public function test_cannot_cancel_paid_commission(): void
    {
        $entry = $this->createTestCommissionEntry(['status' => 'paid', 'paid_at' => now()]);

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/cancel");
        $response->assertStatus(409);
    }

    public function test_approved_commission_can_be_paid(): void
    {
        $entry = $this->createTestCommissionEntry(['status' => 'approved', 'approved_at' => now()]);

        $response = $this->wsPost("/api/commission-entries/{$entry->id}/mark-paid");
        $response->assertOk();

        $entry->refresh();
        $this->assertEquals('paid', $entry->status);
        $this->assertNotNull($entry->paid_at);
    }

    // ═══════════════════════════════════════════════════════════
    //  9. Multi-Step Workflow
    // ═══════════════════════════════════════════════════════════

    public function test_multi_step_workflow_advances_through_steps(): void
    {
        $workflow = $this->createTestWorkflow();

        // Step 1: Manager approval
        $step1 = $this->createTestWorkflowStep($workflow->id, [
            'name'                    => 'Manager Approval',
            'step_order'              => 1,
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        // Step 2: Finance approval
        $step2 = $this->createTestWorkflowStep($workflow->id, [
            'name'                    => 'Finance Approval',
            'step_order'              => 2,
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Approve step 1
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
            'notes'    => 'Step 1 OK',
        ]);
        $r2->assertOk();

        // Request should still be pending (step 2 remaining)
        $request = ApprovalRequest::find($requestId);
        $this->assertEquals('pending', $request->status);
        $this->assertEquals(2, $request->current_step_order);

        // Commission should still be pending
        $entry->refresh();
        $this->assertEquals('pending', $entry->status);

        // Approve step 2
        $r3 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
            'notes'    => 'Step 2 OK — all clear',
        ]);
        $r3->assertOk();

        // Now the request should be approved
        $request->refresh();
        $this->assertEquals('approved', $request->status);

        // Commission should now be finalized
        $entry->refresh();
        $this->assertEquals('approved', $entry->status);
        $this->assertNotNull($entry->approved_at);

        $this->trackApprovalRequest($request);
    }

    // ═══════════════════════════════════════════════════════════
    //  Helper: Create test data
    // ═══════════════════════════════════════════════════════════

    /**
     * Create a test CommissionEntry linked to the seeded workspace and membership.
     */
    private function createTestCommissionEntry(array $overrides = []): CommissionEntry
    {
        // Create a PipelineRecord to satisfy the FK
        $record = PipelineRecord::create([
            'workspace_id'           => $this->workspaceId,
            'pipeline_id'            => $this->pipelineId,
            'stage_id'               => $this->stageId,
            'title'                  => 'Test Deal (CommissionApprovalApiTest)',
            'value_amount'           => 10000.00,
            'currency'               => 'USD',
            'status'                 => 'won',
            'assigned_membership_id' => FoundationSeeder::MEMBERSHIP_ID,
        ]);
        $this->cleanUpIds['pipeline_records'][] = $record->id;

        $defaults = [
            'workspace_id'             => $this->workspaceId,
            'pipeline_record_id'       => $record->id,
            'recipient_membership_id'  => FoundationSeeder::MEMBERSHIP_ID,
            'base_amount'              => 10000.00,
            'commission_amount'        => 1000.00,
            'currency'                 => 'USD',
            'calculation_type'         => 'percentage',
            'percentage_rate'          => 10.0000,
            'status'                   => 'pending',
            'calculated_at'            => now(),
        ];

        $entry = CommissionEntry::create(array_merge($defaults, $overrides));
        $this->cleanUpIds['commission_entries'][] = $entry->id;

        return $entry;
    }

    /**
     * Create an active approval workflow for commission_entry in the test workspace.
     */
    private function createTestWorkflow(): ApprovalWorkflow
    {
        $workflow = ApprovalWorkflow::create([
            'workspace_id'       => $this->workspaceId,
            'workflow_key'       => 'test_commission_approval_' . uniqid(),
            'name'               => 'Test Commission Approval Workflow',
            'entity_type'        => 'commission_entry',
            'trigger_conditions' => [],
            'is_active'          => true,
            'sort_order'         => 1,
            'created_by'         => FoundationSeeder::MEMBERSHIP_ID,
        ]);
        $this->cleanUpIds['approval_workflows'][] = $workflow->id;

        return $workflow;
    }

    /**
     * Create an active workflow step for a given workflow.
     */
    private function createTestWorkflowStep(string $workflowId, array $overrides = []): ApprovalWorkflowStep
    {
        $defaults = [
            'workspace_id'            => $this->workspaceId,
            'workflow_id'             => $workflowId,
            'name'                    => 'Approval Step',
            'step_order'              => 1,
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
            'is_active'               => true,
        ];

        $step = ApprovalWorkflowStep::create(array_merge($defaults, $overrides));
        $this->cleanUpIds['approval_workflow_steps'][] = $step->id;

        return $step;
    }

    /**
     * Track an approval request and its child records for cleanup.
     */
    private function trackApprovalRequest(ApprovalRequest $request): void
    {
        $this->cleanUpIds['approval_requests'][] = $request->id;

        // Track request steps
        $stepIds = DB::table('approval_request_steps')
            ->where('approval_request_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['approval_request_steps'] = array_merge(
            $this->cleanUpIds['approval_request_steps'] ?? [],
            $stepIds,
        );

        // Track decisions
        $decisionIds = DB::table('approval_decisions')
            ->where('approval_request_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['approval_decisions'] = array_merge(
            $this->cleanUpIds['approval_decisions'] ?? [],
            $decisionIds,
        );

        // Track audit logs
        $auditIds = DB::table('audit_logs')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'approval_request')
            ->where('entity_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['audit_logs'] = array_merge(
            $this->cleanUpIds['audit_logs'] ?? [],
            $auditIds,
        );

        // Also track commission_entry finalization audit logs
        if ($request->entity_type === 'commission_entry') {
            $commissionAuditIds = DB::table('audit_logs')
                ->where('workspace_id', $this->workspaceId)
                ->where('entity_type', 'commission_entry')
                ->where('entity_id', $request->entity_id)
                ->pluck('id')->toArray();
            $this->cleanUpIds['audit_logs'] = array_merge(
                $this->cleanUpIds['audit_logs'] ?? [],
                $commissionAuditIds,
            );
        }
    }
}
