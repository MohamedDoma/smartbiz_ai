<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\MembershipRole;
use App\Models\Role;
use App\Models\Team;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * WorkspaceEmployeeRoleController — employee listing & role assignment.
 *
 * GET /api/workspace-employees
 * PUT /api/workspace-employees/{membership_id}/roles
 */
class WorkspaceEmployeeRoleController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager'];

    /**
     * GET /api/workspace-employees
     *
     * List all workspace members with their roles.
     */
    public function index(): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $memberships = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->with([
                'user',
                'membershipRoles.role',
                'department:id,name',
                'team:id,name,department_id',
                'managerMembership.user:id,full_name,email',
            ])
            ->orderBy('joined_at')
            ->get();

        $data = $memberships->map(function ($m) {
            $roles = $m->membershipRoles;
            $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();
            $manager = $m->managerMembership?->user;

            return [
                'membership_id' => $m->id,
                'user_id'       => $m->user_id,
                'full_name'     => $m->user?->full_name,
                'email'         => $m->user?->email,
                'phone_number'  => $m->user?->phone_number,
                'status'        => $m->status,
                'joined_at'     => $m->joined_at?->toIso8601String(),
                'job_title'     => $m->job_title,
                'department'    => $m->department ? [
                    'id'   => $m->department->id,
                    'name' => $m->department->name,
                ] : null,
                'team'          => $m->team ? [
                    'id'   => $m->team->id,
                    'name' => $m->team->name,
                ] : null,
                'direct_manager' => $manager ? [
                    'membership_id' => $m->manager_membership_id,
                    'full_name'     => $manager->full_name,
                    'email'         => $manager->email,
                ] : null,
                'primary_role'  => $primaryMr ? [
                    'role_id'  => $primaryMr->role_id,
                    'role_key' => $primaryMr->role?->role_key,
                    'name'     => $primaryMr->role?->name,
                ] : null,
                'roles' => $roles->map(fn ($mr) => [
                    'role_id'    => $mr->role_id,
                    'role_key'   => $mr->role?->role_key,
                    'name'       => $mr->role?->name,
                    'is_primary' => $mr->is_primary,
                ])->values()->toArray(),
            ];
        });

        return response()->json(['data' => $data]);
    }

    /**
     * PUT /api/workspace-employees/{membership_id}/roles
     *
     * Update the roles assigned to a workspace member.
     */
    public function updateRoles(Request $request, string $membershipId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeRoleManagement($ctx);

        $membership = WorkspaceMembership::where('workspace_id', $ctx->workspaceId())
            ->where('id', $membershipId)
            ->first();

        if (! $membership) {
            return response()->json(['message' => 'Membership not found.'], 404);
        }

        $validated = $request->validate([
            'role_ids'        => 'required|array|min:1',
            'role_ids.*'      => 'uuid',
            'primary_role_id' => 'nullable|uuid',
        ]);

        $roleIds = $validated['role_ids'];
        $primaryRoleId = $validated['primary_role_id'] ?? $roleIds[0];

        // Validate primary_role_id is in role_ids
        if (! in_array($primaryRoleId, $roleIds, true)) {
            return response()->json([
                'message' => 'Primary role must be one of the selected roles.',
                'errors'  => ['primary_role_id' => ['Primary role must be in role_ids.']],
            ], 422);
        }

        // Verify all roles belong to workspace
        $roles = Role::where('workspace_id', $ctx->workspaceId())
            ->whereIn('id', $roleIds)
            ->get();

        if ($roles->count() !== count($roleIds)) {
            return response()->json([
                'message' => 'One or more roles do not belong to this workspace.',
                'errors'  => ['role_ids' => ['Invalid role ID(s).']],
            ], 422);
        }

        // Block owner role assignment through this endpoint
        $hasOwner = $roles->contains(fn ($r) => $r->role_key === 'owner');
        if ($hasOwner) {
            return response()->json([
                'message' => 'Owner role cannot be assigned through this endpoint.',
            ], 403);
        }

        // Protect against removing the last owner from the workspace
        $currentOwnerMr = MembershipRole::where('membership_id', $membershipId)
            ->whereHas('role', fn ($q) => $q->where('role_key', 'owner'))
            ->first();

        if ($currentOwnerMr) {
            // This membership currently has the owner role
            // Check if they're the last owner
            $ownerRole = Role::where('workspace_id', $ctx->workspaceId())
                ->where('role_key', 'owner')
                ->first();

            if ($ownerRole) {
                $ownerCount = MembershipRole::where('role_id', $ownerRole->id)
                    ->whereHas('membership', fn ($q) => $q->where('status', 'active'))
                    ->count();

                if ($ownerCount <= 1) {
                    return response()->json([
                        'message' => 'Cannot remove the last owner role from the workspace.',
                    ], 409);
                }
            }
        }

        try {
            DB::transaction(function () use ($membership, $roleIds, $primaryRoleId, $currentOwnerMr, $ctx) {
                // Remove existing non-owner membership roles
                MembershipRole::where('membership_id', $membership->id)
                    ->where(function ($q) {
                        $q->whereDoesntHave('role', fn ($rq) => $rq->where('role_key', 'owner'));
                    })
                    ->delete();

                // Insert new roles
                foreach ($roleIds as $roleId) {
                    MembershipRole::create([
                        'workspace_id'  => $ctx->workspaceId(),
                        'membership_id' => $membership->id,
                        'role_id'       => $roleId,
                        'is_primary'    => $roleId === $primaryRoleId,
                        'assigned_at'   => now(),
                    ]);
                }
            });
        } catch (\Throwable $e) {
            report($e);
            return response()->json(['message' => 'Failed to update roles.'], 500);
        }

        // Return updated employee payload
        $membership = $membership->fresh()->load(['user', 'membershipRoles.role']);
        $roles = $membership->membershipRoles;
        $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();

        return response()->json(['data' => [
            'membership_id' => $membership->id,
            'user_id'       => $membership->user_id,
            'full_name'     => $membership->user?->full_name,
            'email'         => $membership->user?->email,
            'status'        => $membership->status,
            'primary_role'  => $primaryMr ? [
                'role_id'  => $primaryMr->role_id,
                'role_key' => $primaryMr->role?->role_key,
                'name'     => $primaryMr->role?->name,
            ] : null,
            'roles' => $roles->map(fn ($mr) => [
                'role_id'    => $mr->role_id,
                'role_key'   => $mr->role?->role_key,
                'name'       => $mr->role?->name,
                'is_primary' => $mr->is_primary,
            ])->values()->toArray(),
        ]]);
    }

    private function authorizeRoleManagement(WorkspaceContextManager $ctx): void
    {
        $membership = WorkspaceMembership::where('id', $ctx->membershipId())->first();

        if (! $membership) {
            abort(403, 'No active membership in this workspace.');
        }

        $roleKeys = $membership->membershipRoles()
            ->with('role')
            ->get()
            ->pluck('role.role_key')
            ->toArray();

        if (empty(array_intersect($roleKeys, self::ADMIN_ROLE_KEYS))) {
            abort(403, 'You do not have permission to manage employee roles.');
        }
    }

    /**
     * PUT /api/workspace-employees/{membership_id}/assignment
     *
     * Update org assignment (department, team, manager, job title).
     */
    public function updateAssignment(Request $request, string $membershipId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeRoleManagement($ctx);

        $wsId = $ctx->workspaceId();
        $membership = WorkspaceMembership::where('workspace_id', $wsId)
            ->where('id', $membershipId)
            ->first();

        if (! $membership) {
            return response()->json(['message' => 'Membership not found.'], 404);
        }

        $validated = $request->validate([
            'department_id'                => 'nullable|uuid',
            'team_id'                      => 'nullable|uuid',
            'direct_manager_membership_id' => 'nullable|uuid',
            'job_title'                    => 'nullable|string|max:255',
        ]);

        // Self-manager check
        if (! empty($validated['direct_manager_membership_id'])
            && $validated['direct_manager_membership_id'] === $membershipId) {
            return response()->json([
                'message' => 'Employee cannot be their own direct manager.',
                'errors'  => ['direct_manager_membership_id' => ['Self-assignment not allowed.']],
            ], 422);
        }

        // Validate department belongs to workspace
        if (! empty($validated['department_id'])) {
            if (! Department::where('id', $validated['department_id'])->where('workspace_id', $wsId)->exists()) {
                return response()->json([
                    'message' => 'Department does not belong to this workspace.',
                ], 422);
            }
        }

        // Validate team belongs to workspace
        if (! empty($validated['team_id'])) {
            $team = Team::where('id', $validated['team_id'])->where('workspace_id', $wsId)->first();
            if (! $team) {
                return response()->json([
                    'message' => 'Team does not belong to this workspace.',
                ], 422);
            }
            // Auto-set department from team if not provided
            if (empty($validated['department_id']) && $team->department_id) {
                $validated['department_id'] = $team->department_id;
            }
            // Cross-check team department matches provided department
            if (! empty($validated['department_id']) && $team->department_id
                && $team->department_id !== $validated['department_id']) {
                return response()->json([
                    'message' => 'Team does not belong to the specified department.',
                ], 422);
            }
        }

        // Validate direct manager belongs to workspace
        if (! empty($validated['direct_manager_membership_id'])) {
            if (! WorkspaceMembership::where('id', $validated['direct_manager_membership_id'])
                    ->where('workspace_id', $wsId)->where('status', 'active')->exists()) {
                return response()->json([
                    'message' => 'Manager membership does not belong to this workspace.',
                ], 422);
            }
        }

        $membership->update([
            'department_id'          => $validated['department_id'] ?? null,
            'team_id'                => $validated['team_id'] ?? null,
            'manager_membership_id'  => $validated['direct_manager_membership_id'] ?? $membership->manager_membership_id,
            'job_title'              => $validated['job_title'] ?? $membership->job_title,
        ]);

        // Return updated payload with org + roles
        $membership = $membership->fresh()->load([
            'user',
            'membershipRoles.role',
            'department:id,name',
            'team:id,name,department_id',
            'managerMembership.user:id,full_name,email',
        ]);

        $roles = $membership->membershipRoles;
        $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();
        $manager = $membership->managerMembership?->user;

        return response()->json(['data' => [
            'membership_id'  => $membership->id,
            'user_id'        => $membership->user_id,
            'full_name'      => $membership->user?->full_name,
            'email'          => $membership->user?->email,
            'status'         => $membership->status,
            'job_title'      => $membership->job_title,
            'department'     => $membership->department ? [
                'id' => $membership->department->id, 'name' => $membership->department->name,
            ] : null,
            'team'           => $membership->team ? [
                'id' => $membership->team->id, 'name' => $membership->team->name,
            ] : null,
            'direct_manager' => $manager ? [
                'membership_id' => $membership->manager_membership_id,
                'full_name'     => $manager->full_name,
                'email'         => $manager->email,
            ] : null,
            'primary_role'   => $primaryMr ? [
                'role_id' => $primaryMr->role_id, 'role_key' => $primaryMr->role?->role_key, 'name' => $primaryMr->role?->name,
            ] : null,
            'roles'          => $roles->map(fn ($mr) => [
                'role_id' => $mr->role_id, 'role_key' => $mr->role?->role_key, 'name' => $mr->role?->name, 'is_primary' => $mr->is_primary,
            ])->values()->toArray(),
        ]]);
    }
}
