<?php

namespace App\Services;

use App\Models\MembershipRole;
use App\Models\PermissionDelegation;
use App\Models\UserPermissionOverride;
use App\Models\WorkspaceMembership;

/**
 * Resolves effective permissions for a workspace membership.
 *
 * Resolution order:
 * 1. Collect role-based permissions from membership → roles → roles.permissions JSONB
 * 2. Apply user_permission_overrides (grant adds, deny removes)
 * 3. Apply active permission_delegations (adds delegated permissions)
 *
 * This is a stateless service — each call resolves fresh from the DB.
 */
class PermissionResolver
{
    /**
     * Check if a membership has a specific permission.
     */
    public function can(WorkspaceMembership $membership, string $permissionKey): bool
    {
        // Step 1: Check for explicit deny override (highest priority)
        $denyExists = UserPermissionOverride::where('membership_id', $membership->id)
            ->where('permission_key', $permissionKey)
            ->where('override_type', 'deny')
            ->active()
            ->exists();

        if ($denyExists) {
            return false;
        }

        // Step 2: Check for explicit grant override
        $grantExists = UserPermissionOverride::where('membership_id', $membership->id)
            ->where('permission_key', $permissionKey)
            ->where('override_type', 'grant')
            ->active()
            ->exists();

        if ($grantExists) {
            return true;
        }

        // Step 3: Check role-based permissions
        if ($this->hasRolePermission($membership, $permissionKey)) {
            return true;
        }

        // Step 4: Check active delegations
        if ($this->hasDelegatedPermission($membership, $permissionKey)) {
            return true;
        }

        return false;
    }

    /**
     * Get all effective permissions for a membership.
     *
     * Returns an array of permission keys that are currently granted.
     */
    public function resolveAll(WorkspaceMembership $membership): array
    {
        $permissions = [];

        // Collect from roles
        $rolePermissions = $this->getRolePermissions($membership);
        foreach ($rolePermissions as $key) {
            $permissions[$key] = true;
        }

        // Collect from delegations
        $delegatedPerms = $this->getDelegatedPermissions($membership);
        foreach ($delegatedPerms as $key) {
            $permissions[$key] = true;
        }

        // Apply overrides
        $overrides = UserPermissionOverride::where('membership_id', $membership->id)
            ->active()
            ->get();

        foreach ($overrides as $override) {
            if ($override->override_type === 'grant') {
                $permissions[$override->permission_key] = true;
            } elseif ($override->override_type === 'deny') {
                unset($permissions[$override->permission_key]);
            }
        }

        return array_keys($permissions);
    }

    // ── Internal helpers ───────────────────────────────────────

    private function hasRolePermission(WorkspaceMembership $membership, string $permissionKey): bool
    {
        $rolePermissions = $this->getRolePermissions($membership);
        return in_array($permissionKey, $rolePermissions, true);
    }

    /**
     * Extract flat permission keys from all assigned roles' JSONB permissions.
     *
     * The roles.permissions JSONB can contain either:
     * - A flat array of strings: ["products.create", "products.read"]
     * - A nested object: {"products": {"create": true, "read": true}}
     *
     * This method normalizes both formats into a flat array of keys.
     */
    private function getRolePermissions(WorkspaceMembership $membership): array
    {
        $membershipRoles = MembershipRole::where('membership_id', $membership->id)
            ->with('role')
            ->get();

        $keys = [];

        foreach ($membershipRoles as $mr) {
            $rolePerms = $mr->role?->permissions;
            if (!is_array($rolePerms)) {
                continue;
            }

            // Handle flat array format: ["products.create", "products.read"]
            if (array_is_list($rolePerms)) {
                $keys = array_merge($keys, $rolePerms);
                continue;
            }

            // Handle nested object format: {"products": {"create": true}}
            foreach ($rolePerms as $module => $actions) {
                if (is_array($actions)) {
                    foreach ($actions as $action => $enabled) {
                        if ($enabled) {
                            $keys[] = "{$module}.{$action}";
                        }
                    }
                }
            }
        }

        return array_unique($keys);
    }

    private function hasDelegatedPermission(WorkspaceMembership $membership, string $permissionKey): bool
    {
        return PermissionDelegation::where('delegate_membership_id', $membership->id)
            ->currentlyActive()
            ->whereHas('items', function ($q) use ($permissionKey) {
                $q->where('permission_key', $permissionKey);
            })
            ->exists();
    }

    private function getDelegatedPermissions(WorkspaceMembership $membership): array
    {
        $delegations = PermissionDelegation::where('delegate_membership_id', $membership->id)
            ->currentlyActive()
            ->with('items')
            ->get();

        $keys = [];
        foreach ($delegations as $delegation) {
            foreach ($delegation->items as $item) {
                $keys[] = $item->permission_key;
            }
        }

        return array_unique($keys);
    }
}
