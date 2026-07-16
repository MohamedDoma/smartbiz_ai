<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ApprovalWorkflow;
use App\Models\ApprovalWorkflowStep;
use App\Models\WorkspaceMembership;
use App\Services\PermissionCatalog;
use App\Services\PermissionResolver;
use App\Services\TriggerConditionValidator;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * ApprovalWorkflowController — CRUD for approval workflow definitions.
 *
 * All endpoints require approvals.manage permission.
 * Workflows and their steps are managed as a unit.
 */
class ApprovalWorkflowController extends Controller
{
    public function __construct(
        private readonly WorkspaceContextManager $ctx,
        private readonly PermissionResolver $resolver,
        private readonly TriggerConditionValidator $conditionValidator,
    ) {}

    /**
     * List all approval workflows for the workspace.
     */
    public function index(Request $request): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $q = ApprovalWorkflow::where('workspace_id', $this->ctx->workspaceId())
            ->with('steps')
            ->orderBy('sort_order');

        if ($request->filled('entity_type')) {
            $q->where('entity_type', $request->input('entity_type'));
        }

        if ($request->filled('is_active')) {
            $q->where('is_active', filter_var($request->input('is_active'), FILTER_VALIDATE_BOOLEAN));
        }

        return response()->json([
            'data' => $q->get()->map(fn ($w) => $this->fmt($w))->toArray(),
        ]);
    }

    /**
     * Show a single workflow with its steps.
     */
    public function show(string $id): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $workflow = ApprovalWorkflow::where('workspace_id', $this->ctx->workspaceId())
            ->with('steps')
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($workflow)]);
    }

    /**
     * Create a new workflow with optional steps.
     *
     * Body: { name, description?, entity_type, trigger_conditions?, steps[]?, workflow_key? }
     *
     * workflow_key is optional.  When omitted the server generates a stable
     * opaque key in the format `wf_<ULID>`.  Technical callers (seeders,
     * tests) may still supply an explicit key.
     */
    public function store(Request $request): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $request->validate([
            'workflow_key'       => 'nullable|string|max:100',
            'name'               => 'required|string|max:255',
            'description'        => 'nullable|string',
            'entity_type'        => 'required|string|max:100',
            'trigger_conditions' => 'nullable|array',
            'steps'              => 'nullable|array',
            'steps.*.name'       => 'required_with:steps|string|max:255',
            'steps.*.approver_type'          => 'required_with:steps|in:permission,requester_manager,specific_membership',
            'steps.*.approver_permission_key' => 'nullable|string|max:100',
            'steps.*.approver_membership_id' => 'nullable|uuid',
            'steps.*.allow_self_approval'    => 'nullable|boolean',
            'steps.*.conditions'             => 'nullable|array',
        ]);

        // Auto-generate workflow_key when not provided.
        $workflowKey = $request->input('workflow_key');
        if (empty($workflowKey) || trim($workflowKey) === '') {
            $workflowKey = 'wf_' . Str::ulid();
        }

        // Validate trigger_conditions structure
        $triggerConditions = $request->input('trigger_conditions');
        $conditionErrors = $this->conditionValidator->validate($triggerConditions);
        if ($conditionErrors) {
            return response()->json([
                'message' => 'Invalid trigger conditions.',
                'errors'  => ['trigger_conditions' => $conditionErrors],
            ], 422);
        }

        $wsId = $this->ctx->workspaceId();

        // Check uniqueness of workflow_key per workspace
        $exists = ApprovalWorkflow::where('workspace_id', $wsId)
            ->where('workflow_key', $workflowKey)
            ->exists();

        if ($exists) {
            return response()->json([
                'message' => "A workflow with this key already exists in this workspace.",
            ], 409);
        }

        // Validate inline steps' approver constraints
        $steps = $request->input('steps', []);
        foreach ($steps as $i => $stepData) {
            $validationError = $this->validateApproverConstraints(
                $stepData['approver_type'] ?? '',
                $stepData['approver_permission_key'] ?? null,
                $stepData['approver_membership_id'] ?? null,
                $wsId,
                "steps.$i",
            );
            if ($validationError) {
                return $validationError;
            }
        }

        $workflow = DB::transaction(function () use ($request, $wsId, $membership, $steps, $workflowKey) {
            $workflow = ApprovalWorkflow::create([
                'workspace_id'       => $wsId,
                'workflow_key'       => $workflowKey,
                'name'               => $request->input('name'),
                'description'        => $request->input('description'),
                'entity_type'        => $request->input('entity_type'),
                'trigger_conditions' => $request->input('trigger_conditions', []),
                'is_active'          => true,
                'sort_order'         => 0,
                'created_by'         => $membership->id,
            ]);

            // Create steps if provided
            foreach ($steps as $i => $stepData) {
                ApprovalWorkflowStep::create([
                    'workspace_id'            => $wsId,
                    'workflow_id'             => $workflow->id,
                    'name'                    => $stepData['name'],
                    'step_order'              => $i + 1,
                    'approver_type'           => $stepData['approver_type'],
                    'approver_permission_key' => $stepData['approver_permission_key'] ?? null,
                    'approver_membership_id'  => $stepData['approver_membership_id'] ?? null,
                    'conditions'              => $stepData['conditions'] ?? [],
                    'allow_self_approval'     => $stepData['allow_self_approval'] ?? false,
                    'is_active'               => true,
                ]);
            }

            return $workflow->load('steps');
        });

        return response()->json(['data' => $this->fmt($workflow)], 201);
    }

    /**
     * Update a workflow definition.
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $request->validate([
            'name'               => 'nullable|string|max:255',
            'description'        => 'nullable|string',
            'trigger_conditions' => 'nullable|array',
            'is_active'          => 'nullable|boolean',
            'sort_order'         => 'nullable|integer',
        ]);

        // Validate trigger_conditions structure if provided
        if ($request->has('trigger_conditions')) {
            // Explicit null is not allowed — the DB column is NOT NULL.
            // The store() endpoint defaults to []; on update, omit the key to preserve existing.
            if ($request->input('trigger_conditions') === null) {
                return response()->json([
                    'message' => 'Invalid trigger conditions.',
                    'errors'  => ['trigger_conditions' => ['trigger_conditions cannot be null. Send [] to clear, or omit the key to preserve existing conditions.']],
                ], 422);
            }

            $conditionErrors = $this->conditionValidator->validate($request->input('trigger_conditions'));
            if ($conditionErrors) {
                return response()->json([
                    'message' => 'Invalid trigger conditions.',
                    'errors'  => ['trigger_conditions' => $conditionErrors],
                ], 422);
            }
        }

        $workflow = ApprovalWorkflow::where('workspace_id', $this->ctx->workspaceId())
            ->findOrFail($id);

        $workflow->update($request->only([
            'name', 'description', 'trigger_conditions', 'is_active', 'sort_order',
        ]));

        return response()->json(['data' => $this->fmt($workflow->fresh()->load('steps'))]);
    }

    /**
     * Delete (deactivate) a workflow.
     *
     * Workflows with active requests cannot be hard-deleted.
     */
    public function destroy(string $id): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $workflow = ApprovalWorkflow::where('workspace_id', $this->ctx->workspaceId())
            ->findOrFail($id);

        // Soft-deactivate instead of hard delete to preserve audit trail
        $workflow->update(['is_active' => false]);

        return response()->json(['message' => 'Workflow deactivated.']);
    }

    // ── Workflow Steps CRUD ────────────────────────────────────

    /**
     * Add a step to a workflow.
     */
    public function addStep(Request $request, string $workflowId): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $wsId = $this->ctx->workspaceId();
        $workflow = ApprovalWorkflow::where('workspace_id', $wsId)->findOrFail($workflowId);

        $request->validate([
            'name'                    => 'required|string|max:255',
            'approver_type'           => 'required|in:permission,requester_manager,specific_membership',
            'approver_permission_key' => 'nullable|string|max:100',
            'approver_membership_id'  => 'nullable|uuid',
            'allow_self_approval'     => 'nullable|boolean',
            'conditions'              => 'nullable|array',
        ]);

        // Validate approver constraints
        $validationError = $this->validateApproverConstraints(
            $request->input('approver_type'),
            $request->input('approver_permission_key'),
            $request->input('approver_membership_id'),
            $wsId,
        );
        if ($validationError) {
            return $validationError;
        }

        // Auto-assign step_order as max + 1
        $maxOrder = ApprovalWorkflowStep::where('workflow_id', $workflowId)->max('step_order') ?? 0;

        $step = ApprovalWorkflowStep::create([
            'workspace_id'            => $wsId,
            'workflow_id'             => $workflowId,
            'name'                    => $request->input('name'),
            'step_order'              => $maxOrder + 1,
            'approver_type'           => $request->input('approver_type'),
            'approver_permission_key' => $request->input('approver_permission_key'),
            'approver_membership_id'  => $request->input('approver_membership_id'),
            'conditions'              => $request->input('conditions', []),
            'allow_self_approval'     => $request->input('allow_self_approval', false),
            'is_active'               => true,
        ]);

        return response()->json(['data' => $this->fmtStep($step)], 201);
    }

    /**
     * Update a workflow step.
     */
    public function updateStep(Request $request, string $stepId): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $step = ApprovalWorkflowStep::where('workspace_id', $this->ctx->workspaceId())
            ->findOrFail($stepId);

        $request->validate([
            'name'                    => 'nullable|string|max:255',
            'step_order'              => 'nullable|integer|min:1',
            'approver_type'           => 'nullable|in:permission,requester_manager,specific_membership',
            'approver_permission_key' => 'nullable|string|max:100',
            'approver_membership_id'  => 'nullable|uuid',
            'allow_self_approval'     => 'nullable|boolean',
            'conditions'              => 'nullable|array',
            'is_active'               => 'nullable|boolean',
        ]);

        // Validate approver constraints when type or key/member changes
        $effectiveType = $request->input('approver_type', $step->approver_type);
        $effectiveKey  = $request->has('approver_permission_key')
            ? $request->input('approver_permission_key')
            : $step->approver_permission_key;
        $effectiveMid  = $request->has('approver_membership_id')
            ? $request->input('approver_membership_id')
            : $step->approver_membership_id;

        $validationError = $this->validateApproverConstraints(
            $effectiveType,
            $effectiveKey,
            $effectiveMid,
            $this->ctx->workspaceId(),
        );
        if ($validationError) {
            return $validationError;
        }

        $step->update($request->only([
            'name', 'step_order', 'approver_type', 'approver_permission_key',
            'approver_membership_id', 'allow_self_approval', 'conditions', 'is_active',
        ]));

        return response()->json(['data' => $this->fmtStep($step->fresh())]);
    }

    /**
     * Delete a workflow step.
     */
    public function deleteStep(string $stepId): JsonResponse
    {
        $membership = $this->ctx->membership();
        $this->requirePermission($membership, 'approvals.manage');

        $step = ApprovalWorkflowStep::where('workspace_id', $this->ctx->workspaceId())
            ->findOrFail($stepId);

        $step->delete();

        return response()->json(['message' => 'Step deleted.']);
    }

    // ── Formatters ─────────────────────────────────────────────

    private function fmt(ApprovalWorkflow $w): array
    {
        return [
            'id'                 => $w->id,
            'workflow_key'       => $w->workflow_key,
            'name'               => $w->name,
            'description'        => $w->description,
            'entity_type'        => $w->entity_type,
            'trigger_conditions' => $w->trigger_conditions,
            'is_active'          => $w->is_active,
            'sort_order'         => $w->sort_order,
            'created_by'         => $w->created_by,
            'steps'              => $w->relationLoaded('steps')
                ? $w->steps->map(fn ($s) => $this->fmtStep($s))->toArray()
                : [],
            'created_at'         => $w->created_at?->toIso8601String(),
            'updated_at'         => $w->updated_at?->toIso8601String(),
        ];
    }

    private function fmtStep(ApprovalWorkflowStep $s): array
    {
        return [
            'id'                      => $s->id,
            'workflow_id'             => $s->workflow_id,
            'name'                    => $s->name,
            'step_order'              => $s->step_order,
            'approver_type'           => $s->approver_type,
            'approver_permission_key' => $s->approver_permission_key,
            'approver_membership_id'  => $s->approver_membership_id,
            'conditions'              => $s->conditions,
            'allow_self_approval'     => $s->allow_self_approval,
            'is_active'               => $s->is_active,
            'created_at'              => $s->created_at?->toIso8601String(),
            'updated_at'              => $s->updated_at?->toIso8601String(),
        ];
    }

    // ── Approver constraint validation ──────────────────────────

    /**
     * Validate that the approver constraints are satisfied:
     * - permission type → key must be in the approver-eligible subset.
     * - specific_membership type → membership must exist in the workspace.
     *
     * Returns null on success, or a 422 JsonResponse on failure.
     */
    private function validateApproverConstraints(
        string $approverType,
        ?string $permissionKey,
        ?string $membershipId,
        string $workspaceId,
        ?string $fieldPrefix = null,
    ): ?JsonResponse {
        $prefix = $fieldPrefix ? "{$fieldPrefix}." : '';

        if ($approverType === 'permission') {
            if (empty($permissionKey)) {
                return response()->json([
                    'message' => 'A permission key is required when approver type is permission.',
                    'errors'  => ["{$prefix}approver_permission_key" => ['Permission key is required.']],
                ], 422);
            }

            $eligible = PermissionCatalog::approverKeys();
            if (! in_array($permissionKey, $eligible, true)) {
                return response()->json([
                    'message' => "The permission '{$permissionKey}' is not eligible as an approver permission.",
                    'errors'  => ["{$prefix}approver_permission_key" => ["'{$permissionKey}' is not eligible for approval steps."]],
                ], 422);
            }
        }

        if ($approverType === 'specific_membership') {
            if (empty($membershipId)) {
                return response()->json([
                    'message' => 'A membership ID is required when approver type is specific_membership.',
                    'errors'  => ["{$prefix}approver_membership_id" => ['Membership ID is required.']],
                ], 422);
            }

            $exists = WorkspaceMembership::where('workspace_id', $workspaceId)
                ->where('id', $membershipId)
                ->where('status', 'active')
                ->exists();

            if (! $exists) {
                return response()->json([
                    'message' => 'The specified member does not exist or is not active in this workspace.',
                    'errors'  => ["{$prefix}approver_membership_id" => ['Member not found or inactive.']],
                ], 422);
            }
        }

        return null;
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
