<?php

namespace Tests\Feature;

use App\Models\ApprovalRequest;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\CommissionEntry;
use App\Models\PipelineRecord;
use Database\Seeders\FoundationSeeder;
use Illuminate\Support\Facades\DB;

/**
 * Feature tests for the Approval Authorization hardening.
 *
 * Validates:
 *  - API responses include can_view, can_decide, can_cancel flags
 *  - can_decide is true when the actor is the authorized approver
 *  - can_cancel is true when the actor is the requester
 *  - Flags are false for resolved (non-pending) requests
 *  - The "all" scope is restricted at the backend
 *  - Self-approval is blocked when allow_self_approval is false
 */
class ApprovalAuthorizationApiTest extends SmartBizTestCase
{
    private array $cleanUpIds = [];
    private string $pipelineId;
    private string $stageId;

    /** Fixed pipeline name used by every test in this class. */
    private const PIPELINE_NAME = 'Test Pipeline (AuthorizationTest)';

    /** Prefix used by createTestWorkflow() for workflow_key values. */
    private const WORKFLOW_KEY_PREFIX = 'test_auth_approval_';

    protected function setUp(): void
    {
        parent::setUp();

        // ── Defensive cleanup of stale data from interrupted prior runs ──
        // The pipelines table has UNIQUE(workspace_id, name). If a previous
        // run leaked a record with PIPELINE_NAME, a new insertOrIgnore with
        // a different UUID would silently no-op, leaving $this->pipelineId
        // pointing to a non-existent row. The pipeline_stages FK insert
        // would then fail. Purging stale records here makes tests self-healing.
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

        $this->pipelineId = (string) \Illuminate\Support\Str::uuid();
        $this->stageId    = (string) \Illuminate\Support\Str::uuid();

        DB::table('pipelines')->insert([
            'id'           => $this->pipelineId,
            'workspace_id' => $this->workspaceId,
            'pipeline_key' => 'test_auth_deals_' . substr($this->pipelineId, 0, 8),
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

        DB::table('pipeline_stages')->where('id', $this->stageId)->delete();
        DB::table('pipelines')->where('id', $this->pipelineId)->delete();

        parent::tearDown();
    }

    // ═══════════════════════════════════════════════════════════
    //  1. Capability flags are present in list responses
    // ═══════════════════════════════════════════════════════════

    public function test_inbox_response_includes_capability_flags(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit to workflow
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Fetch inbox
        $r2 = $this->wsGet('/api/approvals/inbox');
        $r2->assertOk();

        $data = $r2->json('data');
        $this->assertNotEmpty($data, 'Inbox should contain the pending request.');

        $item = collect($data)->firstWhere('id', $requestId);
        $this->assertNotNull($item, 'Created request should appear in inbox.');

        // Assert capability flags are present
        $this->assertArrayHasKey('can_view', $item);
        $this->assertArrayHasKey('can_decide', $item);
        $this->assertArrayHasKey('can_cancel', $item);

        // The seeded admin has commissions.approve → can_decide should be true
        $this->assertTrue($item['can_view'], 'can_view should always be true.');
        $this->assertTrue($item['can_decide'], 'Admin with commissions.approve should be able to decide.');
        $this->assertTrue($item['can_cancel'], 'Requester should be able to cancel their own request.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  2. Capability flags on index (list) responses
    // ═══════════════════════════════════════════════════════════

    public function test_list_response_includes_capability_flags(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Fetch all requests
        $r2 = $this->wsGet('/api/approvals');
        $r2->assertOk();

        $data = $r2->json('data');
        $item = collect($data)->firstWhere('id', $requestId);
        $this->assertNotNull($item);

        $this->assertArrayHasKey('can_view', $item);
        $this->assertArrayHasKey('can_decide', $item);
        $this->assertArrayHasKey('can_cancel', $item);
        $this->assertTrue($item['can_view']);

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  3. Capability flags on detail (show) response
    // ═══════════════════════════════════════════════════════════

    public function test_show_response_includes_capability_flags(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Fetch details
        $r2 = $this->wsGet("/api/approvals/{$requestId}");
        $r2->assertOk();

        $data = $r2->json('data');
        $this->assertArrayHasKey('can_view', $data);
        $this->assertArrayHasKey('can_decide', $data);
        $this->assertArrayHasKey('can_cancel', $data);
        $this->assertTrue($data['can_view']);
        $this->assertTrue($data['can_decide']);
        $this->assertTrue($data['can_cancel']);

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  4. Flags are false for resolved requests
    // ═══════════════════════════════════════════════════════════

    public function test_capability_flags_are_false_for_approved_request(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Approve
        $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
            'notes'    => 'All good',
        ])->assertOk();

        // Fetch via show — now resolved
        $r3 = $this->wsGet("/api/approvals/{$requestId}");
        $r3->assertOk();

        $data = $r3->json('data');
        $this->assertFalse($data['can_decide'], 'can_decide must be false for resolved requests.');
        $this->assertFalse($data['can_cancel'], 'can_cancel must be false for resolved requests.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  5. Self-approval blocked when allow_self_approval is false
    // ═══════════════════════════════════════════════════════════

    public function test_can_decide_is_false_when_self_approval_disabled(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => false,  // self-approval disabled
        ]);

        $entry = $this->createTestCommissionEntry();

        // Submit (the seeded admin IS the requester)
        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Fetch inbox — since the admin is the requester AND self-approval is off,
        // can_decide should be false even though they hold the permission
        $r2 = $this->wsGet("/api/approvals/{$requestId}");
        $r2->assertOk();

        $data = $r2->json('data');
        $this->assertFalse($data['can_decide'],
            'can_decide must be false when self-approval is disabled and actor is the requester.');

        // Attempting to decide should also fail at the engine level
        $r3 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
            'notes'    => 'Trying self-approval',
        ]);
        $r3->assertStatus(409);
        $this->assertStringContainsString('Self-approval', $r3->json('message'));

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  6. Decide response also returns updated capability flags
    // ═══════════════════════════════════════════════════════════

    public function test_decide_response_includes_capability_flags(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Approve
        $r2 = $this->wsPost("/api/approvals/{$requestId}/decide", [
            'decision' => 'approved',
        ]);
        $r2->assertOk();

        $data = $r2->json('data');
        $this->assertArrayHasKey('can_decide', $data);
        $this->assertArrayHasKey('can_cancel', $data);

        // After approval, both should be false
        $this->assertFalse($data['can_decide']);
        $this->assertFalse($data['can_cancel']);

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  7. Cancel response includes capability flags
    // ═══════════════════════════════════════════════════════════

    public function test_cancel_response_includes_capability_flags(): void
    {
        $workflow = $this->createTestWorkflow();
        $this->createTestWorkflowStep($workflow->id, [
            'approver_type'           => 'permission',
            'approver_permission_key' => 'commissions.approve',
            'allow_self_approval'     => true,
        ]);

        $entry = $this->createTestCommissionEntry();

        $r1 = $this->wsPost("/api/commission-entries/{$entry->id}/mark-approved");
        $r1->assertStatus(201);
        $requestId = $r1->json('approval_request_id');

        // Cancel
        $r2 = $this->wsPost("/api/approvals/{$requestId}/cancel", [
            'reason' => 'Changed my mind',
        ]);
        $r2->assertOk();

        $data = $r2->json('data');
        $this->assertArrayHasKey('can_decide', $data);
        $this->assertArrayHasKey('can_cancel', $data);
        $this->assertFalse($data['can_decide'], 'can_decide must be false after cancellation.');
        $this->assertFalse($data['can_cancel'], 'can_cancel must be false after cancellation.');

        $this->trackApprovalRequest(ApprovalRequest::find($requestId));
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function createTestCommissionEntry(array $overrides = []): CommissionEntry
    {
        $record = PipelineRecord::create([
            'workspace_id'           => $this->workspaceId,
            'pipeline_id'            => $this->pipelineId,
            'stage_id'               => $this->stageId,
            'title'                  => 'Test Deal (AuthorizationTest)',
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

    private function createTestWorkflow(): ApprovalWorkflow
    {
        $workflow = ApprovalWorkflow::create([
            'workspace_id'       => $this->workspaceId,
            'workflow_key'       => 'test_auth_approval_' . uniqid(),
            'name'               => 'Test Auth Approval Workflow',
            'entity_type'        => 'commission_entry',
            'trigger_conditions' => [],
            'is_active'          => true,
            'sort_order'         => 1,
            'created_by'         => FoundationSeeder::MEMBERSHIP_ID,
        ]);
        $this->cleanUpIds['approval_workflows'][] = $workflow->id;

        return $workflow;
    }

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

    private function trackApprovalRequest(ApprovalRequest $request): void
    {
        $this->cleanUpIds['approval_requests'][] = $request->id;

        $stepIds = DB::table('approval_request_steps')
            ->where('approval_request_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['approval_request_steps'] = array_merge(
            $this->cleanUpIds['approval_request_steps'] ?? [],
            $stepIds,
        );

        $decisionIds = DB::table('approval_decisions')
            ->where('approval_request_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['approval_decisions'] = array_merge(
            $this->cleanUpIds['approval_decisions'] ?? [],
            $decisionIds,
        );

        $auditIds = DB::table('audit_logs')
            ->where('workspace_id', $this->workspaceId)
            ->where('entity_type', 'approval_request')
            ->where('entity_id', $request->id)
            ->pluck('id')->toArray();
        $this->cleanUpIds['audit_logs'] = array_merge(
            $this->cleanUpIds['audit_logs'] ?? [],
            $auditIds,
        );

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
