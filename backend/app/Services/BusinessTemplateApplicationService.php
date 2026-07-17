<?php

namespace App\Services;

use App\Models\BusinessTemplate;
use App\Models\MembershipRole;
use App\Models\ProvisioningEntityBinding;
use App\Models\Role;
use App\Models\User;
use App\Models\Workspace;
use App\Models\WorkspaceFeatureFlag;
use App\Models\WorkspaceMembership;
use App\Models\WorkspaceTemplateApplication;
use Illuminate\Support\Facades\DB;

/**
 * Applies a BusinessTemplate to a Workspace.
 *
 * Creates workspace feature flags, roles, and records the application.
 * Writes entity-level template provenance for every created/updated role.
 * Fully idempotent — safe to call multiple times for the same template.
 */
class BusinessTemplateApplicationService
{
    /**
     * Apply a template to a workspace.
     *
     * @throws \InvalidArgumentException if template is inactive
     * @throws \RuntimeException on unexpected errors
     */
    public function apply(BusinessTemplate $template, Workspace $workspace, User $user): WorkspaceTemplateApplication
    {
        if (! $template->is_active) {
            throw new \InvalidArgumentException('Template is not active.');
        }

        return DB::transaction(function () use ($template, $workspace, $user) {

            // 1. Apply modules as workspace feature flags
            $this->applyModules($template, $workspace, $user);

            // 2. Apply roles to workspace (with provenance)
            $this->applyRoles($template, $workspace, $user);

            // 3. Build snapshot of everything applied
            $snapshot = $this->buildSnapshot($template);

            // 4. Record/update the template application
            $application = WorkspaceTemplateApplication::updateOrCreate(
                [
                    'workspace_id'         => $workspace->id,
                    'business_template_id' => $template->id,
                ],
                [
                    'template_key'       => $template->template_key,
                    'template_version'   => $template->version,
                    'status'             => 'applied',
                    'applied_at'         => now(),
                    'applied_by_user_id' => $user->id,
                    'snapshot'           => $snapshot,
                ]
            );

            // 5. Update workspace metadata
            $onboardingData = $workspace->onboarding_data ?? [];
            $onboardingData['selected_template_key'] = $template->template_key;
            $onboardingData['onboarding_completed'] = true;
            $onboardingData['onboarding_completed_at'] = now()->toIso8601String();
            $onboardingData['industry_type'] = $template->industry_type;

            $workspace->update([
                'industry_type'   => $template->industry_type,
                'onboarding_data' => $onboardingData,
            ]);

            return $application;
        });
    }

    /**
     * Check if a different template is already applied to this workspace.
     */
    public function hasConflictingTemplate(Workspace $workspace, BusinessTemplate $template): bool
    {
        return WorkspaceTemplateApplication::where('workspace_id', $workspace->id)
            ->where('business_template_id', '!=', $template->id)
            ->exists();
    }

    /**
     * Apply template modules as workspace feature flags.
     */
    private function applyModules(BusinessTemplate $template, Workspace $workspace, User $user): void
    {
        foreach ($template->modules as $module) {
            WorkspaceFeatureFlag::updateOrCreate(
                [
                    'workspace_id' => $workspace->id,
                    'feature_key'  => $module->module_key,
                ],
                [
                    'is_enabled'      => $module->is_enabled,
                    'override_reason' => 'template:' . $template->template_key,
                    'set_by'          => $user->id,
                ]
            );
        }
    }

