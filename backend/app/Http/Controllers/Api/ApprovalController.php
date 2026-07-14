<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ApprovalRequest;
use App\Models\WorkspaceMembership;
use App\Services\ApprovalEngine;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ApprovalController — API for approval request lifecycle.
 *
 * Endpoints:
 *  GET    /approvals           — List requests (inbox, my-requests, all)
 *  GET    /approvals/{id}      — Show request details
 *  POST   /approvals           — Submit a new approval request
 *  POST   /approvals/{id}/decide  — Approve or reject
 *  POST   /approvals/{id}/cancel  — Cancel a pending request
 *  GET    /approvals/inbox     — Pending requests awaiting actor's decision
 */
class ApprovalController extends Controller
{
    public function __construct(
        private readonly ApprovalEngine $engine,
        private readonly WorkspaceContextManager $ctx,
        private readonly PermissionResolver $resolver,
    ) {}

    /**
     * List approval requests.
     *
     * Query params:
     *  - scope: 'inbox' | 'my_requests' | 'all' (default: 'all')
     *  - status: 'pending' | 'approved' | 'rejected' | 'cancelled'
     *  - entity_type: filter by entity type
     *
     * Requires: approvals.list
     */
    public function index(Request $request): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.list');

        $wsId = $this->ctx->workspaceId();
        $scope = $request->input('scope', 'all');

        if ($scope === 'inbox') {
            // Use engine's pending-for-actor query
            $results = $this->engine->pendingForActor($wsId, $membership);
            return response()->json([
                'data' => $results->map(fn ($r) => $this->fmt($r))->values()->toArray(),
            ]);
        }

        $q = ApprovalRequest::where('workspace_id', $wsId)
            ->with([
                'workflow:id,name,workflow_key,entity_type',
                'requesterMembership.user:id,full_name',
                'requestSteps',
            ])
            ->orderByDesc('created_at');

        // Scope filter
        if ($scope === 'my_requests') {
            $q->where('requester_membership_id', $membership->id);
        }

        // Status filter
        if ($request->filled('status')) {
            $q->where('status', $request->input('status'));
        }

        // Entity type filter
        if ($request->filled('entity_type')) {
            $q->where('entity_type', $request->input('entity_type'));
        }

