<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MembershipRole;
use App\Models\Role;
use App\Models\WorkspaceMembership;
use App\Services\PermissionCatalog;
use App\Services\WorkspaceContextManager;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * RoleManagementController — workspace role CRUD.
 *
 * GET  /api/permission-catalog
 * GET  /api/workspace-roles        (replaces the one from WorkspaceInvitationController)
 * POST /api/workspace-roles
 * PUT  /api/workspace-roles/{id}
 * POST /api/workspace-roles/{id}/deactivate
 */
class RoleManagementController extends Controller
{
    private const ADMIN_ROLE_KEYS = ['owner', 'admin', 'general_manager'];

    // ═══════════════════════════════════════════════════════════
    //  Permission Catalog (no workspace context needed)
    // ═══════════════════════════════════════════════════════════

    /**
     * GET /api/permission-catalog
     */
    public function permissionCatalog(): JsonResponse
    {
        return response()->json(['data' => PermissionCatalog::all()]);
    }

    // ═══════════════════════════════════════════════════════════
    //  Workspace Roles CRUD
    // ═══════════════════════════════════════════════════════════

    /**
     * GET /api/workspace-roles
     */
    public function index(): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);

        $roles = Role::where('workspace_id', $ctx->workspaceId())
            ->orderBy('hierarchy_level')
            ->orderBy('sort_order')
            ->get();

        $data = $roles->map(fn (Role $r) => $this->rolePayload($r));

        return response()->json(['data' => $data]);
    }

    /**
     * POST /api/workspace-roles
     */
    public function store(Request $request): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeRoleManagement($ctx);

        $validated = $request->validate([
            'name'        => 'required|string|max:255',
            'role_key'    => 'nullable|string|max:100|regex:/^[a-z0-9_]+$/',
            'description' => 'nullable|string|max:1000',
            'permissions' => 'present|array',
            'permissions.*' => 'string|max:100',
            'sort_order'  => 'nullable|integer|min:0|max:999',
        ]);

        // Auto-generate role_key from name if not provided
        $roleKey = $validated['role_key'] ?? Str::slug($validated['name'], '_');

        // Ensure unique within workspace
        $exists = Role::where('workspace_id', $ctx->workspaceId())
            ->where('role_key', $roleKey)
            ->exists();

        if ($exists) {
            return response()->json([
                'message' => 'A role with this key already exists in the workspace.',
                'errors'  => ['role_key' => ['Role key must be unique within the workspace.']],
            ], 422);
        }

        // Block owner role creation through this endpoint
        if ($roleKey === 'owner') {
            return response()->json([
                'message' => 'Cannot create a role with the owner key.',
            ], 403);
        }

        // Validate permission keys against catalog + existing workspace permissions
        $invalidKeys = $this->validatePermissions($validated['permissions'], $ctx->workspaceId());
        if (! empty($invalidKeys)) {
            return response()->json([
                'message' => 'Some permission keys are invalid.',
                'errors'  => ['permissions' => ['Invalid keys: ' . implode(', ', $invalidKeys)]],
            ], 422);
        }

        $role = Role::create([
            'workspace_id'    => $ctx->workspaceId(),
            'name'            => $validated['name'],
            'role_key'        => $roleKey,
            'description'     => $validated['description'] ?? null,
            'permissions'     => $validated['permissions'],
            'hierarchy_level' => 50,
            'is_system'       => false,
            'is_default'      => false,
            'is_deletable'    => true,
            'is_active'       => true,
            'sort_order'      => $validated['sort_order'] ?? 0,
        ]);

        return response()->json(['data' => $this->rolePayload($role)], 201);
    }

    /**
     * PUT /api/workspace-roles/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeRoleManagement($ctx);

        $role = Role::where('workspace_id', $ctx->workspaceId())->find($id);

        if (! $role) {
            return response()->json(['message' => 'Role not found.'], 404);
        }

        // Protect owner role permissions from reduction via this endpoint
        if ($role->role_key === 'owner') {
            return response()->json([
                'message' => 'Owner role cannot be modified through this endpoint.',
            ], 403);
        }

        $validated = $request->validate([
            'name'        => 'sometimes|string|max:255',
            'description' => 'nullable|string|max:1000',
            'permissions' => 'sometimes|array',
            'permissions.*' => 'string|max:100',
            'sort_order'  => 'nullable|integer|min:0|max:999',
            'is_active'   => 'sometimes|boolean',
        ]);

        // Validate permissions if provided
        if (isset($validated['permissions'])) {
            $invalidKeys = $this->validatePermissions($validated['permissions'], $ctx->workspaceId());
            if (! empty($invalidKeys)) {
                return response()->json([
                    'message' => 'Some permission keys are invalid.',
                    'errors'  => ['permissions' => ['Invalid keys: ' . implode(', ', $invalidKeys)]],
                ], 422);
            }
        }

        $role->update(array_filter([
            'name'        => $validated['name'] ?? null,
            'description' => array_key_exists('description', $validated) ? $validated['description'] : null,
            'permissions' => $validated['permissions'] ?? null,
            'sort_order'  => $validated['sort_order'] ?? null,
            'is_active'   => $validated['is_active'] ?? null,
        ], fn ($v) => $v !== null));

        return response()->json(['data' => $this->rolePayload($role->fresh())]);
    }

    /**
     * POST /api/workspace-roles/{id}/deactivate
     */
    public function deactivate(Request $request, string $id): JsonResponse
    {
        $ctx = app(WorkspaceContextManager::class);
        $this->authorizeRoleManagement($ctx);

        $role = Role::where('workspace_id', $ctx->workspaceId())->find($id);

        if (! $role) {
            return response()->json(['message' => 'Role not found.'], 404);
        }

        if ($role->role_key === 'owner') {
            return response()->json(['message' => 'Owner role cannot be deactivated.'], 403);
        }

        // Check if role is assigned to active memberships
        $assignedCount = MembershipRole::where('role_id', $role->id)
            ->whereHas('membership', fn ($q) => $q->where('status', 'active'))
            ->count();

        if ($assignedCount > 0) {
            return response()->json([
                'message' => "Cannot deactivate role. It is assigned to {$assignedCount} active member(s). Remove the role from all members first.",
            ], 409);
        }

        $role->update(['is_active' => false]);

        return response()->json(['message' => 'Role deactivated.']);
    }

    // ═══════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════

    private function rolePayload(Role $role): array
    {
        $assignedCount = MembershipRole::where('role_id', $role->id)
            ->whereHas('membership', fn ($q) => $q->where('status', 'active'))
            ->count();

        return [
            'id'              => $role->id,
            'role_key'        => $role->role_key,
            'name'            => $role->name,
            'description'     => $role->description,
            'permissions'     => $role->permissions ?? [],
            'hierarchy_level' => $role->hierarchy_level,
            'is_system'       => $role->is_system,
            'is_default'      => $role->is_default,
            'is_deletable'    => $role->is_deletable,
            'is_active'       => $role->is_active ?? true,
            'sort_order'      => $role->sort_order ?? 0,
            'assigned_count'  => $assignedCount,
        ];
    }

    /**
     * Validate permission keys against the catalog + existing workspace role permissions.
     *
     * @return string[] Invalid keys
     */
    private function validatePermissions(array $keys, string $workspaceId): array
    {
        $catalogKeys = PermissionCatalog::allKeys();

        // Also accept any permission key already used in this workspace's roles
        $existingKeys = Role::where('workspace_id', $workspaceId)
            ->pluck('permissions')
            ->flatten()
            ->unique()
            ->toArray();

        $allValid = array_unique(array_merge($catalogKeys, $existingKeys));

        return array_values(array_diff($keys, $allValid));
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
            abort(403, 'You do not have permission to manage roles.');
        }
    }
}