    /**
     * Apply template roles to workspace.
     *
     * Preserves existing owner role if already created during registration.
     * Updates permissions from template but does not remove user-created roles.
     * Writes entity-level template provenance for every role touched.
     */
    private function applyRoles(BusinessTemplate $template, Workspace $workspace, User $user): void
    {
        foreach ($template->roles as $templateRole) {
            $existingRole = Role::where('workspace_id', $workspace->id)
                ->where('role_key', $templateRole->role_key)
                ->first();

            if ($existingRole) {
                // Merge template permissions into existing role
                $existingPerms = $existingRole->permissions ?? [];
                $templatePerms = $templateRole->permissions ?? [];
                $merged = array_values(array_unique(array_merge($existingPerms, $templatePerms)));

                $existingRole->update([
                    'name'            => $templateRole->name,
                    'description'     => $templateRole->description,
                    'permissions'     => $merged,
                    'hierarchy_level' => $templateRole->hierarchy_level,
                ]);

                // Write provenance binding for this role
                $this->writeTemplateProvenance(
                    $workspace->id,
                    'role',
                    $templateRole->role_key,
                    $existingRole->id,
                    $template->template_key,
                );
            } else {
                $newRole = Role::create([
                    'workspace_id'    => $workspace->id,
                    'name'            => $templateRole->name,
                    'role_key'        => $templateRole->role_key,
                    'description'     => $templateRole->description,
                    'hierarchy_level' => $templateRole->hierarchy_level,
                    'permissions'     => $templateRole->permissions ?? [],
                    'is_system'       => true,
                    'is_default'      => false,
                    'is_deletable'    => ! $templateRole->is_primary_owner_role,
                ]);

                // Write provenance binding for the new role
                $this->writeTemplateProvenance(
                    $workspace->id,
                    'role',
                    $templateRole->role_key,
                    $newRole->id,
                    $template->template_key,
                );
            }
        }

        // Ensure the workspace owner membership has the primary owner role
        $this->ensureOwnerHasPrimaryRole($workspace, $user);
    }

    /**
     * Write entity-level template provenance to provisioning_entity_bindings.
     *
     * Uses updateOrCreate to be idempotent — safe on repeated template applications.
     */
    private function writeTemplateProvenance(
        string $workspaceId,
        string $entityType,
        string $localKey,
        string $entityId,
        string $templateKey,
    ): void {
        ProvisioningEntityBinding::updateOrCreate(
            [
                'workspace_id' => $workspaceId,
                'entity_type'  => $entityType,
                'local_key'    => $localKey,
            ],
            [
                'entity_id'                => $entityId,
                'ownership_type'           => ProvisioningEntityBinding::OWNERSHIP_CREATED_BY_TEMPLATE,
                'last_provisioning_run_id' => null,
                'last_blueprint_id'        => null,
                'last_blueprint_version'   => 1,
                'metadata'                 => [
                    'source'       => 'template_application',
                    'template_key' => $templateKey,
                    'applied_at'   => now()->toIso8601String(),
                ],
            ],
        );
    }

    /**
     * Ensure the applying user's membership has the owner role assigned.
     */
    private function ensureOwnerHasPrimaryRole(Workspace $workspace, User $user): void
    {
        $membership = WorkspaceMembership::where('workspace_id', $workspace->id)
            ->where('user_id', $user->id)
            ->where('status', 'active')
            ->first();

        if (! $membership) {
            return;
        }

        $ownerRole = Role::where('workspace_id', $workspace->id)
            ->where('role_key', 'owner')
            ->first();

        if (! $ownerRole) {
            return;
        }

        // Upsert the membership role assignment
        MembershipRole::updateOrCreate(
            [
                'workspace_id'  => $workspace->id,
                'membership_id' => $membership->id,
                'role_id'       => $ownerRole->id,
            ],
            [
                'is_primary'  => true,
                'assigned_at' => now(),
            ]
        );
    }

    /**
     * Build a complete snapshot of the template for auditing.
     */
    private function buildSnapshot(BusinessTemplate $template): array
    {
        return [
            'template_key' => $template->template_key,
            'version'      => $template->version,
            'metadata'     => $template->metadata,
            'modules'      => $template->modules->map(fn ($m) => [
                'module_key'  => $m->module_key,
                'name'        => $m->name,
                'is_enabled'  => $m->is_enabled,
                'is_required' => $m->is_required,
            ])->toArray(),
            'roles' => $template->roles->map(fn ($r) => [
                'role_key'     => $r->role_key,
                'name'         => $r->name,
                'permissions'  => $r->permissions,
                'hierarchy_level' => $r->hierarchy_level,
            ])->toArray(),
            'workflows' => $template->workflows->map(fn ($w) => [
                'workflow_type' => $w->workflow_type,
                'workflow_key'  => $w->workflow_key,
                'name'          => $w->name,
                'config'        => $w->config,
            ])->toArray(),
            'custom_fields' => $template->customFields->map(fn ($f) => [
                'entity_type' => $f->entity_type,
                'field_key'   => $f->field_key,
                'label'       => $f->label,
                'field_type'  => $f->field_type,
                'options'     => $f->options,
            ])->toArray(),
        ];
    }
}
