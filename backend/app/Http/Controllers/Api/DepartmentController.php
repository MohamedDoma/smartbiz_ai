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

class DepartmentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();

        $query = Department::where('workspace_id', $workspaceId)
            ->with(['managerMembership.user:id,full_name,email'])
            ->withCount([
                'members as member_count' => fn ($q) => $q->where('status', 'active'),
                'teams as team_count' => fn ($q) => $q->where('is_active', true),
            ])
            ->orderBy('sort_order')
            ->orderBy('name');

        if (! $request->boolean('include_inactive')) {
            $query->where('is_active', true);
        }

        return response()->json([
            'data' => $query->get()->map(fn (Department $department) => $this->formatDepartment($department)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $validated = $request->validate([
            'name'                  => 'required|string|max:255',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        $name = trim($validated['name']);
        $this->ensureUniqueName($workspaceId, $name);
        $this->validateManager($validated['manager_membership_id'] ?? null, $workspaceId);

        $department = Department::create([
            'workspace_id'          => $workspaceId,
            'department_key'        => $this->uniqueKey($workspaceId, $name),
            'name'                  => $name,
            'description'           => $this->nullableTrim($validated['description'] ?? null),
            'manager_membership_id' => $validated['manager_membership_id'] ?? null,
            'is_active'             => true,
            'sort_order'            => $validated['sort_order'] ?? 0,
        ]);

        return response()->json([
            'data' => $this->formatDepartment($this->loadDepartment($department)),
        ], 201);
    }

    public function show(string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $department = Department::where('workspace_id', $workspaceId)
            ->with([
                'managerMembership.user:id,full_name,email',
                'teams' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')->orderBy('name'),
                'members.user:id,full_name,email',
            ])
            ->withCount([
                'members as member_count' => fn ($q) => $q->where('status', 'active'),
                'teams as team_count' => fn ($q) => $q->where('is_active', true),
            ])
            ->findOrFail($id);

        return response()->json(['data' => $this->formatDepartment($department)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $department = Department::where('workspace_id', $workspaceId)->findOrFail($id);

        $validated = $request->validate([
            'name'                  => 'sometimes|required|string|max:255',
            'description'           => 'sometimes|nullable|string|max:1000',
            'manager_membership_id' => 'sometimes|nullable|uuid',
            'is_active'             => 'sometimes|boolean',
            'sort_order'            => 'sometimes|integer|min:0',
        ]);

        if (array_key_exists('name', $validated)) {
            $validated['name'] = trim($validated['name']);
            $this->ensureUniqueName($workspaceId, $validated['name'], $department->id);
            $validated['department_key'] = $this->uniqueKey($workspaceId, $validated['name'], $department->id);
        }
        if (array_key_exists('description', $validated)) {
            $validated['description'] = $this->nullableTrim($validated['description']);
        }
        if (array_key_exists('manager_membership_id', $validated)) {
            $this->validateManager($validated['manager_membership_id'], $workspaceId);
        }

        if (array_key_exists('is_active', $validated)
            && $validated['is_active'] === false
            && $department->is_active) {
            $this->ensureCanDeactivate($department, $workspaceId);
            $validated['manager_membership_id'] = null;
        }

        $department->update($validated);

        return response()->json([
            'data' => $this->formatDepartment($this->loadDepartment($department->fresh())),
        ]);
    }

    public function destroy(string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $department = Department::where('workspace_id', $workspaceId)->findOrFail($id);

        $this->ensureCanDeactivate($department, $workspaceId);
        $department->update(['is_active' => false, 'manager_membership_id' => null]);

        return response()->json(['message' => 'Department deactivated.']);
    }

    private function ensureCanDeactivate(Department $department, string $workspaceId): void
    {
        $activeMembers = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('department_id', $department->id)
            ->where('status', 'active')
            ->count();
        $activeTeams = Team::where('workspace_id', $workspaceId)
            ->where('department_id', $department->id)
            ->where('is_active', true)
            ->count();

        abort_if(
            $activeMembers > 0 || $activeTeams > 0,
            409,
            'Move active employees and deactivate the department teams before deactivating this department.',
        );
    }

    private function loadDepartment(Department $department): Department
    {
        return $department->load('managerMembership.user:id,full_name,email')
            ->loadCount([
                'members as member_count' => fn ($q) => $q->where('status', 'active'),
                'teams as team_count' => fn ($q) => $q->where('is_active', true),
            ]);
    }

    private function formatDepartment(Department $department): array
    {
        $manager = $department->managerMembership?->user;

        return [
            'id'             => $department->id,
            'workspace_id'   => $department->workspace_id,
            'department_key' => $department->department_key,
            'name'           => $department->name,
            'description'    => $department->description,
            'is_active'      => $department->is_active,
            'sort_order'     => $department->sort_order,
            'manager'        => $manager ? [
                'membership_id' => $department->manager_membership_id,
                'full_name' => $manager->full_name,
                'email' => $manager->email,
            ] : null,
            'member_count'   => (int) ($department->member_count ?? 0),
            'team_count'     => (int) ($department->team_count ?? 0),
            'created_at'     => $department->created_at?->toISOString(),
            'updated_at'     => $department->updated_at?->toISOString(),
        ];
    }

    private function validateManager(?string $membershipId, string $workspaceId): void
    {
        if (! $membershipId) {
            return;
        }

        abort_unless(
            WorkspaceMembership::where('id', $membershipId)
                ->where('workspace_id', $workspaceId)
                ->where('status', 'active')
                ->exists(),
            422,
            'Manager membership does not belong to this workspace or is inactive.',
        );
    }

    private function ensureUniqueName(string $workspaceId, string $name, ?string $ignoreId = null): void
    {
        $exists = Department::where('workspace_id', $workspaceId)
            ->whereRaw('LOWER(name) = ?', [mb_strtolower($name)])
            ->when($ignoreId, fn ($query) => $query->where('id', '!=', $ignoreId))
            ->exists();

        abort_if($exists, 422, 'A department with this name already exists.');
    }

    private function uniqueKey(string $workspaceId, string $name, ?string $ignoreId = null): string
    {
        $base = Str::slug($name, '_') ?: 'department';
        $key = $base;
        $suffix = 2;

        while (Department::where('workspace_id', $workspaceId)
            ->where('department_key', $key)
            ->when($ignoreId, fn ($query) => $query->where('id', '!=', $ignoreId))
            ->exists()) {
            $key = "{$base}_{$suffix}";
            $suffix++;
        }

        return $key;
    }

    private function nullableTrim(?string $value): ?string
    {
        $value = $value !== null ? trim($value) : null;
        return $value === '' ? null : $value;
    }
}
