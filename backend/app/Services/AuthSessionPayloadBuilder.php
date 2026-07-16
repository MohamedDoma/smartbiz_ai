<?php

namespace App\Services;

use App\Models\MembershipRole;
use App\Models\PlatformPlan;
use App\Models\ProvisioningRun;
use App\Models\User;
use App\Models\WorkspaceFeatureFlag;
use App\Models\WorkspaceMembership;
use App\Models\WorkspaceTemplateApplication;

/**
 * Builds the session payload returned by login/register/me/invite-accept.
 *
 * Extracted from AuthController to avoid duplication.
 *
 * Permissions are resolved through PermissionResolver to ensure consistency
 * with runtime checks (includes overrides and delegations, not just roles).
 */
class AuthSessionPayloadBuilder
{
    /**
     * Build the full session payload for a user.
     */
    public static function build(User $user): array
    {
        $memberships = $user->activeMemberships()
            ->with(['workspace', 'membershipRoles.role', 'department:id,name', 'team:id,name,department_id', 'managerMembership.user:id,full_name,email'])
            ->get();

        // Platform role
        $platformRole = $user->is_super_admin ? 'super_admin' : 'none';

        // Resolve permissions through PermissionResolver for consistency
        // with runtime permission checks (includes overrides & delegations).
        $resolver = app(PermissionResolver::class);

        // Build membership payloads
        $membershipPayloads = $memberships->map(function ($membership) use ($resolver) {
            $workspace = $membership->workspace;
            $roles = $membership->membershipRoles;

            $primaryMr = $roles->firstWhere('is_primary', true) ?? $roles->first();

            $permissions = $resolver->resolveAll($membership);

            $onboardingCompleted = false;
            if ($workspace) {
                $onboardingCompleted = ProvisioningRun::where('workspace_id', $workspace->id)
                        ->where('status', 'completed')
                        ->exists()
                    || WorkspaceTemplateApplication::where('workspace_id', $workspace->id)
                        ->where('status', 'applied')
                        ->exists();
            }

            $enabledModules = $workspace
                ? WorkspaceFeatureFlag::where('workspace_id', $workspace->id)
                    ->where('is_enabled', true)
                    ->pluck('feature_key')
                    ->values()
                    ->toArray()
                : [];

            return [
                'id'            => $membership->id,
                'workspace_id'  => $membership->workspace_id,
                'workspace'     => [
                    'id'   => $workspace?->id,
                    'name' => $workspace?->name,
                ],
                'status'        => $membership->status,
                'department_id' => $membership->department_id,
                'department'    => $membership->department ? [
                    'id'   => $membership->department->id,
                    'name' => $membership->department->name,
                ] : null,
                'team_id'       => $membership->team_id,
                'team'          => $membership->team ? [
                    'id'   => $membership->team->id,
                    'name' => $membership->team->name,
                ] : null,
                'job_title'     => $membership->job_title,
                'direct_manager' => $membership->managerMembership?->user ? [
                    'membership_id' => $membership->manager_membership_id,
                    'full_name'     => $membership->managerMembership->user->full_name,
                    'email'         => $membership->managerMembership->user->email,
                ] : null,
                'branch_id'     => $membership->branch_id,
                'joined_at'     => $membership->joined_at?->toIso8601String(),
                'primary_role'  => $primaryMr ? [
                    'role_id'   => $primaryMr->role_id,
                    'role_name' => $primaryMr->role?->name,
                    'role_key'  => $primaryMr->role?->role_key,
                ] : null,
                'roles'         => $roles->map(fn ($mr) => [
                    'role_id'    => $mr->role_id,
                    'role_name'  => $mr->role?->name,
                    'role_key'   => $mr->role?->role_key,
                    'is_primary' => $mr->is_primary,
                ])->values()->toArray(),
                'onboarding_completed' => $onboardingCompleted,
                'enabled_modules'      => $enabledModules,
                'permissions'          => $permissions,
            ];
        });

        // Active workspace (first active membership)
        $activeMembership = $membershipPayloads->first();
        $activeWorkspace = $activeMembership ? [
            'id'                   => $activeMembership['workspace']['id'],
            'name'                 => $activeMembership['workspace']['name'],
            'role_key'             => $activeMembership['primary_role']['role_key'] ?? null,
            'role_keys'            => array_values(array_filter(array_map(
                fn ($r) => $r['role_key'] ?? null,
                $activeMembership['roles'] ?? [],
            ))),
            'onboarding_completed' => $activeMembership['onboarding_completed'],
            'enabled_modules'      => $activeMembership['enabled_modules'],
            'permissions'          => $activeMembership['permissions'],
        ] : null;

        return [
            'user' => [
                'id'               => $user->id,
                'full_name'        => $user->full_name,
                'email'            => $user->email,
                'phone_number'     => $user->phone_number,
                'is_active'        => $user->is_active,
                'preferred_locale' => $user->preferred_locale,
                'platform_role'    => $platformRole,
                'created_at'       => $user->created_at?->toIso8601String(),
            ],
            'active_workspace' => $activeWorkspace,
            'memberships'      => $membershipPayloads->toArray(),
        ];
    }
}
