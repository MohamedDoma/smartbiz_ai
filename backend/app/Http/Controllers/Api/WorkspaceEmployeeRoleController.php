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

class WorkspaceEmployeeRoleController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $query = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->with([
                'user:id,full_name,email,phone_number,is_active,preferred_locale',
                'membershipRoles.role',
                'department:id,name',
                'team:id,name,department_id',
                'managerMembership.user:id,full_name,email',
            ])
            ->orderBy('joined_at');

        if ($request->filled('status')) {
            $query->where('status', $request->string('status')->toString());
        } else {
            $query->whereIn('status', ['active', 'suspended']);
        }
        if ($request->filled('department_id')) {
            $query->where('department_id', $request->string('department_id')->toString());
        }
        if ($request->filled('team_id')) {
            $query->where('team_id', $request->string('team_id')->toString());
        }
        if ($request->filled('search')) {
            $search = mb_strtolower(trim($request->string('search')->toString()));
            $query->whereHas('user', function ($builder) use ($search) {
                $builder->whereRaw('LOWER(full_name) LIKE ?', ["%{$search}%"])
                    ->orWhereRaw('LOWER(email) LIKE ?', ["%{$search}%"]);
            });
        }

        return response()->json([
            'data' => $query->get()->map(fn (WorkspaceMembership $membership) => $this->employeePayload($membership)),
        ]);
    }

    public function updateRoles(Request $request, string $membershipId): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $membership = WorkspaceMembership::where('workspace_id', $workspaceId)->find($membershipId);
        if (! $membership) {
            return response()->json(['message' => 'Membership not found.'], 404);
        }

        $validated = $request->validate([
            'role_ids'        => 'required|array|min:1',
            'role_ids.*'      => 'uuid',
            'primary_role_id' => 'nullable|uuid',
        ]);

        $roleIds = array_values(array_unique($validated['role_ids']));
        $primaryRoleId = $validated['primary_role_id'] ?? $roleIds[0];
        if (! in_array($primaryRoleId, $roleIds, true)) {
            return response()->json([
                'message' => 'Primary role must be one of the selected roles.',
                'errors' => ['primary_role_id' => ['Primary role must be in role_ids.']],
            ], 422);
        }

        $roles = Role::where('workspace_id', $workspaceId)
            ->where('is_active', true)
            ->whereIn('id', $roleIds)
            ->get();
        if ($roles->count() !== count($roleIds)) {
            return response()->json([
                'message' => 'One or more roles do not belong to this workspace.',
                'errors' => ['role_ids' => ['Invalid role ID(s).']],
            ], 422);
        }
        if ($roles->contains(fn (Role $role) => $role->role_key === 'owner')) {
            return response()->json(['message' => 'The owner role cannot be assigned through this endpoint.'], 403);
        }

        $currentlyOwner = $membership->membershipRoles()
            ->whereHas('role', fn ($q) => $q->where('role_key', 'owner'))
            ->exists();
        if ($currentlyOwner) {
            return response()->json([
                'message' => 'Use the ownership-transfer workflow to change an owner role.',
            ], 409);
        }

        DB::transaction(function () use ($membership, $workspaceId, $roleIds, $primaryRoleId) {
            MembershipRole::where('membership_id', $membership->id)->delete();
            foreach ($roleIds as $roleId) {
                MembershipRole::create([
                    'workspace_id'  => $workspaceId,
                    'membership_id' => $membership->id,
                    'role_id'       => $roleId,
                    'is_primary'    => $roleId === $primaryRoleId,
                    'assigned_at'   => now(),
                ]);
            }
        });

        return response()->json([
            'data' => $this->employeePayload($this->loadMembership($membership->fresh())),
        ]);
    }

    public function updateAssignment(Request $request, string $membershipId): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $membership = WorkspaceMembership::where('workspace_id', $workspaceId)->find($membershipId);
        if (! $membership) {
            return response()->json(['message' => 'Membership not found.'], 404);
        }

        $validated = $request->validate([
            'department_id'                => 'sometimes|nullable|uuid',
            'team_id'                      => 'sometimes|nullable|uuid',
            'direct_manager_membership_id' => 'sometimes|nullable|uuid',
            'job_title'                    => 'sometimes|nullable|string|max:255',
        ]);

        $departmentId = array_key_exists('department_id', $validated)
            ? $validated['department_id']
            : $membership->department_id;
        $teamId = array_key_exists('team_id', $validated)
            ? $validated['team_id']
            : $membership->team_id;

        if ($departmentId) {
            abort_unless(
                Department::where('workspace_id', $workspaceId)
                    ->where('is_active', true)
                    ->whereKey($departmentId)
                    ->exists(),
                422,
                'Department does not belong to this workspace or is inactive.',
            );
        }

        if ($teamId) {
            $team = Team::where('workspace_id', $workspaceId)
                ->where('is_active', true)
                ->find($teamId);
            abort_unless($team, 422, 'Team does not belong to this workspace or is inactive.');

            if ($departmentId && $team->department_id && $team->department_id !== $departmentId) {
                return response()->json(['message' => 'Team does not belong to the specified department.'], 422);
            }
            $departmentId ??= $team->department_id;
        }

        // If only the department changed, clear an incompatible existing team.
        if (! array_key_exists('team_id', $validated) && $teamId) {
            $currentTeam = Team::where('workspace_id', $workspaceId)->find($teamId);
            if ($currentTeam?->department_id && $currentTeam->department_id !== $departmentId) {
                $teamId = null;
            }
        }

        $managerId = array_key_exists('direct_manager_membership_id', $validated)
            ? $validated['direct_manager_membership_id']
            : $membership->manager_membership_id;

        if ($managerId) {
            if ($managerId === $membershipId) {
                return response()->json([
                    'message' => 'Employee cannot be their own direct manager.',
                    'errors' => ['direct_manager_membership_id' => ['Self-assignment is not allowed.']],
                ], 422);
            }

            $manager = WorkspaceMembership::where('workspace_id', $workspaceId)
                ->where('status', 'active')
                ->find($managerId);
            abort_unless($manager, 422, 'Manager membership does not belong to this workspace or is inactive.');

            if ($this->wouldCreateManagerCycle($membershipId, $managerId, $workspaceId)) {
                return response()->json([
                    'message' => 'This manager assignment would create a reporting cycle.',
                    'errors' => ['direct_manager_membership_id' => ['Reporting cycles are not allowed.']],
                ], 422);
            }
        }

        $updates = [
            'department_id' => $departmentId,
            'team_id' => $teamId,
            'manager_membership_id' => $managerId,
        ];
        if (array_key_exists('job_title', $validated)) {
            $jobTitle = $validated['job_title'] !== null ? trim($validated['job_title']) : null;
            $updates['job_title'] = $jobTitle === '' ? null : $jobTitle;
        }

        $membership->update($updates);

        return response()->json([
            'data' => $this->employeePayload($this->loadMembership($membership->fresh())),
        ]);
    }

    public function updateStatus(Request $request, string $membershipId): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $workspaceId = $ctx->workspaceId();
        $membership = WorkspaceMembership::where('workspace_id', $workspaceId)->find($membershipId);
        if (! $membership) {
            return response()->json(['message' => 'Membership not found.'], 404);
        }

        $validated = $request->validate([
            'status' => 'required|string|in:active,suspended',
        ]);

        if ($membershipId === $ctx->membershipId() && $validated['status'] === 'suspended') {
            return response()->json(['message' => 'You cannot suspend your own membership.'], 409);
        }

        $isOwner = $membership->membershipRoles()
            ->whereHas('role', fn ($q) => $q->where('role_key', 'owner'))
            ->exists();
        if ($isOwner && $validated['status'] === 'suspended') {
            return response()->json(['message' => 'Transfer ownership before suspending the workspace owner.'], 409);
        }

        if ($validated['status'] === 'suspended') {
            $managesDepartment = Department::where('workspace_id', $workspaceId)
                ->where('manager_membership_id', $membershipId)
                ->where('is_active', true)
                ->exists();
            $managesTeam = Team::where('workspace_id', $workspaceId)
                ->where('manager_membership_id', $membershipId)
                ->where('is_active', true)
                ->exists();
            $hasDirectReports = WorkspaceMembership::where('workspace_id', $workspaceId)
                ->where('manager_membership_id', $membershipId)
                ->where('status', 'active')
                ->exists();

            if ($managesDepartment || $managesTeam || $hasDirectReports) {
                return response()->json([
                    'message' => 'Reassign this employee’s departments, teams, and direct reports before suspending them.',
                ], 409);
            }
        }

        $membership->update([
            'status' => $validated['status'],
            'suspended_at' => $validated['status'] === 'suspended' ? now() : null,
        ]);

        return response()->json([
            'data' => $this->employeePayload($this->loadMembership($membership->fresh())),
        ]);
    }

    private function wouldCreateManagerCycle(string $membershipId, string $managerId, string $workspaceId): bool
    {
        $visited = [];
        $currentId = $managerId;

        while ($currentId) {
            if ($currentId === $membershipId || isset($visited[$currentId])) {
                return true;
            }
            $visited[$currentId] = true;
            $currentId = WorkspaceMembership::where('workspace_id', $workspaceId)
                ->whereKey($currentId)
                ->value('manager_membership_id');
        }

        return false;
    }

    private function loadMembership(WorkspaceMembership $membership): WorkspaceMembership
    {
        return $membership->load([
            'user:id,full_name,email,phone_number,is_active,preferred_locale',
            'membershipRoles.role',
            'department:id,name',
            'team:id,name,department_id',
            'managerMembership.user:id,full_name,email',
        ]);
    }

    private function employeePayload(WorkspaceMembership $membership): array
    {
        $roles = $membership->membershipRoles;
        $primary = $roles->firstWhere('is_primary', true) ?? $roles->first();
        $manager = $membership->managerMembership?->user;

        return [
            'membership_id' => $membership->id,
            'user_id'       => $membership->user_id,
            'full_name'     => $membership->user?->full_name,
            'email'         => $membership->user?->email,
            'phone_number'  => $membership->user?->phone_number,
            'preferred_locale' => $membership->user?->preferred_locale,
            'status'        => $membership->status,
            'joined_at'     => $membership->joined_at?->toIso8601String(),
            'job_title'     => $membership->job_title,
            'department'    => $membership->department ? [
                'id' => $membership->department->id,
                'name' => $membership->department->name,
            ] : null,
            'team'          => $membership->team ? [
                'id' => $membership->team->id,
                'name' => $membership->team->name,
            ] : null,
            'direct_manager'=> $manager ? [
                'membership_id' => $membership->manager_membership_id,
                'full_name' => $manager->full_name,
                'email' => $manager->email,
            ] : null,
            'primary_role'  => $primary ? [
                'role_id' => $primary->role_id,
                'role_key' => $primary->role?->role_key,
                'name' => $primary->role?->name,
                'is_primary' => true,
            ] : null,
            'roles'         => $roles->map(fn (MembershipRole $role) => [
                'role_id' => $role->role_id,
                'role_key' => $role->role?->role_key,
                'name' => $role->role?->name,
                'is_primary' => $role->is_primary,
            ])->values()->toArray(),
        ];
    }
}