        return response()->json([
            'data' => $q->get()->map(fn ($r) => $this->fmt($r))->toArray(),
        ]);
    }

    /**
     * Show a single approval request with full details.
     *
     * Requires: approvals.show
     */
    public function show(string $id): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.show');

        $request = ApprovalRequest::where('workspace_id', $this->ctx->workspaceId())
            ->with([
                'workflow:id,name,workflow_key,entity_type',
                'workflow.steps',
                'requesterMembership.user:id,full_name,email',
                'requestSteps.workflowStep:id,name,step_order,approver_type,approver_permission_key',
                'requestSteps.decidedByMembership.user:id,full_name',
                'decisions.actorMembership.user:id,full_name',
            ])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmtDetailed($request)]);
    }

    /**
     * Submit a new approval request.
     *
     * Body: { entity_type, entity_id, entity_snapshot?, metadata? }
     *
     * Requires: approvals.request
     */
    public function store(Request $request): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.request');

        $request->validate([
            'entity_type'     => 'required|string|max:100',
            'entity_id'       => 'required|uuid',
            'entity_snapshot' => 'nullable|array',
            'metadata'        => 'nullable|array',
        ]);

        try {
            $approvalRequest = $this->engine->submit(
                $this->ctx->workspaceId(),
                $request->input('entity_type'),
                $request->input('entity_id'),
                $membership,
                $request->input('entity_snapshot', []),
                $request->input('metadata', []),
            );

            return response()->json([
                'data' => $this->fmtDetailed($approvalRequest->load([
                    'workflow:id,name,workflow_key,entity_type',
                    'requesterMembership.user:id,full_name',
                    'requestSteps',
                ])),
            ], 201);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        }
    }

    /**
     * Approve or reject the current step of an approval request.
     *
     * Body: { decision: 'approved'|'rejected', notes? }
     *
     * Requires: approvals.decide
     */
    public function decide(Request $request, string $id): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.decide');

        $request->validate([
            'decision' => 'required|in:approved,rejected',
            'notes'    => 'nullable|string|max:2000',
        ]);

        try {
            $approvalRequest = $this->engine->decide(
                $id,
                $membership,
                $request->input('decision'),
                $request->input('notes'),
            );

            return response()->json([
                'data' => $this->fmtDetailed($approvalRequest->load([
                    'workflow:id,name,workflow_key,entity_type',
                    'requesterMembership.user:id,full_name',
                    'requestSteps.workflowStep:id,name,step_order,approver_type,approver_permission_key',
                    'requestSteps.decidedByMembership.user:id,full_name',
                    'decisions.actorMembership.user:id,full_name',
                ])),
            ]);
        } catch (\RuntimeException | \InvalidArgumentException $e) {
            $code = $e instanceof \InvalidArgumentException ? 422 : 409;
            return response()->json(['message' => $e->getMessage()], $code);
        }
    }

    /**
     * Cancel a pending approval request.
     *
     * Requires: approvals.cancel (own) or approvals.manage (any)
     */
    public function cancel(Request $request, string $id): JsonResponse
    {
        $membership = $this->ctx->membership();

        // approvals.cancel for own, approvals.manage for others (engine validates)
        $canCancel = $this->resolver->can($membership, 'approvals.cancel');
        $canManage = $this->resolver->can($membership, 'approvals.manage');
        if (!$canCancel && !$canManage) {
            abort(403, 'Insufficient permissions.');
        }

        $request->validate([
            'reason' => 'nullable|string|max:2000',
        ]);

        try {
            $approvalRequest = $this->engine->cancel(
                $id,
                $membership,
                $request->input('reason'),
            );

            return response()->json(['data' => $this->fmt($approvalRequest)]);
        } catch (\RuntimeException $e) {
            return response()->json(['message' => $e->getMessage()], 409);
        }
    }

    /**
     * Get inbox: pending requests awaiting the actor's decision.
     *
     * Requires: approvals.list
     */
    public function inbox(): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.list');

        $results = $this->engine->pendingForActor(
            $this->ctx->workspaceId(),
            $membership,
        );

        return response()->json([
            'data' => $results->map(fn ($r) => $this->fmt($r))->values()->toArray(),
        ]);
    }

    // ── Formatters ─────────────────────────────────────────────

    private function fmt(ApprovalRequest $r): array
    {
        return [
            'id'                       => $r->id,
            'workflow_id'              => $r->workflow_id,
            'workflow'                 => $r->relationLoaded('workflow') && $r->workflow
                ? [
                    'id'            => $r->workflow->id,
                    'name'          => $r->workflow->name,
                    'workflow_key'  => $r->workflow->workflow_key,
                    'entity_type'   => $r->workflow->entity_type,
                ] : null,
            'entity_type'              => $r->entity_type,
            'entity_id'                => $r->entity_id,
            'requester_membership_id'  => $r->requester_membership_id,
            'requester'                => $r->relationLoaded('requesterMembership') && $r->requesterMembership
                ? [
                    'membership_id' => $r->requester_membership_id,
                    'full_name'     => $r->requesterMembership->user?->full_name,
                ] : null,
            'status'                   => $r->status,
            'current_step_order'       => $r->current_step_order,
            'final_notes'              => $r->final_notes,
            'resolved_at'              => $r->resolved_at?->toIso8601String(),
            'created_at'               => $r->created_at?->toIso8601String(),
            'updated_at'               => $r->updated_at?->toIso8601String(),
            'steps_count'              => $r->relationLoaded('requestSteps') ? $r->requestSteps->count() : null,
            'completed_steps'          => $r->relationLoaded('requestSteps')
                ? $r->requestSteps->whereIn('status', ['approved', 'rejected', 'skipped'])->count()
                : null,
        ];
    }

    private function fmtDetailed(ApprovalRequest $r): array
    {
        $base = $this->fmt($r);

        $base['entity_snapshot'] = $r->entity_snapshot;
        $base['metadata'] = $r->metadata;

        // Request steps with workflow step info
        $base['steps'] = $r->relationLoaded('requestSteps')
            ? $r->requestSteps->map(function ($step) {
                return [
                    'id'                       => $step->id,
                    'workflow_step_id'         => $step->workflow_step_id,
                    'step_name'                => $step->relationLoaded('workflowStep') && $step->workflowStep
                        ? $step->workflowStep->name : null,
                    'step_order'               => $step->step_order,
                    'approver_type'            => $step->relationLoaded('workflowStep') && $step->workflowStep
                        ? $step->workflowStep->approver_type : null,
                    'approver_permission_key'  => $step->relationLoaded('workflowStep') && $step->workflowStep
                        ? $step->workflowStep->approver_permission_key : null,
                    'status'                   => $step->status,
                    'decided_by'               => $step->relationLoaded('decidedByMembership') && $step->decidedByMembership
                        ? [
                            'membership_id' => $step->decided_by_membership_id,
                            'full_name'     => $step->decidedByMembership->user?->full_name,
                        ] : null,
                    'decision_notes'           => $step->decision_notes,
                    'decided_at'               => $step->decided_at?->toIso8601String(),
                ];
            })->toArray()
            : [];

        // Audit trail
        $base['decisions'] = $r->relationLoaded('decisions')
            ? $r->decisions->map(function ($d) {
                return [
                    'id'              => $d->id,
                    'step_id'         => $d->approval_request_step_id,
                    'actor'           => $d->relationLoaded('actorMembership') && $d->actorMembership
                        ? [
                            'membership_id' => $d->actor_membership_id,
                            'full_name'     => $d->actorMembership->user?->full_name,
                        ] : null,
                    'decision'        => $d->decision,
                    'notes'           => $d->notes,
                    'actor_snapshot'  => $d->actor_snapshot,
                    'created_at'      => $d->created_at?->toIso8601String(),
                ];
            })->toArray()
            : [];

        return $base;
    }

    // ── Permission helper ──────────────────────────────────────

    private function requirePermission(?WorkspaceMembership $membership, string $permissionKey): void
    {
        $user = request()->user();
        if ($user && $user->is_super_admin) {
            return;
        }

        if (!$membership) {
            abort(403, 'Not a workspace member.');
        }

        if (!$this->resolver->can($membership, $permissionKey)) {
            abort(403, 'Insufficient permissions.');
        }
    }
}
