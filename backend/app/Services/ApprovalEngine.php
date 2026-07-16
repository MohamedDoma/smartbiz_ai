<?php

namespace App\Services;

use App\Exceptions\NoMatchingApprovalWorkflowException;
use App\Models\ApprovalDecision;
use App\Models\ApprovalRequest;
use App\Models\ApprovalRequestStep;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\AuditLog;
use App\Models\WorkspaceMembership;
use Illuminate\Support\Facades\DB;

/**
 * ApprovalEngine — Universal, permission-driven approval workflow engine.
 *
 * Design principles:
 *  - Zero hardcoded role names or business-type logic
 *  - Approver resolution is 100% configuration-driven (permission keys, manager hierarchy, or specific memberships)
 *  - All decisions are immutable and audited
 *  - Workspace-isolated
 *
 * Usage:
 *  $engine = app(ApprovalEngine::class);
 *  $request = $engine->submit($workspaceId, 'commission_entry', $entityId, $requesterMembership, $entitySnapshot);
 *  $engine->decide($request->id, $actorMembership, 'approved', 'Looks good');
 */
class ApprovalEngine
{
    public function __construct(
        private readonly PermissionResolver $permissionResolver,
        private readonly ApprovalFinalizationService $finalizationService,
    ) {}

    // ═══════════════════════════════════════════════════════════
    //  Submit a new approval request
    // ═══════════════════════════════════════════════════════════

