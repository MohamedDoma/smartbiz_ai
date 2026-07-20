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

class TeamController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $query = Team::where('workspace_id', $workspaceId)
            ->with(['department:id,name', 'managerMembership.user:id,full_name,email'])
            ->withCount(['members as member_count' => fn ($q) => $q->where('status', 'active')])
            ->orderBy('sort_order')
            ->orderBy('name');

        if ($request->filled('department_id')) {
            $query->where('department_id', $request->string('department_id')->toString());
        }
        if (! $request->boolean('include_inactive')) {
            $query->where('is_active', true);
        }

        return response()->json([
            'data' => $query->get()->map(fn (Team $team) => $this->formatTeam($team)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $validated = $request->validate([
            'name'                  => 'required|string|max:255',
            'department_id'         => 'nullable|uuid',
            'description'           => 'nullable|string|max:1000',
            'manager_membership_id' => 'nullable|uuid',
            'sort_order'            => 'nullable|integer|min:0',
        ]);

        $name = trim($validated['name']);
        $this->ensureUniqueName($workspaceId, $name);
        $department = $this->validateDepartment($validated['department_id'] ?? null, $workspaceId);
        $this->validateManager($validated['manager_membership_id'] ?? null, $workspaceId, $department?->id);

        $team = Team::create([
            'workspace_id'          => $workspaceId,
            'department_id'         => $department?->id,
            'team_key'              => $this->uniqueKey($workspaceId, $name),
            'name'                  => $name,
            'description'           => $this->nullableTrim($validated['description'] ?? null),
            'manager_membership_id' => $validated['manager_membership_id'] ?? null,
            'is_active'             => true,
            'sort_order'            => $validated['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->formatTeam($this->loadTeam($team))], 201);
    }

    public function show(string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $team = Team::where('workspace_id', $workspaceId)
            ->with([
                'department:id,name',
                'managerMembership.user:id,full_name,email',
                'members.user:id,full_name,email',
            ])
            ->withCount(['members as member_count' => fn ($q) => $q->where('status', 'active')])
            ->findOrFail($id);

        return response()->json(['data' => $this->formatTeam($team)]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $team = Team::where('workspace_id', $workspaceId)->findOrFail($id);
        $validated = $request->validate([
            'name'                  => 'sometimes|required|string|max:255',
            'department_id'         => 'sometimes|nullable|uuid',
            'description'           => 'sometimes|nullable|string|max:1000',
            'manager_membership_id' => 'sometimes|nullable|uuid',
            'is_active'             => 'sometimes|boolean',
            'sort_order'            => 'sometimes|integer|min:0',
        ]);

        if (array_key_exists('name', $validated)) {
            $validated['name'] = trim($validated['name']);
            $this->ensureUniqueName($workspaceId, $validated['name'], $team->id);
            $validated['team_key'] = $this->uniqueKey($workspaceId, $validated['name'], $team->id);
        }

        $departmentId = array_key_exists('department_id', $validated)
            ? $this->validateDepartment($validated['department_id'], $workspaceId)?->id
            : $team->department_id;
        if (array_key_exists('department_id', $validated)) {
            $validated['department_id'] = $departmentId;
        }
        $managerId = array_key_exists('manager_membership_id', $validated)
            ? $validated['manager_membership_id']
            : $team->manager_membership_id;
        $this->validateManager($managerId, $workspaceId, $departmentId);

        if (array_key_exists('description', $validated)) {
            $validated['description'] = $this->nullableTrim($validated['description']);
        }

        if (array_key_exists('is_active', $validated)
            && $validated['is_active'] === false
            && $team->is_active) {
            $this->ensureCanDeactivate($team, $workspaceId);
            $validated['manager_membership_id'] = null;
        }

        $team->update($validated);

        return response()->json(['data' => $this->formatTeam($this->loadTeam($team->fresh()))]);
    }

    public function destroy(string $id): JsonResponse
    {
        $workspaceId = app(WorkspaceContextManager::class)->workspaceId();
        $team = Team::where('workspace_id', $workspaceId)->findOrFail($id);
        $this->ensureCanDeactivate($team, $workspaceId);
        $team->update(['is_active' => false, 'manager_membership_id' => null]);
        return response()->json(['message' => 'Team deactivated.']);
    }

    private function ensureCanDeactivate(Team $team, string $workspaceId): void
    {
        $activeMembers = WorkspaceMembership::where('workspace_id', $workspaceId)
            ->where('team_id', $team->id)
            ->where('status', 'active')
            ->count();

        abort_if(
            $activeMembers > 0,
            409,
            'Move active employees out of this team before deactivating it.',
        );
    }

    private function loadTeam(Team $team): Team
    {
        return $team->load(['department:id,name', 'managerMembership.user:id,full_name,email'])
            ->loadCount(['members as member_count' => fn ($q) => $q->where('status', 'active')]);
    }

    private function formatTeam(Team $team): array
    {
        $manager = $team->managerMembership?->user;

        return [
            'id'            => $team->id,
            'workspace_id'  => $team->workspace_id,
            'department_id' => $team->department_id,
            'department'    => $team->department ? ['id' => $team->department->id, 'name' => $team->department->name] : null,
            'team_key'      => $team->team_key,
            'name'          => $team->name,
            'description'   => $team->description,
            'is_active'     => $team->is_active,
            'sort_order'    => $team->sort_order,
            'manager'       => $manager ? [
                'membership_id' => $team->manager_membership_id,
                'full_name' => $manager->full_name,
                'email' => $manager->email,
            ] : null,
            'member_count'  => (int) ($team->member_count ?? 0),
            'created_at'    => $team->created_at?->toISOString(),
            'updated_at'    => $team->updated_at?->toISOString(),
        ];
    }

    private function validateDepartment(?string $departmentId, string $workspaceId): ?Department
    {
        if (! $departmentId) {
            return null;
        }

        $department = Department::where('workspace_id', $workspaceId)
            ->where('is_active', true)
            ->find($departmentId);
        abort_unless($department, 422, 'Department does not belong to this workspace or is inactive.');

        return $department;
    }

    private function validateManager(?string $membershipId, string $workspaceId, ?string $departmentId): void
    {
        if (! $membershipId) {
            return;
        }

        $manager = WorkspaceMembership::where('id', $membershipId)
            ->where('workspace_id', $workspaceId)
            ->where('status', 'active')
            ->first();
        abort_unless($manager, 422, 'Manager membership does not belong to this workspace or is inactive.');

        if ($departmentId && $manager->department_id && $manager->department_id !== $departmentId) {
            abort(422, 'Team manager belongs to a different department.');
        }
    }

    private function ensureUniqueName(string $workspaceId, string $name, ?string $ignoreId = null): void
    {
        $exists = Team::where('workspace_id', $workspaceId)
            ->whereRaw('LOWER(name) = ?', [mb_strtolower($name)])
            ->when($ignoreId, fn ($query) => $query->where('id', '!=', $ignoreId))
            ->exists();
        abort_if($exists, 422, 'A team with this name already exists.');
    }

    private function uniqueKey(string $workspaceId, string $name, ?string $ignoreId = null): string
    {
        $base = Str::slug($name, '_') ?: 'team';
        $key = $base;
        $suffix = 2;
        while (Team::where('workspace_id', $workspaceId)
            ->where('team_key', $key)
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
