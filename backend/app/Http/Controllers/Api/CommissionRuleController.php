<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommissionPlan;
use App\Models\CommissionRule;
use App\Models\Pipeline;
use App\Models\PipelineStage;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommissionRuleController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $q = CommissionRule::where('workspace_id', $wsId)
            ->with(['plan:id,name', 'pipeline:id,name', 'stage:id,name'])
            ->orderBy('sort_order');

        if ($request->filled('commission_plan_id')) {
            $q->where('commission_plan_id', $request->input('commission_plan_id'));
        }

        return response()->json(['data' => $q->get()->map(fn ($r) => $this->fmt($r))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $wsId = $ctx->workspaceId();
        $this->requireAdmin($wsId, $request);

        $v = $request->validate([
            'commission_plan_id' => 'required|uuid',
            'pipeline_id'       => 'nullable|uuid',
            'stage_id'          => 'nullable|uuid',
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
            'trigger_status'    => 'nullable|string|in:won,completed,open',
            'sort_order'        => 'nullable|integer|min:0',
        ]);

        // Validate plan belongs to workspace
        if (!CommissionPlan::where('workspace_id', $wsId)->where('id', $v['commission_plan_id'])->exists()) {
            return response()->json(['message' => 'Plan not found.'], 422);
        }
        if (!empty($v['pipeline_id']) && !Pipeline::where('workspace_id', $wsId)->where('id', $v['pipeline_id'])->exists()) {
            return response()->json(['message' => 'Pipeline not found.'], 422);
        }
        if (!empty($v['stage_id'])) {
            $sq = PipelineStage::where('workspace_id', $wsId)->where('id', $v['stage_id']);
            if (!empty($v['pipeline_id'])) $sq->where('pipeline_id', $v['pipeline_id']);
            if (!$sq->exists()) return response()->json(['message' => 'Stage not found.'], 422);
        }

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
            'pipeline_id'        => $v['pipeline_id'] ?? null,
            'stage_id'           => $v['stage_id'] ?? null,
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
            'trigger_status'     => $v['trigger_status'] ?? 'won',
            'is_active'          => true,
            'sort_order'         => $v['sort_order'] ?? 0,
        ]);

        $rule->load(['plan:id,name', 'pipeline:id,name', 'stage:id,name']);
        return response()->json(['data' => $this->fmt($rule)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $rule = CommissionRule::where('workspace_id', $wsId)
            ->with(['plan:id,name', 'pipeline:id,name', 'stage:id,name'])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($rule)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $rule = CommissionRule::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $v = $request->validate([
            'target_type'      => 'nullable|string|in:assigned_employee,direct_manager,team_manager,department_manager',
            'calculation_type' => 'nullable|string|in:percentage,fixed_amount',
            'percentage_rate'  => 'nullable|numeric|min:0.0001|max:100',
            'fixed_amount'     => 'nullable|numeric|min:0.01',
            'currency'         => 'nullable|string|max:10',
            'min_record_value' => 'nullable|numeric|min:0',
            'max_record_value' => 'nullable|numeric|min:0',
            'trigger_status'   => 'nullable|string|in:won,completed,open',
            'is_active'        => 'sometimes|boolean',
            'sort_order'       => 'nullable|integer|min:0',
        ]);

        $rule->update($v);
        $rule->load(['plan:id,name', 'pipeline:id,name', 'stage:id,name']);
        return response()->json(['data' => $this->fmt($rule->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $rule = CommissionRule::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
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
            'stage'              => $r->relationLoaded('stage') && $r->stage ? ['id' => $r->stage->id, 'name' => $r->stage->name] : null,
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

    private function requireAdmin(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;
        $m = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();
        if (!$m) abort(403, 'Not a member.');
        $keys = $m->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();
        if (empty(array_intersect($keys, self::ADMIN_ROLE_KEYS))) abort(403, 'Insufficient permissions.');
    }
}
