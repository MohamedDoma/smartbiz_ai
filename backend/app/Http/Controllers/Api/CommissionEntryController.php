<?php

namespace App\Http\Controllers\Api;

use App\Exceptions\NoMatchingApprovalWorkflowException;
use App\Http\Controllers\Controller;
use App\Models\ApprovalRequest;
use App\Models\CommissionEntry;
use App\Models\PipelineRecord;
use App\Models\WorkspaceMembership;
use App\Services\ApprovalEngine;
use App\Services\ApprovalTriggerEvaluator;
use App\Services\CommissionCalculationService;
use App\Services\CommissionEntryConditionSchemaProvider;
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

        $relations = [
            'plan:id,name',
            'pipelineRecord:id,title,value_amount,currency',
            'recipientMembership.user:id,full_name',
            'sourceMembership.user:id,full_name',
        ];

        $entry = CommissionEntry::where('workspace_id', $wsId)->findOrFail($id);

        // ── Already finalized (approved/paid/cancelled) → idempotent return ──
        if ($entry->status !== 'pending') {
            return response()->json([
                'data'              => $this->fmt($entry->load($relations)),
                'approval_required' => false,
            ]);
        }

        // ── Check for existing approval request ─────────────────────
        $engine = app(ApprovalEngine::class);
        $existing = $engine->latestRequest($wsId, 'commission_entry', $entry->id);

        // Already approved via workflow → return finalized commission
        if ($existing && $existing->status === 'approved') {
            // Ensure the commission reflects the finalized state
            $entry->refresh();
            return response()->json([
                'data'              => $this->fmt($entry->load($relations)),
                'approval_required' => false,
            ]);
        }

        // Already has a pending request → idempotent reuse (no duplicate)
        if ($existing && $existing->status === 'pending') {
            return response()->json([
                'data'                => $this->fmt($entry->load($relations)),
                'approval_required'   => true,
                'approval_request_id' => $existing->id,
            ]);
        }

        // ── Try to submit via ApprovalEngine ────────────────────────
        // The engine resolves matching workflows internally.
        // If no workflow exists, it throws — meaning no approval is needed
        // and the commission can be approved directly.
        $provider = app(CommissionEntryConditionSchemaProvider::class);
        $snapshot = array_merge($provider->evaluationData($entry), [
            'commission_entry_id' => $entry->id,
            'recipient_id'        => $entry->recipient_membership_id,
        ]);

        try {
            $approvalRequest = $engine->submit(
                $wsId,
                'commission_entry',
                $entry->id,
                $membership,
                $snapshot,
                ['trigger' => 'manual', 'action' => 'commission.approve'],
            );

            // Workflow matched → commission stays pending, return request info
            return response()->json([
                'data'                => $this->fmt($entry->load($relations)),
                'approval_required'   => true,
                'approval_request_id' => $approvalRequest->id,
            ], 201);

        } catch (NoMatchingApprovalWorkflowException) {
            // ── SAFE: No active workflow for commission_entry → direct approval allowed ──
            // This is the ONLY exception type that permits direct approval.
            // All other failures (DB errors, duplicate requests, workflow misconfiguration)
            // propagate as 500s — the commission stays pending.
            $entry->update(['status' => 'approved', 'approved_at' => now()]);
            return response()->json([
                'data'              => $this->fmt($entry->fresh()->load($relations)),
                'approval_required' => false,
            ]);
        }
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
        return response()->json(['data' => $this->fmt($entry->fresh()->load([
            'plan:id,name',
            'pipelineRecord:id,title,value_amount,currency',
            'recipientMembership.user:id,full_name',
            'sourceMembership.user:id,full_name',
        ]))]);
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
        return response()->json(['data' => $this->fmt($entry->fresh()->load([
            'plan:id,name',
            'pipelineRecord:id,title,value_amount,currency',
            'recipientMembership.user:id,full_name',
            'sourceMembership.user:id,full_name',
        ]))]);
    }

    /**
     * Apply visibility scope to commission entry queries.
     *
     * Uses the dedicated commission permission hierarchy:
     * - commissions.view_all → all workspace entries
     * - commissions.view_team → entries for recipients in same team
     * - commissions.view_own → only entries where the user is the recipient
     * - none of the above → 403
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

        // Level 3: view_own sees only own commissions
        if ($resolver->can($membership, 'commissions.view_own')) {
            $query->where('recipient_membership_id', $membership->id);
            return;
        }

        // No valid scope permission → return empty result (no rows match impossible ID)
        $query->whereRaw('1 = 0');
    }

    /**
     * Auto-submit an approval request if the commission entry triggers
     * the workflow's configured conditions.
     *
     * Uses the ApprovalTriggerEvaluator to determine whether the entity
     * data meets the workflow's trigger_conditions (canonical JSON format).
     * If so, submits the request through the ApprovalEngine.
     *
     * Entity data is extracted via CommissionEntryConditionSchemaProvider::evaluationData()
     * — the SINGLE SOURCE OF TRUTH for field mapping. This ensures the runtime
     * evaluation data and the catalog schema can never drift.
     */
    private function autoSubmitApprovalIfRequired(
        string $workspaceId,
        CommissionEntry $entry,
        ?WorkspaceMembership $requester,
    ): ?ApprovalRequest {
        if (!$requester) {
            return null;
        }

        // Build entity data for condition evaluation via the shared provider.
        // This is the ONLY place entity data mapping should happen — never
        // hand-build the array here or in markApproved.
        $provider = app(CommissionEntryConditionSchemaProvider::class);
        $entityData = $provider->evaluationData($entry);

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

        // Build snapshot for audit trail: shared evaluation data + audit-only fields
        $snapshot = array_merge($entityData, [
            'commission_entry_id' => $entry->id,
            'recipient_id'        => $entry->recipient_membership_id,
        ]);

        try {
            return $engine->submit(
                $workspaceId,
                'commission_entry',
                $entry->id,
                $requester,
                $snapshot,
                ['trigger' => 'auto', 'workflow_key' => $workflow->workflow_key],
            );
        } catch (NoMatchingApprovalWorkflowException) {
            // Workflow was deleted between evaluator check and submit — skip
            return null;
        } catch (\RuntimeException) {
            // Workflow has no active steps or duplicate request — gracefully skip
            return null;
        }
    }

    private function fmt(CommissionEntry $e): array
    {
        // Determine if there's a pending approval request for this entry.
        // This allows the frontend to show workflow-pending state and hide
        // the direct approve button when a workflow is active.
        $approvalStatus = null;
        if ($e->status === 'pending') {
            $pendingApproval = ApprovalRequest::where('workspace_id', $e->workspace_id)
                ->where('entity_type', 'commission_entry')
                ->where('entity_id', $e->id)
                ->where('status', 'pending')
                ->first();

            $approvalStatus = $pendingApproval
                ? 'workflow_pending'
                : null;
        }

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
            'approval_status'         => $approvalStatus,
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
