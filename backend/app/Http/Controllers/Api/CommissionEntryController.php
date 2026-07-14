<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ApprovalRequest;
use App\Models\ApprovalWorkflow;
use App\Models\CommissionEntry;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;
use App\Services\ApprovalEngine;
use App\Services\ApprovalTriggerEvaluator;
use App\Services\CommissionCalculationService;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommissionEntryController extends Controller
{
    /**
     * List commission entries with permission-based visibility.
     *
     * Requires commissions.list.
     * Visibility scope:
     *  - commissions.view_all → sees all workspace commissions
     *  - commissions.view_team → sees commissions for team members (by recipient)
     *  - otherwise → sees only own commissions (where recipient = current membership)
     */
    public function index(Request $request): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.list');

        $q = CommissionEntry::where('workspace_id', $wsId)
            ->with([
                'plan:id,name',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
                'sourceMembership.user:id,full_name',
            ])
            ->orderByDesc('calculated_at');

        // ── Visibility scope ─────────────────────────────────
        if ($membership) {
            $this->applyVisibilityScope($q, $membership);
        }

        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }
        if ($request->filled('recipient_membership_id')) {
            $q->where('recipient_membership_id', $request->input('recipient_membership_id'));
        }
        if ($request->filled('pipeline_record_id')) {
            $q->where('pipeline_record_id', $request->input('pipeline_record_id'));
        }

        return response()->json(['data' => $q->get()->map(fn ($e) => $this->fmt($e))]);
    }

    public function show(string $id): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.list');

        $q = CommissionEntry::where('workspace_id', $wsId)
            ->with([
                'plan:id,name', 'rule',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
                'sourceMembership.user:id,full_name',
            ]);

        // ── Visibility scope ─────────────────────────────────
        if ($membership) {
            $this->applyVisibilityScope($q, $membership);
        }

        $entry = $q->findOrFail($id);

        return response()->json(['data' => $this->fmt($entry)]);
    }

    public function calculateForRecord(Request $request, string $recordId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.calculate');

        $record = PipelineRecord::where('workspace_id', $wsId);
        if ($membership) {
            \App\Services\PipelineRecordScope::apply($record, $membership);
        }
        $record = $record->findOrFail($recordId);

        $service = app(CommissionCalculationService::class);
        $entries = $service->calculateForRecord($record);

        // ── Auto-submit approval requests for high-value commissions ──
        $approvalResults = [];
        foreach ($entries as $e) {
            $submitted = $this->autoSubmitApprovalIfRequired($wsId, $e, $membership);
            if ($submitted) {
                $approvalResults[] = $submitted;
            }

            $e->load([
                'plan:id,name',
                'pipelineRecord:id,title,value_amount,currency',
                'recipientMembership.user:id,full_name',
            ]);
        }

        return response()->json([
            'data' => [
                'created_count'   => count($entries),
                'entries'         => array_map(fn ($e) => $this->fmt($e), $entries),
                'approval_count'  => count($approvalResults),
            ],
        ], 201);
    }

    public function markApproved(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.approve');

        $entry = CommissionEntry::where('workspace_id', $wsId)->findOrFail($id);

        if ($entry->status !== 'pending') {
            return response()->json(['message' => "Cannot approve entry with status '{$entry->status}'."], 409);
        }

        // If an approval workflow request exists, it must be resolved first
        $activeApproval = ApprovalRequest::where('workspace_id', $wsId)
            ->where('entity_type', 'commission_entry')
            ->where('entity_id', $entry->id)
            ->where('status', 'pending')
            ->first();

        if ($activeApproval) {
            return response()->json([
                'message' => 'This commission entry has a pending approval request. It must be approved through the approval workflow first.',
                'approval_request_id' => $activeApproval->id,
            ], 409);
        }

        $entry->update(['status' => 'approved', 'approved_at' => now()]);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    public function markPaid(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.pay');

        $entry = CommissionEntry::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if (!in_array($entry->status, ['pending', 'approved'], true)) {
            return response()->json(['message' => "Cannot mark paid entry with status '{$entry->status}'."], 409);
        }

        $entry->update(['status' => 'paid', 'paid_at' => now()]);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    public function cancel(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.cancel');

        $entry = CommissionEntry::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        if ($entry->status === 'paid') {
            return response()->json(['message' => 'Cannot cancel a paid commission entry.'], 409);
        }

        $entry->update(['status' => 'cancelled']);
        return response()->json(['data' => $this->fmt($entry->fresh())]);
    }

    /**
     * Apply visibility scope to commission entry queries.
     *
     * Uses the dedicated commission permission hierarchy:
     * - commissions.view_all → all workspace entries
     * - commissions.view_team → entries for recipients in same team
     * - otherwise → only entries where the user is the recipient
     */
    private function applyVisibilityScope($query, WorkspaceMembership $membership): void
    {
        $resolver = app(PermissionResolver::class);

        // Level 1: view_all sees everything
        if ($resolver->can($membership, 'commissions.view_all')) {
            return;
        }

        // Level 2: view_team sees team members' commissions
        if ($resolver->can($membership, 'commissions.view_team')
            && $membership->team_id !== null) {
            $teamId = $membership->team_id;
            $wsId   = $membership->workspace_id;

            $query->where(function ($q) use ($membership, $teamId, $wsId) {
                $q->where('recipient_membership_id', $membership->id)
                  ->orWhereIn('recipient_membership_id', function ($sub) use ($teamId, $wsId) {
                      $sub->select('id')
                          ->from('workspace_memberships')
                          ->where('workspace_id', $wsId)
                          ->where('team_id', $teamId)
                          ->where('status', 'active');
                  });
            });
            return;
        }

        // Level 3: own commissions only
        $query->where('recipient_membership_id', $membership->id);
    }

    /**
     * Auto-submit an approval request if the commission entry triggers
     * the workflow's configured conditions.
     *
     * Uses the ApprovalTriggerEvaluator to determine whether the entity
     * data meets the workflow's trigger_conditions (canonical JSON format).
     * If so, submits the request through the ApprovalEngine.
     *
     * Entity data uses generic field names matching the workflow conditions:
     *  - 'amount'   maps to commission_amount (canonical condition field)
     *  - 'currency' maps to currency
     */
    private function autoSubmitApprovalIfRequired(
        string $workspaceId,
        CommissionEntry $entry,
        ?WorkspaceMembership $requester,
    ): ?ApprovalRequest {
        if (!$requester) {
            return null;
        }

        // Build entity data for condition evaluation.
        // Field names must match the workflow trigger_conditions field values.
        // The canonical condition uses "amount" (not "commission_amount").
        $entityData = [
            'amount'            => (float) $entry->commission_amount,
            'base_amount'       => (float) $entry->base_amount,
            'currency'          => $entry->currency,
            'calculation_type'  => $entry->calculation_type,
            'percentage_rate'   => $entry->percentage_rate,
        ];

        // Let the evaluator determine if a workflow triggers
        $evaluator = app(ApprovalTriggerEvaluator::class);
        $workflow = $evaluator->evaluate('commission_entry', $workspaceId, $entityData);

        if (!$workflow) {
            return null;
        }

        // Check if approval request already exists for this entry
        $engine = app(ApprovalEngine::class);
        if ($engine->hasPendingRequest($workspaceId, 'commission_entry', $entry->id)) {
            return null;
        }

        // Build snapshot for audit trail (full entity context)
        $snapshot = [
            'commission_entry_id' => $entry->id,
            'amount'              => $entry->commission_amount,
            'base_amount'         => $entry->base_amount,
            'currency'            => $entry->currency,
            'calculation_type'    => $entry->calculation_type,
            'percentage_rate'     => $entry->percentage_rate,
            'recipient_id'        => $entry->recipient_membership_id,
        ];

        try {
            return $engine->submit(
                $workspaceId,
                'commission_entry',
                $entry->id,
                $requester,
                $snapshot,
                ['trigger' => 'auto', 'workflow_key' => $workflow->workflow_key],
            );
        } catch (\RuntimeException) {
            // Workflow might not have active steps — gracefully skip
            return null;
        }
    }

    private function fmt(CommissionEntry $e): array
    {
        return [
            'id'                      => $e->id,
            'commission_plan_id'      => $e->commission_plan_id,
            'plan'                    => $e->relationLoaded('plan') && $e->plan
                ? ['id' => $e->plan->id, 'name' => $e->plan->name] : null,
            'commission_rule_id'      => $e->commission_rule_id,
            'pipeline_record_id'      => $e->pipeline_record_id,
            'record'                  => $e->relationLoaded('pipelineRecord') && $e->pipelineRecord
                ? ['id' => $e->pipelineRecord->id, 'title' => $e->pipelineRecord->title,
                   'value_amount' => $e->pipelineRecord->value_amount, 'currency' => $e->pipelineRecord->currency]
                : null,
            'recipient_membership_id' => $e->recipient_membership_id,
            'recipient'               => $e->relationLoaded('recipientMembership') && $e->recipientMembership
                ? ['membership_id' => $e->recipient_membership_id,
                   'full_name' => $e->recipientMembership->user?->full_name]
                : null,
            'source_membership_id'    => $e->source_membership_id,
            'source'                  => $e->relationLoaded('sourceMembership') && $e->sourceMembership
                ? ['membership_id' => $e->source_membership_id,
                   'full_name' => $e->sourceMembership->user?->full_name]
                : null,
            'base_amount'             => $e->base_amount,
            'commission_amount'       => $e->commission_amount,
            'currency'                => $e->currency,
            'calculation_type'        => $e->calculation_type,
            'percentage_rate'         => $e->percentage_rate,
            'fixed_amount'            => $e->fixed_amount,
            'status'                  => $e->status,
            'calculated_at'           => $e->calculated_at?->toIso8601String(),
            'approved_at'             => $e->approved_at?->toIso8601String(),
            'paid_at'                 => $e->paid_at?->toIso8601String(),
            'notes'                   => $e->notes,
            'created_at'              => $e->created_at?->toIso8601String(),
        ];
    }

    /**
     * Require a specific permission via the PermissionResolver.
     *
     * Super-admins are always allowed. Regular users must have an active
     * membership with the requested permission key.
     */
    private function requirePermission(?WorkspaceMembership $membership, string $permissionKey): void
    {
        // Super-admin bypass
        $user = request()->user();
        if ($user && $user->is_super_admin) {
            return;
        }

        if (!$membership) {
            abort(403, 'Not a workspace member.');
        }

        $resolver = app(PermissionResolver::class);
        if (!$resolver->can($membership, $permissionKey)) {
            abort(403, 'Insufficient permissions.');
        }
    }
}
