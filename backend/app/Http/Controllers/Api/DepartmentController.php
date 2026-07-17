<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Department;
use App\Models\WorkspaceMembership;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * DepartmentController — workspace department CRUD.
 */
class DepartmentController extends Controller
{

    /**
     * GET /api/departments
     */
    public function index(): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $departments = Department::where('workspace_id', $wsId)
            ->with(['managerMembership.user:id,full_name,email'])
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get();

        return response()->json([
            'data' => $departments->map(fn ($d) => $this->formatDepartment($d)),
        ]);
    }

    /**
     * POST /api/departments
     */
    public function store(Request $request): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();


        $validated = $request->validate([
            'name'                  => 'required|string|max:255',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        if (! empty($validated['manager_membership_id'])) {
            $this->validateMembershipBelongsToWorkspace($validated['manager_membership_id'], $wsId);
        }

        $department = Department::create([
            'workspace_id'          => $wsId,
            'department_key'        => Str::slug($validated['name'], '_'),
            'name'                  => $validated['name'],
            'description'           => $validated['description'] ?? null,
            'manager_membership_id' => $validated['manager_membership_id'] ?? null,
            'is_active'             => true,
            'sort_order'            => $validated['sort_order'] ?? 0,
        ]);

        $department->load('managerMembership.user:id,full_name,email');

        return response()->json([
            'data' => $this->formatDepartment($department),
        ], 201);
    }

    /**
     * GET /api/departments/{id}
     */
    public function show(string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();

        $department = Department::where('workspace_id', $wsId)
            ->with(['managerMembership.user:id,full_name,email', 'teams', 'members.user:id,full_name,email'])
            ->findOrFail($id);

        return response()->json([
            'data' => $this->formatDepartment($department),
        ]);
    }

    /**
     * PUT /api/departments/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();


        $department = Department::where('workspace_id', $wsId)->findOrFail($id);

        $validated = $request->validate([
            'name'                  => 'sometimes|required|string|max:255',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'is_active'             => 'sometimes|boolean',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        if (! empty($validated['manager_membership_id'])) {
            $this->validateMembershipBelongsToWorkspace($validated['manager_membership_id'], $wsId);
        }

        if (isset($validated['name'])) {
            $validated['department_key'] = Str::slug($validated['name'], '_');
        }

        $department->update($validated);
        $department->load('managerMembership.user:id,full_name,email');

        return response()->json([
            'data' => $this->formatDepartment($department),
        ]);
    }

    /**
     * DELETE /api/departments/{id}
     *
     * Soft-deactivates the department.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $wsId = app(WorkspaceContextManager::class)->workspaceId();


        $department = Department::where('workspace_id', $wsId)->findOrFail($id);

        // Check for active members
        $memberCount = WorkspaceMembership::where('department_id', $id)
            ->where('status', 'active')
            ->count();

        if ($memberCount > 0) {
            $department->update(['is_active' => false]);

            return response()->json([
                'message' => 'Department deactivated (has active members).',
                'data'    => $this->formatDepartment($department->fresh()),
            ]);
        }

        $department->update(['is_active' => false]);

        return response()->json([
            'message' => 'Department deactivated.',
        ]);
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function formatDepartment(Department $d): array
    {
        $manager = $d->managerMembership?->user;

        return [
            'id'              => $d->id,
            'workspace_id'    => $d->workspace_id,
            'department_key'  => $d->department_key,
            'name'            => $d->name,
            'description'     => $d->description,
            'is_active'       => $d->is_active,
            'sort_order'      => $d->sort_order,
            'manager'         => $manager ? [
                'membership_id' => $d->manager_membership_id,
                'full_name'     => $manager->full_name,
                'email'         => $manager->email,
            ] : null,
            'member_count'    => $d->members_count ?? $d->members()->where('status', 'active')->count(),
            'team_count'      => $d->teams_count ?? $d->teams()->where('is_active', true)->count(),
            'created_at'      => $d->created_at?->toISOString(),
            'updated_at'      => $d->updated_at?->toISOString(),
        ];
    }



    private function validateMembershipBelongsToWorkspace(string $membershipId, string $wsId): void
    {
        $exists = WorkspaceMembership::where('id', $membershipId)
            ->where('workspace_id', $wsId)
            ->where('status', 'active')
            ->exists();

        if (! $exists) {
            abort(422, 'Manager membership does not belong to this workspace.');
        }
    }
}
