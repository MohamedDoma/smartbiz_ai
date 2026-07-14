<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Models\WorkspaceMembership;
use App\Services\PermissionResolver;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommissionRuleController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.view');

        $q = CommissionRule::where('workspace_id', $wsId)
            ->with(['plan:id,name', 'pipeline:id,name', 'stage:id,name,status_type'])
            ->orderBy('sort_order');

        if ($request->filled('commission_plan_id')) {
            $q->where('commission_plan_id', $request->input('commission_plan_id'));
        }

        return response()->json(['data' => $q->get()->map(fn ($r) => $this->fmt($r))]);
    }


    public function store(Request $request): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.manage');

        $v = $request->validate([
            'commission_plan_id' => 'required|uuid',
            'pipeline_id'       => 'required|uuid',
            'stage_id'          => 'required|uuid',
            'role_id'           => 'nullable|uuid',
            'department_id'     => 'nullable|uuid',
            'team_id'           => 'nullable|uuid',
            'target_type'       => 'nullable|string|in:assigned_employee,direct_manager,team_manager,department_manager',
            'calculation_type'  => 'nullable|string|in:percentage,fixed_amount',
            'percentage_rate'   => 'nullable|numeric|min:0.0001|max:100',
            'fixed_amount'      => 'nullable|numeric|min:0.01',
            'currency'          => 'nullable|string|max:10',
            'min_record_value'  => 'nullable|numeric|min:0',
            'max_record_value'  => 'nullable|numeric|min:0',
            'sort_order'        => 'nullable|integer|min:0',
        ]);

        // Validate plan belongs to workspace
        if (!CommissionPlan::where('workspace_id', $wsId)->where('id', $v['commission_plan_id'])->exists()) {
            return response()->json(['message' => 'Plan not found.'], 422);
        }

        // Validate pipeline + stage pair
        $pairResult = $this->validatePipelineStage($wsId, $v['pipeline_id'], $v['stage_id']);
        if ($pairResult instanceof JsonResponse) {
            return $pairResult;
        }

        // Derive trigger_status from validated stage — never trust client-supplied value
        $triggerStatus = $pairResult['stage']->status_type;

        $calcType = $v['calculation_type'] ?? 'percentage';
        if ($calcType === 'percentage' && empty($v['percentage_rate'])) {
            return response()->json(['message' => 'percentage_rate required for percentage type.'], 422);
        }
        if ($calcType === 'fixed_amount' && empty($v['fixed_amount'])) {
            return response()->json(['message' => 'fixed_amount required for fixed_amount type.'], 422);
        }

        $rule = CommissionRule::create([
            'workspace_id'       => $wsId,
            'commission_plan_id' => $v['commission_plan_id'],
            'pipeline_id'        => $v['pipeline_id'],
            'stage_id'           => $v['stage_id'],
            'role_id'            => $v['role_id'] ?? null,
            'department_id'      => $v['department_id'] ?? null,
            'team_id'            => $v['team_id'] ?? null,
            'target_type'        => $v['target_type'] ?? 'assigned_employee',
            'calculation_type'   => $calcType,
            'percentage_rate'    => $v['percentage_rate'] ?? null,
            'fixed_amount'       => $v['fixed_amount'] ?? null,
            'currency'           => $v['currency'] ?? 'LYD',
            'min_record_value'   => $v['min_record_value'] ?? null,
            'max_record_value'   => $v['max_record_value'] ?? null,
            'trigger_status'     => $triggerStatus,
            'is_active'          => true,
            'sort_order'         => $v['sort_order'] ?? 0,
        ]);

        $rule->load(['plan:id,name', 'pipeline:id,name', 'stage:id,name,status_type']);
        return response()->json(['data' => $this->fmt($rule)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.view');

        $rule = CommissionRule::where('workspace_id', $wsId)
            ->with(['plan:id,name', 'pipeline:id,name', 'stage:id,name,status_type'])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($rule)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.manage');

        $rule = CommissionRule::where('workspace_id', $wsId)->findOrFail($id);

        $v = $request->validate([
            'pipeline_id'      => 'nullable|uuid',
            'stage_id'         => 'nullable|uuid',
            'target_type'      => 'nullable|string|in:assigned_employee,direct_manager,team_manager,department_manager',
            'calculation_type' => 'nullable|string|in:percentage,fixed_amount',
            'percentage_rate'  => 'nullable|numeric|min:0.0001|max:100',
            'fixed_amount'     => 'nullable|numeric|min:0.01',
            'currency'         => 'nullable|string|max:10',
            'min_record_value' => 'nullable|numeric|min:0',
            'max_record_value' => 'nullable|numeric|min:0',
            'is_active'        => 'sometimes|boolean',
            'sort_order'       => 'nullable|integer|min:0',
        ]);

        // ── Compute effective pipeline_id + stage_id ──────────────
        $effectivePipelineId = $v['pipeline_id'] ?? $rule->pipeline_id;
        $effectiveStageId    = $v['stage_id']    ?? $rule->stage_id;
        $pipelineChanging    = isset($v['pipeline_id']) && $v['pipeline_id'] !== $rule->pipeline_id;

        // Pipeline changed without a new stage → reject. The old stage
        // belongs to the previous pipeline and must not be silently retained.
        if ($pipelineChanging && !isset($v['stage_id'])) {
            return response()->json([
                'message'    => 'A stage must be selected for the new pipeline.',
                'error_code' => 'commission_stage_required_for_pipeline',
            ], 422);
        }

        // Validate the effective pair whenever pipeline or stage is touched,
        // or when either effective value is set (covers legacy null cases).
        if (isset($v['pipeline_id']) || isset($v['stage_id']) || $effectivePipelineId || $effectiveStageId) {
            if (!$effectivePipelineId || !$effectiveStageId) {
                return response()->json(['message' => 'Both pipeline and stage are required.'], 422);
            }

            $pairResult = $this->validatePipelineStage($wsId, $effectivePipelineId, $effectiveStageId);
            if ($pairResult instanceof JsonResponse) {
                return $pairResult;
            }

            // Persist the validated effective IDs and derived trigger_status
            $v['pipeline_id']    = $effectivePipelineId;
            $v['stage_id']       = $effectiveStageId;
            $v['trigger_status'] = $pairResult['stage']->status_type;
        }

        // Never allow client-supplied trigger_status to leak through
        // (the field is not in the validation rules, but be defensive)
        unset($v['trigger_status_client']);

        $rule->update($v);
        $rule->load(['plan:id,name', 'pipeline:id,name', 'stage:id,name,status_type']);
        return response()->json(['data' => $this->fmt($rule->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx  = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $membership = $ctx->membership();

        $this->requirePermission($membership, 'commissions.settings.manage');

        $rule = CommissionRule::where('workspace_id', $wsId)->findOrFail($id);
        $rule->update(['is_active' => false]);

        return response()->json(['message' => 'Rule deactivated.']);
    }

    private function fmt(CommissionRule $r): array
    {
        return [
            'id'                 => $r->id,
            'commission_plan_id' => $r->commission_plan_id,
            'plan'               => $r->relationLoaded('plan') && $r->plan ? ['id' => $r->plan->id, 'name' => $r->plan->name] : null,
            'pipeline_id'        => $r->pipeline_id,
            'pipeline'           => $r->relationLoaded('pipeline') && $r->pipeline ? ['id' => $r->pipeline->id, 'name' => $r->pipeline->name] : null,
            'stage_id'           => $r->stage_id,
            'stage'              => $r->relationLoaded('stage') && $r->stage ? [
                'id'          => $r->stage->id,
                'name'        => $r->stage->name,
                'status_type' => $r->stage->status_type ?? null,
            ] : null,
            'role_id'            => $r->role_id,
            'department_id'      => $r->department_id,
            'team_id'            => $r->team_id,
            'target_type'        => $r->target_type,
            'calculation_type'   => $r->calculation_type,
            'percentage_rate'    => $r->percentage_rate,
            'fixed_amount'       => $r->fixed_amount,
            'currency'           => $r->currency,
            'min_record_value'   => $r->min_record_value,
            'max_record_value'   => $r->max_record_value,
            'trigger_status'     => $r->trigger_status,
            'is_active'          => $r->is_active,
            'sort_order'         => $r->sort_order,
            'created_at'         => $r->created_at?->toIso8601String(),
        ];
    }

    /**
     * Validate a pipeline + stage pair for commission rule configuration.
     *
     * Returns an associative array ['pipeline' => Pipeline, 'stage' => PipelineStage]
     * on success, or a JsonResponse (422) on validation failure.
     *
     * Used by both store() and update() to keep validation consistent.
     */
    private function validatePipelineStage(string $wsId, string $pipelineId, string $stageId): array|JsonResponse
    {
        $pipeline = Pipeline::where('workspace_id', $wsId)
            ->where('id', $pipelineId)
            ->first();

        if (!$pipeline) {
            return response()->json(['message' => 'Pipeline not found.'], 422);
        }
        if (!$pipeline->is_active) {
            return response()->json(['message' => 'Pipeline is not active.'], 422);
        }
        if ($pipeline->entity_type !== 'deal') {
            return response()->json(['message' => 'Pipeline entity type is not supported by the commission engine.'], 422);
        }

        $stage = PipelineStage::where('workspace_id', $wsId)
            ->where('pipeline_id', $pipelineId)
            ->where('id', $stageId)
            ->first();

        if (!$stage) {
            return response()->json(['message' => 'Stage not found.'], 422);
        }
        if (!$stage->is_active) {
            return response()->json(['message' => 'Stage is inactive.'], 422);
        }

        return ['pipeline' => $pipeline, 'stage' => $stage];
    }

    /**
     * Require a specific permission via the PermissionResolver.
     *
     * Super-admins are always allowed. Regular users must have an active
     * membership with the requested permission key.
     */
    private function requirePermission(?WorkspaceMembership $membership, string $permissionKey): void
    {
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
