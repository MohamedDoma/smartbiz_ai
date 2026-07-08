<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\OwnershipAssignment;
use App\Models\WorkspaceMembership;
use App\Services\OwnershipService;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class OwnershipController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $q = OwnershipAssignment::where('workspace_id', $wsId)
            ->with(['ownerMembership.user:id,full_name', 'team:id,name', 'department:id,name'])
            ->orderByDesc('assigned_at');

        if ($request->filled('entity_type')) $q->where('entity_type', $request->input('entity_type'));
        if ($request->filled('owner_membership_id')) $q->where('owner_membership_id', $request->input('owner_membership_id'));
        if ($request->filled('status')) $q->where('status', $request->input('status'));

        return response()->json(['data' => $q->get()->map(fn ($a) => $this->fmt($a))]);
    }

    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $v = $request->validate([
            'entity_type'         => 'required|string|in:contact,pipeline_record',
            'entity_id'           => 'required|uuid',
            'owner_membership_id' => 'required|uuid',
            'source'              => 'nullable|string|in:manual,created_by,assigned_employee,transfer,import',
            'notes'               => 'nullable|string|max:2000',
        ]);

        // Validate owner belongs to workspace
        if (!WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
                ->where('id', $v['owner_membership_id'])->exists()) {
            return response()->json(['message' => 'Owner membership not found.'], 422);
        }

        $currentUser = $request->user();
        $currentMembership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $currentUser->id)->first();

        $svc = new OwnershipService();
        $assignment = $svc->assign(
            $ctx->workspaceId(),
            $v['entity_type'],
            $v['entity_id'],
            $v['owner_membership_id'],
            $v['source'] ?? 'manual',
            $currentMembership?->id,
            $v['notes'] ?? null,
        );

        if (!$assignment) {
            return response()->json([
                'message' => 'Entity already has an active owner. Use transfer endpoint to change.',
            ], 409);
        }

        $assignment->load(['ownerMembership.user:id,full_name', 'team:id,name', 'department:id,name']);
        return response()->json(['data' => $this->fmt($assignment)], 201);
    }

    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $a = OwnershipAssignment::where('workspace_id', $wsId)
            ->with(['ownerMembership.user:id,full_name', 'team:id,name', 'department:id,name'])
            ->findOrFail($id);

        return response()->json(['data' => $this->fmt($a)]);
    }

    public function transfer(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->requireAdmin($ctx->workspaceId(), $request);

        $v = $request->validate([
            'to_membership_id' => 'required|uuid',
            'reason'           => 'nullable|string|max:2000',
        ]);

        $currentUser = $request->user();
        $currentMembership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('user_id', $currentUser->id)->first();

        $svc = new OwnershipService();
        $assignment = $svc->transfer(
            $ctx->workspaceId(),
            $id,
            $v['to_membership_id'],
            $currentMembership?->id,
            $v['reason'] ?? null,
        );

        $assignment->load(['ownerMembership.user:id,full_name', 'team:id,name', 'department:id,name']);
        return response()->json(['data' => $this->fmt($assignment)]);
    }

    public function resolve(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $v = $request->validate([
            'entity_type' => 'required|string|in:contact,pipeline_record',
            'entity_id'   => 'required|uuid',
        ]);

        $svc = new OwnershipService();
        $result = $svc->resolve($wsId, $v['entity_type'], $v['entity_id']);

        if (!$result) {
            return response()->json(['data' => ['source' => 'none', 'owner' => null]]);
        }

        $data = [
            'source' => $result['source'],
            'owner'  => $result['owner'],
        ];
        if ($result['assignment']) {
            $data['assignment_id'] = $result['assignment']->id;
        }

        return response()->json(['data' => $data]);
    }

    private function fmt(OwnershipAssignment $a): array
    {
        return [
            'id'                  => $a->id,
            'entity_type'         => $a->entity_type,
            'entity_id'           => $a->entity_id,
            'owner_membership_id' => $a->owner_membership_id,
            'owner'               => $a->relationLoaded('ownerMembership') && $a->ownerMembership
                ? ['membership_id' => $a->owner_membership_id, 'full_name' => $a->ownerMembership->user?->full_name]
                : null,
            'team'                => $a->relationLoaded('team') && $a->team
                ? ['id' => $a->team->id, 'name' => $a->team->name] : null,
            'department'          => $a->relationLoaded('department') && $a->department
                ? ['id' => $a->department->id, 'name' => $a->department->name] : null,
            'source'              => $a->source,
            'status'              => $a->status,
            'assigned_at'         => $a->assigned_at?->toIso8601String(),
            'notes'               => $a->notes,
            'created_at'          => $a->created_at?->toIso8601String(),
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
