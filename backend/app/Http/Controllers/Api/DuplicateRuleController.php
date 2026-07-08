<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\DuplicateRule;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class DuplicateRuleController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $q = DuplicateRule::where('workspace_id', $wsId)->orderBy('sort_order');

        if ($request->filled('entity_type')) $q->where('entity_type', $request->input('entity_type'));

        return response()->json(['data' => $q->get()->map(fn ($r) => $this->fmt($r))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $v = $request->validate([
            'name'           => 'required|string|max:255',
            'entity_type'    => 'required|string|in:contact,pipeline_record',
            'match_fields'   => 'required|array|min:1',
            'match_fields.*' => 'string',
            'match_strategy' => 'nullable|string|in:exact,normalized_exact',
            'action'         => 'nullable|string|in:warn,block',
            'sort_order'     => 'nullable|integer|min:0',
        ]);

        $rule = DuplicateRule::create([
            'workspace_id'  => $ctx->workspaceId(),
            'rule_key'      => Str::slug($v['name'], '_'),
            'name'          => $v['name'],
            'entity_type'   => $v['entity_type'],
            'match_fields'  => $v['match_fields'],
            'match_strategy' => $v['match_strategy'] ?? 'normalized_exact',
            'action'        => $v['action'] ?? 'warn',
            'is_active'     => true,
            'sort_order'    => $v['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->fmt($rule)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $rule = DuplicateRule::where('workspace_id', $wsId)->findOrFail($id);
        return response()->json(['data' => $this->fmt($rule)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $rule = DuplicateRule::where('workspace_id', $ctx->workspaceId())->findOrFail($id);

        $v = $request->validate([
            'name'           => 'sometimes|required|string|max:255',
            'match_fields'   => 'sometimes|array|min:1',
            'match_fields.*' => 'string',
            'match_strategy' => 'nullable|string|in:exact,normalized_exact',
            'action'         => 'nullable|string|in:warn,block',
            'is_active'      => 'sometimes|boolean',
            'sort_order'     => 'nullable|integer|min:0',
        ]);

        if (isset($v['name'])) $v['rule_key'] = Str::slug($v['name'], '_');
        $rule->update($v);

        return response()->json(['data' => $this->fmt($rule->fresh())]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $rule = DuplicateRule::where('workspace_id', $ctx->workspaceId())->findOrFail($id);
        $rule->update(['is_active' => false]);

        return response()->json(['message' => 'Rule deactivated.']);
    }

    private function fmt(DuplicateRule $r): array
    {
        return [
            'id'             => $r->id,
            'rule_key'       => $r->rule_key,
            'name'           => $r->name,
            'entity_type'    => $r->entity_type,
            'match_fields'   => $r->match_fields,
            'match_strategy' => $r->match_strategy,
            'action'         => $r->action,
            'is_active'      => $r->is_active,
            'sort_order'     => $r->sort_order,
            'created_at'     => $r->created_at?->toIso8601String(),
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