    /**
     * Create a new approval request for an entity.
     *
     * Resolves the matching workflow, creates request steps mirroring the
     * workflow's active steps, and returns the new request.
     *
     * @param string $workspaceId
     * @param string $entityType      e.g. "commission_entry", "invoice"
     * @param string $entityId        UUID of the record being approved
     * @param WorkspaceMembership $requester  The membership submitting the request
     * @param array  $entitySnapshot  Snapshot of entity data for audit
     * @param array  $metadata        Optional additional context
     *
     * @throws NoMatchingApprovalWorkflowException if no active workflow matches the entity type
     * @throws \RuntimeException if the workflow has no active steps or a duplicate pending request exists
     */
    public function submit(
        string $workspaceId,
        string $entityType,
        string $entityId,
        WorkspaceMembership $requester,
        array $entitySnapshot = [],
        array $metadata = [],
    ): ApprovalRequest {
        return DB::transaction(function () use ($workspaceId, $entityType, $entityId, $requester, $entitySnapshot, $metadata) {
            // Find the matching workflow
            $workflow = ApprovalWorkflow::where('workspace_id', $workspaceId)
                ->forEntity($entityType)
                ->active()
                ->orderBy('sort_order')
                ->first();

            if (!$workflow) {
                throw new NoMatchingApprovalWorkflowException($entityType, $workspaceId);
            }

            // Get active steps
            $steps = $workflow->activeSteps()->get();

            if ($steps->isEmpty()) {
                throw new \RuntimeException("Approval workflow '{$workflow->name}' has no active steps.");
            }

            // Check for existing pending request for the same entity
            $existingPending = ApprovalRequest::where('workspace_id', $workspaceId)
                ->where('entity_type', $entityType)
                ->where('entity_id', $entityId)
                ->where('status', 'pending')
                ->exists();

            if ($existingPending) {
                throw new \RuntimeException("A pending approval request already exists for this entity.");
            }

            // Create the request
            $request = ApprovalRequest::create([
                'workspace_id'             => $workspaceId,
                'workflow_id'              => $workflow->id,
                'entity_type'              => $entityType,
                'entity_id'                => $entityId,
                'requester_membership_id'  => $requester->id,
                'status'                   => 'pending',
                'current_step_order'       => $steps->first()->step_order,
                'entity_snapshot'          => $entitySnapshot,
                'metadata'                 => $metadata,
            ]);

            // Create request steps for each active workflow step
            foreach ($steps as $step) {
                ApprovalRequestStep::create([
                    'workspace_id'        => $workspaceId,
                    'approval_request_id' => $request->id,
                    'workflow_step_id'    => $step->id,
                    'step_order'          => $step->step_order,
                    'status'              => 'pending',
                ]);
            }

            // Audit log
            $this->audit($workspaceId, $requester->user_id, 'approval_request.created', 'approval_request', $request->id, null, [
                'entity_type' => $entityType,
                'entity_id'   => $entityId,
                'workflow'    => $workflow->workflow_key,
            ]);

            return $request->load('requestSteps');
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  Make a decision on an approval request
    // ═══════════════════════════════════════════════════════════

    /**
     * Approve or reject the current step of an approval request.
     *
     * @param string $requestId
     * @param WorkspaceMembership $actor  The membership making the decision
     * @param string $decision           'approved' or 'rejected'
     * @param string|null $notes
     *
     * @throws \RuntimeException on invalid state or unauthorized actor
     */
    public function decide(
        string $requestId,
        WorkspaceMembership $actor,
        string $decision,
        ?string $notes = null,
    ): ApprovalRequest {
        if (!in_array($decision, ['approved', 'rejected'], true)) {
            throw new \InvalidArgumentException("Decision must be 'approved' or 'rejected'.");
        }

        return DB::transaction(function () use ($requestId, $actor, $decision, $notes) {
            $request = ApprovalRequest::where('workspace_id', $actor->workspace_id)
                ->lockForUpdate()
                ->findOrFail($requestId);

            if (!$request->isPending()) {
                throw new \RuntimeException("Cannot decide on a request with status '{$request->status}'.");
            }

            // Get the current active step
            $currentStep = $request->currentRequestStep();
            if (!$currentStep) {
                throw new \RuntimeException("No pending step found at order {$request->current_step_order}.");
            }

            // Load the workflow step definition
            $workflowStep = $currentStep->workflowStep;

            // Validate actor is authorized for this step
            $this->validateActorAuthorization($workflowStep, $actor, $request);

            // Build actor snapshot for audit
            $actorSnapshot = $this->buildActorSnapshot($actor);

            // Record the decision (immutable)
            ApprovalDecision::create([
                'workspace_id'               => $actor->workspace_id,
                'approval_request_id'        => $request->id,
                'approval_request_step_id'   => $currentStep->id,
                'actor_membership_id'        => $actor->id,
                'decision'                   => $decision,
                'notes'                      => $notes,
                'actor_snapshot'             => $actorSnapshot,
            ]);

            // Update the step
            $currentStep->update([
                'status'                    => $decision,
                'decided_by_membership_id'  => $actor->id,
                'decision_notes'            => $notes,
                'decided_at'                => now(),
            ]);

            // Process the outcome
            if ($decision === 'rejected') {
                // Rejection at any step rejects the entire request
                $request->update([
                    'status'      => 'rejected',
                    'final_notes' => $notes,
                    'resolved_at' => now(),
                ]);

                // Mark remaining pending steps as skipped
                $request->requestSteps()
                    ->where('status', 'pending')
                    ->update(['status' => 'skipped']);

                // Execute domain-specific rejection action
                $this->finalizationService->finalize($request->fresh());

            } else {
                // Approved — check if there are more steps
                $nextStep = $request->requestSteps()
                    ->where('step_order', '>', $currentStep->step_order)
                    ->where('status', 'pending')
                    ->orderBy('step_order')
                    ->first();

                if ($nextStep) {
                    // Advance to next step
                    $request->update([
                        'current_step_order' => $nextStep->step_order,
                    ]);
                } else {
                    // All steps approved — mark request as approved
                    $request->update([
                        'status'      => 'approved',
                        'final_notes' => $notes,
                        'resolved_at' => now(),
                    ]);

                    // Execute domain-specific final action
                    $this->finalizationService->finalize($request->fresh());
                }
            }

            // Audit log
            $this->audit(
                $actor->workspace_id,
                $actor->user_id,
                "approval_request.{$decision}",
                'approval_request',
                $request->id,
                ['status' => 'pending'],
                [
                    'status'    => $request->fresh()->status,
                    'decision'  => $decision,
                    'step'      => $workflowStep->name,
                    'step_order' => $currentStep->step_order,
                ],
            );

            return $request->fresh()->load(['requestSteps', 'decisions']);
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  Cancel an approval request
    // ═══════════════════════════════════════════════════════════

    /**
     * Cancel a pending approval request.
     *
     * Only the requester or someone with approvals.manage permission can cancel.
     */
    public function cancel(
        string $requestId,
        WorkspaceMembership $actor,
        ?string $reason = null,
    ): ApprovalRequest {
        return DB::transaction(function () use ($requestId, $actor, $reason) {
            $request = ApprovalRequest::where('workspace_id', $actor->workspace_id)
                ->lockForUpdate()
                ->findOrFail($requestId);

            if (!$request->isPending()) {
                throw new \RuntimeException("Cannot cancel a request with status '{$request->status}'.");
            }

            // Only requester or someone with approvals.manage can cancel
            $isRequester = $request->requester_membership_id === $actor->id;
            $canManage = $this->permissionResolver->can($actor, 'approvals.manage');

            if (!$isRequester && !$canManage) {
                throw new \RuntimeException("Only the requester or an approvals manager can cancel this request.");
            }

            $request->update([
                'status'      => 'cancelled',
                'final_notes' => $reason,
                'resolved_at' => now(),
            ]);

            // Mark remaining pending steps as skipped
            $request->requestSteps()
                ->where('status', 'pending')
                ->update(['status' => 'skipped']);

            $this->audit(
                $actor->workspace_id,
                $actor->user_id,
                'approval_request.cancelled',
                'approval_request',
                $request->id,
                null,
                ['reason' => $reason],
            );

            return $request->fresh()->load('requestSteps');
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  Query helpers
    // ═══════════════════════════════════════════════════════════

    /**
     * Check if an actor can decide on the current step of an approval request.
     *
     * This is the non-throwing counterpart to validateActorAuthorization().
     * Used by the controller to compute the `can_decide` capability flag
     * without relying on exception control flow in the API response layer.
     *
     * Returns false for non-pending requests or when no current step exists.
     */
    public function canActorDecide(ApprovalRequest $request, WorkspaceMembership $actor): bool
    {
        if (!$request->isPending()) {
            return false;
        }

        $currentStep = $request->currentRequestStep();
        if (!$currentStep) {
            return false;
        }

        $workflowStep = ApprovalWorkflowStep::find($currentStep->workflow_step_id);
        if (!$workflowStep) {
            return false;
        }

        try {
            $this->validateActorAuthorization($workflowStep, $actor, $request);
            return true;
        } catch (\RuntimeException) {
            return false;
        }
    }

    /**
     * Get pending approval requests where the actor can decide on the current step.
     *
     * This is the "Inbox" query — returns requests awaiting the actor's decision.
     */
    public function pendingForActor(string $workspaceId, WorkspaceMembership $actor): \Illuminate\Support\Collection
    {
        $pendingRequests = ApprovalRequest::where('workspace_id', $workspaceId)
            ->where('status', 'pending')
            ->with([
                'workflow:id,name,workflow_key,entity_type',
                'requesterMembership.user:id,full_name',
                'requestSteps',
            ])
            ->get();

        return $pendingRequests->filter(function (ApprovalRequest $request) use ($actor) {
            return $this->canActorDecide($request, $actor);
        })->values();
    }

    /**
     * Check if an entity has a pending approval request.
     */
    public function hasPendingRequest(string $workspaceId, string $entityType, string $entityId): bool
    {
        return ApprovalRequest::where('workspace_id', $workspaceId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->where('status', 'pending')
            ->exists();
    }

    /**
     * Get the latest approval request for an entity.
     */
    public function latestRequest(string $workspaceId, string $entityType, string $entityId): ?ApprovalRequest
    {
        return ApprovalRequest::where('workspace_id', $workspaceId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $entityId)
            ->orderByDesc('created_at')
            ->first();
    }

    // ═══════════════════════════════════════════════════════════
    //  Internal helpers
    // ═══════════════════════════════════════════════════════════

    /**
     * Validate that the actor is authorized to decide on the given workflow step.
     *
     * Resolution is 100% configuration-driven — no hardcoded role names.
     */
    private function validateActorAuthorization(
        ApprovalWorkflowStep $step,
        WorkspaceMembership $actor,
        ApprovalRequest $request,
    ): void {
        // Self-approval check
        if (!$step->allow_self_approval && $request->requester_membership_id === $actor->id) {
            throw new \RuntimeException("Self-approval is not allowed for this step.");
        }

        switch ($step->approver_type) {
            case 'permission':
                // Actor must hold the specified permission key
                if (!$step->approver_permission_key) {
                    throw new \RuntimeException("Workflow step '{$step->name}' has approver_type='permission' but no permission key configured.");
                }

                if (!$this->permissionResolver->can($actor, $step->approver_permission_key)) {
                    throw new \RuntimeException("You do not have the required permission '{$step->approver_permission_key}' to approve this step.");
                }
                break;

            case 'requester_manager':
                // Actor must be the requester's direct manager
                $requester = WorkspaceMembership::find($request->requester_membership_id);
                if (!$requester || $requester->manager_membership_id !== $actor->id) {
                    throw new \RuntimeException("Only the requester's direct manager can approve this step.");
                }
                break;

            case 'specific_membership':
                // Actor must be the specific membership configured in the step
                if ($step->approver_membership_id !== $actor->id) {
                    throw new \RuntimeException("Only the designated approver can approve this step.");
                }
                break;

            default:
                throw new \RuntimeException("Unknown approver_type: '{$step->approver_type}'.");
        }
    }

    /**
     * Build a snapshot of the actor at decision time for audit purposes.
     */
    private function buildActorSnapshot(WorkspaceMembership $actor): array
    {
        $actor->load(['user:id,full_name,email', 'membershipRoles.role:id,name,role_key']);

        $roles = $actor->membershipRoles->map(function ($mr) {
            return [
                'role_id'  => $mr->role?->id,
                'name'     => $mr->role?->name,
                'role_key' => $mr->role?->role_key,
            ];
        })->toArray();

        return [
            'membership_id' => $actor->id,
            'user_id'       => $actor->user_id,
            'full_name'     => $actor->user?->full_name,
            'email'         => $actor->user?->email,
            'department_id' => $actor->department_id,
            'team_id'       => $actor->team_id,
            'roles'         => $roles,
            'snapshot_at'   => now()->toIso8601String(),
        ];
    }

    /**
     * Write an audit log entry.
     */
    private function audit(
        string $workspaceId,
        ?string $userId,
        string $action,
        string $entityType,
        string $entityId,
        ?array $oldValues,
        ?array $newValues,
    ): void {
        AuditLog::create([
            'workspace_id' => $workspaceId,
            'user_id'      => $userId,
            'action'       => $action,
            'entity_type'  => $entityType,
            'entity_id'    => $entityId,
            'old_values'   => $oldValues,
            'new_values'   => $newValues,
        ]);
    }
}
