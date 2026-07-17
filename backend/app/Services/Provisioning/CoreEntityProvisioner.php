<?php

namespace App\Services\Provisioning;

use App\Exceptions\ProvisioningException;
use App\Models\Branch;
use App\Models\Department;
use App\Models\MembershipRole;
use App\Models\ProvisioningEntityBinding;
use App\Models\Role;
use App\Models\Team;
use App\Models\WorkspaceConfiguration;
use App\Models\WorkspaceFeatureFlag;
use App\Services\PermissionCatalog;
use Illuminate\Support\Facades\Log;

/**
 * Core Entity Provisioner — creates foundational workspace entities from a Blueprint plan.
 *
 * Provisions in dependency order:
 *   1. Locations (branches)
 *   2. Departments (parent-safe order)
 *   3. Teams
 *   4. Roles + permissions
 *   5. Module feature flags
 *   6. WorkspaceConfiguration
 *
 * All operations are designed to run inside a single DB transaction.
 * Does NOT create warehouses, pipelines, approvals, commissions, or financial entities.
 */
class CoreEntityProvisioner
{
    private string $workspaceId;
    private string $runId;
    private string $blueprintId;
    private int    $blueprintVersion;

    /** @var array<string,string> Blueprint local key → DB entity ID */
    private array $bindings = [];

    /** @var array Tracking for rollback */
    private array $created = [];
    private array $updated = [];
    private array $reused  = [];
    private array $warnings = [];

    /** @var array Before-state for rollback */
    private array $rolePermissionsBefore = [];
    private array $featureFlagsBefore = [];
    /** @var array<string, array> Before-state snapshots of adopted entities keyed by "type:localKey" */
    private array $adoptedEntitySnapshots = [];

    /**
     * Test-only failure injection hook.
     *
     * When set, this callback is invoked after locations are provisioned
     * but before departments, simulating a mid-run crash.
     *
     * SAFETY: This is a private static property with no public setter.
     * Only test scripts can set it via Closure binding or reflection.
     * It is inaccessible through API requests, controllers, or service container.
     *
     * @internal Test infrastructure only — never call from production code.
     * @var \Closure|null
     */
    private static ?\Closure $testFailureHook = null;

    /**
     * Provision core entities from a validated plan.
     *
     * @param  string  $workspaceId
     * @param  string  $runId
     * @param  array   $plan  The operations section from ProvisioningPlanBuilder
     * @param  string  $blueprintId
     * @param  int     $blueprintVersion
     * @return array   Structured result
     * @throws ProvisioningException on conflicts or validation failures
     */
    public function provision(
        string $workspaceId,
        string $runId,
        array  $plan,
        string $blueprintId,
        int    $blueprintVersion,
    ): array {
        $this->workspaceId      = $workspaceId;
        $this->runId            = $runId;
        $this->blueprintId      = $blueprintId;
        $this->blueprintVersion = $blueprintVersion;

        $operations = $plan['operations'] ?? $plan;

        // Load existing bindings for this workspace
        $this->loadExistingBindings();

        // 1. Locations
        $this->provisionLocations($operations['locations'] ?? []);

        // ── Test-only failure injection point ──
        if (self::$testFailureHook !== null) {
            (self::$testFailureHook)($this);
        }

        // 2. Departments (parent-safe order)
        $this->provisionDepartments($operations['departments'] ?? []);

        // 3. Teams
        $this->provisionTeams($operations['teams'] ?? []);

        // 4. Roles + permissions
        $this->provisionRoles($operations['roles'] ?? []);

        // 5. Module feature flags
        $this->provisionModuleFlags($operations['modules'] ?? []);

        // 6. WorkspaceConfiguration
        $this->persistWorkspaceConfiguration($operations, $plan);

        return [
            'created'  => $this->created,
            'updated'  => $this->updated,
            'reused'   => $this->reused,
            'warnings' => $this->warnings,
            'rollback_changes' => [
                'core_entities' => [
                    'created'          => $this->created,
                    'updated'          => $this->updated,
                    'reused'           => $this->reused,
                    'bindings_created' => $this->getCreatedBindingKeys(),
                ],
                'role_permissions_before'  => $this->rolePermissionsBefore,
                'feature_flags_before'     => $this->featureFlagsBefore,
                'adopted_entity_snapshots' => $this->adoptedEntitySnapshots,
            ],
        ];
    }

