<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\Team;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * TeamController — workspace team CRUD.
 */
class TeamController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager', 'manager'];

    /**
     * GET /api/teams
     */
    public function index(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $query = Team::where('workspace_id', $wsId)
            ->with(['department:id,name', 'managerMembership.user:id,full_name,email'])
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($request->has('department_id')) {
            $query->where('department_id', $request->input('department_id'));
        }

        return response()->json([
            'data' => $query->get()->map(fn ($t) => $this->formatTeam($t)),
        ]);
    }

    /**
     * POST /api/teams
     */
    public function store(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireAdminRole($wsId, $request);

        $validated = $request->validate([
            'name'                  => 'required|string|max:255',
            'department_id'         => 'nullable|uuid',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        if (! empty($validated['department_id'])) {
            $this->validateDepartmentBelongsToWorkspace($validated['department_id'], $wsId);
        }
        if (! empty($validated['manager_membership_id'])) {
            $this->validateMembershipBelongsToWorkspace($validated['manager_membership_id'], $wsId);
        }

        $team = Team::create([
            'workspace_id'          => $wsId,
            'department_id'         => $validated['department_id'] ?? null,
            'team_key'              => Str::slug($validated['name'], '_'),
            'name'                  => $validated['name'],
            'description'           => $validated['description'] ?? null,
            'manager_membership_id' => $validated['manager_membership_id'] ?? null,
            'is_active'             => true,
            'sort_order'            => $validated['sort_order'] ?? 0,
        ]);

        $team->load(['department:id,name', 'managerMembership.user:id,full_name,email']);

        return response()->json([
            'data' => $this->formatTeam($team),
        ], 201);
    }

    /**
     * GET /api/teams/{id}
     */
    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $team = Team::where('workspace_id', $wsId)
            ->with(['department:id,name', 'managerMembership.user:id,full_name,email', 'members.user:id,full_name,email'])
            ->findOrFail($id);

        return response()->json([
            'data' => $this->formatTeam($team),
        ]);
    }

    /**
     * PUT /api/teams/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireAdminRole($wsId, $request);

        $team = Team::where('workspace_id', $wsId)->findOrFail($id);

        $validated = $request->validate([
            'name'                  => 'sometimes|required|string|max:255',
            'department_id'         => 'nullable|uuid',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'is_active'             => 'sometimes|boolean',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        if (! empty($validated['department_id'])) {
            $this->validateDepartmentBelongsToWorkspace($validated['department_id'], $wsId);
        }
        if (! empty($validated['manager_membership_id'])) {
            $this->validateMembershipBelongsToWorkspace($validated['manager_membership_id'], $wsId);
        }

        if (isset($validated['name'])) {
            $validated['team_key'] = Str::slug($validated['name'], '_');
        }

        $team->update($validated);
        $team->load(['department:id,name', 'managerMembership.user:id,full_name,email']);

        return response()->json([
            'data' => $this->formatTeam($team),
        ]);
    }

    /**
     * DELETE /api/teams/{id}
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();
        $this->requireAdminRole($wsId, $request);

        $team = Team::where('workspace_id', $wsId)->findOrFail($id);
        $team->update(['is_active' => false]);

        return response()->json([
            'message' => 'Team deactivated.',
        ]);
    }

    // ═══════════════════════════════════════════════════════════

    private function formatTeam(Team $t): array
    {
        $manager = $t->managerMembership?->user;

        return [
            'id'             => $t->id,
            'workspace_id'   => $t->workspace_id,
            'department_id'  => $t->department_id,
            'department'     => $t->department ? ['id' => $t->department->id, 'name' => $t->department->name] : null,
            'team_key'       => $t->team_key,
            'name'           => $t->name,
            'description'    => $t->description,
            'is_active'      => $t->is_active,
            'sort_order'     => $t->sort_order,
            'manager'        => $manager ? [
                'membership_id' => $t->manager_membership_id,
                'full_name'     => $manager->full_name,
                'email'         => $manager->email,
            ] : null,
            'member_count'   => $t->members_count ?? $t->members()->where('status', 'active')->count(),
            'created_at'     => $t->created_at?->toISOString(),
            'updated_at'     => $t->updated_at?->toISOString(),
        ];
    }

    private function requireAdminRole(string $wsId, Request $request): void
    {
        $user = $request->user();
        if ($user->is_super_admin) return;

        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('user_id', $user->id)->where('status', 'active')->first();

        if (! $membership) abort(403, 'Not a member of this workspace.');

        $roleKeys = $membership->membershipRoles()
            ->join('roles', 'roles.id', '=', 'membership_roles.role_id')
            ->pluck('roles.role_key')->toArray();

        if (empty(array_intersect($roleKeys, self::ADMIN_ROLE_KEYS))) {
            abort(403, 'Insufficient permissions.');
        }
    }

    private function validateDepartmentBelongsToWorkspace(string $deptId, string $wsId): void
    {
        if (! Department::where('id', $deptId)->where('workspace_id', $wsId)->exists()) {
            abort(422, 'Department does not belong to this workspace.');
        }
    }

    private function validateMembershipBelongsToWorkspace(string $membershipId, string $wsId): void
    {
        if (! WorkspaceMembership::where('id', $membershipId)->where('workspace_id', $wsId)->where('status', 'active')->exists()) {
            abort(422, 'Manager membership does not belong to this workspace.');
        }
    }
}
