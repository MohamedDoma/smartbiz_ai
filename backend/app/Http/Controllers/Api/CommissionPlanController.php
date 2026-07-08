<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\CommissionPlan;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class CommissionPlanController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $plans = CommissionPlan::where('workspace_id', $wsId)
            ->withCount('rules')
            ->orderBy('sort_order')
            ->get();

        return response()->json(['data' => $plans->map(fn ($p) => $this->fmt($p))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $v = $request->validate([
            'name'        => 'required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'applies_to'  => 'nullable|string|in:pipeline_record',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        $plan = CommissionPlan::create([
            'workspace_id' => $ctx->workspaceId(),
            'plan_key'     => Str::slug($v['name'], '_'),
            'name'         => $v['name'],
            'description'  => $v['description'] ?? null,
            'applies_to'   => $v['applies_to'] ?? 'pipeline_record',
            'is_active'    => true,
            'sort_order'   => $v['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->fmt($plan)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $plan = CommissionPlan::where('workspace_id', $wsId)
            ->with(['rules' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')])
            ->withCount('rules')
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($plan)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $plan = CommissionPlan::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $v = $request->validate([
            'name'        => 'sometimes|required|string|max:255',
            'description' => 'nullable|string|max:2000',
            'is_active'   => 'sometimes|boolean',
            'sort_order'  => 'nullable|integer|min:0',
        ]);

        if (isset($v['name'])) {
            $v['plan_key'] = Str::slug($v['name'], '_');
        }

        $plan->update($v);
        return response()->json(['data' => $this->fmt($plan->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $plan = CommissionPlan::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        $plan->update(['is_active' => false]);

        return response()->json(['message' => 'Plan deactivated.']);
    }

    private function fmt(CommissionPlan $p): array
    {
        $data = [
            'id'           => $p->id,
            'workspace_id' => $p->workspace_id,
            'plan_key'     => $p->plan_key,
            'name'         => $p->name,
            'description'  => $p->description,
            'applies_to'   => $p->applies_to,
            'is_active'    => $p->is_active,
            'sort_order'   => $p->sort_order,
            'rules_count'  => $p->rules_count ?? null,
            'created_at'   => $p->created_at?->toIso8601String(),
        ];
        if ($p->relationLoaded('rules')) {
            $data['rules'] = $p->rules->map(fn ($r) => [
                'id' => $r->id, 'target_type' => $r->target_type,
                'calculation_type' => $r->calculation_type,
                'percentage_rate' => $r->percentage_rate,
                'fixed_amount' => $r->fixed_amount,
                'trigger_status' => $r->trigger_status,
                'is_active' => $r->is_active,
            ])->toArray();
        }
        return $data;
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