    // ═══════════════════════════════════════════════════════════════
    //  1. Locations (branches)
    // ═══════════════════════════════════════════════════════════════

    private function provisionLocations(array $locations): void
    {
        foreach ($locations as $loc) {
            $localKey = $loc['key'];

            // Check for existing binding
            $binding = $this->findBinding('location', $localKey);

            if ($binding) {
                // Update existing bound entity
                $entity = Branch::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'      => $loc['name'],
                        'location'  => $loc['country'] ?? null,
                        'is_active' => true,
                        'metadata'  => $this->buildProvenanceMetadata($localKey),
                    ]);
                    $this->updated['locations'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                // Bound entity deleted externally — refuse to silently recreate
                $this->throwMissingBoundEntity('location', $localKey, $binding->entity_id);
            }

            // Adopt existing entity by name — requires entity-level template provenance
            $existingByName = Branch::where('workspace_id', $this->workspaceId)
                ->where('name', $loc['name'])
                ->first();

            if ($existingByName) {
                if (!ProvisioningEntityBinding::hasTemplateProvenance($this->workspaceId, 'location', $existingByName->id)) {
                    throw new ProvisioningException(
                        "Provisioning conflict: Location '{$localKey}' matches existing branch '{$existingByName->name}' but has no template provenance. Cannot adopt unmanaged entity.",
                        'provisioning_conflict',
                        409,
                        null,
                        ['entity_type' => 'location', 'local_key' => $localKey, 'existing_entity_id' => $existingByName->id],
                    );
                }

                $this->adoptedEntitySnapshots["location:{$localKey}"] = [
                    'entity_id' => $existingByName->id,
                    'name'      => $existingByName->name,
                    'location'  => $existingByName->location,
                    'is_active' => $existingByName->is_active,
                    'metadata'  => $existingByName->metadata,
                ];
                $existingByName->update([
                    'name'      => $loc['name'],
                    'location'  => $loc['country'] ?? null,
                    'is_active' => true,
                    'metadata'  => $this->buildProvenanceMetadata($localKey),
                ]);
                $this->createBinding('location', $localKey, $existingByName->id, ProvisioningEntityBinding::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY);
                $this->reused['locations'][] = ['key' => $localKey, 'id' => $existingByName->id, 'adopted' => true];
                $this->warnings[] = "Location '{$localKey}': adopted template branch '{$existingByName->name}'.";
                continue;
            }

            // Check for name conflict with unmanaged entity
            $this->detectNameConflict('location', $localKey, $loc['name'], $existingByName);

            // Create new location
            $entity = Branch::create([
                'workspace_id' => $this->workspaceId,
                'name'         => $loc['name'],
                'location'     => $loc['country'] ?? null,
                'is_active'    => true,
                'metadata'     => $this->buildProvenanceMetadata($localKey),
            ]);

            $this->createBinding('location', $localKey, $entity->id);
            $this->created['locations'][] = ['key' => $localKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  2. Departments (parent-safe order)
    // ═══════════════════════════════════════════════════════════════

    private function provisionDepartments(array $departments): void
    {
        // Sort: parents before children
        $sorted = $this->sortByParent($departments);

        foreach ($sorted as $idx => $dept) {
            $localKey = $dept['key'];

            // Resolve parent
            $parentId = null;
            if (!empty($dept['parent_key'])) {
                $parentBinding = $this->findBinding('department', $dept['parent_key']);
                if ($parentBinding) {
                    $parentId = $parentBinding->entity_id;
                } else {
                    $this->warnings[] = "Department '{$localKey}': parent '{$dept['parent_key']}' not found. Creating without parent.";
                }
            }

            $binding = $this->findBinding('department', $localKey);

            if ($binding) {
                $entity = Department::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'                 => $dept['name'],
                        'description'          => $dept['description'] ?? null,
                        'department_key'       => $localKey,
                        'parent_department_id' => $parentId,
                        'is_active'            => true,
                        'sort_order'           => $idx,
                    ]);
                    $this->updated['departments'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                // Bound entity deleted externally — refuse to silently recreate
                $this->throwMissingBoundEntity('department', $localKey, $binding->entity_id);
            }

            // ── Adopt existing entity by department_key — requires template provenance ──
            $existingByKey = Department::where('workspace_id', $this->workspaceId)
                ->where('department_key', $localKey)
                ->first();

            if ($existingByKey) {
                // Require exact entity-level template provenance
                if (!ProvisioningEntityBinding::hasTemplateProvenance($this->workspaceId, 'department', $existingByKey->id)) {
                    throw new ProvisioningException(
                        "Provisioning conflict: Department '{$localKey}' exists but has no template provenance. Cannot adopt unmanaged entity.",
                        'provisioning_conflict',
                        409,
                        null,
                        ['entity_type' => 'department', 'local_key' => $localKey, 'existing_entity_id' => $existingByKey->id],
                    );
                }

                $this->adoptedEntitySnapshots["department:{$localKey}"] = [
                    'entity_id'            => $existingByKey->id,
                    'name'                 => $existingByKey->name,
                    'description'          => $existingByKey->description,
                    'parent_department_id' => $existingByKey->parent_department_id,
                    'is_active'            => $existingByKey->is_active,
                    'sort_order'           => $existingByKey->sort_order,
                ];
                $existingByKey->update([
                    'name'                 => $dept['name'],
                    'description'          => $dept['description'] ?? null,
                    'parent_department_id' => $parentId,
                    'is_active'            => true,
                    'sort_order'           => $idx,
                ]);
                $this->createBinding('department', $localKey, $existingByKey->id, ProvisioningEntityBinding::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY);
                $this->reused['departments'][] = ['key' => $localKey, 'id' => $existingByKey->id, 'adopted' => true];
                $this->warnings[] = "Department '{$localKey}': adopted template entity '{$existingByKey->name}'.";
                continue;
            }

            // Check for name conflict (different key, same name)
            $this->detectNameConflict('department', $localKey, $dept['name'],
                Department::where('workspace_id', $this->workspaceId)->where('name', $dept['name'])->first()
            );

            $entity = Department::create([
                'workspace_id'         => $this->workspaceId,
                'department_key'       => $localKey,
                'name'                 => $dept['name'],
                'description'          => $dept['description'] ?? null,
                'parent_department_id' => $parentId,
                'is_active'            => true,
                'sort_order'           => $idx,
            ]);

            $this->createBinding('department', $localKey, $entity->id);
            $this->created['departments'][] = ['key' => $localKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  3. Teams
    // ═══════════════════════════════════════════════════════════════

    private function provisionTeams(array $teams): void
    {
        foreach ($teams as $idx => $team) {
            $localKey = $team['key'];

            // Resolve department
            $departmentId = null;
            if (!empty($team['department_key'])) {
                $deptBinding = $this->findBinding('department', $team['department_key']);
                if ($deptBinding) {
                    $departmentId = $deptBinding->entity_id;
                } else {
                    $this->warnings[] = "Team '{$localKey}': department '{$team['department_key']}' not found.";
                }
            }

            $binding = $this->findBinding('team', $localKey);

            if ($binding) {
                $entity = Team::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    $entity->update([
                        'name'          => $team['name'],
                        'description'   => $team['purpose'] ?? $team['description'] ?? null,
                        'team_key'      => $localKey,
                        'department_id' => $departmentId,
                        'is_active'     => true,
                        'sort_order'    => $idx,
                    ]);
                    $this->updated['teams'][] = ['key' => $localKey, 'id' => $entity->id];
                    $this->updateBinding($binding);
                    continue;
                }
                // Bound entity deleted externally — refuse to silently recreate
                $this->throwMissingBoundEntity('team', $localKey, $binding->entity_id);
            }

            // ── Adopt existing entity by team_key — requires template provenance ──
            $existingByKey = Team::where('workspace_id', $this->workspaceId)
                ->where('team_key', $localKey)
                ->first();

            if ($existingByKey) {
                if (!ProvisioningEntityBinding::hasTemplateProvenance($this->workspaceId, 'team', $existingByKey->id)) {
                    throw new ProvisioningException(
                        "Provisioning conflict: Team '{$localKey}' exists but has no template provenance. Cannot adopt unmanaged entity.",
                        'provisioning_conflict',
                        409,
                        null,
                        ['entity_type' => 'team', 'local_key' => $localKey, 'existing_entity_id' => $existingByKey->id],
                    );
                }

                $this->adoptedEntitySnapshots["team:{$localKey}"] = [
                    'entity_id'     => $existingByKey->id,
                    'name'          => $existingByKey->name,
                    'description'   => $existingByKey->description,
                    'department_id' => $existingByKey->department_id,
                    'is_active'     => $existingByKey->is_active,
                    'sort_order'    => $existingByKey->sort_order,
                ];
                $existingByKey->update([
                    'name'          => $team['name'],
                    'description'   => $team['purpose'] ?? $team['description'] ?? null,
                    'department_id' => $departmentId,
                    'is_active'     => true,
                    'sort_order'    => $idx,
                ]);
                $this->createBinding('team', $localKey, $existingByKey->id, ProvisioningEntityBinding::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY);
                $this->reused['teams'][] = ['key' => $localKey, 'id' => $existingByKey->id, 'adopted' => true];
                $this->warnings[] = "Team '{$localKey}': adopted template entity '{$existingByKey->name}'.";
                continue;
            }

            // Check for name conflict (different key, same name)
            $this->detectNameConflict('team', $localKey, $team['name'],
                Team::where('workspace_id', $this->workspaceId)->where('name', $team['name'])->first()
            );

            $entity = Team::create([
                'workspace_id'  => $this->workspaceId,
                'team_key'      => $localKey,
                'name'          => $team['name'],
                'description'   => $team['purpose'] ?? $team['description'] ?? null,
                'department_id' => $departmentId,
                'is_active'     => true,
                'sort_order'    => $idx,
            ]);

            $this->createBinding('team', $localKey, $entity->id);
            $this->created['teams'][] = ['key' => $localKey, 'id' => $entity->id];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  4. Roles + Permissions
    // ═══════════════════════════════════════════════════════════════

    private function provisionRoles(array $roles): void
    {
        $catalogKeys = PermissionCatalog::allKeys();

        foreach ($roles as $idx => $role) {
            $localKey    = $role['key'];
            $permissions = $role['permissions'] ?? [];

            // Exact permission enforcement — reject unknown keys immediately
            $invalid = array_values(array_diff($permissions, $catalogKeys));
            if (!empty($invalid)) {
                throw new ProvisioningException(
                    "Role '{$localKey}' contains " . count($invalid) . " unregistered permission key(s): " .
                    implode(', ', array_slice($invalid, 0, 10)) .
                    (count($invalid) > 10 ? '…' : '') .
                    '. All permission keys must exist in PermissionCatalog.',
                    'invalid_permissions',
                    422,
                    null,
                    [
                        'entity_type'      => 'role',
                        'local_key'        => $localKey,
                        'invalid_keys'     => $invalid,
                        'invalid_count'    => count($invalid),
                    ],
                );
            }

            $validPermissions = array_values($permissions);

            $binding = $this->findBinding('role', $localKey);

            if ($binding) {
                $entity = Role::where('workspace_id', $this->workspaceId)
                    ->where('id', $binding->entity_id)
                    ->first();

                if ($entity) {
                    // Capture full entity snapshot for rollback (not just permissions)
                    $this->rolePermissionsBefore[$localKey] = $entity->permissions ?? [];
                    $this->adoptedEntitySnapshots["role_update:{$localKey}"] = [
                        'entity_id'       => $entity->id,
                        'name'            => $entity->name,
                        'description'     => $entity->description,
                        'permissions'     => $entity->permissions ?? [],
                        'hierarchy_level' => $entity->hierarchy_level,
                        'is_active'       => $entity->is_active,
                        'sort_order'      => $entity->sort_order,
                    ];

                    $entity->update([
                        'name'            => $role['name'],
                        'description'     => $role['description'] ?? null,
                        'role_key'        => $localKey,
                        'permissions'     => $validPermissions,
                        'hierarchy_level' => $this->roleHierarchy($role),
                        'is_active'       => true,
                        'sort_order'      => $idx,
                    ]);
                    $this->updated['roles'][] = ['key' => $localKey, 'id' => $entity->id, 'permission_count' => count($validPermissions)];
                    $this->updateBinding($binding);
                    continue;
                }
                // Bound entity deleted externally — refuse to silently recreate
                $this->throwMissingBoundEntity('role', $localKey, $binding->entity_id);
            }

            // ── Adopt existing entity by role_key — requires template provenance ──
            $existingByKey = Role::where('workspace_id', $this->workspaceId)
                ->where('role_key', $localKey)
                ->first();

            if ($existingByKey) {
                if (!ProvisioningEntityBinding::hasTemplateProvenance($this->workspaceId, 'role', $existingByKey->id)) {
                    // ── Canonical workspace-owner binding ────────────────────
                    // The registration bootstrap creates the Owner role with
                    // is_system=true, hierarchy_level=0, is_deletable=false but
                    // no ProvisioningEntityBinding (it predates Blueprint).
                    //
                    // We verify canonical identity through authoritative evidence
                    // on BOTH sides:
                    //   Blueprint:  is_primary_owner = true
                    //   Runtime:    is_system + hierarchy_level=0 + is_deletable=false
                    //               + active primary MembershipRole assignment
                    //
                    // This does NOT broaden unmanaged-entity adoption in general.
                    // Only the verified canonical workspace-owner receives this path.
                    if ($this->isCanonicalOwnerBinding($role, $existingByKey)) {
                        Log::info("Canonical owner binding: Blueprint role '{$localKey}' → existing system role {$existingByKey->id}");
                    } else {
                        throw new ProvisioningException(
                            "Provisioning conflict: Role '{$localKey}' exists but has no template provenance. Cannot adopt unmanaged entity.",
                            'provisioning_conflict',
                            409,
                            null,
                            ['entity_type' => 'role', 'local_key' => $localKey, 'existing_entity_id' => $existingByKey->id],
                        );
                    }
                }

                $this->rolePermissionsBefore[$localKey] = $existingByKey->permissions ?? [];
                $this->adoptedEntitySnapshots["role:{$localKey}"] = [
                    'entity_id'       => $existingByKey->id,
                    'name'            => $existingByKey->name,
                    'description'     => $existingByKey->description,
                    'permissions'     => $existingByKey->permissions ?? [],
                    'hierarchy_level' => $existingByKey->hierarchy_level,
                    'is_active'       => $existingByKey->is_active,
                    'sort_order'      => $existingByKey->sort_order,
                ];

                $existingByKey->update([
                    'name'            => $role['name'],
                    'description'     => $role['description'] ?? null,
                    'permissions'     => $validPermissions,
                    'hierarchy_level' => $this->roleHierarchy($role),
                    'is_active'       => true,
                    'sort_order'      => $idx,
                ]);

                $this->createBinding('role', $localKey, $existingByKey->id, ProvisioningEntityBinding::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY);
                $this->reused['roles'][] = ['key' => $localKey, 'id' => $existingByKey->id, 'permission_count' => count($validPermissions), 'adopted' => true];
                $this->warnings[] = "Role '{$localKey}': adopted template entity '{$existingByKey->name}' (id: {$existingByKey->id}).";
                continue;
            }

            // Check name conflict (different key, same name)
            $this->detectNameConflict('role', $localKey, $role['name'],
                Role::where('workspace_id', $this->workspaceId)->where('name', $role['name'])->first()
            );

            $entity = Role::create([
                'workspace_id'    => $this->workspaceId,
                'name'            => $role['name'],
                'role_key'        => $localKey,
                'description'     => $role['description'] ?? null,
                'permissions'     => $validPermissions,
                'hierarchy_level' => $this->roleHierarchy($role),
                'is_system'       => true,
                'is_default'      => false,
                'is_deletable'    => !($role['is_primary_owner'] ?? false),
                'is_active'       => true,
                'sort_order'      => $idx,
            ]);

            $this->createBinding('role', $localKey, $entity->id);
            $this->created['roles'][] = ['key' => $localKey, 'id' => $entity->id, 'permission_count' => count($validPermissions)];
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  5. Module Feature Flags
    // ═══════════════════════════════════════════════════════════════

    private function provisionModuleFlags(array $modules): void
    {
        foreach ($modules as $module) {
            $key     = $module['key'];
            $enabled = $module['enabled'] ?? false;

            // Capture current state for rollback
            $existing = WorkspaceFeatureFlag::where('workspace_id', $this->workspaceId)
                ->where('feature_key', $key)
                ->first();

            $this->featureFlagsBefore[$key] = $existing ? [
                'feature_key' => $existing->feature_key,
                'is_enabled'  => $existing->is_enabled,
            ] : null;

            WorkspaceFeatureFlag::updateOrCreate(
                [
                    'workspace_id' => $this->workspaceId,
                    'feature_key'  => $key,
                ],
                [
                    'is_enabled'      => $enabled,
                    'override_reason' => 'blueprint_provisioning',
                ]
            );
        }
    }

    // ═══════════════════════════════════════════════════════════════
    //  6. WorkspaceConfiguration
    // ═══════════════════════════════════════════════════════════════

    private function persistWorkspaceConfiguration(array $operations, array $plan): void
    {
        $modules     = $operations['modules'] ?? [];
        $enabledKeys = array_column(
            array_filter($modules, fn($m) => $m['enabled'] ?? false),
            'key'
        );

        // Build role configs summary
        $roleConfigs = [];
        foreach ($operations['roles'] ?? [] as $r) {
            $roleConfigs[$r['key']] = [
                'name'             => $r['name'],
                'description'      => $r['description'] ?? '',
                'department_key'   => $r['department_key'] ?? null,
                'permission_count' => $r['permission_count'] ?? count($r['permissions'] ?? []),
            ];
        }

        // Build workflow summary
        $workflows = [];
        foreach ($operations['approval_workflows'] ?? [] as $wf) {
            $workflows[] = [
                'key'         => $wf['key'],
                'name'        => $wf['name'],
                'entity_type' => $wf['entity_type'],
                'step_count'  => count($wf['steps'] ?? []),
                'active'      => empty($wf['requires_configuration']),
            ];
        }

        $existing = WorkspaceConfiguration::where('workspace_id', $this->workspaceId)->first();

        $configData = [
            'enabled_modules'     => $enabledKeys,
            'role_configs'        => $roleConfigs,
            'pages'               => $existing->pages ?? [],  // Preserve manually set pages
            'workflows'           => $workflows,
            'automations'         => $existing->automations ?? [],  // Preserve
            'provisioning_run_id' => $this->runId,
        ];

        WorkspaceConfiguration::updateOrCreate(
            ['workspace_id' => $this->workspaceId],
            $configData,
        );
    }

    // ═══════════════════════════════════════════════════════════════
    //  Private Helpers
    // ═══════════════════════════════════════════════════════════════

    private function loadExistingBindings(): void
    {
        $bindings = ProvisioningEntityBinding::where('workspace_id', $this->workspaceId)->get();
        foreach ($bindings as $b) {
            $this->bindings["{$b->entity_type}:{$b->local_key}"] = $b;
        }
    }

    private function findBinding(string $type, string $localKey): ?ProvisioningEntityBinding
    {
        return $this->bindings["{$type}:{$localKey}"] ?? null;
    }

    private function createBinding(
        string $type,
        string $localKey,
        string $entityId,
        string $ownershipType = ProvisioningEntityBinding::OWNERSHIP_CREATED_BY_PROVISIONING,
    ): void {
        // For adoption: the entity may already have a binding under a different local_key.
        // The unique constraint on (workspace_id, entity_type, entity_id) prevents duplicates,
        // so we must update the existing binding's local_key rather than creating a new one.
        if ($ownershipType === ProvisioningEntityBinding::OWNERSHIP_ADOPTED_TEMPLATE_ENTITY) {
            $existingByEntity = ProvisioningEntityBinding::where('workspace_id', $this->workspaceId)
                ->where('entity_type', $type)
                ->where('entity_id', $entityId)
                ->first();

            if ($existingByEntity) {
                $existingByEntity->update([
                    'local_key'                => $localKey,
                    'ownership_type'           => $ownershipType,
                    'last_provisioning_run_id' => $this->runId,
                    'last_blueprint_id'        => $this->blueprintId,
                    'last_blueprint_version'   => $this->blueprintVersion,
                ]);
                $this->bindings["{$type}:{$localKey}"] = $existingByEntity;
                return;
            }
        }

        $binding = ProvisioningEntityBinding::updateOrCreate(
            [
                'workspace_id' => $this->workspaceId,
                'entity_type'  => $type,
                'local_key'    => $localKey,
            ],
            [
                'entity_id'                => $entityId,
                'ownership_type'           => $ownershipType,
                'last_provisioning_run_id' => $this->runId,
                'last_blueprint_id'        => $this->blueprintId,
                'last_blueprint_version'   => $this->blueprintVersion,
            ],
        );
        $this->bindings["{$type}:{$localKey}"] = $binding;
    }

    private function updateBinding(ProvisioningEntityBinding $binding): void
    {
        $binding->update([
            'last_provisioning_run_id'  => $this->runId,
            'last_blueprint_id'         => $this->blueprintId,
            'last_blueprint_version'    => $this->blueprintVersion,
        ]);
    }

    private function getCreatedBindingKeys(): array
    {
        $keys = [];
        foreach (['locations', 'departments', 'teams', 'roles'] as $type) {
            foreach ($this->created[$type] ?? [] as $entry) {
                $keys[] = ['entity_type' => rtrim($type, 's'), 'local_key' => $entry['key']];
            }
        }
        // Map location → location (not locations)
        foreach ($keys as &$k) {
            if ($k['entity_type'] === 'location') $k['entity_type'] = 'location';
        }
        return $keys;
    }

    /**
     * Throw when a binding exists but the underlying entity was deleted externally.
     *
     * @throws ProvisioningException always (409 missing_bound_entity)
     */
    private function throwMissingBoundEntity(string $entityType, string $localKey, string $entityId): void
    {
        throw new ProvisioningException(
            "Provisioning conflict: {$entityType} '{$localKey}' is bound to entity {$entityId}, but that entity no longer exists. " .
            "Manual intervention required — delete the stale binding or restore the entity.",
            'missing_bound_entity',
            409,
            null,
            [
                'entity_type' => $entityType,
                'local_key'   => $localKey,
                'entity_id'   => $entityId,
            ],
        );
    }

    /**
     * Detect name conflict with an unmanaged entity.
     *
     * @throws ProvisioningException with structured context
     */
    private function detectNameConflict(string $entityType, string $localKey, string $name, $existing): void
    {
        if (!$existing) return;

        // Check if this existing entity is already bound (managed by provisioning)
        $boundToThis = ProvisioningEntityBinding::where('workspace_id', $this->workspaceId)
            ->where('entity_type', $entityType)
            ->where('entity_id', $existing->id)
            ->first();

        if ($boundToThis) {
            // Already managed — safe to update
            return;
        }

        // Unmanaged entity with conflicting name → 409
        throw new ProvisioningException(
            "Provisioning conflict: An unmanaged {$entityType} named '{$name}' already exists. " .
            "Cannot create Blueprint {$entityType} '{$localKey}' without overwriting it.",
            'provisioning_conflict',
            409,
            null,
            [
                'entity_type'       => $entityType,
                'local_key'         => $localKey,
                'conflicting_name'  => $name,
                'existing_entity_id' => $existing->id,
            ],
        );
    }

    /**
     * Sort departments so parents come before children.
     */
    private function sortByParent(array $departments): array
    {
        $byKey    = [];
        $sorted   = [];
        $resolved = [];

        foreach ($departments as $d) {
            $byKey[$d['key']] = $d;
        }

        $resolve = function (string $key) use (&$resolve, &$byKey, &$sorted, &$resolved) {
            if (isset($resolved[$key])) return;
            $resolved[$key] = true;
            $dept = $byKey[$key] ?? null;
            if (!$dept) return;
            if (!empty($dept['parent_key']) && isset($byKey[$dept['parent_key']])) {
                $resolve($dept['parent_key']);
            }
            $sorted[] = $dept;
        };

        foreach ($departments as $d) {
            $resolve($d['key']);
        }

        return $sorted;
    }

    /**
     * Determine role hierarchy level.
     *
     * No role-key or role-name inference — only:
     *   1. is_primary_owner → level 0
     *   2. Explicit Blueprint-supplied hierarchy_level
     *   3. Neutral default: 5
     */
    private function roleHierarchy(array $role): int
    {
        if ($role['is_primary_owner'] ?? false) {
            return 0;
        }

        if (isset($role['hierarchy_level']) && is_int($role['hierarchy_level'])) {
            return $role['hierarchy_level'];
        }

        return 5;
    }

    /**
     * Determine if a Blueprint role and an existing runtime role represent the
     * same canonical workspace-owner identity.
     *
     * This is NOT a generic adoption path. It exists solely because the
     * registration bootstrap creates the Owner role before Blueprint provisioning
     * exists, so it has no ProvisioningEntityBinding.
     *
     * Verification requires authoritative evidence on BOTH sides:
     *
     *   Blueprint side:
     *     - is_primary_owner = true
     *
     *   Runtime side (ALL must be true):
     *     - is_system = true
     *     - hierarchy_level = 0
     *     - is_deletable = false
     *     - At least one active MembershipRole with is_primary = true
     *       (proves the role is actively used as the workspace-owner assignment)
     *
     * Display names (Owner, مالك, etc.) are explicitly NOT checked.
     * role_key matching alone is insufficient — the structural invariants above
     * must hold.
     *
     * @param  array  $blueprintRole  The Blueprint role definition
     * @param  Role   $existingRole   The runtime role entity
     * @return bool
     */
    private function isCanonicalOwnerBinding(array $blueprintRole, Role $existingRole): bool
    {
        // Blueprint side: must be the primary owner role
        if (!($blueprintRole['is_primary_owner'] ?? false)) {
            return false;
        }

        // Runtime side: structural invariants from seedOwnerRole()
        if (!$existingRole->is_system) {
            return false;
        }

        if ((int) $existingRole->hierarchy_level !== 0) {
            return false;
        }

        if ($existingRole->is_deletable) {
            return false;
        }

        // Runtime side: must have an active primary MembershipRole assignment
        // This proves the role is genuinely functioning as the workspace owner,
        // not just a stale or orphaned system role.
        $hasPrimaryAssignment = MembershipRole::where('workspace_id', $this->workspaceId)
            ->where('role_id', $existingRole->id)
            ->where('is_primary', true)
            ->exists();

        if (!$hasPrimaryAssignment) {
            return false;
        }

        return true;
    }

    /**
     * Build provenance metadata JSONB payload for created/adopted entities.
     */
    private function buildProvenanceMetadata(string $localKey): array
    {
        return [
            'provisioning_run_id'  => $this->runId,
            'blueprint_id'         => $this->blueprintId,
            'blueprint_version'    => $this->blueprintVersion,
            'local_key'            => $localKey,
            'provisioned_at'       => now()->toIso8601String(),
        ];
    }

    // NOTE: workspace-level hasTemplateProvenance() removed.
    // Adoption now requires exact entity-level provenance via
    // ProvisioningEntityBinding::hasTemplateProvenance().
}
